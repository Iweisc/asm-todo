; Teams and their members.

section .rodata
text e_team_name,       "team names are 1-32 printable characters"
text e_team_key,        "team keys are 2-5 letters, A-Z"
text e_too_many_teams,  "that's too many teams for one person"
text e_not_member,      "you're not a member of that team"
text e_owner_only,      "only the team's owner can do that"
text e_no_user,         "there's no user with that name"
text e_already_member,  "they're already a member"
text e_not_their_team,  "they're not a member of that team"
text e_team_full,       "that team is full"
text e_last_owner,      "a team needs an owner. Make someone else an owner first"

; Every new team starts with these labels: color, name.
default_labels:
    dd 0xeb5757
    db 3, "Bug"
    dd 0xbb87fc
    db 7, "Feature"
    dd 0x4ea7fc
    db 11, "Improvement"
    dd 0

section .bss
unassigned:     resq TEAM_ISSUE_MAX         ; issues a member removal touched

section .text

; Sends the teams a user belongs to. edi = connection index, esi = user id
send_teams:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15d, edi
    mov r12d, esi
    lea rdi, [msg_buf]
    mov esi, MSG_TEAMS
    call wr_u8
    mov r14, rdi                            ; count goes here
    inc rdi
    xor r13d, r13d
    lea rbx, [members]
    mov ecx, [n_members]
.row:
    test ecx, ecx
    jz .send
    cmp [rbx + MEM_USER], r12d
    jne .next
    push rcx
    push rdi
    mov edi, [rbx + MEM_TEAM]
    call find_team
    pop rdi
    pop rcx
    test rax, rax
    jz .next
    push rcx
    push rax
    mov esi, [rax + TEAM_ID]
    call wr_u32
    movzx esi, byte [rbx + MEM_ROLE]
    call wr_u8
    mov rax, [rsp]
    lea rsi, [rax + TEAM_KEY]
    movzx edx, byte [rax + TEAM_KEY_LEN]
    call wr_str
    pop rax
    lea rsi, [rax + TEAM_NAME]
    movzx edx, byte [rax + TEAM_NAME_LEN]
    call wr_str
    pop rcx
    inc r13d
.next:
    add rbx, MEM_SIZE
    dec ecx
    jmp .row
.send:
    mov [r14], r13b
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    mov edi, r15d
    call send_msg
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Every logged-in connection of a user gets their fresh team list. edi = user id
send_teams_to_user:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, edi
    xor ebx, ebx
.loop:
    mov edi, ebx
    call conn_addr
    cmp byte [rax + C_STATE], ST_OPEN
    jne .next
    cmp [rax + C_USER], r12d
    jne .next
    mov edi, ebx
    mov esi, r12d
    call send_teams
.next:
    inc ebx
    cmp ebx, MAX_CONN
    jb .loop
    add rsp, 8
    pop r12
    pop rbx
    ret

; Sends a built message to every connection viewing a team.
; edi = team, rsi = message, edx = length
broadcast_team:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12d, edi
    mov r13, rsi
    mov r14d, edx
    xor ebx, ebx
.loop:
    mov edi, ebx
    call conn_addr
    cmp byte [rax + C_STATE], ST_OPEN
    jne .next
    cmp dword [rax + C_USER], 0
    je .next
    cmp [rax + C_TEAM], r12d
    jne .next
    mov edi, ebx
    mov rsi, r13
    mov edx, r14d
    call send_msg
.next:
    inc ebx
    cmp ebx, MAX_CONN
    jb .loop
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; edi = team, esi = user -> eax = 1 if they have the team open right now
is_online:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov r13d, esi
    xor ebx, ebx
.loop:
    mov edi, ebx
    call conn_addr
    cmp byte [rax + C_STATE], ST_OPEN
    jne .next
    cmp [rax + C_USER], r13d
    jne .next
    cmp [rax + C_TEAM], r12d
    jne .next
    mov eax, 1
    jmp .done
.next:
    inc ebx
    cmp ebx, MAX_CONN
    jb .loop
    xor eax, eax
.done:
    pop r13
    pop r12
    pop rbx
    ret

; The member list with who's online, to everyone viewing the team. edi = team
broadcast_members:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, edi
    lea rdi, [msg_buf]
    mov esi, MSG_MEMBERS
    call wr_u8
    mov esi, r12d
    call wr_u32
    mov r14, rdi
    inc rdi
    mov r15, rdi
    xor r13d, r13d
    lea rbx, [members]
    mov ebp, [n_members]
.row:
    test ebp, ebp
    jz .send
    cmp [rbx + MEM_TEAM], r12d
    jne .next
    mov edi, [rbx + MEM_USER]
    call find_user
    test rax, rax
    jz .next
    mov [rsp], rax
    mov rdi, r15
    mov esi, [rax + USER_ID]
    call wr_u32
    movzx esi, byte [rbx + MEM_ROLE]
    call wr_u8
    mov r15, rdi
    mov edi, r12d
    mov esi, [rbx + MEM_USER]
    call is_online
    mov rdi, r15
    mov esi, eax
    call wr_u8
    mov rax, [rsp]
    lea rsi, [rax + USER_NAME]
    movzx edx, byte [rax + USER_NAME_LEN]
    call wr_str
    mov r15, rdi
    mov rdi, rbx
    call is_timed_out
    neg eax
    and eax, [rbx + MEM_TIMEOUT]            ; one that's over goes out as 0
    mov rdi, r15
    mov esi, eax
    call wr_u32
    movzx esi, word [rbx + MEM_ROLES]
    call wr_u16
    mov esi, r12d
    mov edx, [rbx + MEM_USER]
    call wr_nick
    mov r15, rdi
    inc r13d
.next:
    add rbx, MEM_SIZE
    dec ebp
    jmp .row
.send:
    mov [r14], r13b
    lea rsi, [msg_buf]
    mov rdx, r15
    sub rdx, rsi
    mov edi, r12d
    call broadcast_team
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; rsi = key, edx = length -> eax = 1 if it's 2-5 letters A-Z
valid_key:
    xor eax, eax
    cmp edx, TEAM_KEY_MIN
    jb .done
    cmp edx, TEAM_KEY_MAX
    ja .done
    xor ecx, ecx
.char:
    movzx r8d, byte [rsi + rcx]
    sub r8d, 'A'
    cmp r8d, 'Z' - 'A'
    ja .done
    inc ecx
    cmp ecx, edx
    jb .char
    mov eax, 1
.done:
    ret

; edi = team, esi = user, edx = role -> rax = the new row, or 0 if full.
; The row is touched, not committed.
add_member_row:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov edi, T_MEMBERS
    call alloc_row
    test rax, rax
    jz .done
    mov [rax + MEM_TEAM], ebx
    mov [rax + MEM_USER], r12d
    mov [rax + MEM_ROLE], r13b
    mov rbx, rax
    mov edi, T_MEMBERS
    mov rsi, rax
    call db_touch
    mov rax, rbx
.done:
    pop r13
    pop r12
    pop rbx
    ret

; edi = user -> eax = how many teams they belong to
count_user_teams:
    mov edx, edi
    mov edi, T_MEMBERS
    mov esi, MEM_USER
    jmp count_where

h_create_team:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    call rd_str
    mov r14, rax
    mov r15d, edx
    call rd_str
    mov r12, rax
    mov r13d, edx
    call rd_ok
    test eax, eax
    jz .violation
    mov rsi, r12
    mov edx, r13d
    mov ecx, TEAMNAME_MAX
    call valid_text
    test eax, eax
    jz .bad_name
    mov rsi, r14
    mov edx, r15d
    call valid_key
    test eax, eax
    jz .bad_key
    mov rax, [cur]
    mov edi, [rax + C_USER]
    call count_user_teams
    cmp eax, USER_TEAM_MAX
    jae .too_many

    mov edi, T_TEAMS
    call alloc_row
    test rax, rax
    jz .full
    mov rbx, rax
    mov eax, [next_team_id]
    mov [rbx + TEAM_ID], eax
    mov rax, [cur]
    mov esi, [rax + C_USER]
    mov edi, [rbx + TEAM_ID]
    mov edx, ROLE_OWNER
    call add_member_row
    test rax, rax
    jz .no_member_room
    inc dword [next_team_id]
    mov edi, [rbx + TEAM_ID]
    call add_default_roles
    mov dword [rbx + TEAM_NEXT_NUM], 1
    mov [rbx + TEAM_KEY_LEN], r15b
    lea rdi, [rbx + TEAM_KEY]
    mov rsi, r14
    mov ecx, r15d
    rep movsb
    mov [rbx + TEAM_NAME_LEN], r13b
    lea rdi, [rbx + TEAM_NAME]
    mov rsi, r12
    mov ecx, r13d
    rep movsb
    lea rsi, [default_labels]
    lea rbp, [rbx + TEAM_LABELS]
.label:
    mov eax, [rsi]
    test eax, eax
    jz .labels_done
    mov [rbp + LABEL_COLOR], eax
    movzx ecx, byte [rsi + 4]
    mov [rbp + LABEL_NAME_LEN], cl
    add rsi, 5
    lea rdi, [rbp + LABEL_NAME]
    rep movsb
    add rbp, LABEL_SIZE
    jmp .label
.labels_done:
    mov edi, T_TEAMS
    mov rsi, rbx
    call db_touch
    call db_commit
    mov rax, [cur]
    mov edi, [rax + C_USER]
    call send_teams_to_user
    jmp .done
.no_member_room:
    mov dword [rbx + TEAM_ID], 0            ; never committed, so it's simply free again
    jmp .full
.violation:
    call kill_cur
    jmp .done
.bad_name:
    lea rsi, [e_team_name]
    mov edx, e_team_name_len
    jmp .error
.bad_key:
    lea rsi, [e_team_key]
    mov edx, e_team_key_len
    jmp .error
.too_many:
    lea rsi, [e_too_many_teams]
    mov edx, e_too_many_teams_len
    jmp .error
.full:
    lea rsi, [e_full]
    mov edx, e_full_len
.error:
    call send_error
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = team -> eax = 1 if cur is its owner. Sends the matching error if not.
require_owner:
    mov rax, [cur]
    mov esi, [rax + C_USER]
    call find_member
    test rax, rax
    jz .not_member
    cmp byte [rax + MEM_ROLE], ROLE_OWNER
    jne .not_owner
    mov eax, 1
    ret
.not_member:
    lea rsi, [e_not_member]
    mov edx, e_not_member_len
    jmp .error
.not_owner:
    lea rsi, [e_owner_only]
    mov edx, e_owner_only_len
.error:
    call send_error
    xor eax, eax
    ret

h_add_member:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    call rd_u32
    mov r14d, eax
    call rd_str
    mov r12, rax
    mov r13d, edx
    call rd_ok
    test eax, eax
    jz .violation
    mov edi, r14d
    mov esi, PERM_INVITE
    call require_perm
    test rax, rax
    jz .done
    mov rsi, r12
    mov edx, r13d
    call find_user_by_name
    test rax, rax
    jz .no_user
    mov rbx, rax
    mov edi, r14d
    mov esi, [rbx + USER_ID]
    call find_member
    test rax, rax
    jnz .already
    mov edi, r14d
    mov esi, [rbx + USER_ID]
    call find_ban
    test rax, rax
    jnz .banned
    mov edi, T_MEMBERS
    mov esi, MEM_TEAM
    mov edx, r14d
    call count_where
    cmp eax, TEAM_MEMBER_MAX
    jae .team_full
    mov edi, [rbx + USER_ID]
    call count_user_teams
    cmp eax, USER_TEAM_MAX
    jae .too_many
    mov edi, r14d
    mov esi, [rbx + USER_ID]
    mov edx, ROLE_MEMBER
    call add_member_row
    test rax, rax
    jz .full
    mov edi, r14d
    mov esi, AU_INVITE
    mov edx, [rbx + USER_ID]
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call audit_add
    call db_commit
    mov edi, [rbx + USER_ID]
    call send_teams_to_user
    mov edi, r14d
    call broadcast_members
    mov edi, r14d
    mov esi, -1
    call send_moderation
    jmp .done
.violation:
    call kill_cur
    jmp .done
.no_user:
    lea rsi, [e_no_user]
    mov edx, e_no_user_len
    jmp .error
.banned:
    lea rsi, [e_banned]
    mov edx, e_banned_len
    jmp .error
.already:
    lea rsi, [e_already_member]
    mov edx, e_already_member_len
    jmp .error
.team_full:
    lea rsi, [e_team_full]
    mov edx, e_team_full_len
    jmp .error
.too_many:
    lea rsi, [e_too_many_teams]
    mov edx, e_too_many_teams_len
    jmp .error
.full:
    lea rsi, [e_full]
    mov edx, e_full_len
.error:
    call send_error
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Whoever was removed stops seeing the team immediately. edi = team, esi = user
unsubscribe_user:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov r13d, esi
    xor ebx, ebx
.conn:
    mov edi, ebx
    call conn_addr
    cmp [rax + C_USER], r13d
    jne .next
    cmp [rax + C_TEAM], r12d
    jne .next
    mov dword [rax + C_TEAM], 0
.next:
    inc ebx
    cmp ebx, MAX_CONN
    jb .conn
    pop r13
    pop r12
    pop rbx
    ret

; MSG_REMOVE_MEMBER: leaving, or kicking someone below you.
h_remove_member:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call rd_u32
    mov r12d, eax                           ; team
    call rd_u32
    mov r13d, eax                           ; user being removed
    call rd_str
    mov r14, rax
    mov r15d, edx                           ; reason
    call rd_ok
    test eax, eax
    jz .violation
    mov rsi, r14
    mov edx, r15d
    call valid_reason
    test eax, eax
    jz .bad_reason
    mov rax, [cur]
    cmp [rax + C_USER], r13d
    je .leave
    mov edi, r12d
    mov esi, r13d
    mov edx, PERM_KICK
    call moderated_member
    test rax, rax
    jz .done
    mov rbx, rax
    mov edi, r12d
    mov esi, AU_KICK
    mov edx, r13d
    xor ecx, ecx
    mov r8, r14
    mov r9d, r15d
    call audit_add
    mov edi, r12d
    mov esi, r13d
    mov rdx, rbx
    call drop_member
    mov edi, r12d
    mov esi, -1
    call send_moderation
    jmp .done
.leave:
    mov edi, r12d
    mov esi, r13d
    call find_member
    test rax, rax
    jz .not_member
    mov rbx, rax
    cmp byte [rax + MEM_ROLE], ROLE_OWNER
    jne .drop
    mov edi, r12d
    call count_owners
    cmp eax, 1
    jbe .last_owner
.drop:
    mov edi, r12d
    mov esi, r13d
    mov rdx, rbx
    call drop_member
    jmp .done
.violation:
    call kill_cur
    jmp .done
.bad_reason:
    lea rsi, [e_reason]
    mov edx, e_reason_len
    jmp .error
.not_member:
    lea rsi, [e_not_member]
    mov edx, e_not_member_len
    jmp .error
.last_owner:
    lea rsi, [e_last_owner]
    mov edx, e_last_owner_len
.error:
    call send_error
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Takes someone out of a team. Their seen marks and nickname go too, and they're
; unassigned from its issues, one EV_ISSUE each so everyone's view stays in
; step. Commits whatever else the caller touched along with it.
; edi = team, esi = user, rdx = their member row
drop_member:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov edi, T_MEMBERS
    mov rsi, rdx
    call free_row
    mov edi, r12d
    mov esi, r13d
    call forget_seen
    mov edi, r12d
    mov esi, r13d
    call forget_nick
    mov edi, r12d
    call find_team
    mov r15, rax
    mov ebp, [r15 + TEAM_SEQ]               ; the seq before the first event
    call now_unix
    mov [rsp], eax
    lea rbx, [issues]
    xor r14d, r14d                          ; issues unassigned
    mov ecx, [n_issues]
.issue:
    test ecx, ecx
    jz .commit
    cmp [rbx + ISS_TEAM], r12d
    jne .next_issue
    cmp [rbx + ISS_ASSIGNEE], r13d
    jne .next_issue
    mov dword [rbx + ISS_ASSIGNEE], 0
    mov eax, [rsp]
    mov [rbx + ISS_UPDATED], eax
    mov [unassigned + r14 * 8], rbx
    inc r14d
    inc dword [r15 + TEAM_SEQ]
    push rcx
    mov edi, T_ISSUES
    mov rsi, rbx
    call db_touch
    pop rcx
.next_issue:
    add rbx, ISSUE_SIZE
    dec ecx
    jmp .issue
.commit:
    mov edi, T_TEAMS
    mov rsi, r15
    call db_touch
    call db_commit

    mov edi, r12d
    mov esi, r13d
    call unsubscribe_user

    xor ebx, ebx
.event:
    cmp ebx, r14d
    jae .events_sent
    inc ebp
    mov rdi, r15
    mov esi, EV_ISSUE
    mov edx, ebp
    call begin_event_seq
    mov rsi, [unassigned + rbx * 8]
    call wr_issue
    mov esi, r12d
    call finish_event
    inc ebx
    jmp .event
.events_sent:
    mov edi, r13d
    call send_teams_to_user
    mov edi, r12d
    call broadcast_members
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = team -> eax = how many owners it has
count_owners:
    lea rcx, [members]
    mov edx, [n_members]
    xor eax, eax
.row:
    test edx, edx
    jz .done
    cmp [rcx + MEM_TEAM], edi
    jne .next
    cmp byte [rcx + MEM_ROLE], ROLE_OWNER
    jne .next
    inc eax
.next:
    add rcx, MEM_SIZE
    dec edx
    jmp .row
.done:
    ret

; Every member of a team gets their fresh team list. edi = team
send_teams_to_members:
    push rbx
    push r12
    push r13
    mov r12d, edi
    lea rbx, [members]
    mov r13d, [n_members]
.row:
    test r13d, r13d
    jz .done
    cmp [rbx + MEM_TEAM], r12d
    jne .next
    mov edi, [rbx + MEM_USER]
    call send_teams_to_user
.next:
    add rbx, MEM_SIZE
    dec r13d
    jmp .row
.done:
    pop r13
    pop r12
    pop rbx
    ret

; MSG_SET_ROLE: an owner makes someone an owner or a member. The last owner
; can't stop being one, and becoming one ends a timeout.
h_set_role:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    call rd_u32
    mov r12d, eax                           ; team
    call rd_u32
    mov r13d, eax                           ; user
    call rd_u8
    mov ebx, eax                            ; role
    call rd_ok
    test eax, eax
    jz .violation
    dec ebx
    cmp ebx, ROLE_MEMBER - 1                ; ROLE_OWNER or ROLE_MEMBER
    ja .violation
    inc ebx
    mov edi, r12d
    call require_owner
    test eax, eax
    jz .done
    mov edi, r12d
    mov esi, r13d
    call find_member
    test rax, rax
    jz .not_theirs
    mov r14, rax
    cmp [r14 + MEM_ROLE], bl
    je .done
    cmp byte [r14 + MEM_ROLE], ROLE_OWNER
    jne .set
    mov edi, r12d
    call count_owners
    cmp eax, 1
    jbe .last_owner
.set:
    mov [r14 + MEM_ROLE], bl
    cmp ebx, ROLE_OWNER
    jne .touch
    mov dword [r14 + MEM_TIMEOUT], 0
.touch:
    mov edi, T_MEMBERS
    mov rsi, r14
    call db_touch
    mov edi, r12d
    mov esi, AU_ROLE
    mov edx, r13d
    mov ecx, ebx
    xor r8d, r8d
    xor r9d, r9d
    call audit_add
    call db_commit
    mov edi, r13d
    call send_teams_to_user
    mov edi, r12d
    call permissions_changed
    jmp .done
.violation:
    call kill_cur
    jmp .done
.not_theirs:
    lea rsi, [e_not_their_team]
    mov edx, e_not_their_team_len
    jmp .error
.last_owner:
    lea rsi, [e_last_owner]
    mov edx, e_last_owner_len
.error:
    call send_error
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; MSG_RENAME_TEAM: PERM_MANAGE_TEAM. Every member's team list shows the new name.
h_rename_team:
    push rbx
    push r12
    push r13
    call rd_u32
    mov ebx, eax
    call rd_str
    mov r12, rax
    mov r13d, edx
    call rd_ok
    test eax, eax
    jz .violation
    mov rsi, r12
    mov edx, r13d
    mov ecx, TEAMNAME_MAX
    call valid_text
    test eax, eax
    jz .bad_name
    mov edi, ebx
    mov esi, PERM_MANAGE_TEAM
    call require_perm
    test rax, rax
    jz .done
    mov edi, ebx
    call find_team
    test rax, rax
    jz .done
    mov [rax + TEAM_NAME_LEN], r13b
    lea rdi, [rax + TEAM_NAME]
    mov rsi, r12
    mov ecx, r13d
    rep movsb
    mov edi, T_TEAMS
    mov rsi, rax
    call db_touch
    mov edi, ebx
    mov esi, AU_RENAME_TEAM
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call audit_add
    call db_commit
    mov edi, ebx
    call send_teams_to_members
    mov edi, ebx
    mov esi, -1
    call send_moderation
    jmp .done
.violation:
    call kill_cur
    jmp .done
.bad_name:
    lea rsi, [e_team_name]
    mov edx, e_team_name_len
    call send_error
.done:
    pop r13
    pop r12
    pop rbx
    ret
