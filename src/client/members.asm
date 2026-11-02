; Team settings, the team's dashboard: its name, an overview (overview.asm),
; its members, and tabs for its roles, bans, audit log and AutoMod for
; whoever's permissions get them (access.asm). A member's page
; (dashboard.asm) changes their nickname and roles, times them out, kicks or
; bans them, as far as our permissions and rank go. The roles and AutoMod
; tabs are in rolepage.asm. Everyone can look, search, and leave. Remove,
; Leave, Kick and Ban ask first, with a second click.

%define SETTINGS_W      640
%define MEMBER_ROW_H    44
%define LIST_ROW_H      52              ; a ban or an audit entry
%define CONTENT_TOP     190             ; where the tabs' content starts, from the dialog's top
%define FIELD_ROW_H     44              ; a field above the list
%define TAB_OVERVIEW    0
%define TAB_MEMBERS     1
%define TAB_ROLES       2
%define TAB_BANS        3
%define TAB_AUDIT       4
%define TAB_AUTOMOD     5
%define TAB_COUNT       6

section .rodata
text s_settings_title,  "Team settings"
text s_team_name_label, "Name"
text s_save,            "Save"
text s_invite,          "Invite"
text s_you,             "(you)"
text s_role_owner,      "Owner"
text s_role_member,     "Member"
text s_manage,          "Manage"
text s_remove_sure,     "Remove?"
text s_leave_team,      "Leave team"
text s_leave_sure,      "Leave?"
text s_timed_out,       "Timed out"
text s_no_match,        "Nobody on the team has that in their name."
text s_tab_overview,    "Overview"
text s_tab_roles,       "Roles"
text s_tab_bans,        "Bans"
text s_tab_audit,       "Audit log"
text s_tab_automod,     "AutoMod"
text s_search_hint,     "Search members"
text s_overview_hint,   "Online counts the members who have the team open right now."
text s_settings_hint,   "Removing someone also unassigns them from the team's issues."
text s_bans_hint,       "Unbanning lets them be invited again. It doesn't add them back."
text s_audit_hint,      "The newest 50 changes to the team's members, roles and posts."
text s_roles_hint,      "Members get the permissions of @everyone and each of their roles."
text s_automod_hint,    "Blocked in channels. One per line, * at either end matches the rest of a word."

align 8
role_names:     NAME s_role_owner       ; by ROLE_* - 1
                NAME s_role_member
tab_names:      NAME s_tab_overview     ; by TAB_*
                NAME s_members
                NAME s_tab_roles
                NAME s_tab_bans
                NAME s_tab_audit
                NAME s_tab_automod
tab_hints:      NAME s_overview_hint
                NAME s_settings_hint
                NAME s_roles_hint
                NAME s_bans_hint
                NAME s_audit_hint
                NAME s_automod_hint
tab_perms:      dd 0, 0, PERM_MANAGE_ROLES, PERM_BAN, PERM_VIEW_AUDIT, PERM_MANAGE_AUTOMOD

section .bss
alignb 4
member_armed:   resd 1                  ; the member whose Remove, Leave, Kick or Ban was clicked once, 0 for none
armed_action:   resd 1                  ; which of those it was
settings_scroll: resd 1
settings_tab:   resd 1                  ; TAB_*
managing:       resd 1                  ; the member whose page is open, 0 for the list
search_buf:     resb USERNAME_MAX

section .text

; -> eax = our role in the current team, 0 without one
my_role:
    sub rsp, 8
    call current_team_row
    test rax, rax
    jz .done
    movzx eax, byte [rax + CO_ROLE]
.done:
    add rsp, 8
    ret

; -> eax = 1 if we own the current team
am_owner:
    sub rsp, 8
    call my_role
    cmp eax, ROLE_OWNER
    sete al
    movzx eax, al
    add rsp, 8
    ret

; edi = TAB_* -> eax = 1 if our permissions get us that tab
tab_shown:
    mov edi, [tab_perms + rdi * 4]
    mov eax, 1
    test edi, edi
    jz .done
    jmp has_perm
.done:
    ret

; rdi = member row -> eax = 1 if they're timed out right now
member_timed_out:
    push rbx
    mov ebx, [rdi + CM_TIMEOUT]
    call unix_now
    cmp ebx, eax
    seta al
    movzx eax, al
    pop rbx
    ret

; edi = ROLE_* -> rsi = its name, edx = length
role_name:
    dec edi
    cmp edi, ROLE_MEMBER - 1
    jbe .known
    mov edi, ROLE_MEMBER - 1                ; whatever it is, it's no more than a member
.known:
    shl edi, 4
    mov rsi, [role_names + rdi]
    mov edx, [role_names + rdi + 8]
    ret

; Opens the dialog on its overview, or its member list to invite someone.
; edi = field to focus
open_team_settings:
    push rbx
    mov ebx, edi
    mov byte [menu_open], 0
    mov byte [modal], M_SETTINGS
    xor eax, eax
    mov [member_armed], eax
    mov [settings_scroll], eax
    mov [managing], eax
    mov ecx, TAB_MEMBERS                    ; where the invite box is
    cmp ebx, F_MEMBER
    cmovne ecx, eax
    mov [settings_tab], ecx
    mov dword [role_editing], ROLE_LIST
    mov edi, F_SEARCH
    call field_clear
    mov edi, F_REASON
    call field_clear
    mov edi, F_DELETE_KEY
    call field_clear
    call current_team_row
    test rax, rax
    jz .focus
    lea rsi, [rax + CO_NAME]
    movzx edx, byte [rax + CO_NAME_LEN]
    mov edi, F_TEAM_RENAME
    call field_set
.focus:
    mov edi, PERM_INVITE
    call has_perm
    test eax, eax
    jnz .staff
    mov ebx, F_NONE                         ; the invite box is only drawn for those who can invite
.staff:
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

; The first click on Remove, Leave, Kick or Ban asks, the second goes ahead.
; edi = user id, esi = the action -> eax = 1 on the second
confirm_member:
    cmp edi, [member_armed]
    jne .arm
    cmp esi, [armed_action]
    jne .arm
    xor eax, eax
    mov [member_armed], eax
    inc eax
    ret
.arm:
    mov [member_armed], edi
    mov [armed_action], esi
    xor eax, eax
    ret

; Remove in the member list, or Leave. edi = user id, esi = A_REMOVE or A_LEAVE
click_remove_member:
    push rbx
    mov ebx, edi
    call confirm_member
    test eax, eax
    jz .done
    mov edi, ebx
    xor esi, esi
    xor edx, edx
    call sync_remove_member
.done:
    pop rbx
    ret

; Gives the member being managed a role. edi = ROLE_*
click_set_role:
    mov esi, edi
    mov edi, [managing]
    jmp sync_set_role

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

; Switches team settings to another tab, at its top. edi = TAB_*
click_tab:
    mov [settings_tab], edi
    xor eax, eax
    mov [managing], eax
    mov [settings_scroll], eax
    mov [member_armed], eax
    mov dword [role_editing], ROLE_LIST
    mov edi, F_NONE
    jmp set_focus

; Opens a member's page, with their nickname to edit, or goes back to the
; list. edi = user id, 0 for the list
click_manage:
    sub rsp, 8
    mov [managing], edi
    xor eax, eax
    mov [settings_scroll], eax
    mov [member_armed], eax
    mov [ban_history], eax
    mov edi, F_REASON
    call field_clear
    mov edi, F_NICK
    call field_clear
    mov edi, [managing]
    call find_member_row
    test rax, rax
    jz .focus
    lea rsi, [rax + CM_NICK]
    movzx edx, byte [rax + CM_NICK_LEN]
    mov edi, F_NICK
    call field_set
.focus:
    mov edi, F_NONE
    call set_focus
    add rsp, 8
    ret

; The member list changed, or our roles did. A member's page closes once
; they're gone or out of our reach, and a tab once we can't see it.
settings_members_changed:
    sub rsp, 8
    mov edi, [settings_tab]
    call tab_shown
    test eax, eax
    jnz .page
    mov dword [settings_tab], TAB_MEMBERS
.page:
    mov edi, [managing]
    test edi, edi
    jz .done
    call find_member_row
    test rax, rax
    jz .close
    mov rdi, rax
    call can_manage
    test eax, eax
    jnz .done
.close:
    mov dword [managing], 0
.done:
    add rsp, 8
    ret

; rdi = name, esi = length -> eax = 1 if the search box is empty or the name
; has what's in it, ignoring case
name_matches:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    mov edi, F_SEARCH
    call field_trimmed
    mov eax, 1
    test edx, edx
    jz .done
    mov r8, rbx                             ; where the match would start
    mov r9d, r12d                           ; and what's left from there
.start:
    xor eax, eax
    cmp r9d, edx
    jb .done
    xor ecx, ecx
.char:
    cmp ecx, edx
    jae .found
    movzx eax, byte [r8 + rcx]
    lea r10d, [eax - 'A']
    cmp r10d, 'Z' - 'A'
    ja .name_lower
    or eax, 0x20
.name_lower:
    movzx r11d, byte [rsi + rcx]
    lea r10d, [r11d - 'A']
    cmp r10d, 'Z' - 'A'
    ja .search_lower
    or r11d, 0x20
.search_lower:
    cmp eax, r11d
    jne .next
    inc ecx
    jmp .char
.next:
    inc r8
    dec r9d
    jmp .start
.found:
    mov eax, 1
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; rdi = member row -> eax = 1 if the search box lets them through, by
; username or nickname
member_matches:
    push rbx
    mov rbx, rdi
    lea rdi, [rbx + CM_NAME]
    movzx esi, byte [rbx + CM_NAME_LEN]
    call name_matches
    test eax, eax
    jnz .done
    movzx esi, byte [rbx + CM_NICK_LEN]
    test esi, esi
    jz .done
    lea rdi, [rbx + CM_NICK]
    call name_matches
.done:
    pop rbx
    ret

; -> eax = how many members the search box lets through
shown_members:
    push rbx
    push r12
    sub rsp, 8
    lea rbx, [members]
    mov r12d, [member_count]
    xor eax, eax
    mov [rsp], eax
.member:
    test r12d, r12d
    jz .done
    mov rdi, rbx
    call member_matches
    add [rsp], eax
    add rbx, CM_SIZE
    dec r12d
    jmp .member
.done:
    mov eax, [rsp]
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
    mov eax, [rsp + 32]
    cmp eax, [armed_action]
    jne .plain
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

; Leave for us, Remove for whoever we can kick, and Manage for whoever's
; page has something we can change, ours included.
; rdi = member row, esi = right edge, edx = baseline -> eax = where what's
; left of them has to end
draw_member_actions:
    push rbx
    push r12
    push r13
    sub rsp, 16
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov eax, [rbx + CM_ID]
    cmp eax, [my_id]
    jne .others
    mov dword [rsp], A_LEAVE
    mov [rsp + 8], eax
    mov edi, r12d
    mov esi, r13d
    lea rdx, [s_leave_team]
    mov ecx, s_leave_team_len
    lea r8, [s_leave_sure]
    mov r9d, s_leave_sure_len
    call draw_member_link
    lea r12d, [eax - 16]
    jmp .manage
.others:
    mov rdi, rbx
    mov esi, PERM_KICK
    call may_act_on
    test eax, eax
    jz .manage
    mov dword [rsp], A_REMOVE
    mov eax, [rbx + CM_ID]
    mov [rsp + 8], eax
    mov edi, r12d
    mov esi, r13d
    lea rdx, [s_remove]
    mov ecx, s_remove_len
    lea r8, [s_remove_sure]
    mov r9d, s_remove_sure_len
    call draw_member_link
    lea r12d, [eax - 16]
.manage:
    mov rdi, rbx
    call can_manage
    test eax, eax
    jz .none
    mov eax, [rbx + CM_ID]
    mov [rsp + 8], eax
    mov edi, r12d
    mov dword [rsp], A_MANAGE
    mov esi, r13d
    lea rdx, [s_manage]
    mov ecx, s_manage_len
    lea r8, [s_manage]
    mov r9d, s_manage_len
    call draw_member_link
    lea r12d, [eax - 16]
.none:
    mov eax, r12d
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret

; One member: avatar, name, role, whether they're timed out, and what we may do.
; rdi = member row, esi = x, edx = top
draw_member_row:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov rdi, rbx
    call display_name
    mov r8, rsi
    lea edi, [r12d + 28]
    lea esi, [r13d + 10]
    mov edx, 24
    mov ecx, [rbx + CM_ID]
    call draw_avatar
    lea r15d, [r13d + 27]                   ; baseline
    mov rdi, rbx
    lea esi, [r12d + SETTINGS_W - 28]
    mov edx, r15d
    call draw_member_actions
    mov r14d, eax
    mov rdi, rbx
    call member_timed_out
    test eax, eax
    jz .role
    mov edi, r14d
    mov esi, r15d
    lea rdx, [s_timed_out]
    mov ecx, s_timed_out_len
    mov r8d, C_DANGER
    call draw_link
    lea r14d, [eax - 12]
.role:
    lea rdi, [scratch]
    mov rsi, rbx
    call put_rank_name
    lea rdx, [scratch]
    mov rcx, rdi
    sub rcx, rdx
    mov edi, r14d
    mov esi, r15d
    mov r8d, C_FAINT
    call draw_link
    lea r14d, [eax - 16]                    ; where the name has to stop
    mov rdi, rbx
    call display_name
    mov ecx, edx
    mov rdx, rsi
    lea edi, [r12d + 62]
    mov esi, r15d
    mov r8d, INK(C_TEXT, ST_BODY)
    mov r9d, r14d
    sub r9d, edi
    call draw_text_fit
    mov eax, [rbx + CM_ID]
    cmp eax, [my_id]
    jne .done
    mov rdi, rbx
    call display_name
    mov rdi, rsi
    mov esi, edx
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
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; The members the search lets through, or a line saying there are none.
; edi = x, esi = top
draw_member_list:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov ebx, edi
    mov r12d, esi
    xor ebp, ebp                            ; rows drawn
    lea r13, [members]
    mov r14d, [member_count]
.member:
    test r14d, r14d
    jz .listed
    mov rdi, r13
    call member_matches
    test eax, eax
    jz .next
    mov rdi, r13
    mov esi, ebx
    mov edx, r12d
    call draw_member_row
    add r12d, MEMBER_ROW_H
    inc ebp
.next:
    add r13, CM_SIZE
    dec r14d
    jmp .member
.listed:
    test ebp, ebp
    jnz .done
    lea edi, [ebx + 28]
    lea esi, [r12d + 26]
    lea rdx, [s_no_match]
    mov ecx, s_no_match_len
    mov r8d, INK(C_DIM, ST_BODY)
    call draw_text
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; A field and a button side by side, the button at the right edge.
; edi = field, esi = x, edx = y, rcx = button text, r8d = its length,
; r9d = button action, r10d = how wide the two are together
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
    push r10
    mov rdi, r14
    mov esi, r15d
    mov edx, ST_MEDIUM
    call text_width
    add eax, 24                             ; as wide as draw_button makes it
    mov [rsp + 4], eax                      ; over r10's high half, which is 0
    mov edi, ebx
    mov esi, r12d
    mov edx, r13d
    mov ecx, [rsp]
    sub ecx, 12
    sub ecx, eax
    call draw_field_box
    mov edi, r12d
    add edi, [rsp]
    sub edi, [rsp + 4]
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

; A row of tabs, the open one underlined, as wide as the settings dialog.
; edi = the dialog's x, esi = the tabs' baseline, rdx = their names, ecx = bit
; n set to show tab n, r8d = the open tab, r9d = the action, whose arg is the tab
draw_tab_strip:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov ebx, edi
    mov r12d, esi
    mov [rsp], rdx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov [rsp + 16], r9d
    lea edi, [ebx + 28]
    lea esi, [r12d + 11]
    mov edx, SETTINGS_W - 56
    mov ecx, 1
    mov r8d, C_LINE
    call fill_rect
    lea r13d, [ebx + 28]                    ; the next tab's x
    xor ebp, ebp
.tab:
    bt dword [rsp + 8], ebp
    jnc .next
    mov r14d, ebp
    shl r14d, 4
    add r14, [rsp]                          ; its name
    mov rdi, [r14]
    mov esi, [r14 + 8]
    mov edx, ST_MEDIUM
    call text_width
    mov r15d, eax
    mov edi, [rsp + 16]
    mov esi, ebp
    call hovering
    mov r8d, INK(C_DIM, ST_MEDIUM)
    mov ecx, INK(C_TEXT, ST_MEDIUM)
    cmp ebp, [rsp + 12]
    sete dl
    or al, dl
    test al, al
    cmovnz r8d, ecx
    mov edi, r13d
    mov esi, r12d
    mov rdx, [r14]
    mov ecx, [r14 + 8]
    call draw_text
    cmp ebp, [rsp + 12]
    jne .hit
    mov edi, r13d
    lea esi, [r12d + 10]
    mov edx, r15d
    mov ecx, 2
    mov r8d, C_ACCENT
    call fill_rect
.hit:
    mov edi, r13d
    lea esi, [r12d - 18]
    mov edx, r15d
    mov ecx, 30
    mov r8d, [rsp + 16]
    mov r9d, ebp
    call add_hit
    lea r13d, [r13d + r15d + 24]
.next:
    inc ebp
    mov eax, [rsp + 8]
    mov ecx, ebp
    shr eax, cl
    test eax, eax
    jnz .tab
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The tabs our permissions get us. edi = the dialog's x, esi = the tabs' baseline
draw_settings_tabs:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    xor ebx, ebx
    xor r14d, r14d                          ; the tabs shown
.tab:
    mov edi, ebx
    call tab_shown
    test eax, eax
    jz .next
    bts r14d, ebx
.next:
    inc ebx
    cmp ebx, TAB_COUNT
    jb .tab
    mov edi, r12d
    mov esi, r13d
    lea rdx, [tab_names]
    mov ecx, r14d
    mov r8d, [settings_tab]
    mov r9d, A_TAB
    call draw_tab_strip
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; The title, the team's name, and the tabs.
; edi = the dialog's x, esi = its y
draw_settings_head:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
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
    mov edi, PERM_MANAGE_TEAM
    call has_perm
    test eax, eax
    jz .name_text
    mov edi, F_TEAM_RENAME
    lea esi, [ebx + 28]
    lea edx, [r12d + 94]
    lea rcx, [s_save]
    mov r8d, s_save_len
    mov r9d, A_SAVE_TEAM_NAME
    mov r10d, SETTINGS_W - 56
    call draw_field_with_button
    jmp .tabs
.name_text:
    call current_team_row
    test rax, rax
    jz .tabs
    lea edi, [ebx + 28]
    lea esi, [r12d + 118]
    lea rdx, [rax + CO_NAME]
    movzx ecx, byte [rax + CO_NAME_LEN]
    mov r8d, INK(C_TEXT, ST_BODY)
    call draw_text
.tabs:
    mov edi, ebx
    lea esi, [r12d + 166]
    call draw_settings_tabs
    pop r13
    pop r12
    pop rbx
    ret

; The fields above the member list: inviting, for those who can, and the
; search. edi = the dialog's x, esi = its y
draw_settings_fields:
    push rbx
    push r12
    sub rsp, 8
    cmp dword [settings_tab], TAB_MEMBERS
    jne .done
    cmp dword [managing], 0
    jne .done
    mov ebx, edi
    lea r12d, [esi + CONTENT_TOP]
    mov edi, PERM_INVITE
    call has_perm
    test eax, eax
    jz .search
    mov edi, F_MEMBER
    lea esi, [ebx + 28]
    mov edx, r12d
    lea rcx, [s_invite]
    mov r8d, s_invite_len
    mov r9d, A_INVITE
    mov r10d, SETTINGS_W - 56
    call draw_field_with_button
    add r12d, FIELD_ROW_H
.search:
    mov edi, F_SEARCH
    lea esi, [ebx + 28]
    mov edx, r12d
    mov ecx, SETTINGS_W - 56
    call draw_field_box
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -> eax = how far down the dialog the scrolled part starts, edx = its whole height
settings_layout:
    push rbx
    mov ebx, CONTENT_TOP
    mov eax, [settings_tab]
    cmp eax, TAB_OVERVIEW
    je .overview
    cmp eax, TAB_ROLES
    je .roles
    cmp eax, TAB_AUTOMOD
    je .automod
    cmp eax, TAB_MEMBERS
    jne .entries
    mov edi, [managing]
    test edi, edi
    jnz .page
    mov edi, PERM_INVITE
    call has_perm
    imul eax, eax, FIELD_ROW_H
    lea ebx, [ebx + eax + FIELD_ROW_H]      ; the invite box for some, the search for all
    call shown_members
    imul edx, eax, MEMBER_ROW_H
    jmp .at_least_a_row
.page:
    call find_member_row
    mov edx, MEMBER_ROW_H
    test rax, rax
    jz .done
    mov rdi, rax
    call page_height
    mov edx, eax
    jmp .done
.overview:
    call overview_height
    mov edx, eax
    jmp .done
.roles:
    call roles_tab_height
    mov edx, eax
    jmp .done
.automod:
    call automod_tab_height
    mov edx, eax
    jmp .done
.entries:
    mov eax, [ban_count]
    cmp dword [settings_tab], TAB_AUDIT
    cmove eax, [audit_count]
    imul edx, eax, LIST_ROW_H
.at_least_a_row:
    mov eax, MEMBER_ROW_H                   ; for the line saying there's nothing
    cmp edx, eax
    cmovl edx, eax
.done:
    mov eax, ebx
    pop rbx
    ret

; Whichever list or page the dialog shows. edi = the dialog's x, esi = the top
draw_settings_body:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov eax, [settings_tab]
    cmp eax, TAB_OVERVIEW
    je .overview
    cmp eax, TAB_ROLES
    je .roles
    cmp eax, TAB_AUTOMOD
    je .automod
    cmp eax, TAB_BANS
    je .bans
    cmp eax, TAB_AUDIT
    je .audit
    mov edi, [managing]
    test edi, edi
    jz .members
    call find_member_row
    test rax, rax
    jz .done
    mov rdx, rax
    mov edi, ebx
    mov esi, r12d
    call draw_member_page
    jmp .done
.members:
    mov edi, ebx
    mov esi, r12d
    call draw_member_list
    jmp .done
.overview:
    mov edi, ebx
    mov esi, r12d
    call draw_overview
    jmp .done
.roles:
    mov edi, ebx
    mov esi, r12d
    call draw_roles_tab
    jmp .done
.automod:
    mov edi, ebx
    mov esi, r12d
    call draw_automod_tab
    jmp .done
.bans:
    mov edi, ebx
    mov esi, r12d
    call draw_bans
    jmp .done
.audit:
    mov edi, ebx
    mov esi, r12d
    call draw_audit
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; The tab's hint at the bottom. edi = x, esi = baseline
draw_settings_hint:
    mov eax, [settings_tab]
    shl eax, 4
    mov rdx, [tab_hints + rax]
    mov ecx, [tab_hints + rax + 8]
    mov r8d, INK(C_FAINT, ST_SMALL)
    jmp draw_text

; The dialog. Its list or page scrolls when the window can't fit it.
draw_team_settings:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    call settings_layout
    mov r14d, eax                           ; above the scrolled part
    mov r15d, edx                           ; all of it
    mov eax, [win_h]
    sub eax, 80 + 40 + 52
    sub eax, r14d                           ; the room for it
    cmp eax, MEMBER_ROW_H
    jge .room
    mov eax, MEMBER_ROW_H
.room:
    cmp eax, r15d
    cmovg eax, r15d
    mov [rsp], eax                          ; the scrolled part's window
    lea esi, [r14d + eax + 52]
    mov r13d, esi
    mov edi, SETTINGS_W
    call modal_box
    mov ebx, eax
    mov r12d, edx
    mov edi, ebx
    mov esi, r12d
    call draw_settings_head
    mov edi, ebx
    mov esi, r12d
    call draw_settings_fields
    lea rdi, [settings_scroll]
    mov esi, [rsp]
    mov edx, r15d
    call clamp_scroll_to
    add r14d, r12d                          ; the scrolled part's top
    mov edi, ebx
    mov esi, r14d
    lea edx, [ebx + SETTINGS_W]
    mov ecx, [rsp]
    add ecx, r14d
    call set_clip
    sub r14d, [settings_scroll]
    mov edi, ebx
    mov esi, r14d
    call draw_settings_body
    call reset_clip
    lea edi, [ebx + 28]
    lea esi, [r12d + r13d - 22]
    call draw_settings_hint
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
