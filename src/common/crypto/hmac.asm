; HMAC-SHA256 (RFC 2104), Noise's two-output HKDF, and PBKDF2-HMAC-SHA256.

%define HMAC_INNER      0
%define HMAC_OUTER      MD_CTX_SIZE
%define HMAC_CTX_SIZE   (MD_CTX_SIZE * 2)

section .text

; Absorbs the key into the inner and outer hash states once, so repeated
; MACs under the same key (PBKDF2) only pay for the message.
; rdi = hmac ctx, rsi = key, rdx = key length
hmac_init:
    push rbx
    push r12
    sub rsp, 72                             ; 64-byte key block
    mov rbx, rdi
    mov rdi, rsp
    xor eax, eax
    mov ecx, 64
    rep stosb
    cmp rdx, 64
    jbe .short_key
    mov rdi, rsi                            ; long keys are hashed first
    mov rsi, rdx
    mov rdx, rsp
    call sha256
    jmp .pads
.short_key:
    mov rdi, rsp
    mov rcx, rdx
    rep movsb
.pads:
    xor ecx, ecx
.ipad:
    xor byte [rsp + rcx], 0x36
    inc ecx
    cmp ecx, 64
    jb .ipad
    lea rdi, [rbx + HMAC_INNER]
    call sha256_init
    lea rdi, [rbx + HMAC_INNER]
    mov rsi, rsp
    mov edx, 64
    call sha256_update
    xor ecx, ecx
.opad:
    xor byte [rsp + rcx], 0x36 ^ 0x5c
    inc ecx
    cmp ecx, 64
    jb .opad
    lea rdi, [rbx + HMAC_OUTER]
    call sha256_init
    lea rdi, [rbx + HMAC_OUTER]
    mov rsi, rsp
    mov edx, 64
    call sha256_update
    mov rdi, rsp
    mov esi, 64
    call wipe
    add rsp, 72
    pop r12
    pop rbx
    ret

; rdi = hmac ctx, rsi = message, rdx = length, rcx = out (32 bytes)
hmac_compute:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, MD_CTX_SIZE + 40               ; scratch hash ctx + inner digest
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, rsp
    lea rsi, [rbx + HMAC_INNER]
    mov ecx, MD_CTX_SIZE
    rep movsb
    mov rdi, rsp
    mov rsi, r12
    mov rdx, r13
    call sha256_update
    mov rdi, rsp
    lea rsi, [rsp + MD_CTX_SIZE]
    call sha256_final
    mov rdi, rsp
    lea rsi, [rbx + HMAC_OUTER]
    mov ecx, MD_CTX_SIZE
    rep movsb
    mov rdi, rsp
    lea rsi, [rsp + MD_CTX_SIZE]
    mov edx, 32
    call sha256_update
    mov rdi, rsp
    mov rsi, r14
    call sha256_final
    add rsp, MD_CTX_SIZE + 40
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi = key, rsi = key length, rdx = message, rcx = message length, r8 = out
hmac_sha256:
    push rbx
    push r12
    push r13
    sub rsp, HMAC_CTX_SIZE
    mov rbx, rdx
    mov r12, rcx
    mov r13, r8
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, rsp
    call hmac_init
    mov rdi, rsp
    mov rsi, rbx
    mov rdx, r12
    mov rcx, r13
    call hmac_compute
    mov rdi, rsp
    mov esi, HMAC_CTX_SIZE
    call wipe
    add rsp, HMAC_CTX_SIZE
    pop r13
    pop r12
    pop rbx
    ret

; Noise HKDF with two outputs. out1 may alias ck.
; rdi = chaining key (32), rsi = input key material, rdx = its length,
; rcx = out1 (32), r8 = out2 (32)
hkdf2:
    push rbx
    push r12
    push r13
    sub rsp, 80                             ; temp key + out1 || 0x02
    mov r12, rcx
    mov r13, r8
    mov rcx, rdx
    mov rdx, rsi
    mov esi, 32
    mov r8, rsp
    call hmac_sha256                        ; temp = HMAC(ck, ikm)

    mov byte [rsp + 32], 1
    mov rdi, rsp
    mov esi, 32
    lea rdx, [rsp + 32]
    mov ecx, 1
    lea r8, [rsp + 40]
    call hmac_sha256                        ; out1 = HMAC(temp, 0x01)
    ; out2 = HMAC(temp, out1 || 0x02). out1 sits at rsp+40, 0x02 right after.
    mov byte [rsp + 72], 2
    mov rdi, rsp
    mov esi, 32
    lea rdx, [rsp + 40]
    mov ecx, 33
    mov r8, r13
    call hmac_sha256
    mov rdi, r12
    lea rsi, [rsp + 40]
    mov ecx, 32
    rep movsb
    mov rdi, rsp
    mov esi, 80
    call wipe
    add rsp, 80
    pop r13
    pop r12
    pop rbx
    ret

; PBKDF2-HMAC-SHA256 with a single 32-byte output block, split into begin and
; step so a server can hash a password a slice at a time between other work.
%define PB_HMAC         0
%define PB_U            HMAC_CTX_SIZE
%define PB_T            (HMAC_CTX_SIZE + 32)        ; the result once done
%define PB_LEFT         (HMAC_CTX_SIZE + 64)
%define PB_SIZE         (HMAC_CTX_SIZE + 72)

; rdi = job, rsi = password, rdx = password length, rcx = salt,
; r8 = salt length (max 60), r9d = iterations (at least 1)
pbkdf2_begin:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 72                             ; salt || INT(1)
    mov rbx, rdi
    mov r12, rcx
    mov r13, r8
    lea eax, [r9d - 1]
    mov [rbx + PB_LEFT], eax
    call hmac_init                          ; rdi, rsi, rdx are already right
    mov rdi, rsp
    mov rsi, r12
    mov rcx, r13
    rep movsb
    mov dword [rdi], 0x01000000             ; INT(1), big-endian
    lea rdi, [rbx + PB_HMAC]
    mov rsi, rsp
    lea rdx, [r13 + 4]
    lea rcx, [rbx + PB_U]
    call hmac_compute
    lea rdi, [rbx + PB_T]
    lea rsi, [rbx + PB_U]
    mov ecx, 32
    rep movsb
    add rsp, 72
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Runs up to esi more iterations. rdi = job -> eax = 1 once the result is ready
pbkdf2_step:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
.iterate:
    cmp dword [rbx + PB_LEFT], 0
    je .done
    test r12d, r12d
    jz .more
    dec r12d
    dec dword [rbx + PB_LEFT]
    lea rdi, [rbx + PB_HMAC]
    lea rsi, [rbx + PB_U]
    mov edx, 32
    lea rcx, [rbx + PB_U]
    call hmac_compute
    mov rax, [rbx + PB_U]
    xor [rbx + PB_T], rax
    mov rax, [rbx + PB_U + 8]
    xor [rbx + PB_T + 8], rax
    mov rax, [rbx + PB_U + 16]
    xor [rbx + PB_T + 16], rax
    mov rax, [rbx + PB_U + 24]
    xor [rbx + PB_T + 24], rax
    jmp .iterate
.more:
    xor eax, eax
    jmp .out
.done:
    mov eax, 1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; One-shot version. rdi = password, rsi = password length, rdx = salt,
; rcx = salt length (max 60), r8d = iterations, r9 = out (32)
pbkdf2_sha256:
    push rbx
    sub rsp, PB_SIZE
    mov rbx, r9
    mov r9d, r8d
    mov r8, rcx
    mov rcx, rdx
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, rsp
    call pbkdf2_begin
    mov rdi, rsp
    mov esi, -1
    call pbkdf2_step
    mov rdi, rbx
    lea rsi, [rsp + PB_T]
    mov ecx, 32
    rep movsb
    mov rdi, rsp
    mov esi, PB_SIZE
    call wipe
    add rsp, PB_SIZE
    pop rbx
    ret
