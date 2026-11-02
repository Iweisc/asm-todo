; ui-test's checks of roles, nicknames, channel settings and AutoMod: the
; roles tab and its editor, what a member's rank lets them change, the
; channel dialog's slowmode and overrides, the composer in a channel we can't
; post in, and the AutoMod tab. ui_test.asm includes this after
; ui_moderation.asm, whose t_roles and has_hit it uses.

section .rodata
n_roles_tab:    db "the roles tab lists the roles and @everyone, each with Edit, and Create role", 0
n_roles_editor: db "Edit fills the editor, and its switches and swatches change what Save sends", 0
n_roles_delete: db "Delete role asks first", 0
n_roles_gone:   db "the editor goes back to the list when its role is deleted elsewhere", 0
n_roles_rank:   db "Manage roles only edits roles below ours, and only switches what we have", 0
n_roles_none:   db "members without Manage roles don't get the roles tab", 0
n_nick_search:  db "the member search finds a member by nickname", 0
n_nick_self:    db "a member can change their own nickname, and nothing else, from their page", 0
n_chan_slow:    db "the channel dialog picks a slowmode", 0
n_chan_grid:    db "an override steps from default to allow to deny and back", 0
n_chan_cant:    db "a channel we can't send in has no message box", 0
n_chan_scroll:  db "with many roles the overrides scroll, and the dialog still holds Save", 0
n_automod_tab:  db "AUTOMOD fills the AutoMod tab, which picks a timeout", 0
n_ack_slow:     db "a message refused for slowmode says so", 0
t_bee:          db "bee", 0
; MSG_ROLES past the type byte: no roles at all.
t_no_roles:     dd 1, PERM_EVERYONE
                db 0
t_no_roles_len  equ $ - t_no_roles
; MSG_ROLES past the type byte: Mods, and Leads above it, who manage roles and ban.
t_leads:        dd 1, PERM_EVERYONE
                db 2
                db 1, 1
                dd 0x3ba55c, PERM_MODERATOR
                db 4, "Mods"
                db 2, 2
                dd 0x3498db, PERM_MANAGE_ROLES | PERM_BAN
                db 5, "Leads"
t_leads_len     equ $ - t_leads
; MSG_AUTOMOD past the type byte: two words, and five minutes out for them.
t_automod:      dd 1, 300
                dw 9
                db "spam", 10, "scam"
t_automod_len   equ $ - t_automod
t_ack_slowmode: dd 1
                db ACK_SLOWMODE
t_ack_slowmode_len equ $ - t_ack_slowmode

section .text

; rdi = message past its type byte, esi = its length. Hands it to on_roles.
feed_roles:
    sub rsp, 8
    call rd_begin
    call on_roles
    add rsp, 8
    ret

; The roles tab and its editor, as the owner.
roles_tests:
    push rbx
    call add_maya
    lea rdi, [t_roles]
    mov esi, t_roles_len
    call feed_roles
    mov edi, F_NONE
    call open_team_settings
    call frame
    mov edi, A_TAB
    mov esi, TAB_ROLES
    call click_hit
    xor ebx, ebx
    mov edi, A_NEW_ROLE
    xor esi, esi
    call has_hit
    test eax, eax
    jz .tab
    mov edi, A_EDIT_ROLE
    xor esi, esi
    call has_hit
    test eax, eax
    jz .tab
    mov edi, A_EDIT_ROLE
    mov esi, 1
    call has_hit
    mov ebx, eax
.tab:
    mov esi, ebx
    lea rdi, [n_roles_tab]
    call check

    xor ebx, ebx
    mov edi, A_EDIT_ROLE
    mov esi, 1
    call click_hit
    cmp dword [role_editing], 1
    jne .editor
    mov edi, F_ROLE_NAME
    call field_len
    cmp eax, 4
    jne .editor
    mov edi, A_ROLE_PERM
    xor esi, esi                            ; owners can hand out Administrator
    call has_hit
    test eax, eax
    jz .editor
    mov edi, A_ROLE_COLOR
    mov esi, 0x9b59b6
    call click_hit
    cmp dword [role_color], 0x9b59b6
    jne .editor
    mov dword [settings_scroll], 200        ; down to Ban members
    call frame
    mov edi, A_ROLE_PERM
    mov esi, 6                              ; PERM_BAN's bit
    call click_hit
    test dword [role_perms], PERM_BAN
    setz bl
.editor:
    mov esi, ebx
    lea rdi, [n_roles_editor]
    call check

    mov dword [settings_scroll], 100000     ; Delete role is at the bottom
    call frame
    xor ebx, ebx
    mov edi, A_DELETE_ROLE
    xor esi, esi
    call click_hit
    test eax, eax
    jz .delete
    movzx ebx, byte [role_armed]
.delete:
    mov esi, ebx
    lea rdi, [n_roles_delete]
    call check

    lea rdi, [t_no_roles]
    mov esi, t_no_roles_len
    call feed_roles
    xor esi, esi
    cmp dword [role_editing], ROLE_LIST
    sete sil
    lea rdi, [n_roles_gone]
    call check

    call rank_tests
    call close_modal
    mov dword [member_count], 1
    pop rbx
    ret

; lewis as a member: with Leads he edits Mods but not Leads, without a role
; he gets no roles tab.
rank_tests:
    push rbx
    lea rdi, [t_leads]
    mov esi, t_leads_len
    call feed_roles
    mov byte [teams + CO_ROLE], ROLE_MEMBER
    mov byte [members + CM_ROLE], ROLE_MEMBER
    mov word [members + CM_ROLES], 1 << 2
    call ui_members_changed
    call frame
    xor ebx, ebx
    mov edi, A_EDIT_ROLE
    mov esi, 2
    call has_hit
    test eax, eax
    jnz .rank
    mov edi, A_EDIT_ROLE
    mov esi, 1
    call click_hit
    test eax, eax
    jz .rank
    mov edi, A_ROLE_PERM
    xor esi, esi
    call has_hit
    test eax, eax
    jnz .rank
    mov dword [settings_scroll], 200
    call frame
    mov edi, A_ROLE_PERM
    mov esi, 6
    call has_hit
    mov ebx, eax
.rank:
    mov esi, ebx
    lea rdi, [n_roles_rank]
    call check

    mov word [members + CM_ROLES], 0
    call ui_members_changed
    call frame
    xor ebx, ebx
    cmp dword [settings_tab], TAB_MEMBERS
    jne .none
    mov edi, A_TAB
    mov esi, TAB_ROLES
    call has_hit
    mov ebx, eax
    xor ebx, 1
.none:
    mov esi, ebx
    lea rdi, [n_roles_none]
    call check

    call nickname_tests
    mov byte [teams + CO_ROLE], ROLE_OWNER
    mov byte [members + CM_ROLE], ROLE_OWNER
    lea rdi, [t_roles]
    mov esi, t_roles_len
    call feed_roles
    pop rbx
    ret

; The member search by nickname as the owner, then lewis, a plain member, on
; his own page.
nickname_tests:
    push rbx
    mov byte [teams + CO_ROLE], ROLE_OWNER
    mov byte [members + CM_SIZE + CM_NICK_LEN], 3
    mov dword [members + CM_SIZE + CM_NICK], 'Bee'
    mov edi, F_SEARCH
    lea rsi, [t_bee]
    call type_into
    call frame
    mov edi, A_MANAGE
    mov esi, 2
    call has_hit
    mov ebx, eax
    mov edi, F_SEARCH
    call field_clear
    mov byte [members + CM_SIZE + CM_NICK_LEN], 0
    mov byte [teams + CO_ROLE], ROLE_MEMBER
    mov esi, ebx
    lea rdi, [n_nick_search]
    call check

    call frame
    xor ebx, ebx
    mov edi, A_MANAGE
    mov esi, 1
    call click_hit
    cmp dword [managing], 1
    jne .self
    mov edi, A_SAVE_NICK
    xor esi, esi
    call has_hit
    test eax, eax
    jz .self
    mov edi, A_TOGGLE_ROLE
    mov esi, 1
    call has_hit
    test eax, eax
    jnz .self
    mov edi, A_TIMEOUT
    mov esi, 3600
    call has_hit
    xor eax, 1
    mov ebx, eax
.self:
    mov esi, ebx
    lea rdi, [n_nick_self]
    call check
    mov dword [managing], 0
    pop rbx
    ret

; #general's dialog, then the composer in it once we can't send there.
channel_settings_tests:
    push rbx
    xor edi, edi
    call open_channel_dialog
    call frame
    xor ebx, ebx
    mov edi, A_SLOWMODE
    mov esi, 30
    call click_hit
    test eax, eax
    jz .slow
    cmp dword [chan_slowmode], 30
    sete bl
.slow:
    mov esi, ebx
    lea rdi, [n_chan_slow]
    call check

    xor ebx, ebx
    mov edi, A_OVERRIDE
    mov esi, 1 * 4 + 1                      ; Mods' Send
    call click_hit
    test eax, eax
    jz .grid
    cmp byte [chan_overrides + 1], CH_SEND
    jne .grid
    mov edi, A_OVERRIDE
    mov esi, 1 * 4 + 1
    call click_hit
    cmp byte [chan_overrides + 1], CH_SEND << 4
    jne .grid
    mov edi, A_OVERRIDE
    mov esi, 1 * 4 + 1
    call click_hit
    cmp byte [chan_overrides + 1], 0
    sete bl
.grid:
    mov esi, ebx
    lea rdi, [n_chan_grid]
    call check
    call close_modal
    call many_roles_test

    mov byte [chans + CN_ACCESS], CH_VIEW
    xor edi, edi
    call open_chat
    call frame
    mov edi, A_FIELD
    mov esi, F_MESSAGE
    call has_hit
    mov ebx, eax
    xor ebx, 1
    mov byte [chans + CN_ACCESS], CH_VIEW | CH_SEND | CH_MANAGE | CH_EDIT
    call frame
    mov edi, A_FIELD
    mov esi, F_MESSAGE
    call has_hit
    and ebx, eax
    call close_detail
    mov esi, ebx
    lea rdi, [n_chan_cant]
    call check
    pop rbx
    ret

; 14 roles in #general's dialog: the lowest one's row is past the bottom
; until the grid scrolls, and Save shows either way.
many_roles_test:
    push rbx
    lea rdi, [role_rows]
    mov ecx, 14
.role:
    mov [rdi + RO_SLOT], cl
    mov [rdi + RO_POS], cl
    mov byte [rdi + RO_NAME_LEN], 1
    mov byte [rdi + RO_NAME], 'r'
    add rdi, RO_SIZE
    loop .role
    mov dword [role_count], 14
    xor edi, edi
    call open_channel_dialog
    call frame
    xor ebx, ebx
    mov edi, A_SAVE_CHANNEL
    xor esi, esi
    call find_hit
    test rax, rax
    jz .done
    ; Left of Save is still the dialog's own fill, not the shade around it.
    mov ecx, [rax + HIT_Y]
    imul ecx, ecx, TEST_W
    add ecx, [rax + HIT_X]
    sub ecx, 14
    mov eax, [test_fb + rcx * 4]
    and eax, 0xffffff
    cmp eax, C_RAISED
    jne .done
    mov edi, A_OVERRIDE
    mov esi, 1 * 4                          ; the lowest role's View
    call has_hit
    test eax, eax
    jnz .done
    mov dword [chan_scroll], 100000
    call frame
    mov edi, A_OVERRIDE
    mov esi, 1 * 4
    call has_hit
    test eax, eax
    jz .done
    mov edi, A_SAVE_CHANNEL
    xor esi, esi
    call has_hit
    mov ebx, eax
.done:
    call close_modal
    lea rdi, [t_roles]                      ; Mods back in the first row
    mov esi, t_roles_len
    call feed_roles
    mov esi, ebx
    lea rdi, [n_chan_scroll]
    call check
    pop rbx
    ret

; AUTOMOD as it arrives, the AutoMod tab, and an ACK refused for slowmode.
automod_tests:
    push rbx
    lea rdi, [t_automod]
    mov esi, t_automod_len
    call rd_begin
    call on_automod
    xor ebx, ebx
    call rd_ok
    test eax, eax
    jz .tab
    mov edi, F_AUTOMOD
    call field_len
    cmp eax, 9
    jne .tab
    mov edi, F_NONE
    call open_team_settings
    call frame
    mov edi, A_TAB
    mov esi, TAB_AUTOMOD
    call click_hit
    mov edi, A_AUTOMOD_TIMEOUT
    mov esi, 300                            ; already picked, so not a link
    call has_hit
    test eax, eax
    jnz .tab
    mov edi, A_AUTOMOD_TIMEOUT
    mov esi, 3600
    call click_hit
    cmp dword [automod_choice], 3600
    jne .tab
    mov edi, A_SAVE_AUTOMOD
    xor esi, esi
    call has_hit
    mov ebx, eax
.tab:
    call close_modal
    mov esi, ebx
    lea rdi, [n_automod_tab]
    call check

    lea rdi, [t_ack_slowmode]
    mov esi, t_ack_slowmode_len
    call rd_begin
    call on_ack
    xor esi, esi
    cmp dword [status_len], st_slowmode_len
    sete sil
    lea rdi, [n_ack_slow]
    call check
    mov dword [status_len], 0
    mov edi, F_AUTOMOD
    call field_clear
    pop rbx
    ret
