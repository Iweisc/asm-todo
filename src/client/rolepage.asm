; Team settings' Roles and AutoMod tabs. The roles tab lists the team's
; roles, highest first, then @everyone, and opens one in an editor for its
; name, color and permissions, which can also move or delete it. Only roles
; below ours open, and only the permissions we have switch. The AutoMod tab
; edits the blocked words and the timeout for using one.

%define ROLE_ROW_H      44
%define PERM_ROW_H      30
%define SWATCH_D        22

section .rodata
text s_create_role,     "Create role"
text s_everyone_hint,   "Every member has it"
text s_members_count,   " members"
text s_one_member,      " member"
text s_back_to_roles,   "Back to roles"
text s_role_name_label, "Name"
text s_role_name_hint,  "e.g. Moderator"
text s_color_label,     "Color"
text s_perms_label,     "Permissions"
text s_save_role,       "Save role"
text s_move_up,         "Move up"
text s_move_down,       "Move down"
text s_delete_role,     "Delete role"
text s_delete_role_sure, "Delete it?"
text s_words_label,     "Blocked words"
text s_automod_timeout, "Timeout"
text s_no_timeout,      "Only block"
text s_save_automod,    "Save rules"
text p_admin,           "Administrator, every permission"
text p_manage_team,     "Rename the team"
text p_manage_roles,    "Manage roles"
text p_manage_channels, "Manage channels"
text p_invite,          "Invite members"
text p_kick,            "Kick members"
text p_ban,             "Ban members"
text p_timeout,         "Time out members"
text p_manage_messages, "Delete others' messages"
text p_view_audit,      "View the audit log"
text p_manage_nicknames, "Change others' nicknames"
text p_change_nickname, "Change their own nickname"
text p_manage_automod,  "Manage AutoMod"
text p_view_channels,   "View channels"
text p_send_messages,   "Send messages"

align 4
swatches:       dd 0x3ba55c, 0x1abc9c, 0x3498db, 0x9b59b6, 0xe91e63, 0xf1c40f, 0xe67e22, 0xe74c3c, 0x99aab5
SWATCHES        equ ($ - swatches) / 4
align 8
perm_names:     NAME p_admin            ; by PERM_* bit number
                NAME p_manage_team
                NAME p_manage_roles
                NAME p_manage_channels
                NAME p_invite
                NAME p_kick
                NAME p_ban
                NAME p_timeout
                NAME p_manage_messages
                NAME p_view_audit
                NAME p_manage_nicknames
                NAME p_change_nickname
                NAME p_manage_automod
                NAME p_view_channels
                NAME p_send_messages
%if ($ - perm_names) / 16 != PERM_COUNT
%error "every permission needs its name"
%endif

section .bss
alignb 4
role_editing:   resd 1                  ; the slot open in the editor, ROLE_NEW, or ROLE_LIST
role_color:     resd 1                  ; the editor's, until Save
role_perms:     resd 1
role_armed:     resb 1                  ; Delete role was clicked once
role_name_buf:  resb ROLE_NAME_MAX

section .text

; The roles changed. An editor for a role that's gone goes back to the list.
roles_changed:
    sub rsp, 8
    mov edi, [role_editing]
    lea eax, [edi - 1]
    cmp eax, ROLE_SLOTS - 1
    ja .done                                ; the list, @everyone or a new one
    call find_role_row
    test rax, rax
    jnz .done
    mov dword [role_editing], ROLE_LIST
.done:
    add rsp, 8
    ret

; Opens a role in the editor, or goes back to the list.
; edi = slot, 0 for @everyone, ROLE_NEW for a new one, or ROLE_LIST
click_edit_role:
    push rbx
    mov ebx, edi
    mov [role_editing], ebx
    xor eax, eax
    mov [settings_scroll], eax
    mov [role_armed], al
    mov eax, [swatches]
    mov [role_color], eax
    mov dword [role_perms], 0
    mov edi, F_ROLE_NAME
    call field_clear
    mov edi, F_NONE
    call set_focus
    test ebx, ebx
    jz .everyone
    cmp ebx, ROLE_NEW
    je .new
    mov edi, ebx
    call find_role_row
    test rax, rax
    jz .done
    mov ecx, [rax + RO_COLOR]
    mov [role_color], ecx
    mov ecx, [rax + RO_PERMS]
    mov [role_perms], ecx
    lea rsi, [rax + RO_NAME]
    movzx edx, byte [rax + RO_NAME_LEN]
    mov edi, F_ROLE_NAME
    call field_set
    jmp .done
.everyone:
    mov eax, [everyone_perms]
    mov [role_perms], eax
    jmp .done
.new:
    mov edi, F_ROLE_NAME
    call set_focus
.done:
    pop rbx
    ret

; Opens the editor on a role that doesn't exist yet.
click_new_role:
    mov edi, ROLE_NEW
    jmp click_edit_role

; edi = color, for the role being edited
click_role_color:
    mov [role_color], edi
    ret

; Switches a permission of the role being edited. edi = its bit number
click_role_perm:
    btc [role_perms], edi
    ret

; edi = 1 to move the role being edited up, 0 down
click_move_role:
    mov esi, edi
    mov edi, [role_editing]
    jmp sync_move_role

; Saves the role being edited, and goes back to the list once it's sent.
save_role:
    push rbx
    mov ebx, [role_editing]
    xor edx, edx
    test ebx, ebx
    jz .send                                ; @everyone's name isn't sent
    mov edi, F_ROLE_NAME
    call field_trimmed
    test edx, edx
    jz .done                                ; an empty name would delete it
.send:
    mov rcx, rsi
    mov r8d, edx
    mov edi, ebx
    mov esi, [role_color]
    mov edx, [role_perms]
    call sync_save_role
    test eax, eax
    jz .done
    mov dword [role_editing], ROLE_LIST
.done:
    pop rbx
    ret

; The first click asks, the second deletes the role being edited.
click_delete_role:
    sub rsp, 8
    cmp byte [role_armed], 0
    jne .sure
    mov byte [role_armed], 1
    jmp .done
.sure:
    mov edi, [role_editing]
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call sync_save_role
    test eax, eax
    jz .done
    mov dword [role_editing], ROLE_LIST
.done:
    add rsp, 8
    ret

; edi = seconds a blocked word times its author out for, 0 for none
click_automod_timeout:
    mov [automod_choice], edi
    ret

; Sends the blocked words and timeout the AutoMod tab has.
save_automod:
    sub rsp, 8
    mov edi, F_AUTOMOD
    call field_trimmed
    mov edi, [automod_choice]
    call sync_set_automod
    test eax, eax
    jz .done
    mov edi, F_NONE
    call set_focus
.done:
    add rsp, 8
    ret

; edi = slot -> eax = how many members have it
role_holders:
    lea rcx, [members]
    mov r8d, [member_count]
    xor eax, eax
.member:
    test r8d, r8d
    jz .done
    movzx edx, word [rcx + CM_ROLES]
    bt edx, edi
    adc eax, 0
    add rcx, CM_SIZE
    dec r8d
    jmp .member
.done:
    ret

; -> eax = the roles tab's height: the list's or the editor's
roles_tab_height:
    mov eax, [role_count]
    add eax, 2                              ; @everyone and Create role
    imul eax, eax, ROLE_ROW_H
    mov edx, [role_editing]
    cmp edx, ROLE_LIST
    je .done
    mov eax, 54 + PERM_COUNT * PERM_ROW_H + 42  ; Back, the switches and the buttons
    test edx, edx
    jz .done                                ; @everyone has no name or color
    add eax, FIELD_ROW_H + 40
.done:
    ret

; One row of the list: a dot in its color, its name, how many have it, and
; Edit when it's below us. edi = x, esi = top, rdx = role row, 0 for @everyone,
; ecx = our rank
draw_role_row:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 16
    mov ebx, edi
    mov ebp, esi
    mov r12, rdx
    mov r13d, ecx
    lea r14d, [ebx + 28]
    test r12, r12
    jz .name
    lea edi, [ebx + 34]
    lea esi, [ebp + 22]
    mov edx, 6
    mov ecx, [r12 + RO_COLOR]
    call fill_disc
    lea r14d, [ebx + 48]
.name:
    lea rdx, [s_everyone]
    mov ecx, s_everyone_len
    test r12, r12
    jz .named
    lea rdx, [r12 + RO_NAME]
    movzx ecx, byte [r12 + RO_NAME_LEN]
.named:
    mov edi, r14d
    lea esi, [ebp + 27]
    mov r8d, INK(C_TEXT, ST_BODY)
    call draw_text
    lea rdi, [scratch]
    lea rsi, [s_everyone_hint]
    mov edx, s_everyone_hint_len
    test r12, r12
    jz .count
    movzx edi, byte [r12 + RO_SLOT]
    call role_holders
    mov [rsp], eax
    lea rdi, [scratch]
    mov esi, eax
    call put_u32
    lea rsi, [s_members_count]
    mov edx, s_members_count_len
    lea rax, [s_one_member]
    mov ecx, s_one_member_len
    cmp dword [rsp], 1
    cmove rsi, rax
    cmove edx, ecx
.count:
    call put_mem
    mov rcx, rdi
    lea rdx, [scratch]
    lea edi, [ebx + 240]
    lea esi, [ebp + 27]
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_scratch
    xor r9d, r9d                            ; the slot Edit opens
    test r12, r12
    jz .edit
    movzx eax, byte [r12 + RO_POS]
    cmp eax, r13d
    jae .done
    movzx r9d, byte [r12 + RO_SLOT]
.edit:
    mov [rsp], r9d
    lea edi, [ebx + SETTINGS_W - 28]
    lea esi, [ebp + 27]
    lea rdx, [s_edit]
    mov ecx, s_edit_len
    mov r8d, C_DIM
    call draw_link
    mov edi, eax
    lea esi, [ebp + 27]
    mov r8d, A_EDIT_ROLE
    mov r9d, [rsp]
    call add_link_hit
.done:
    add rsp, 16
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The list: Create role, the roles highest first, then @everyone.
; edi = x, esi = top
draw_role_list:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 8
    mov ebx, edi
    mov ebp, esi
    cmp dword [role_count], ROLE_SLOTS
    jae .full
    lea edi, [ebx + 28]
    lea esi, [ebp + 4]
    lea rdx, [s_create_role]
    mov ecx, s_create_role_len
    mov r8d, A_NEW_ROLE
    xor r9d, r9d
    call draw_button
.full:
    add ebp, ROLE_ROW_H
    call my_rank
    mov r13d, eax
    mov r12d, [role_count]
.role:
    test r12d, r12d
    jz .everyone
    mov edi, r12d
    call role_at_pos
    test rax, rax
    jz .next
    mov edi, ebx
    mov esi, ebp
    mov rdx, rax
    mov ecx, r13d
    call draw_role_row
    add ebp, ROLE_ROW_H
.next:
    dec r12d
    jmp .role
.everyone:
    mov edi, ebx
    mov esi, ebp
    xor edx, edx
    mov ecx, r13d
    call draw_role_row
    add rsp, 8
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The color swatches, the picked one ringed. edi = x, esi = baseline
draw_swatches:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 8
    mov ebx, edi
    mov ebp, esi
    lea edi, [ebx + 28]
    lea rdx, [s_color_label]
    mov ecx, s_color_label_len
    call draw_page_label
    lea r12d, [ebx + OPTION_X]
    xor r13d, r13d
.swatch:
    mov eax, [swatches + r13 * 4]
    cmp eax, [role_color]
    jne .disc
    lea edi, [r12d + SWATCH_D / 2]
    lea esi, [ebp - 5]
    mov edx, SWATCH_D / 2 + 3
    mov ecx, C_TEXT
    call fill_disc
    lea edi, [r12d + SWATCH_D / 2]
    lea esi, [ebp - 5]
    mov edx, SWATCH_D / 2 + 1
    mov ecx, C_PANEL
    call fill_disc
.disc:
    lea edi, [r12d + SWATCH_D / 2]
    lea esi, [ebp - 5]
    mov edx, SWATCH_D / 2 - 1
    mov ecx, [swatches + r13 * 4]
    call fill_disc
    mov edi, r12d
    lea esi, [ebp - 5 - SWATCH_D / 2]
    mov edx, SWATCH_D
    mov ecx, SWATCH_D
    mov r8d, A_ROLE_COLOR
    mov r9d, [swatches + r13 * 4]
    call add_hit
    add r12d, SWATCH_D + 12
    inc r13d
    cmp r13d, SWATCHES
    jb .swatch
    add rsp, 8
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Every permission with its switch. Only ones we have switch.
; edi = x, esi = the first baseline -> eax = the baseline under them
draw_perm_switches:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 8
    mov ebx, edi
    mov ebp, esi
    lea edi, [ebx + 28]
    lea rdx, [s_perms_label]
    mov ecx, s_perms_label_len
    call draw_page_label
    call my_perms
    mov r13d, eax
    xor r12d, r12d
.perm:
    mov eax, r12d
    shl eax, 4
    mov rdx, [perm_names + rax]
    mov ecx, [perm_names + rax + 8]
    lea edi, [ebx + OPTION_X]
    mov esi, ebp
    mov r8d, INK(C_TEXT, ST_BODY)
    call draw_text
    xor edx, edx
    bt [role_perms], r12d
    setc dl
    xor ecx, ecx
    bt r13d, r12d
    setc cl
    lea edi, [ebx + SETTINGS_W - 28 - SWITCH_W]
    lea esi, [ebp - 14]
    mov r8d, A_ROLE_PERM
    mov r9d, r12d
    call draw_switch
    add ebp, PERM_ROW_H
    inc r12d
    cmp r12d, PERM_COUNT
    jb .perm
    mov eax, ebp
    add rsp, 8
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Save, then for an existing role Move up, Move down and Delete role.
; edi = x, esi = the buttons' top
draw_role_buttons:
    push rbx
    push rbp
    push r12
    mov ebx, edi
    mov ebp, esi
    lea edi, [ebx + 28]
    mov esi, ebp
    lea rdx, [s_save_role]
    mov ecx, s_save_role_len
    mov r8d, A_SAVE_ROLE
    mov r9d, BTN_PRIMARY
    call draw_button
    lea r12d, [ebx + 28 + eax + 16]
    mov eax, [role_editing]
    dec eax
    cmp eax, ROLE_SLOTS - 1
    ja .done                                ; @everyone and new roles don't move or go
    mov edi, r12d
    lea esi, [ebp + 21]
    lea rdx, [s_move_up]
    mov ecx, s_move_up_len
    mov r8d, A_MOVE_ROLE
    mov r9d, 1
    call left_link
    lea edi, [eax + 16]
    lea esi, [ebp + 21]
    lea rdx, [s_move_down]
    mov ecx, s_move_down_len
    mov r8d, A_MOVE_ROLE
    xor r9d, r9d
    call left_link
    lea rdx, [s_delete_role]
    mov ecx, s_delete_role_len
    lea rax, [s_delete_role_sure]
    mov esi, s_delete_role_sure_len
    cmp byte [role_armed], 0
    cmovne rdx, rax
    cmovne ecx, esi
    push rdx
    push rcx
    mov rdi, rdx
    mov esi, ecx
    mov edx, ST_MEDIUM
    call text_width
    pop rcx
    pop rdx
    lea edi, [ebx + SETTINGS_W - 28 - 24]
    sub edi, eax                            ; right-aligned
    mov esi, ebp
    mov r8d, A_DELETE_ROLE
    mov r9d, BTN_DANGER
    cmp byte [role_armed], 0
    jne .delete
    xor r9d, r9d
.delete:
    call draw_button
.done:
    pop r12
    pop rbp
    pop rbx
    ret

; The editor: Back, the name and color, the permissions, then the buttons.
; edi = x, esi = top
draw_role_editor:
    push rbx
    push rbp
    push r12
    mov ebx, edi
    mov r12d, esi
    lea edi, [ebx + 28]
    lea esi, [r12d + 14]
    lea rdx, [s_back_to_roles]
    mov ecx, s_back_to_roles_len
    mov r8d, A_EDIT_ROLE
    mov r9d, ROLE_LIST
    call left_link
    lea ebp, [r12d + 30 + 24]               ; the next row's baseline
    cmp dword [role_editing], 0
    je .perms
    mov edi, ebx
    mov esi, ebp
    lea rdx, [s_role_name_label]
    mov ecx, s_role_name_label_len
    mov r8d, F_ROLE_NAME
    xor r9d, r9d
    call draw_page_field
    add ebp, FIELD_ROW_H
    mov edi, ebx
    mov esi, ebp
    call draw_swatches
    add ebp, 40
.perms:
    mov edi, ebx
    mov esi, ebp
    call draw_perm_switches
    mov edi, ebx
    lea esi, [eax + 4]
    call draw_role_buttons
    pop r12
    pop rbp
    pop rbx
    ret

; The roles tab: the list, or the editor. edi = x, esi = top
draw_roles_tab:
    cmp dword [role_editing], ROLE_LIST
    jne draw_role_editor
    jmp draw_role_list

; -> eax = the AutoMod tab's height, with its box as tall as the words in it
automod_tab_height:
    sub rsp, 8
    call automod_box_height
    add eax, 20 + 48 + 70
    add rsp, 8
    ret

; -> eax = the height of the box for the blocked words
automod_box_height:
    sub rsp, 8
    mov edi, F_AUTOMOD
    call field_addr
    mov rdi, [rax + FD_BUF]
    mov esi, [rax + FD_LEN]
    mov edx, SETTINGS_W - 56 - 24
    mov ecx, ST_BODY
    call text_height
    add eax, 24
    mov ecx, 120
    cmp eax, ecx
    cmovl eax, ecx
    add rsp, 8
    ret

; The AutoMod tab: the blocked words, the timeout for using one, and Save.
; edi = x, esi = top
draw_automod_tab:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov ebx, edi
    mov r12d, esi
    lea edi, [ebx + 28]
    lea esi, [r12d + 14]
    lea rdx, [s_words_label]
    mov ecx, s_words_label_len
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    call automod_box_height
    mov r13d, eax
    lea ebp, [r12d + 24]                    ; the box's top
    mov edi, F_AUTOMOD
    call field_focused
    mov r8d, C_LINE
    mov ecx, C_ACCENT
    test eax, eax
    cmovnz r8d, ecx
    lea edi, [ebx + 28]
    mov esi, ebp
    mov edx, SETTINGS_W - 56
    mov ecx, r13d
    mov r9d, C_RAISED
    mov r10d, 8
    call outline_rrect
    lea edi, [ebx + 28]
    mov esi, ebp
    mov edx, SETTINGS_W - 56
    mov ecx, r13d
    mov r8d, A_FIELD
    mov r9d, F_AUTOMOD
    call add_hit
    mov edi, F_AUTOMOD
    lea esi, [ebx + 40]
    lea edx, [ebp + 12]
    mov ecx, SETTINGS_W - 56 - 24
    call draw_area
    lea r14d, [ebp + r13d + 34]             ; the timeout's baseline
    lea edi, [ebx + 28]
    mov esi, r14d
    lea rdx, [s_automod_timeout]
    mov ecx, s_automod_timeout_len
    call draw_page_label
    mov edi, ebx
    mov esi, r14d
    call draw_automod_timeouts
    lea edi, [ebx + 28]
    lea esi, [r14d + 22]
    lea rdx, [s_save_automod]
    mov ecx, s_save_automod_len
    mov r8d, A_SAVE_AUTOMOD
    mov r9d, BTN_PRIMARY
    call draw_button
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Only block, then the timeout lengths, the one picked highlighted.
; edi = x, esi = baseline
draw_automod_timeouts:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 8
    mov ebx, edi
    mov ebp, esi
    lea r12d, [ebx + OPTION_X]
    mov r13d, -1                            ; Only block, then the presets
.option:
    lea rdx, [s_no_timeout]
    mov ecx, s_no_timeout_len
    xor r9d, r9d
    test r13d, r13d
    js .draw
    mov eax, r13d
    shl eax, 4
    mov rdx, [timeout_names + rax]
    mov ecx, [timeout_names + rax + 8]
    mov r9d, [timeout_secs + r13 * 4]
.draw:
    mov edi, r12d
    mov esi, ebp
    cmp r9d, [automod_choice]
    je .current
    mov r8d, A_AUTOMOD_TIMEOUT
    call left_link
    jmp .next
.current:
    mov r8d, INK(C_ACCENT_HI, ST_SMALL)
    call draw_text
.next:
    lea r12d, [eax + 14]
    inc r13d
    cmp r13d, TIMEOUT_PRESETS
    jb .option
    add rsp, 8
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
