; todo-server: accounts, teams, live-synced issue tracking and team chat
; over WebSocket, with every message inside a Noise_NK channel.
;
; Usage: todo-server [database-path] [ip:port]
;        defaults: ./issues.db and 127.0.0.1:8080
;
; The server's public key is printed at startup and written to
; <database-path>.pub. Clients need it to connect.

default rel
bits 64

%include "sys.inc"
%include "config.inc"
%include "macros.inc"

%define MAX_EVENTS      64
%define IDLE_WAIT_MS    500

section .rodata
default_db_path:    db "issues.db", 0
default_addr:       db "127.0.0.1:8080", 0
s_listening:        db "todo-server: listening on ", 0
s_key:              db ", server key ", 0
msg_usage:          db "usage: todo-server [database-path] [ip:port]", 10, 0
msg_listen_failed:  db "todo-server: can't listen on that address (is it already running?)", 10, 0

section .bss
listen_addr:        resb 16
events:             resb MAX_EVENTS * 12

section .text
global _start

%include "util.asm"
%include "crypto/sha.asm"
%include "crypto/hmac.asm"
%include "crypto/chacha.asm"
%include "crypto/x25519.asm"
%include "noise.asm"
%include "ws.asm"
%include "wire.asm"
%include "mention.asm"
%include "db.asm"
%include "conn.asm"
%include "handlers.asm"
%include "password.asm"
%include "channels.asm"
%include "teams.asm"
%include "issues.asm"
%include "messages.asm"
%include "images.asm"

_start:
    call ignore_sigpipe
    mov rbx, rsp
    cmp qword [rbx], 3
    ja .usage
    lea rdi, [default_db_path]
    cmp qword [rbx], 2
    jb .have_db
    mov rdi, [rbx + 16]
.have_db:
    lea r12, [default_addr]
    cmp qword [rbx], 3
    jb .have_addr
    mov r12, [rbx + 24]
.have_addr:
    push rdi
    mov rdi, r12
    lea rsi, [listen_addr]
    call parse_addr
    pop rdi
    test eax, eax
    jz .usage
    call db_load
    call write_pub_file
    call listen_on
    call announce
    call update_now
    jmp event_loop
.usage:
    lea rdi, [msg_usage]
    call print_err
    mov edi, 2
    call exit

; "todo-server: listening on <addr>, server key <hex>". r12 = address string
announce:
    sub rsp, 200
    mov rdi, rsp
    lea rsi, [s_listening]
    call put_cstr
    mov rsi, r12
    call put_cstr
    lea rsi, [s_key]
    call put_cstr
    lea rsi, [server_pub]
    mov edx, 32
    call put_hex
    mov byte [rdi], 10
    mov byte [rdi + 1], 0
    mov rdi, rsp
    call print_err
    add rsp, 200
    ret

listen_on:
    mov eax, SYS_socket
    mov edi, AF_INET
    mov esi, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK
    xor edx, edx
    syscall
    test eax, eax
    js .failed
    mov [listen_fd], eax
    mov eax, SYS_setsockopt
    mov edi, [listen_fd]
    mov esi, SOL_SOCKET
    mov edx, SO_REUSEADDR
    lea r10, [one]
    mov r8d, 4
    syscall
    mov eax, SYS_bind
    mov edi, [listen_fd]
    lea rsi, [listen_addr]
    mov edx, 16
    syscall
    test eax, eax
    jnz .failed
    mov eax, SYS_listen
    mov edi, [listen_fd]
    mov esi, 128
    syscall
    test eax, eax
    jnz .failed

    mov eax, SYS_epoll_create1
    xor edi, edi
    syscall
    test eax, eax
    js .failed
    mov [epoll_fd], eax
    sub rsp, 16
    mov dword [rsp], EPOLLIN
    mov qword [rsp + 4], 0                  ; data 0 is the listening socket
    mov eax, SYS_epoll_ctl
    mov edi, [epoll_fd]
    mov esi, EPOLL_CTL_ADD
    mov edx, [listen_fd]
    mov r10, rsp
    syscall
    add rsp, 16
    test eax, eax
    jnz .failed
    ret
.failed:
    lea rdi, [msg_listen_failed]
    call print_err
    mov edi, 1
    call exit

; Password hashing runs between events in slices, so while any is waiting
; epoll only polls instead of sleeping.
event_loop:
    mov r10d, IDLE_WAIT_MS
    xor eax, eax
    cmp dword [jobs_pending], 0
    cmovne r10d, eax
    mov eax, SYS_epoll_wait
    mov edi, [epoll_fd]
    lea rsi, [events]
    mov edx, MAX_EVENTS
    syscall
    mov r12d, eax
    call update_now
    xor ebx, ebx
.event:
    cmp ebx, r12d
    jge .events_done
    imul eax, ebx, 12
    lea r13, [events + rax]
    inc ebx
    mov rax, [r13 + 4]
    test rax, rax
    jnz .connection
    call conn_accept_all
    jmp .event
.connection:
    lea r14d, [eax - 1]
    test dword [r13], EPOLLOUT
    jz .read
    mov edi, r14d
    call conn_flush
.read:
    test dword [r13], EPOLLIN | EPOLLERR | EPOLLHUP
    jz .event
    mov edi, r14d
    call conn_readable
    jmp .event
.events_done:
    cmp dword [jobs_pending], 0
    je .reap
    call run_jobs
.reap:
    call conn_reap
    jmp event_loop
