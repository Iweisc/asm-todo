; The framebuffer being drawn, the clip rectangle, solid rectangles and
; blending. Text and anti-aliased shapes live in text.asm.

section .bss

fb:         resq 1
fb_w:       resd 1
fb_h:       resd 1
clip_x0:    resd 1
clip_y0:    resd 1
clip_x1:    resd 1
clip_y1:    resd 1

section .text

reset_clip:
    mov dword [clip_x0], 0
    mov dword [clip_y0], 0
    mov eax, [fb_w]
    mov [clip_x1], eax
    mov eax, [fb_h]
    mov [clip_y1], eax
    ret

; edi = x0, esi = y0, edx = x1, ecx = y1 (exclusive), kept inside the framebuffer
set_clip:
    xor eax, eax
    cmp edi, eax
    cmovl edi, eax
    cmp esi, eax
    cmovl esi, eax
    cmp edx, [fb_w]
    cmovg edx, [fb_w]
    cmp ecx, [fb_h]
    cmovg ecx, [fb_h]
    mov [clip_x0], edi
    mov [clip_y0], esi
    mov [clip_x1], edx
    mov [clip_y1], ecx
    ret

; Narrows the clip to its overlap with a rectangle.
; edi = x0, esi = y0, edx = x1, ecx = y1 (exclusive)
clip_to:
    cmp edi, [clip_x0]
    cmovl edi, [clip_x0]
    cmp esi, [clip_y0]
    cmovl esi, [clip_y0]
    cmp edx, [clip_x1]
    cmovg edx, [clip_x1]
    cmp ecx, [clip_y1]
    cmovg ecx, [clip_y1]
    cmp edx, edi
    cmovl edx, edi
    cmp ecx, esi
    cmovl ecx, esi
    mov [clip_x0], edi
    mov [clip_y0], esi
    mov [clip_x1], edx
    mov [clip_y1], ecx
    ret

; -> rax = the clip packed as four words, for restore_clip
save_clip:
    movzx eax, word [clip_y1]
    shl rax, 16
    mov ax, [clip_x1]
    shl rax, 16
    mov ax, [clip_y0]
    shl rax, 16
    mov ax, [clip_x0]
    ret

; rdi = what save_clip returned
restore_clip:
    movzx eax, di
    mov [clip_x0], eax
    shr rdi, 16
    movzx eax, di
    mov [clip_y0], eax
    shr rdi, 16
    movzx eax, di
    mov [clip_x1], eax
    shr rdi, 16
    movzx eax, di
    mov [clip_y1], eax
    ret

; edi = x, esi = y, edx = w, ecx = h, r8d = color
fill_rect:
    add edx, edi                            ; edx = x1
    add ecx, esi                            ; ecx = y1
    cmp edi, [clip_x0]
    cmovl edi, [clip_x0]
    cmp esi, [clip_y0]
    cmovl esi, [clip_y0]
    cmp edx, [clip_x1]
    cmovg edx, [clip_x1]
    cmp ecx, [clip_y1]
    cmovg ecx, [clip_y1]
    sub edx, edi                            ; edx = visible width
    jle .done
    sub ecx, esi                            ; ecx = visible height
    jle .done

    mov r9d, [fb_w]
    mov eax, esi
    imul eax, r9d
    add eax, edi
    mov r10, [fb]
    lea r10, [r10 + rax * 4]                ; first pixel
    shl r9, 2                               ; stride in bytes
    mov r11d, ecx
    mov eax, r8d
    and eax, 0xffffff
.row:
    mov rdi, r10
    mov ecx, edx
    rep stosd
    add r10, r9
    dec r11d
    jnz .row
.done:
    ret

; Mixes a color into a pixel. rdi = pixel, esi = color, edx = coverage 0-255
; Clobbers eax, ecx, edx, r8d, r9d, r10d.
blend_pixel:
    cmp edx, 255
    jae .solid
    mov ecx, edx
    shr ecx, 7
    add edx, ecx                            ; 0-256, so full coverage is exact
    mov ecx, 256
    sub ecx, edx
    mov eax, [rdi]
    mov r8d, esi
    and r8d, 0xff00ff
    imul r8d, edx
    mov r9d, eax
    and r9d, 0xff00ff
    imul r9d, ecx
    add r8d, r9d
    shr r8d, 8
    and r8d, 0xff00ff
    mov r10d, esi
    and r10d, 0xff00
    imul r10d, edx
    and eax, 0xff00
    imul eax, ecx
    add eax, r10d
    shr eax, 8
    and eax, 0xff00
    or eax, r8d
    mov [rdi], eax
    ret
.solid:
    mov eax, esi
    and eax, 0xffffff
    mov [rdi], eax
    ret
