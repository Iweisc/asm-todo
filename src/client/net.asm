; The connection to todo-server: non-blocking TCP, the WebSocket upgrade,
; the Noise handshake against the pinned server key, encrypted frames,
; keepalive pings and reconnecting with backoff.
;
;   OFF -> CONNECTING -> UPGRADE -> HANDSHAKE -> OPEN
;
; Anything unexpected drops back to OFF and a retry gets scheduled. The sync
; layer hears about it through sync_on_open, sync_on_message and sync_on_offline.

%define NET_OFF             0
%define NET_CONNECTING      1
%define NET_UPGRADE         2
%define NET_HANDSHAKE       3
%define NET_OPEN            4

%define NET_IN_SIZE         69632
%define NET_OUT_SIZE        131072
%define HTTP_REPLY_MAX      4096
%define CONNECT_TIMEOUT_MS  10000
%define PING_EVERY_MS       20000
%define DEAD_AFTER_MS       60000       ; the server answers pings, so silence this long means it's gone
%define RETRY_MIN_MS        1000
%define RETRY_MAX_MS        16000

section .rodata
net_req_head:       db "GET /sync HTTP/1.1", 13, 10
                    db "Host: todo", 13, 10
                    db "Upgrade: websocket", 13, 10
                    db "Connection: Upgrade", 13, 10
                    db "Sec-WebSocket-Version: 13", 13, 10
                    db "Sec-WebSocket-Key: "
net_req_head_len    equ $ - net_req_head
net_101:            db "HTTP/1.1 101 "
net_101_len         equ $ - net_101
h_accept:           db "sec-websocket-accept", 0
net_nodelay:        dd 1

section .data
net_fd:             dd -1
net_backoff:        dd RETRY_MIN_MS

section .bss
server_addr:        resb 16
server_key:         resb 32
net_state:          resb 1
net_in_len:         resd 1
net_out_len:        resd 1
net_out_pos:        resd 1
net_retry_at:       resq 1
net_deadline:       resq 1
net_ping_at:        resq 1
net_last_rx:        resq 1
net_accept:         resb 28
net_hs:             resb HS_SIZE
net_ciphers:        resb PAIR_SIZE
net_in:             resb NET_IN_SIZE
net_out:            resb NET_OUT_SIZE

section .text

net_connect:
    mov eax, SYS_socket
    mov edi, AF_INET
    mov esi, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC
    xor edx, edx
    syscall
    test eax, eax
    js net_drop
    mov [net_fd], eax
    mov eax, SYS_setsockopt
    mov edi, [net_fd]
    mov esi, IPPROTO_TCP
    mov edx, TCP_NODELAY
    lea r10, [net_nodelay]
    mov r8d, 4
    syscall
    mov dword [net_in_len], 0
    mov dword [net_out_len], 0
    mov dword [net_out_pos], 0
    mov byte [net_state], NET_CONNECTING
    call now_ms
    add rax, CONNECT_TIMEOUT_MS
    mov [net_deadline], rax
    mov eax, SYS_connect
    mov edi, [net_fd]
    lea rsi, [server_addr]
    mov edx, 16
    syscall
    test eax, eax
    jz net_connected
    cmp eax, -EINPROGRESS
    jne net_drop
    ret

; The TCP connect finished, one way or the other. Sends the upgrade request.
net_connected:
    sub rsp, 56                             ; SO_ERROR, raw key, base64 key
    mov dword [rsp + 4], 4
    mov eax, SYS_getsockopt
    mov edi, [net_fd]
    mov esi, SOL_SOCKET
    mov edx, SO_ERROR
    mov r10, rsp
    lea r8, [rsp + 4]
    syscall
    test eax, eax
    jnz .failed
    cmp dword [rsp], 0
    jne .failed
    lea rdi, [rsp + 8]
    mov esi, 16
    call random_bytes
    lea rdi, [rsp + 24]
    lea rsi, [rsp + 8]
    mov edx, 16
    call put_base64
    lea rdi, [rsp + 24]
    mov esi, 24
    lea rdx, [net_accept]
    call ws_accept_for
    lea rdi, [net_out]
    lea rsi, [net_req_head]
    mov edx, net_req_head_len
    call put_mem
    lea rsi, [rsp + 24]
    mov edx, 24
    call put_mem
    mov dword [rdi], 0x0A0D0A0D
    mov dword [net_out_len], net_req_head_len + 24 + 4
    mov byte [net_state], NET_UPGRADE
    add rsp, 56
    jmp net_flush
.failed:
    add rsp, 56
    jmp net_drop

; Gives up on the connection and schedules the next attempt.
net_drop:
    mov edi, [net_fd]
    test edi, edi
    js .closed
    mov eax, SYS_close
    syscall
    mov dword [net_fd], -1
.closed:
    lea rdi, [net_hs]
    mov esi, HS_SIZE + PAIR_SIZE            ; net_ciphers follows net_hs
    call wipe
    mov byte [net_state], NET_OFF
    call now_ms
    mov ecx, [net_backoff]
    add rax, rcx
    mov [net_retry_at], rax
    shl ecx, 1
    mov eax, RETRY_MAX_MS
    cmp ecx, eax
    cmova ecx, eax
    mov [net_backoff], ecx
    jmp sync_on_offline

; -> eax = milliseconds until the next retry, 0 if connected or connecting
net_retry_in:
    xor eax, eax
    cmp byte [net_state], NET_OFF
    jne .done
    call now_ms
    mov rcx, [net_retry_at]
    sub rcx, rax
    xor eax, eax
    test rcx, rcx
    cmovg rax, rcx
.done:
    ret

; Sends whatever is queued. A full socket just waits for POLLOUT.
net_flush:
.write:
    mov edx, [net_out_len]
    sub edx, [net_out_pos]
    jz .drained
    mov eax, SYS_write
    mov edi, [net_fd]
    mov esi, [net_out_pos]
    lea rcx, [net_out]
    add rsi, rcx
    syscall
    cmp rax, -EINTR
    je .write
    cmp rax, -EAGAIN
    je .done
    test rax, rax
    jle net_drop
    add [net_out_pos], eax
    jmp .write
.drained:
    mov dword [net_out_len], 0
    mov dword [net_out_pos], 0
.done:
    ret

; Makes room for rdx bytes at the end of the output buffer.
; -> rax = where to write them, or 0 if they won't fit
net_reserve:
    mov eax, [net_out_pos]
    test eax, eax
    jz .check
    push rdx
    lea rdi, [net_out]
    lea rsi, [net_out + rax]
    mov edx, [net_out_len]
    sub edx, eax
    mov [net_out_len], edx
    mov dword [net_out_pos], 0
    call memmove
    pop rdx
.check:
    mov eax, [net_out_len]
    add rdx, rax
    cmp rdx, NET_OUT_SIZE
    ja .full
    lea rax, [net_out + rax]
    ret
.full:
    xor eax, eax
    ret

; A masked frame with a plaintext payload. esi = opcode, rdx = payload, ecx = length
net_send_frame:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    lea edx, [ecx + 8]
    call net_reserve
    test rax, rax
    jz .overflow
    mov rbx, rax
    mov rdi, rbx
    mov esi, r12d
    mov edx, r14d
    call ws_header_masked
    lea rdi, [rbx + rax]
    add eax, r14d
    add [net_out_len], eax
    mov [rsp], ecx
    push rdi
    mov rsi, r13
    mov edx, r14d
    call put_mem
    pop rdi
    mov esi, r14d
    mov edx, [rsp]
    call ws_mask
    call net_flush
    jmp .done
.overflow:
    call net_drop
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Encrypts and sends an application message. rsi = message, edx = length
; -> eax = 1 if it went out, 0 if we're not connected
net_send:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    xor eax, eax
    cmp byte [net_state], NET_OPEN
    jne .done
    mov r12, rsi
    mov r13d, edx
    lea edx, [r13d + NOISE_TAG + 8]
    call net_reserve
    test rax, rax
    jz .overflow
    mov rbx, rax
    mov rdi, rbx
    mov esi, WS_OP_BINARY
    lea edx, [r13d + NOISE_TAG]
    call ws_header_masked
    mov [rsp], ecx
    lea r14, [rbx + rax]                    ; payload
    lea eax, [eax + r13d + NOISE_TAG]
    add [net_out_len], eax
    mov rdi, r14
    mov rsi, r12
    mov edx, r13d
    call put_mem
    lea rdi, [net_ciphers + PAIR_SEND]
    mov rsi, r14
    mov edx, r13d
    call noise_encrypt
    mov rdi, r14
    lea esi, [r13d + NOISE_TAG]
    mov edx, [rsp]
    call ws_mask
    call net_flush
    mov eax, 1
    jmp .done
.overflow:
    call net_drop
    xor eax, eax
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; edi = poll revents for the socket
net_io:
    cmp byte [net_state], NET_OFF           ; dropped since poll returned
    je .stale
    cmp byte [net_state], NET_CONNECTING
    jne .connected
    test edi, POLLOUT | POLLERR | POLLHUP
    jnz net_connected
.stale:
    ret
.connected:
    push rbx
    mov ebx, edi
    test ebx, POLLOUT
    jz .read
    call net_flush
.read:
    cmp byte [net_state], NET_OFF
    je .done
    test ebx, POLLIN | POLLERR | POLLHUP
    jz .done
    call net_readable
.done:
    pop rbx
    ret

net_readable:
.read:
    mov edx, NET_IN_SIZE
    sub edx, [net_in_len]
    jz .full
    mov eax, SYS_read
    mov edi, [net_fd]
    mov esi, [net_in_len]
    lea rcx, [net_in]
    add rsi, rcx
    syscall
    cmp rax, -EINTR
    je .read
    cmp rax, -EAGAIN
    je .process
    test rax, rax
    jle net_drop
    add [net_in_len], eax
    call now_ms
    mov [net_last_rx], rax
    jmp .read
.full:
    call net_process
    cmp byte [net_state], NET_OFF
    je .done
    cmp dword [net_in_len], NET_IN_SIZE
    jb .read
    jmp net_drop                            ; a frame bigger than we allow
.process:
    jmp net_process
.done:
    ret

; Handles the 101 response and every complete frame in the input buffer.
net_process:
    push rbx
    sub rsp, 48
.next:
    mov al, [net_state]
    cmp al, NET_UPGRADE
    je .upgrade
    cmp al, NET_HANDSHAKE
    jb .done
    lea rdi, [net_in]
    mov esi, [net_in_len]
    xor edx, edx                            ; server frames are never masked
    call ws_parse
    test rax, rax
    js .drop
    jz .done
    mov rbx, rax
    mov eax, [ws_opcode]
    cmp eax, WS_OP_PING
    je .ping
    cmp eax, WS_OP_CLOSE
    je .drop
    cmp eax, WS_OP_BINARY
    jne .consume
    cmp byte [net_state], NET_HANDSHAKE
    je .handshake

    mov rdx, [ws_payload_len]
    cmp rdx, NOISE_TAG + 1
    jb .drop
    lea rdi, [net_ciphers + PAIR_RECV]
    mov rsi, [ws_payload]
    call noise_decrypt
    test eax, eax
    jnz .drop
    mov rsi, [ws_payload]
    mov rdx, [ws_payload_len]
    sub rdx, NOISE_TAG
    call sync_on_message
    jmp .consume

.handshake:
    cmp qword [ws_payload_len], NOISE_MSG2_LEN
    jne .drop
    lea rdi, [net_hs]
    mov rsi, [ws_payload]
    lea rdx, [net_ciphers]
    call noise_client_msg2
    test eax, eax
    jnz .drop
    mov byte [net_state], NET_OPEN
    mov dword [net_backoff], RETRY_MIN_MS
    call now_ms
    add rax, PING_EVERY_MS
    mov [net_ping_at], rax
    call sync_on_open
    jmp .consume

.ping:
    mov esi, WS_OP_PONG
    mov rdx, [ws_payload]
    mov rcx, [ws_payload_len]
    call net_send_frame
.consume:
    cmp byte [net_state], NET_OFF           ; a handler may have dropped us
    je .done
    lea rdi, [net_in]
    lea rsi, [net_in + rbx]
    mov edx, [net_in_len]
    sub rdx, rbx
    mov [net_in_len], edx
    call memmove
    jmp .next

.upgrade:
    lea rdi, [net_in]
    mov esi, [net_in_len]
    call find_header_end
    test rax, rax
    jns .reply
    cmp dword [net_in_len], HTTP_REPLY_MAX
    jae .drop
    jmp .done
.reply:
    mov rbx, rax
    cmp rbx, net_101_len
    jb .drop
    lea rdi, [net_in]
    lea rsi, [net_101]
    mov edx, net_101_len
    call mem_eq
    test eax, eax
    jz .drop
    lea rdi, [net_in]
    mov rsi, rbx
    lea rdx, [h_accept]
    call find_header
    cmp edx, 28
    jne .drop
    mov rdi, rax
    lea rsi, [net_accept]
    mov edx, 28
    call mem_eq
    test eax, eax
    jz .drop
    lea rdi, [net_hs]
    lea rsi, [server_key]
    mov rdx, rsp
    call noise_client_msg1
    test eax, eax
    jnz .drop
    mov byte [net_state], NET_HANDSHAKE
    mov esi, WS_OP_BINARY
    mov rdx, rsp
    mov ecx, NOISE_MSG1_LEN
    call net_send_frame
    jmp .consume
.drop:
    call net_drop
.done:
    add rsp, 48
    pop rbx
    ret

; Timers: retries, connect timeouts, keepalive.
net_tick:
    call now_ms
    mov cl, [net_state]
    cmp cl, NET_OFF
    je .off
    cmp cl, NET_OPEN
    je .open
    cmp rax, [net_deadline]
    jae net_drop
    ret
.off:
    cmp rax, [net_retry_at]
    jae net_connect
    ret
.open:
    mov rcx, rax
    sub rcx, [net_last_rx]
    cmp rcx, DEAD_AFTER_MS
    jae net_drop
    cmp rax, [net_ping_at]
    jb .done
    add rax, PING_EVERY_MS
    mov [net_ping_at], rax
    mov esi, WS_OP_PING
    xor edx, edx
    xor ecx, ecx
    jmp net_send_frame
.done:
    ret

; -> eax = ms until net_tick has something to do
net_timeout:
    call now_ms
    mov cl, [net_state]
    mov rdx, [net_retry_at]
    cmp cl, NET_OFF
    je .until
    mov rdx, [net_ping_at]
    cmp cl, NET_OPEN
    je .until
    mov rdx, [net_deadline]
.until:
    sub rdx, rax
    xor eax, eax
    test rdx, rdx
    cmovg rax, rdx
    ret

; -> eax = the poll events to wait for on net_fd
net_poll_events:
    mov eax, POLLIN
    cmp byte [net_state], NET_CONNECTING
    je .out
    mov ecx, [net_out_len]
    cmp ecx, [net_out_pos]
    je .done
.out:
    or eax, POLLOUT
.done:
    ret
