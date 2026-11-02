; The screens: login, the sidebar, the list and board, the issue detail
; view and the two modals. The chat is drawn in chat.asm.

section .rodata
text s_new_issue,       "New issue"
text s_my_issues,       "My issues"
text s_your_teams,      "Your teams"
text s_issues,          "Issues"
text s_active,          "Active"
text s_projects,        "Projects"
text s_members,         "Members"
text s_remove,          "Remove"
text s_direct_messages, "Direct messages"
text s_invite_people,   "Invite people"
text s_settings,        "Settings"
text s_log_out,         "Log out"
text s_all_issues,      "All issues"
text s_active_issues,   "Active issues"
text s_backlog_view,    "Backlog"
text s_filter,          "Filter"
text s_list,            "List"
text s_board,           "Board"
text s_issue_count,     " issues"
text s_no_issues,       "No issues here"
text s_no_matches,      "No issues match these filters"
text s_unfilter_hint,   "Remove a filter above to see more."
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
text s_confirm_delete,  "Click again to delete"
text s_new_team_title,  "Create a team"
text s_team_name,       "Name"
text s_team_key,        "Identifier, used in issue IDs like ENG-12"
text s_label_is,        "Label: "
text s_project_is,      "Project: "
text s_priority_is,     "Priority: "
text s_assignee_is,     "Assignee: "
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
    cmp byte [restoring], 0
    je .form
    mov edi, ebx
    lea esi, [r12d + 164]
    lea rdx, [s_signing_in]
    mov ecx, s_signing_in_len
    mov r8d, INK(C_DIM, ST_BODY)
    mov r9d, 340
    call draw_text_fit
    jmp .footer

.form:
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
    mov r9d, BTN_PRIMARY
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
    cmp byte [chat_open], 0
    jne .chat_name
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
.chat_name:
    lea rdi, [scratch]
    call put_chat_name
    jmp .scratch_crumb
.issue_id:
    mov edi, [detail_issue]
    call find_view_issue
    test rax, rax
    jz .done
    lea rdi, [scratch]
    mov rsi, rax
    call put_issue_id
.scratch_crumb:
    lea rdx, [scratch]
    mov rcx, rdi
    sub rcx, rdx
.crumb:
    mov edi, [rsp]
    lea esi, [r12d + 27]
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    cmp byte [chat_open], 0
    jne .close
    cmp dword [detail_issue], 0
    jne .close
    lea edi, [ebx + r13d - 132]
    mov esi, r12d
    call draw_layout_switch
    jmp .done
.close:
    lea r14d, [ebx + r13d - 44]
    cmp byte [chat_open], 0
    je .close_button
    mov edi, r14d
    mov esi, r12d
    call draw_channel_edit_link
.close_button:
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
    lea edi, [r14d + 14]
    lea esi, [r12d + 22]
    mov edx, 18
    mov ecx, C_DIM
    call draw_cross
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; List and board, as a two-part switch. edi = x, esi = the header's y
draw_layout_switch:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    lea esi, [r12d + 8]
    mov edx, 116
    mov ecx, 28
    mov r8d, C_LINE
    mov r9d, C_PANEL
    mov r10d, 6
    call outline_rrect
    movzx eax, byte [board]
    imul eax, eax, 57
    lea edi, [ebx + eax + 2]
    lea esi, [r12d + 10]
    mov edx, 55
    mov ecx, 24
    mov r8d, C_SELECT
    mov r9d, 5
    call fill_rrect
    mov edi, ebx
    lea esi, [r12d + 8]
    mov edx, 58
    mov ecx, 28
    mov r8d, A_LAYOUT
    xor r9d, r9d
    call add_hit
    lea edi, [ebx + 58]
    lea esi, [r12d + 8]
    mov edx, 58
    mov ecx, 28
    mov r8d, A_LAYOUT
    mov r9d, 1
    call add_hit
    mov edi, ebx
    mov esi, 58
    mov edx, r12d
    add edx, 27
    lea rcx, [s_list]
    mov r8d, s_list_len
    mov r9d, INK(C_TEXT, ST_SMALL)
    call draw_centered
    lea edi, [ebx + 58]
    mov esi, 58
    lea edx, [r12d + 27]
    lea rcx, [s_board]
    mov r8d, s_board_len
    mov r9d, INK(C_TEXT, ST_SMALL)
    call draw_centered
    add rsp, 8
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
    call .named_chip
.project:
    mov eax, [filter_project]
    test eax, eax
    jz .priority
    dec eax
    imul eax, eax, PJ_SIZE
    lea r15, [view_projects + rax]
    lea rsi, [s_project_is]
    mov edx, s_project_is_len
    mov ecx, 1
    call .named_chip
.priority:
    mov edi, [filter_priority]
    test edi, edi
    js .assignee
    call priority_name
    mov r15, rsi
    mov r9d, edx
    lea rsi, [s_priority_is]
    mov edx, s_priority_is_len
    mov r8d, -1
    mov ecx, 2
    call .filter_chip
.assignee:
    mov edi, [filter_assignee]
    test edi, edi
    js .count
    lea rsi, [s_no_assignee]
    mov edx, s_no_assignee_len
    jz .nobody
    call user_name
.nobody:
    mov r15, rsi
    mov r9d, edx
    lea rsi, [s_assignee_is]
    mov edx, s_assignee_is_len
    mov r8d, -1
    mov ecx, 3
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
; The same for a label or project, named and colored by its slot at r15.
.named_chip:
    mov r8d, [r15 + LB_COLOR]
    movzx r9d, byte [r15 + LB_NAME_LEN]
    lea r15, [r15 + LB_NAME]
; A removable filter chip at r14d. rsi = prefix, edx = its length,
; r15 = name, r9d = its length, r8d = dot color or -1,
; ecx = A_UNFILTER's arg. Advances r14d.
.filter_chip:
    push rcx
    lea rdi, [scratch]
    call put_mem
    mov rsi, r15
    mov edx, r9d
    call put_mem
    lea rdx, [scratch]
    mov rcx, rdi
    sub rcx, rdx
    mov edi, r14d
    lea esi, [r12d + 8]
    call draw_removable_chip
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
    call filtered
    lea rcx, [s_no_issues]
    mov r8d, s_no_issues_len
    test eax, eax
    jz .note
    lea rcx, [s_no_matches]
    mov r8d, s_no_matches_len
.note:
    mov edi, [rsp]
    mov esi, [rsp + 8]
    mov edx, [rsp + 4]
    add edx, 80
    mov r9d, INK(C_DIM, ST_MEDIUM)
    call draw_centered
    cmp byte [loaded], 0
    je .done
    call filtered
    lea rcx, [s_press_c]
    mov r8d, s_press_c_len
    test eax, eax
    jz .hint
    lea rcx, [s_unfilter_hint]
    mov r8d, s_unfilter_hint_len
.hint:
    mov edi, [rsp]
    mov esi, [rsp + 8]
    mov edx, [rsp + 4]
    add edx, 104
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

    ; No priority is only shown on hover, as the place to click to set one.
    movzx edx, byte [rbx + CI_PRIORITY]
    test edx, edx
    jnz .priority
    cmp dword [rsp + 8], C_PANEL
    je .priority_hit
.priority:
    lea edi, [r12d + 20]
    lea esi, [r13d + 12]
    mov ecx, C_DIM
    mov r8d, C_FAINT
    mov r9d, [rsp + 8]
    call draw_priority_icon
.priority_hit:
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
    mov edi, ebp
    mov esi, r13d
    mov edx, r15d
    mov rcx, rbx
    call row_chips
    mov ebp, eax
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
    ; No priority leaves the box out unless the card's hovered.
    ; When it was made at the bottom right, and the chips stop short of it.
    lea rdi, [scratch]
    mov esi, [rbx + CI_CREATED]
    call put_date
    lea rdx, [scratch]
    mov rcx, rdi
    sub rcx, rdx
    lea edi, [r12d + r14d - 14]
    lea esi, [r13d + 75]
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_link
    lea r15d, [eax - 8]                     ; where chips must end
    lea ebp, [r12d + 14]                    ; chip x
    cmp byte [rbx + CI_PRIORITY], 0
    jne .priority
    cmp dword [rsp + 8], C_RAISED
    je .chips
.priority:
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
    add ebp, 30
.chips:
    mov edi, ebp
    mov esi, r13d
    mov edx, r15d
    mov rcx, rbx
    call card_chips
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
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

    mov rax, [rsp]                          ; for drop_column
    mov [board_area], rax
    mov rax, [rsp + 8]
    mov [board_area + 8], rax
    mov eax, [rsp + 24]
    mov [board_col_w], eax
    mov qword [rsp + 32], 0                 ; the held card, while it's moving
    mov dword [rsp + 28], -1                ; the column it would drop into
    cmp byte [drag_moving], 0
    je .columns
    mov edi, [drag_id]
    call find_view_issue
    mov [rsp + 32], rax
    test rax, rax
    jz .columns
    call drop_column
    cmp eax, -1
    je .columns
    movzx ecx, byte [board_order + rax]
    mov rdx, [rsp + 32]
    cmp [rdx + CI_STATUS], cl
    je .columns                             ; it's already in that column
    mov [rsp + 28], eax

.columns:
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
    cmp r15d, [rsp + 28]
    jne .card
    lea edi, [ebx - 4]                      ; the drop target, out into the gaps
    mov esi, [rsp + 4]
    add esi, GROUP_H + 4
    mov edx, [rsp + 24]
    add edx, 8
    mov ecx, [rsp + 12]
    sub ecx, GROUP_H + 12                   ; clear of the panel's rounded bottom
    mov r8d, C_ACCENT
    mov r9d, C_GROUP
    mov r10d, 8
    call outline_rrect
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
    cmp rcx, [rsp + 32]
    je .held
    call draw_card
    jmp .next_card
.held:
    mov ecx, CARD_H                         ; an empty slot where it was
    mov r8d, C_LINE
    mov r9d, C_PANEL
    mov r10d, 8
    call outline_rrect
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
    mov rcx, [rsp + 32]                     ; the held card follows the pointer, over the headers too
    test rcx, rcx
    jz .out
    mov edi, [pointer_x]
    sub edi, [drag_dx]
    mov esi, [pointer_y]
    sub esi, [drag_dy]
    mov edx, [rsp + 24]
    call draw_card
.out:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -> eax = the board column under the pointer (index into board_order), or
; -1 outside the board. Uses the last frame's layout.
drop_column:
    mov eax, [pointer_x]
    sub eax, [board_area]
    cmp eax, [board_area + 8]
    jae .none
    mov ecx, [pointer_y]
    sub ecx, [board_area + 4]
    cmp ecx, [board_area + 12]
    jae .none
    add eax, [board_x]
    sub eax, 12
    xor ecx, ecx
    cmp eax, ecx
    cmovl eax, ecx
    xor edx, edx
    mov ecx, [board_col_w]
    add ecx, CARD_GAP
    div ecx
    mov ecx, STATUS_COUNT - 1
    cmp eax, ecx
    cmova eax, ecx
    ret
.none:
    mov eax, -1
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
; edi = x, esi = top, edx = h, rcx = view issue, r8d = width
draw_props:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov rbp, rcx
    mov r15d, r8d
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
    lea edx, [r15d - 104]
    mov ecx, 28
    mov r8d, C_HOVER
    mov r9d, 6
    call fill_rrect
.pick:
    lea edi, [ebx + 92]
    mov esi, r13d
    lea edx, [r15d - 104]
    mov ecx, 28
    mov r8d, A_PICK
    mov r9d, r14d
    call add_hit
    mov edi, r14d
    mov rsi, rbp
    call prop_info
    lea edi, [ebx + 100]
    mov esi, r13d
    lea edx, [r15d - 120]
    call draw_prop
    add r13d, 36
    inc r14d
    jmp .prop
.dates:
    add r13d, 8
    lea edi, [ebx + 20]
    mov esi, r13d
    lea edx, [r15d - 40]
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
    ; Deleting can't be undone, so the first click only asks again.
    lea rdx, [s_delete_issue]
    mov ecx, s_delete_issue_len
    xor r9d, r9d
    mov eax, [rbp + CI_ID]
    cmp eax, [delete_armed]
    jne .delete
    lea rdx, [s_confirm_delete]
    mov ecx, s_confirm_delete_len
    mov r9d, BTN_DANGER
.delete:
    lea edi, [ebx + 20]
    mov esi, r13d
    mov r8d, A_DELETE
    call draw_button
    add rsp, 8
    pop r15
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

    ; Narrow windows get narrower properties and margins, so the text
    ; column keeps some room.
    mov dword [rsp + 36], PROPS_W
    mov ebp, 48                             ; the column's margin
    cmp dword [rsp + 8], DETAIL_NARROW
    jge .props
    mov dword [rsp + 36], PROPS_NARROW_W
    mov ebp, 24
.props:
    mov edi, [rsp]
    add edi, [rsp + 8]
    sub edi, [rsp + 36]
    mov esi, [rsp + 4]
    mov edx, [rsp + 12]
    mov rcx, rbx
    mov r8d, [rsp + 36]
    call draw_props

    mov eax, [rsp]                          ; the main column
    add eax, ebp
    mov [rsp + 24], eax
    mov eax, [rsp + 8]
    sub eax, [rsp + 36]
    sub eax, ebp
    sub eax, ebp
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
    sub edx, [rsp + 36]
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
    mov [fields + F_TITLE * FD_SIZE + FD_X], r14d   ; so a click can place the caret
    mov [fields + F_TITLE * FD_SIZE + FD_Y], r12d
    mov [fields + F_TITLE * FD_SIZE + FD_W], r15d
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
    mov edi, r14d
    mov esi, r12d
    mov edx, r15d
    call draw_description
    mov ebp, eax
.activity:
    mov rdi, rbx
    mov esi, r14d
    lea edx, [r12d + ebp + 32]
    mov ecx, r15d
    call draw_activity
    mov r12d, eax
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

; The open issue's description, or the box editing it.
; edi = x, esi = top, edx = width -> eax = its height
draw_description:
    push rbp
    push r12
    push r14
    push r15
    sub rsp, 8
    mov r14d, edi
    mov r12d, esi
    mov r15d, edx
    mov [fields + F_DESC * FD_SIZE + FD_X], r14d    ; so a click can place the caret
    mov [fields + F_DESC * FD_SIZE + FD_Y], r12d
    mov [fields + F_DESC * FD_SIZE + FD_W], r15d
    cmp byte [detail_loaded], 0
    je .loading
    cmp dword [focus], F_DESC
    jne .text
    mov edi, F_DESC
    mov esi, r14d
    mov edx, r12d
    mov ecx, r15d
    call draw_area
    jmp .hit
.text:
    cmp dword [view_desc_len], 0
    je .empty
    mov rdi, [view_desc]
    mov esi, [view_desc_len]
    mov edx, r14d
    mov ecx, r12d
    mov r8d, r15d
    mov r9d, INK(C_TEXT, ST_BODY)
    mov byte [wrap_mentions], 1
    call draw_wrapped
    jmp .hit
.empty:
    lea edi, [r14d + 2]
    lea esi, [r12d + 14]
    lea rdx, [s_desc_hint]
    mov ecx, s_desc_hint_len
    mov r8d, INK(C_FAINT, ST_BODY)
    call draw_text
    mov eax, LINE_H
.hit:
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
    jmp .done
.loading:
    mov edi, r14d
    lea esi, [r12d + 14]
    lea rdx, [s_loading]
    mov ecx, s_loading_len
    mov r8d, INK(C_FAINT, ST_BODY)
    call draw_text
    mov ebp, 60
.done:
    mov eax, ebp
    add rsp, 8
    pop r15
    pop r14
    pop r12
    pop rbp
    ret

; The open issue's activity: who made it, its comments, and the box for
; the next one. rdi = view issue, esi = x, edx = top, ecx = width
; -> eax = the y under the comment box's hint
draw_activity:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r14d, esi
    mov r12d, edx
    mov r15d, ecx
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
    lea rdx, [scratch]
    mov rcx, rdi
    sub rcx, rdx
    lea edi, [r14d + 28]
    lea esi, [r12d + 14]
    mov r8d, INK(C_DIM, ST_SMALL)
    lea r9d, [r15d - 28]
    call draw_text_fit
    add r12d, 36

    lea r13, [view_comments]
    mov eax, [view_comment_count]
    mov [rsp], eax
.comment:
    cmp dword [rsp], 0
    je .compose
    mov rdi, r13
    mov esi, r14d
    mov edx, r12d
    mov ecx, r15d
    call draw_comment
    add r12d, eax
    add r13, CC_SIZE
    dec dword [rsp]
    jmp .comment

.compose:
    mov edi, r14d
    mov esi, r12d
    mov edx, r15d
    call draw_comment_box
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The box for the next comment, with a hint under it while it's focused.
; edi = x, esi = top, edx = width -> eax = the y under it
draw_comment_box:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r14d, edi
    mov r12d, esi
    mov r15d, edx
    mov edi, F_COMMENT
    mov esi, r14d
    mov edx, r12d
    call draw_attachment
    mov edi, F_COMMENT
    call attachment_height
    add r12d, eax                           ; the box goes under it
    mov edi, F_COMMENT
    call field_addr
    mov rdi, [rax + FD_BUF]
    mov esi, [rax + FD_LEN]
    lea edx, [r15d - 24 - BOX_BUTTONS_W]
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
    lea ecx, [r15d - 24 - BOX_BUTTONS_W]
    call draw_area
    mov edi, F_COMMENT
    lea esi, [r14d + r15d]
    lea edx, [r12d + ebp]
    call draw_box_buttons
    lea r12d, [r12d + ebp + 8]
    test r13d, r13d
    jz .done
    mov edi, r14d
    lea esi, [r12d + 12]
    lea rdx, [s_enter_send]
    mov ecx, s_enter_send_len
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_text
.done:
    mov eax, r12d
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Shade, a click-catcher to dismiss, and the modal's box with an X to close it.
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
    lea r12d, [ebx + r12d - 44]             ; the X
    mov edi, A_CLOSE_MODAL
    xor esi, esi
    call hovering
    test eax, eax
    jz .close_hit
    mov edi, r12d
    mov esi, 96
    mov edx, 28
    mov ecx, 28
    mov r8d, C_HOVER
    mov r9d, 6
    call fill_rrect
.close_hit:
    mov edi, r12d
    mov esi, 96
    mov edx, 28
    mov ecx, 28
    mov r8d, A_CLOSE_MODAL
    xor r9d, r9d
    call add_hit
    lea edi, [r12d + 14]
    mov esi, 110
    mov edx, 18
    mov ecx, C_DIM
    call draw_cross
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
    mov r9d, BTN_PRIMARY
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
    mov r9d, BTN_PRIMARY
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
    cmp byte [chat_open], 0
    jne .chat
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
.chat:
    mov edi, ebx
    lea esi, [r12d + HEADER_H]
    mov edx, r13d
    lea ecx, [r14d - HEADER_H]
    call draw_chat
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
    mov r9d, BTN_PRIMARY
    call draw_button
.modal:
    call reset_clip
    cmp byte [modal], M_CREATE
    jne .team_modal
    call draw_create
    jmp .done
.team_modal:
    cmp byte [modal], M_TEAM
    jne .labels_modal
    call draw_team_modal
    jmp .done
.labels_modal:
    cmp byte [modal], M_LABELS
    jne .password_modal
    call draw_labels_modal
    jmp .done
.password_modal:
    cmp byte [modal], M_PASSWORD
    jne .settings_modal
    call draw_password_modal
    jmp .done
.settings_modal:
    cmp byte [modal], M_SETTINGS
    jne .channel_modal
    call draw_team_settings
    jmp .done
.channel_modal:
    cmp byte [modal], M_CHANNEL
    jne .image_modal
    call draw_channel_dialog
    jmp .done
.image_modal:
    cmp byte [modal], M_IMAGE
    jne .done
    call draw_image_view
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
    call wl_acquire_buffer
    test rax, rax
    jz .done
    call draw_frame
    call wl_present
    mov byte [need_redraw], 0
    call update_hover
.done:
    ret

; Draws everything into fb and rebuilds the hit regions.
draw_frame:
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
    call draw_mentions
    call draw_toast
    cmp byte [menu_open], 0
    je .pump
    call draw_menu
.pump:
    jmp images_pump                         ; what this frame wanted to show

