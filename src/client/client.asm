; todo-client: the desktop window for a team's issue tracker.
;
; Usage: todo-client <server-key> [ip:port]     (defaults to 127.0.0.1:8080)
;
; <server-key> is the 64 hex characters todo-server prints at startup. The
; client refuses to talk to anything that can't prove it holds that key.
;
; It talks Wayland directly over the compositor socket, draws every pixel
; itself into shared memory, and keeps one encrypted WebSocket to the server.

default rel
bits 64

%include "sys.inc"
%include "config.inc"
%include "macros.inc"

section .rodata
default_server:     db "127.0.0.1:8080", 0
msg_usage:          db "usage: todo-client <server-key> [ip:port]", 10
                    db "  <server-key> is the 64 hex characters todo-server prints at startup", 10, 0
msg_bad_key:        db "todo-client: the server key must be 64 hex characters", 10, 0
msg_bad_addr:       db "todo-client: the server address must look like 127.0.0.1:8080", 10, 0

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
%include "font.asm"
%include "draw.asm"
%include "text.asm"
%include "icons.asm"
%include "wayland.asm"
%include "net.asm"
%include "sync.asm"
%include "ui.asm"
%include "input.asm"
%include "widgets.asm"
%include "views.asm"

section .text

_start:
    call ignore_sigpipe
    mov rbx, rsp
    mov rax, [rbx]                          ; argc
    cmp rax, 2
    jb .usage
    cmp rax, 3
    ja .usage

    mov rdi, [rbx + 16]                     ; argv[1]: the server's public key
    call strlen
    cmp rax, 64
    jne .bad_key
    lea rdi, [server_key]
    mov rsi, [rbx + 16]
    mov edx, 32
    call parse_hex
    test eax, eax
    jz .bad_key

    lea rdi, [default_server]
    cmp qword [rbx], 3
    jb .have_addr
    mov rdi, [rbx + 24]
.have_addr:
    mov [server_label], rdi
    lea rsi, [server_addr]
    call parse_addr
    test eax, eax
    jz .bad_addr

    mov dword [win_w], 1200
    mov dword [win_h], 780
    call text_init
    mov rax, [rbx]
    lea rdi, [rbx + rax * 8 + 16]           ; envp
    call wl_init
    call net_connect
    jmp main_loop

.usage:
    lea rdi, [msg_usage]
    jmp .die
.bad_key:
    lea rdi, [msg_bad_key]
    jmp .die
.bad_addr:
    lea rdi, [msg_bad_addr]
.die:
    call print_err
    mov edi, 2
    call exit

; Waits on the compositor and the server at once.
main_loop:
    sub rsp, 24                             ; two struct pollfd { fd, events, revents }
.loop:
    cmp byte [net_state], NET_OFF
    jne .draw
    mov byte [need_redraw], 1               ; the retry countdown ticks
.draw:
    cmp byte [need_redraw], 0
    je .wait
    call render
.wait:
    call wl_flush
    call repeat_timeout
    mov ebx, eax                            ; -1 is "forever", the largest unsigned
    call net_timeout
    cmp eax, ebx
    cmovb ebx, eax
    cmp byte [net_state], NET_OFF
    jne .poll
    mov eax, 1000
    cmp ebx, eax
    cmova ebx, eax
.poll:
    mov eax, [wl_fd]
    mov [rsp], eax
    mov dword [rsp + 4], POLLIN
    mov eax, [net_fd]                       ; -1 makes poll skip it
    mov [rsp + 8], eax
    call net_poll_events
    mov [rsp + 12], eax
    mov eax, SYS_poll
    mov rdi, rsp
    mov esi, 2
    mov edx, ebx
    syscall
    test rax, rax
    jle .tick
    test word [rsp + 6], 0xffff
    jz .net
    call wl_read_events
.net:
    movzx edi, word [rsp + 14]
    test edi, edi
    jz .tick
    call net_io
.tick:
    call repeat_tick
    call net_tick
    jmp .loop
