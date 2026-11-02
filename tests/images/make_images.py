#!/usr/bin/env python3
# Writes the PNGs png_test decodes, each with the pixels it should come out
# as: premultiplied ARGB, little-endian, the way the client draws them. An
# empty .argb means the PNG has to be refused.
# Every color type, every filter and all three kinds of deflate block are in
# here somewhere. Run it from this directory.
import random, struct, zlib

def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else (b if pb <= pc else c)

def filtered(rows, bpp):
    out, prev = b"", bytes(len(rows[0]))
    for i, row in enumerate(rows):
        f = i % 5
        enc = bytearray()
        for x, v in enumerate(row):
            a = row[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            enc.append((v - [0, a, b, (a + b) // 2, paeth(a, b, c)][f]) & 255)
        out += bytes([f]) + enc
        prev = row
    return out

def premul(c, a):
    t = c * a + 128
    return (t + (t >> 8)) >> 8

def write(name, w, h, ctype, depth, rows, argb, strategy, extra=b""):
    bpp = max(1, {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype] * depth // 8)
    raw = filtered(rows, bpp)
    if strategy == "stored":
        z = zlib.compressobj(0)
    elif strategy == "fixed":
        z = zlib.compressobj(9, zlib.DEFLATED, 15, 9, zlib.Z_FIXED)
    else:
        z = zlib.compressobj(9)
    data = z.compress(raw) + z.flush()
    ihdr = struct.pack(">IIBBBBB", w, h, depth, ctype, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + extra
    half = len(data) // 2                   # two IDATs, to check they're joined
    png += chunk(b"IDAT", data[:half]) + chunk(b"IDAT", data[half:]) + chunk(b"IEND", b"")
    open(name + ".png", "wb").write(png)
    out = b"".join(struct.pack("<I", (a << 24) | (premul(r, a) << 16) | (premul(g, a) << 8) | premul(b, a))
                   for (a, r, g, b) in argb)
    open(name + ".argb", "wb").write(out)

rnd = random.Random(7)
W, H = 13, 7

# RGB, 8-bit, dynamic codes. Mostly smooth so the filters matter.
px = [[(255, (x * 19) % 256, (y * 37) % 256, (x * y * 5) % 256) for x in range(W)] for y in range(H)]
rows = [bytes(v for p in r for v in p[1:]) for r in px]
write("rgb8", W, H, 2, 8, rows, [p for r in px for p in r], "dynamic")

# RGBA, 8-bit, fixed codes.
px = [[(rnd.randrange(256), rnd.randrange(256), rnd.randrange(256), rnd.randrange(256)) for x in range(W)] for y in range(H)]
rows = [bytes(v for (a, r_, g, b) in r for v in (r_, g, b, a)) for r in px]
write("rgba8", W, H, 6, 8, rows, [p for r in px for p in r], "fixed")

# Gray with alpha, 16-bit, stored: the decoder keeps each sample's high byte.
px = [[(rnd.randrange(65536), rnd.randrange(65536)) for x in range(W)] for y in range(H)]
rows = [b"".join(struct.pack(">HH", g, a) for (g, a) in r) for r in px]
write("ga16", W, H, 4, 16, rows, [(a >> 8, g >> 8, g >> 8, g >> 8) for r in px for (g, a) in r], "stored")

# Gray, 1-bit.
px = [[rnd.randrange(2) for x in range(W)] for y in range(H)]
rows = []
for r in px:
    bits = "".join(str(v) for v in r).ljust(16, "0")
    rows.append(int(bits, 2).to_bytes(2, "big"))
write("gray1", W, H, 0, 1, rows, [(255, v * 255, v * 255, v * 255) for r in px for v in r], "dynamic")

# Palette, 4-bit, with some palette alpha.
pal = [(rnd.randrange(256), rnd.randrange(256), rnd.randrange(256)) for i in range(16)]
alpha = [rnd.randrange(256) for i in range(5)]
px = [[rnd.randrange(16) for x in range(W)] for y in range(H)]
rows = []
for r in px:
    nib = r + [0] * (W % 2)
    rows.append(bytes((nib[i] << 4) | nib[i + 1] for i in range(0, len(nib), 2)))
extra = chunk(b"PLTE", bytes(v for p in pal for v in p)) + chunk(b"tRNS", bytes(alpha))
argb = [((alpha[i] if i < len(alpha) else 255),) + pal[i] for r in px for i in r]
write("pal4", W, H, 3, 4, rows, argb, "dynamic", extra)

# A 4x4 shrunk to 2x2: each output pixel is the average of a 2x2 box.
px = [[(rnd.randrange(256), rnd.randrange(256), rnd.randrange(256), rnd.randrange(256)) for x in range(4)] for y in range(4)]
rows = [bytes(v for (a, r_, g, b) in r for v in (r_, g, b, a)) for r in px]
write("shrink", 4, 4, 6, 8, rows, [], "dynamic")
boxes = []
for oy in range(2):
    for ox in range(2):
        cells = [px[oy * 2 + dy][ox * 2 + dx] for dy in range(2) for dx in range(2)]
        sums = [sum(c[0] for c in cells)] + [sum(premul(c[i], c[0]) for c in cells) for i in (1, 2, 3)]
        a, r_, g, b = [(s + 2) // 4 for s in sums]
        boxes.append(struct.pack("<I", (a << 24) | (r_ << 16) | (g << 8) | b))
open("shrink.argb", "wb").write(b"".join(boxes))

# A second IHDR making the same rows into gray three times as wide. The
# server only checks the first, so the client has to refuse it rather than
# draw the picture at the second's shape.
px = [[(255, x * 9, y * 9, 0) for x in range(W)] for y in range(H)]
rows = [bytes(v for p in r for v in p[1:]) for r in px]
lie = chunk(b"IHDR", struct.pack(">IIBBBBB", W * 3, H, 8, 0, 0, 0, 0))
write("two_ihdr", W, H, 2, 8, rows, [], "dynamic", lie)
