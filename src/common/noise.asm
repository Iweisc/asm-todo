; Noise_NK_25519_ChaChaPoly_SHA256 (Noise spec revision 34).
;
;   <- s                    the client already knows the server's static key
;   ...
;   -> e, es                msg1
;   <- e, ee                msg2
;
; NK authenticates the server and gives forward secrecy. The client stays
; anonymous at this layer and proves who it is with a password or session
; token inside the encrypted channel. Both handshake payloads are empty.

%define CS_KEY      0
%define CS_N        32
%define CS_SIZE     40

; A pair of cipher states, the way callers keep them.
%define PAIR_SEND   0
%define PAIR_RECV   CS_SIZE
%define PAIR_SIZE   (CS_SIZE * 2)

%define HS_CK       0
%define HS_H        32
%define HS_K        64
%define HS_N        96
%define HS_E_PRIV   104
%define HS_E_PUB    136
%define HS_RE       168
%define HS_DH       200
%define HS_SIZE     232

section .rodata
noise_protocol_name:    db "Noise_NK_25519_ChaChaPoly_SHA256"   ; exactly 32 bytes, used as-is
noise_prologue:         db "asm-todo sync v1"
noise_prologue_len      equ $ - noise_prologue

section .text

; rdi = hs, rsi = data, rdx = len. h = SHA256(h || data)
noise_mix_hash:
    push rbx
    push r12
    push r13
    sub rsp, MD_CTX_SIZE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rsp
    call sha256_init
    mov rdi, rsp
    lea rsi, [rbx + HS_H]
    mov edx, 32
    call sha256_update
    mov rdi, rsp
    mov rsi, r12
    mov rdx, r13
    call sha256_update
    mov rdi, rsp
    lea rsi, [rbx + HS_H]
    call sha256_final
    add rsp, MD_CTX_SIZE
    pop r13
    pop r12
    pop rbx
    ret

; Mixes hs.dh into the chaining key and sets a fresh handshake key. rdi = hs
noise_mix_key:
    push rbx
    mov rbx, rdi
    lea rsi, [rdi + HS_DH]
    mov edx, 32
    lea rcx, [rdi + HS_CK]
    lea r8, [rdi + HS_K]
    call hkdf2
    mov qword [rbx + HS_N], 0
    pop rbx
    ret

; Encrypts an empty payload, which is just a tag, and hashes it.
; rdi = hs, rsi = out (16)
noise_encrypt_empty:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rbx + HS_K]
    mov rsi, [rbx + HS_N]
    lea rdx, [rbx + HS_H]
    mov ecx, 32
    mov r8, r12
    xor r9d, r9d
    call aead_seal
    inc qword [rbx + HS_N]
    mov rdi, rbx
    mov rsi, r12
    mov edx, 16
    call noise_mix_hash
    add rsp, 8
    pop r12
    pop rbx
    ret

; Checks an empty payload's tag and hashes it. rdi = hs, rsi = tag (16) -> eax = 0 / -1
noise_decrypt_empty:
    push rbx
    push r12
    sub rsp, 24
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsp                            ; the tag gets hashed as it arrived
    mov ecx, 16
    rep movsb
    lea rdi, [rbx + HS_K]
    mov rsi, [rbx + HS_N]
    lea rdx, [rbx + HS_H]
    mov ecx, 32
    mov r8, r12
    mov r9d, 16
    call aead_open
    test eax, eax
    jnz .done
    inc qword [rbx + HS_N]
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 16
    call noise_mix_hash
    xor eax, eax
.done:
    add rsp, 24
    pop r12
    pop rbx
    ret

; rdi = hs, rsi = server static public key
noise_init:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rbx + HS_CK]                  ; ck = h = protocol name
    lea rsi, [noise_protocol_name]
    mov ecx, 32
    rep movsb
    lea rdi, [rbx + HS_H]
    lea rsi, [noise_protocol_name]
    mov ecx, 32
    rep movsb
    mov rdi, rbx
    lea rsi, [noise_prologue]
    mov edx, noise_prologue_len
    call noise_mix_hash
    mov rdi, rbx
    mov rsi, r12
    mov edx, 32
    call noise_mix_hash
    add rsp, 8
    pop r12
    pop rbx
    ret

; Fresh ephemeral key pair into hs, and e.pub hashed in. rdi = hs
noise_new_ephemeral:
    push rbx
    mov rbx, rdi
    lea rdi, [rbx + HS_E_PRIV]
    mov esi, 32
    call random_bytes
    lea rdi, [rbx + HS_E_PUB]
    lea rsi, [rbx + HS_E_PRIV]
    call x25519_public
    mov rdi, rbx
    lea rsi, [rbx + HS_E_PUB]
    mov edx, 32
    call noise_mix_hash
    pop rbx
    ret

; Derives both transport keys. rdi = hs, rsi = first cipher state, rdx = second
noise_split:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea rdi, [rbx + HS_CK]
    mov rsi, rbx                            ; any pointer, the input is empty
    xor edx, edx
    lea rcx, [r12 + CS_KEY]
    lea r8, [r13 + CS_KEY]
    call hkdf2
    mov qword [r12 + CS_N], 0
    mov qword [r13 + CS_N], 0
    mov rdi, rbx
    mov esi, HS_SIZE
    call wipe
    pop r13
    pop r12
    pop rbx
    ret

; Client, first message. rdi = hs, rsi = server public key, rdx = out (48)
; -> eax = 0, or -1 if the server key is a bad point
noise_client_msg1:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call noise_init
    mov rdi, rbx
    call noise_new_ephemeral
    mov rdi, r13
    lea rsi, [rbx + HS_E_PUB]
    mov ecx, 32
    rep movsb
    lea rdi, [rbx + HS_DH]                  ; es
    lea rsi, [rbx + HS_E_PRIV]
    mov rdx, r12
    call x25519
    test eax, eax
    jnz .done
    mov rdi, rbx
    call noise_mix_key
    mov rdi, rbx
    lea rsi, [r13 + 32]
    call noise_encrypt_empty
    xor eax, eax
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Client, reads the reply and derives the transport keys.
; rdi = hs, rsi = msg2 (48), rdx = cipher pair -> eax = 0 / -1
noise_client_msg2:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea rdi, [rbx + HS_RE]
    mov ecx, 32
    rep movsb
    mov rdi, rbx
    lea rsi, [rbx + HS_RE]
    mov edx, 32
    call noise_mix_hash
    lea rdi, [rbx + HS_DH]                  ; ee
    lea rsi, [rbx + HS_E_PRIV]
    lea rdx, [rbx + HS_RE]
    call x25519
    test eax, eax
    jnz .fail
    mov rdi, rbx
    call noise_mix_key
    mov rdi, rbx
    lea rsi, [r12 + 32]
    call noise_decrypt_empty
    test eax, eax
    jnz .fail
    mov rdi, rbx
    lea rsi, [r13 + PAIR_SEND]
    lea rdx, [r13 + PAIR_RECV]
    call noise_split
    xor eax, eax
    jmp .done
.fail:
    mov rdi, rbx
    mov esi, HS_SIZE
    call wipe
    mov eax, -1
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Server, reads msg1 and writes msg2.
; rdi = hs, rsi = static keys (private 32 || public 32), rdx = msg1 (48),
; rcx = out msg2 (48), r8 = cipher pair -> eax = 0 / -1
noise_server_respond:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov rbp, rsi
    mov r12, rdx
    mov r13, rcx
    mov r14, r8
    lea rsi, [rbp + 32]
    call noise_init
    lea rdi, [rbx + HS_RE]
    mov rsi, r12
    mov ecx, 32
    rep movsb
    mov rdi, rbx
    lea rsi, [rbx + HS_RE]
    mov edx, 32
    call noise_mix_hash
    lea rdi, [rbx + HS_DH]                  ; es, from our side
    mov rsi, rbp
    lea rdx, [rbx + HS_RE]
    call x25519
    test eax, eax
    jnz .fail
    mov rdi, rbx
    call noise_mix_key
    mov rdi, rbx
    lea rsi, [r12 + 32]
    call noise_decrypt_empty
    test eax, eax
    jnz .fail

    mov rdi, rbx
    call noise_new_ephemeral
    mov rdi, r13
    lea rsi, [rbx + HS_E_PUB]
    mov ecx, 32
    rep movsb
    lea rdi, [rbx + HS_DH]                  ; ee
    lea rsi, [rbx + HS_E_PRIV]
    lea rdx, [rbx + HS_RE]
    call x25519
    test eax, eax
    jnz .fail
    mov rdi, rbx
    call noise_mix_key
    mov rdi, rbx
    lea rsi, [r13 + 32]
    call noise_encrypt_empty
    ; The initiator's first cipher state is the responder's receiving one.
    mov rdi, rbx
    lea rsi, [r14 + PAIR_RECV]
    lea rdx, [r14 + PAIR_SEND]
    call noise_split
    xor eax, eax
    jmp .done
.fail:
    mov rdi, rbx
    mov esi, HS_SIZE
    call wipe
    mov eax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Transport encryption, in place. rdi = cipher state, rsi = buf, rdx = len (tag appended)
noise_encrypt:
    push rbx
    mov rbx, rdi
    mov r8, rsi
    mov r9, rdx
    lea rdi, [rbx + CS_KEY]
    mov rsi, [rbx + CS_N]
    xor edx, edx
    xor ecx, ecx
    call aead_seal
    inc qword [rbx + CS_N]
    pop rbx
    ret

; rdi = cipher state, rsi = buf, rdx = len including the tag -> eax = 0 / -1
noise_decrypt:
    push rbx
    mov rbx, rdi
    mov r8, rsi
    mov r9, rdx
    lea rdi, [rbx + CS_KEY]
    mov rsi, [rbx + CS_N]
    xor edx, edx
    xor ecx, ecx
    call aead_open
    test eax, eax
    jnz .done
    inc qword [rbx + CS_N]
.done:
    pop rbx
    ret
