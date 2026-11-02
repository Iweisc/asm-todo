; Changing a password. Two hashing jobs, one after the other: the current
; password against the stored hash, then the new one with a fresh salt. The
; new password waits in the connection between the two and is wiped as soon
; as its job starts. A change logs out the user's other sessions, so whoever
; might have had the old password loses what it got them.

section .rodata
text e_wrong_password,  "your current password is wrong"
s_log_password:         db "changed the password of ", 0

section .text

; MSG_CHANGE_PASSWORD: checks the new password, then starts on the current one.
h_change_password:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    call rd_str
    mov r12, rax
    mov r13d, edx
    call rd_str
    mov rbx, rax
    mov r14d, edx
    call rd_ok
    test eax, eax
    jz .violation
    cmp r14d, PASSWORD_MIN
    jb .bad_password
    cmp r14d, PASSWORD_MAX
    ja .bad_password
    test r13d, r13d
    jz .wrong
    cmp r13d, PASSWORD_MAX
    ja .wrong
    mov rax, [cur]
    mov edi, [rax + C_IP]
    call rate_allow
    test eax, eax
    jz .rate
    mov rax, [cur]
    mov edi, [rax + C_USER]
    call find_user
    test rax, rax
    jz .violation
    push rax
    mov rax, [cur]
    mov [rax + C_NEW_PASS_LEN], r14b
    lea rdi, [rax + C_NEW_PASS]
    mov rsi, rbx
    mov ecx, r14d
    rep movsb
    pop rax
    lea rcx, [rax + USER_SALT]
    mov edi, JOB_CHECK_PASSWORD
    mov rsi, r12
    mov edx, r13d
    call start_job
    jmp .done
.violation:
    call kill_cur
    jmp .done
.bad_password:
    lea rsi, [e_password]
    mov edx, e_password_len
    call send_error
    jmp .done
.wrong:
    lea rsi, [e_wrong_password]
    mov edx, e_wrong_password_len
    call password_failed
    jmp .done
.rate:
    lea rsi, [e_rate]
    mov edx, e_rate_len
    call send_error
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; One of the two jobs finished, for cur. -> eax = 1 if the second one started
finish_password_job:
    push rbx
    push r12
    sub rsp, 8
    mov r12, [cur]
    mov rax, r12
    mov edi, [rax + C_USER]
    call find_user
    mov rbx, rax
    cmp byte [r12 + C_JOB_KIND], JOB_NEW_PASSWORD
    je .store
    lea rdi, [r12 + C_JOB + PB_T]
    lea rsi, [rbx + USER_HASH]
    mov edx, 32
    call ct_equal
    test eax, eax
    jz .wrong
    lea rdi, [r12 + C_JOB_SALT]
    mov esi, 16
    call random_bytes
    mov edi, JOB_NEW_PASSWORD
    lea rsi, [r12 + C_NEW_PASS]
    movzx edx, byte [r12 + C_NEW_PASS_LEN]
    lea rcx, [r12 + C_JOB_SALT]
    call start_job
    call wipe_new_password
    mov eax, 1
    jmp .done
.wrong:
    call wipe_new_password
    lea rsi, [e_wrong_password]
    mov edx, e_wrong_password_len
    call password_failed
    xor eax, eax
    jmp .done
.store:
    lea rdi, [rbx + USER_SALT]
    lea rsi, [r12 + C_JOB_SALT]
    mov ecx, 16
    rep movsb
    lea rdi, [rbx + USER_HASH]
    lea rsi, [r12 + C_JOB + PB_T]
    mov ecx, 32
    rep movsb
    mov edi, T_USERS
    mov rsi, rbx
    call db_touch
    mov edi, [rbx + USER_ID]
    mov esi, [r12 + C_SESSION]
    call end_other_sessions
    call db_commit
    lea rdi, [s_log_password]
    lea rsi, [rbx + USER_NAME]
    movzx edx, byte [rbx + USER_NAME_LEN]
    call log_name
    lea rdi, [msg_buf]
    mov esi, MSG_PASSWORD_CHANGED
    call wr_u8
    lea rsi, [msg_buf]
    mov edx, 1
    call reply
    xor eax, eax
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; A wrong current password counts like a failed login, so one connection
; can't keep guessing. rsi = message, edx = length
password_failed:
    sub rsp, 8
    call send_error
    mov rax, [cur]
    inc byte [rax + C_FAILS]
    cmp byte [rax + C_FAILS], MAX_AUTH_FAILS
    jb .done
    call kill_cur
.done:
    add rsp, 8
    ret

; Clears the new password waiting in cur.
wipe_new_password:
    mov rdi, [cur]
    mov byte [rdi + C_NEW_PASS_LEN], 0
    lea rdi, [rdi + C_NEW_PASS]
    mov esi, PASSWORD_MAX
    jmp wipe

; Revokes every session of a user but one, and drops their connections.
; edi = user id, esi = the session slot to keep
end_other_sessions:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    lea rbx, [sessions]
    xor r14d, r14d
.slot:
    cmp r14d, [n_sessions]
    jae .done
    cmp r14d, r13d
    je .next
    cmp [rbx + SESS_USER], r12d
    jne .next
    mov edi, T_SESSIONS
    mov rsi, rbx
    call free_row
    mov edi, r14d
    call kick_session
.next:
    add rbx, SESS_SIZE
    inc r14d
    jmp .slot
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
