; Application messages: the dispatcher, accounts and sessions. Teams are in
; teams.asm, issues and the sync in issues.asm, chat in messages.asm.

%define JOB_LOGIN           1
%define JOB_REGISTER        2
%define JOB_CHECK_PASSWORD  3               ; the current password, before a change
%define JOB_NEW_PASSWORD    4
%define JOB_SLICE           25000       ; PBKDF2 iterations per event loop turn (~12ms)
%define MAX_AUTH_FAILS      5
%define RATE_SLOTS          64
%define RATE_WINDOW_MS      60000
%define RATE_MAX            10          ; password checks per IP per window
%define SNAPSHOT_CHUNK      15000

section .rodata
text e_log_in_first,    "log in first"
text e_logged_in,       "you're already logged in"
text e_bad_login,       "wrong username or password"
text e_username,        "usernames are 3-32 characters of a-z, 0-9, '.', '-' or '_'"
text e_password,        "passwords need 8 to 128 characters"
text e_rate,            "too many attempts, wait a minute"
text e_taken,           "that username is taken"
text e_full,            "the server is full"
text e_expired,         "your session expired, log in again"
s_log_prefix:           db "todo-server: ", 0
s_log_register:         db "registered ", 0
s_log_login:            db "logged in ", 0
s_log_failed:           db "failed login for ", 0

; Hashed for logins with an unknown username, so they take as long as real ones.
dummy_salt:             times 16 db 0x5a

section .bss
cur_idx:            resd 1
cur:                resq 1
jobs_pending:       resd 1
job_rr:             resd 1
msg_buf:            resb APP_MAX + 256
log_buf:            resb 256
rate_ip:            resd RATE_SLOTS
rate_count:         resd RATE_SLOTS
rate_start:         resq RATE_SLOTS

section .text

; edi = index, rsi = plaintext, rdx = length
handle_message:
    push rbx
    mov [cur_idx], edi
    push rsi
    push rdx
    call conn_addr
    mov [cur], rax
    pop rsi
    pop rdi
    call rd_begin
    call rd_u8
    mov rbx, [cur]
    cmp eax, MSG_REGISTER
    je .register
    cmp eax, MSG_LOGIN
    je .login
    cmp eax, MSG_RESUME
    je .resume
    cmp dword [rbx + C_USER], 0
    je .anonymous
    cmp eax, MSG_LOGOUT
    je .logout
    cmp eax, MSG_CHANGE_PASSWORD
    je .change_password
    cmp eax, MSG_CREATE_TEAM
    je .create_team
    cmp eax, MSG_ADD_MEMBER
    je .add_member
    cmp eax, MSG_REMOVE_MEMBER
    je .remove_member
    cmp eax, MSG_SUBSCRIBE
    je .subscribe
    cmp eax, MSG_OPEN_ISSUE
    je .open_issue
    cmp eax, MSG_OPEN_CHAT
    je .open_chat
    cmp eax, MSG_SET_ROLE
    je .set_role
    cmp eax, MSG_RENAME_TEAM
    je .rename_team
    cmp eax, MSG_SET_CHANNEL
    je .set_channel
    cmp eax, MSG_EDIT_MESSAGE
    je .edit_message
    cmp eax, MSG_DELETE_MESSAGE
    je .delete_message
    cmp eax, MSG_UPLOAD_IMAGE
    je .upload_image
    cmp eax, MSG_IMAGE_PART
    je .image_part
    cmp eax, MSG_GET_IMAGE
    je .get_image
    cmp eax, MSG_OP
    je .op
.violation:
    or byte [rbx + C_FLAGS], F_KILL
    jmp .done
.anonymous:
    cmp eax, MSG_LOGOUT
    jb .violation
    cmp eax, MSG_OP
    ja .violation
    lea rsi, [e_log_in_first]
    mov edx, e_log_in_first_len
    call send_error
    jmp .done
.register:
    call h_register
    jmp .done
.login:
    call h_login
    jmp .done
.resume:
    call h_resume
    jmp .done
.logout:
    call h_logout
    jmp .done
.change_password:
    call h_change_password
    jmp .done
.create_team:
    call h_create_team
    jmp .done
.add_member:
    call h_add_member
    jmp .done
.remove_member:
    call h_remove_member
    jmp .done
.subscribe:
    call h_subscribe
    jmp .done
.open_issue:
    call h_open_issue
    jmp .done
.open_chat:
    call h_open_chat
    jmp .done
.set_role:
    call h_set_role
    jmp .done
.rename_team:
    call h_rename_team
    jmp .done
.set_channel:
    call h_set_channel
    jmp .done
.edit_message:
    call h_edit_message
    jmp .done
.delete_message:
    call h_delete_message
    jmp .done
.upload_image:
    call h_upload_image
    jmp .done
.image_part:
    call h_image_part
    jmp .done
.get_image:
    call h_get_image
    jmp .done
.op:
    call h_op
.done:
    pop rbx
    ret

kill_cur:
    mov rax, [cur]
    or byte [rax + C_FLAGS], F_KILL
    ret

; rsi = message, edx = length
reply:
    mov edi, [cur_idx]
    jmp send_msg

; esi = type, rdx = text, ecx = length. Sends [type, str text] to cur.
reply_text:
    push rbx
    mov rbx, rdx
    lea rdi, [msg_buf]
    call wr_u8
    mov rsi, rbx
    mov edx, ecx
    call wr_str
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    pop rbx
    jmp reply

; rsi = text, edx = length
send_error:
    mov rcx, rdx
    mov rdx, rsi
    mov esi, MSG_ERROR
    jmp reply_text

; A failed login, register or resume. Too many and the connection goes.
; rsi = text, edx = length
auth_failed:
    mov rcx, rdx
    mov rdx, rsi
    mov esi, MSG_AUTH_FAIL
    call reply_text
    mov rax, [cur]
    inc byte [rax + C_FAILS]
    cmp byte [rax + C_FAILS], MAX_AUTH_FAILS
    jb .done
    mov byte [rax + C_STATE], ST_CLOSING
    mov rcx, [now]
    add rcx, CLOSING_TIMEOUT_MS
    mov [rax + C_DEADLINE], rcx
.done:
    ret

; "todo-server: <prefix><name>" on stderr, with unprintable bytes shown as '?'.
; rdi = prefix, rsi = name, edx = length
log_name:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13d, edx
    mov rbx, rdi
    lea rdi, [log_buf]
    lea rsi, [s_log_prefix]
    call put_cstr
    mov rsi, rbx
    call put_cstr
    xor ecx, ecx
.char:
    cmp ecx, r13d
    jae .end
    cmp ecx, 64
    jae .end
    mov al, [r12 + rcx]
    cmp al, ' '
    jb .unprintable
    cmp al, '~'
    jbe .store
.unprintable:
    mov al, '?'
.store:
    stosb
    inc ecx
    jmp .char
.end:
    mov al, 10
    stosb
    mov rdx, rdi
    lea rsi, [log_buf]
    sub rdx, rsi
    mov edi, 2
    call write_all
    pop r13
    pop r12
    pop rbx
    ret

; Allows RATE_MAX password checks per IP per minute.
; edi = IPv4 address -> eax = 1 if this attempt may go ahead
rate_allow:
    xor ecx, ecx
    mov r8d, -1                             ; slot with the oldest window
    mov r9, -1
.find:
    cmp [rate_ip + rcx * 4], edi
    jne .older
    cmp qword [rate_start + rcx * 8], 0
    jne .found
.older:
    mov rax, [rate_start + rcx * 8]
    cmp rax, r9
    jae .next
    mov r9, rax
    mov r8d, ecx
.next:
    inc ecx
    cmp ecx, RATE_SLOTS
    jb .find
    mov ecx, r8d                            ; reuse the stalest slot
    mov [rate_ip + rcx * 4], edi
    mov dword [rate_count + rcx * 4], 0
    mov rax, [now]
    mov [rate_start + rcx * 8], rax
.found:
    mov rax, [now]
    sub rax, [rate_start + rcx * 8]
    cmp rax, RATE_WINDOW_MS
    jb .in_window
    mov rax, [now]
    mov [rate_start + rcx * 8], rax
    mov dword [rate_count + rcx * 4], 0
.in_window:
    xor eax, eax
    cmp dword [rate_count + rcx * 4], RATE_MAX
    jae .done
    inc dword [rate_count + rcx * 4]
    mov eax, 1
.done:
    ret

; rsi = name, edx = length -> eax = 1 if it's an acceptable username
valid_username:
    xor eax, eax
    cmp edx, USERNAME_MIN
    jb .done
    cmp edx, USERNAME_MAX
    ja .done
    xor ecx, ecx
.char:
    cmp ecx, edx
    jae .ok
    movzx r8d, byte [rsi + rcx]
    lea r9d, [r8d - 'a']
    cmp r9d, 'z' - 'a'
    jbe .next
    lea r9d, [r8d - '0']
    cmp r9d, 9
    jbe .next
    cmp r8d, '.'
    je .next
    cmp r8d, '-'
    je .next
    cmp r8d, '_'
    jne .done
.next:
    inc ecx
    jmp .char
.ok:
    mov eax, 1
.done:
    ret

; Names and titles: printable ASCII only, no leading or trailing space.
; rsi = text, edx = length, ecx = max length -> eax = 1 if acceptable
valid_text:
    xor eax, eax
    test edx, edx
    jz .done
    cmp edx, ecx
    ja .done
    cmp byte [rsi], ' '
    je .done
    cmp byte [rsi + rdx - 1], ' '
    je .done
    xor ecx, ecx
.char:
    cmp ecx, edx
    jae .ok
    mov r8b, [rsi + rcx]
    cmp r8b, ' '
    jb .done
    cmp r8b, '~'
    ja .done
    inc ecx
    jmp .char
.ok:
    mov eax, 1
.done:
    ret

; Hands a password to the hashing scheduler and parks the connection.
; edi = job kind, rsi = password, edx = length, rcx = 16-byte salt
start_job:
    mov rax, [cur]
    mov [rax + C_JOB_KIND], dil
    or byte [rax + C_FLAGS], F_BUSY
    inc dword [jobs_pending]
    lea rdi, [rax + C_JOB]
    mov r8d, 16
    mov r9d, PBKDF2_ITERATIONS
    jmp pbkdf2_begin

h_register:
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
    mov rax, [cur]
    cmp dword [rax + C_USER], 0
    jne .logged_in

    mov rsi, r12
    mov edx, r13d
    call valid_username
    test eax, eax
    jz .bad_name
    cmp r14d, PASSWORD_MIN
    jb .bad_password
    cmp r14d, PASSWORD_MAX
    ja .bad_password
    mov rax, [cur]
    mov edi, [rax + C_IP]
    call rate_allow
    test eax, eax
    jz .rate
    mov rsi, r12
    mov edx, r13d
    call find_user_by_name
    test rax, rax
    jnz .taken
    cmp dword [n_users], MAX_USERS
    jae .full

    mov rax, [cur]
    mov [rax + C_JOB_NAME_LEN], r13b
    lea rdi, [rax + C_JOB_NAME]
    mov rsi, r12
    mov ecx, r13d
    rep movsb
    mov rax, [cur]
    lea rdi, [rax + C_JOB_SALT]
    mov esi, 16
    call random_bytes
    mov rax, [cur]
    mov edi, JOB_REGISTER
    mov rsi, rbx
    mov edx, r14d
    lea rcx, [rax + C_JOB_SALT]
    call start_job
    jmp .done
.violation:
    call kill_cur
    jmp .done
.logged_in:
    lea rsi, [e_logged_in]
    mov edx, e_logged_in_len
    call send_error
    jmp .done
.bad_name:
    lea rsi, [e_username]
    mov edx, e_username_len
    jmp .fail
.bad_password:
    lea rsi, [e_password]
    mov edx, e_password_len
    jmp .fail
.rate:
    lea rsi, [e_rate]
    mov edx, e_rate_len
    jmp .fail
.taken:
    lea rsi, [e_taken]
    mov edx, e_taken_len
    jmp .fail
.full:
    lea rsi, [e_full]
    mov edx, e_full_len
.fail:
    call auth_failed
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

h_login:
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
    mov rax, [cur]
    cmp dword [rax + C_USER], 0
    jne .logged_in
    test r14d, r14d
    jz .bad
    cmp r14d, PASSWORD_MAX
    ja .bad
    mov rax, [cur]
    mov edi, [rax + C_IP]
    call rate_allow
    test eax, eax
    jz .rate

    ; Unknown names still get hashed against a dummy salt, so response time
    ; doesn't tell anyone which usernames exist.
    mov rax, [cur]
    mov dword [rax + C_JOB_USER], -1
    lea rcx, [dummy_salt]
    mov rsi, r12
    mov edx, r13d
    push rcx
    call find_user_by_name
    pop rcx
    test rax, rax
    jz .hash
    lea rcx, [rax + USER_SALT]
    lea rdx, [users]
    sub rax, rdx
    xor edx, edx
    mov r8d, USER_SIZE
    div r8
    mov rdx, [cur]
    mov [rdx + C_JOB_USER], eax
.hash:
    mov rax, [cur]                          ; remembered for the log line
    mov edx, r13d
    cmp edx, USERNAME_MAX
    jbe .name_fits
    mov edx, USERNAME_MAX
.name_fits:
    mov [rax + C_JOB_NAME_LEN], dl
    push rcx
    lea rdi, [rax + C_JOB_NAME]
    mov rsi, r12
    mov ecx, edx
    rep movsb
    pop rcx
    mov edi, JOB_LOGIN
    mov rsi, rbx
    mov edx, r14d
    call start_job
    jmp .done
.violation:
    call kill_cur
    jmp .done
.logged_in:
    lea rsi, [e_logged_in]
    mov edx, e_logged_in_len
    call send_error
    jmp .done
.rate:
    lea rsi, [e_rate]
    mov edx, e_rate_len
    call auth_failed
    jmp .done
.bad:
    lea rsi, [e_bad_login]
    mov edx, e_bad_login_len
    call auth_failed
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Runs one slice of one waiting password job, round robin.
run_jobs:
    push rbx
    push r12
    push r13
    mov r12d, [job_rr]
    xor r13d, r13d
.scan:
    cmp r13d, MAX_CONN
    jae .done
    mov eax, r12d
    add eax, r13d
    xor edx, edx
    mov ecx, MAX_CONN
    div ecx
    mov ebx, edx
    mov edi, ebx
    call conn_addr
    inc r13d
    cmp byte [rax + C_STATE], ST_FREE
    je .scan
    test byte [rax + C_FLAGS], F_BUSY
    jz .scan
    test byte [rax + C_FLAGS], F_KILL
    jnz .scan
    lea rdi, [rax + C_JOB]
    mov esi, JOB_SLICE
    call pbkdf2_step
    lea ecx, [ebx + 1]
    mov [job_rr], ecx
    test eax, eax
    jz .done
    mov edi, ebx
    call finish_job
.done:
    pop r13
    pop r12
    pop rbx
    ret

; A password hash finished. edi = index
finish_job:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov [cur_idx], edi
    call conn_addr
    mov [cur], rax
    mov r12, rax
    and byte [r12 + C_FLAGS], ~F_BUSY
    dec dword [jobs_pending]
    cmp byte [r12 + C_JOB_KIND], JOB_CHECK_PASSWORD
    jae .password
    cmp byte [r12 + C_JOB_KIND], JOB_REGISTER
    je .register

    mov eax, [r12 + C_JOB_USER]
    test eax, eax
    js .login_failed
    imul eax, eax, USER_SIZE
    lea r13, [users + rax]
    lea rdi, [r12 + C_JOB + PB_T]
    lea rsi, [r13 + USER_HASH]
    mov edx, 32
    call ct_equal
    test eax, eax
    jz .login_failed
    lea rdi, [s_log_login]
    lea rsi, [r13 + USER_NAME]
    movzx edx, byte [r13 + USER_NAME_LEN]
    call log_name
    mov rdi, r13
    call login_success
    jmp .cleanup
.login_failed:
    lea rdi, [s_log_failed]
    lea rsi, [r12 + C_JOB_NAME]
    movzx edx, byte [r12 + C_JOB_NAME_LEN]
    call log_name
    lea rsi, [e_bad_login]
    mov edx, e_bad_login_len
    call auth_failed
    jmp .cleanup

.register:
    ; Someone may have taken the name while we were hashing.
    lea rsi, [r12 + C_JOB_NAME]
    movzx edx, byte [r12 + C_JOB_NAME_LEN]
    call find_user_by_name
    test rax, rax
    jnz .taken
    mov edi, T_USERS
    call alloc_row
    test rax, rax
    jz .full
    mov r13, rax
    mov eax, [next_user_id]
    mov [r13 + USER_ID], eax
    inc dword [next_user_id]
    movzx ecx, byte [r12 + C_JOB_NAME_LEN]
    mov [r13 + USER_NAME_LEN], cl
    lea rdi, [r13 + USER_NAME]
    lea rsi, [r12 + C_JOB_NAME]
    rep movsb
    lea rdi, [r13 + USER_SALT]
    lea rsi, [r12 + C_JOB_SALT]
    mov ecx, 16
    rep movsb
    lea rdi, [r13 + USER_HASH]
    lea rsi, [r12 + C_JOB + PB_T]
    mov ecx, 32
    rep movsb
    mov edi, T_USERS
    mov rsi, r13
    call db_touch
    lea rdi, [s_log_register]
    lea rsi, [r13 + USER_NAME]
    movzx edx, byte [r13 + USER_NAME_LEN]
    call log_name
    mov rdi, r13
    call login_success                      ; commits the new user too
    jmp .cleanup
.taken:
    lea rsi, [e_taken]
    mov edx, e_taken_len
    call auth_failed
    jmp .cleanup
.full:
    lea rsi, [e_full]
    mov edx, e_full_len
    call auth_failed
    jmp .cleanup
.password:
    call finish_password_job
    test eax, eax
    jnz .busy                               ; on to hashing the new one
.cleanup:
    lea rdi, [r12 + C_JOB_NAME_LEN]         ; name, salt and hash state, all of it
    mov esi, C_JOB + PB_SIZE - C_JOB_NAME_LEN
    call wipe
    mov edi, ebx                            ; input that arrived while hashing
    call conn_process
.busy:
    pop r13
    pop r12
    pop rbx
    ret

; Opens a session for cur and tells the client. rdi = user row
login_success:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 72                             ; token, its hash
    mov r12, rdi

    ; Pick a free or expired slot, else grow, else evict the soonest to expire.
    call now_unix
    mov r14, rax
    lea rbx, [sessions]
    xor ecx, ecx
    mov r13d, -1
    mov r8, -1                              ; earliest expiry seen
    xor r9d, r9d
.slot:
    cmp ecx, [n_sessions]
    jae .grow
    cmp dword [rbx + SESS_USER], 0
    je .take
    cmp [rbx + SESS_EXPIRES], r14
    jbe .take
    cmp [rbx + SESS_EXPIRES], r8
    jae .slot_next
    mov r8, [rbx + SESS_EXPIRES]
    mov r9d, ecx
.slot_next:
    add rbx, SESS_SIZE
    inc ecx
    jmp .slot
.grow:
    cmp ecx, MAX_SESSIONS
    jb .append
    mov ecx, r9d
    imul eax, ecx, SESS_SIZE
    lea rbx, [sessions + rax]
    jmp .take
.append:
    inc dword [n_sessions]
.take:
    mov r13d, ecx
    ; Anyone still using an evicted slot is logged out with it.
    mov edi, r13d
    call kick_session

    mov rdi, rsp
    mov esi, 32
    call random_bytes
    mov rdi, rsp
    mov esi, 32
    lea rdx, [rbx + SESS_HASH]
    call sha256
    mov eax, [r12 + USER_ID]
    mov [rbx + SESS_USER], eax
    mov dword [rbx + SESS_LAST_OP], 0
    lea rax, [r14 + SESSION_DAYS * 86400]
    mov [rbx + SESS_EXPIRES], rax
    mov edi, T_SESSIONS
    mov rsi, rbx
    call db_touch
    call db_commit

    mov rax, [cur]
    mov ecx, [r12 + USER_ID]
    mov [rax + C_USER], ecx
    mov [rax + C_SESSION], r13d
    mov byte [rax + C_FAILS], 0
    mov qword [rax + C_DEADLINE], 0
    mov rdi, r12
    mov rsi, rsp
    xor edx, edx
    call send_auth_ok
    mov rdi, rsp
    mov esi, 32
    call wipe
    add rsp, 72
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Logs out every connection on a session slot. edi = slot
kick_session:
    push rbx
    push r12
    push r13
    mov r12d, edi
    xor ebx, ebx
.loop:
    mov edi, ebx
    call conn_addr
    cmp byte [rax + C_STATE], ST_FREE
    je .next
    cmp dword [rax + C_USER], 0
    je .next
    cmp [rax + C_SESSION], r12d
    jne .next
    or byte [rax + C_FLAGS], F_KILL
.next:
    inc ebx
    cmp ebx, MAX_CONN
    jb .loop
    pop r13
    pop r12
    pop rbx
    ret

; AUTH_OK followed by the user's team list.
; rdi = user row, rsi = token, edx = last op applied
send_auth_ok:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    lea rdi, [msg_buf]
    mov esi, MSG_AUTH_OK
    call wr_u8
    mov esi, [rbx + USER_ID]
    call wr_u32
    lea rsi, [rbx + USER_NAME]
    movzx edx, byte [rbx + USER_NAME_LEN]
    call wr_str
    mov rsi, r12
    mov ecx, 32
    rep movsb
    mov esi, r13d
    call wr_u32
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    call reply
    mov edi, [cur_idx]
    mov esi, [rbx + USER_ID]
    call send_teams
    pop r13
    pop r12
    pop rbx
    ret

h_resume:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 40
    mov edi, 32
    call rd_bytes
    mov r12, rax
    call rd_ok
    test eax, eax
    jz .violation
    mov rax, [cur]
    cmp dword [rax + C_USER], 0
    jne .logged_in
    mov rdi, r12
    mov esi, 32
    mov rdx, rsp
    call sha256
    call now_unix
    mov r14, rax
    lea rbx, [sessions]
    xor r13d, r13d
.slot:
    cmp r13d, [n_sessions]
    jae .expired
    cmp dword [rbx + SESS_USER], 0
    je .next
    cmp [rbx + SESS_EXPIRES], r14
    jbe .next
    mov rdi, rsp
    lea rsi, [rbx + SESS_HASH]
    mov edx, 32
    call ct_equal
    test eax, eax
    jnz .found
.next:
    add rbx, SESS_SIZE
    inc r13d
    jmp .slot
.found:
    mov edi, [rbx + SESS_USER]
    call find_user
    test rax, rax
    jz .expired
    mov rcx, [cur]
    mov edx, [rbx + SESS_USER]
    mov [rcx + C_USER], edx
    mov [rcx + C_SESSION], r13d
    mov byte [rcx + C_FAILS], 0
    mov qword [rcx + C_DEADLINE], 0
    mov rdi, rax
    mov rsi, r12
    mov edx, [rbx + SESS_LAST_OP]
    call send_auth_ok
    jmp .done
.violation:
    call kill_cur
    jmp .done
.logged_in:
    lea rsi, [e_logged_in]
    mov edx, e_logged_in_len
    call send_error
    jmp .done
.expired:
    lea rsi, [e_expired]
    mov edx, e_expired_len
    call auth_failed
.done:
    add rsp, 40
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

h_logout:
    push rbx
    push r12
    sub rsp, 8
    call rd_ok
    test eax, eax
    jz .violation
    mov rbx, [cur]
    mov eax, [rbx + C_SESSION]
    imul eax, eax, SESS_SIZE
    lea rsi, [sessions + rax]
    mov edi, T_SESSIONS
    call free_row
    call db_commit
    mov edi, [rbx + C_SESSION]              ; other connections on this session go too
    call kick_session
    and byte [rbx + C_FLAGS], ~F_KILL       ; ...but this one stays, logged out
    mov r12d, [rbx + C_TEAM]
    mov dword [rbx + C_USER], 0
    mov dword [rbx + C_TEAM], 0
    mov rax, [now]
    add rax, AUTH_TIMEOUT_MS
    mov [rbx + C_DEADLINE], rax
    lea rdi, [msg_buf]
    mov esi, MSG_LOGGED_OUT
    call wr_u8
    lea rsi, [msg_buf]
    mov edx, 1
    call reply
    test r12d, r12d
    jz .done
    mov edi, r12d
    call broadcast_members
    jmp .done
.violation:
    call kill_cur
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret
