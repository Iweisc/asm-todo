; Status, priority and avatar icons, drawn in a 14px box from shapes.asm, and
; the X on close buttons. Shape coordinates are in quarter pixels, so the box
; is 56 units wide.

%define ICON_SIZE       14

section .rodata
align 4
status_color:   dd 0x8a8f98, 0xc8cbd0, 0xf2c94c, 0x5e6ad2, 0x6b6f76
check_points:   dd 17, 29, 25, 36, 39, 21
cross_a:        dd 21, 21, 35, 35
cross_b:        dd 35, 21, 21, 35
avatar_colors:  dd 0x5e6ad2, 0x26b5ce, 0x4cb782, 0xf2994a, 0xeb5757, 0xbb87fc, 0xf2c94c, 0x8a8f98

section .text

; edi = x, esi = y (top left), edx = status, ecx = the background behind it
draw_status_icon:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov ebx, edx
    mov r14d, ecx
    mov ecx, [status_color + rbx * 4]
    lea edi, [r12d * 4 + 28]
    lea esi, [r13d * 4 + 28]
    cmp ebx, STATUS_BACKLOG
    je .backlog
    cmp ebx, STATUS_TODO
    je .todo
    cmp ebx, STATUS_IN_PROGRESS
    je .in_progress
    mov edx, 25
    call aa_disc
    lea rdi, [check_points]
    mov esi, 3
    cmp ebx, STATUS_DONE
    je .mark
    lea rdi, [cross_a]
    mov esi, 2
    mov edx, r12d
    mov ecx, r13d
    mov r8d, r14d
    mov r9d, 6
    call aa_polyline
    lea rdi, [cross_b]
    mov esi, 2
.mark:
    mov edx, r12d
    mov ecx, r13d
    mov r8d, r14d
    mov r9d, 6
    call aa_polyline
    jmp .done
.backlog:
    mov edx, 21
    mov r8d, 6
    call aa_dashed_ring
    jmp .done
.in_progress:
    mov edx, 21
    mov r8d, 6
    call aa_ring
    lea edi, [r12d * 4 + 28]
    lea esi, [r13d * 4 + 28]
    mov edx, 11
    mov ecx, [status_color + rbx * 4]
    call aa_half_disc
    jmp .done
.todo:
    mov edx, 21
    mov r8d, 6
    call aa_ring
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; edi = x, esi = y (top left), edx = priority, ecx = color, r8d = dim color
; (the unlit bars), r9d = the background behind it
draw_priority_icon:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov ebx, edx
    mov r14d, ecx
    mov r15d, r8d
    mov ebp, r9d
    cmp ebx, PRIO_NONE
    je .none
    cmp ebx, PRIO_URGENT
    je .urgent
    ; Three rising bars, the first 5 - priority of them lit.
    xor eax, eax
.bar:
    mov [rsp], eax
    lea edi, [eax * 4 + 2]
    add edi, r12d
    lea esi, [eax * 2 + eax]                ; heights 6, 9, 12, sitting on y + 13
    mov ecx, esi
    add ecx, 6
    mov esi, r13d
    add esi, 13
    sub esi, ecx
    mov edx, 3
    mov r8d, r14d
    mov r9d, 5
    sub r9d, ebx
    cmp eax, r9d
    jb .lit
    mov r8d, r15d
.lit:
    mov r9d, 1
    call fill_rrect
    mov eax, [rsp]
    inc eax
    cmp eax, 3
    jb .bar
    jmp .done
.urgent:
    lea edi, [r12d + 1]
    lea esi, [r13d + 1]
    mov edx, 12
    mov ecx, 12
    mov r8d, 0xf2994a
    mov r9d, 3
    call fill_rrect
    lea edi, [r12d + 6]
    lea esi, [r13d + 3]
    mov edx, 2
    mov ecx, 5
    mov r8d, ebp
    call fill_rect
    lea edi, [r12d + 6]
    lea esi, [r13d + 9]
    mov edx, 2
    mov ecx, 2
    mov r8d, ebp
    call fill_rect
    jmp .done
.none:
    xor eax, eax
.dash:
    mov [rsp], eax
    lea edi, [eax * 4 + eax + 1]
    add edi, r12d
    lea esi, [r13d + 6]
    mov edx, 3
    mov ecx, 2
    mov r8d, r15d
    call fill_rect
    mov eax, [rsp]
    inc eax
    cmp eax, 3
    jb .dash
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; A colored disc with the first letter of a name in it.
; edi = x, esi = y (top left), edx = diameter, ecx = user id, r8 = name
draw_avatar:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov rbx, r8
    and ecx, 7
    mov ecx, [avatar_colors + rcx * 4]
    lea edi, [r12d * 2 + r14d]
    shl edi, 1                              ; center, quarter pixels
    lea esi, [r13d * 2 + r14d]
    shl esi, 1
    lea edx, [r14d * 2]
    call aa_disc
    movzx eax, byte [rbx]
    lea ecx, [eax - 'a']
    cmp ecx, 25
    ja .upper
    sub eax, 32
.upper:
    mov [rsp], al
    mov rdi, rsp
    mov esi, 1
    mov edx, ST_SMALL
    call text_width
    mov edi, r14d
    sub edi, eax
    sar edi, 1
    add edi, r12d
    mov esi, r14d
    shr esi, 1
    add esi, r13d
    add esi, 4                              ; half the cap height at 12px
    mov rdx, rsp
    mov ecx, 1
    mov r8d, INK(0xffffff, ST_SMALL)
    call draw_text
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; An X, for closing and removing things.
; edi = x, esi = y (its center, pixels), edx = half its size (quarter pixels), ecx = color
draw_cross:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 24
    mov r12d, edi
    mov r13d, esi
    mov ebx, edx
    mov r14d, ecx
    neg edx
    mov [rsp], edx                          ; top left to bottom right
    mov [rsp + 4], edx
    mov [rsp + 8], ebx
    mov [rsp + 12], ebx
    mov rdi, rsp
    mov esi, 2
    mov edx, r12d
    mov ecx, r13d
    mov r8d, r14d
    mov r9d, 6
    call aa_polyline
    mov eax, [rsp]                          ; then bottom left to top right
    mov [rsp + 4], ebx
    mov [rsp + 12], eax
    mov rdi, rsp
    mov esi, 2
    mov edx, r12d
    mov ecx, r13d
    mov r8d, r14d
    mov r9d, 6
    call aa_polyline
    add rsp, 24
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
