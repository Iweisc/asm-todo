; WebSocket framing (RFC 6455), only what this app speaks: unfragmented
; binary messages plus ping, pong and close.

section .rodata
ws_guid:        db "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
ws_guid_len     equ $ - ws_guid

section .bss
ws_opcode:      resd 1
ws_payload:     resq 1
ws_payload_len: resq 1

section .text

; Sec-WebSocket-Accept for a key. rdi = key, rsi = key length, rdx = out (28 chars)
ws_accept_for:
    push rbx
    push r12
    push r13
    sub rsp, MD_CTX_SIZE + 32
    mov r12, rdi
    mov r13, rsi
    mov rbx, rdx
    mov rdi, rsp
    call sha1_init
    mov rdi, rsp
    mov rsi, r12
    mov rdx, r13
    call sha1_update
    mov rdi, rsp
    lea rsi, [ws_guid]
    mov edx, ws_guid_len
    call sha1_update
    mov rdi, rsp
    lea rsi, [rsp + MD_CTX_SIZE]
    call sha1_final
    mov rdi, rbx
    lea rsi, [rsp + MD_CTX_SIZE]
    mov edx, 20
    call put_base64
    add rsp, MD_CTX_SIZE + 32
    pop r13
    pop r12
    pop rbx
    ret

; Writes an unmasked frame header. rdi = dst, esi = opcode, edx = payload length
; -> rax = header length (2 or 4)
ws_header:
    or esi, 0x80                            ; FIN
    mov [rdi], sil
    cmp edx, 125
    ja .long
    mov [rdi + 1], dl
    mov eax, 2
    ret
.long:
    mov byte [rdi + 1], 126
    mov [rdi + 3], dl
    shr edx, 8
    mov [rdi + 2], dl
    mov eax, 4
    ret

; Writes a masked frame header, as clients must, and returns the mask key.
; rdi = dst, esi = opcode, edx = payload length
; -> rax = header length (6 or 8), ecx = mask key
ws_header_masked:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    call ws_header
    or byte [rbx + 1], 0x80
    mov r12, rax
    lea rdi, [rbx + rax]
    mov esi, 4
    call random_bytes
    mov ecx, [rbx + r12]
    lea rax, [r12 + 4]
    add rsp, 8
    pop r12
    pop rbx
    ret

; XORs the 4-byte mask over a payload, in place (masking and unmasking are the same).
; rdi = buf, rsi = len, edx = mask key
ws_mask:
    xor ecx, ecx
.loop:
    cmp rcx, rsi
    jae .done
    xor [rdi + rcx], dl
    ror edx, 8
    inc rcx
    jmp .loop
.done:
    ret

; Parses the frame at the start of buf and unmasks its payload in place.
; rdi = buf, rsi = bytes available, edx = 1 if frames must be masked (server side)
; -> rax = whole frame length, 0 if it isn't complete yet, -1 if it breaks the
;    rules. On success ws_opcode, ws_payload and ws_payload_len describe it.
ws_parse:
    push rbx
    mov rax, -1
    cmp rsi, 2
    jb .need_more
    movzx ecx, byte [rdi]
    test ecx, 0x70                          ; reserved bits
    jnz .done
    test ecx, 0x80                          ; we never fragment, so neither may the peer
    jz .done
    and ecx, 15
    mov [ws_opcode], ecx
    cmp ecx, WS_OP_BINARY
    je .opcode_ok
    cmp ecx, WS_OP_CLOSE
    jb .done
    cmp ecx, WS_OP_PONG
    ja .done
.opcode_ok:
    movzx ecx, byte [rdi + 1]
    mov r8d, ecx
    shr r8d, 7
    cmp r8d, edx
    jne .done                               ; wrong masking for this direction
    and ecx, 127
    mov r9d, 2                              ; header length so far
    cmp ecx, 126
    jb .short
    ja .done                                ; 64-bit lengths are beyond anything we accept
    cmp rsi, 4
    jb .need_more
    movzx ecx, byte [rdi + 2]
    shl ecx, 8
    mov cl, [rdi + 3]
    mov r9d, 4
.short:
    cmp dword [ws_opcode], WS_OP_CLOSE
    jb .size_ok
    cmp ecx, 125                            ; control frames stay small
    ja .done
.size_ok:
    cmp ecx, WS_MAX_PAYLOAD
    ja .done
    xor ebx, ebx                            ; mask key
    test edx, edx
    jz .no_mask
    lea r10, [r9 + 4]
    cmp rsi, r10
    jb .need_more
    mov ebx, [rdi + r9]
    mov r9, r10
.no_mask:
    lea rax, [r9 + rcx]                     ; full frame length
    cmp rsi, rax
    jb .need_more
    lea r10, [rdi + r9]
    mov [ws_payload], r10
    mov [ws_payload_len], rcx
    test edx, edx
    jz .done
    push rax
    mov rdi, r10
    mov rsi, rcx
    mov edx, ebx
    call ws_mask
    pop rax
    jmp .done
.need_more:
    xor eax, eax
.done:
    pop rbx
    ret
