; Roles and permissions. A member has @everyone's permissions and their
; roles', owners have every one, and so does anyone with PERM_ADMIN. A member
; ranks as their highest role's position, owners above everyone. Roles,
; their holders and the permissions they give can only be changed below the
; changer's rank, and nobody gives a permission they don't have.

section .rodata
text e_no_permission,   "you don't have permission to do that in this team"
text e_role_name,       "role names are 1-24 printable characters"
text e_roles_full,      "that team has as many roles as it can have"
text e_no_role,         "that role doesn't exist anymore"
text e_role_rank,       "you can only change roles below your highest one"
text e_role_perms,      "you can only give permissions you have yourself"
text moderator_name,    "Moderator"

section .text

; edi = team, esi = slot -> rax = its row, or 0
find_role:
    lea rax, [roles]
    mov ecx, [n_roles]
    test edi, edi
    jz .none
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + RL_TEAM], edi
    jne .next
    movzx edx, byte [rax + RL_SLOT]
    cmp edx, esi
    je .done
.next:
    add rax, RL_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; edi = team -> eax = @everyone's permissions
everyone_perms:
    sub rsp, 8
    xor esi, esi
    call find_role
    add rsp, 8
    test rax, rax
    jz .default
    mov eax, [rax + RL_PERMS]
    ret
.default:
    mov eax, PERM_EVERYONE
    ret

; rdi = member row -> eax = their permissions in its team
member_perms:
    mov eax, PERM_ALL
    cmp byte [rdi + MEM_ROLE], ROLE_OWNER
    je .done
    push rbx
    push r12
    push r13
    mov r12d, [rdi + MEM_TEAM]
    movzx r13d, word [rdi + MEM_ROLES]
    mov edi, r12d
    call everyone_perms
    mov ebx, eax
    lea rcx, [roles]
    mov r8d, [n_roles]
.row:
    test r8d, r8d
    jz .admin
    cmp [rcx + RL_TEAM], r12d
    jne .next
    movzx edx, byte [rcx + RL_SLOT]
    bt r13d, edx
    jnc .next
    or ebx, [rcx + RL_PERMS]
.next:
    add rcx, RL_SIZE
    dec r8d
    jmp .row
.admin:
    mov eax, ebx
    test ebx, PERM_ADMIN
    jz .out
    mov eax, PERM_ALL
.out:
    pop r13
    pop r12
    pop rbx
.done:
    ret

; rdi = member row -> eax = their rank: their highest role's position, or
; above every position for an owner
member_rank:
    mov eax, ROLE_SLOTS + 1
    cmp byte [rdi + MEM_ROLE], ROLE_OWNER
    je .done
    mov r9d, [rdi + MEM_TEAM]
    movzx r10d, word [rdi + MEM_ROLES]
    xor eax, eax
    lea rcx, [roles]
    mov r8d, [n_roles]
.row:
    test r8d, r8d
    jz .done
    cmp [rcx + RL_TEAM], r9d
    jne .next
    movzx edx, byte [rcx + RL_SLOT]
    bt r10d, edx
    jnc .next
    movzx edx, byte [rcx + RL_POS]
    cmp edx, eax
    cmova eax, edx
.next:
    add rcx, RL_SIZE
    dec r8d
    jmp .row
.done:
    ret

; rdi = actor's member row, rsi = target's -> eax = 1 if the actor ranks above
; the target. Owners rank above everyone, other owners too.
outranks:
    mov eax, 1
    cmp byte [rdi + MEM_ROLE], ROLE_OWNER
    je .done
    push rbx
    push r12
    sub rsp, 8
    mov r12, rsi
    call member_rank
    mov ebx, eax
    mov rdi, r12
    call member_rank
    cmp ebx, eax
    seta al
    movzx eax, al
    add rsp, 8
    pop r12
    pop rbx
.done:
    ret

; edi = team, esi = PERM_* -> rax = cur's member row if they have it and
; aren't timed out, or 0 once the error is sent
require_perm:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, esi
    call writable_member
    test rax, rax
    jz .done
    mov rbx, rax
    mov rdi, rax
    call member_perms
    test eax, r12d
    jz .denied
    mov rax, rbx
    jmp .done
.denied:
    lea rsi, [e_no_permission]
    mov edx, e_no_permission_len
    call send_error
    xor eax, eax
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; edi = connection index, esi = team -> rax = the member row of the user
; viewing the team on it, or 0
viewing_member:
    push rbx
    mov ebx, esi
    call conn_addr
    mov rcx, rax
    xor eax, eax
    cmp byte [rcx + C_STATE], ST_OPEN
    jne .done
    mov esi, [rcx + C_USER]
    test esi, esi
    jz .done
    cmp [rcx + C_TEAM], ebx
    jne .done
    mov edi, ebx
    call find_member
.done:
    pop rbx
    ret

; edi = connection index, esi = team, edx = PERM_* -> eax = 1 if whoever views
; the team on it has the permission
conn_has_perm:
    push rbx
    mov ebx, edx
    call viewing_member
    test rax, rax
    jz .done
    mov rdi, rax
    call member_perms
    and eax, ebx
    setnz al
    movzx eax, al
.done:
    pop rbx
    ret

; Sends what's built in msg_buf to everyone viewing a team with a permission.
; edi = team, esi = the only connection to send it to, or -1 for all,
; edx = PERM_*, ecx = length
perm_send:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov r12d, edi
    mov r13d, esi
    mov ebp, edx
    mov r14d, ecx
    xor ebx, ebx
.conn:
    cmp r13d, -1
    je .any
    cmp ebx, r13d
    jne .next
.any:
    mov edi, ebx
    mov esi, r12d
    mov edx, ebp
    call conn_has_perm
    test eax, eax
    jz .next
    mov edi, ebx
    lea rsi, [msg_buf]
    mov edx, r14d
    call send_msg
.next:
    inc ebx
    cmp ebx, MAX_CONN
    jb .conn
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Builds MSG_ROLES for a team in msg_buf. edi = team -> rdx = its length
build_roles:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    call everyone_perms
    mov ebx, eax
    lea rdi, [msg_buf]
    mov esi, MSG_ROLES
    call wr_u8
    mov esi, r12d
    call wr_u32
    mov esi, ebx
    call wr_u32
    mov r14, rdi                            ; the count goes here
    inc rdi
    xor r13d, r13d
    lea rbx, [roles]
    mov r15d, [n_roles]
.row:
    test r15d, r15d
    jz .built
    cmp [rbx + RL_TEAM], r12d
    jne .next
    movzx esi, byte [rbx + RL_SLOT]
    test esi, esi
    jz .next                                ; @everyone went out above
    call wr_u8
    movzx esi, byte [rbx + RL_POS]
    call wr_u8
    mov esi, [rbx + RL_COLOR]
    call wr_u32
    mov esi, [rbx + RL_PERMS]
    call wr_u32
    lea rsi, [rbx + RL_NAME]
    movzx edx, byte [rbx + RL_NAME_LEN]
    call wr_str
    inc r13d
.next:
    add rbx, RL_SIZE
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

; Everything that depends on who may do what, to everyone viewing a team:
; its roles, members, channels, and the lists their permissions get them.
; edi = team
permissions_changed:
    push rbx
    mov ebx, edi
    call build_roles
    mov edi, ebx
    lea rsi, [msg_buf]
    call broadcast_team
    mov edi, ebx
    call broadcast_members
    mov edi, ebx
    call send_channels_all
    mov edi, ebx
    mov esi, -1
    call send_moderation
    pop rbx
    ret

; edi = team -> eax = its lowest free role slot, or 0 if it has them all
free_role_slot:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, 1
.slot:
    mov edi, ebx
    mov esi, r12d
    call find_role
    test rax, rax
    jz .found
    inc r12d
    cmp r12d, ROLE_SLOTS
    jbe .slot
    xor r12d, r12d
.found:
    mov eax, r12d
    add rsp, 8
    pop r12
    pop rbx
    ret

; Moves every role of a team at or above a position by one. The rows are
; touched, not committed. edi = team, esi = position, edx = 1 or -1
shift_roles:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    lea rbx, [roles]
    mov r15d, [n_roles]
.row:
    test r15d, r15d
    jz .done
    cmp [rbx + RL_TEAM], r12d
    jne .next
    cmp byte [rbx + RL_SLOT], 0
    je .next
    movzx eax, byte [rbx + RL_POS]
    cmp eax, r13d
    jb .next
    add [rbx + RL_POS], r14b
    mov edi, T_ROLES
    mov rsi, rbx
    call db_touch
.next:
    add rbx, RL_SIZE
    dec r15d
    jmp .row
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Takes a deleted role's slot off every member and channel override that
; had it. The rows are touched, not committed. edi = team, esi = slot
forget_role:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    lea rbx, [members]
    mov r14d, [n_members]
.member:
    test r14d, r14d
    jz .overrides
    cmp [rbx + MEM_TEAM], r12d
    jne .next_member
    movzx eax, word [rbx + MEM_ROLES]
    btr eax, r13d
    jnc .next_member
    mov [rbx + MEM_ROLES], ax
    mov edi, T_MEMBERS
    mov rsi, rbx
    call db_touch
.next_member:
    add rbx, MEM_SIZE
    dec r14d
    jmp .member
.overrides:
    lea rbx, [chancfg]
    mov r14d, [n_chancfg]
.channel:
    test r14d, r14d
    jz .done
    cmp [rbx + CC_TEAM], r12d
    jne .next_channel
    cmp byte [rbx + CC_OVERRIDES + r13], 0
    je .next_channel
    mov byte [rbx + CC_OVERRIDES + r13], 0
    mov edi, T_CHANCFG
    mov rsi, rbx
    call db_touch
.next_channel:
    add rbx, CC_SIZE
    dec r14d
    jmp .channel
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Writes a role's fields. The row is touched, not committed.
; rdi = row, esi = color, edx = perms, rcx = name, r8d = its length
set_role:
    push rbx
    mov rbx, rdi
    mov [rbx + RL_COLOR], esi
    mov [rbx + RL_PERMS], edx
    mov [rbx + RL_NAME_LEN], r8b
    lea rdi, [rbx + RL_NAME]
    mov rsi, rcx
    mov ecx, r8d
    rep movsb
    mov edi, T_ROLES
    mov rsi, rbx
    call db_touch
    pop rbx
    ret

; Every new team gets a Moderator role. The row is touched, not committed.
; edi = team
add_default_roles:
    sub rsp, 8
    push rdi
    mov edi, T_ROLES
    call alloc_row
    pop rdi
    test rax, rax
    jz .done                                ; it simply starts without one
    mov [rax + RL_TEAM], edi
    mov byte [rax + RL_SLOT], 1
    mov byte [rax + RL_POS], 1
    mov rdi, rax
    mov esi, 0x3ba55c
    mov edx, PERM_MODERATOR
    lea rcx, [moderator_name]
    mov r8d, moderator_name_len
    call set_role
.done:
    add rsp, 8
    ret

; Makes a role at the bottom, above @everyone. The row is touched, not
; committed. edi = team -> rax = the row, or 0 if the team or table is full
new_role:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    call free_role_slot
    test eax, eax
    jz .full
    mov r12d, eax
    mov edi, T_ROLES
    call alloc_row
    test rax, rax
    jz .done
    mov [rax + RL_TEAM], ebx
    mov [rax + RL_SLOT], r12b
    mov r12, rax
    mov edi, ebx
    mov esi, 1
    mov edx, 1
    call shift_roles
    mov rax, r12
    mov byte [rax + RL_POS], 1
    jmp .done
.full:
    xor eax, eax
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; edi = team -> rax = @everyone's row, made with PERM_EVERYONE if it had
; none, or 0 if the table is full
everyone_row:
    push rbx
    mov ebx, edi
    xor esi, esi
    call find_role
    test rax, rax
    jnz .done
    mov edi, T_ROLES
    call alloc_row
    test rax, rax
    jz .done
    mov [rax + RL_TEAM], ebx
    mov dword [rax + RL_PERMS], PERM_EVERYONE
.done:
    pop rbx
    ret

; rsi = name, edx = length -> eax = 1 if it's empty or a valid role name
valid_role_name:
    mov eax, 1
    test edx, edx
    jz .done
    mov ecx, ROLE_NAME_MAX
    jmp valid_text
.done:
    ret

; rdi = member row -> eax = their permissions, edx = their rank
authority:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdi
    call member_perms
    mov ebx, eax
    mov rdi, r12
    call member_rank
    mov edx, eax
    mov eax, ebx
    add rsp, 8
    pop r12
    pop rbx
    ret

; Sets @everyone's permissions. The row is touched, not committed.
; edi = team, esi = perms -> eax = 0 if the table had no room
set_everyone:
    push rbx
    mov ebx, esi
    call everyone_row
    test rax, rax
    jz .done
    mov [rax + RL_PERMS], ebx
    mov edi, T_ROLES
    mov rsi, rax
    call db_touch
    mov eax, 1
.done:
    pop rbx
    ret

; Deletes a role for cur and logs it, and the positions above it close the
; gap. The rows are touched, not committed. rdi = row
delete_role:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, [rbx + RL_TEAM]
    mov edi, r12d
    mov esi, AU_DELETE_ROLE
    xor edx, edx
    xor ecx, ecx
    lea r8, [rbx + RL_NAME]
    movzx r9d, byte [rbx + RL_NAME_LEN]
    call audit_add
    movzx r13d, byte [rbx + RL_POS]
    movzx esi, byte [rbx + RL_SLOT]
    mov edi, r12d
    call forget_role
    mov edi, T_ROLES
    mov rsi, rbx
    call free_row
    mov edi, r12d
    lea esi, [r13d + 1]
    mov edx, -1
    call shift_roles
    pop r13
    pop r12
    pop rbx
    ret

; MSG_SAVE_ROLE: makes, changes or deletes a role, or sets @everyone's permissions.
h_save_role:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24                             ; name, its length, cur's permissions
    call rd_u32
    mov r12d, eax                           ; team
    call rd_u8
    mov r13d, eax                           ; slot
    call rd_u32
    mov r14d, eax                           ; color
    call rd_u32
    mov r15d, eax                           ; perms
    call rd_str
    mov [rsp], rax
    mov [rsp + 8], edx
    call rd_ok
    test eax, eax
    jz .violation
    test r15d, ~PERM_ALL
    jnz .violation
    cmp r13d, ROLE_SLOTS
    jbe .slot_ok
    cmp r13d, ROLE_NEW
    jne .violation
.slot_ok:
    mov rsi, [rsp]
    mov edx, [rsp + 8]
    call valid_role_name
    test eax, eax
    jz .bad_name
    mov edi, r12d
    mov esi, PERM_MANAGE_ROLES
    call require_perm
    test rax, rax
    jz .done
    mov rdi, rax
    call authority
    mov [rsp + 12], eax
    mov ebp, edx                            ; cur's rank
    test r13d, r13d
    jz .everyone
    cmp r13d, ROLE_NEW
    jne .existing
    cmp dword [rsp + 8], 0
    je .violation                           ; deleting nothing
    xor eax, eax                            ; it had no permissions to change
    jmp .perms
.existing:
    mov edi, r12d
    mov esi, r13d
    mov edx, ebp
    call editable_role
    test rax, rax
    jz .done
    mov rbx, rax
    cmp dword [rsp + 8], 0
    je .delete
    mov eax, [rbx + RL_PERMS]
    jmp .perms
.everyone:
    mov edi, r12d
    call everyone_perms
.perms:
    xor eax, r15d                           ; every changed bit has to be one of cur's
    not eax
    or eax, [rsp + 12]
    cmp eax, -1
    jne .perms_denied
    test r13d, r13d
    jnz .role
    mov edi, r12d
    mov esi, r15d
    call set_everyone
    test eax, eax
    jz .full
    xor r14d, r14d
    mov dword [rsp + 8], 0                  ; the audit log names @everyone itself
    jmp .record
.role:
    cmp r13d, ROLE_NEW
    jne .write
    mov edi, r12d
    call new_role
    test rax, rax
    jz .full
    mov rbx, rax
    movzx r13d, byte [rbx + RL_SLOT]
.write:
    mov rdi, rbx
    mov esi, r14d
    mov edx, r15d
    mov rcx, [rsp]
    mov r8d, [rsp + 8]
    call set_role
    mov r14d, r13d
.record:
    mov edi, r12d
    mov esi, AU_SAVE_ROLE
    xor edx, edx
    mov ecx, r14d
    mov r8, [rsp]
    mov r9d, [rsp + 8]
    call audit_add
    jmp .commit
.delete:
    mov rdi, rbx
    call delete_role
.commit:
    call db_commit
    mov edi, r12d
    call permissions_changed
    jmp .done
.violation:
    call kill_cur
    jmp .done
.bad_name:
    lea rsi, [e_role_name]
    mov edx, e_role_name_len
    jmp .error
.full:
    lea rsi, [e_roles_full]
    mov edx, e_roles_full_len
    jmp .error
.perms_denied:
    lea rsi, [e_role_perms]
    mov edx, e_role_perms_len
.error:
    call send_error
.done:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = team, esi = position -> rax = the team's role there, or 0
role_at:
    lea rax, [roles]
    mov ecx, [n_roles]
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + RL_TEAM], edi
    jne .next
    cmp byte [rax + RL_SLOT], 0
    je .next
    movzx edx, byte [rax + RL_POS]
    cmp edx, esi
    je .done
.next:
    add rax, RL_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; MSG_MOVE_ROLE: swaps a role with the one just above or below it. Both have
; to be below cur's rank.
h_move_role:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    call rd_u32
    mov r12d, eax                           ; team
    call rd_u8
    mov r13d, eax                           ; slot
    call rd_u8
    mov r14d, eax                           ; 1 for up
    call rd_ok
    test eax, eax
    jz .violation
    lea eax, [r13d - 1]
    cmp eax, ROLE_SLOTS - 1
    ja .violation
    cmp r14d, 1
    ja .violation
    mov edi, r12d
    mov esi, PERM_MANAGE_ROLES
    call require_perm
    test rax, rax
    jz .done
    mov rdi, rax
    call member_rank
    mov ebp, eax
    mov edi, r12d
    mov esi, r13d
    mov edx, ebp
    call editable_role
    test rax, rax
    jz .done
    mov rbx, rax
    movzx esi, byte [rbx + RL_POS]
    lea esi, [esi + r14d * 2 - 1]           ; up one or down one
    mov edi, r12d
    call role_at
    test rax, rax
    jz .done                                ; it's already at that end
    movzx ecx, byte [rbx + RL_POS]
    movzx edx, byte [rax + RL_POS]
    cmp edx, ebp
    jae .rank
    mov [rbx + RL_POS], dl
    mov [rax + RL_POS], cl
    mov edi, T_ROLES
    mov rsi, rax
    call db_touch
    mov edi, T_ROLES
    mov rsi, rbx
    call db_touch
    mov edi, r12d
    mov esi, AU_SAVE_ROLE
    xor edx, edx
    mov ecx, r13d
    lea r8, [rbx + RL_NAME]
    movzx r9d, byte [rbx + RL_NAME_LEN]
    call audit_add
    call db_commit
    mov edi, r12d
    call permissions_changed
    jmp .done
.violation:
    call kill_cur
    jmp .done
.rank:
    lea rsi, [e_role_rank]
    mov edx, e_role_rank_len
    call send_error
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = team, esi = slot, edx = cur's rank -> rax = the role's row if it's
; below that rank, or 0 once the error is sent
editable_role:
    sub rsp, 8
    mov [rsp], edx
    call find_role
    test rax, rax
    jz .no_role
    movzx ecx, byte [rax + RL_POS]
    cmp ecx, [rsp]
    jae .rank
    add rsp, 8
    ret
.no_role:
    lea rsi, [e_no_role]
    mov edx, e_no_role_len
    jmp .error
.rank:
    lea rsi, [e_role_rank]
    mov edx, e_role_rank_len
.error:
    call send_error
    xor eax, eax
    add rsp, 8
    ret

; Checks every role in a set of slots exists and ranks below cur.
; edi = team, esi = slots, edx = cur's rank -> eax = 1 if so, or 0 once the error is sent
roles_below:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov ebp, edx
    mov ebx, 1
.slot:
    mov eax, 1
    cmp ebx, ROLE_SLOTS
    ja .done
    bt r13d, ebx
    jnc .next
    mov edi, r12d
    mov esi, ebx
    mov edx, ebp
    call editable_role
    test rax, rax
    jz .done
.next:
    inc ebx
    jmp .slot
.done:
    add rsp, 8
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; MSG_MEMBER_ROLES: gives a member roles or takes them away. Every role that
; changes has to be below cur's rank, and so does the member, unless it's cur.
h_member_roles:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    call rd_u32
    mov r12d, eax                           ; team
    call rd_u32
    mov r13d, eax                           ; user
    call rd_u16
    mov r14d, eax                           ; roles
    call rd_ok
    test eax, eax
    jz .violation
    test r14d, 1                            ; @everyone isn't given
    jnz .violation
    mov edi, r12d
    mov esi, PERM_MANAGE_ROLES
    call require_perm
    test rax, rax
    jz .done
    mov rbp, rax
    mov edi, r12d
    mov esi, r13d
    call find_member
    test rax, rax
    jz .not_theirs
    mov rbx, rax
    cmp rbx, rbp
    je .ranked
    mov rdi, rbp
    mov rsi, rbx
    call outranks
    test eax, eax
    jz .outranked
.ranked:
    movzx esi, word [rbx + MEM_ROLES]
    xor esi, r14d
    jz .done                                ; nothing changes
    mov rdi, rbp
    call member_rank
    mov edx, eax
    movzx esi, word [rbx + MEM_ROLES]
    xor esi, r14d
    mov edi, r12d
    call roles_below
    test eax, eax
    jz .done
    mov [rbx + MEM_ROLES], r14w
    mov edi, T_MEMBERS
    mov rsi, rbx
    call db_touch
    mov edi, r12d
    mov esi, AU_MEMBER_ROLES
    mov edx, r13d
    mov ecx, r14d
    xor r8d, r8d
    xor r9d, r9d
    call audit_add
    call db_commit
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
.outranked:
    lea rsi, [e_outranked]
    mov edx, e_outranked_len
.error:
    call send_error
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
