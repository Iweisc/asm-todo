; Nicknames: what a team calls a member instead of their username. Members
; with PERM_CHANGE_NICKNAME set their own, PERM_MANAGE_NICKNAMES sets those
; of members below them.

section .rodata
text e_nickname,        "nicknames are 1-32 printable characters"
text e_nicks_full,      "the server has no room for more nicknames right now"

section .text

; edi = team, esi = user -> rax = their nickname's row, or 0
find_nick:
    lea rax, [nicks]
    mov ecx, [n_nicks]
    test edi, edi
    jz .none
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + NICK_TEAM], edi
    jne .next
    cmp [rax + NICK_USER], esi
    je .done
.next:
    add rax, NICK_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; rdi = cursor, esi = team, edx = user -> rdi advanced past their nickname as a str, empty for none
wr_nick:
    push rdi
    mov edi, esi
    mov esi, edx
    call find_nick
    pop rdi
    xor edx, edx
    test rax, rax
    jz .write
    lea rsi, [rax + NICK_TEXT]
    movzx edx, byte [rax + NICK_LEN]
.write:
    jmp wr_str

; A member leaving drops their nickname. The row is touched, not committed.
; edi = team, esi = user
forget_nick:
    sub rsp, 8
    call find_nick
    test rax, rax
    jz .done
    mov edi, T_NICKS
    mov rsi, rax
    call free_row
.done:
    add rsp, 8
    ret

; MSG_NICKNAME: sets or clears a member's nickname.
h_nickname:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call rd_u32
    mov r12d, eax                           ; team
    call rd_u32
    mov r13d, eax                           ; user
    call rd_str
    mov r14, rax
    mov r15d, edx                           ; nickname
    call rd_ok
    test eax, eax
    jz .violation
    test r15d, r15d
    jz .valid
    mov rsi, r14
    mov edx, r15d
    mov ecx, NICKNAME_MAX
    call valid_text
    test eax, eax
    jz .bad_nick
.valid:
    mov edi, r12d
    mov rax, [cur]
    cmp [rax + C_USER], r13d
    jne .other
    mov esi, PERM_CHANGE_NICKNAME
    call require_perm
    jmp .checked
.other:
    mov esi, r13d
    mov edx, PERM_MANAGE_NICKNAMES
    call moderated_member
.checked:
    test rax, rax
    jz .done
    mov edi, r12d
    mov esi, r13d
    call find_nick
    test r15d, r15d
    jnz .set
    test rax, rax
    jz .done                                ; nothing to clear
    mov edi, T_NICKS
    mov rsi, rax
    call free_row
    jmp .record
.set:
    test rax, rax
    jnz .have
    mov edi, T_NICKS
    call alloc_row
    test rax, rax
    jz .full
    mov [rax + NICK_TEAM], r12d
    mov [rax + NICK_USER], r13d
.have:
    mov rbx, rax
    lea rdi, [rbx + NICK_TEXT]              ; the old one goes, not just its length
    mov esi, NICKNAME_MAX
    call wipe
    mov [rbx + NICK_LEN], r15b
    lea rdi, [rbx + NICK_TEXT]
    mov rsi, r14
    mov ecx, r15d
    rep movsb
    mov edi, T_NICKS
    mov rsi, rbx
    call db_touch
.record:
    mov edi, r12d
    mov esi, AU_NICKNAME
    mov edx, r13d
    xor ecx, ecx
    mov r8, r14
    mov r9d, r15d
    call audit_add
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
.bad_nick:
    lea rsi, [e_nickname]
    mov edx, e_nickname_len
    jmp .error
.full:
    lea rsi, [e_nicks_full]
    mov edx, e_nicks_full_len
.error:
    call send_error
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
