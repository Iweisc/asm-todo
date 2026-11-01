; SHA-256 (FIPS 180-4) and SHA-1. SHA-1 is only here because the WebSocket
; handshake requires it. Never use it for anything security-relevant.
;
; Both share the Merkle-Damgard plumbing in md_update / md_final and only
; differ in their compression function and output size.

%define MD_STATE        0           ; up to 8 dwords
%define MD_COUNT        32          ; total bytes hashed
%define MD_BUFLEN       40
%define MD_BUF          48          ; one 64-byte block
%define MD_CTX_SIZE     112

section .rodata

align 16
sha256_k:
    dd 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    dd 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    dd 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    dd 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    dd 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
    dd 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    dd 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    dd 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2

sha256_iv:
    dd 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

sha1_iv:
    dd 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0

section .text

; rdi = ctx
sha256_init:
    lea rsi, [sha256_iv]
    mov ecx, 8
    jmp md_init

; rdi = ctx
sha1_init:
    lea rsi, [sha1_iv]
    mov ecx, 5

; rdi = ctx, rsi = IV, ecx = words
md_init:
    push rdi
    mov edx, ecx
    xor eax, eax
.iv:
    mov r8d, [rsi + rax * 4]
    mov [rdi + rax * 4], r8d
    inc eax
    cmp eax, edx
    jb .iv
    pop rdi
    mov qword [rdi + MD_COUNT], 0
    mov qword [rdi + MD_BUFLEN], 0
    ret

; rdi = ctx, rsi = data, rdx = len
sha256_update:
    lea rcx, [sha256_compress]
    jmp md_update
sha1_update:
    lea rcx, [sha1_compress]

; rdi = ctx, rsi = data, rdx = len, rcx = compression function
md_update:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    add [rbx + MD_COUNT], rdx
.loop:
    test r13, r13
    jz .done
    mov rbp, [rbx + MD_BUFLEN]
    test rbp, rbp
    jnz .buffer
    cmp r13, 64
    jb .buffer
    mov rdi, rbx                            ; whole block straight from the input
    mov rsi, r12
    call r14
    add r12, 64
    sub r13, 64
    jmp .loop
.buffer:
    mov rdx, 64
    sub rdx, rbp
    cmp rdx, r13
    cmova rdx, r13
    lea rdi, [rbx + MD_BUF + rbp]
    mov rsi, r12
    add r12, rdx
    sub r13, rdx
    add rbp, rdx
    mov rcx, rdx
    rep movsb
    mov [rbx + MD_BUFLEN], rbp
    cmp rbp, 64
    jne .loop
    mov rdi, rbx
    lea rsi, [rbx + MD_BUF]
    call r14
    mov qword [rbx + MD_BUFLEN], 0
    jmp .loop
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; rdi = ctx, rsi = out (32 bytes)
sha256_final:
    lea rcx, [sha256_compress]
    mov edx, 8
    jmp md_final
; rdi = ctx, rsi = out (20 bytes)
sha1_final:
    lea rcx, [sha1_compress]
    mov edx, 5

; rdi = ctx, rsi = out, edx = output words, rcx = compression function
md_final:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    mov rax, [rbx + MD_BUFLEN]
    mov byte [rbx + MD_BUF + rax], 0x80
    inc rax
    cmp rax, 56
    jbe .pad
.pad_block:
    cmp rax, 64
    jae .flush
    mov byte [rbx + MD_BUF + rax], 0
    inc rax
    jmp .pad_block
.flush:
    mov rdi, rbx
    lea rsi, [rbx + MD_BUF]
    call r14
    xor eax, eax
.pad:
    cmp rax, 56
    jae .length
    mov byte [rbx + MD_BUF + rax], 0
    inc rax
    jmp .pad
.length:
    mov rax, [rbx + MD_COUNT]
    shl rax, 3                              ; bits, big-endian
    bswap rax
    mov [rbx + MD_BUF + 56], rax
    mov rdi, rbx
    lea rsi, [rbx + MD_BUF]
    call r14
    xor ecx, ecx
.out:
    mov eax, [rbx + rcx * 4]
    bswap eax
    mov [r12 + rcx * 4], eax
    inc ecx
    cmp ecx, r13d
    jb .out
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi = data, rsi = len, rdx = out (32 bytes)
sha256:
    push rbx
    sub rsp, MD_CTX_SIZE
    mov rbx, rdx
    push rsi
    push rdi
    lea rdi, [rsp + 16]
    call sha256_init
    pop rsi
    pop rdx
    mov rdi, rsp
    call sha256_update
    mov rdi, rsp
    mov rsi, rbx
    call sha256_final
    add rsp, MD_CTX_SIZE
    pop rbx
    ret

; rdi = state (8 dwords), rsi = 64-byte block
sha256_compress:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256 + 8                        ; message schedule W[64]

    xor ecx, ecx
.load:
    mov eax, [rsi + rcx * 4]
    bswap eax
    mov [rsp + rcx * 4], eax
    inc ecx
    cmp ecx, 16
    jb .load
.expand:
    mov eax, [rsp + rcx * 4 - 60]           ; W[i-15]
    mov ebx, eax
    ror ebx, 7
    mov edx, eax
    ror edx, 18
    xor ebx, edx
    shr eax, 3
    xor ebx, eax                            ; s0
    mov eax, [rsp + rcx * 4 - 8]            ; W[i-2]
    mov edx, eax
    ror edx, 17
    mov r8d, eax
    ror r8d, 19
    xor edx, r8d
    shr eax, 10
    xor edx, eax                            ; s1
    add ebx, edx
    add ebx, [rsp + rcx * 4 - 64]           ; W[i-16]
    add ebx, [rsp + rcx * 4 - 28]           ; W[i-7]
    mov [rsp + rcx * 4], ebx
    inc ecx
    cmp ecx, 64
    jb .expand

    mov r8d, [rdi]
    mov r9d, [rdi + 4]
    mov r10d, [rdi + 8]
    mov r11d, [rdi + 12]
    mov r12d, [rdi + 16]
    mov r13d, [rdi + 20]
    mov r14d, [rdi + 24]
    mov r15d, [rdi + 28]
    lea rsi, [sha256_k]
    xor ebp, ebp
.round:
    mov eax, r12d
    ror eax, 6
    mov ebx, r12d
    ror ebx, 11
    xor eax, ebx
    ror ebx, 14
    xor eax, ebx                            ; S1(e)
    mov ebx, r12d
    and ebx, r13d
    mov edx, r12d
    not edx
    and edx, r14d
    xor ebx, edx                            ; ch(e, f, g)
    add eax, ebx
    add eax, r15d
    add eax, [rsi + rbp * 4]
    add eax, [rsp + rbp * 4]                ; t1
    mov ebx, r8d
    ror ebx, 2
    mov edx, r8d
    ror edx, 13
    xor ebx, edx
    ror edx, 9
    xor ebx, edx                            ; S0(a)
    mov edx, r8d
    and edx, r9d
    mov ecx, r8d
    xor ecx, r9d
    and ecx, r10d
    or edx, ecx                             ; maj(a, b, c)
    add ebx, edx                            ; t2
    mov r15d, r14d
    mov r14d, r13d
    mov r13d, r12d
    lea r12d, [r11d + eax]
    mov r11d, r10d
    mov r10d, r9d
    mov r9d, r8d
    lea r8d, [eax + ebx]
    inc ebp
    cmp ebp, 64
    jb .round

    add [rdi], r8d
    add [rdi + 4], r9d
    add [rdi + 8], r10d
    add [rdi + 12], r11d
    add [rdi + 16], r12d
    add [rdi + 20], r13d
    add [rdi + 24], r14d
    add [rdi + 28], r15d
    add rsp, 256 + 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; rdi = state (5 dwords), rsi = 64-byte block
sha1_compress:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 320 + 8                        ; W[80]

    xor ecx, ecx
.load:
    mov eax, [rsi + rcx * 4]
    bswap eax
    mov [rsp + rcx * 4], eax
    inc ecx
    cmp ecx, 16
    jb .load
.expand:
    mov eax, [rsp + rcx * 4 - 12]
    xor eax, [rsp + rcx * 4 - 32]
    xor eax, [rsp + rcx * 4 - 56]
    xor eax, [rsp + rcx * 4 - 64]
    rol eax, 1
    mov [rsp + rcx * 4], eax
    inc ecx
    cmp ecx, 80
    jb .expand

    mov r8d, [rdi]                          ; a
    mov r9d, [rdi + 4]                      ; b
    mov r10d, [rdi + 8]                     ; c
    mov r11d, [rdi + 12]                    ; d
    mov r12d, [rdi + 16]                    ; e
    xor ebp, ebp
.round:
    cmp ebp, 20
    jb .ch
    cmp ebp, 40
    jb .parity1
    cmp ebp, 60
    jb .maj
    mov ebx, r9d
    xor ebx, r10d
    xor ebx, r11d
    mov edx, 0xca62c1d6
    jmp .mix
.ch:
    mov ebx, r9d
    and ebx, r10d
    mov eax, r9d
    not eax
    and eax, r11d
    or ebx, eax
    mov edx, 0x5a827999
    jmp .mix
.parity1:
    mov ebx, r9d
    xor ebx, r10d
    xor ebx, r11d
    mov edx, 0x6ed9eba1
    jmp .mix
.maj:
    mov ebx, r9d
    and ebx, r10d
    mov eax, r9d
    or eax, r10d
    and eax, r11d
    or ebx, eax
    mov edx, 0x8f1bbcdc
.mix:
    mov eax, r8d
    rol eax, 5
    add eax, ebx
    add eax, r12d
    add eax, edx
    add eax, [rsp + rbp * 4]
    mov r12d, r11d
    mov r11d, r10d
    mov r10d, r9d
    rol r10d, 30
    mov r9d, r8d
    mov r8d, eax
    inc ebp
    cmp ebp, 80
    jb .round

    add [rdi], r8d
    add [rdi + 4], r9d
    add [rdi + 8], r10d
    add [rdi + 12], r11d
    add [rdi + 16], r12d
    add rsp, 320 + 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
