; Team settings: the team's name, its members and their roles, inviting
; people and leaving. Owners can change all of it. Members can look, and
; leave. Remove and Leave ask first, with a second click.

%define SETTINGS_W      560
%define MEMBER_ROW_H    44

section .rodata
text s_settings_title,  "Team settings"
text s_team_name_label, "Name"
text s_save,            "Save"
text s_invite,          "Invite"
text s_you,             "(you)"
text s_role_owner,      "Owner"
text s_role_member,     "Member"
text s_make_owner,      "Make owner"
text s_make_member,     "Make member"
text s_remove_sure,     "Remove?"
text s_leave_team,      "Leave team"
text s_leave_sure,      "Leave?"
text s_settings_hint,   "Removing someone also unassigns them from the team's issues."

section .bss
alignb 4
member_armed:   resd 1                  ; the member whose Remove or Leave was clicked once, 0 for none
settings_scroll: resd 1

section .text

; -> eax = 1 if we own the current team
am_owner:
    sub rsp, 8
    call current_team_row
    test rax, rax
    jz .done
    cmp byte [rax + CO_ROLE], ROLE_OWNER
    sete al
    movzx eax, al
.done:
    add rsp, 8
    ret

; Opens the dialog with the team's name ready to edit. edi = field to focus
open_team_settings:
    push rbx
    mov ebx, edi
    mov byte [menu_open], 0
    mov byte [modal], M_SETTINGS
    xor eax, eax
    mov [member_armed], eax
    mov [settings_scroll], eax
    call current_team_row
    test rax, rax
    jz .focus
    lea rsi, [rax + CO_NAME]
    movzx edx, byte [rax + CO_NAME_LEN]
    mov edi, F_TEAM_RENAME
    call field_set
.focus:
    call am_owner
    test eax, eax
    jnz .owner
    mov ebx, F_NONE                         ; the boxes are only drawn for owners
.owner:
    mov edi, ebx
    call set_focus
    pop rbx
    ret

; Sends the name in the dialog if it changed.
save_team_name:
    push rbx
    push r12
    push r13
    call current_team_row
    test rax, rax
    jz .done
    mov rbx, rax
    mov edi, F_TEAM_RENAME
    call field_trimmed
    test edx, edx
    jz .done
    mov r12, rsi
    mov r13d, edx
    movzx eax, byte [rbx + CO_NAME_LEN]
    cmp eax, edx
    jne .send
    lea rdi, [rbx + CO_NAME]
    call mem_eq
    test eax, eax
    jnz .done
.send:
    mov rsi, r12
    mov edx, r13d
    call sync_rename_team
.done:
    mov edi, F_NONE
    call set_focus
    pop r13
    pop r12
    pop rbx
    ret

; Invites whoever's named in the invite box. The box empties once they've
; joined, so a failed invite keeps the name to fix.
submit_invite:
    sub rsp, 8
    mov edi, F_MEMBER
    call field_trimmed
    test edx, edx
    jz .done
    call sync_add_member
.done:
    add rsp, 8
    ret

; Makes a member an owner, or an owner a member. edi = user id
click_set_role:
    push rbx
    mov ebx, edi
    call find_member_row
    test rax, rax
    jz .done
    mov esi, ROLE_OWNER
    mov ecx, ROLE_MEMBER
    cmp byte [rax + CM_ROLE], ROLE_OWNER
    cmove esi, ecx
    mov edi, ebx
    call sync_set_role
.done:
    pop rbx
    ret

; The first click on Remove or Leave asks, the second does it. edi = user id
click_remove_member:
    cmp edi, [member_armed]
    je .sure
    mov [member_armed], edi
    ret
.sure:
    mov dword [member_armed], 0
    jmp sync_remove_member

; edi = user id, esi = ROLE_*
sync_set_role:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_SET_ROLE
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    mov esi, ebx
    call wr_u32
    mov esi, r12d
    call wr_u8
    call send_built
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; rsi = name, edx = length
sync_rename_team:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rsi
    mov r12d, edx
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_RENAME_TEAM
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    mov rsi, rbx
    mov edx, r12d
    call wr_str
    call send_built
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; A text link at a right edge, red once it's been clicked to ask.
; edi = right edge, esi = baseline, rdx = text, ecx = length, r8 = the asking
; text, r9d = its length, then on the stack the action and its arg -> eax = its left x
draw_member_link:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov eax, [rsp + 40]
    cmp eax, [member_armed]
    jne .plain
    cmp dword [rsp + 32], A_SET_ROLE        ; only Remove and Leave ask
    je .plain
    mov rdx, r8
    mov ecx, r9d
    mov r8d, C_DANGER
    jmp .draw
.plain:
    mov r8d, C_DIM
.draw:
    call draw_link
    mov r13d, eax
    mov edi, eax
    mov esi, r12d
    mov r8d, [rsp + 32]
    mov r9d, [rsp + 40]
    call add_link_hit
    mov eax, r13d
    pop r13
    pop r12
    pop rbx
    ret

; One member: avatar, name, role, and what we may do to them.
; rdi = member row, esi = x, edx = top, ecx = 1 if we own the team
draw_member_row:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov ebp, ecx
    lea edi, [r12d + 28]
    lea esi, [r13d + 10]
    mov edx, 24
    mov ecx, [rbx + CM_ID]
    lea r8, [rbx + CM_NAME]
    call draw_avatar
    lea r14d, [r12d + SETTINGS_W - 28]      ; links, from the right
    lea r15d, [r13d + 27]                   ; baseline
    mov eax, [rbx + CM_ID]
    cmp eax, [my_id]
    jne .others
    mov dword [rsp], A_LEAVE
    mov [rsp + 8], eax
    mov edi, r14d
    mov esi, r15d
    lea rdx, [s_leave_team]
    mov ecx, s_leave_team_len
    lea r8, [s_leave_sure]
    mov r9d, s_leave_sure_len
    call draw_member_link
    mov r14d, eax
    jmp .role
.others:
    test ebp, ebp
    jz .role
    mov dword [rsp], A_REMOVE
    mov [rsp + 8], eax
    mov edi, r14d
    mov esi, r15d
    lea rdx, [s_remove]
    mov ecx, s_remove_len
    lea r8, [s_remove_sure]
    mov r9d, s_remove_sure_len
    call draw_member_link
    lea r14d, [eax - 16]
    mov dword [rsp], A_SET_ROLE
    mov eax, [rbx + CM_ID]
    mov [rsp + 8], eax
    lea rdx, [s_make_owner]
    mov ecx, s_make_owner_len
    lea rax, [s_make_member]
    mov r9d, s_make_member_len
    cmp byte [rbx + CM_ROLE], ROLE_OWNER
    cmove rdx, rax
    cmove ecx, r9d
    mov edi, r14d
    mov esi, r15d
    call draw_member_link
    mov r14d, eax
.role:
    lea edi, [r14d - 20]
    mov esi, r15d
    lea rdx, [s_role_member]
    mov ecx, s_role_member_len
    lea rax, [s_role_owner]
    mov r8d, s_role_owner_len
    cmp byte [rbx + CM_ROLE], ROLE_OWNER
    cmove rdx, rax
    cmove ecx, r8d
    mov r8d, C_FAINT
    call draw_link
    lea r14d, [eax - 16]                    ; where the name has to stop
    lea edi, [r12d + 62]
    mov esi, r15d
    lea rdx, [rbx + CM_NAME]
    movzx ecx, byte [rbx + CM_NAME_LEN]
    mov r8d, INK(C_TEXT, ST_BODY)
    mov r9d, r14d
    sub r9d, edi
    call draw_text_fit
    mov eax, [rbx + CM_ID]
    cmp eax, [my_id]
    jne .done
    lea rdi, [rbx + CM_NAME]
    movzx esi, byte [rbx + CM_NAME_LEN]
    mov edx, ST_BODY
    call text_width
    lea edi, [r12d + 62 + 6]
    add edi, eax
    mov esi, r15d
    lea rdx, [s_you]
    mov ecx, s_you_len
    mov r8d, INK(C_FAINT, ST_BODY)
    call draw_text
.done:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Owners get a field and a button side by side. edi = field, esi = x,
; edx = y, rcx = button text, r8d = its length, r9d = button action
draw_field_with_button:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14, rcx
    mov r15d, r8d
    push r9
    sub rsp, 8
    mov edi, ebx
    mov esi, r12d
    mov edx, r13d
    mov ecx, SETTINGS_W - 56 - 96
    call draw_field_box
    lea edi, [r12d + SETTINGS_W - 56 - 84]
    lea esi, [r13d + 3]
    mov rdx, r14
    mov ecx, r15d
    mov r8d, [rsp + 8]
    xor r9d, r9d
    call draw_button
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; The dialog. Its member list scrolls when the window can't fit it.
draw_team_settings:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    call am_owner
    mov ebp, eax
    mov r14d, 176                           ; above the member list
    mov eax, 228
    test ebp, ebp
    cmovnz r14d, eax
    mov r15d, [member_count]
    imul r15d, r15d, MEMBER_ROW_H           ; the whole list
    mov eax, [win_h]
    sub eax, 80 + 40 + 52
    sub eax, r14d                           ; the room for it
    cmp eax, MEMBER_ROW_H
    jge .room
    mov eax, MEMBER_ROW_H
.room:
    cmp eax, r15d
    cmovg eax, r15d
    mov [rsp], eax                          ; the list's window
    lea esi, [r14d + eax + 52]
    mov r13d, esi
    mov edi, SETTINGS_W
    call modal_box
    mov ebx, eax
    mov r12d, edx
    lea edi, [ebx + 28]
    lea esi, [r12d + 46]
    lea rdx, [s_settings_title]
    mov ecx, s_settings_title_len
    mov r8d, INK(C_TEXT, ST_TITLE)
    call draw_text
    lea edi, [ebx + 28]
    lea esi, [r12d + 84]
    lea rdx, [s_team_name_label]
    mov ecx, s_team_name_label_len
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    test ebp, ebp
    jz .name_text
    mov edi, F_TEAM_RENAME
    lea esi, [ebx + 28]
    lea edx, [r12d + 94]
    lea rcx, [s_save]
    mov r8d, s_save_len
    mov r9d, A_SAVE_TEAM_NAME
    call draw_field_with_button
    jmp .members
.name_text:
    call current_team_row
    test rax, rax
    jz .members
    lea edi, [ebx + 28]
    lea esi, [r12d + 118]
    lea rdx, [rax + CO_NAME]
    movzx ecx, byte [rax + CO_NAME_LEN]
    mov r8d, INK(C_TEXT, ST_BODY)
    call draw_text
.members:
    lea edi, [ebx + 28]
    lea esi, [r12d + 162]
    test ebp, ebp
    jz .heading
    add esi, 4
.heading:
    lea rdx, [s_members]
    mov ecx, s_members_len
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    test ebp, ebp
    jz .list
    mov edi, F_MEMBER
    lea esi, [ebx + 28]
    lea edx, [r12d + 178]
    lea rcx, [s_invite]
    mov r8d, s_invite_len
    mov r9d, A_INVITE
    call draw_field_with_button
.list:
    lea rdi, [settings_scroll]
    mov esi, [rsp]
    mov edx, r15d
    call clamp_scroll_to
    add r14d, r12d                          ; the list's top
    mov edi, ebx
    mov esi, r14d
    lea edx, [ebx + SETTINGS_W]
    mov ecx, [rsp]
    add ecx, r14d
    call set_clip
    sub r14d, [settings_scroll]
    lea r15, [members]
    mov eax, [member_count]
    mov [rsp + 4], eax
.member:
    cmp dword [rsp + 4], 0
    je .listed
    mov rdi, r15
    mov esi, ebx
    mov edx, r14d
    mov ecx, ebp
    call draw_member_row
    add r14d, MEMBER_ROW_H
    add r15, CM_SIZE
    dec dword [rsp + 4]
    jmp .member
.listed:
    call reset_clip
    lea edi, [ebx + 28]
    lea esi, [r12d + r13d - 22]
    lea rdx, [s_settings_hint]
    mov ecx, s_settings_hint_len
    mov r8d, INK(C_FAINT, ST_SMALL)
    test ebp, ebp
    jz .done
    call draw_text
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
