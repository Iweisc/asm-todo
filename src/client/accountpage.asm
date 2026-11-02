; Drawing the account dialog: its tabs, Profile, Password and sessions, and
; Teams. account.asm has what they do and the data they show.

section .text

; -> eax = the open tab's height, as it's drawn
account_height:
    mov eax, [account_tab]
    cmp eax, ACC_SECURITY
    je .security
    cmp eax, ACC_TEAMS
    je .teams
    mov eax, PROFILE_H
    ret
.security:
    mov eax, [session_count]
    mov ecx, 1                              ; for the line saying they're loading
    cmp byte [account_loaded], 0
    cmove eax, ecx
    imul eax, eax, ACC_ROW_H
    add eax, SECURITY_TOP + 8
    ret
.teams:
    mov eax, [team_count]
    mov ecx, 1                              ; for the line saying there are none
    test eax, eax
    cmovz eax, ecx
    imul eax, eax, ACC_ROW_H
    add eax, 48 + 8
    ret

; Joined, teams and sessions, then deleting the account. edi = x, esi = top
draw_profile:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    lea edi, [ebx + 28]
    lea esi, [r12d + 8]
    mov edx, 48
    mov ecx, [my_id]
    lea r8, [my_name]
    call draw_avatar
    lea edi, [ebx + 92]
    lea esi, [r12d + 30]
    lea rdx, [my_name]
    mov ecx, [my_name_len]
    mov r8d, INK(C_TEXT, ST_TITLE)
    call draw_text
    lea rdi, [scratch]
    lea rsi, [s_user_number]
    mov edx, s_user_number_len
    call put_mem
    mov esi, [my_id]
    call put_u32
    mov rcx, rdi
    lea edi, [ebx + 92]
    lea esi, [r12d + 50]
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_scratch
    mov edi, ebx
    mov esi, r12d
    call draw_profile_rows
    mov edi, ebx
    lea esi, [r12d + 188]
    call draw_delete_account
    add rsp, 8
    pop r12
    pop rbx
    ret

; A row of the profile: its label, then a value. edi = x, esi = baseline,
; rdx = label, ecx = its length -> rdi = scratch, for the value
profile_label:
    add edi, 28
    call draw_page_label
    lea rdi, [scratch]
    ret

; Joined, Teams and Sessions, the last two with a link to their tab.
; edi = x, esi = top
draw_profile_rows:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov edi, ebx
    lea esi, [r12d + 96]
    lea rdx, [s_joined]
    mov ecx, s_joined_len
    call profile_label
    lea rsi, [s_loading]
    mov edx, s_loading_len
    cmp byte [account_loaded], 0
    je .joined
    mov esi, [joined]
    test esi, esi
    jnz .date
    lea rsi, [s_joined_unknown]
    mov edx, s_joined_unknown_len
.joined:
    call put_mem
    jmp .joined_drawn
.date:
    call put_full_date
.joined_drawn:
    mov rcx, rdi
    lea edi, [ebx + OPTION_X]
    lea esi, [r12d + 96]
    mov r8d, INK(C_TEXT, ST_BODY)
    call draw_scratch
    mov edi, ebx
    lea esi, [r12d + 128]
    lea rdx, [s_tab_teams]
    mov ecx, s_tab_teams_len
    call profile_label
    mov esi, [team_count]
    lea rdx, [s_one_team]
    mov ecx, s_one_team_len
    call put_count
    mov rcx, rdi
    mov edi, ebx
    lea esi, [r12d + 128]
    mov edx, ACC_TEAMS
    call profile_value_link
    mov edi, ebx
    lea esi, [r12d + 160]
    lea rdx, [s_sessions]
    mov ecx, s_sessions_len
    call profile_label
    lea rsi, [s_loading]
    mov edx, s_loading_len
    cmp byte [account_loaded], 0
    je .sessions
    mov esi, [session_count]
    call put_u32
    lea rsi, [s_signed_in_now]
    mov edx, s_signed_in_now_len
.sessions:
    call put_mem
    mov rcx, rdi
    mov edi, ebx
    lea esi, [r12d + 160]
    mov edx, ACC_SECURITY
    call profile_value_link
    add rsp, 8
    pop r12
    pop rbx
    ret

; The value in scratch, then Manage, which opens a tab. edi = x,
; esi = baseline, edx = ACC_*, rcx = the value's end in scratch
profile_value_link:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, esi
    mov r12d, edx
    add edi, OPTION_X
    mov esi, ebx
    mov r8d, INK(C_TEXT, ST_BODY)
    call draw_scratch
    lea edi, [eax + 16]
    mov esi, ebx
    lea rdx, [s_manage]
    mov ecx, s_manage_len
    mov r8d, A_ACCOUNT_TAB
    mov r9d, r12d
    call left_link
    add rsp, 8
    pop r12
    pop rbx
    ret

; What deleting does, the password box and the button, which asks with a
; first click. edi = x, esi = top
draw_delete_account:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    lea edi, [ebx + 28]
    mov esi, r12d
    mov edx, SETTINGS_W - 56
    mov ecx, 1
    mov r8d, C_LINE
    call fill_rect
    lea edi, [ebx + 28]
    lea esi, [r12d + 34]
    lea rdx, [s_delete_account]
    mov ecx, s_delete_account_len
    mov r8d, INK(C_DANGER, ST_MEDIUM)
    call draw_text
    lea edi, [ebx + 28]
    lea esi, [r12d + 56]
    lea rdx, [s_delete_account_hint]
    mov ecx, s_delete_account_hint_len
    mov r8d, INK(C_DIM, ST_SMALL)
    mov r9d, SETTINGS_W - 56
    call draw_text_fit
    lea edi, [ebx + 28]
    lea esi, [r12d + 74]
    lea rdx, [s_delete_account_keeps]
    mov ecx, s_delete_account_keeps_len
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    mov edi, ebx
    lea esi, [r12d + 118]
    lea rdx, [s_password_label]
    mov ecx, s_password_label_len
    mov r8d, F_DELETE_PASS
    xor r9d, r9d
    call draw_page_field
    lea rdx, [s_delete_account]
    mov ecx, s_delete_account_len
    cmp dword [account_armed], -1
    jne .busy
    lea rdx, [s_delete_account_sure]
    mov ecx, s_delete_account_sure_len
.busy:
    cmp byte [deleting], 0
    je .button
    lea rdx, [s_deleting_account]
    mov ecx, s_deleting_account_len
.button:
    lea edi, [ebx + OPTION_X]
    lea esi, [r12d + 143]
    mov r8d, A_DELETE_ACCOUNT
    mov r9d, BTN_DANGER
    call draw_button
    add rsp, 8
    pop r12
    pop rbx
    ret

; Both password boxes and the button that sends them. edi = x, esi = top
draw_password_change:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    lea edi, [ebx + 28]
    lea esi, [r12d + 24]
    lea rdx, [s_change_password]
    mov ecx, s_change_password_len
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    lea edi, [ebx + 28]
    lea esi, [r12d + 56]
    lea rdx, [s_current_password]
    mov ecx, s_current_password_len
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    mov edi, F_OLD_PASS
    lea esi, [ebx + 28]
    lea edx, [r12d + 66]
    mov ecx, SETTINGS_W - 56
    call draw_field_box
    lea edi, [ebx + 28]
    lea esi, [r12d + 122]
    lea rdx, [s_new_password]
    mov ecx, s_new_password_len
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    mov edi, F_NEW_PASS
    lea esi, [ebx + 28]
    lea edx, [r12d + 132]
    mov ecx, SETTINGS_W - 56
    call draw_field_box
    lea rdx, [s_change_password]
    mov ecx, s_change_password_len
    cmp byte [password_busy], 0
    je .button
    lea rdx, [s_changing]
    mov ecx, s_changing_len
.button:
    lea edi, [ebx + 28]
    lea esi, [r12d + 182]
    mov r8d, A_CHANGE_PASSWORD
    mov r9d, BTN_PRIMARY
    call draw_button
    add rsp, 8
    pop r12
    pop rbx
    ret

; One session: whether it's this one, whether it's connected, when it signed
; in and last connected, and Log out for the others. edi = x, esi = top,
; rdx = session row
draw_session_row:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    lea edi, [ebx + 34]
    lea esi, [r12d + 20]
    mov edx, 5
    mov ecx, C_FAINT
    mov eax, C_ONLINE
    test byte [r13 + AS_FLAGS], SS_ONLINE
    cmovnz ecx, eax
    call fill_disc
    lea rdx, [s_other_device]
    mov ecx, s_other_device_len
    test byte [r13 + AS_FLAGS], SS_CURRENT
    jz .name
    lea rdx, [s_this_device]
    mov ecx, s_this_device_len
.name:
    lea edi, [ebx + 52]
    lea esi, [r12d + 24]
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    lea rdi, [scratch]
    test byte [r13 + AS_FLAGS], SS_ONLINE
    jz .last
    lea rsi, [s_online_now]
    mov edx, s_online_now_len
    call put_mem
    call put_middot
    jmp .signed_in
.last:
    mov esi, [r13 + AS_SEEN]
    test esi, esi
    jz .signed_in                           ; from before it was kept
    push rsi
    lea rsi, [s_last_connected]
    mov edx, s_last_connected_len
    call put_mem
    pop rsi
    call put_ago
    call put_middot
.signed_in:
    lea rsi, [s_signed_in_at]
    mov edx, s_signed_in_at_len
    call put_mem
    mov esi, [r13 + AS_SIGNED_IN]
    call put_time
    mov rcx, rdi
    lea edi, [ebx + 52]
    lea esi, [r12d + 42]
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_scratch
    test byte [r13 + AS_FLAGS], SS_CURRENT
    jnz .done                               ; Log out in the sidebar ends this one
    lea edi, [ebx + SETTINGS_W - 28]
    lea esi, [r12d + 24]
    lea rdx, [s_log_out]
    mov ecx, s_log_out_len
    mov r8d, A_END_SESSION
    mov r9d, [r13 + AS_ID]
    call right_link
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Changing the password, then our sessions with Log out everywhere else.
; edi = x, esi = top
draw_security:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    call draw_password_change
    lea edi, [ebx + 28]
    lea esi, [r12d + 228]
    mov edx, SETTINGS_W - 56
    mov ecx, 1
    mov r8d, C_LINE
    call fill_rect
    lea edi, [ebx + 28]
    lea esi, [r12d + 260]
    lea rdx, [s_sessions]
    mov ecx, s_sessions_len
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    lea r13d, [r12d + SECURITY_TOP]
    cmp byte [account_loaded], 0
    je .loading
    cmp dword [session_count], 1
    jbe .rows
    lea edi, [ebx + SETTINGS_W - 28]
    lea esi, [r12d + 260]
    lea rdx, [s_end_others]
    mov ecx, s_end_others_len
    mov r8d, A_END_SESSION
    mov r9d, -1
    call right_link
.rows:
    lea r14, [session_rows]
    mov r12d, [session_count]
.row:
    test r12d, r12d
    jz .done
    mov edi, ebx
    mov esi, r13d
    mov rdx, r14
    call draw_session_row
    add r13d, ACC_ROW_H
    add r14, AS_SIZE
    dec r12d
    jmp .row
.loading:
    lea edi, [ebx + 28]
    lea esi, [r13d + 26]
    lea rdx, [s_loading]
    mov ecx, s_loading_len
    mov r8d, INK(C_DIM, ST_BODY)
    call draw_text
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Leave on a team's row, red and asking once it's been clicked.
; edi = right edge, esi = baseline, edx = team -> eax = its left x
draw_leave_link:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    cmp [account_armed], edx
    je .armed
    lea rdx, [s_leave]
    mov ecx, s_leave_len
    mov r8d, A_LEAVE_TEAM
    mov r9d, r13d
    call right_link
    jmp .done
.armed:
    lea rdx, [s_leave_sure]
    mov ecx, s_leave_sure_len
    mov r8d, C_DANGER
    call draw_link
    push rax
    mov edi, eax
    mov esi, r12d
    mov r8d, A_LEAVE_TEAM
    mov r9d, r13d
    call add_link_hit
    pop rax
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Open (or Current), Settings and Leave, right to left from Leave.
; edi = right edge, esi = baseline, edx = team
draw_team_links:
    push rbx
    push r12
    push r13
    mov ebx, esi
    mov r12d, edx
    call draw_leave_link
    lea edi, [eax - 16]
    mov esi, ebx
    lea rdx, [s_settings]
    mov ecx, s_settings_len
    mov r8d, A_TEAM_SETTINGS
    mov r9d, r12d
    call right_link
    lea edi, [eax - 16]
    mov esi, ebx
    cmp r12d, [current_team]
    je .current
    lea rdx, [s_open]
    mov ecx, s_open_len
    mov r8d, A_GO_TEAM
    mov r9d, r12d
    call right_link
    jmp .done
.current:
    lea rdx, [s_current]
    mov ecx, s_current_len
    mov r8d, C_FAINT
    call draw_link
.done:
    pop r13
    pop r12
    pop rbx
    ret

; One team: its badge, name and key, our role, its size, and what we can do.
; edi = x, esi = top, rdx = team row
draw_team_row:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    lea edi, [ebx + 28]
    lea esi, [r12d + 12]
    mov edx, 28
    mov rcx, r13
    call draw_team_badge
    lea edi, [ebx + 68]
    lea esi, [r12d + 24]
    lea rdx, [r13 + CO_NAME]
    movzx ecx, byte [r13 + CO_NAME_LEN]
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    mov r9d, 280
    call draw_text_fit
    lea edi, [rbx + rax + 68 + 8]
    lea esi, [r12d + 24]
    lea rdx, [r13 + CO_KEY]
    movzx ecx, byte [r13 + CO_KEY_LEN]
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_text
    movzx edi, byte [r13 + CO_ROLE]
    call role_name
    lea rdi, [scratch]
    call put_mem
    cmp byte [account_loaded], 0
    je .size_drawn
    push rdi
    mov edi, [r13 + CO_ID]
    call find_team_size
    pop rdi
    test rax, rax
    jz .size_drawn
    push rax
    call put_middot
    mov rax, [rsp]
    movzx esi, byte [rax + AT_MEMBERS]
    lea rdx, [s_one_member]
    mov ecx, s_one_member_len
    call put_count
    call put_middot
    pop rax
    movzx esi, word [rax + AT_OPEN]
    lea rdx, [s_open_issue]
    mov ecx, s_open_issue_len
    call put_count
.size_drawn:
    mov rcx, rdi
    lea edi, [ebx + 68]
    lea esi, [r12d + 42]
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_scratch
    lea edi, [ebx + SETTINGS_W - 28]
    lea esi, [r12d + 24]
    mov edx, [r13 + CO_ID]
    call draw_team_links
    pop r13
    pop r12
    pop rbx
    ret

; Every team we're on, with New team. edi = x, esi = top
draw_my_teams:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    lea edi, [ebx + 28]
    lea esi, [r12d + 24]
    lea rdx, [s_your_teams]
    mov ecx, s_your_teams_len
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    lea rdi, [s_new_team]
    mov esi, s_new_team_len
    mov edx, ST_MEDIUM
    call text_width
    lea edi, [ebx + SETTINGS_W - 28 - 24]   ; draw_button adds 24 to the text
    sub edi, eax
    lea esi, [r12d + 4]
    lea rdx, [s_new_team]
    mov ecx, s_new_team_len
    mov r8d, A_NEW_TEAM
    xor r9d, r9d
    call draw_button
    lea r13d, [r12d + 48]
    mov r12d, [team_count]
    test r12d, r12d
    jz .none
    lea r14, [teams]
.team:
    mov edi, ebx
    mov esi, r13d
    mov rdx, r14
    call draw_team_row
    add r13d, ACC_ROW_H
    add r14, CO_SIZE
    dec r12d
    jnz .team
    jmp .done
.none:
    lea edi, [ebx + 28]
    lea esi, [r13d + 26]
    lea rdx, [s_no_teams]
    mov ecx, s_no_teams_len
    mov r8d, INK(C_DIM, ST_BODY)
    call draw_text
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; The dialog: the title, the tabs, and the open tab, which scrolls when the
; window can't fit it.
draw_account_dialog:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    call account_height
    mov r15d, eax
    mov eax, [win_h]
    sub eax, 80 + 40 + 28 + ACCOUNT_TOP     ; the room for the tab
    cmp eax, ACC_ROW_H
    jge .room
    mov eax, ACC_ROW_H
.room:
    cmp eax, r15d
    cmovg eax, r15d
    mov [rsp], eax
    lea esi, [eax + ACCOUNT_TOP + 28]
    mov edi, SETTINGS_W
    call modal_box
    mov ebx, eax
    mov r12d, edx
    lea edi, [ebx + 28]
    lea esi, [r12d + 46]
    lea rdx, [s_account_title]
    mov ecx, s_account_title_len
    mov r8d, INK(C_TEXT, ST_TITLE)
    call draw_text
    mov edi, ebx
    lea esi, [r12d + 94]
    lea rdx, [account_tabs]
    mov ecx, (1 << ACC_COUNT) - 1
    mov r8d, [account_tab]
    mov r9d, A_ACCOUNT_TAB
    call draw_tab_strip
    lea rdi, [account_scroll]
    mov esi, [rsp]
    mov edx, r15d
    call clamp_scroll_to
    lea r14d, [r12d + ACCOUNT_TOP]
    mov edi, ebx
    mov esi, r14d
    lea edx, [ebx + SETTINGS_W]
    mov ecx, [rsp]
    add ecx, r14d
    call set_clip
    sub r14d, [account_scroll]
    mov edi, ebx
    mov esi, r14d
    mov eax, [account_tab]
    cmp eax, ACC_SECURITY
    je .security
    cmp eax, ACC_TEAMS
    je .teams
    call draw_profile
    jmp .drawn
.security:
    call draw_security
    jmp .drawn
.teams:
    call draw_my_teams
.drawn:
    call reset_clip
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
