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
text e_owner_leave,     "owners can't leave their own team"

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
    mov [rax + MEM_ROLE], r13d
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
    cmp dword [rax + MEM_ROLE], ROLE_OWNER
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
    call require_owner
    test eax, eax
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
    call db_commit
    mov edi, [rbx + USER_ID]
    call send_teams_to_user
    mov edi, r14d
    call broadcast_members
    jmp .done
.violation:
    call kill_cur
    jmp .done
.no_user:
    lea rsi, [e_no_user]
    mov edx, e_no_user_len
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

; Removing someone (or leaving) also unassigns them from the team's issues,
; one EV_ISSUE each so everyone's view stays in step.
h_remove_member:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    call rd_u32
    mov r12d, eax                           ; team
    call rd_u32
    mov r13d, eax                           ; user being removed
    call rd_ok
    test eax, eax
    jz .violation
    mov rax, [cur]
    mov r14d, [rax + C_USER]
    mov edi, r12d
    mov esi, r14d
    call find_member
    test rax, rax
    jz .not_member
    movzx ebx, byte [rax + MEM_ROLE]
    mov edi, r12d
    mov esi, r13d
    call find_member
    test rax, rax
    jz .not_theirs
    cmp r13d, r14d
    jne .removing_someone
    cmp ebx, ROLE_OWNER                     ; leaving
    je .owner_leave
    jmp .remove
.removing_someone:
    cmp ebx, ROLE_OWNER
    jne .owner_only
.remove:
    mov edi, T_MEMBERS
    mov rsi, rax
    call free_row
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

    ; Whoever was removed stops seeing the team immediately.
    xor ebx, ebx
.unsubscribe:
    mov edi, ebx
    call conn_addr
    cmp [rax + C_USER], r13d
    jne .next_conn
    cmp [rax + C_TEAM], r12d
    jne .next_conn
    mov dword [rax + C_TEAM], 0
.next_conn:
    inc ebx
    cmp ebx, MAX_CONN
    jb .unsubscribe

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
    jmp .done
.violation:
    call kill_cur
    jmp .done
.not_member:
    lea rsi, [e_not_member]
    mov edx, e_not_member_len
    jmp .error
.not_theirs:
    lea rsi, [e_not_their_team]
    mov edx, e_not_their_team_len
    jmp .error
.owner_leave:
    lea rsi, [e_owner_leave]
    mov edx, e_owner_leave_len
    jmp .error
.owner_only:
    lea rsi, [e_owner_only]
    mov edx, e_owner_only_len
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
