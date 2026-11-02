; Deleting a team with everything in it, and deleting an account. Both free
; rows across most tables, so they live together. Deleting an account keeps
; the user's channel messages, comments and issues, like leaving does, but
; their direct messages go.

section .rodata
text e_wrong_key,       "type the team's key to delete it"
text e_wrong_account_password, "that password is wrong"
text e_owns_team,       "you're the last owner of a team. Make someone else an owner or delete the team first"
s_log_deleted_team:     db "deleted the team ", 0
s_log_deleted_user:     db "deleted the account of ", 0

; The tables a team's rows are freed from, by the offset of their team field.
; Members go last, so the rows before them can still be told apart.
align 4
team_tables:
    dd T_ISSUES, ISS_TEAM
    dd T_MESSAGES, MS_TEAM
    dd T_SEEN, SEEN_TEAM
    dd T_CHANNELS, CHN_TEAM
    dd T_BANS, BAN_TEAM
    dd T_AUDIT, AUD_TEAM
    dd T_ROLES, RL_TEAM
    dd T_CHANCFG, CC_TEAM
    dd T_NICKS, NICK_TEAM
    dd T_AUTOMOD, AM_TEAM
    dd T_MEMBERS, MEM_TEAM
TEAM_TABLES equ ($ - team_tables) / 8

section .bss
alignb 4
gone_users:     resd TEAM_MEMBER_MAX        ; a deleted team's members, to tell
gone_issues:    resd TEAM_ISSUE_MAX         ; its issues, whose comments go too
gone_count:     resd 1
ban_teams:      resd MAX_TEAMS              ; teams a deleted user was banned from

section .text

; Collects the values of a u32 in a team's rows. edi = table, esi = offset
; of the team field, edx = team, rcx = destination, r8d = offset of the value,
; r9d = how many fit -> eax = how many were collected
collect_where:
    push rbx
    push r12
    sub rsp, 8
    mov r10d, edi
    shl r10d, 5
    lea rbx, [db_tables + r10]
    mov r10, [rbx + 8]
    mov r10d, [r10]                         ; rows to look at
    mov r11, [rbx]
    xor eax, eax
.row:
    test r10d, r10d
    jz .done
    cmp eax, r9d
    jae .done
    cmp [r11 + rsi], edx
    jne .next
    mov r12d, [r11 + r8]
    mov [rcx + rax * 4], r12d
    inc eax
.next:
    add r11, [rbx + 16]
    dec r10d
    jmp .row
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; Frees the comments on the issues in gone_issues.
free_gone_comments:
    push rbx
    push r12
    sub rsp, 8
    lea rbx, [comments]
    mov r12d, [n_comments]
.row:
    test r12d, r12d
    jz .done
    mov eax, [rbx + CMT_ISSUE]
    test eax, eax
    jz .next
    xor ecx, ecx
.issue:
    cmp ecx, [gone_count]
    jae .next
    cmp [gone_issues + rcx * 4], eax
    je .free
    inc ecx
    jmp .issue
.free:
    mov edi, T_COMMENTS
    mov rsi, rbx
    call free_row
.next:
    add rbx, CMT_SIZE
    dec r12d
    jmp .row
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; Frees a team's images, files and all. edi = team
free_team_images:
    push rbx
    push r12
    push r13
    mov r12d, edi
    lea rbx, [images]
    mov r13d, [n_images]
.row:
    test r13d, r13d
    jz .done
    cmp dword [rbx + IMG_ID], 0
    je .next
    cmp [rbx + IMG_TEAM], r12d
    jne .next
    mov rdi, rbx
    call free_image
.next:
    add rbx, IMG_SIZE
    dec r13d
    jmp .row
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Deletes a team and every row of it, then gives its former members their
; team lists without it. edi = team
purge_team:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov edi, T_MEMBERS
    mov esi, MEM_TEAM
    mov edx, r12d
    lea rcx, [gone_users]
    mov r8d, MEM_USER
    mov r9d, TEAM_MEMBER_MAX
    call collect_where
    mov r13d, eax
    mov edi, T_ISSUES
    mov esi, ISS_TEAM
    mov edx, r12d
    lea rcx, [gone_issues]
    mov r8d, ISS_ID
    mov r9d, TEAM_ISSUE_MAX
    call collect_where
    mov [gone_count], eax
    call free_gone_comments
    xor ebx, ebx
.table:
    mov edi, [team_tables + rbx * 8]
    mov esi, [team_tables + rbx * 8 + 4]
    mov edx, r12d
    call free_where
    inc ebx
    cmp ebx, TEAM_TABLES
    jb .table
    mov edi, r12d                           ; after the messages took theirs
    call free_team_images
    mov edi, r12d
    call find_team
    mov edi, T_TEAMS
    mov rsi, rax
    call free_row
    call db_commit
    xor ebx, ebx
.conn:
    mov edi, ebx
    call conn_addr
    cmp [rax + C_TEAM], r12d
    jne .next_conn
    mov dword [rax + C_TEAM], 0
    and byte [rax + C_FLAGS], ~F_CHAT
.next_conn:
    inc ebx
    cmp ebx, MAX_CONN
    jb .conn
    xor ebx, ebx
.tell:
    cmp ebx, r13d
    jae .done
    mov edi, [gone_users + rbx * 4]
    call send_teams_to_user
    inc ebx
    jmp .tell
.done:
    pop r13
    pop r12
    pop rbx
    ret

; MSG_DELETE_TEAM: an owner deletes the team, once they've typed its key.
h_delete_team:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    call rd_u32
    mov r12d, eax
    call rd_str
    mov r13, rax
    mov r14d, edx
    call rd_ok
    test eax, eax
    jz .violation
    mov edi, r12d
    call require_owner
    test eax, eax
    jz .done
    mov edi, r12d
    call find_team
    test rax, rax
    jz .done
    mov rbx, rax
    movzx eax, byte [rbx + TEAM_KEY_LEN]
    cmp eax, r14d
    jne .wrong_key
    lea rdi, [rbx + TEAM_KEY]
    mov rsi, r13
    mov edx, r14d
    call mem_eq
    test eax, eax
    jz .wrong_key
    lea rdi, [s_log_deleted_team]
    lea rsi, [rbx + TEAM_KEY]
    mov edx, r14d
    call log_name
    mov edi, r12d
    call purge_team
    jmp .done
.wrong_key:
    lea rsi, [e_wrong_key]
    mov edx, e_wrong_key_len
    call send_error
    jmp .done
.violation:
    call kill_cur
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; edi = user -> eax = 1 if they're the only owner of one of their teams
sole_owner:
    push rbx
    push r12
    push r13
    mov r12d, edi
    lea rbx, [members]
    mov r13d, [n_members]
.row:
    test r13d, r13d
    jz .no
    cmp [rbx + MEM_USER], r12d
    jne .next
    cmp byte [rbx + MEM_ROLE], ROLE_OWNER
    jne .next
    mov edi, [rbx + MEM_TEAM]
    call count_owners
    cmp eax, 1
    jbe .yes
.next:
    add rbx, MEM_SIZE
    dec r13d
    jmp .row
.yes:
    mov eax, 1
    jmp .done
.no:
    xor eax, eax
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Sends cur the error for an account that owns a team alone.
owns_team_error:
    lea rsi, [e_owns_team]
    mov edx, e_owns_team_len
    jmp send_error

; MSG_DELETE_ACCOUNT: refuses the last owner of a team before hashing, then
; checks the password like a login would.
h_delete_account:
    push rbx
    push r12
    push r13
    call rd_str
    mov r12, rax
    mov r13d, edx
    call rd_ok
    test eax, eax
    jz .violation
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
    call sole_owner
    test eax, eax
    jnz .owns
    mov rax, [cur]
    mov edi, [rax + C_USER]
    call find_user
    test rax, rax
    jz .violation
    lea rcx, [rax + USER_SALT]
    mov edi, JOB_DELETE_ACCOUNT
    mov rsi, r12
    mov edx, r13d
    call start_job
    jmp .done
.owns:
    call owns_team_error
    jmp .done
.rate:
    lea rsi, [e_rate]
    mov edx, e_rate_len
    call send_error
    jmp .done
.wrong:
    lea rsi, [e_wrong_account_password]
    mov edx, e_wrong_account_password_len
    call password_failed
    jmp .done
.violation:
    call kill_cur
.done:
    pop r13
    pop r12
    pop rbx
    ret

; The password check before deleting cur's account finished. A team could
; have changed hands while it ran, so the owner check goes again.
; -> eax = 0, there's no second job
finish_delete_account:
    push rbx
    push r12
    sub rsp, 8
    mov r12, [cur]
    mov edi, [r12 + C_USER]
    call find_user
    test rax, rax
    jz .done
    mov rbx, rax
    lea rdi, [r12 + C_JOB + PB_T]
    lea rsi, [rbx + USER_HASH]
    mov edx, 32
    call ct_equal
    test eax, eax
    jz .wrong
    mov edi, [rbx + USER_ID]
    call sole_owner
    test eax, eax
    jnz .owns
    lea rdi, [s_log_deleted_user]
    lea rsi, [rbx + USER_NAME]
    movzx edx, byte [rbx + USER_NAME_LEN]
    call log_name
    mov edi, [rbx + USER_ID]
    call delete_user
    call log_out_cur
    jmp .done
.owns:
    call owns_team_error
    jmp .done
.wrong:
    lea rsi, [e_wrong_account_password]
    mov edx, e_wrong_account_password_len
    call password_failed
.done:
    xor eax, eax
    add rsp, 8
    pop r12
    pop rbx
    ret

; Frees the direct messages a user sent or got. edi = user
free_direct_messages:
    push rbx
    push r12
    push r13
    mov r12d, edi
    lea rbx, [messages]
    mov r13d, [n_messages]
.row:
    test r13d, r13d
    jz .done
    cmp dword [rbx + MS_ID], 0
    je .next
    mov eax, [rbx + MS_TO]
    cmp eax, r12d
    je .free
    cmp [rbx + MS_FROM], r12d
    jne .next
    test eax, eax
    jz .next                                ; #general
    test eax, CHANNEL_PEER
    jnz .next
.free:
    mov edi, T_MESSAGES
    mov rsi, rbx
    call free_row
.next:
    add rbx, MS_SIZE
    dec r13d
    jmp .row
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Frees a user's bans, noting their teams in ban_teams. edi = user
; -> eax = how many teams
free_user_bans:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12d, edi
    lea rbx, [bans]
    mov r13d, [n_bans]
    xor r14d, r14d
.row:
    test r13d, r13d
    jz .done
    cmp dword [rbx + BAN_TEAM], 0
    je .next
    cmp [rbx + BAN_USER], r12d
    jne .next
    cmp r14d, MAX_TEAMS
    jae .next
    mov eax, [rbx + BAN_TEAM]
    mov [ban_teams + r14 * 4], eax
    inc r14d
    mov edi, T_BANS
    mov rsi, rbx
    call free_row
.next:
    add rbx, BAN_SIZE
    dec r13d
    jmp .row
.done:
    mov eax, r14d
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Deletes a user: out of every team as if they'd left, then their direct
; messages, others' seen marks of those, their bans, unfinished uploads, sessions and the user.
; edi = user
delete_user:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov r12d, edi
    lea rbx, [members]
    mov r13d, [n_members]
.membership:
    test r13d, r13d
    jz .rest
    cmp [rbx + MEM_USER], r12d
    jne .next
    mov edi, [rbx + MEM_TEAM]
    mov esi, r12d
    mov rdx, rbx
    call drop_member
.next:
    add rbx, MEM_SIZE
    dec r13d
    jmp .membership
.rest:
    mov edi, r12d
    call free_direct_messages
    mov edi, T_SEEN                         ; leaving took their own marks, these are others' of them
    mov esi, SEEN_PEER
    mov edx, r12d
    call free_where
    mov edi, r12d
    call free_user_bans
    mov r14d, eax
    mov edi, r12d
    call drop_unattached
    mov edi, r12d
    mov esi, -1
    call end_other_sessions
    mov edi, r12d
    call find_user
    mov edi, T_USERS
    mov rsi, rax
    call free_row
    call db_commit
    xor ebp, ebp
.ban_list:
    cmp ebp, r14d
    jae .done
    mov edi, [ban_teams + rbp * 4]
    mov esi, -1
    call send_moderation
    inc ebp
    jmp .ban_list
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
