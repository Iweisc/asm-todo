; Mentions: "@name" in a message, comment or description tags that member.
; The server and the client both read them with these, so they agree on
; what counts as one. Names match whatever their case.

section .text

; edi = character -> eax = 1 if it can be part of a username. Clobbers only eax.
; Uppercase counts too, since "@Maya" still means maya.
mention_char:
    mov eax, edi
    or eax, 0x20
    sub eax, 'a'
    cmp eax, 'z' - 'a'
    jbe .yes
    lea eax, [edi - '0']
    cmp eax, 9
    jbe .yes
    cmp edi, '.'
    je .yes
    cmp edi, '-'
    je .yes
    cmp edi, '_'
    je .yes
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret

; Whether "@name" is at a position, and not inside a word or the start of a
; longer name. Full stops after it end the sentence rather than the name.
; rdi = text, esi = length, edx = position, rcx = name, r8d = name length
; -> eax = the length of "@name" there, or 0
mention_at:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14, rcx
    mov r15d, r8d
    cmp r13d, r12d
    jae .no
    cmp byte [rbx + r13], '@'
    jne .no
    test r13d, r13d
    jz .name
    movzx edi, byte [rbx + r13 - 1]
    call mention_char
    test eax, eax
    jnz .no                                 ; an address, like x@y
.name:
    lea eax, [r13d + r15d + 1]
    cmp eax, r12d
    ja .no
    xor ecx, ecx
.char:
    cmp ecx, r15d
    jae .after
    lea eax, [r13d + ecx + 1]
    movzx edx, byte [rbx + rax]
    movzx eax, byte [r14 + rcx]
    lea edi, [edx - 'A']
    cmp edi, 'Z' - 'A'
    ja .compare
    or edx, 0x20
.compare:
    lea edi, [eax - 'A']
    cmp edi, 'Z' - 'A'
    ja .same
    or eax, 0x20
.same:
    cmp eax, edx
    jne .no
    inc ecx
    jmp .char
.after:
    lea r13d, [r13d + r15d + 1]             ; just past the name
.dots:
    cmp r13d, r12d
    jae .yes
    movzx edi, byte [rbx + r13]
    inc r13d
    cmp edi, '.'
    je .dots
    call mention_char
    test eax, eax
    jnz .no
.yes:
    lea eax, [r15d + 1]
    jmp .done
.no:
    xor eax, eax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi = text, esi = length, rdx = name, ecx = name length -> eax = 1 if the text mentions @name
text_mentions:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    xor ebp, ebp
.scan:
    cmp ebp, r12d
    jae .none
    cmp byte [rbx + rbp], '@'
    jne .next
    mov rdi, rbx
    mov esi, r12d
    mov edx, ebp
    mov rcx, r13
    mov r8d, r14d
    call mention_at
    test eax, eax
    jnz .found
.next:
    inc ebp
    jmp .scan
.found:
    mov eax, 1
    jmp .done
.none:
    xor eax, eax
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
