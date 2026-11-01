; The screens: login, the sidebar, the list and board, the issue detail
; view and the two modals.

section .rodata
text s_new_issue,       "New issue"
text s_my_issues,       "My issues"
text s_your_teams,      "Your teams"
text s_issues,          "Issues"
text s_active,          "Active"
text s_projects,        "Projects"
text s_members,         "Members"
text s_remove,          "Remove"
text s_leave,           "Leave"
text s_log_out,         "Log out"
text s_all_issues,      "All issues"
text s_active_issues,   "Active issues"
text s_backlog_view,    "Backlog"
text s_filter,          "Filter"
text s_list,            "List"
text s_board,           "Board"
text s_issue_count,     " issues"
text s_no_issues,       "No issues here"
text s_press_c,         "Press C to create one, or Ctrl+K for everything else."
text s_loading,         "Loading..."
text s_no_team,         "Create a team to start tracking issues."
text s_create_team,     "Create team"
text s_create_issue,    "Create issue"
text s_ctrl_enter,      "Ctrl+Enter to create"
text s_activity,        "Activity"
text s_created_issue,   " created the issue "
text s_enter_send,      "Enter to send, Shift+Enter for a new line"
text s_status,          "Status"
text s_priority,        "Priority"
text s_assignee,        "Assignee"
text s_project,         "Project"
text s_labels,          "Labels"
text s_label_count,     " labels"
text s_created,         "Created "
text s_updated,         "Updated "
text s_delete_issue,    "Delete issue"
text s_new_team_title,  "Create a team"
text s_team_name,       "Name"
text s_team_key,        "Identifier, used in issue IDs like ENG-12"
text s_label_is,        "Label: "
text s_project_is,      "Project: "
text s_unfilter,        "  x"
text s_close,           "x"
text s_owner,           "owner"
text s_connected_to,    "Connected to "
text s_connecting_to,   "Connecting to "
text s_offline,         "Offline, retrying in "
text s_seconds,         "s"
text s_saved,           "All changes saved"
text s_syncing,         "Syncing "
text s_changes,         " changes"
text s_change,          " change"
prop_names:     NAME s_status
                NAME s_priority
                NAME s_assignee
                NAME s_project
                NAME s_labels
view_names:     NAME s_all_issues
                NAME s_active_issues
                NAME s_backlog_view
                NAME s_my_issues

section .bss
alignb 8
pi_item:        resb MI_SIZE            ; a property shown as a menu item would be
side_selected:  resb 1

section .text

; --- shared bits ---

; Writes the connection and sync state for the status line.
; rdi = out -> rdi advanced, eax = 1 when everything is in sync
put_net_status:
    push rbx
    xor ebx, ebx
    mov al, [net_state]
    cmp al, NET_OPEN
    je .open
    cmp al, NET_OFF
    je .off
    lea rsi, [s_connecting_to]
    mov edx, s_connecting_to_len
    call put_mem
    mov rsi, [server_label]
    call put_cstr
    jmp .done
.off:
    lea rsi, [s_offline]
    mov edx, s_offline_len
    call put_mem
    push rdi
    call net_retry_in
    add eax, 999                            ; round up, so it never says 0s
    xor edx, edx
    mov ecx, 1000
    div ecx
    pop rdi
    mov esi, eax
    call put_u32
    lea rsi, [s_seconds]
    mov edx, s_seconds_len
    call put_mem
    jmp .done
.open:
    mov ebx, 1
    cmp byte [logged_in], 0
    je .connected
    mov eax, [pending_count]
    test eax, eax
    jz .saved
    xor ebx, ebx
    lea rsi, [s_syncing]
    mov edx, s_syncing_len
    call put_mem
    mov esi, [pending_count]
    call put_u32
    lea rsi, [s_changes]
    mov edx, s_changes_len
    cmp dword [pending_count], 1
    jne .plural
    lea rsi, [s_change]
    mov edx, s_change_len
.plural:
    call put_mem
    jmp .done
.saved:
    lea rsi, [s_saved]
    mov edx, s_saved_len
    call put_mem
    jmp .done
.connected:
    lea rsi, [s_connected_to]
    mov edx, s_connected_to_len
    call put_mem
    mov rsi, [server_label]
    call put_cstr
.done:
    mov eax, ebx
    pop rbx
    ret

; The connection line with a colored dot. edi = x, esi = baseline, edx = width
draw_net_status:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    lea rdi, [scratch]
    call put_net_status
    push rdi
    push rax
    mov ecx, 0xf2c94c
    test eax, eax
    mov eax, C_ONLINE
    cmovnz ecx, eax
    cmp byte [net_state], NET_OFF
    mov eax, C_DANGER
    cmove ecx, eax
    lea edi, [ebx * 4 + 12]
    lea esi, [r12d * 4 - 14]
    mov edx, 12
    call aa_disc
    pop rax
    pop rcx
    lea rdx, [scratch]
    sub rcx, rdx
    lea edi, [ebx + 12]
    mov esi, r12d
    mov r8d, INK(C_DIM, ST_SMALL)
    lea r9d, [r13d - 12]
    call draw_text_fit
    pop r13
    pop r12
    pop rbx
    ret

; Centered text. edi = left, esi = width, edx = baseline, rcx = text, r8d = length, r9d = ink
draw_centered:
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
    push r9
    mov rdi, r14
    mov esi, r15d
    mov edx, r9d
    shr edx, 24
    call text_width
    mov edi, r12d
    sub edi, eax
    sar edi, 1
    add edi, ebx
    mov esi, r13d
    mov rdx, r14
    mov ecx, r15d
    mov r8d, [rsp]
    call draw_text
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; A box around a single-line field, focused or not, with its hit region.
; edi = field, esi = x, edx = y, ecx = width. 36px tall.
draw_field_box:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    call field_focused
    mov r8d, C_LINE
    mov ecx, C_ACCENT
    test eax, eax
    cmovnz r8d, ecx
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, 36
    mov r9d, C_PANEL
    mov r10d, 6
    call outline_rrect
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, 36
    mov r8d, A_FIELD
    mov r9d, ebx
    call add_hit
    mov edi, ebx
    lea esi, [r12d + 12]
    lea edx, [r13d + 23]
    lea ecx, [r14d - 24]
    call draw_field
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi = text, esi = length, edx = 1 if it has a dot -> eax = draw_chip's width
chip_width:
    push rdx
    mov edx, ST_SMALL
    call text_width
    pop rdx
    add eax, 18
    test edx, edx
    jz .done
    add eax, 14
.done:
    ret

; Works out how a property reads: fills pi_item with its text and icon.
; edi = MK_*, rsi = view issue, or 0 for the create draft
prop_info:
    push rbx
    push r12
    mov r12d, edi
    mov rbx, rsi
    mov dword [pi_item + MI_ICON], IC_DOT
    mov dword [pi_item + MI_ICON_ARG], C_FAINT
    mov eax, [new_status + r12 * 4]
    test rbx, rbx
    jz .have
    movzx eax, byte [rbx + CI_STATUS]
    cmp r12d, MK_STATUS
    je .have
    movzx eax, byte [rbx + CI_PRIORITY]
    cmp r12d, MK_PRIORITY
    je .have
    mov eax, [rbx + CI_ASSIGNEE]
    cmp r12d, MK_ASSIGNEE
    je .have
    movzx eax, byte [rbx + CI_PROJECT]
    cmp r12d, MK_PROJECT
    je .have
    movzx eax, word [rbx + CI_LABELS]
.have:
    mov ebx, eax
    cmp r12d, MK_STATUS
    je .status
    cmp r12d, MK_PRIORITY
    je .priority
    cmp r12d, MK_ASSIGNEE
    je .assignee
    cmp r12d, MK_PROJECT
    je .project
    test ebx, ebx
    jz .no_labels
    bsf ecx, ebx
    imul ecx, ecx, LB_SIZE
    mov eax, [view_labels + rcx + LB_COLOR]
    mov [pi_item + MI_ICON_ARG], eax
    popcnt eax, ebx
    cmp eax, 1
    jne .several
    lea rsi, [view_labels + rcx + LB_NAME]
    movzx edx, byte [view_labels + rcx + LB_NAME_LEN]
    jmp .text
.several:
    lea rdi, [scratch + 256]
    mov esi, eax
    call put_u32
    lea rsi, [s_label_count]
    mov edx, s_label_count_len
    call put_mem
    lea rsi, [scratch + 256]
    mov rdx, rdi
    sub rdx, rsi
    jmp .text
.no_labels:
    lea rsi, [s_labels]
    mov edx, s_labels_len
    jmp .text
.status:
    mov dword [pi_item + MI_ICON], IC_STATUS
    mov [pi_item + MI_ICON_ARG], ebx
    mov edi, ebx
    call status_name
    jmp .text
.priority:
    mov dword [pi_item + MI_ICON], IC_PRIORITY
    mov [pi_item + MI_ICON_ARG], ebx
    mov edi, ebx
    call priority_name
    jmp .text
.assignee:
    mov dword [pi_item + MI_ICON], IC_AVATAR
    mov [pi_item + MI_ICON_ARG], ebx
    lea rsi, [s_no_assignee]
    mov edx, s_no_assignee_len
    test ebx, ebx
    jz .text
    mov edi, ebx
    call user_name
    jmp .text
.project:
    lea rsi, [s_no_project]
    mov edx, s_no_project_len
    test ebx, ebx
    jz .text
    lea eax, [ebx - 1]
    imul eax, eax, PJ_SIZE
    lea rsi, [view_projects + rax + LB_NAME]
    movzx edx, byte [view_projects + rax + LB_NAME_LEN]
    mov eax, [view_projects + rax + LB_COLOR]
    mov [pi_item + MI_ICON_ARG], eax
.text:
    mov [pi_item + MI_TEXT], rsi
    mov [pi_item + MI_LEN], edx
    pop r12
    pop rbx
    ret

; A property's icon and text. edi = x, esi = row top (28px rows), edx = width
draw_prop:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    lea rdi, [pi_item]
    mov esi, ebx
    lea edx, [r12d + 7]
    call draw_item_icon
    lea edi, [ebx + 24]
    lea esi, [r12d + 19]
    mov rdx, [pi_item + MI_TEXT]
    mov ecx, [pi_item + MI_LEN]
    mov r8d, INK(C_TEXT, ST_BODY)
    lea r9d, [r13d - 24]
    call draw_text_fit
    pop r13
    pop r12
    pop rbx
    ret

; --- login ---

draw_login:
    push rbx
    push r12
    push r13
    mov ebx, [win_w]                        ; column x
    sub ebx, 340
    sar ebx, 1
    mov r12d, [win_h]                       ; column top
    shr r12d, 1
    sub r12d, 200
    mov eax, 30
    cmp r12d, eax
    cmovl r12d, eax

    lea edi, [ebx]                          ; the mark
    mov esi, r12d
    mov edx, 40
    mov ecx, 40
    mov r8d, C_ACCENT
    mov r9d, 10
    call fill_rrect
    lea edi, [ebx * 4 + 80]                 ; a big white "in progress" mark
    lea esi, [r12d * 4 + 80]
    mov edx, 46
    mov ecx, 0xffffff
    mov r8d, 10
    call aa_ring
    lea edi, [ebx * 4 + 80]
    lea esi, [r12d * 4 + 80]
    mov edx, 26
    mov ecx, 0xffffff
    call aa_half_disc
    lea edi, [ebx]
    lea esi, [r12d + 84]
    lea rdx, [s_app]
    mov ecx, s_app_len
    mov r8d, INK(C_TEXT, ST_LARGE)
    call draw_text
    mov edi, ebx
    lea esi, [r12d + 112]
    lea rdx, [s_subtitle]
    mov ecx, s_subtitle_len
    mov r8d, INK(C_DIM, ST_BODY)
    mov r9d, [win_w]
    sub r9d, ebx
    sub r9d, 16
    call draw_text_fit

    mov edi, F_USER
    mov esi, ebx
    lea edx, [r12d + 140]
    mov ecx, 340
    call draw_field_box
    mov edi, F_PASS
    mov esi, ebx
    lea edx, [r12d + 186]
    mov ecx, 340
    call draw_field_box
    mov edi, ebx
    lea esi, [r12d + 240]
    lea rdx, [s_log_in]
    mov ecx, s_log_in_len
    mov r8d, A_LOGIN
    mov r9d, 1
    call draw_button
    lea edi, [ebx + eax + 8]
    lea esi, [r12d + 240]
    lea rdx, [s_sign_up]
    mov ecx, s_sign_up_len
    mov r8d, A_SIGNUP
    xor r9d, r9d
    call draw_button

    mov edi, ebx
    lea esi, [r12d + 304]
    mov r9d, 340
    cmp byte [auth_busy], 0
    jne .busy
    cmp dword [auth_msg_len], 0
    je .footer
    lea rdx, [auth_msg]
    mov ecx, [auth_msg_len]
    mov r8d, INK(C_DANGER, ST_BODY)
    call draw_text_fit
    jmp .footer
.busy:
    lea rdx, [s_checking]
    mov ecx, s_checking_len
    mov r8d, INK(C_DIM, ST_BODY)
    call draw_text_fit
.footer:
    mov edi, 20
    mov esi, [win_h]
    sub esi, 20
    mov edx, [win_w]
    sub edx, 40
    call draw_net_status
    pop r13
    pop r12
    pop rbx
    ret

; --- sidebar ---

; One sidebar row: highlight and hit region. side_selected marks the current one.
; edi = y, esi = action, edx = arg. 28px tall.
side_row:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r8d, C_SELECT
    cmp byte [side_selected], 0
    jne .fill
    mov edi, r12d
    mov esi, r13d
    call hovering
    test eax, eax
    jz .hit
    mov r8d, C_HOVER
.fill:
    mov edi, 8
    mov esi, ebx
    mov edx, SIDEBAR_W - 16
    mov ecx, 28
    mov r9d, 6
    call fill_rrect
.hit:
    mov edi, 8
    mov esi, ebx
    mov edx, SIDEBAR_W - 16
    mov ecx, 28
    mov r8d, r12d
    mov r9d, r13d
    call add_hit
    mov byte [side_selected], 0
    pop r13
    pop r12
    pop rbx
    ret

; Sidebar row text. edi = x, esi = row y, rdx = text, ecx = length
side_text:
    add esi, 19
    mov r8d, INK(C_TEXT, ST_BODY)
    mov r9d, SIDEBAR_W - 24
    sub r9d, edi
    jmp draw_text_fit

; A section heading. edi = y, rsi = text, edx = length
side_heading:
    mov ecx, edx
    mov rdx, rsi
    lea esi, [edi + 18]
    mov edi, 18
    mov r8d, INK(C_FAINT, ST_SMALL)
    jmp draw_text

draw_sidebar:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    xor edi, edi
    xor esi, esi
    mov edx, SIDEBAR_W
    mov ecx, [win_h]
    sub ecx, 64
    call set_clip

    mov edi, 16                             ; who's logged in
    mov esi, 14
    mov edx, 20
    mov ecx, [my_id]
    lea r8, [my_name]
    call draw_avatar
    mov edi, 44
    mov esi, 29
    lea rdx, [my_name]
    mov ecx, [my_name_len]
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    mov r9d, SIDEBAR_W - 60
    call draw_text_fit

    mov edi, A_NEW_ISSUE                    ; the new issue button
    mov esi, -1
    call hovering
    mov r9d, C_RAISED
    mov ecx, C_SELECT
    test eax, eax
    cmovnz r9d, ecx
    mov edi, 10
    mov esi, 48
    mov edx, SIDEBAR_W - 20
    mov ecx, 32
    mov r8d, C_LINE
    mov r10d, 7
    call outline_rrect
    mov edi, 10
    mov esi, 48
    mov edx, SIDEBAR_W - 20
    mov ecx, 32
    mov r8d, A_NEW_ISSUE
    mov r9d, -1
    call add_hit
    mov dword [pi_item + MI_ICON], IC_PLUS
    lea rdi, [pi_item]
    mov esi, 22
    mov edx, 57
    call draw_item_icon
    mov edi, 44
    mov esi, 69
    lea rdx, [s_new_issue]
    mov ecx, s_new_issue_len
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    mov edi, SIDEBAR_W - 40
    mov esi, 55
    mov edx, 'C'
    call draw_keycap

    mov ebx, 92                             ; y
    cmp dword [current_team], 0
    je .teams
    cmp dword [view_mode], V_MINE
    sete byte [side_selected]
    mov edi, ebx
    mov esi, A_VIEW
    mov edx, V_MINE
    call side_row
    mov edi, 4 * 25                         ; an avatar-sized ring for "me"
    lea esi, [ebx * 4 + 56]
    mov edx, 24
    mov ecx, C_DIM
    mov r8d, 6
    call aa_ring
    mov edi, 40
    mov esi, ebx
    lea rdx, [s_my_issues]
    mov ecx, s_my_issues_len
    call side_text
    add ebx, 40

.teams:
    mov edi, ebx
    lea rsi, [s_your_teams]
    mov edx, s_your_teams_len
    call side_heading
    mov edi, A_NEW_TEAM                     ; "+" to make another
    xor esi, esi
    call hovering
    mov r8d, C_FAINT
    mov ecx, C_TEXT
    test eax, eax
    cmovnz r8d, ecx
    mov [rsp], r8d
    mov edi, SIDEBAR_W - 30
    lea esi, [ebx + 7]
    mov edx, 2
    mov ecx, 10
    call fill_rect
    mov edi, SIDEBAR_W - 34
    lea esi, [ebx + 11]
    mov edx, 10
    mov ecx, 2
    mov r8d, [rsp]
    call fill_rect
    mov edi, SIDEBAR_W - 40
    mov esi, ebx
    mov edx, 24
    mov ecx, 24
    mov r8d, A_NEW_TEAM
    xor r9d, r9d
    call add_hit
    add ebx, 28

    lea r12, [teams]
    mov r13d, [team_count]
.team:
    test r13d, r13d
    jz .projects
    mov edi, ebx
    mov esi, A_TEAM
    mov edx, [r12 + CO_ID]
    call side_row
    mov edi, 16                             ; the team's badge
    lea esi, [ebx + 5]
    mov edx, 18
    mov ecx, 18
    mov r8d, C_ACCENT
    mov r9d, 5
    call fill_rrect
    lea rdx, [r12 + CO_KEY]
    mov edi, 20
    lea esi, [ebx + 18]
    mov ecx, 1
    mov r8d, INK(0xffffff, ST_SMALL)
    call draw_text
    mov edi, 44
    mov esi, ebx
    lea rdx, [r12 + CO_NAME]
    movzx ecx, byte [r12 + CO_NAME_LEN]
    call side_text
    add ebx, 30
    mov eax, [r12 + CO_ID]
    cmp eax, [current_team]
    jne .next_team
    ; The current team's views, indented.
    xor r14d, r14d
.team_view:
    cmp r14d, V_MINE
    jae .next_team
    cmp [view_mode], r14d
    jne .not_current
    cmp dword [filter_project], 0
    sete byte [side_selected]
.not_current:
    mov edi, ebx
    mov esi, A_VIEW
    mov edx, r14d
    call side_row
    lea rdi, [s_issues]
    mov esi, s_issues_len
    cmp r14d, V_ALL
    je .view_text
    lea rdi, [s_active]
    mov esi, s_active_len
    cmp r14d, V_ACTIVE
    je .view_text
    lea rdi, [s_backlog]
    mov esi, s_backlog_len
.view_text:
    mov rdx, rdi
    mov ecx, esi
    mov edi, 52
    mov esi, ebx
    call side_text
    add ebx, 30
    inc r14d
    jmp .team_view
.next_team:
    add r12, CO_SIZE
    dec r13d
    jmp .team

.projects:
    cmp dword [current_team], 0
    je .bottom
    add ebx, 12
    lea r12, [view_projects]
    mov r13d, 1
    mov r14d, ebx                           ; heading goes here if there are any
    add ebx, 28
.project:
    cmp r13d, PROJECT_SLOTS
    ja .projects_done
    cmp byte [r12 + LB_NAME_LEN], 0
    je .next_project
    cmp [filter_project], r13d
    sete byte [side_selected]
    mov edi, ebx
    mov esi, A_PROJECT
    mov edx, r13d
    call side_row
    mov edi, 4 * 25
    lea esi, [ebx * 4 + 56]
    mov edx, 18
    mov ecx, [r12 + LB_COLOR]
    call aa_disc
    mov edi, 44
    mov esi, ebx
    lea rdx, [r12 + LB_NAME]
    movzx ecx, byte [r12 + LB_NAME_LEN]
    call side_text
    add ebx, 30
.next_project:
    add r12, PJ_SIZE
    inc r13d
    jmp .project
.projects_done:
    lea eax, [r14d + 28]
    cmp ebx, eax
    jne .project_heading
    mov ebx, r14d                           ; no projects, no heading
    jmp .members
.project_heading:
    mov edi, r14d
    lea rsi, [s_projects]
    mov edx, s_projects_len
    call side_heading

.members:
    add ebx, 12
    mov edi, ebx
    lea rsi, [s_members]
    mov edx, s_members_len
    call side_heading
    add ebx, 28
    call current_team_row
    xor ebp, ebp                            ; we own this team
    test rax, rax
    jz .member_rows
    cmp byte [rax + CO_ROLE], ROLE_OWNER
    sete bpl
.member_rows:
    lea r12, [members]
    mov r13d, [member_count]
.member:
    test r13d, r13d
    jz .invite
    mov edi, 16
    lea esi, [ebx + 5]
    mov edx, 18
    mov ecx, [r12 + CM_ID]
    lea r8, [r12 + CM_NAME]
    call draw_avatar
    mov edi, 4 * 31                         ; online dot on the avatar's corner
    lea esi, [ebx * 4 + 4 * 21]
    mov edx, 14
    mov ecx, C_BG
    call aa_disc
    mov ecx, C_ONLINE
    cmp byte [r12 + CM_ONLINE], 0
    jne .dot
    mov ecx, C_FAINT
.dot:
    mov edi, 4 * 31
    lea esi, [ebx * 4 + 4 * 21]
    mov edx, 9
    call aa_disc
    mov edi, 44
    lea esi, [ebx + 19]
    lea rdx, [r12 + CM_NAME]
    movzx ecx, byte [r12 + CM_NAME_LEN]
    mov r8d, INK(C_TEXT, ST_BODY)
    mov r9d, SIDEBAR_W - 110
    call draw_text_fit
    cmp byte [r12 + CM_ROLE], ROLE_OWNER
    jne .member_action
    mov edi, SIDEBAR_W - 60
    lea esi, [ebx + 19]
    lea rdx, [s_owner]
    mov ecx, s_owner_len
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_text
    jmp .next_member
.member_action:
    ; Owners can remove others, and anyone else can leave.
    mov eax, [r12 + CM_ID]
    cmp eax, [my_id]
    je .leave
    test ebp, ebp
    jz .next_member
    lea r14, [s_remove]
    mov r15d, s_remove_len
    mov r8d, A_REMOVE
    mov r9d, eax
    jmp .action_link
.leave:
    test ebp, ebp
    jnz .next_member
    lea r14, [s_leave]
    mov r15d, s_leave_len
    mov r8d, A_LEAVE
    xor r9d, r9d
.action_link:
    push r8
    push r9
    mov edi, SIDEBAR_W - 64
    mov esi, ebx
    mov edx, 56
    mov ecx, 28
    call add_hit
    pop rsi
    pop rdi
    call hovering
    mov r8d, INK(C_FAINT, ST_SMALL)
    mov ecx, INK(C_DANGER, ST_SMALL)
    test eax, eax
    cmovnz r8d, ecx
    mov edi, SIDEBAR_W - 60
    lea esi, [ebx + 19]
    mov rdx, r14
    mov ecx, r15d
    call draw_text
.next_member:
    add ebx, 28
    add r12, CM_SIZE
    dec r13d
    jmp .member
.invite:
    test ebp, ebp
    jz .bottom
    add ebx, 4
    mov edi, F_MEMBER
    mov esi, 12
    mov edx, ebx
    mov ecx, SIDEBAR_W - 24
    call draw_field_box

.bottom:
    call reset_clip
    mov edi, 8
    mov esi, [win_h]
    sub esi, 60
    mov edx, SIDEBAR_W - 16
    mov ecx, 1
    mov r8d, C_LINE
    call fill_rect
    mov edi, A_LOGOUT
    xor esi, esi
    call hovering
    mov r8d, INK(C_DIM, ST_SMALL)
    mov ecx, INK(C_TEXT, ST_SMALL)
    test eax, eax
    cmovnz r8d, ecx
    mov edi, 16
    mov esi, [win_h]
    sub esi, 40
    lea rdx, [s_log_out]
    mov ecx, s_log_out_len
    call draw_text
    mov edi, 8
    mov esi, [win_h]
    sub esi, 56
    mov edx, 80
    mov ecx, 24
    mov r8d, A_LOGOUT
    xor r9d, r9d
    call add_hit
    mov edi, 16
    mov esi, [win_h]
    sub esi, 16
    mov edx, SIDEBAR_W - 24
    call draw_net_status
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; --- the main panel ---

; The panel's header: where we are, and the layout switch.
; edi = x, esi = y, edx = w
draw_header:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    call current_team_row
    test rax, rax
    jz .done
    mov r14, rax
    lea edi, [ebx + 20]
    lea esi, [r12d + 27]
    lea rdx, [r14 + CO_NAME]
    movzx ecx, byte [r14 + CO_NAME_LEN]
    mov r8d, INK(C_DIM, ST_MEDIUM)
    call draw_text
    lea edi, [eax + 8]
    lea esi, [r12d + 27]
    mov byte [scratch], GLYPH_CHEVRON
    lea rdx, [scratch]
    mov ecx, 1
    mov r8d, INK(C_FAINT, ST_MEDIUM)
    call draw_text
    lea edi, [eax + 8]
    mov [rsp], edi
    cmp dword [detail_issue], 0
    jne .issue_id
    mov eax, [view_mode]
    shl eax, 4
    mov rdx, [view_names + rax]
    mov ecx, [view_names + rax + 8]
    cmp dword [filter_project], 0
    je .crumb
    mov eax, [filter_project]               ; a project's issues: its name instead
    dec eax
    imul eax, eax, PJ_SIZE
    lea rdx, [view_projects + rax + LB_NAME]
    movzx ecx, byte [view_projects + rax + LB_NAME_LEN]
    jmp .crumb
.issue_id:
    mov edi, [detail_issue]
    call find_view_issue
    test rax, rax
    jz .done
    lea rdi, [scratch]
    mov rsi, rax
    call put_issue_id
    lea rdx, [scratch]
    mov rcx, rdi
    sub rcx, rdx
.crumb:
    mov edi, [rsp]
    lea esi, [r12d + 27]
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    cmp dword [detail_issue], 0
    jne .close

    ; List and board, as a two-part switch at the right.
    lea r14d, [ebx + r13d - 132]
    mov edi, r14d
    lea esi, [r12d + 8]
    mov edx, 116
    mov ecx, 28
    mov r8d, C_LINE
    mov r9d, C_PANEL
    mov r10d, 6
    call outline_rrect
    movzx eax, byte [board]
    imul eax, eax, 57
    lea edi, [r14d + eax + 2]
    lea esi, [r12d + 10]
    mov edx, 55
    mov ecx, 24
    mov r8d, C_SELECT
    mov r9d, 5
    call fill_rrect
    mov edi, r14d
    lea esi, [r12d + 8]
    mov edx, 58
    mov ecx, 28
    mov r8d, A_LAYOUT
    xor r9d, r9d
    call add_hit
    lea edi, [r14d + 58]
    lea esi, [r12d + 8]
    mov edx, 58
    mov ecx, 28
    mov r8d, A_LAYOUT
    mov r9d, 1
    call add_hit
    mov edi, r14d
    mov esi, 58
    mov edx, r12d
    add edx, 27
    lea rcx, [s_list]
    mov r8d, s_list_len
    mov r9d, INK(C_TEXT, ST_SMALL)
    call draw_centered
    lea edi, [r14d + 58]
    mov esi, 58
    lea edx, [r12d + 27]
    lea rcx, [s_board]
    mov r8d, s_board_len
    mov r9d, INK(C_TEXT, ST_SMALL)
    call draw_centered
    jmp .done
.close:
    lea r14d, [ebx + r13d - 44]
    mov edi, A_CLOSE
    xor esi, esi
    call hovering
    test eax, eax
    jz .close_hit
    mov edi, r14d
    lea esi, [r12d + 8]
    mov edx, 28
    mov ecx, 28
    mov r8d, C_HOVER
    mov r9d, 6
    call fill_rrect
.close_hit:
    mov edi, r14d
    lea esi, [r12d + 8]
    mov edx, 28
    mov ecx, 28
    mov r8d, A_CLOSE
    xor r9d, r9d
    call add_hit
    mov edi, r14d
    mov esi, 28
    lea edx, [r12d + 27]
    lea rcx, [s_close]
    mov r8d, s_close_len
    mov r9d, INK(C_DIM, ST_MEDIUM)
    call draw_centered
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; The filter bar: a Filter button, chips for active filters, the count.
; edi = x, esi = y, edx = w
draw_filters:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    lea edi, [ebx + 16]
    lea esi, [r12d + 8]
    lea rdx, [s_filter]
    mov ecx, s_filter_len
    mov r8d, -1
    call draw_chip
    mov r14d, eax
    lea edi, [ebx + 16]
    lea esi, [r12d + 8]
    mov edx, r14d
    mov ecx, 24
    mov r8d, A_FILTER
    xor r9d, r9d
    call add_hit
    lea r14d, [ebx + r14d + 24]             ; next chip x

    mov eax, [filter_label]
    test eax, eax
    js .project
    imul eax, eax, LB_SIZE
    lea r15, [view_labels + rax]
    lea rsi, [s_label_is]
    mov edx, s_label_is_len
    xor ecx, ecx
    call .filter_chip
.project:
    mov eax, [filter_project]
    test eax, eax
    jz .count
    dec eax
    imul eax, eax, PJ_SIZE
    lea r15, [view_projects + rax]
    lea rsi, [s_project_is]
    mov edx, s_project_is_len
    mov ecx, 1
    call .filter_chip
.count:
    lea rdi, [scratch]
    xor esi, esi
    xor ecx, ecx
.sum:
    add esi, [col_count + rcx * 4]
    inc ecx
    cmp ecx, STATUS_COUNT
    jb .sum
    push rsi
    call put_u32
    pop rcx
    lea rsi, [s_issue_count]
    mov edx, s_issue_count_len
    cmp ecx, 1
    jne .plural
    dec edx                                 ; "1 issue"
.plural:
    call put_mem
    lea rdx, [scratch]
    mov rcx, rdi
    sub rcx, rdx
    push rcx
    push rcx
    mov rdi, rdx
    mov esi, ecx
    mov edx, ST_SMALL
    call text_width
    pop rcx
    pop rcx
    lea edi, [ebx + r13d - 20]
    sub edi, eax
    lea esi, [r12d + 25]
    lea rdx, [scratch]
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_text
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; A removable filter chip at r14d. rsi = prefix, edx = its length,
; r15 = label or project slot, ecx = A_UNFILTER's arg. Advances r14d.
.filter_chip:
    push rcx
    lea rdi, [scratch]
    call put_mem
    lea rsi, [r15 + LB_NAME]
    movzx edx, byte [r15 + LB_NAME_LEN]
    call put_mem
    lea rsi, [s_unfilter]
    mov edx, s_unfilter_len
    call put_mem
    lea rdx, [scratch]
    mov rcx, rdi
    sub rcx, rdx
    mov edi, r14d
    lea esi, [r12d + 8]
    mov r8d, [r15 + LB_COLOR]
    call draw_chip
    mov edx, eax
    mov edi, r14d
    lea esi, [r12d + 8]
    mov ecx, 24
    mov r8d, A_UNFILTER
    pop r9
    lea r14d, [r14d + edx + 8]
    jmp add_hit

; The list view. edi = x, esi = top, edx = w, ecx = h
draw_list:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov [rsp], edi                          ; x
    mov [rsp + 4], esi                      ; top
    mov [rsp + 8], edx                      ; w
    mov [rsp + 12], ecx                     ; h
    call save_clip
    mov [rsp + 16], rax
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, edi
    add edx, [rsp + 8]
    mov ecx, esi
    add ecx, [rsp + 12]
    call clip_to

    ; Total height, so scrolling stops at the end.
    xor eax, eax
    xor ecx, ecx
.measure:
    cmp ecx, [row_count]
    jae .measured
    imul edx, ecx, RW_SIZE
    cmp qword [rows + rdx + RW_ISSUE], 0
    mov edx, ROW_H
    mov r8d, GROUP_H
    cmove edx, r8d
    add eax, edx
    inc ecx
    jmp .measure
.measured:
    mov [content_h], eax
    lea rdi, [scroll_y]
    mov esi, [rsp + 12]
    call clamp_scroll

    cmp dword [row_count], 0
    jne .rows
    lea rcx, [s_loading]
    mov r8d, s_loading_len
    cmp byte [loaded], 0
    je .note
    lea rcx, [s_no_issues]
    mov r8d, s_no_issues_len
.note:
    mov edi, [rsp]
    mov esi, [rsp + 8]
    mov edx, [rsp + 4]
    add edx, 80
    mov r9d, INK(C_DIM, ST_MEDIUM)
    call draw_centered
    cmp byte [loaded], 0
    je .done
    mov edi, [rsp]
    mov esi, [rsp + 8]
    mov edx, [rsp + 4]
    add edx, 104
    lea rcx, [s_press_c]
    mov r8d, s_press_c_len
    mov r9d, INK(C_FAINT, ST_BODY)
    call draw_centered
    jmp .done

.rows:
    mov r12d, [rsp + 4]
    sub r12d, [scroll_y]                    ; y of row 0
    xor ebx, ebx
.row:
    cmp ebx, [row_count]
    jae .done
    mov eax, [rsp + 4]
    add eax, [rsp + 12]
    cmp r12d, eax
    jge .done
    imul eax, ebx, RW_SIZE
    lea r13, [rows + rax]
    mov r14, [r13 + RW_ISSUE]
    test r14, r14
    jz .header
    lea eax, [r12d + ROW_H]
    cmp eax, [rsp + 4]
    jle .next_issue
    mov edi, [rsp]
    mov esi, r12d
    mov edx, [rsp + 8]
    mov rcx, r14
    call draw_row
.next_issue:
    add r12d, ROW_H
    inc ebx
    jmp .row
.header:
    lea eax, [r12d + GROUP_H]
    cmp eax, [rsp + 4]
    jle .next_header
    mov edi, [rsp]
    mov esi, r12d
    mov edx, [rsp + 8]
    mov ecx, [r13 + RW_STATUS]
    mov r8d, [r13 + RW_COUNT]
    call draw_group
.next_header:
    add r12d, GROUP_H
    inc ebx
    jmp .row
.done:
    mov rdi, [rsp + 16]
    call restore_clip
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; A status group's header, in the list or above a board column.
; edi = x, esi = y, edx = w, ecx = status, r8d = count
draw_group:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 16
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov ebp, r8d
    mov edi, ebx
    mov esi, r12d
    mov edx, r13d
    mov ecx, GROUP_H
    mov r8d, C_GROUP
    call fill_rect
    lea edi, [ebx + 20]
    lea esi, [r12d + 11]
    mov edx, r14d
    mov ecx, C_GROUP
    call draw_status_icon
    mov edi, r14d
    call status_name
    mov ecx, edx
    mov rdx, rsi
    lea edi, [ebx + 44]
    lea esi, [r12d + 23]
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    mov [rsp], eax
    lea rdi, [scratch]
    mov esi, ebp
    call put_u32
    mov rcx, rdi
    mov edi, [rsp]
    add edi, 10
    lea esi, [r12d + 23]
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_scratch

    lea ebx, [ebx + r13d - 40]              ; "+": a new issue in this status
    add r12d, 6
    mov edi, A_NEW_ISSUE
    mov esi, r14d
    call hovering
    test eax, eax
    jz .plus
    mov edi, ebx
    mov esi, r12d
    mov edx, 24
    mov ecx, 24
    mov r8d, C_SELECT
    mov r9d, 6
    call fill_rrect
.plus:
    mov dword [pi_item + MI_ICON], IC_PLUS
    lea rdi, [pi_item]
    lea esi, [ebx + 5]
    lea edx, [r12d + 5]
    call draw_item_icon
    mov edi, ebx
    mov esi, r12d
    mov edx, 24
    mov ecx, 24
    mov r8d, A_NEW_ISSUE
    mov r9d, r14d
    call add_hit
    add rsp, 16
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The background behind an issue row or card: selected, hovered or plain.
; rdi = view issue, esi = the plain color -> eax = color
issue_bg:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, [rdi + CI_ID]
    mov r12d, esi
    mov eax, C_SELECT
    cmp ebx, [sel_id]
    je .done
    mov edi, A_ISSUE
    mov esi, ebx
    call hovering
    test eax, eax
    mov eax, C_HOVER
    cmovz eax, r12d
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; One issue in the list. edi = x, esi = y, edx = w, rcx = view issue
draw_row:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov rbx, rcx
    mov rdi, rbx
    mov esi, C_PANEL
    call issue_bg
    mov [rsp + 8], eax                      ; background
    cmp eax, C_PANEL
    je .hit
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, ROW_H
    mov r8d, eax
    call fill_rect
.hit:
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, ROW_H
    mov r8d, A_ISSUE
    mov r9d, [rbx + CI_ID]
    call add_hit

    lea edi, [r12d + 20]
    lea esi, [r13d + 12]
    movzx edx, byte [rbx + CI_PRIORITY]
    mov ecx, C_DIM
    mov r8d, C_FAINT
    mov r9d, [rsp + 8]
    call draw_priority_icon
    lea edi, [r12d + 14]
    lea esi, [r13d + 7]
    mov edx, 26
    mov ecx, 24
    mov r8d, A_ROW_PRIORITY
    mov r9d, [rbx + CI_ID]
    call add_hit
    lea rdi, [scratch]
    mov rsi, rbx
    call put_issue_id
    mov rcx, rdi
    lea edi, [r12d + 48]
    lea esi, [r13d + 24]
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_scratch
    lea edi, [r12d + 116]
    lea esi, [r13d + 12]
    movzx edx, byte [rbx + CI_STATUS]
    mov ecx, [rsp + 8]
    call draw_status_icon
    lea edi, [r12d + 110]
    lea esi, [r13d + 7]
    mov edx, 26
    mov ecx, 24
    mov r8d, A_ROW_STATUS
    mov r9d, [rbx + CI_ID]
    call add_hit
    lea r15d, [r12d + 142]                  ; the title's x

    ; From the right edge in: assignee, date, project, labels.
    lea ebp, [r12d + r14d - 38]
    mov ecx, [rbx + CI_ASSIGNEE]
    test ecx, ecx
    jz .date
    mov edi, ecx
    call user_name
    mov r8, rsi
    mov edi, ebp
    lea esi, [r13d + 10]
    mov edx, 18
    mov ecx, [rbx + CI_ASSIGNEE]
    call draw_avatar
.date:
    sub ebp, 56
    lea rdi, [scratch]
    mov esi, [rbx + CI_CREATED]
    call put_date
    mov rcx, rdi
    mov edi, ebp
    lea esi, [r13d + 24]
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_scratch
    sub ebp, 10
    movzx eax, byte [rbx + CI_PROJECT]
    test eax, eax
    jz .labels
    dec eax
    imul eax, eax, PJ_SIZE
    lea rdi, [view_projects + rax]
    call .chip
.labels:
    mov dword [rsp], LABEL_SLOTS - 1        ; right to left, so they read in slot order
.label:
    mov ecx, [rsp]
    test ecx, ecx
    js .title
    movzx eax, word [rbx + CI_LABELS]
    bt eax, ecx
    jnc .next_label
    imul eax, ecx, LB_SIZE
    lea rdi, [view_labels + rax]
    call .chip
    test eax, eax
    jz .title
.next_label:
    dec dword [rsp]
    jmp .label
.title:
    mov edi, r15d
    lea esi, [r13d + 24]
    lea rdx, [rbx + CI_TITLE]
    movzx ecx, byte [rbx + CI_TITLE_LEN]
    mov r8d, INK(C_TEXT, ST_BODY)
    mov r9d, ebp
    sub r9d, r15d
    sub r9d, 8
    call draw_text_fit
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
; A label or project chip ending at ebp, if it leaves the title some room.
; rdi = the label or project -> eax = 0 when there wasn't room
.chip:
    push r12
    mov r12, rdi
    xor eax, eax
    cmp byte [r12 + LB_NAME_LEN], 0
    je .chip_skip                           ; a deleted label
    lea rdi, [r12 + LB_NAME]
    movzx esi, byte [r12 + LB_NAME_LEN]
    mov edx, 1
    call chip_width
    mov ecx, ebp
    sub ecx, eax
    lea edx, [r15d + 160]
    cmp ecx, edx
    jl .no_room
    mov ebp, ecx
    mov edi, ebp
    lea esi, [r13d + 7]
    lea rdx, [r12 + LB_NAME]
    movzx ecx, byte [r12 + LB_NAME_LEN]
    mov r8d, [r12 + LB_COLOR]
    call draw_chip
    sub ebp, 6
.chip_skip:
    mov eax, 1
    pop r12
    ret
.no_room:
    xor eax, eax
    pop r12
    ret

%define CARD_H          94

; One issue on the board. edi = x, esi = y, edx = w, rcx = view issue
draw_card:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov rbx, rcx
    mov rdi, rbx
    mov esi, C_RAISED
    call issue_bg
    mov [rsp + 8], eax
    mov r8d, C_LINE
    mov ecx, C_ACCENT
    mov edx, [rbx + CI_ID]
    cmp edx, [sel_id]
    cmove r8d, ecx
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, CARD_H
    mov r9d, eax
    mov r10d, 8
    call outline_rrect
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, CARD_H
    mov r8d, A_ISSUE
    mov r9d, [rbx + CI_ID]
    call add_hit

    lea rdi, [scratch]
    mov rsi, rbx
    call put_issue_id
    mov rcx, rdi
    lea edi, [r12d + 14]
    lea esi, [r13d + 24]
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_scratch
    mov edi, [rbx + CI_ASSIGNEE]
    test edi, edi
    jz .title
    call user_name
    mov r8, rsi
    lea edi, [r12d + r14d - 32]
    lea esi, [r13d + 10]
    mov edx, 18
    mov ecx, [rbx + CI_ASSIGNEE]
    call draw_avatar
.title:
    lea edi, [r12d + 14]
    lea esi, [r13d + 48]
    lea rdx, [rbx + CI_TITLE]
    movzx ecx, byte [rbx + CI_TITLE_LEN]
    mov r8d, INK(C_TEXT, ST_BODY)
    lea r9d, [r14d - 28]
    call draw_text_fit

    ; Priority in a little box, then the project and labels while they fit.
    lea edi, [r12d + 14]
    lea esi, [r13d + 58]
    mov edx, 24
    mov ecx, 24
    mov r8d, C_LINE
    mov r9d, [rsp + 8]
    mov r10d, 6
    call outline_rrect
    lea edi, [r12d + 19]
    lea esi, [r13d + 63]
    movzx edx, byte [rbx + CI_PRIORITY]
    mov ecx, C_DIM
    mov r8d, C_FAINT
    mov r9d, [rsp + 8]
    call draw_priority_icon
    lea ebp, [r12d + 44]                    ; chip x
    lea r15d, [r12d + r14d - 14]            ; where chips must end
    movzx eax, byte [rbx + CI_PROJECT]
    test eax, eax
    jz .labels
    dec eax
    imul eax, eax, PJ_SIZE
    lea rdi, [view_projects + rax]
    call .chip
.labels:
    mov dword [rsp], 0
.label:
    mov ecx, [rsp]
    cmp ecx, LABEL_SLOTS
    jae .done
    movzx eax, word [rbx + CI_LABELS]
    bt eax, ecx
    jnc .next_label
    imul eax, ecx, LB_SIZE
    lea rdi, [view_labels + rax]
    call .chip
    test eax, eax
    jz .done
.next_label:
    inc dword [rsp]
    jmp .label
.done:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
; A chip at ebp, if it fits before r15d. rdi = label or project -> eax = 0 if it didn't
.chip:
    push r12
    mov r12, rdi
    cmp byte [r12 + LB_NAME_LEN], 0
    je .chip_skip
    lea rdi, [r12 + LB_NAME]
    movzx esi, byte [r12 + LB_NAME_LEN]
    mov edx, 1
    call chip_width
    lea ecx, [ebp + eax]
    cmp ecx, r15d
    jg .no_room
    mov edi, ebp
    lea ebp, [ecx + 6]
    lea esi, [r13d + 58]
    lea rdx, [r12 + LB_NAME]
    movzx ecx, byte [r12 + LB_NAME_LEN]
    mov r8d, [r12 + LB_COLOR]
    call draw_chip
.chip_skip:
    mov eax, 1
    pop r12
    ret
.no_room:
    xor eax, eax
    pop r12
    ret

; The board: a column per status. edi = x, esi = top, edx = w, ecx = h
draw_board:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov [rsp], edi                          ; x
    mov [rsp + 4], esi                      ; top
    mov [rsp + 8], edx                      ; w
    mov [rsp + 12], ecx                     ; h
    call save_clip
    mov [rsp + 16], rax
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, edi
    add edx, [rsp + 8]
    mov ecx, esi
    add ecx, [rsp + 12]
    call clip_to

    mov eax, [rsp + 8]                      ; column width
    sub eax, 24 + 4 * CARD_GAP
    xor edx, edx
    mov ecx, STATUS_COUNT
    div ecx
    mov ecx, COL_MIN_W
    cmp eax, ecx
    cmovl eax, ecx
    mov [rsp + 24], eax
    cmp byte [board_reveal], 0
    je .scroll
    call reveal_card
.scroll:
    mov eax, [rsp + 24]
    imul eax, eax, STATUS_COUNT             ; sideways scrolling
    add eax, 24 + 4 * CARD_GAP
    mov [content_h], eax
    lea rdi, [board_x]
    mov esi, [rsp + 8]
    call clamp_scroll
    xor eax, eax                            ; and down, to the longest column
    xor ecx, ecx
.longest:
    mov edx, [col_count + rcx * 4]
    cmp edx, eax
    cmova eax, edx
    inc ecx
    cmp ecx, STATUS_COUNT
    jb .longest
    imul eax, eax, CARD_H + CARD_GAP
    add eax, GROUP_H + 8
    mov [content_h], eax
    lea rdi, [scroll_y]
    mov esi, [rsp + 12]
    call clamp_scroll

    xor r15d, r15d                          ; position in board_order
.column:
    cmp r15d, STATUS_COUNT
    jae .done
    movzx r14d, byte [board_order + r15]
    mov ebx, [rsp + 24]
    add ebx, CARD_GAP
    imul ebx, r15d
    add ebx, [rsp]
    add ebx, 12
    sub ebx, [board_x]
    mov r12d, [rsp + 4]
    add r12d, GROUP_H + 8
    sub r12d, [scroll_y]
    imul eax, r14d, VIEW_MAX * 8
    lea rbp, [col_items + rax]
    mov r13d, [col_count + r14 * 4]
.card:
    test r13d, r13d
    jz .header
    mov eax, [rsp + 4]
    add eax, [rsp + 12]
    cmp r12d, eax
    jge .header
    lea eax, [r12d + CARD_H]
    cmp eax, [rsp + 4]
    jle .next_card
    mov edi, ebx
    mov esi, r12d
    mov edx, [rsp + 24]
    mov rcx, [rbp]
    call draw_card
.next_card:
    add r12d, CARD_H + CARD_GAP
    add rbp, 8
    dec r13d
    jmp .card
.header:
    ; Drawn after the cards so they slide under it.
    mov edi, ebx
    mov esi, [rsp + 4]
    mov edx, [rsp + 24]
    mov ecx, r14d
    mov r8d, [col_count + r14 * 4]
    call draw_group
    inc r15d
    jmp .column
.done:
    mov rdi, [rsp + 16]
    call restore_clip
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Scrolls the board so the selected card shows. Only after keyboard moves,
; so it doesn't fight the scroll wheel. Uses draw_board's frame.
reveal_card:
    mov byte [board_reveal], 0
    call selected_cell
    cmp eax, -1
    je .done
    mov ecx, [rsp + 8 + 24]                 ; the column's x
    add ecx, CARD_GAP
    imul ecx, eax
    add ecx, 12
    mov eax, ecx
    sub eax, 12
    cmp eax, [board_x]
    jge .right
    mov [board_x], eax
    jmp .down
.right:
    add ecx, [rsp + 8 + 24]
    add ecx, 12
    sub ecx, [rsp + 8 + 8]
    cmp ecx, [board_x]
    jle .down
    mov [board_x], ecx
.down:
    imul edx, edx, CARD_H + CARD_GAP        ; the card's y below the header
    cmp edx, [scroll_y]
    jge .bottom
    mov [scroll_y], edx
    ret
.bottom:
    add edx, GROUP_H + 8 + CARD_H + 8
    sub edx, [rsp + 8 + 12]
    cmp edx, [scroll_y]
    jle .done
    mov [scroll_y], edx
.done:
    ret

; How tall draw_wrapped would make some text.
; rdi = text, esi = length, edx = width, ecx = style -> eax = height
text_height:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov ebp, esi
    mov r12d, esi                           ; left to measure
    mov r13d, edx
    mov r14d, ecx
    xor r15d, r15d
.line:
    mov rsi, rbx
    mov edx, r12d
    mov ecx, r13d
    mov r8d, r14d
    call wrap_line
    inc r15d
    add rbx, rdx
    sub r12d, edx
    ja .line
    test ebp, ebp
    jz .done
    cmp byte [rbx - 1], 10
    jne .done
    inc r15d
.done:
    imul eax, r15d, LINE_H
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The open issue's properties, down the right side.
; edi = x, esi = top, edx = h, rcx = view issue
draw_props:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov ebx, edi
    mov r12d, esi
    mov rbp, rcx
    mov ecx, edx
    mov edx, 1
    mov r8d, C_LINE
    call fill_rect
    lea r13d, [r12d + 20]                   ; row y
    xor r14d, r14d                          ; MK_*
.prop:
    cmp r14d, MK_LABELS
    ja .dates
    mov eax, r14d
    shl eax, 4
    mov rdx, [prop_names + rax]
    mov ecx, [prop_names + rax + 8]
    lea edi, [ebx + 20]
    lea esi, [r13d + 19]
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_text
    mov edi, A_PICK
    mov esi, r14d
    call hovering
    test eax, eax
    jz .pick
    lea edi, [ebx + 92]
    mov esi, r13d
    mov edx, PROPS_W - 104
    mov ecx, 28
    mov r8d, C_HOVER
    mov r9d, 6
    call fill_rrect
.pick:
    lea edi, [ebx + 92]
    mov esi, r13d
    mov edx, PROPS_W - 104
    mov ecx, 28
    mov r8d, A_PICK
    mov r9d, r14d
    call add_hit
    mov edi, r14d
    mov rsi, rbp
    call prop_info
    lea edi, [ebx + 100]
    mov esi, r13d
    mov edx, PROPS_W - 120
    call draw_prop
    add r13d, 36
    inc r14d
    jmp .prop
.dates:
    add r13d, 8
    lea edi, [ebx + 20]
    mov esi, r13d
    mov edx, PROPS_W - 40
    mov ecx, 1
    mov r8d, C_LINE
    call fill_rect
    add r13d, 30
    lea rdi, [scratch]
    lea rsi, [s_created]
    mov edx, s_created_len
    call put_mem
    mov esi, [rbp + CI_CREATED]
    call put_ago
    mov rcx, rdi
    lea edi, [ebx + 20]
    mov esi, r13d
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_scratch
    add r13d, 22
    lea rdi, [scratch]
    lea rsi, [s_updated]
    mov edx, s_updated_len
    call put_mem
    mov esi, [rbp + CI_UPDATED]
    call put_ago
    mov rcx, rdi
    lea edi, [ebx + 20]
    mov esi, r13d
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_scratch
    add r13d, 24
    lea edi, [ebx + 20]
    mov esi, r13d
    lea rdx, [s_delete_issue]
    mov ecx, s_delete_issue_len
    mov r8d, A_DELETE
    xor r9d, r9d
    call draw_button
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The open issue: title, description, activity and a comment box, with its
; properties on the right. edi = x, esi = top, edx = w, ecx = h
draw_detail:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56
    mov [rsp], edi                          ; x
    mov [rsp + 4], esi                      ; top
    mov [rsp + 8], edx                      ; w
    mov [rsp + 12], ecx                     ; h
    mov edi, [detail_issue]
    call find_view_issue
    test rax, rax
    jz .gone
    mov rbx, rax

    mov edi, [rsp]
    add edi, [rsp + 8]
    sub edi, PROPS_W
    mov esi, [rsp + 4]
    mov edx, [rsp + 12]
    mov rcx, rbx
    call draw_props

    mov eax, [rsp]                          ; the main column
    add eax, 48
    mov [rsp + 24], eax
    mov eax, [rsp + 8]
    sub eax, PROPS_W + 96
    mov ecx, 760
    cmp eax, ecx
    cmovg eax, ecx
    mov ecx, 120
    cmp eax, ecx
    cmovl eax, ecx
    mov [rsp + 28], eax
    call save_clip
    mov [rsp + 16], rax
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, edi
    add edx, [rsp + 8]
    sub edx, PROPS_W
    mov ecx, esi
    add ecx, [rsp + 12]
    call clip_to
    lea rdi, [detail_scroll]
    mov esi, [rsp + 12]
    call clamp_scroll
    mov r12d, [rsp + 4]                     ; y
    add r12d, 32
    sub r12d, [detail_scroll]
    mov [rsp + 32], r12d

    mov r14d, [rsp + 24]                    ; x of the column
    mov r15d, [rsp + 28]                    ; and its width
    cmp dword [focus], F_TITLE
    jne .title
    mov edi, F_TITLE                        ; one scrolling line while it's edited
    mov esi, r14d
    lea edx, [r12d + 22]
    mov ecx, r15d
    call draw_field
    mov eax, 28
    jmp .title_hit
.title:
    mov dword [wrap_lh], 28
    lea rdi, [rbx + CI_TITLE]
    movzx esi, byte [rbx + CI_TITLE_LEN]
    mov edx, r14d
    mov ecx, r12d
    mov r8d, r15d
    mov r9d, INK(C_TEXT, ST_TITLE)
    call draw_wrapped
.title_hit:
    mov ebp, eax
    lea edi, [r14d - 8]
    lea esi, [r12d - 4]
    lea edx, [r15d + 16]
    lea ecx, [ebp + 8]
    mov r8d, A_FIELD
    mov r9d, F_TITLE
    call add_hit

.description:
    lea r12d, [r12d + ebp + 24]
    cmp byte [detail_loaded], 0
    je .desc_loading
    cmp dword [focus], F_DESC
    jne .desc_text
    mov edi, F_DESC
    mov esi, r14d
    mov edx, r12d
    mov ecx, r15d
    call draw_area
    jmp .desc_hit
.desc_text:
    cmp dword [view_desc_len], 0
    je .desc_empty
    mov rdi, [view_desc]
    mov esi, [view_desc_len]
    mov edx, r14d
    mov ecx, r12d
    mov r8d, r15d
    mov r9d, INK(C_TEXT, ST_BODY)
    call draw_wrapped
    jmp .desc_hit
.desc_empty:
    lea edi, [r14d + 2]
    lea esi, [r12d + 14]
    lea rdx, [s_desc_hint]
    mov ecx, s_desc_hint_len
    mov r8d, INK(C_FAINT, ST_BODY)
    call draw_text
    mov eax, LINE_H
.desc_hit:
    mov ebp, 60
    cmp eax, ebp
    cmovg ebp, eax
    lea edi, [r14d - 8]
    lea esi, [r12d - 6]
    lea edx, [r15d + 16]
    lea ecx, [ebp + 12]
    mov r8d, A_FIELD
    mov r9d, F_DESC
    call add_hit
    jmp .activity
.desc_loading:
    mov edi, r14d
    lea esi, [r12d + 14]
    lea rdx, [s_loading]
    mov ecx, s_loading_len
    mov r8d, INK(C_FAINT, ST_BODY)
    call draw_text
    mov ebp, 60

.activity:
    lea r12d, [r12d + ebp + 32]
    mov edi, r14d
    mov esi, r12d
    mov edx, r15d
    mov ecx, 1
    mov r8d, C_LINE
    call fill_rect
    add r12d, 24
    mov edi, r14d
    lea esi, [r12d + 14]
    lea rdx, [s_activity]
    mov ecx, s_activity_len
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    add r12d, 36
    ; Who created it, and when.
    mov edi, [rbx + CI_CREATOR]
    call user_name
    push rsi
    push rdx
    mov r8, rsi
    mov edi, r14d
    mov esi, r12d
    mov edx, 18
    mov ecx, [rbx + CI_CREATOR]
    call draw_avatar
    pop rdx
    pop rsi
    lea rdi, [scratch]
    call put_mem
    lea rsi, [s_created_issue]
    mov edx, s_created_issue_len
    call put_mem
    mov esi, [rbx + CI_CREATED]
    call put_ago
    mov rcx, rdi
    lea edi, [r14d + 28]
    lea esi, [r12d + 14]
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_scratch
    add r12d, 36

    lea r13, [view_comments]
    mov eax, [view_comment_count]
    mov [rsp + 36], eax
.comment:
    cmp dword [rsp + 36], 0
    je .compose
    mov edi, [r13 + CC_AUTHOR]
    call user_name
    push rsi
    push rdx
    mov r8, rsi
    mov edi, r14d
    mov esi, r12d
    mov edx, 18
    mov ecx, [r13 + CC_AUTHOR]
    call draw_avatar
    pop rcx
    pop rdx
    lea edi, [r14d + 28]
    lea esi, [r12d + 14]
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    mov [rsp + 40], eax
    lea rdi, [scratch]
    mov esi, [r13 + CC_CREATED]
    call put_ago
    mov rcx, rdi
    mov edi, [rsp + 40]
    add edi, 8
    lea esi, [r12d + 14]
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_scratch
    mov r9d, INK(C_TEXT, ST_BODY)
    mov eax, INK(C_DIM, ST_BODY)            ; not on the server yet
    cmp byte [r13 + CC_PENDING], 0
    cmovne r9d, eax
    lea rdi, [r13 + CC_TEXT]
    movzx esi, word [r13 + CC_LEN]
    lea edx, [r14d + 28]
    lea ecx, [r12d + 24]
    lea r8d, [r15d - 28]
    call draw_wrapped
    lea r12d, [r12d + eax + 44]
    add r13, CC_SIZE
    dec dword [rsp + 36]
    jmp .comment

.compose:
    mov edi, F_COMMENT
    call field_addr
    mov rdi, [rax + FD_BUF]
    mov esi, [rax + FD_LEN]
    lea edx, [r15d - 24]
    mov ecx, ST_BODY
    call text_height
    lea ebp, [eax + 24]
    mov edi, F_COMMENT
    call field_focused
    mov r13d, eax
    mov r8d, C_LINE
    mov ecx, C_ACCENT
    test eax, eax
    cmovnz r8d, ecx
    mov edi, r14d
    mov esi, r12d
    mov edx, r15d
    mov ecx, ebp
    mov r9d, C_RAISED
    mov r10d, 8
    call outline_rrect
    mov edi, r14d
    mov esi, r12d
    mov edx, r15d
    mov ecx, ebp
    mov r8d, A_FIELD
    mov r9d, F_COMMENT
    call add_hit
    mov edi, F_COMMENT
    lea esi, [r14d + 12]
    lea edx, [r12d + 12]
    lea ecx, [r15d - 24]
    call draw_area
    lea r12d, [r12d + ebp + 8]
    test r13d, r13d
    jz .measured
    mov edi, r14d
    lea esi, [r12d + 12]
    lea rdx, [s_enter_send]
    mov ecx, s_enter_send_len
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_text
.measured:
    add r12d, 48
    sub r12d, [rsp + 32]
    mov [content_h], r12d
    mov rdi, [rsp + 16]
    call restore_clip
    jmp .done
.gone:
    ; Opened but not in the view yet, or about to close.
    mov edi, [rsp]
    mov esi, [rsp + 8]
    mov edx, [rsp + 4]
    add edx, 80
    lea rcx, [s_loading]
    mov r8d, s_loading_len
    mov r9d, INK(C_DIM, ST_MEDIUM)
    call draw_centered
.done:
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Shade, a click-catcher to dismiss, and the modal's box.
; edi = width, esi = height -> eax = x, edx = y
modal_box:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov r13d, esi
    call shade_screen
    xor edi, edi
    xor esi, esi
    mov edx, [win_w]
    mov ecx, [win_h]
    mov r8d, A_DISMISS
    xor r9d, r9d
    call add_hit
    mov ebx, [win_w]
    sub ebx, r12d
    sar ebx, 1
    mov edi, ebx
    mov esi, 80
    mov edx, r12d
    mov ecx, r13d
    mov r8d, C_LINE
    mov r9d, C_RAISED
    mov r10d, 12
    call outline_rrect
    mov edi, ebx
    mov esi, 80
    mov edx, r12d
    mov ecx, r13d
    mov r8d, A_BLOCK
    xor r9d, r9d
    call add_hit
    mov eax, ebx
    mov edx, 80
    pop r13
    pop r12
    pop rbx
    ret

draw_create:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    lea rdi, [new_desc_buf]
    mov esi, [fields + F_NEW_DESC * FD_SIZE + FD_LEN]
    mov edx, MODAL_W - 48
    mov ecx, ST_BODY
    call text_height
    mov r13d, 100                           ; the description's height
    cmp eax, r13d
    cmovg r13d, eax
    mov edi, MODAL_W
    lea esi, [r13d + 220]
    call modal_box
    mov ebx, eax
    mov r12d, edx

    call current_team_row
    test rax, rax
    jz .title
    lea rdx, [rax + CO_KEY]
    movzx ecx, byte [rax + CO_KEY_LEN]
    lea edi, [ebx + 24]
    lea esi, [r12d + 18]
    mov r8d, -1
    call draw_chip
    lea edi, [ebx + eax + 32]
    lea esi, [r12d + 35]
    lea rdx, [s_new_issue]
    mov ecx, s_new_issue_len
    mov r8d, INK(C_DIM, ST_BODY)
    call draw_text
.title:
    lea edi, [ebx + 16]
    lea esi, [r12d + 60]
    mov edx, MODAL_W - 32
    mov ecx, 36
    mov r8d, A_FIELD
    mov r9d, F_NEW_TITLE
    call add_hit
    mov edi, F_NEW_TITLE
    lea esi, [ebx + 24]
    lea edx, [r12d + 86]
    mov ecx, MODAL_W - 48
    call draw_field
    lea edi, [ebx + 16]
    lea esi, [r12d + 104]
    mov edx, MODAL_W - 32
    lea ecx, [r13d + 8]
    mov r8d, A_FIELD
    mov r9d, F_NEW_DESC
    call add_hit
    mov edi, F_NEW_DESC
    lea esi, [ebx + 24]
    lea edx, [r12d + 108]
    mov ecx, MODAL_W - 48
    call draw_area

    ; The draft's properties, as chips that open their menus.
    lea r14d, [ebx + 24]
    lea r15d, [r12d + r13d + 120]
    xor ebp, ebp
.chip:
    cmp ebp, MK_LABELS
    ja .footer
    mov edi, ebp
    xor esi, esi
    call prop_info
    mov rdi, [pi_item + MI_TEXT]
    mov esi, [pi_item + MI_LEN]
    mov edx, ST_SMALL
    call text_width
    add eax, 42
    mov [rsp], eax
    mov edi, A_PICK
    mov esi, ebp
    call hovering
    mov r9d, C_RAISED
    mov ecx, C_SELECT
    test eax, eax
    cmovnz r9d, ecx
    mov edi, r14d
    mov esi, r15d
    mov edx, [rsp]
    mov ecx, 28
    mov r8d, C_LINE
    mov r10d, 7
    call outline_rrect
    mov edi, r14d
    mov esi, r15d
    mov edx, [rsp]
    mov ecx, 28
    mov r8d, A_PICK
    mov r9d, ebp
    call add_hit
    lea rdi, [pi_item]
    lea esi, [r14d + 9]
    lea edx, [r15d + 7]
    call draw_item_icon
    lea edi, [r14d + 31]
    lea esi, [r15d + 19]
    mov rdx, [pi_item + MI_TEXT]
    mov ecx, [pi_item + MI_LEN]
    mov r8d, INK(C_TEXT, ST_SMALL)
    call draw_text
    mov eax, [rsp]
    lea r14d, [r14d + eax + 6]
    inc ebp
    jmp .chip

.footer:
    add r15d, 44
    mov edi, ebx
    mov esi, r15d
    mov edx, MODAL_W
    mov ecx, 1
    mov r8d, C_LINE
    call fill_rect
    lea edi, [ebx + 24]
    lea esi, [r15d + 32]
    lea rdx, [s_ctrl_enter]
    mov ecx, s_ctrl_enter_len
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_text
    lea rdi, [s_create_issue]
    mov esi, s_create_issue_len
    mov edx, ST_MEDIUM
    call text_width
    lea edi, [ebx + MODAL_W - 48]
    sub edi, eax
    lea esi, [r15d + 12]
    lea rdx, [s_create_issue]
    mov ecx, s_create_issue_len
    mov r8d, A_CREATE
    mov r9d, 1
    call draw_button
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%define TEAM_MODAL_W    440

draw_team_modal:
    push rbx
    push r12
    sub rsp, 8
    mov edi, TEAM_MODAL_W
    mov esi, 296
    call modal_box
    mov ebx, eax
    mov r12d, edx
    lea edi, [ebx + 28]
    lea esi, [r12d + 46]
    lea rdx, [s_new_team_title]
    mov ecx, s_new_team_title_len
    mov r8d, INK(C_TEXT, ST_TITLE)
    call draw_text
    lea edi, [ebx + 28]
    lea esi, [r12d + 84]
    lea rdx, [s_team_name]
    mov ecx, s_team_name_len
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    mov edi, F_TEAM_NAME
    lea esi, [ebx + 28]
    lea edx, [r12d + 94]
    mov ecx, TEAM_MODAL_W - 56
    call draw_field_box
    lea edi, [ebx + 28]
    lea esi, [r12d + 154]
    lea rdx, [s_team_key]
    mov ecx, s_team_key_len
    mov r8d, INK(C_DIM, ST_SMALL)
    mov r9d, TEAM_MODAL_W - 56
    call draw_text_fit
    mov edi, F_TEAM_KEY
    lea esi, [ebx + 28]
    lea edx, [r12d + 164]
    mov ecx, 140
    call draw_field_box
    lea edi, [ebx + 28]
    lea esi, [r12d + 236]
    lea rdx, [s_create_team]
    mov ecx, s_create_team_len
    mov r8d, A_CREATE_TEAM
    mov r9d, 1
    call draw_button
    add rsp, 8
    pop r12
    pop rbx
    ret

; The last error or notice, near the bottom. Any click clears it.
draw_toast:
    cmp dword [status_len], 0
    je .done
    push rbx
    push r12
    sub rsp, 8
    lea rdi, [status_msg]
    mov esi, [status_len]
    mov edx, ST_BODY
    call text_width
    lea ebx, [eax + 32]
    mov r12d, [win_w]
    sub r12d, ebx
    sar r12d, 1
    mov edi, r12d
    mov esi, [win_h]
    sub esi, 64
    mov edx, ebx
    mov ecx, 36
    mov r8d, C_LINE
    mov r9d, C_SELECT
    mov r10d, 8
    call outline_rrect
    lea edi, [r12d + 16]
    mov esi, [win_h]
    sub esi, 41
    lea rdx, [status_msg]
    mov ecx, [status_len]
    mov r8d, INK(C_TEXT, ST_BODY)
    call draw_text
    add rsp, 8
    pop r12
    pop rbx
.done:
    ret

; Everything after logging in: the sidebar, the panel and any modal.
draw_app:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call draw_sidebar
    call panel_rect
    mov ebx, eax
    mov r12d, ecx
    mov r13d, edx
    mov r14d, r8d
    mov edi, ebx
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    mov r8d, C_LINE
    mov r9d, C_PANEL
    mov r10d, 10
    call outline_rrect
    ; Inside the border, and short of the rounded corners at the bottom.
    lea edi, [ebx + 1]
    lea esi, [r12d + 1]
    lea edx, [ebx + r13d - 1]
    lea ecx, [r12d + r14d - 6]
    call set_clip
    cmp dword [current_team], 0
    je .no_team
    mov edi, ebx
    mov esi, r12d
    mov edx, r13d
    call draw_header
    mov edi, ebx
    lea esi, [r12d + HEADER_H - 1]
    mov edx, r13d
    mov ecx, 1
    mov r8d, C_LINE
    call fill_rect
    cmp dword [detail_issue], 0
    jne .detail
    mov edi, ebx
    lea esi, [r12d + HEADER_H]
    mov edx, r13d
    call draw_filters
    mov edi, ebx
    lea esi, [r12d + HEADER_H + FILTER_H - 1]
    mov edx, r13d
    mov ecx, 1
    mov r8d, C_LINE
    call fill_rect
    call list_height
    mov ecx, eax
    mov edi, ebx
    lea esi, [r12d + HEADER_H + FILTER_H]
    mov edx, r13d
    cmp byte [board], 0
    jne .board
    call draw_list
    jmp .modal
.board:
    call draw_board
    jmp .modal
.detail:
    mov edi, ebx
    lea esi, [r12d + HEADER_H]
    mov edx, r13d
    lea ecx, [r14d - HEADER_H]
    call draw_detail
    jmp .modal
.no_team:
    mov r15d, r14d
    shr r15d, 1
    add r15d, r12d
    mov edi, ebx
    mov esi, r13d
    lea edx, [r15d - 20]
    lea rcx, [s_no_team]
    mov r8d, s_no_team_len
    mov r9d, INK(C_DIM, ST_MEDIUM)
    call draw_centered
    lea rdi, [s_create_team]
    mov esi, s_create_team_len
    mov edx, ST_MEDIUM
    call text_width
    add eax, 24
    mov edi, r13d
    sub edi, eax
    sar edi, 1
    add edi, ebx
    mov esi, r15d
    lea rdx, [s_create_team]
    mov ecx, s_create_team_len
    mov r8d, A_NEW_TEAM
    mov r9d, 1
    call draw_button
.modal:
    call reset_clip
    cmp byte [modal], M_CREATE
    jne .team_modal
    call draw_create
    jmp .done
.team_modal:
    cmp byte [modal], M_TEAM
    jne .done
    call draw_team_modal
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Draws a frame if the window is ready and a buffer is free. A busy buffer
; leaves need_redraw set, so its release brings us back here.
render:
    cmp byte [configured], 0
    je .done
    push rbx
    call wl_acquire_buffer
    test rax, rax
    jz .busy
    call reset_clip
    mov dword [hit_count], 0
    cmp byte [list_dirty], 0
    je .background
    call build_list
.background:
    xor edi, edi
    xor esi, esi
    mov edx, [fb_w]
    mov ecx, [fb_h]
    mov r8d, C_BG
    call fill_rect
    cmp byte [logged_in], 0
    je .login
    call draw_app
    jmp .overlays
.login:
    call draw_login
.overlays:
    call draw_toast
    cmp byte [menu_open], 0
    je .present
    call draw_menu
.present:
    call wl_present
    mov byte [need_redraw], 0
    call update_hover
.busy:
    pop rbx
.done:
    ret
