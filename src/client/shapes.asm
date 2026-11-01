; Anti-aliased shapes: discs, rings, round-capped polylines and rounded
; rectangles. Each pixel's coverage comes from a function of its distance to
; the shape, like the glyphs in text.asm.

section .bss
alignb 4
sh_cx:          resd 1                              ; shape parameters, px
sh_cy:          resd 1
sh_r:           resd 1
sh_w:           resd 1                              ; half a stroke's width

section .text

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

; xmm0 = x, xmm1 = y -> xmm0 = coverage of the disc at sh_cx, sh_cy, radius sh_r
cov_disc:
    call center_dist
    movss xmm1, [sh_r]
    addss xmm1, [f_half]
    subss xmm1, xmm0
    movaps xmm0, xmm1
    ret

; xmm0 = x, xmm1 = y -> xmm0 = coverage of that circle's outline, sh_w either side
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

; xmm0 = x, xmm1 = y -> xmm0 = coverage of the segments in segs, sh_w either side
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
; The same, with r9 = the coverage function
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

; edi = cx, esi = cy, edx = r, ecx = color, r8d = stroke width. A ring in 8 dashes.
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
