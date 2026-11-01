; Connections: accept, the HTTP -> WebSocket upgrade, the Noise handshake,
; encrypted framing, buffered non-blocking writes and teardown.
;
; Every connection goes HTTP -> HANDSHAKE -> OPEN. CLOSING means "flush what's
; queued, then close". Closing is always deferred to conn_reap, so a handler
; can kill any connection (even the one it's serving) without pulling state
; out from under a loop.

%define C_FD            0
%define C_STATE         4               ; byte
%define C_FLAGS         5               ; byte
%define C_FAILS         6               ; byte, failed auth attempts
%define C_JOB_KIND      7               ; byte, which password job is running
%define C_IP            8
%define C_USER          12              ; 0 until authenticated
%define C_SESSION       16              ; session slot index
%define C_TEAM          20              ; subscribed team, 0 for none
%define C_IN_LEN        24
%define C_OUT_LEN       28
%define C_OUT_POS       32
%define C_JOB_USER      36              ; user row for a login job, -1 for an unknown name
%define C_DEADLINE      40              ; qword, ms. Must authenticate before this.
%define C_LAST_RX       48              ; qword, ms
%define C_CIPHERS       56              ; PAIR_SIZE
%define C_JOB_NAME_LEN  136
%define C_JOB_NAME      137
%define C_JOB_SALT      176
%define C_JOB           192             ; PB_SIZE
%define CONN_SIZE       512

fits C_CIPHERS, PAIR_SIZE, C_JOB_NAME_LEN
fits C_JOB_NAME, USERNAME_MAX, C_JOB_SALT
fits C_JOB_SALT, 16, C_JOB
fits C_JOB, PB_SIZE, CONN_SIZE

%define ST_FREE         0
%define ST_HTTP         1
%define ST_HANDSHAKE    2
%define ST_OPEN         3
%define ST_CLOSING      4

%define F_KILL          1
%define F_WANT_OUT      2
%define F_BUSY          4               ; waiting on a password job, input is held back

%define MAX_CONN        256
%define MAX_CONN_PER_IP 16
%define HTTP_MAX        8192
%define IN_SIZE         69632           ; the biggest frame plus slack
%define OUT_SIZE        262144

%define AUTH_TIMEOUT_MS     30000
%define IDLE_TIMEOUT_MS     90000
%define CLOSING_TIMEOUT_MS  5000

section .rodata
http_bad:           db "HTTP/1.1 400 Bad Request", 13, 10
                    db "Content-Length: 0", 13, 10
                    db "Connection: close", 13, 10, 13, 10
http_bad_len        equ $ - http_bad
http_switch:        db "HTTP/1.1 101 Switching Protocols", 13, 10
                    db "Upgrade: websocket", 13, 10
                    db "Connection: Upgrade", 13, 10
                    db "Sec-WebSocket-Accept: "
http_switch_len     equ $ - http_switch
http_request_line:  db "GET /sync HTTP/1.1", 13, 10
http_request_line_len equ $ - http_request_line
h_key:              db "sec-websocket-key", 0
h_version:          db "sec-websocket-version", 0
h_upgrade:          db "upgrade", 0
s_websocket:        db "websocket"
s_13:               db "13"
one:                dd 1

section .bss
now:                resq 1              ; monotonic ms, updated once per loop turn
epoll_fd:           resd 1
listen_fd:          resd 1
conns:              resb MAX_CONN * CONN_SIZE
conn_in:            resb MAX_CONN * IN_SIZE
conn_out:           resb MAX_CONN * OUT_SIZE
accept_addr:        resb 16
accept_addr_len:    resd 1

section .text

; edi = index -> rax = connection
conn_addr:
    mov eax, edi
    shl rax, 9                              ; * CONN_SIZE
    lea rcx, [conns]
    add rax, rcx
    ret

; edi = index -> rax = input buffer
conn_in_buf:
    mov eax, edi
    imul rax, rax, IN_SIZE
    lea rcx, [conn_in]
    add rax, rcx
    ret

; edi = index -> rax = output buffer
conn_out_buf:
    mov eax, edi
    imul rax, rax, OUT_SIZE
    lea rcx, [conn_out]
    add rax, rcx
    ret

update_now:
    call now_ms
    mov [now], rax
    ret

; -> rax = unix seconds
now_unix:
    sub rsp, 16
    mov eax, SYS_clock_gettime
    mov edi, CLOCK_REALTIME
    mov rsi, rsp
    syscall
    mov rax, [rsp]
    add rsp, 16
    ret

; edi = index
conn_kill:
    call conn_addr
    or byte [rax + C_FLAGS], F_KILL
    ret

conn_accept_all:
    push rbx
    push r12
    push r13
.next:
    mov dword [accept_addr_len], 16
    mov eax, SYS_accept4
    mov edi, [listen_fd]
    lea rsi, [accept_addr]
    lea rdx, [accept_addr_len]
    mov r10d, SOCK_NONBLOCK | SOCK_CLOEXEC
    syscall
    test eax, eax
    js .done
    mov ebx, eax
    mov r12d, [accept_addr + 4]             ; peer IPv4

    ; Find a free slot and count this address's connections on the way.
    mov r13d, -1
    xor ecx, ecx
    xor edx, edx                            ; connections from this IP
    lea rsi, [conns]
.scan:
    cmp byte [rsi + C_STATE], ST_FREE
    jne .used
    cmp r13d, -1
    jne .scan_next
    mov r13d, ecx
    jmp .scan_next
.used:
    cmp [rsi + C_IP], r12d
    jne .scan_next
    inc edx
.scan_next:
    add rsi, CONN_SIZE
    inc ecx
    cmp ecx, MAX_CONN
    jb .scan
    cmp r13d, -1
    je .reject
    cmp edx, MAX_CONN_PER_IP
    jae .reject

    mov edi, r13d
    call conn_addr
    mov rdi, rax
    push rdi
    mov esi, CONN_SIZE
    call wipe
    pop rdi
    mov [rdi + C_FD], ebx
    mov byte [rdi + C_STATE], ST_HTTP
    mov [rdi + C_IP], r12d
    mov rax, [now]
    mov [rdi + C_LAST_RX], rax
    add rax, AUTH_TIMEOUT_MS
    mov [rdi + C_DEADLINE], rax

    mov eax, SYS_setsockopt                 ; small messages, send them right away
    mov edi, ebx
    mov esi, IPPROTO_TCP
    mov edx, TCP_NODELAY
    lea r10, [one]
    mov r8d, 4
    syscall

    sub rsp, 16                             ; struct epoll_event, packed: u32 events, u64 data
    mov dword [rsp], EPOLLIN
    lea eax, [r13d + 1]
    mov [rsp + 4], rax
    mov eax, SYS_epoll_ctl
    mov edi, [epoll_fd]
    mov esi, EPOLL_CTL_ADD
    mov edx, ebx
    mov r10, rsp
    syscall
    add rsp, 16
    jmp .next
.reject:
    mov eax, SYS_close
    mov edi, ebx
    syscall
    jmp .next
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Reads whatever is waiting, then processes it. edi = index
conn_readable:
    push rbx
    push r12
    push r13
    mov ebx, edi
    call conn_addr
    mov r12, rax
    test byte [r12 + C_FLAGS], F_KILL | F_BUSY
    jnz .done
    mov edi, ebx
    call conn_in_buf
    mov r13, rax
.read:
    mov edx, IN_SIZE
    sub edx, [r12 + C_IN_LEN]
    jz .process
    cmp byte [r12 + C_STATE], ST_CLOSING
    jne .into_buffer
    mov edx, IN_SIZE                        ; closing: read and throw away
    mov dword [r12 + C_IN_LEN], 0
.into_buffer:
    mov eax, SYS_read
    mov edi, [r12 + C_FD]
    mov esi, [r12 + C_IN_LEN]
    add rsi, r13
    syscall
    cmp rax, -EINTR
    je .read
    cmp rax, -EAGAIN
    je .process
    test rax, rax
    jle .kill                               ; EOF or error
    add [r12 + C_IN_LEN], eax
    mov rcx, [now]
    mov [r12 + C_LAST_RX], rcx
    jmp .read
.process:
    mov edi, ebx
    call conn_process
    jmp .done
.kill:
    or byte [r12 + C_FLAGS], F_KILL
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Handles every complete request or frame in the input buffer. edi = index
conn_process:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    call conn_addr
    mov r12, rax
    mov edi, ebx
    call conn_in_buf
    mov r13, rax
.next:
    test byte [r12 + C_FLAGS], F_KILL | F_BUSY
    jnz .done
    mov al, [r12 + C_STATE]
    cmp al, ST_HTTP
    je .http
    cmp al, ST_CLOSING
    je .done

    mov rdi, r13
    mov esi, [r12 + C_IN_LEN]
    mov edx, 1                              ; client frames must be masked
    call ws_parse
    test rax, rax
    js .kill
    jz .incomplete
    mov r14, rax                            ; frame length, consumed below
    mov eax, [ws_opcode]
    cmp eax, WS_OP_PING
    je .ping
    cmp eax, WS_OP_CLOSE
    je .close
    cmp eax, WS_OP_BINARY
    jne .consume                            ; pong
    cmp byte [r12 + C_STATE], ST_HANDSHAKE
    je .handshake

    ; An encrypted application message.
    mov rdx, [ws_payload_len]
    cmp rdx, NOISE_TAG + 1
    jb .kill
    lea rdi, [r12 + C_CIPHERS + PAIR_RECV]
    mov rsi, [ws_payload]
    call noise_decrypt
    test eax, eax
    jnz .kill                               ; forged, replayed or reordered
    mov edi, ebx
    mov rsi, [ws_payload]
    mov rdx, [ws_payload_len]
    sub rdx, NOISE_TAG
    call handle_message
    mov rdi, [ws_payload]                   ; it may have held a password
    mov rsi, [ws_payload_len]
    call wipe
    jmp .consume

.handshake:
    cmp qword [ws_payload_len], NOISE_MSG1_LEN
    jne .kill
    sub rsp, 64                             ; msg2 + handshake state below it
    sub rsp, HS_SIZE + 8
    mov rdi, rsp
    lea rsi, [server_keys]
    mov rdx, [ws_payload]
    lea rcx, [rsp + HS_SIZE + 8]
    lea r8, [r12 + C_CIPHERS]
    call noise_server_respond
    mov r15d, eax
    add rsp, HS_SIZE + 8
    test r15d, r15d
    jnz .handshake_failed
    mov edi, ebx
    mov esi, WS_OP_BINARY
    mov rdx, rsp
    mov ecx, NOISE_MSG2_LEN
    call send_frame
    add rsp, 64
    mov byte [r12 + C_STATE], ST_OPEN
    jmp .consume
.handshake_failed:
    add rsp, 64
    jmp .kill

.ping:
    mov edi, ebx
    mov esi, WS_OP_PONG
    mov rdx, [ws_payload]
    mov rcx, [ws_payload_len]
    call send_frame
    jmp .consume
.close:
    mov edi, ebx
    mov esi, WS_OP_CLOSE
    xor edx, edx
    xor ecx, ecx
    call send_frame
    mov byte [r12 + C_STATE], ST_CLOSING
    mov rax, [now]
    add rax, CLOSING_TIMEOUT_MS
    mov [r12 + C_DEADLINE], rax
.consume:
    mov rdi, r13
    lea rsi, [r13 + r14]
    mov edx, [r12 + C_IN_LEN]
    sub rdx, r14
    mov [r12 + C_IN_LEN], edx
    call memmove
    jmp .next

.http:
    mov edi, ebx
    call http_upgrade
    test eax, eax
    jnz .next
.incomplete:
    cmp dword [r12 + C_IN_LEN], IN_SIZE
    jb .done
.kill:
    or byte [r12 + C_FLAGS], F_KILL
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi = haystack, esi = its length, rdx = lowercase needle, ecx = its length
; -> eax = 1 if the needle appears, ignoring ASCII case
contains_ci:
    xor r8d, r8d
.start:
    mov eax, esi
    sub eax, r8d
    cmp eax, ecx
    jb .no
    xor r9d, r9d
.cmp:
    cmp r9d, ecx
    jae .yes
    lea r10d, [r8d + r9d]
    movzx eax, byte [rdi + r10]
    lea r11d, [eax - 'A']
    cmp r11d, 'Z' - 'A'
    ja .lower
    add eax, 32
.lower:
    cmp al, [rdx + r9]
    jne .advance
    inc r9d
    jmp .cmp
.advance:
    inc r8d
    jmp .start
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; Handles the HTTP upgrade request. edi = index
; -> eax = 1 if it was handled (switched or refused), 0 if more bytes are needed
http_upgrade:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48
    mov ebx, edi
    call conn_addr
    mov r12, rax
    mov edi, ebx
    call conn_in_buf
    mov r13, rax
    mov rdi, r13
    mov esi, [r12 + C_IN_LEN]
    call find_header_end
    test rax, rax
    jns .complete
    xor eax, eax
    cmp dword [r12 + C_IN_LEN], HTTP_MAX
    jb .out
    jmp .refuse
.complete:
    mov r14, rax                            ; header length
    cmp r14, HTTP_MAX
    ja .refuse
    cmp r14, http_request_line_len
    jb .refuse
    mov rdi, r13
    lea rsi, [http_request_line]
    mov edx, http_request_line_len
    call mem_eq
    test eax, eax
    jz .refuse

    mov rdi, r13
    mov rsi, r14
    lea rdx, [h_version]
    call find_header
    cmp edx, 2
    jne .refuse
    mov rdi, rax
    lea rsi, [s_13]
    mov edx, 2
    call mem_eq
    test eax, eax
    jz .refuse

    mov rdi, r13
    mov rsi, r14
    lea rdx, [h_upgrade]
    call find_header
    test rax, rax
    jz .refuse
    mov rdi, rax
    mov esi, edx
    lea rdx, [s_websocket]
    mov ecx, 9
    call contains_ci
    test eax, eax
    jz .refuse

    mov rdi, r13
    mov rsi, r14
    lea rdx, [h_key]
    call find_header
    cmp edx, 24                             ; base64 of 16 bytes
    jne .refuse
    mov rdi, rax
    mov esi, 24
    mov rdx, rsp
    call ws_accept_for

    ; Build the 101 response in the output buffer directly.
    mov edi, ebx
    call conn_out_buf
    mov edi, [r12 + C_OUT_LEN]
    add rdi, rax
    lea rsi, [http_switch]
    mov edx, http_switch_len
    call put_mem
    mov rsi, rsp
    mov edx, 28
    call put_mem
    mov dword [rdi], 0x0A0D0A0D
    add dword [r12 + C_OUT_LEN], http_switch_len + 28 + 4
    mov byte [r12 + C_STATE], ST_HANDSHAKE

    mov rdi, r13                            ; drop the request, keep anything after it
    lea rsi, [r13 + r14]
    mov edx, [r12 + C_IN_LEN]
    sub rdx, r14
    mov [r12 + C_IN_LEN], edx
    call memmove
    mov edi, ebx
    call conn_flush
    mov eax, 1
    jmp .out
.refuse:
    mov edi, ebx
    call conn_out_buf
    mov edi, [r12 + C_OUT_LEN]
    add rdi, rax
    lea rsi, [http_bad]
    mov edx, http_bad_len
    call put_mem
    add dword [r12 + C_OUT_LEN], http_bad_len
    mov byte [r12 + C_STATE], ST_CLOSING
    mov rax, [now]
    add rax, CLOSING_TIMEOUT_MS
    mov [r12 + C_DEADLINE], rax
    mov edi, ebx
    call conn_flush
    mov eax, 1
.out:
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Queues an unencrypted frame (handshake reply and control frames).
; edi = index, esi = opcode, rdx = payload, ecx = length
send_frame:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r13d, esi
    mov r14, rdx
    mov r15d, ecx
    call conn_addr
    mov r12, rax
    mov eax, [r12 + C_OUT_LEN]
    add eax, r15d
    add eax, 4
    cmp eax, OUT_SIZE
    ja .overflow
    mov edi, ebx
    call conn_out_buf
    mov edi, [r12 + C_OUT_LEN]
    add rdi, rax
    push rdi
    mov esi, r13d
    mov edx, r15d
    call ws_header
    pop rdi
    add rdi, rax
    add [r12 + C_OUT_LEN], eax
    mov rsi, r14
    mov edx, r15d
    call put_mem
    add [r12 + C_OUT_LEN], r15d
    mov edi, ebx
    call conn_flush
    jmp .done
.overflow:
    or byte [r12 + C_FLAGS], F_KILL
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Queues an encrypted application message. A peer too slow to drain its
; buffer gets disconnected rather than buffered without bound.
; edi = index, rsi = message, edx = length
send_msg:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r13, rsi
    mov r14d, edx
    call conn_addr
    mov r12, rax
    cmp byte [r12 + C_STATE], ST_OPEN
    jne .done
    test byte [r12 + C_FLAGS], F_KILL
    jnz .done
    mov eax, [r12 + C_OUT_LEN]
    lea eax, [eax + r14d + NOISE_TAG + 4]
    cmp eax, OUT_SIZE
    ja .overflow
    mov edi, ebx
    call conn_out_buf
    mov edi, [r12 + C_OUT_LEN]
    add rdi, rax
    mov r15, rdi
    mov esi, WS_OP_BINARY
    lea edx, [r14d + NOISE_TAG]
    call ws_header
    add r15, rax                            ; payload goes right after the header
    lea ecx, [eax + r14d + NOISE_TAG]
    add [r12 + C_OUT_LEN], ecx
    mov rdi, r15
    mov rsi, r13
    mov edx, r14d
    call put_mem
    lea rdi, [r12 + C_CIPHERS + PAIR_SEND]
    mov rsi, r15
    mov edx, r14d
    call noise_encrypt
    mov edi, ebx
    call conn_flush
    jmp .done
.overflow:
    or byte [r12 + C_FLAGS], F_KILL
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Writes as much queued output as the socket takes, and asks epoll for
; EPOLLOUT only while something is left. edi = index
conn_flush:
    push rbx
    push r12
    push r13
    mov ebx, edi
    call conn_addr
    mov r12, rax
    test byte [r12 + C_FLAGS], F_KILL
    jnz .done
    mov edi, ebx
    call conn_out_buf
    mov r13, rax
.write:
    mov edx, [r12 + C_OUT_LEN]
    sub edx, [r12 + C_OUT_POS]
    jz .drained
    mov eax, SYS_write
    mov edi, [r12 + C_FD]
    mov esi, [r12 + C_OUT_POS]
    add rsi, r13
    syscall
    cmp rax, -EINTR
    je .write
    cmp rax, -EAGAIN
    je .blocked
    test rax, rax
    jle .kill
    add [r12 + C_OUT_POS], eax
    jmp .write
.drained:
    mov dword [r12 + C_OUT_LEN], 0
    mov dword [r12 + C_OUT_POS], 0
    test byte [r12 + C_FLAGS], F_WANT_OUT
    jz .done
    and byte [r12 + C_FLAGS], ~F_WANT_OUT
    mov esi, EPOLLIN
    jmp .ctl
.blocked:
    ; Slide the unsent part to the front so the buffer doesn't creep.
    mov rdi, r13
    mov esi, [r12 + C_OUT_POS]
    add rsi, r13
    mov edx, [r12 + C_OUT_LEN]
    sub edx, [r12 + C_OUT_POS]
    mov [r12 + C_OUT_LEN], edx
    mov dword [r12 + C_OUT_POS], 0
    call memmove
    test byte [r12 + C_FLAGS], F_WANT_OUT
    jnz .done
    or byte [r12 + C_FLAGS], F_WANT_OUT
    mov esi, EPOLLIN | EPOLLOUT
.ctl:
    sub rsp, 16
    mov [rsp], esi
    lea eax, [ebx + 1]
    mov [rsp + 4], rax
    mov eax, SYS_epoll_ctl
    mov edi, [epoll_fd]
    mov esi, EPOLL_CTL_MOD
    mov edx, [r12 + C_FD]
    mov r10, rsp
    syscall
    add rsp, 16
    jmp .done
.kill:
    or byte [r12 + C_FLAGS], F_KILL
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Closes killed connections, finished CLOSING ones, and anything past its
; deadline or idle for too long.
conn_reap:
    push rbx
    push r12
    sub rsp, 8
    xor ebx, ebx
.loop:
    mov edi, ebx
    call conn_addr
    mov r12, rax
    mov al, [r12 + C_STATE]
    cmp al, ST_FREE
    je .next
    test byte [r12 + C_FLAGS], F_KILL
    jnz .close
    mov rax, [now]
    mov rcx, [r12 + C_DEADLINE]
    test rcx, rcx
    jz .idle
    cmp rax, rcx
    jae .close
.idle:
    sub rax, [r12 + C_LAST_RX]
    cmp rax, IDLE_TIMEOUT_MS
    jae .close
    cmp byte [r12 + C_STATE], ST_CLOSING
    jne .next
    mov eax, [r12 + C_OUT_LEN]
    test eax, eax
    jnz .next
.close:
    mov edi, ebx
    call conn_close
.next:
    inc ebx
    cmp ebx, MAX_CONN
    jb .loop
    add rsp, 8
    pop r12
    pop rbx
    ret

; edi = index
conn_close:
    push rbx
    push r12
    push r13
    mov ebx, edi
    call conn_addr
    mov r12, rax
    mov eax, SYS_close                      ; also drops it from epoll
    mov edi, [r12 + C_FD]
    syscall
    test byte [r12 + C_FLAGS], F_BUSY
    jz .not_busy
    dec dword [jobs_pending]
.not_busy:
    mov r13d, [r12 + C_TEAM]
    mov rdi, r12
    mov esi, CONN_SIZE                      ; keys and any half-hashed password go too
    call wipe
    mov dword [r12 + C_FD], -1
    test r13d, r13d
    jz .done
    mov edi, r13d                           ; they've gone offline for everyone else
    call broadcast_members
.done:
    pop r13
    pop r12
    pop rbx
    ret
