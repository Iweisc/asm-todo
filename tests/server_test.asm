; server-test: checks the server's connections and storage without a network.
;
;   server-test     runs against build/server-test.db, which it starts fresh,
;                   and exits 1 on any failure.
;
; It includes the server's sources but not server.asm, so nothing listens.
; A connection is one end of a socketpair, and the test reads the other end
; to see what the server sent.

default rel
bits 64

%include "sys.inc"
%include "config.inc"
%include "macros.inc"

%define SYS_socketpair  53
%define BIG_MSG         60000           ; five of these overflow OUT_SIZE, four don't

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
%include "moderation.asm"
%include "roles.asm"
%include "nicknames.asm"
%include "automod.asm"
%include "sessions.asm"
%include "teardown.asm"

section .rodata
t_db:           db "build/server-test.db", 0
t_db_log:       db "build/server-test.db.log", 0
n_held:         db "a reply to a change waits until the change is on disk", 0
n_sent:         db "the turn's fdatasync sends the replies that waited", 0
n_overflow:     db "replies held past the buffer sync early instead of dropping the peer", 0
n_killed:       db "a killed connection still gets what was queued before it was killed", 0
s_ok:           db "ok    ", 0
s_fail:         db "FAIL  ", 0
s_newline:      db 10, 0

section .bss
failures:       resd 1
peer_fd:        resd 1                  ; the client's end of connection 0
big_msg:        resb BIG_MSG
drain_buf:      resb 65536

section .text

_start:
    mov eax, SYS_unlink
    lea rdi, [t_db]
    syscall
    mov eax, SYS_unlink
    lea rdi, [t_db_log]
    syscall
    lea rdi, [t_db]
    call db_load
    call open_conn
    call held_tests
    call overflow_tests
    call killed_tests
    xor edi, edi
    cmp dword [failures], 0
    setne dil
    call exit

; Makes connection 0 an open, logged-in one over a socketpair.
open_conn:
    sub rsp, 8
    mov eax, SYS_socketpair
    mov edi, AF_UNIX
    mov esi, SOCK_STREAM | SOCK_NONBLOCK
    xor edx, edx
    mov r10, rsp
    syscall
    xor edi, edi
    call conn_addr
    mov ecx, [rsp]
    mov [rax + C_FD], ecx
    mov ecx, [rsp + 4]
    mov [peer_fd], ecx
    mov byte [rax + C_STATE], ST_OPEN
    mov dword [rax + C_USER], 1
    add rsp, 8
    ret

; A change that isn't synced yet, the way a handler leaves one before replying.
commit_change:
    sub rsp, 8
    mov edi, T_USERS
    lea rsi, [users]
    call db_touch
    call db_commit
    add rsp, 8
    ret

; Reads everything the server has sent so far. -> rax = bytes, 0 for none
drain:
    push rbx
    xor ebx, ebx
.read:
    mov eax, SYS_read
    mov edi, [peer_fd]
    lea rsi, [drain_buf]
    mov edx, 65536
    syscall
    test rax, rax
    jle .done
    add rbx, rax
    jmp .read
.done:
    mov rax, rbx
    pop rbx
    ret

; Sends a one-byte message on connection 0.
send_small:
    xor edi, edi
    lea rsi, [big_msg]
    mov edx, 1
    jmp send_msg

; A reply after a change stays put until the end of the turn.
held_tests:
    sub rsp, 8
    call commit_change
    call send_small
    call drain
    xor esi, esi
    test rax, rax
    sete sil
    lea rdi, [n_held]
    call check
    call conn_send_held
    call drain
    xor esi, esi
    test rax, rax
    jz .sent
    cmp byte [journal_unsynced], 0
    sete sil
.sent:
    lea rdi, [n_sent]
    call check
    add rsp, 8
    ret

; Five big replies after a change don't fit OUT_SIZE unsent.
overflow_tests:
    push rbx
    call commit_change
    mov ebx, 5
.send:
    xor edi, edi
    lea rsi, [big_msg]
    mov edx, BIG_MSG
    call send_msg
    dec ebx
    jnz .send
    xor edi, edi
    call conn_addr
    xor esi, esi
    test byte [rax + C_FLAGS], F_KILL
    jnz .report
    cmp byte [journal_unsynced], 0
    sete sil
.report:
    lea rdi, [n_overflow]
    call check
    call conn_send_held
.wait:
    call drain
    xor edi, edi
    call conn_flush
    xor edi, edi
    call conn_addr
    cmp dword [rax + C_OUT_LEN], 0
    jne .wait
    pop rbx
    ret

; Kicking someone sends them a reason and marks them killed in one go.
killed_tests:
    sub rsp, 8
    call commit_change
    call send_small
    xor edi, edi
    call conn_kill
    call conn_send_held
    call drain
    xor esi, esi
    test rax, rax
    setnz sil
    lea rdi, [n_killed]
    call check
    add rsp, 8
    ret

; rdi = test name, esi = 1 if it passed
check:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    lea rdi, [s_ok]
    test r12d, r12d
    jnz .print
    inc dword [failures]
    lea rdi, [s_fail]
.print:
    call say
    mov rdi, rbx
    call say
    lea rdi, [s_newline]
    call say
    add rsp, 8
    pop r12
    pop rbx
    ret

; rdi = a zero-terminated string for stdout
say:
    push rdi
    call strlen
    pop rsi
    mov rdx, rax
    mov eax, SYS_write
    mov edi, 1
    syscall
    ret
