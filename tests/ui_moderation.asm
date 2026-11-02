; ui-test's checks of moderation in team settings: who gets offered what, a
; member's page, the member search, the bans and the audit log.
; ui_test.asm includes this at its end.

section .rodata
n_mod_tabs:     db "owners and moderators get the bans and audit log tabs, members don't", 0
n_mod_page:     db "a member's page offers Owner, a switch per role, timeouts, Kick and Ban", 0
n_mod_ask:      db "Ban asks first, Kick after it asks again, and clicking elsewhere backs out", 0
n_mod_timed:    db "End timeout only shows while a member is timed out", 0
n_mod_rank:     db "a role with moderator permissions gets a member's page without the roles", 0
n_mod_closes:   db "a member's page closes once they're out of reach", 0
n_mod_search:   db "the member search ignores case and hides who doesn't match", 0
n_mod_enter:    db "Enter in the search box leaves it without adding a line", 0
n_mod_bans:     db "BANS fills the bans tab, with Unban for each", 0
n_mod_audit:    db "AUDIT fills the log, and one of a kind we don't know still draws", 0
n_mod_demoted:  db "losing ownership takes the bans and audit log away", 0
n_mod_ack:      db "a change refused for a timeout says so", 0
t_ma:           db "MA", 0
t_zz:           db "zz", 0
; MSG_ROLES past the type byte: @everyone's defaults and Mods in slot 1.
t_roles:        dd 1, PERM_EVERYONE
                db 1
                db 1, 1
                dd 0x3ba55c, PERM_MODERATOR
                db 4, "Mods"
t_roles_len     equ $ - t_roles
; MSG_BANS past the type byte: owen, banned for spam.
t_bans:         dd 1
                db 1
                dd 3, 0
                db 4, "owen", 4, "spam"
t_bans_len      equ $ - t_bans
; MSG_AUDIT past the type byte: lewis banned owen, then a kind from the future.
t_audit:        dd 1
                db 2
                db AU_BAN
                dd 1, 3, 0, 0
                db 5, "lewis", 4, "owen", 4, "spam"
                db 200
                dd 1, 3, 0, 0
                db 5, "lewis", 4, "owen", 0
t_audit_len     equ $ - t_audit
; MSG_ACK past the type byte: op 1, refused for a timeout.
t_ack_timed_out: dd 1
                db ACK_TIMED_OUT
t_ack_timed_out_len equ $ - t_ack_timed_out

section .text

; edi = action, esi = arg -> eax = 1 if the last frame drew a hit region for them
has_hit:
    sub rsp, 8
    call find_hit
    test rax, rax
    setnz al
    movzx eax, al
    add rsp, 8
    ret

; The tabs, a member's page and who gets it, with maya on the team.
moderation_tests:
    push rbx
    sub rsp, 16
    call add_maya
    lea rdi, [t_roles]
    mov esi, t_roles_len
    call rd_begin
    call on_roles
    mov edi, F_NONE
    call open_team_settings
    call frame
    mov edi, A_TAB
    mov esi, TAB_AUDIT
    call has_hit
    mov ebx, eax
    mov byte [teams + CO_ROLE], ROLE_MEMBER
    call frame
    mov edi, A_TAB
    mov esi, TAB_BANS
    call has_hit
    xor eax, 1
    and ebx, eax
    mov byte [teams + CO_ROLE], ROLE_OWNER
    mov esi, ebx
    lea rdi, [n_mod_tabs]
    call check

    call frame
    mov edi, A_TAB
    mov esi, TAB_MEMBERS
    call click_hit
    xor ebx, ebx
    mov edi, A_MANAGE
    mov esi, 2
    call click_hit
    cmp dword [managing], 2
    jne .page
    mov edi, A_SET_ROLE
    mov esi, ROLE_OWNER
    call has_hit
    test eax, eax
    jz .page
    mov edi, A_TOGGLE_ROLE
    mov esi, 1
    call has_hit
    test eax, eax
    jz .page
    mov edi, A_SET_ROLE
    mov esi, ROLE_MEMBER                    ; hers already, so not a link
    call has_hit
    test eax, eax
    jnz .page
    mov edi, A_TIMEOUT
    mov esi, 3600
    call has_hit
    test eax, eax
    jz .page
    mov dword [settings_scroll], 100000     ; Kick and Ban are at the bottom
    call frame
    mov edi, A_KICK
    xor esi, esi
    call has_hit
    test eax, eax
    jz .page
    mov edi, A_BAN
    xor esi, esi
    call has_hit
    mov ebx, eax
.page:
    mov esi, ebx
    lea rdi, [n_mod_page]
    call check

    xor ebx, ebx
    mov edi, A_BAN
    xor esi, esi
    call click_hit
    cmp dword [member_armed], 2
    jne .ask
    cmp dword [armed_action], A_BAN
    jne .ask
    mov edi, A_KICK
    xor esi, esi
    call click_hit
    cmp dword [member_armed], 2
    jne .ask
    cmp dword [armed_action], A_KICK
    jne .ask
    mov edi, A_FIELD
    mov esi, F_REASON
    call click_hit
    cmp dword [member_armed], 0
    sete bl
.ask:
    mov esi, ebx
    lea rdi, [n_mod_ask]
    call check

    mov edi, A_TIMEOUT
    xor esi, esi
    call has_hit
    mov ebx, eax
    xor ebx, 1
    call unix_now
    add eax, 600
    mov [members + CM_SIZE + CM_TIMEOUT], eax
    call frame
    mov edi, A_TIMEOUT
    xor esi, esi
    call has_hit
    and ebx, eax
    mov dword [members + CM_SIZE + CM_TIMEOUT], 0
    mov esi, ebx
    lea rdi, [n_mod_timed]
    call check

    call moderator_tests
    call search_tests
    call moderation_lists_tests
    call close_modal
    mov dword [member_count], 1
    add rsp, 16
    pop rbx
    ret

; lewis as a member with Mods: maya's page loses the roles, and closes once
; she's an owner.
moderator_tests:
    push rbx
    mov byte [teams + CO_ROLE], ROLE_MEMBER
    mov byte [members + CM_ROLE], ROLE_MEMBER
    mov word [members + CM_ROLES], 1 << 1
    call ui_members_changed
    call frame
    xor ebx, ebx
    cmp dword [managing], 2
    jne .rank
    mov edi, A_SET_ROLE
    mov esi, ROLE_OWNER
    call has_hit
    test eax, eax
    jnz .rank
    mov edi, A_TOGGLE_ROLE
    mov esi, 1
    call has_hit
    test eax, eax
    jnz .rank
    mov edi, A_BAN
    xor esi, esi
    call has_hit
    mov ebx, eax
.rank:
    mov esi, ebx
    lea rdi, [n_mod_rank]
    call check

    mov byte [members + CM_SIZE + CM_ROLE], ROLE_OWNER
    call ui_members_changed
    call frame
    xor ebx, ebx
    cmp dword [managing], 0
    jne .closes
    mov edi, A_MANAGE
    mov esi, 2
    call has_hit
    mov ebx, eax
    xor ebx, 1
.closes:
    mov esi, ebx
    lea rdi, [n_mod_closes]
    call check
    mov byte [members + CM_SIZE + CM_ROLE], ROLE_MEMBER
    mov byte [teams + CO_ROLE], ROLE_OWNER
    mov byte [members + CM_ROLE], ROLE_OWNER
    mov word [members + CM_ROLES], 0
    call frame
    pop rbx
    ret

; The member search, and Enter in it.
search_tests:
    push rbx
    mov edi, F_SEARCH
    lea rsi, [t_zz]
    call type_into
    call frame
    mov edi, A_MANAGE
    mov esi, 2
    call has_hit
    mov ebx, eax
    xor ebx, 1
    mov edi, F_SEARCH
    call field_clear
    mov edi, F_SEARCH
    lea rsi, [t_ma]
    call type_into
    call frame
    mov edi, A_MANAGE
    mov esi, 2
    call has_hit
    and ebx, eax
    mov esi, ebx
    lea rdi, [n_mod_search]
    call check

    mov edi, F_SEARCH
    call set_focus
    mov edi, KEY_ENTER
    call field_command
    xor ebx, ebx
    cmp dword [focus], F_NONE
    jne .enter
    mov edi, F_SEARCH
    call field_len
    cmp eax, 2
    sete bl
.enter:
    mov esi, ebx
    lea rdi, [n_mod_enter]
    call check
    mov edi, F_SEARCH
    call field_clear
    pop rbx
    ret

; BANS, AUDIT and an ACK refused for a timeout, as they arrive.
moderation_lists_tests:
    push rbx
    lea rdi, [t_bans]
    mov esi, t_bans_len
    call rd_begin
    call on_bans
    xor ebx, ebx
    call rd_ok
    test eax, eax
    jz .bans
    cmp dword [ban_count], 1
    jne .bans
    mov edi, A_TAB
    mov esi, TAB_BANS
    call click_hit
    mov edi, A_UNBAN
    mov esi, 3
    call has_hit
    mov ebx, eax
.bans:
    mov esi, ebx
    lea rdi, [n_mod_bans]
    call check

    lea rdi, [t_audit]
    mov esi, t_audit_len
    call rd_begin
    call on_audit
    xor ebx, ebx
    call rd_ok
    test eax, eax
    jz .audit
    cmp dword [audit_count], 2
    jne .audit
    mov edi, A_TAB
    mov esi, TAB_AUDIT
    call click_hit
    cmp dword [settings_tab], TAB_AUDIT
    sete bl
.audit:
    mov esi, ebx
    lea rdi, [n_mod_audit]
    call check

    mov byte [teams + CO_ROLE], ROLE_MEMBER
    call ui_members_changed
    call frame
    xor ebx, ebx
    cmp dword [settings_tab], TAB_MEMBERS
    sete bl
    mov byte [teams + CO_ROLE], ROLE_OWNER
    mov esi, ebx
    lea rdi, [n_mod_demoted]
    call check

    lea rdi, [t_ack_timed_out]
    mov esi, t_ack_timed_out_len
    call rd_begin
    call on_ack
    xor esi, esi
    cmp dword [status_len], st_timed_out_len
    sete sil
    lea rdi, [n_mod_ack]
    call check
    xor eax, eax
    mov [ban_count], eax
    mov [audit_count], eax
    mov [status_len], eax
    pop rbx
    ret
