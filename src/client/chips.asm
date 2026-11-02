; The project and label chips on a list row and a board card, as many as
; there's room for.

section .text

; A list row's chips, right to left from edi, so they read in slot order and
; leave the title some room. edi = right edge, esi = row y, edx = the title's
; x, rcx = view issue -> eax = the x left of them
row_chips:
    push rbx
    push rbp
    push r13
    push r15
    sub rsp, 8
    mov ebp, edi
    mov r13d, esi
    mov r15d, edx
    mov rbx, rcx
    movzx eax, byte [rbx + CI_PROJECT]
    test eax, eax
    jz .labels
    dec eax
    imul eax, eax, PJ_SIZE
    lea rdi, [view_projects + rax]
    call .chip
.labels:
    mov dword [rsp], LABEL_SLOTS - 1
.label:
    mov ecx, [rsp]
    test ecx, ecx
    js .done
    movzx eax, word [rbx + CI_LABELS]
    bt eax, ecx
    jnc .next_label
    imul eax, ecx, LB_SIZE
    lea rdi, [view_labels + rax]
    call .chip
    test eax, eax
    jz .done
.next_label:
    dec dword [rsp]
    jmp .label
.done:
    mov eax, ebp
    add rsp, 8
    pop r15
    pop r13
    pop rbp
    pop rbx
    ret
; A chip ending at ebp, if it leaves the title some room.
; rdi = the label or project -> eax = 0 when there wasn't room
.chip:
    push r12
    mov r12, rdi
    cmp byte [r12 + LB_NAME_LEN], 0
    je .chip_skip                           ; a deleted label
    lea rdi, [r12 + LB_NAME]
    movzx esi, byte [r12 + LB_NAME_LEN]
    mov edx, 1
    call chip_width
    mov ecx, ebp
    sub ecx, eax
    lea edx, [r15d + 160]
    cmp ecx, edx
    jl .no_room
    mov ebp, ecx
    mov edi, ebp
    lea esi, [r13d + 7]
    lea rdx, [r12 + LB_NAME]
    movzx ecx, byte [r12 + LB_NAME_LEN]
    mov r8d, [r12 + LB_COLOR]
    call draw_chip
    sub ebp, 6
.chip_skip:
    mov eax, 1
    pop r12
    ret
.no_room:
    xor eax, eax
    pop r12
    ret

; A board card's chips, left to right from edi while they fit.
; edi = x, esi = the card's y, edx = where they must end, rcx = view issue
card_chips:
    push rbx
    push rbp
    push r13
    push r15
    sub rsp, 8
    mov ebp, edi
    mov r13d, esi
    mov r15d, edx
    mov rbx, rcx
    movzx eax, byte [rbx + CI_PROJECT]
    test eax, eax
    jz .labels
    dec eax
    imul eax, eax, PJ_SIZE
    lea rdi, [view_projects + rax]
    call .chip
.labels:
    mov dword [rsp], 0
.label:
    mov ecx, [rsp]
    cmp ecx, LABEL_SLOTS
    jae .done
    movzx eax, word [rbx + CI_LABELS]
    bt eax, ecx
    jnc .next_label
    imul eax, ecx, LB_SIZE
    lea rdi, [view_labels + rax]
    call .chip
    test eax, eax
    jz .done
.next_label:
    inc dword [rsp]
    jmp .label
.done:
    add rsp, 8
    pop r15
    pop r13
    pop rbp
    pop rbx
    ret
; A chip at ebp, if it fits before r15d. rdi = label or project -> eax = 0 if it didn't
.chip:
    push r12
    mov r12, rdi
    cmp byte [r12 + LB_NAME_LEN], 0
    je .chip_skip
    lea rdi, [r12 + LB_NAME]
    movzx esi, byte [r12 + LB_NAME_LEN]
    mov edx, 1
    call chip_width
    lea ecx, [ebp + eax]
    cmp ecx, r15d
    jg .no_room
    mov edi, ebp
    lea ebp, [ecx + 6]
    lea esi, [r13d + 58]
    lea rdx, [r12 + LB_NAME]
    movzx ecx, byte [r12 + LB_NAME_LEN]
    mov r8d, [r12 + LB_COLOR]
    call draw_chip
.chip_skip:
    mov eax, 1
    pop r12
    ret
.no_room:
    xor eax, eax
    pop r12
    ret
