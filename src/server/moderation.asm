; Moderation: bans, timeouts and the audit log. Who may use them on whom is
; in roles.asm. Kicking is h_remove_member in teams.asm, which bans share
; drop_member with.

section .rodata
text e_outranked,       "you can only do that to someone below your role"
text e_timed_out,       "you're timed out in this team, so you can only read for now"
text e_banned,          "they're banned from this team. Unban them first"
text e_not_banned,      "they're not banned from this team"
text e_bans_full,       "this team has banned as many people as it can"
text e_timeout_admin,   "owners and admins can't be timed out"
text e_yourself,        "you can't do that to yourself"
text e_reason,          "reasons are up to 100 printable characters"

section .text

; rdi = member row -> eax = 1 if they're timed out right now
is_timed_out:
    push rbx
    mov ebx, [rdi + MEM_TIMEOUT]
    xor eax, eax
    test ebx, ebx
    jz .done
    call now_unix
    cmp ebx, eax
    seta al
    movzx eax, al
.done:
    pop rbx
    ret

; edi = team -> rax = cur's member row if they may change things in it, or
; 0 once the error is sent
writable_member:
    push rbx
    mov rax, [cur]
    mov esi, [rax + C_USER]
    call find_member
    test rax, rax
    jz .not_member
    mov rbx, rax
    mov rdi, rax
    call is_timed_out
    test eax, eax
    jnz .timed_out
    mov rax, rbx
    pop rbx
    ret
.not_member:
    lea rsi, [e_not_member]
    mov edx, e_not_member_len
    jmp .error
.timed_out:
    lea rsi, [e_timed_out]
    mov edx, e_timed_out_len
.error:
    call send_error
    xor eax, eax
    pop rbx
    ret

; Checks cur may kick, ban, time out or nickname a member.
; edi = team, esi = user, edx = PERM_* -> rax = the member's row, or 0 once the error is sent
moderated_member:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov esi, edx
    call require_perm
    test rax, rax
    jz .done
    mov r13, rax
    mov rax, [cur]
    cmp [rax + C_USER], r12d
    je .yourself
    mov edi, ebx
    mov esi, r12d
    call find_member
    test rax, rax
    jz .not_theirs
    mov rbx, rax
    mov rdi, r13
    mov rsi, rax
    call outranks
    test eax, eax
    jz .outranked
    mov rax, rbx
    jmp .done
.yourself:
    lea rsi, [e_yourself]
    mov edx, e_yourself_len
    jmp .error
.not_theirs:
    lea rsi, [e_not_their_team]
    mov edx, e_not_their_team_len
    jmp .error
.outranked:
    lea rsi, [e_outranked]
    mov edx, e_outranked_len
.error:
    call send_error
    xor eax, eax
.done:
    pop r13
    pop r12
    pop rbx
    ret

; rsi = reason, edx = length -> eax = 1 if it's empty or fits as a name would
valid_reason:
    mov eax, 1
    test edx, edx
    jz .done
    mov ecx, REASON_MAX
    jmp valid_text
.done:
    ret

; edi = team, esi = user -> rax = their ban row, or 0
find_ban:
    lea rax, [bans]
    mov ecx, [n_bans]
    test edi, edi
    jz .none
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + BAN_TEAM], edi
    jne .next
    cmp [rax + BAN_USER], esi
    je .done
.next:
    add rax, BAN_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; edi = team, esi = user, rdx = reason, ecx = its length -> eax = 0 if the
; team or the table has no room. The row is touched, not committed.
add_ban:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    mov edi, T_BANS
    mov esi, BAN_TEAM
    mov edx, ebx
    call count_where
    cmp eax, TEAM_BAN_MAX
    jae .full
    mov edi, T_BANS
    call alloc_row
    test rax, rax
    jz .full
    mov [rax + BAN_TEAM], ebx
    mov [rax + BAN_USER], r12d
    mov rbx, rax
    call now_unix
    mov [rbx + BAN_AT], eax
    mov [rbx + BAN_REASON_LEN], r14b
    lea rdi, [rbx + BAN_REASON]
    mov rsi, r13
    mov ecx, r14d
    rep movsb
    mov edi, T_BANS
    mov rsi, rbx
    call db_touch
    mov eax, 1
    jmp .done
.full:
    xor eax, eax
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; A wiped row for a new audit entry, the oldest entry's once the table is full.
; -> rax = the row, edx = the seq it gets
audit_row:
    push rbx
    push r12
    push r13
    lea rcx, [audit]
    mov r8d, [n_audit]
    xor ebx, ebx                            ; the highest seq
    xor r12d, r12d                          ; the oldest row
    mov r13d, -1                            ; and its seq
.scan:
    test r8d, r8d
    jz .alloc
    cmp dword [rcx + AUD_TEAM], 0
    je .next
    mov eax, [rcx + AUD_SEQ]
    cmp eax, ebx
    cmova ebx, eax
    cmp eax, r13d
    jae .next
    mov r13d, eax
    mov r12, rcx
.next:
    add rcx, AUD_SIZE
    dec r8d
    jmp .scan
.alloc:
    mov edi, T_AUDIT
    call alloc_row
    test rax, rax
    jnz .done
    mov rdi, r12
    mov esi, AUD_SIZE
    call wipe
    mov rax, r12
.done:
    lea edx, [ebx + 1]
    pop r13
    pop r12
    pop rbx
    ret

; Records what cur did. The row is touched, not committed.
; edi = team, esi = AU_*, edx = target, ecx = extra, r8 = reason, r9d = its length
audit_add:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov ebx, edi
    mov ebp, esi
    mov r12d, edx
    mov r13d, ecx
    mov r14, r8
    mov r15d, r9d
    call audit_row
    mov [rax + AUD_TEAM], ebx
    mov [rax + AUD_SEQ], edx
    mov rbx, rax
    mov rax, [cur]
    mov eax, [rax + C_USER]
    mov [rbx + AUD_ACTOR], eax
    mov [rbx + AUD_TARGET], r12d
    mov [rbx + AUD_EXTRA], r13d
    mov [rbx + AUD_KIND], bpl
    mov [rbx + AUD_REASON_LEN], r15b
    call now_unix
    mov [rbx + AUD_AT], eax
    lea rdi, [rbx + AUD_REASON]
    mov rsi, r14
    mov ecx, r15d
    rep movsb
    mov edi, T_AUDIT
    mov rsi, rbx
    call db_touch
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; rdi = cursor, esi = user id -> rdi advanced past their name as a str, empty for nobody
wr_user_name:
    push rdi
    mov edi, esi
    call find_user
    pop rdi
    xor edx, edx
    test rax, rax
    jz .write
    lea rsi, [rax + USER_NAME]
    movzx edx, byte [rax + USER_NAME_LEN]
.write:
    jmp wr_str

; Builds MSG_BANS for a team in msg_buf. edi = team -> rdx = its length
build_bans:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    lea rdi, [msg_buf]
    mov esi, MSG_BANS
    call wr_u8
    mov esi, r12d
    call wr_u32
    mov r14, rdi                            ; the count goes here
    inc rdi
    xor r13d, r13d
    lea rbx, [bans]
    mov r15d, [n_bans]
.row:
    test r15d, r15d
    jz .built
    cmp [rbx + BAN_TEAM], r12d
    jne .next
    cmp r13d, TEAM_BAN_MAX
    jae .built
    mov esi, [rbx + BAN_USER]
    call wr_u32
    mov esi, [rbx + BAN_AT]
    call wr_u32
    mov esi, [rbx + BAN_USER]
    call wr_user_name
    lea rsi, [rbx + BAN_REASON]
    movzx edx, byte [rbx + BAN_REASON_LEN]
    call wr_str
    inc r13d
.next:
    add rbx, BAN_SIZE
    dec r15d
    jmp .row
.built:
    mov [r14], r13b
    lea rax, [msg_buf]
    mov rdx, rdi
    sub rdx, rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; edi = team, esi = a seq -> rax = the team's newest audit row older than
; it, or 0
audit_before:
    lea rcx, [audit]
    mov r8d, [n_audit]
    xor eax, eax
    xor edx, edx                            ; the best seq so far
.row:
    test r8d, r8d
    jz .done
    cmp [rcx + AUD_TEAM], edi
    jne .next
    mov r9d, [rcx + AUD_SEQ]
    cmp r9d, esi
    jae .next
    cmp r9d, edx
    jbe .next
    mov edx, r9d
    mov rax, rcx
.next:
    add rcx, AUD_SIZE
    dec r8d
    jmp .row
.done:
    ret

; Builds MSG_AUDIT for a team in msg_buf, its newest AUDIT_SHOWN entries.
; edi = team -> rdx = its length
build_audit:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    lea rdi, [msg_buf]
    mov esi, MSG_AUDIT
    call wr_u8
    mov esi, r12d
    call wr_u32
    mov r14, rdi                            ; the count goes here
    inc rdi
    xor r13d, r13d
    mov r15d, -1                            ; the last seq written
.entry:
    cmp r13d, AUDIT_SHOWN
    jae .built
    push rdi
    mov edi, r12d
    mov esi, r15d
    call audit_before
    pop rdi
    test rax, rax
    jz .built
    mov rbx, rax
    mov r15d, [rbx + AUD_SEQ]
    movzx esi, byte [rbx + AUD_KIND]
    call wr_u8
    mov esi, [rbx + AUD_ACTOR]
    call wr_u32
    mov esi, [rbx + AUD_TARGET]
    call wr_u32
    mov esi, [rbx + AUD_AT]
    call wr_u32
    mov esi, [rbx + AUD_EXTRA]
    call wr_u32
    mov esi, [rbx + AUD_ACTOR]
    call wr_user_name
    mov esi, [rbx + AUD_TARGET]
    call wr_user_name
    lea rsi, [rbx + AUD_REASON]
    movzx edx, byte [rbx + AUD_REASON_LEN]
    call wr_str
    inc r13d
    jmp .entry
.built:
    mov [r14], r13b
    lea rax, [msg_buf]
    mov rdx, rdi
    sub rdx, rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Builds a list with rcx and sends it to those viewing a team with a
; permission. A single connection without it doesn't get it built.
; edi = team, esi = the only connection to send it to, or -1 for all, edx = PERM_*,
; rcx = builder taking edi = team and returning rdx = length
send_listed:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14, rcx
    cmp r12d, -1
    je .build
    mov edi, r12d
    mov esi, ebx
    call conn_has_perm
    test eax, eax
    jz .done
.build:
    mov edi, ebx
    call r14
    mov ecx, edx
    mov edi, ebx
    mov esi, r12d
    mov edx, r13d
    call perm_send
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; The team's bans, audit log and AutoMod rules, to whoever viewing it may
; see each. edi = team, esi = the only connection to send them to, or -1 for all
send_moderation:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov edx, PERM_BAN
    lea rcx, [build_bans]
    call send_listed
    mov edi, ebx
    mov esi, r12d
    mov edx, PERM_VIEW_AUDIT
    lea rcx, [build_audit]
    call send_listed
    mov edi, ebx
    mov esi, r12d
    mov edx, PERM_MANAGE_AUTOMOD
    lea rcx, [build_automod]
    call send_listed
    add rsp, 8
    pop r12
    pop rbx
    ret

; MSG_BAN: takes a member out of the team, keeps them from being invited
; back, and deletes their channel messages from the last seconds asked for.
h_ban:
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
    mov r13d, eax                           ; user
    call rd_u32
    mov ebp, eax                            ; seconds of their messages to delete
    call rd_str
    mov r14, rax
    mov r15d, edx                           ; reason
    call rd_ok
    test eax, eax
    jz .violation
    cmp ebp, BAN_HISTORY_MAX
    ja .violation
    mov rsi, r14
    mov edx, r15d
    call valid_reason
    test eax, eax
    jz .bad_reason
    mov edi, r12d
    mov esi, r13d
    mov edx, PERM_BAN
    call moderated_member
    test rax, rax
    jz .done
    mov rbx, rax
    mov edi, r12d
    mov esi, r13d
    mov rdx, r14
    mov ecx, r15d
    call add_ban
    test eax, eax
    jz .full
    mov edi, r12d
    mov esi, AU_BAN
    mov edx, r13d
    mov ecx, ebp
    mov r8, r14
    mov r9d, r15d
    call audit_add
    mov edi, r12d
    mov esi, r13d
    mov edx, ebp
    call delete_recent_messages
    mov ebp, eax
    mov edi, r12d
    mov esi, r13d
    mov rdx, rbx
    call drop_member
    mov edi, ebp
    call announce_deleted
    mov edi, r12d
    mov esi, -1
    call send_moderation
    jmp .done
.violation:
    call kill_cur
    jmp .done
.bad_reason:
    lea rsi, [e_reason]
    mov edx, e_reason_len
    jmp .error
.full:
    lea rsi, [e_bans_full]
    mov edx, e_bans_full_len
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

; MSG_UNBAN: lets someone be invited again. It doesn't add them back.
h_unban:
    push rbx
    push r12
    push r13
    call rd_u32
    mov r12d, eax                           ; team
    call rd_u32
    mov r13d, eax                           ; user
    call rd_ok
    test eax, eax
    jz .violation
    mov edi, r12d
    mov esi, PERM_BAN
    call require_perm
    test rax, rax
    jz .done
    mov edi, r12d
    mov esi, r13d
    call find_ban
    test rax, rax
    jz .not_banned
    mov edi, T_BANS
    mov rsi, rax
    call free_row
    mov edi, r12d
    mov esi, AU_UNBAN
    mov edx, r13d
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call audit_add
    call db_commit
    mov edi, r12d
    mov esi, -1
    call send_moderation
    jmp .done
.violation:
    call kill_cur
    jmp .done
.not_banned:
    lea rsi, [e_not_banned]
    mov edx, e_not_banned_len
    call send_error
.done:
    pop r13
    pop r12
    pop rbx
    ret

; MSG_TIMEOUT: a member can only read for a while, or again ends early.
; Owners and admins can't be timed out.
h_timeout:
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
    mov r13d, eax                           ; user
    call rd_u32
    mov ebp, eax                            ; seconds, 0 to end it
    call rd_str
    mov r14, rax
    mov r15d, edx                           ; reason
    call rd_ok
    test eax, eax
    jz .violation
    cmp ebp, TIMEOUT_MAX
    ja .violation
    mov rsi, r14
    mov edx, r15d
    call valid_reason
    test eax, eax
    jz .bad_reason
    mov edi, r12d
    mov esi, r13d
    mov edx, PERM_TIMEOUT
    call moderated_member
    test rax, rax
    jz .done
    mov rbx, rax
    mov rdi, rax
    call member_perms
    test eax, PERM_ADMIN
    jnz .admin
    test ebp, ebp
    jz .end
    call now_unix
    add eax, ebp
    mov [rbx + MEM_TIMEOUT], eax
    mov esi, AU_TIMEOUT
    jmp .record
.end:
    mov rdi, rbx
    call is_timed_out
    test eax, eax
    jz .done                                ; nothing to end
    mov dword [rbx + MEM_TIMEOUT], 0
    mov esi, AU_UNTIMEOUT
.record:
    mov edi, r12d
    mov edx, r13d
    mov ecx, ebp
    mov r8, r14
    mov r9d, r15d
    call audit_add
    mov edi, T_MEMBERS
    mov rsi, rbx
    call db_touch
    call db_commit
    mov edi, r12d
    call broadcast_members
    mov edi, r12d
    mov esi, -1
    call send_moderation
    jmp .done
.violation:
    call kill_cur
    jmp .done
.bad_reason:
    lea rsi, [e_reason]
    mov edx, e_reason_len
    jmp .error
.admin:
    lea rsi, [e_timeout_admin]
    mov edx, e_timeout_admin_len
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
