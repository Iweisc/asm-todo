; Anti-aliased text.
;
; Glyphs from font.asm are flattened into line segments, and a pixel's
; coverage is how much of it a pen of the style's width covers along them.
; Where strokes meet the pen is round, and a stroke end that touches nothing
; is cut flat. Each glyph is rasterized once per style and per quarter-pixel
; offset, on first use, then blended from the cache. shapes.asm uses the
; same distance trick for circles, rounded boxes and icon strokes.
;
; Text color and style travel together as an "ink": color | style << 24.

%define ST_SMALL        0               ; 12px, IDs and metadata
%define ST_BODY         1               ; 13.5px
%define ST_MEDIUM       2               ; 13.5px, heavier
%define ST_TITLE        3               ; 20px
%define ST_LARGE        4               ; 26px
%define STYLE_COUNT     5
%define INK(color, style) ((style) << 24 | (color))

%define BASE_PEN        90              ; the pen the glyph spacing was drawn for, in font units
%define PHASES          4               ; subpixel offsets, quarter pixels apart
%define SEG_MAX         256
%define SEG_AX          0
%define SEG_AY          4
%define SEG_DX          8
%define SEG_DY          12
%define SEG_INV         16              ; 1 / squared length, 0 for a dot
%define SEG_FLAGS       20
%define SEG_NAX         24              ; the flat cut at the start: unit normal into the stroke,
%define SEG_NAY         28
%define SEG_OFFA        32              ; and how far past the start it is, plus half a pixel
%define SEG_NBX         36              ; the same at the end
%define SEG_NBY         40
%define SEG_OFFB        44
%define SEG_SIZE        48
%define SF_FLAT_A       1               ; cut flat at the start instead of round
%define SF_FLAT_B       2
%define OPS_MAX         64
%define GUIDE_SNAP      8               ; font units from a guideline that still count as on it
%define FLATTEN_STEPS   12
%define ARENA_SIZE      (4 * 1024 * 1024)

section .rodata
align 4
style_size:     dd 12.0, 13.5, 13.5, 20.0, 26.0
style_pen:      dd 100, 100, 128, 118, 122           ; pen width in font units
style_track:    dd 28, 18, 18, 6, 0                  ; extra space after each glyph, font units
; Flat ends of steep strokes on these lines are cut level with them, like the
; feet of an A, instead of square to the stroke. The cut sits half a pen past
; the line, as far out as a round or joined stroke on it reaches.
guidelines:     dd 0, XHEIGHT, CAPHEIGHT, ASCENDER, DESCENDER
f_boost:        dd 0.35                             ; how much partly covered pixels darken
f_snap:         dd 0.3
f_half:         dd 0.5
f_one:          dd 1.0
f_255:          dd 255.0
f_quarter:      dd 0.25
f_milli:        dd 0.001
f_big:          dd 1.0e30
f_eps:          dd 1.0e-6
f_step:         dd 0.0833333                        ; 1 / FLATTEN_STEPS
f_three:        dd 3.0
f_tan22:        dd 0.41421356                       ; tan(22.5 degrees)
ellipsis_char:  db GLYPH_ELLIPSIS

section .bss
alignb 4
style_scale:    resd STYLE_COUNT                    ; px per font unit
style_sy:       resd STYLE_COUNT                    ; and up, nudged so the x-height lands on a pixel edge
style_yoff:     resd STYLE_COUNT                    ; how far below the cell's baseline row the font's baseline sits
style_half:     resd STYLE_COUNT                    ; half the pen, px
style_left:     resd STYLE_COUNT                    ; where x = 0 sits in a cell
style_base:     resd STYLE_COUNT                    ; the baseline row in a cell
style_cell_w:   resd STYLE_COUNT
style_cell_h:   resd STYLE_COUNT
adv4:           resd STYLE_COUNT * GLYPH_COUNT      ; advances in quarter pixels
cell_ptr:       resq STYLE_COUNT * GLYPH_COUNT * PHASES
arena_used:     resq 1
arena:          resb ARENA_SIZE

tr_scale:       resd 1
tr_sy:          resd 1
tr_ox:          resd 1
tr_oy:          resd 1
cubic:          resd 8
seg_count:      resd 1
segs:           resb SEG_MAX * SEG_SIZE
op_count:       resd 1
op_first:       resd OPS_MAX + 1                    ; each stroke's first segment, then the end
pen_reach:      resd 1                              ; half the pen plus half a pixel

section .text

; xmm0 -> eax = ceil(xmm0)
ceil_f:
    cvttss2si eax, xmm0
    cvtsi2ss xmm1, eax
    ucomiss xmm0, xmm1
    jbe .done
    inc eax
.done:
    ret

; xmm0 -> eax = floor(xmm0)
floor_f:
    cvttss2si eax, xmm0
    cvtsi2ss xmm1, eax
    ucomiss xmm0, xmm1
    jae .done
    dec eax
.done:
    ret

; Works out each style's scale, cell layout and advances.
text_init:
    push rbx
    push r12
    xor ebx, ebx
.style:
    movss xmm0, [style_size + rbx * 4]
    mulss xmm0, [f_milli]
    movss [style_scale + rbx * 4], xmm0
    cvtsi2ss xmm1, dword [style_pen + rbx * 4]
    mulss xmm1, xmm0
    mulss xmm1, [f_half]
    movss [style_half + rbx * 4], xmm1
    call snap_style

    ; left: room for strokes that reach 110 units left of the origin (j, the
    ; comma), base: room up to 790, cell bottom: down to -230.
    mov eax, 110
    call units_plus_pen
    add eax, 1
    mov [style_left + rbx * 4], eax
    mov eax, 790
    call units_plus_pen
    add eax, 1
    mov [style_base + rbx * 4], eax
    mov eax, 230
    call units_plus_pen
    add eax, [style_base + rbx * 4]
    add eax, 2
    mov [style_cell_h + rbx * 4], eax
    mov eax, 960                            ; the widest glyph, W
    call units_plus_pen
    add eax, [style_left + rbx * 4]
    add eax, 2
    mov [style_cell_w + rbx * 4], eax

    ; Heavier pens get proportionally more room, and small text more air.
    xor r12d, r12d
.advance:
    mov rax, [glyph_table + r12 * 8]
    movsx eax, word [rax]
    add eax, [style_pen + rbx * 4]
    sub eax, BASE_PEN
    add eax, [style_track + rbx * 4]
    shl eax, 2                              ; quarter pixels
    cvtsi2ss xmm0, eax
    mulss xmm0, [style_scale + rbx * 4]
    cvtss2si eax, xmm0
    imul ecx, ebx, GLYPH_COUNT
    add ecx, r12d
    mov [adv4 + rcx * 4], eax
    inc r12d
    cmp r12d, GLYPH_COUNT
    jb .advance
    inc ebx
    cmp ebx, STYLE_COUNT
    jb .style
    pop r12
    pop rbx
    ret

; Hints a style a little: the bottom of the strokes on the baseline and the
; top of the ones on the x-height land on pixel edges, so lowercase text
; doesn't sit on a half-covered row. ebx = style
snap_style:
    movss xmm2, [style_half + rbx * 4]
    movaps xmm0, xmm2
    addss xmm0, [f_half]
    call floor_f
    cvtsi2ss xmm3, eax
    subss xmm3, xmm2
    movss [style_yoff + rbx * 4], xmm3      ; round(half pen) - half pen
    ; The x-height with the pen on both sides, a bit under half rounding
    ; down, so heavier styles keep the body's height.
    mov eax, XHEIGHT
    cvtsi2ss xmm0, eax
    mulss xmm0, [style_scale + rbx * 4]
    addss xmm0, xmm2
    addss xmm0, xmm2
    addss xmm0, [f_snap]
    call floor_f
    cvtsi2ss xmm0, eax
    subss xmm0, xmm2
    subss xmm0, xmm2
    mov eax, XHEIGHT
    cvtsi2ss xmm1, eax
    divss xmm0, xmm1
    movss [style_sy + rbx * 4], xmm0
    ret

; eax = font units, ebx = style -> eax = ceil(units * scale + half pen)
units_plus_pen:
    cvtsi2ss xmm0, eax
    mulss xmm0, [style_scale + rbx * 4]
    addss xmm0, [style_half + rbx * 4]
    jmp ceil_f

; Adds a segment from (xmm0, xmm1) to (xmm2, xmm3).
add_seg:
    mov eax, [seg_count]
    cmp eax, SEG_MAX
    jae .full
    imul eax, eax, SEG_SIZE
    lea rax, [segs + rax]
    movss [rax + SEG_AX], xmm0
    movss [rax + SEG_AY], xmm1
    subss xmm2, xmm0
    subss xmm3, xmm1
    movss [rax + SEG_DX], xmm2
    movss [rax + SEG_DY], xmm3
    mulss xmm2, xmm2
    mulss xmm3, xmm3
    addss xmm2, xmm3
    xorps xmm4, xmm4
    ucomiss xmm2, [f_eps]
    jbe .dot
    movss xmm4, [f_one]
    divss xmm4, xmm2
.dot:
    movss [rax + SEG_INV], xmm4
    mov dword [rax + SEG_FLAGS], 0
    inc dword [seg_count]
.full:
    ret

; rsi = two int16 font coordinates -> xmm0, xmm1 = pixel position, via tr_*
tr_point:
    movsx eax, word [rsi]
    cvtsi2ss xmm0, eax
    mulss xmm0, [tr_scale]
    addss xmm0, [tr_ox]
    movsx eax, word [rsi + 2]
    cvtsi2ss xmm2, eax
    mulss xmm2, [tr_sy]
    movss xmm1, [tr_oy]
    subss xmm1, xmm2
    ret

; rsi = a glyph's strokes. Replaces segs with them, placed by tr_*, and
; op_first with where each stroke starts.
glyph_segs:
    push rbx
    push r12
    sub rsp, 24
    mov dword [seg_count], 0
    mov dword [op_count], 0
    mov rbx, rsi
.op:
    movzx eax, word [rbx]
    test eax, eax
    jz .done
    mov ecx, [op_count]
    cmp ecx, OPS_MAX
    jae .no_room                            ; past this, the last stroke takes in the rest
    mov edx, [seg_count]
    mov [op_first + rcx * 4], edx
    inc dword [op_count]
.no_room:
    movzx eax, word [rbx]
    cmp eax, GO_LINE
    jne .cubic
    lea rsi, [rbx + 2]
    call tr_point
    movss [rsp], xmm0
    movss [rsp + 4], xmm1
    lea rsi, [rbx + 6]
    call tr_point
    movaps xmm2, xmm0
    movaps xmm3, xmm1
    movss xmm0, [rsp]
    movss xmm1, [rsp + 4]
    call add_seg
    add rbx, 10
    jmp .op
.cubic:
    xor r12d, r12d
.point:
    lea rsi, [rbx + 2 + r12 * 4]
    call tr_point
    movss [cubic + r12 * 8], xmm0
    movss [cubic + r12 * 8 + 4], xmm1
    inc r12d
    cmp r12d, 4
    jb .point
    movss xmm0, [cubic]
    movss xmm1, [cubic + 4]
    movss [rsp], xmm0                       ; previous point
    movss [rsp + 4], xmm1
    mov r12d, 1
.step:
    ; Bernstein weights for t = i / steps
    cvtsi2ss xmm4, r12d
    mulss xmm4, [f_step]                    ; t
    movss xmm5, [f_one]
    subss xmm5, xmm4                        ; 1 - t
    movaps xmm6, xmm5
    mulss xmm6, xmm5
    mulss xmm6, xmm5                        ; (1-t)^3
    movaps xmm7, xmm5
    mulss xmm7, xmm5
    mulss xmm7, xmm4
    mulss xmm7, [f_three]                   ; 3(1-t)^2 t
    movaps xmm8, xmm5
    mulss xmm8, xmm4
    mulss xmm8, xmm4
    mulss xmm8, [f_three]                   ; 3(1-t) t^2
    movaps xmm9, xmm4
    mulss xmm9, xmm4
    mulss xmm9, xmm4                        ; t^3
    movss xmm2, [cubic]
    mulss xmm2, xmm6
    movss xmm10, [cubic + 8]
    mulss xmm10, xmm7
    addss xmm2, xmm10
    movss xmm10, [cubic + 16]
    mulss xmm10, xmm8
    addss xmm2, xmm10
    movss xmm10, [cubic + 24]
    mulss xmm10, xmm9
    addss xmm2, xmm10
    movss xmm3, [cubic + 4]
    mulss xmm3, xmm6
    movss xmm10, [cubic + 12]
    mulss xmm10, xmm7
    addss xmm3, xmm10
    movss xmm10, [cubic + 20]
    mulss xmm10, xmm8
    addss xmm3, xmm10
    movss xmm10, [cubic + 28]
    mulss xmm10, xmm9
    addss xmm3, xmm10
    movss [rsp + 8], xmm2
    movss [rsp + 12], xmm3
    movss xmm0, [rsp]
    movss xmm1, [rsp + 4]
    call add_seg
    movss xmm0, [rsp + 8]
    movss xmm1, [rsp + 12]
    movss [rsp], xmm0
    movss [rsp + 4], xmm1
    inc r12d
    cmp r12d, FLATTEN_STEPS
    jbe .step
    add rbx, 18
    jmp .op
.done:
    mov eax, [op_count]
    mov ecx, [seg_count]
    mov [op_first + rax * 4], ecx
    add rsp, 24
    pop r12
    pop rbx
    ret

; xmm0 = x, xmm1 = y -> xmm0 = squared distance to the nearest segment
seg_dist2:
    movss xmm7, [f_big]
    lea rcx, [segs]
    mov edx, [seg_count]
    xorps xmm8, xmm8
    movss xmm9, [f_one]
.seg:
    test edx, edx
    jz .done
    movaps xmm2, xmm0
    subss xmm2, [rcx + SEG_AX]
    movaps xmm3, xmm1
    subss xmm3, [rcx + SEG_AY]
    movss xmm4, [rcx + SEG_DX]
    mulss xmm4, xmm2
    movss xmm5, [rcx + SEG_DY]
    mulss xmm5, xmm3
    addss xmm4, xmm5
    mulss xmm4, [rcx + SEG_INV]
    maxss xmm4, xmm8
    minss xmm4, xmm9                        ; t, clamped to the segment
    movss xmm5, [rcx + SEG_DX]
    mulss xmm5, xmm4
    subss xmm2, xmm5
    movss xmm6, [rcx + SEG_DY]
    mulss xmm6, xmm4
    subss xmm3, xmm6
    mulss xmm2, xmm2
    mulss xmm3, xmm3
    addss xmm2, xmm3
    minss xmm7, xmm2
    add rcx, SEG_SIZE
    dec edx
    jmp .seg
.done:
    movaps xmm0, xmm7
    ret

; xmm0 = x, xmm1 = y, edi = first, esi = one past the last segment to skip
; -> xmm0 = squared distance to the nearest segment outside that range
seg_dist2_outside:
    movss xmm7, [f_big]
    lea rcx, [segs]
    xor edx, edx
    xorps xmm8, xmm8
    movss xmm9, [f_one]
.seg:
    cmp edx, [seg_count]
    jae .done
    cmp edx, edi
    jb .measure
    cmp edx, esi
    jb .next
.measure:
    movaps xmm2, xmm0
    subss xmm2, [rcx + SEG_AX]
    movaps xmm3, xmm1
    subss xmm3, [rcx + SEG_AY]
    movss xmm4, [rcx + SEG_DX]
    mulss xmm4, xmm2
    movss xmm5, [rcx + SEG_DY]
    mulss xmm5, xmm3
    addss xmm4, xmm5
    mulss xmm4, [rcx + SEG_INV]
    maxss xmm4, xmm8
    minss xmm4, xmm9
    movss xmm5, [rcx + SEG_DX]
    mulss xmm5, xmm4
    subss xmm2, xmm5
    movss xmm6, [rcx + SEG_DY]
    mulss xmm6, xmm4
    subss xmm3, xmm6
    mulss xmm2, xmm2
    mulss xmm3, xmm3
    addss xmm2, xmm3
    minss xmm7, xmm2
.next:
    add rcx, SEG_SIZE
    inc edx
    jmp .seg
.done:
    movaps xmm0, xmm7
    ret

; Cuts every stroke end flat that doesn't run into another stroke. Dots
; stay round. ebx = style
mark_caps:
    push r12
    push r13
    push r14
    xor r12d, r12d
.op:
    cmp r12d, [op_count]
    jae .done
    mov r13d, [op_first + r12 * 4]
    mov r14d, [op_first + r12 * 4 + 4]
    cmp r13d, r14d
    jae .next
    ; A stroke shorter than the pen is a dot.
    imul eax, r13d, SEG_SIZE
    lea rax, [segs + rax]
    imul ecx, r14d, SEG_SIZE
    lea rcx, [segs + rcx - SEG_SIZE]
    movss xmm0, [rcx + SEG_AX]
    addss xmm0, [rcx + SEG_DX]
    subss xmm0, [rax + SEG_AX]
    movss xmm1, [rcx + SEG_AY]
    addss xmm1, [rcx + SEG_DY]
    subss xmm1, [rax + SEG_AY]
    mulss xmm0, xmm0
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    movss xmm1, [style_half + rbx * 4]
    addss xmm1, xmm1
    ucomiss xmm0, xmm1
    jb .next
    mov edi, r13d
    xor esi, esi
    call cap_end
    lea edi, [r14d - 1]
    mov esi, 1
    call cap_end
.next:
    inc r12d
    jmp .op
.done:
    pop r14
    pop r13
    pop r12
    ret

; One end of a stroke. edi = its segment, esi = 0 for the start or 1 for
; the end, ebx = style, r13d and r14d = the stroke's segments, as in mark_caps
cap_end:
    push rbp
    push r12
    sub rsp, 24
    imul eax, edi, SEG_SIZE
    lea rbp, [segs + rax]
    mov r12d, esi
    movss xmm0, [rbp + SEG_AX]              ; the end point
    movss xmm1, [rbp + SEG_AY]
    movss xmm2, [rbp + SEG_DX]              ; and the way into the stroke
    movss xmm3, [rbp + SEG_DY]
    test r12d, r12d
    jz .point
    addss xmm0, xmm2
    addss xmm1, xmm3
    xorps xmm4, xmm4
    subss xmm4, xmm2
    movaps xmm2, xmm4
    xorps xmm4, xmm4
    subss xmm4, xmm3
    movaps xmm3, xmm4
.point:
    movss [rsp], xmm0
    movss [rsp + 4], xmm1
    movss [rsp + 8], xmm2
    movss [rsp + 12], xmm3
    mov edi, r13d
    mov esi, r14d
    call seg_dist2_outside
    sqrtss xmm0, xmm0
    ucomiss xmm0, [style_half + rbx * 4]
    jbe .done                               ; it joins another stroke

    movss xmm2, [rsp + 8]
    movss xmm3, [rsp + 12]
    movaps xmm4, xmm2
    mulss xmm4, xmm4
    movaps xmm5, xmm3
    mulss xmm5, xmm5
    addss xmm4, xmm5
    sqrtss xmm4, xmm4
    ucomiss xmm4, [f_eps]
    jbe .done
    divss xmm2, xmm4
    divss xmm3, xmm4
    movss xmm6, [f_half]                    ; the cut's offset
    ; Steep strokes ending on a guideline get cut level with it.
    movaps xmm4, xmm2
    andps xmm4, [abs_mask]
    movaps xmm5, xmm3
    andps xmm5, [abs_mask]
    ucomiss xmm5, xmm4
    jbe .store
    movss xmm0, [tr_oy]
    subss xmm0, [rsp + 4]
    divss xmm0, [tr_sy]                     ; the end's height in font units
    xor ecx, ecx
.guide:
    cvtsi2ss xmm1, dword [guidelines + rcx * 4]
    subss xmm1, xmm0
    andps xmm1, [abs_mask]
    mov eax, GUIDE_SNAP
    cvtsi2ss xmm4, eax
    ucomiss xmm1, xmm4
    jb .level
    inc ecx
    cmp ecx, 5
    jb .guide
    jmp .store
.level:
    addss xmm6, [style_half + rbx * 4]
    xorps xmm2, xmm2
    movss xmm4, [f_one]
    xorps xmm5, xmm5
    ucomiss xmm3, xmm5
    jae .down
    subss xmm5, xmm4
    movaps xmm4, xmm5
.down:
    movaps xmm3, xmm4
.store:
    mov eax, SF_FLAT_A
    lea rcx, [rbp + SEG_NAX]
    test r12d, r12d
    jz .flag
    mov eax, SF_FLAT_B
    lea rcx, [rbp + SEG_NBX]
.flag:
    or [rbp + SEG_FLAGS], eax
    movss [rcx], xmm2
    movss [rcx + 4], xmm3
    movss [rcx + 8], xmm6
.done:
    add rsp, 24
    pop r12
    pop rbp
    ret

; xmm0 = x, xmm1 = y -> xmm0 = how much of the pixel there the glyph's
; strokes cover, 0-1. A flat end lets its segment run on past the end point
; and cuts it there instead, so a level cut on a slanted stroke stays square.
glyph_cov:
    xorps xmm15, xmm15                      ; the best so far
    xorps xmm8, xmm8
    movss xmm9, [f_one]
    lea rcx, [segs]
    mov edx, [seg_count]
.seg:
    test edx, edx
    jz .done
    movaps xmm2, xmm0
    subss xmm2, [rcx + SEG_AX]
    movaps xmm3, xmm1
    subss xmm3, [rcx + SEG_AY]
    movss xmm4, [rcx + SEG_DX]
    mulss xmm4, xmm2
    movss xmm5, [rcx + SEG_DY]
    mulss xmm5, xmm3
    addss xmm4, xmm5
    mulss xmm4, [rcx + SEG_INV]             ; t along the segment
    mov eax, [rcx + SEG_FLAGS]
    test eax, SF_FLAT_A
    jnz .no_low
    maxss xmm4, xmm8
.no_low:
    test eax, SF_FLAT_B
    jnz .no_high
    minss xmm4, xmm9
.no_high:
    movss xmm5, [rcx + SEG_DX]
    mulss xmm5, xmm4
    movaps xmm6, xmm2
    subss xmm6, xmm5
    movss xmm5, [rcx + SEG_DY]
    mulss xmm5, xmm4
    movaps xmm7, xmm3
    subss xmm7, xmm5
    mulss xmm6, xmm6
    mulss xmm7, xmm7
    addss xmm6, xmm7
    sqrtss xmm6, xmm6
    movss xmm5, [pen_reach]
    subss xmm5, xmm6
    ucomiss xmm5, xmm15
    jbe .next
    minss xmm5, xmm9
    test eax, SF_FLAT_A
    jz .end_cut
    movss xmm6, [rcx + SEG_NAX]
    mulss xmm6, xmm2
    movss xmm7, [rcx + SEG_NAY]
    mulss xmm7, xmm3
    addss xmm6, xmm7
    addss xmm6, [rcx + SEG_OFFA]
    maxss xmm6, xmm8
    minss xmm6, xmm9
    mulss xmm5, xmm6
.end_cut:
    test eax, SF_FLAT_B
    jz .keep
    movaps xmm6, xmm2
    subss xmm6, [rcx + SEG_DX]
    mulss xmm6, [rcx + SEG_NBX]
    movaps xmm7, xmm3
    subss xmm7, [rcx + SEG_DY]
    mulss xmm7, [rcx + SEG_NBY]
    addss xmm6, xmm7
    addss xmm6, [rcx + SEG_OFFB]
    maxss xmm6, xmm8
    minss xmm6, xmm9
    mulss xmm5, xmm6
.keep:
    maxss xmm15, xmm5
.next:
    add rcx, SEG_SIZE
    dec edx
    jmp .seg
.done:
    movaps xmm0, xmm15
    ret

; xmm0 = coverage 0-1 (any value) -> eax = 0-255
cov_byte:
    xorps xmm1, xmm1
    maxss xmm0, xmm1
    minss xmm0, [f_one]
    mulss xmm0, [f_255]
    addss xmm0, [f_half]
    cvttss2si eax, xmm0
    ret

; edi = style, esi = glyph, edx = phase -> rax = its cell, or 0 if the cache is full
glyph_cell:
    imul eax, edi, GLYPH_COUNT
    add eax, esi
    lea eax, [rax * PHASES + rdx]
    mov rax, [cell_ptr + rax * 8]
    test rax, rax
    jnz .done
    jmp raster_cell
.done:
    ret

; Rasterizes a glyph into a new cache cell, for glyph_cell.
; edi = style, esi = glyph, edx = phase -> rax = the cell, or 0 if the cache is full
raster_cell:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov ebx, edi                            ; style
    mov [rsp], esi                          ; glyph
    mov [rsp + 4], edx                      ; phase
    mov eax, [style_cell_w + rbx * 4]
    imul eax, [style_cell_h + rbx * 4]
    mov rcx, [arena_used]
    lea rdx, [rcx + rax]
    cmp rdx, ARENA_SIZE
    ja .full
    mov [arena_used], rdx
    lea r15, [arena + rcx]                  ; the cell, zeroed already

    movss xmm0, [style_scale + rbx * 4]
    movss [tr_scale], xmm0
    movss xmm0, [style_sy + rbx * 4]
    movss [tr_sy], xmm0
    cvtsi2ss xmm0, dword [rsp + 4]
    mulss xmm0, [f_quarter]
    cvtsi2ss xmm1, dword [style_left + rbx * 4]
    addss xmm0, xmm1
    movss [tr_ox], xmm0
    cvtsi2ss xmm0, dword [style_base + rbx * 4]
    addss xmm0, [style_yoff + rbx * 4]
    movss [tr_oy], xmm0
    mov eax, [rsp]
    mov rsi, [glyph_table + rax * 8]
    add rsi, 2                              ; past the advance
    call glyph_segs
    call mark_caps
    movss xmm0, [style_half + rbx * 4]
    addss xmm0, [f_half]
    movss [pen_reach], xmm0

    mov r12d, [style_cell_w + rbx * 4]
    xor r13d, r13d                          ; row
.row:
    cmp r13d, [style_cell_h + rbx * 4]
    jae .stored
    xor r14d, r14d                          ; column
.col:
    cmp r14d, r12d
    jae .next_row
    cvtsi2ss xmm0, r14d
    addss xmm0, [f_half]
    cvtsi2ss xmm1, r13d
    addss xmm1, [f_half]
    call glyph_cov
    ; Thin light strokes on a dark background read too faint when blended
    ; linearly, so partly covered pixels get pushed up a little.
    movss xmm1, [f_one]
    subss xmm1, xmm0
    mulss xmm1, xmm0
    mulss xmm1, [f_boost]
    addss xmm0, xmm1
    call cov_byte
    mov ecx, r13d
    imul ecx, r12d
    add ecx, r14d
    mov [r15 + rcx], al
    inc r14d
    jmp .col
.next_row:
    inc r13d
    jmp .row
.stored:
    imul eax, ebx, GLYPH_COUNT
    add eax, [rsp]
    shl eax, 2
    add eax, [rsp + 4]
    mov [cell_ptr + rax * 8], r15
    mov rax, r15
    jmp .done
.full:
    xor eax, eax
.done:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Blends a coverage cell into the framebuffer.
; rdi = cell, esi = x, edx = y, ecx = style, r8d = color
blit_cell:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov [rsp], r8d
    mov r12d, [style_cell_w + rcx * 4]
    mov r13d, [style_cell_h + rcx * 4]
    ; visible rows [r14, r15) and columns [ebp, [rsp+4]), in cell coordinates
    mov r14d, [clip_y0]
    sub r14d, edx
    xor eax, eax
    cmp r14d, eax
    cmovl r14d, eax
    mov r15d, [clip_y1]
    sub r15d, edx
    cmp r15d, r13d
    cmovg r15d, r13d
    mov ebp, [clip_x0]
    sub ebp, esi
    cmp ebp, eax
    cmovl ebp, eax
    mov eax, [clip_x1]
    sub eax, esi
    cmp eax, r12d
    cmovg eax, r12d
    mov [rsp + 4], eax
    mov [rsp + 8], esi
    mov [rsp + 12], edx
.row:
    cmp r14d, r15d
    jge .done
    mov eax, [rsp + 12]
    add eax, r14d
    imul eax, [fb_w]
    add eax, [rsp + 8]
    movsxd rax, eax                         ; the cell can start left of the framebuffer
    mov rcx, [fb]
    lea r13, [rcx + rax * 4]                ; pixel at cell column 0
    mov eax, r14d
    imul eax, r12d
    lea r9, [rbx + rax]
    mov [rsp + 16], r9
    mov ecx, ebp
.col:
    cmp ecx, [rsp + 4]
    jge .next_row
    mov r9, [rsp + 16]
    movzx edx, byte [r9 + rcx]
    test edx, edx
    jz .skip
    push rcx
    lea rdi, [r13 + rcx * 4]
    mov esi, [rsp + 8]
    call blend_pixel
    pop rcx
.skip:
    inc ecx
    jmp .col
.next_row:
    inc r14d
    jmp .row
.done:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = character -> eax = glyph index. Anything outside the font is '?'.
glyph_index:
    lea eax, [edi - GLYPH_FIRST]
    cmp eax, GLYPH_COUNT
    jb .done
    mov eax, '?' - GLYPH_FIRST
.done:
    ret

; edi = x, esi = baseline y, rdx = text, ecx = length, r8d = ink -> eax = x after it
draw_text:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    lea r12d, [edi * 4]                     ; pen x, quarter pixels
    mov r13d, esi
    mov rbx, rdx
    mov ebp, ecx
    mov r14d, r8d
    and r14d, 0xffffff
    mov r15d, r8d
    shr r15d, 24
.char:
    test ebp, ebp
    jz .done
    movzx edi, byte [rbx]
    call glyph_index
    mov [rsp], eax
    mov edi, r15d
    mov esi, eax
    mov edx, r12d
    and edx, PHASES - 1
    call glyph_cell
    test rax, rax
    jz .advance
    mov rdi, rax
    mov esi, r12d
    sar esi, 2
    sub esi, [style_left + r15 * 4]
    mov edx, r13d
    sub edx, [style_base + r15 * 4]
    mov ecx, r15d
    mov r8d, r14d
    call blit_cell
.advance:
    imul eax, r15d, GLYPH_COUNT
    add eax, [rsp]
    add r12d, [adv4 + rax * 4]
    inc rbx
    dec ebp
    jmp .char
.done:
    lea eax, [r12d + 2]
    sar eax, 2
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; rdi = text, esi = length, edx = style -> eax = width in pixels
text_width:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    imul r13d, edx, GLYPH_COUNT
    xor ecx, ecx                            ; quarter pixels
.char:
    test r12d, r12d
    jz .done
    movzx edi, byte [rbx]
    call glyph_index
    add eax, r13d
    add ecx, [adv4 + rax * 4]
    inc rbx
    dec r12d
    jmp .char
.done:
    lea eax, [ecx + 2]
    sar eax, 2
    pop r13
    pop r12
    pop rbx
    ret

; Like draw_text, but text wider than max_w is cut short with an ellipsis.
; edi = x, esi = y, rdx = text, ecx = length, r8d = ink, r9d = max width
; -> eax = width drawn
draw_text_fit:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov rbx, rdx
    mov ebp, ecx
    mov r14d, r8d
    mov r15d, r9d
    mov rdi, rbx
    mov esi, ebp
    mov edx, r14d
    shr edx, 24
    call text_width
    cmp eax, r15d
    jle .draw
    lea rdi, [ellipsis_char]
    mov esi, 1
    mov edx, r14d
    shr edx, 24
    call text_width
    sub r15d, eax                           ; room for the text itself
.shrink:
    test ebp, ebp
    jz .cut
    dec ebp
    mov rdi, rbx
    mov esi, ebp
    mov edx, r14d
    shr edx, 24
    call text_width
    cmp eax, r15d
    jg .shrink
.cut:
    mov edi, r12d
    mov esi, r13d
    mov rdx, rbx
    mov ecx, ebp
    mov r8d, r14d
    call draw_text
    mov edi, eax
    mov esi, r13d
    lea rdx, [ellipsis_char]
    mov ecx, 1
    mov r8d, r14d
    call draw_text
    sub eax, r12d
    jmp .done
.draw:
    mov edi, r12d
    mov esi, r13d
    mov rdx, rbx
    mov ecx, ebp
    mov r8d, r14d
    call draw_text
    sub eax, r12d
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

section .rodata
align 16
abs_mask:       dd 0x7fffffff, 0x7fffffff, 0x7fffffff, 0x7fffffff
section .text
