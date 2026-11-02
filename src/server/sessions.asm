; The account dashboard's data: when the user joined, their sessions, and
; how big each of their teams is. Ending sessions is here too. Deleting the
; account is in teardown.asm.

section .rodata
text e_no_session,      "that session already ended"

section .text

; edi = session slot -> eax = 1 if a logged in connection is using it
session_online:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, edi
    xor ebx, ebx
.conn:
    mov edi, ebx
    call conn_addr
    cmp byte [rax + C_STATE], ST_OPEN
    jne .next
    cmp dword [rax + C_USER], 0
    je .next
    cmp [rax + C_SESSION], r12d
    jne .next
    mov eax, 1
    jmp .done
.next:
    inc ebx
    cmp ebx, MAX_CONN
    jb .conn
    xor eax, eax
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; edi = team -> eax = its issues that aren't done or canceled
count_open_issues:
    lea rcx, [issues]
    mov edx, [n_issues]
    xor eax, eax
.row:
    test edx, edx
    jz .done
    cmp [rcx + ISS_TEAM], edi
    jne .next
    cmp byte [rcx + ISS_STATUS], STATUS_DONE
    jae .next
    inc eax
.next:
    add rcx, ISSUE_SIZE
    dec edx
    jmp .row
.done:
    ret

; Writes the user's live sessions, up to ACCOUNT_SESSIONS of them.
; rdi = cursor, esi = user -> rdi advanced
wr_sessions:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, esi
    mov r13, rdi                            ; the count goes here
    inc rdi
    mov r15, rdi
    call now_unix
    mov [rsp], eax
    lea rbx, [sessions]
    xor ebp, ebp                            ; slot
    xor r14d, r14d                          ; written
.slot:
    cmp ebp, [n_sessions]
    jae .done
    cmp r14d, ACCOUNT_SESSIONS
    jae .done
    cmp [rbx + SESS_USER], r12d
    jne .next
    mov eax, [rsp]
    cmp [rbx + SESS_EXPIRES], eax
    jbe .next
    mov rdi, r15
    mov esi, ebp
    call wr_u32
    mov esi, [rbx + SESS_EXPIRES]
    sub esi, SESSION_DAYS * 86400
    call wr_u32
    mov esi, [rbx + SESS_SEEN]
    call wr_u32
    mov r15, rdi
    mov edi, ebp
    call session_online
    add eax, eax                            ; SS_ONLINE
    mov rcx, [cur]
    cmp [rcx + C_SESSION], ebp
    jne .flags
    or eax, SS_CURRENT
.flags:
    mov rdi, r15
    mov esi, eax
    call wr_u8
    mov r15, rdi
    inc r14d
.next:
    add rbx, SESS_SIZE
    inc ebp
    jmp .slot
.done:
    mov [r13], r14b
    mov rdi, r15
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Writes each of the user's teams with its member and open issue counts.
; rdi = cursor, esi = user -> rdi advanced
wr_team_sizes:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, esi
    mov r13, rdi
    inc rdi
    mov r15, rdi
    xor r14d, r14d
    lea rbx, [members]
    mov ebp, [n_members]
.row:
    test ebp, ebp
    jz .done
    cmp [rbx + MEM_USER], r12d
    jne .next
    mov rdi, r15
    mov esi, [rbx + MEM_TEAM]
    call wr_u32
    mov r15, rdi
    mov edi, T_MEMBERS
    mov esi, MEM_TEAM
    mov edx, [rbx + MEM_TEAM]
    call count_where
    mov rdi, r15
    mov esi, eax
    call wr_u8
    mov r15, rdi
    mov edi, [rbx + MEM_TEAM]
    call count_open_issues
    mov rdi, r15
    mov esi, eax
    call wr_u16
    mov r15, rdi
    inc r14d
.next:
    add rbx, MEM_SIZE
    dec ebp
    jmp .row
.done:
    mov [r13], r14b
    mov rdi, r15
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Sends cur its MSG_ACCOUNT.
send_account:
    push rbx
    mov rax, [cur]
    mov ebx, [rax + C_USER]
    mov edi, ebx
    call find_user
    test rax, rax
    jz .done
    mov esi, [rax + USER_CREATED]
    push rsi
    lea rdi, [msg_buf]
    mov esi, MSG_ACCOUNT
    call wr_u8
    pop rsi
    call wr_u32
    mov esi, ebx
    call wr_sessions
    mov esi, ebx
    call wr_team_sizes
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    call reply
.done:
    pop rbx
    ret

; MSG_ACCOUNT_INFO: answered with MSG_ACCOUNT.
h_account_info:
    sub rsp, 8
    call rd_ok
    test eax, eax
    jz .violation
    call send_account
    jmp .done
.violation:
    call kill_cur
.done:
    add rsp, 8
    ret

; MSG_END_SESSION: logs out one of the user's other sessions, or all of them,
; and drops whatever's connected on them.
h_end_session:
    push rbx
    push r12
    sub rsp, 8
    call rd_u32
    mov ebx, eax
    call rd_ok
    test eax, eax
    jz .violation
    mov r12, [cur]
    cmp ebx, -1
    je .others
    cmp ebx, [r12 + C_SESSION]
    je .violation                           ; this one ends with MSG_LOGOUT
    cmp ebx, [n_sessions]
    jae .gone
    imul eax, ebx, SESS_SIZE
    lea rsi, [sessions + rax]
    mov eax, [r12 + C_USER]
    cmp [rsi + SESS_USER], eax
    jne .gone
    mov edi, T_SESSIONS
    call free_row
    mov edi, ebx
    call kick_session
    jmp .commit
.others:
    mov edi, [r12 + C_USER]
    mov esi, [r12 + C_SESSION]
    call end_other_sessions
.commit:
    call db_commit
    call send_account
    jmp .done
.gone:
    lea rsi, [e_no_session]
    mov edx, e_no_session_len
    call send_error
    call send_account
    jmp .done
.violation:
    call kill_cur
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret
