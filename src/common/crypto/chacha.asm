; ChaCha20, Poly1305 and the ChaCha20-Poly1305 AEAD from RFC 8439,
; with the 96-bit nonce built the way Noise wants it: 32 zero bits followed
; by a 64-bit little-endian counter.

%define POLY_R0         0
%define POLY_R1         8
%define POLY_S1         16              ; r1 + r1/4, folds the 2^130 = 5 reduction into r1
%define POLY_H0         24
%define POLY_H1         32
%define POLY_H2         40
%define POLY_PAD0       48
%define POLY_PAD1       56
%define POLY_CTX_SIZE   64

section .text

%macro QUARTER_ROUND 4
    mov eax, [rsp + 4 * %1]
    mov ebx, [rsp + 4 * %2]
    mov ecx, [rsp + 4 * %3]
    mov edx, [rsp + 4 * %4]
    add eax, ebx
    xor edx, eax
    rol edx, 16
    add ecx, edx
    xor ebx, ecx
    rol ebx, 12
    add eax, ebx
    xor edx, eax
    rol edx, 8
    add ecx, edx
    xor ebx, ecx
    rol ebx, 7
    mov [rsp + 4 * %1], eax
    mov [rsp + 4 * %2], ebx
    mov [rsp + 4 * %3], ecx
    mov [rsp + 4 * %4], edx
%endmacro

; rdi = key (32), esi = block counter, rdx = nonce (12), rcx = out (64)
chacha20_block:
    push rbx
    push rbp
    push r12
    sub rsp, 128                            ; working state x[16], input j[16]
    mov r12, rcx
    mov dword [rsp + 64], 0x61707865        ; "expand 32-byte k"
    mov dword [rsp + 68], 0x3320646e
    mov dword [rsp + 72], 0x79622d32
    mov dword [rsp + 76], 0x6b206574
    xor ecx, ecx
.key:
    mov eax, [rdi + rcx * 4]
    mov [rsp + 80 + rcx * 4], eax
    inc ecx
    cmp ecx, 8
    jb .key
    mov [rsp + 112], esi
    mov eax, [rdx]
    mov [rsp + 116], eax
    mov eax, [rdx + 4]
    mov [rsp + 120], eax
    mov eax, [rdx + 8]
    mov [rsp + 124], eax
    xor ecx, ecx
.copy:
    mov eax, [rsp + 64 + rcx * 4]
    mov [rsp + rcx * 4], eax
    inc ecx
    cmp ecx, 16
    jb .copy

    mov ebp, 10
.double_round:
    QUARTER_ROUND 0, 4, 8, 12
    QUARTER_ROUND 1, 5, 9, 13
    QUARTER_ROUND 2, 6, 10, 14
    QUARTER_ROUND 3, 7, 11, 15
    QUARTER_ROUND 0, 5, 10, 15
    QUARTER_ROUND 1, 6, 11, 12
    QUARTER_ROUND 2, 7, 8, 13
    QUARTER_ROUND 3, 4, 9, 14
    dec ebp
    jnz .double_round

    xor ecx, ecx
.out:
    mov eax, [rsp + rcx * 4]
    add eax, [rsp + 64 + rcx * 4]
    mov [r12 + rcx * 4], eax
    inc ecx
    cmp ecx, 16
    jb .out
    mov rdi, rsp
    mov esi, 128
    call wipe
    add rsp, 128
    pop r12
    pop rbp
    pop rbx
    ret

; XORs the keystream into buf, in place.
; rdi = key, esi = first block counter, rdx = nonce (12), rcx = buf, r8 = length
chacha20_xor:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov r12, rdi
    mov ebp, esi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
.block:
    test r15, r15
    jz .done
    mov rdi, r12
    mov esi, ebp
    mov rdx, r13
    mov rcx, rsp
    call chacha20_block
    inc ebp
    mov ecx, 64
    cmp r15, rcx
    cmovb rcx, r15
    xor eax, eax
.xor:
    mov dl, [rsp + rax]
    xor [r14 + rax], dl
    inc eax
    cmp eax, ecx
    jb .xor
    add r14, rcx
    sub r15, rcx
    jmp .block
.done:
    mov rdi, rsp
    mov esi, 64
    call wipe
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; rdi = ctx, rsi = one-time key (32)
poly1305_init:
    mov rax, 0x0ffffffc0fffffff
    and rax, [rsi]
    mov [rdi + POLY_R0], rax
    mov rax, 0x0ffffffc0ffffffc
    and rax, [rsi + 8]
    mov [rdi + POLY_R1], rax
    mov rcx, rax
    shr rcx, 2
    add rax, rcx
    mov [rdi + POLY_S1], rax
    xor eax, eax
    mov [rdi + POLY_H0], rax
    mov [rdi + POLY_H1], rax
    mov [rdi + POLY_H2], rax
    mov rax, [rsi + 16]
    mov [rdi + POLY_PAD0], rax
    mov rax, [rsi + 24]
    mov [rdi + POLY_PAD1], rax
    ret

; Absorbs data, zero-padding a trailing partial block to 16 bytes. That's
; exactly the padding the AEAD construction asks for.
; rdi = ctx, rsi = data, rdx = length
poly1305_update_padded:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24                             ; padded tail block
    push rdi
    mov rbx, rdx
    mov r8, [rdi + POLY_H0]
    mov r9, [rdi + POLY_H1]
    mov r10, [rdi + POLY_H2]
    mov r11, [rdi + POLY_R0]
    mov r12, [rdi + POLY_R1]
    mov r13, [rdi + POLY_S1]
.block:
    cmp rbx, 16
    jae .full
    test rbx, rbx
    jz .done
    ; Copy the tail into a zeroed block and run it as a full one.
    xor eax, eax
    mov [rsp + 8], rax
    mov [rsp + 16], rax
    lea rdi, [rsp + 8]
    mov rcx, rbx
    rep movsb
    lea rsi, [rsp + 8]
    mov ebx, 16
.full:
    add r8, [rsi]                           ; h += m + 2^128
    adc r9, [rsi + 8]
    adc r10, 1
    mov rax, r8                             ; d0 = h0*r0 + h1*s1
    mul r11
    mov r14, rax
    mov r15, rdx
    mov rax, r9
    mul r13
    add r14, rax
    adc r15, rdx
    mov rax, r8                             ; d1 = h0*r1 + h1*r0 + h2*s1
    mul r12
    mov rcx, rax
    mov rbp, rdx
    mov rax, r9
    mul r11
    add rcx, rax
    adc rbp, rdx
    mov rax, r10
    imul rax, r13
    add rcx, rax
    adc rbp, 0
    imul r10, r11                           ; d2 = h2*r0
    mov r8, r14
    add rcx, r15
    adc rbp, 0
    mov r9, rcx
    add r10, rbp
    mov rax, r10                            ; fold everything above 2^130 back in, times 5
    and rax, -4
    mov rcx, r10
    shr rcx, 2
    add rax, rcx
    and r10, 3
    add r8, rax
    adc r9, 0
    adc r10, 0
    add rsi, 16
    sub rbx, 16
    jmp .block
.done:
    pop rdi
    mov [rdi + POLY_H0], r8
    mov [rdi + POLY_H1], r9
    mov [rdi + POLY_H2], r10
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; rdi = ctx, rsi = out tag (16)
poly1305_finish:
    mov r8, [rdi + POLY_H0]
    mov r9, [rdi + POLY_H1]
    mov r10, [rdi + POLY_H2]
    ; g = h + 5. If that reaches 2^130, h >= p and the answer is g mod 2^130.
    mov rax, r8
    add rax, 5
    mov rcx, r9
    adc rcx, 0
    mov rdx, r10
    adc rdx, 0
    shr rdx, 2
    neg rdx                                 ; all ones when h >= p
    xor rax, r8
    and rax, rdx
    xor r8, rax
    xor rcx, r9
    and rcx, rdx
    xor r9, rcx
    add r8, [rdi + POLY_PAD0]
    adc r9, [rdi + POLY_PAD1]
    mov [rsi], r8
    mov [rsi + 8], r9
    ret

; Builds the RFC 8439 nonce and the Poly1305 one-time key for message n.
; rdi = key, rsi = n, rdx = nonce out (12), rcx = poly ctx out
aead_setup:
    push rbx
    push r12
    push r13
    sub rsp, 64
    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    mov dword [r12], 0
    mov [r12 + 4], rsi
    xor esi, esi
    mov rdx, r12
    mov rcx, rsp
    call chacha20_block
    mov rdi, r13
    mov rsi, rsp
    call poly1305_init
    mov rdi, rsp
    mov esi, 64
    call wipe
    add rsp, 64
    pop r13
    pop r12
    pop rbx
    ret

; MACs ad and ciphertext the RFC 8439 way into tag.
; rdi = poly ctx, rsi = ad, rdx = ad length, rcx = ciphertext, r8 = its length, r9 = tag out
aead_mac:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    mov r14, r8
    mov r15, r9
    call poly1305_update_padded
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    call poly1305_update_padded
    mov [rsp], r12
    mov [rsp + 8], r14
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 16
    call poly1305_update_padded
    mov rdi, rbx
    mov rsi, r15
    call poly1305_finish
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Encrypts buf in place and appends the 16-byte tag after it.
; rdi = key, rsi = n, rdx = ad, rcx = ad length, r8 = buf, r9 = plaintext length
aead_seal:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, POLY_CTX_SIZE + 24             ; poly ctx + nonce
    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    mov r14, r8
    mov r15, r9
    lea rdx, [rsp + POLY_CTX_SIZE]
    mov rcx, rsp
    call aead_setup
    mov rdi, rbx
    mov esi, 1
    lea rdx, [rsp + POLY_CTX_SIZE]
    mov rcx, r14
    mov r8, r15
    call chacha20_xor
    mov rdi, rsp
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    mov r8, r15
    lea r9, [r14 + r15]
    call aead_mac
    mov rdi, rsp
    mov esi, POLY_CTX_SIZE
    call wipe
    add rsp, POLY_CTX_SIZE + 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Checks the tag, and only then decrypts in place.
; rdi = key, rsi = n, rdx = ad, rcx = ad length, r8 = buf, r9 = length including the tag
; -> eax = 0 if authentic, -1 if not (buf untouched)
aead_open:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, POLY_CTX_SIZE + 40             ; poly ctx + nonce + expected tag
    mov eax, -1
    cmp r9, 16
    jb .out
    sub r9, 16
    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    mov r14, r8
    mov r15, r9
    lea rdx, [rsp + POLY_CTX_SIZE]
    mov rcx, rsp
    call aead_setup
    mov rdi, rsp
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    mov r8, r15
    lea r9, [rsp + POLY_CTX_SIZE + 16]
    call aead_mac
    lea rdi, [rsp + POLY_CTX_SIZE + 16]
    lea rsi, [r14 + r15]
    mov edx, 16
    call ct_equal
    test eax, eax
    jz .forged
    mov rdi, rbx
    mov esi, 1
    lea rdx, [rsp + POLY_CTX_SIZE]
    mov rcx, r14
    mov r8, r15
    call chacha20_xor
    xor eax, eax
    jmp .wipe
.forged:
    mov eax, -1
.wipe:
    push rax
    lea rdi, [rsp + 8]
    mov esi, POLY_CTX_SIZE
    call wipe
    pop rax
.out:
    add rsp, POLY_CTX_SIZE + 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
