; Reading and writing application messages.
;
; The reader never trusts lengths: every read checks the remaining bytes and
; sets rd_bad instead of running past the end. Handlers check rd_ok once,
; after they've read everything.

section .bss
rd_ptr:     resq 1
rd_end:     resq 1
rd_bad:     resb 1

section .text

; rdi = message, rsi = length
rd_begin:
    mov [rd_ptr], rdi
    add rdi, rsi
    mov [rd_end], rdi
    mov byte [rd_bad], 0
    ret

; edi = n -> rax = pointer to n bytes, or a harmless pointer and rd_bad set
rd_bytes:
    mov rax, [rd_ptr]
    mov rcx, [rd_end]
    sub rcx, rax
    cmp rdi, rcx
    ja .bad
    add [rd_ptr], rdi
    ret
.bad:
    mov byte [rd_bad], 1
    mov rax, [rd_end]
    ret

; -> eax
rd_u8:
    mov edi, 1
    call rd_bytes
    cmp byte [rd_bad], 0
    jne rd_zero
    movzx eax, byte [rax]
    ret
rd_u16:
    mov edi, 2
    call rd_bytes
    cmp byte [rd_bad], 0
    jne rd_zero
    movzx eax, word [rax]
    ret
rd_u32:
    mov edi, 4
    call rd_bytes
    cmp byte [rd_bad], 0
    jne rd_zero
    mov eax, [rax]
    ret
rd_zero:
    xor eax, eax
    ret

; u8 length + bytes -> rax = pointer, edx = length
rd_str:
    call rd_u8
    push rax
    mov edi, eax
    call rd_bytes
    pop rdx
    cmp byte [rd_bad], 0
    je .ok
    xor edx, edx
.ok:
    ret

; u16 length + bytes -> rax = pointer, edx = length
rd_str16:
    call rd_u16
    push rax
    mov edi, eax
    call rd_bytes
    pop rdx
    cmp byte [rd_bad], 0
    je .ok
    xor edx, edx
.ok:
    ret

; Skips the rest of the message, for ones we've decided to ignore.
rd_skip:
    mov rax, [rd_end]
    mov [rd_ptr], rax
    ret

; -> eax = 1 if every read succeeded and nothing is left over
rd_ok:
    xor eax, eax
    cmp byte [rd_bad], 0
    jne .done
    mov rcx, [rd_ptr]
    cmp rcx, [rd_end]
    sete al
.done:
    ret

; Writers take and return the cursor in rdi.

; esi = value
wr_u8:
    mov [rdi], sil
    inc rdi
    ret
wr_u16:
    mov [rdi], si
    add rdi, 2
    ret
wr_u32:
    mov [rdi], esi
    add rdi, 4
    ret

; rsi = bytes, edx = length (max 255)
wr_str:
    mov [rdi], dl
    inc rdi
    movzx ecx, dl
    rep movsb
    ret

; rsi = bytes, edx = length (max 65535)
wr_str16:
    mov [rdi], dx
    add rdi, 2
    movzx ecx, dx
    rep movsb
    ret
