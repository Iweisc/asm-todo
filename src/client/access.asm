; Roles and permissions as the server sends them, and the same sums it
; makes, so we only offer what it will take. roles.asm on the server has the
; rules. This also keeps the team's AutoMod rules for its tab.

; A role, as MSG_ROLES lists it.
%define RO_SLOT         0
%define RO_POS          1
%define RO_NAME_LEN     2
%define RO_NAME         3               ; ROLE_NAME_MAX bytes
%define RO_COLOR        28
%define RO_PERMS        32
%define RO_SIZE         36
fits RO_NAME, ROLE_NAME_MAX, RO_COLOR
fits RO_PERMS, 4, RO_SIZE

%define ROLE_LIST       -1              ; role_editing while the roles tab shows its list

section .bss
alignb 4
role_count:     resd 1
everyone_perms: resd 1
role_rows:      resb ROLE_SLOTS * RO_SIZE
automod_timeout: resd 1                 ; the server's
automod_choice: resd 1                  ; what the AutoMod tab has picked
automod_buf:    resb AUTOMOD_MAX        ; F_AUTOMOD's

section .text

; MSG_ROLES: the current team's roles and @everyone's permissions.
on_roles:
    push rbx
    push r12
    push r13
    call rd_u32
    mov ebx, eax
    call rd_u32
    mov r12d, eax
    call rd_u8
    mov r13d, eax
    cmp ebx, [current_team]
    jne .skip
    cmp r13d, ROLE_SLOTS
    ja .bad
    mov [everyone_perms], r12d
    lea rbx, [role_rows]
    xor r12d, r12d
.row:
    cmp r12d, r13d
    jae .read
    call rd_u8
    mov [rbx + RO_SLOT], al
    dec eax
    cmp eax, ROLE_SLOTS - 1
    ja .bad
    call rd_u8
    mov [rbx + RO_POS], al
    call rd_u32
    mov [rbx + RO_COLOR], eax
    call rd_u32
    mov [rbx + RO_PERMS], eax
    lea rdi, [rbx + RO_NAME_LEN]
    mov esi, ROLE_NAME_MAX
    call read_named_str
    add rbx, RO_SIZE
    inc r12d
    jmp .row
.bad:
    mov byte [rd_bad], 1
    xor r13d, r13d                          ; none until the reconnect sends them again
.read:
    mov [role_count], r13d
    call ui_members_changed                 ; what we may do changed
    call roles_changed
    jmp .done
.skip:
    call rd_skip
.done:
    pop r13
    pop r12
    pop rbx
    ret

; MSG_AUTOMOD: the current team's blocked words. The tab shows them, unless
; they're being edited there.
on_automod:
    push rbx
    push r12
    push r13
    call rd_u32
    mov ebx, eax
    call rd_u32
    mov r12d, eax
    call rd_str16
    mov r13d, edx
    cmp ebx, [current_team]
    jne .done
    cmp r13d, AUTOMOD_MAX
    ja .bad
    mov [automod_timeout], r12d
    mov [automod_choice], r12d
    cmp dword [focus], F_AUTOMOD
    je .done
    mov edi, F_AUTOMOD
    mov rsi, rax
    mov edx, r13d
    call field_set
    jmp .done
.bad:
    mov byte [rd_bad], 1
.done:
    pop r13
    pop r12
    pop rbx
    ret

; edi = slot -> rax = the role's row, or 0
find_role_row:
    lea rax, [role_rows]
    mov ecx, [role_count]
.loop:
    test ecx, ecx
    jz .none
    movzx edx, byte [rax + RO_SLOT]
    cmp edx, edi
    je .done
    add rax, RO_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; edi = position -> rax = the role there, or 0
role_at_pos:
    lea rax, [role_rows]
    mov ecx, [role_count]
.loop:
    test ecx, ecx
    jz .none
    movzx edx, byte [rax + RO_POS]
    cmp edx, edi
    je .done
    add rax, RO_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; edi = role slots -> eax = the permissions @everyone and those roles give
roles_perms:
    mov eax, [everyone_perms]
    lea rcx, [role_rows]
    mov r8d, [role_count]
.row:
    test r8d, r8d
    jz .admin
    movzx edx, byte [rcx + RO_SLOT]
    bt edi, edx
    jnc .next
    or eax, [rcx + RO_PERMS]
.next:
    add rcx, RO_SIZE
    dec r8d
    jmp .row
.admin:
    test eax, PERM_ADMIN
    jz .done
    mov eax, PERM_ALL
.done:
    ret

; rdi = member row -> eax = their permissions
member_perms:
    mov eax, PERM_ALL
    cmp byte [rdi + CM_ROLE], ROLE_OWNER
    je .done
    movzx edi, word [rdi + CM_ROLES]
    jmp roles_perms
.done:
    ret

; -> eax = our permissions in the current team. Owners have them all, as
; the team list says, before the member list has come.
my_perms:
    sub rsp, 8
    call my_role
    cmp eax, ROLE_OWNER
    je .all
    mov edi, [my_id]
    call find_member_row
    xor edi, edi
    test rax, rax
    jz .roles
    movzx edi, word [rax + CM_ROLES]
.roles:
    call roles_perms
    jmp .done
.all:
    mov eax, PERM_ALL
.done:
    add rsp, 8
    ret

; edi = PERM_* -> eax = 1 if we have it in the current team
has_perm:
    push rbx
    mov ebx, edi
    call my_perms
    and eax, ebx
    setnz al
    movzx eax, al
    pop rbx
    ret

; rdi = member row -> eax = their rank: their highest role's position, or
; above every position for an owner
member_rank:
    mov eax, ROLE_SLOTS + 1
    cmp byte [rdi + CM_ROLE], ROLE_OWNER
    je .done
    movzx r9d, word [rdi + CM_ROLES]
    xor eax, eax
    lea rcx, [role_rows]
    mov r8d, [role_count]
.row:
    test r8d, r8d
    jz .done
    movzx edx, byte [rcx + RO_SLOT]
    bt r9d, edx
    jnc .next
    movzx edx, byte [rcx + RO_POS]
    cmp edx, eax
    cmova eax, edx
.next:
    add rcx, RO_SIZE
    dec r8d
    jmp .row
.done:
    ret

; -> eax = our rank in the current team
my_rank:
    sub rsp, 8
    call my_role
    cmp eax, ROLE_OWNER
    je .owner
    mov edi, [my_id]
    call find_member_row
    test rax, rax
    jz .done
    mov rdi, rax
    call member_rank
    jmp .done
.owner:
    mov eax, ROLE_SLOTS + 1
.done:
    add rsp, 8
    ret

; rdi = member row -> eax = 1 if they're someone else and rank below us.
; Owners rank above everyone, other owners too.
below_us:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdi
    xor eax, eax
    mov ecx, [r12 + CM_ID]
    cmp ecx, [my_id]
    je .done
    call my_rank
    mov ebx, eax
    mov eax, 1
    cmp ebx, ROLE_SLOTS + 1
    je .done
    mov rdi, r12
    call member_rank
    cmp ebx, eax
    seta al
    movzx eax, al
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; rdi = member row, esi = PERM_* -> eax = 1 if we have it and they rank below us
may_act_on:
    push rbx
    mov rbx, rdi
    mov edi, esi
    call has_perm
    test eax, eax
    jz .done
    mov rdi, rbx
    call below_us
.done:
    pop rbx
    ret

; rdi = member row -> eax = 1 if their page has something we can change:
; nicknames, roles, timeouts, Kick or Ban for them, or our own nickname
can_manage:
    push rbx
    sub rsp, 16
    mov rbx, rdi
    mov eax, [rbx + CM_ID]
    cmp eax, [my_id]
    jne .others
    mov edi, PERM_CHANGE_NICKNAME | PERM_MANAGE_ROLES
    call has_perm
    jmp .done
.others:
    mov esi, PERM_MANAGE_NICKNAMES | PERM_MANAGE_ROLES | PERM_KICK | PERM_BAN | PERM_TIMEOUT
    call may_act_on
.done:
    add rsp, 16
    pop rbx
    ret

; rdi = member row -> rax = their highest role's row, or 0 for none
top_role:
    sub rsp, 8
    call member_rank
    add rsp, 8
    cmp eax, ROLE_SLOTS
    ja .none                                ; an owner
    test eax, eax
    jz .none
    mov edi, eax
    jmp role_at_pos
.none:
    xor eax, eax
    ret

; rdi = member row -> rsi = what the team calls them, edx = its length:
; their nickname, or their username
display_name:
    lea rsi, [rdi + CM_NICK]
    movzx edx, byte [rdi + CM_NICK_LEN]
    test edx, edx
    jnz .done
    lea rsi, [rdi + CM_NAME]
    movzx edx, byte [rdi + CM_NAME_LEN]
.done:
    ret

; edi = slot, esi = color, edx = perms, rcx = name, r8d = its length, empty
; to delete -> eax = 1 if it went out
sync_save_role:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov ebx, edi
    mov ebp, esi
    mov r12d, edx
    mov r13, rcx
    mov r14d, r8d
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_SAVE_ROLE
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    mov esi, ebx
    call wr_u8
    mov esi, ebp
    call wr_u32
    mov esi, r12d
    call wr_u32
    mov rsi, r13
    mov edx, r14d
    call wr_str
    call send_built
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Sends a message that's its type, the current team and two numbers.
; edi = type, esi = the first, edx = 1 if it's a u32 or 0 for a u8,
; ecx = the second, r8d = 2 if it's a u16 or 0 for a u8 -> eax = 1 if it went out
sync_pair:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov ebx, edi
    mov ebp, esi
    mov r12d, edx
    mov r13d, ecx
    mov r14d, r8d
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, ebx
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    mov esi, ebp
    test r12d, r12d
    jz .small
    call wr_u32
    jmp .second
.small:
    call wr_u8
.second:
    mov esi, r13d
    cmp r14d, 2
    jne .byte
    call wr_u16
    jmp .send
.byte:
    call wr_u8
.send:
    call send_built
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = user id, esi = their role slots -> eax = 1 if it went out
sync_member_roles:
    mov ecx, esi
    mov esi, edi
    mov edi, MSG_MEMBER_ROLES
    mov edx, 1
    mov r8d, 2
    jmp sync_pair

; edi = slot, esi = 1 to move it up or 0 down -> eax = 1 if it went out
sync_move_role:
    mov ecx, esi
    mov esi, edi
    mov edi, MSG_MOVE_ROLE
    xor edx, edx
    xor r8d, r8d
    jmp sync_pair

; edi = user id, rsi = nickname, edx = its length, empty to clear it -> eax = 1 if it went out
sync_nickname:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12, rsi
    mov r13d, edx
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_NICKNAME
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    mov esi, ebx
    call wr_u32
    mov rsi, r12
    mov edx, r13d
    call wr_str
    call send_built
.done:
    pop r13
    pop r12
    pop rbx
    ret

; edi = timeout seconds, rsi = words, edx = their length -> eax = 1 if it went out
sync_set_automod:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12, rsi
    mov r13d, edx
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_SET_AUTOMOD
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    mov esi, ebx
    call wr_u32
    mov rsi, r12
    mov edx, r13d
    call wr_str16
    call send_built
.done:
    pop r13
    pop r12
    pop rbx
    ret
