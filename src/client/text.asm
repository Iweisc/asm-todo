; Anti-aliased text and shapes.
;
; Glyphs from font.asm are flattened into line segments, and a pixel's
; coverage is how much of it a round pen of the style's width covers along
; them. Each glyph is rasterized once per style and per quarter-pixel offset,
; on first use, then blended from the cache. Icons use the same distance
; trick, through shape_fill and a coverage function.
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
%define SEG_SIZE        20
%define FLATTEN_STEPS   12
%define ARENA_SIZE      (4 * 1024 * 1024)

section .rodata
align 4
style_size:     dd 12.0, 13.5, 13.5, 20.0, 26.0
style_pen:      dd 100, 100, 135, 120, 125           ; pen width in font units
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
tr_ox:          resd 1
tr_oy:          resd 1
cubic:          resd 8
seg_count:      resd 1
segs:           resb SEG_MAX * SEG_SIZE

sh_cx:          resd 1                              ; shape parameters, px
sh_cy:          resd 1
sh_r:           resd 1
sh_w:           resd 1                              ; half a stroke's width

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

    ; Heavier pens get proportionally more room.
    xor r12d, r12d
.advance:
    mov rax, [glyph_table + r12 * 8]
    movsx eax, word [rax]
    add eax, [style_pen + rbx * 4]
    sub eax, BASE_PEN
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
    mulss xmm2, [tr_scale]
    movss xmm1, [tr_oy]
    subss xmm1, xmm2
    ret

; rsi = a glyph's strokes. Replaces segs with them, placed by tr_*.
glyph_segs:
    push rbx
    push r12
    sub rsp, 24
    mov dword [seg_count], 0
    mov rbx, rsi
.op:
    movzx eax, word [rbx]
    test eax, eax
    jz .done
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
    cvtsi2ss xmm0, dword [rsp + 4]
    mulss xmm0, [f_quarter]
    cvtsi2ss xmm1, dword [style_left + rbx * 4]
    addss xmm0, xmm1
    movss [tr_ox], xmm0
    cvtsi2ss xmm0, dword [style_base + rbx * 4]
    movss [tr_oy], xmm0
    mov eax, [rsp]
    mov rsi, [glyph_table + rax * 8]
    add rsi, 2                              ; past the advance
    call glyph_segs

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
    call seg_dist2
    sqrtss xmm0, xmm0
    movss xmm1, [style_half + rbx * 4]
    addss xmm1, [f_half]
    subss xmm1, xmm0
    movaps xmm0, xmm1
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

; --- shapes ---

; Blends a shape whose coverage a function computes.
; edi = x0, esi = y0, edx = x1, ecx = y1 (exclusive), r8d = color,
; r9 = coverage function: xmm0 = x, xmm1 = y -> xmm0 = coverage
shape_fill:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    cmp edi, [clip_x0]
    cmovl edi, [clip_x0]
    cmp esi, [clip_y0]
    cmovl esi, [clip_y0]
    cmp edx, [clip_x1]
    cmovg edx, [clip_x1]
    cmp ecx, [clip_y1]
    cmovg ecx, [clip_y1]
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov r15d, ecx
    mov [rsp], r8d
    mov rbx, r9
.row:
    cmp r13d, r15d
    jge .done
    mov ebp, r12d
.col:
    cmp ebp, r14d
    jge .next_row
    cvtsi2ss xmm0, ebp
    addss xmm0, [f_half]
    cvtsi2ss xmm1, r13d
    addss xmm1, [f_half]
    call rbx
    call cov_byte
    test eax, eax
    jz .skip
    mov edx, eax
    mov eax, r13d
    imul eax, [fb_w]
    add eax, ebp
    mov rdi, [fb]
    lea rdi, [rdi + rax * 4]
    mov esi, [rsp]
    call blend_pixel
.skip:
    inc ebp
    jmp .col
.next_row:
    inc r13d
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

; xmm0 = x, xmm1 = y -> xmm0 = distance from (sh_cx, sh_cy)
center_dist:
    subss xmm0, [sh_cx]
    subss xmm1, [sh_cy]
    mulss xmm0, xmm0
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    ret

cov_disc:
    call center_dist
    movss xmm1, [sh_r]
    addss xmm1, [f_half]
    subss xmm1, xmm0
    movaps xmm0, xmm1
    ret

cov_ring:
    call center_dist
    subss xmm0, [sh_r]
    movss xmm1, xmm0                        ; |d - r|
    xorps xmm2, xmm2
    subss xmm2, xmm0
    maxss xmm1, xmm2
    movss xmm0, [sh_w]
    addss xmm0, [f_half]
    subss xmm0, xmm1
    ret

; The ring cut into 8 dashes: 16 sectors of 22.5 degrees, every other one drawn.
cov_dashed_ring:
    movss xmm2, xmm0
    subss xmm2, [sh_cx]                     ; dx
    movss xmm3, xmm1
    subss xmm3, [sh_cy]                     ; dy
    xorps xmm4, xmm4
    xor ecx, ecx
    ucomiss xmm2, xmm4
    jae .x_positive
    xor ecx, 1
.x_positive:
    ucomiss xmm3, xmm4
    jae .y_positive
    xor ecx, 1                              ; mirrored quadrants count the other way
.y_positive:
    movaps xmm5, xmm2
    andps xmm5, [abs_mask]
    movaps xmm6, xmm3
    andps xmm6, [abs_mask]
    xor edx, edx                            ; sector within the quadrant, 0-3
    ucomiss xmm5, xmm6
    jb .steep
    mulss xmm5, [f_tan22]
    ucomiss xmm6, xmm5
    jbe .sector
    mov edx, 1
    jmp .sector
.steep:
    mov edx, 3
    mulss xmm6, [f_tan22]
    ucomiss xmm5, xmm6
    jbe .sector
    mov edx, 2
.sector:
    test ecx, ecx
    jz .parity
    xor edx, 3
.parity:
    test edx, 1
    jnz cov_ring
    xorps xmm0, xmm0
    ret

; A disc's right half.
cov_half_disc:
    movaps xmm3, xmm0                       ; cov_disc leaves xmm3 alone
    call cov_disc
    movaps xmm1, xmm3
    subss xmm1, [sh_cx]
    addss xmm1, [f_half]
    xorps xmm2, xmm2
    maxss xmm1, xmm2
    minss xmm1, [f_one]
    mulss xmm0, xmm1
    ret

cov_strokes:
    call seg_dist2
    sqrtss xmm0, xmm0
    movss xmm1, [sh_w]
    addss xmm1, [f_half]
    subss xmm1, xmm0
    movaps xmm0, xmm1
    ret

; Sets sh_cx, sh_cy, sh_r from quarter pixels and returns the bounding box.
; edi = cx, esi = cy, edx = r, ecx = extra margin -> edi, esi, edx, ecx = x0, y0, x1, y1
circle_setup:
    cvtsi2ss xmm0, edi
    mulss xmm0, [f_quarter]
    movss [sh_cx], xmm0
    cvtsi2ss xmm0, esi
    mulss xmm0, [f_quarter]
    movss [sh_cy], xmm0
    cvtsi2ss xmm0, edx
    mulss xmm0, [f_quarter]
    movss [sh_r], xmm0
    lea eax, [edx + ecx + 8]                ; reach in quarter pixels, plus 2px
    mov r10d, edi
    sub r10d, eax
    sar r10d, 2
    lea r11d, [edi + eax]
    sar r11d, 2
    mov edi, esi
    sub edi, eax
    sar edi, 2
    lea ecx, [esi + eax]
    sar ecx, 2
    mov esi, edi
    mov edi, r10d
    mov edx, r11d
    ret

; edi = cx, esi = cy, edx = r (quarter pixels), ecx = color
aa_disc:
    mov r8d, ecx
    xor ecx, ecx
    call circle_setup
    lea r9, [cov_disc]
    jmp shape_fill

; edi = cx, esi = cy, edx = r, ecx = color, r8d = stroke width (quarter pixels)
aa_ring:
    lea r9, [cov_ring]
ring_common:
    cvtsi2ss xmm0, r8d
    mulss xmm0, [f_quarter]
    mulss xmm0, [f_half]
    movss [sh_w], xmm0
    push r9
    push rcx
    mov ecx, r8d
    call circle_setup
    pop r8
    pop r9
    jmp shape_fill

aa_dashed_ring:
    lea r9, [cov_dashed_ring]
    jmp ring_common

; edi = cx, esi = cy, edx = r, ecx = color. The right half of a disc.
aa_half_disc:
    mov r8d, ecx
    xor ecx, ecx
    call circle_setup
    lea r9, [cov_half_disc]
    jmp shape_fill

; A round-capped polyline.
; rdi = points as dword pairs in quarter pixels, esi = point count,
; edx = x, ecx = y (origin, pixels), r8d = color, r9d = pen width (quarter pixels)
aa_polyline:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32
    mov rbx, rdi
    mov r12d, esi
    mov [rsp], r8d
    cvtsi2ss xmm0, r9d
    mulss xmm0, [f_quarter]
    mulss xmm0, [f_half]
    movss [sh_w], xmm0
    cvtsi2ss xmm0, edx
    movss [tr_ox], xmm0
    cvtsi2ss xmm0, ecx
    movss [tr_oy], xmm0
    mov dword [seg_count], 0
    mov r13d, 0x7fffffff                    ; bounding box, quarter pixels
    mov r14d, -0x7fffffff
    mov r15d, 0x7fffffff
    mov dword [rsp + 4], -0x7fffffff
    xor ecx, ecx
.point:
    cmp ecx, r12d
    jae .segments
    mov eax, [rbx + rcx * 8]
    cmp eax, r13d
    cmovl r13d, eax
    cmp eax, r14d
    cmovg r14d, eax
    mov eax, [rbx + rcx * 8 + 4]
    cmp eax, r15d
    cmovl r15d, eax
    cmp eax, [rsp + 4]
    jle .next_point
    mov [rsp + 4], eax
.next_point:
    inc ecx
    jmp .point
.segments:
    mov ecx, 1
.seg:
    cmp ecx, r12d
    jae .fill
    mov [rsp + 8], ecx
    cvtsi2ss xmm0, dword [rbx + rcx * 8 - 8]
    mulss xmm0, [f_quarter]
    addss xmm0, [tr_ox]
    cvtsi2ss xmm1, dword [rbx + rcx * 8 - 4]
    mulss xmm1, [f_quarter]
    addss xmm1, [tr_oy]
    cvtsi2ss xmm2, dword [rbx + rcx * 8]
    mulss xmm2, [f_quarter]
    addss xmm2, [tr_ox]
    cvtsi2ss xmm3, dword [rbx + rcx * 8 + 4]
    mulss xmm3, [f_quarter]
    addss xmm3, [tr_oy]
    call add_seg
    mov ecx, [rsp + 8]
    inc ecx
    jmp .seg
.fill:
    cvttss2si eax, [tr_ox]
    cvttss2si ecx, [tr_oy]
    sar r13d, 2
    sar r14d, 2
    sar r15d, 2
    mov edx, [rsp + 4]
    sar edx, 2
    lea edi, [eax + r13d - 3]
    lea esi, [ecx + r15d - 3]
    lea r9d, [ecx + edx + 4]
    lea edx, [eax + r14d + 4]
    mov ecx, r9d
    mov r8d, [rsp]
    lea r9, [cov_strokes]
    call shape_fill
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; A rectangle with anti-aliased round corners.
; edi = x, esi = y, edx = w, ecx = h, r8d = color, r9d = corner radius
fill_rrect:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov r15d, ecx
    mov ebx, r8d
    mov ebp, r9d
    lea eax, [ebp * 2]                      ; the radius can't exceed half a side
    cmp eax, r14d
    jle .w_ok
    mov ebp, r14d
    shr ebp, 1
.w_ok:
    lea eax, [ebp * 2]
    cmp eax, r15d
    jle .h_ok
    mov ebp, r15d
    shr ebp, 1
.h_ok:
    mov edi, r12d                           ; middle band, full width
    lea esi, [r13d + ebp]
    mov edx, r14d
    mov ecx, r15d
    sub ecx, ebp
    sub ecx, ebp
    mov r8d, ebx
    call fill_rect
    lea edi, [r12d + ebp]                   ; top and bottom bands between the corners
    mov esi, r13d
    mov edx, r14d
    sub edx, ebp
    sub edx, ebp
    mov ecx, ebp
    mov r8d, ebx
    call fill_rect
    lea edi, [r12d + ebp]
    lea esi, [r13d + r15d]
    sub esi, ebp
    mov edx, r14d
    sub edx, ebp
    sub edx, ebp
    mov ecx, ebp
    mov r8d, ebx
    call fill_rect
    test ebp, ebp
    jz .done
    cvtsi2ss xmm0, ebp
    movss [sh_r], xmm0
    ; four corners: (box x, box y, circle center x, center y)
    mov edi, r12d
    mov esi, r13d
    lea eax, [r12d + ebp]
    lea ecx, [r13d + ebp]
    call .corner
    lea edi, [r12d + r14d]
    sub edi, ebp
    mov esi, r13d
    mov eax, edi
    lea ecx, [r13d + ebp]
    call .corner
    mov edi, r12d
    lea esi, [r13d + r15d]
    sub esi, ebp
    lea eax, [r12d + ebp]
    mov ecx, esi
    call .corner
    lea edi, [r12d + r14d]
    sub edi, ebp
    lea esi, [r13d + r15d]
    sub esi, ebp
    mov eax, edi
    mov ecx, esi
    call .corner
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
; edi, esi = corner box, eax, ecx = circle center (pixel corners)
.corner:
    cvtsi2ss xmm0, eax
    movss [sh_cx], xmm0
    cvtsi2ss xmm0, ecx
    movss [sh_cy], xmm0
    lea edx, [edi + ebp]
    lea ecx, [esi + ebp]
    mov r8d, ebx
    lea r9, [cov_disc]
    jmp shape_fill

; A rounded rectangle outline, 1px. Drawn as the border color with the
; inside filled again, so it needs to sit on an opaque fill.
; edi = x, esi = y, edx = w, ecx = h, r8d = border, r9d = fill, r10d = corner radius
outline_rrect:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov r15d, ecx
    mov ebx, r9d
    mov ebp, r10d
    mov r9d, ebp
    call fill_rrect
    lea edi, [r12d + 1]
    lea esi, [r13d + 1]
    lea edx, [r14d - 2]
    lea ecx, [r15d - 2]
    mov r8d, ebx
    lea r9d, [ebp - 1]
    xor eax, eax
    cmp r9d, eax
    cmovl r9d, eax
    call fill_rrect
    add rsp, 8
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
align 16
abs_mask:       dd 0x7fffffff, 0x7fffffff, 0x7fffffff, 0x7fffffff
section .text
