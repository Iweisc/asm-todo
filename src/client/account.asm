; The account dialog, our own dashboard: who we are and deleting the
; account, changing the password and our sessions, and every team we're on.
; MSG_ACCOUNT brings what only the server knows, when we joined, the
; sessions and each team's size, and is asked for whenever the dialog opens
; or changes tab. A wrong password or a refused deletion comes back as an
; ERROR, which shows like any other and leaves the dialog open to try again.

%define ACCOUNT_TOP     120             ; where a tab's content starts, from the dialog's top
%define ACC_ROW_H       52              ; a session or a team
%define PROFILE_H       372             ; the Profile tab, as draw_profile lays it out
%define SECURITY_TOP    280             ; where the Security tab's sessions start

; A session, as MSG_ACCOUNT lists it.
%define AS_ID           0
%define AS_SIGNED_IN    4
%define AS_SEEN         8
%define AS_FLAGS        12              ; u8, SS_*
%define AS_SIZE         16
fits AS_FLAGS, 1, AS_SIZE

; A team's size, as MSG_ACCOUNT lists it.
%define AT_TEAM         0
%define AT_MEMBERS      4               ; u8
%define AT_OPEN         6               ; u16, its issues not done or canceled
%define AT_SIZE         8
fits AT_MEMBERS, 1, AT_OPEN
fits AT_OPEN, 2, AT_SIZE

section .rodata
text s_account_title,   "Account"
text s_tab_profile,     "Profile"
text s_tab_security,    "Password and sessions"
text s_tab_teams,       "Teams"
text s_user_number,     "User #"
text s_joined,          "Joined"
text s_joined_unknown,  "Before join dates were kept"
text s_sessions,        "Sessions"
text s_signed_in_now,   " signed in"
text s_delete_account,  "Delete account"
text s_delete_account_sure, "Delete account?"
text s_deleting_account, "Deleting..."
text s_delete_account_hint, "You leave every team and your direct messages are deleted. This can't be undone."
text s_delete_account_keeps, "Issues, comments and channel messages you wrote stay."
text s_password_label,  "Password"
text s_current_password, "Current password"
text s_new_password,    "New password, at least 8 characters"
text s_change_password, "Change password"
text s_changing,        "Changing..."
text s_end_others,      "Log out everywhere else"
text s_this_device,     "This device"
text s_other_device,    "Another device"
text s_online_now,      "Online now"
text s_last_connected,  "Last connected "
text s_signed_in_at,    "Signed in "
text s_new_team,        "New team"
text s_no_teams,        "You're not on a team yet."
text s_open,            "Open"
text s_current,         "Current"
text s_leave,           "Leave"
text s_one_team,        " team"
text s_open_issue,      " open issue"
text st_password_changed, "password changed. Your other sessions were logged out"
text st_account_deleted, "your account was deleted"

align 8
account_tabs:   NAME s_tab_profile      ; by ACC_*
                NAME s_tab_security
                NAME s_tab_teams

section .bss
delete_pass_buf: resb PASSWORD_MAX
password_busy:  resb 1                  ; a change was sent, waiting for the answer
deleting:       resb 1                  ; MSG_DELETE_ACCOUNT was sent, waiting for the answer
account_loaded: resb 1                  ; a MSG_ACCOUNT came since we logged in
alignb 4
account_tab:    resd 1                  ; ACC_*
account_scroll: resd 1
account_armed:  resd 1                  ; the team whose Leave was clicked once, -1 for
                                        ; Delete account, 0 for neither
joined:         resd 1
session_count:  resd 1
session_rows:   resb ACCOUNT_SESSIONS * AS_SIZE
team_size_count: resd 1
team_sizes:     resb USER_TEAM_MAX * AT_SIZE

section .text

; Opens the dialog on a tab. edi = ACC_*
open_account:
    push rbx
    mov ebx, edi
    mov byte [menu_open], 0
    mov byte [modal], M_ACCOUNT
    call clear_password_fields
    mov edi, ebx
    call click_account_tab
    pop rbx
    ret

; Switches tab, at its top, and asks for fresh numbers. edi = ACC_*
click_account_tab:
    push rbx
    mov [account_tab], edi
    xor eax, eax
    mov [account_scroll], eax
    mov [account_armed], eax
    mov ebx, F_NONE
    mov eax, F_OLD_PASS
    cmp edi, ACC_SECURITY
    cmove ebx, eax
    call request_account
    mov edi, ebx
    call set_focus
    pop rbx
    ret

; Asks for MSG_ACCOUNT, if we can right now.
request_account:
    sub rsp, 8
    call can_send
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_ACCOUNT_INFO
    call wr_u8
    call send_built
.done:
    add rsp, 8
    ret

; MSG_ACCOUNT: when we joined, our sessions and our teams' sizes.
on_account:
    push rbx
    push r12
    push r13
    call rd_u32
    mov [joined], eax
    call rd_u8
    mov r12d, eax
    cmp r12d, ACCOUNT_SESSIONS
    ja .bad
    lea rbx, [session_rows]
    xor r13d, r13d
.session:
    cmp r13d, r12d
    jae .sessions_read
    call rd_u32
    mov [rbx + AS_ID], eax
    call rd_u32
    mov [rbx + AS_SIGNED_IN], eax
    call rd_u32
    mov [rbx + AS_SEEN], eax
    call rd_u8
    mov [rbx + AS_FLAGS], al
    add rbx, AS_SIZE
    inc r13d
    jmp .session
.sessions_read:
    mov [session_count], r12d
    call rd_u8
    mov r12d, eax
    cmp r12d, USER_TEAM_MAX
    ja .bad
    lea rbx, [team_sizes]
    xor r13d, r13d
.team:
    cmp r13d, r12d
    jae .teams_read
    call rd_u32
    mov [rbx + AT_TEAM], eax
    call rd_u8
    mov [rbx + AT_MEMBERS], al
    call rd_u16
    mov [rbx + AT_OPEN], ax
    add rbx, AT_SIZE
    inc r13d
    jmp .team
.teams_read:
    mov [team_size_count], r12d
    mov byte [account_loaded], 1
    jmp .done
.bad:
    mov byte [rd_bad], 1
.done:
    pop r13
    pop r12
    pop rbx
    ret

; edi = team -> rax = its size as MSG_ACCOUNT gave it, or 0
find_team_size:
    lea rax, [team_sizes]
    mov ecx, [team_size_count]
.row:
    test ecx, ecx
    jz .none
    cmp [rax + AT_TEAM], edi
    je .done
    add rax, AT_SIZE
    dec ecx
    jmp .row
.none:
    xor eax, eax
.done:
    ret

; Wipes the password fields, which matters more here than anywhere else.
clear_password_fields:
    sub rsp, 8
    mov edi, F_OLD_PASS
    call field_clear
    mov edi, F_NEW_PASS
    call field_clear
    mov edi, F_DELETE_PASS
    call field_clear
    add rsp, 8
    ret

; No answer is coming to a password change or a deletion: an ERROR came, or
; the connection went.
account_idle:
    mov byte [password_busy], 0
    mov byte [deleting], 0
    ret

; We were logged out. If it was our account being deleted, the login screen says so.
account_logged_out:
    cmp byte [deleting], 0
    je .done
    mov byte [deleting], 0
    mov byte [account_loaded], 0
    lea rsi, [st_account_deleted]
    mov edx, st_account_deleted_len
    jmp set_auth_msg
.done:
    mov byte [account_loaded], 0
    ret

; Enter in either password box, or Change password: moves on to the new
; password, or sends both.
submit_password:
    push rbx
    cmp byte [password_busy], 0
    jne .done
    mov edi, F_OLD_PASS
    call field_addr
    mov rbx, rax
    mov edi, F_OLD_PASS
    cmp dword [rbx + FD_LEN], 0
    je .focus
    mov edi, F_NEW_PASS
    call field_addr
    mov edi, F_NEW_PASS
    cmp dword [rax + FD_LEN], 0
    je .focus
    mov rcx, [rax + FD_BUF]
    mov r8d, [rax + FD_LEN]
    mov rsi, [rbx + FD_BUF]
    mov edx, [rbx + FD_LEN]
    call sync_change_password
    jmp .done
.focus:
    call set_focus
.done:
    pop rbx
    ret

; rsi = current password, edx = length, rcx = new password, r8d = length
sync_change_password:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rsi
    mov r12d, edx
    mov r13, rcx
    mov r14d, r8d
    call can_send
    test eax, eax
    jz .offline
    lea rdi, [out_msg]
    mov esi, MSG_CHANGE_PASSWORD
    call wr_u8
    mov rsi, rbx
    mov edx, r12d
    call wr_str
    mov rsi, r13
    mov edx, r14d
    call wr_str
    call send_built
    lea rdi, [out_msg]                      ; it held both passwords
    mov esi, 512
    call wipe
    mov byte [password_busy], 1
    mov byte [need_redraw], 1
    jmp .done
.offline:
    lea rsi, [st_no_server]
    mov edx, st_no_server_len
    call set_status
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; MSG_PASSWORD_CHANGED: empties the boxes and says so. The other sessions
; are gone, so the list is asked for again.
on_password_changed:
    sub rsp, 8
    mov byte [password_busy], 0
    cmp byte [modal], M_ACCOUNT
    jne .said
    call clear_password_fields
    mov edi, F_NONE
    call set_focus
    call request_account
.said:
    lea rsi, [st_password_changed]
    mov edx, st_password_changed_len
    call set_status
    add rsp, 8
    ret

; Log out on another session, or everywhere else. edi = session, -1 for every other one
click_end_session:
    push rbx
    mov ebx, edi
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_END_SESSION
    call wr_u8
    mov esi, ebx
    call wr_u32
    call send_built
.done:
    pop rbx
    ret

; Delete account: needs the password typed, asks with a first click, sends
; with the second.
click_delete_account:
    push rbx
    cmp byte [deleting], 0
    jne .done
    mov edi, F_DELETE_PASS
    call field_addr
    mov rbx, rax
    cmp dword [rbx + FD_LEN], 0
    je .focus
    cmp dword [account_armed], -1
    je .send
    mov dword [account_armed], -1
    jmp .done
.send:
    mov dword [account_armed], 0
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_DELETE_ACCOUNT
    call wr_u8
    mov rsi, [rbx + FD_BUF]
    mov edx, [rbx + FD_LEN]
    call wr_str
    call send_built
    lea rdi, [out_msg]                      ; it held the password
    mov esi, 256
    call wipe
    mov byte [deleting], 1
    jmp .done
.focus:
    mov edi, F_DELETE_PASS
    call set_focus
.done:
    pop rbx
    ret

; Leave on a team in the dialog. The first click asks. edi = team id
click_leave_team:
    push rbx
    mov ebx, edi
    cmp [account_armed], edi
    je .send
    mov [account_armed], edi
    jmp .done
.send:
    mov dword [account_armed], 0
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_REMOVE_MEMBER
    call wr_u8
    mov esi, ebx
    call wr_u32
    mov esi, [my_id]
    call wr_u32
    xor edx, edx                            ; no reason
    call wr_str
    call send_built
.done:
    pop rbx
    ret

; Settings on a team in the dialog: switches to it and opens its settings. edi = team id
click_team_settings:
    sub rsp, 8
    cmp edi, [current_team]
    je .open
    call select_team
.open:
    mov edi, F_NONE
    call open_team_settings
    add rsp, 8
    ret

; Open on a team in the dialog: switches to it and closes the dialog. edi = team id
click_go_team:
    sub rsp, 8
    call select_team
    call close_modal
    add rsp, 8
    ret

; A link ending at a right edge, dim until hovered. edi = right edge,
; esi = baseline, rdx = text, ecx = length, r8d = action, r9d = arg
; -> eax = its left x
right_link:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    mov edi, r8d
    mov esi, r9d
    push r8
    push r9
    call hovering
    mov r8d, C_DIM
    mov ecx, C_TEXT
    test eax, eax
    cmovnz r8d, ecx
    mov edi, ebx
    mov esi, r12d
    mov rdx, r13
    mov ecx, r14d
    call draw_link
    mov r15d, eax
    mov edi, eax
    mov esi, r12d
    pop r9
    pop r8
    call add_link_hit
    mov eax, r15d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; A team's square with the first letter of its name, so a renamed team's
; badge follows it. edi = x, esi = y, edx = size, rcx = team row
draw_team_badge:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14, rcx
    mov ecx, edx
    mov r8d, C_ACCENT
    mov r9d, 5
    call fill_rrect
    movzx eax, byte [r14 + CO_NAME]
    lea ecx, [eax - 'a']
    cmp ecx, 25
    ja .upper
    sub eax, 32
.upper:
    mov [rsp], al
    mov rdi, rsp
    mov esi, 1
    mov edx, ST_SMALL
    call text_width
    mov edi, r13d
    sub edi, eax
    sar edi, 1
    add edi, ebx
    mov esi, r13d
    shr esi, 1
    lea esi, [r12d + esi + 4]               ; half the cap height at 12px
    mov rdx, rsp
    mov ecx, 1
    mov r8d, INK(0xffffff, ST_SMALL)
    call draw_text
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi = cursor, esi = count, rdx = noun with its leading space, ecx = its
; length -> rdi advanced past "1 member" or "3 members"
put_count:
    push rbx
    push r12
    push r13
    mov ebx, esi
    mov r12, rdx
    mov r13d, ecx
    call put_u32
    mov rsi, r12
    mov edx, r13d
    call put_mem
    cmp ebx, 1
    je .done
    mov byte [rdi], 's'
    inc rdi
.done:
    pop r13
    pop r12
    pop rbx
    ret
