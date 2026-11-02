; The menus: the command menu and the pickers for a property or a filter.
; What each one lists for its filter text, opening, scrolling and choosing
; from it, and drawing it. Its state lives in ui.asm with the rest.

section .rodata
text s_create_label,    "Create label: "
text s_create_project,  "Create project: "
text s_no_results,      "No results"
text s_group_label,     "Label"
text s_group_project,   "Project"
text s_group_priority,  "Priority"
text s_group_assignee,  "Assignee"
group_names:    NAME s_group_label      ; by FG_* - 1
                NAME s_group_project
                NAME s_group_priority
                NAME s_group_assignee

text c_new_issue,       "Create new issue"
text c_board,           "Switch to board view"
text c_list,            "Switch to list view"
text c_status,          "Change status"
text c_priority,        "Change priority"
text c_assign,          "Assign to"
text c_project,         "Move to project"
text c_labels,          "Change labels"
text c_delete,          "Delete issue"
text c_all,             "Go to all issues"
text c_active,          "Go to active issues"
text c_backlog,         "Go to backlog"
text c_mine,            "Go to my issues"
text c_chat,            "Go to #general"
text c_filter,          "Filter issues"
text c_clear,           "Clear filters"
text c_new_team,        "Create new team"
text c_log_out,         "Log out"
text c_copy_id,         "Copy issue ID"
text c_labels_manage,   "Manage labels and projects"
text c_password,        "Change password"
text c_settings,        "Team settings"
text c_invite,          "Invite people"
text c_new_channel,     "New channel"
text c_account,         "Account settings"
text c_all_teams,       "All teams"

%define ISSUE_RESULTS   20              ; issues the command menu lists for a search

text h_status,          "Change status..."
text h_priority,        "Set priority..."
text h_assignee,        "Assign to..."
text h_project,         "Move to project..."
text h_labels,          "Add or remove labels..."
text h_filter,          "Filter by..."
text h_command,         "Type a command or search..."
menu_hints:     NAME h_status
                NAME h_priority
                NAME h_assignee
                NAME h_project
                NAME h_labels
                NAME h_filter
                NAME h_command

; The command menu, top to bottom: text, value, hint key, and when it shows.
%define WHEN_ALWAYS     0
%define WHEN_ISSUE      1               ; there's an issue to act on
%define WHEN_LIST       2               ; in the list layout
%define WHEN_BOARD      3
%define WHEN_FILTERED   4
%macro COMMAND 5                        ; text, value, hint key, when, GL_* icon
    dq %1
    dd %1_len, %2
    db %3, %4, %5, 0, 0, 0, 0, 0
%endmacro
commands:
    COMMAND c_new_issue, CMD_NEW_ISSUE, 'C', WHEN_ALWAYS, GL_PLUS
    COMMAND c_status, CMD_PICK + MK_STATUS, 'S', WHEN_ISSUE, GL_ACTIVE
    COMMAND c_priority, CMD_PICK + MK_PRIORITY, 'P', WHEN_ISSUE, GL_BARS
    COMMAND c_assign, CMD_PICK + MK_ASSIGNEE, 'A', WHEN_ISSUE, GL_PERSON
    COMMAND c_labels, CMD_PICK + MK_LABELS, 'L', WHEN_ISSUE, GL_TAG
    COMMAND c_project, CMD_PICK + MK_PROJECT, 'M', WHEN_ISSUE, GL_CUBE
    COMMAND c_copy_id, CMD_COPY_ID, 0, WHEN_ISSUE, GL_COPY
    COMMAND c_delete, CMD_DELETE, 0, WHEN_ISSUE, GL_TRASH
    COMMAND c_board, CMD_LAYOUT, 0, WHEN_LIST, GL_GRID
    COMMAND c_list, CMD_LAYOUT, 0, WHEN_BOARD, GL_LIST
    COMMAND c_all, CMD_VIEW + V_ALL, 0, WHEN_ALWAYS, GL_ISSUES
    COMMAND c_active, CMD_VIEW + V_ACTIVE, 0, WHEN_ALWAYS, GL_ACTIVE
    COMMAND c_backlog, CMD_VIEW + V_BACKLOG, 0, WHEN_ALWAYS, GL_BACKLOG
    COMMAND c_mine, CMD_VIEW + V_MINE, 0, WHEN_ALWAYS, GL_PERSON
    COMMAND c_chat, CMD_CHAT, 0, WHEN_ALWAYS, GL_HASH
    COMMAND c_filter, CMD_FILTER, 0, WHEN_ALWAYS, GL_FUNNEL
    COMMAND c_clear, CMD_CLEAR, 0, WHEN_FILTERED, GL_CROSS
    COMMAND c_labels_manage, CMD_LABELS, 0, WHEN_ALWAYS, GL_TAG
    COMMAND c_new_channel, CMD_NEW_CHANNEL, 0, WHEN_ALWAYS, GL_HASH
    COMMAND c_invite, CMD_INVITE, 0, WHEN_ALWAYS, GL_PERSON
    COMMAND c_settings, CMD_SETTINGS, 0, WHEN_ALWAYS, GL_SETTINGS
    COMMAND c_all_teams, CMD_ALL_TEAMS, 0, WHEN_ALWAYS, GL_GRID
    COMMAND c_new_team, CMD_NEW_TEAM, 0, WHEN_ALWAYS, GL_PLUS
    COMMAND c_account, CMD_ACCOUNT, 0, WHEN_ALWAYS, GL_PERSON
    COMMAND c_password, CMD_PASSWORD, 0, WHEN_ALWAYS, GL_LOCK
    COMMAND c_log_out, CMD_LOGOUT, 0, WHEN_ALWAYS, GL_LOGOUT
    dq 0
%define COMMAND_SIZE 24

section .text

; Opens a menu. edi = MK_*, esi = the issue it changes (0: the draft)
open_menu:
    mov [menu_kind], edi
    mov [menu_issue], esi
    mov byte [menu_open], 1
    xor eax, eax
    mov [menu_sel], eax
    mov [menu_scroll], eax
    mov [menu_wheel], eax
    mov edi, F_MENU
    call field_clear
    call menu_select_current
    mov edi, F_MENU
    jmp set_focus

; Starts a single-choice menu on the value it has now, so Enter keeps it.
menu_select_current:
    cmp dword [menu_kind], MK_PROJECT
    ja .done                                ; labels pick several, and the rest have no value
    call build_menu
    xor ecx, ecx
.item:
    cmp ecx, [menu_count]
    jae .done
    imul eax, ecx, MI_SIZE
    cmp byte [menu_items + rax + MI_CHECK], 0
    jne .found
    inc ecx
    jmp .item
.found:
    mov [menu_sel], ecx
.done:
    ret

; edi = pixels the wheel turned. Scrolls the menu a row per notch and keeps
; the selection among the rows showing.
menu_wheel_by:
    add edi, [menu_wheel]
    mov eax, edi
    cdq
    mov ecx, WHEEL_NOTCH
    idiv ecx
    mov [menu_wheel], edx
    add eax, [menu_scroll]
    mov ecx, [menu_count]
    sub ecx, MENU_SHOWN
    cmp eax, ecx
    cmovg eax, ecx
    xor ecx, ecx
    cmp eax, ecx
    cmovl eax, ecx
    mov [menu_scroll], eax
    mov ecx, [menu_sel]
    cmp ecx, eax
    cmovl ecx, eax
    add eax, MENU_SHOWN - 1
    cmp ecx, eax
    cmovg ecx, eax
    mov [menu_sel], ecx
    mov byte [need_redraw], 1
    ret

; A right click on an issue's row or card: what can be done to it, in a
; menu at the pointer.
ui_right_click:
    call update_hover
    mov byte [need_redraw], 1
    cmp byte [modal], M_NONE
    jne .done
    cmp byte [menu_open], 0
    jne .done
    cmp dword [hover_action], A_ISSUE
    jne .done
    mov esi, [hover_arg]
    mov [sel_id], esi
    mov byte [menu_context], 1
    mov eax, [pointer_x]
    mov [menu_ax], eax
    mov eax, [pointer_y]
    mov [menu_ay], eax
    mov edi, MK_COMMAND
    jmp open_menu
.done:
    ret

; Closes the menu, back to the field that had focus before it.
close_menu:
    mov byte [menu_open], 0
    mov byte [menu_context], 0
    mov edi, F_NONE
    cmp byte [modal], M_CREATE
    jne .focus
    mov edi, F_NEW_TITLE
.focus:
    jmp set_focus

; Opens a property menu for whatever shortcuts act on. edi = MK_*
pick_for_target:
    push rbx
    mov ebx, edi
    call target_issue
    test eax, eax
    jz .done
    mov edi, ebx
    mov esi, eax
    call open_menu
.done:
    pop rbx
    ret

; Applies a chosen menu item. edi = item index
choose_item:
    push rbx
    push r12
    push r13
    cmp edi, [menu_count]
    jae .done
    imul eax, edi, MI_SIZE
    lea rbx, [menu_items + rax]
    mov r12d, [rbx + MI_VALUE]
    mov r13d, [menu_issue]
    mov eax, [menu_kind]
    cmp eax, MK_COMMAND
    je .command
    cmp eax, MK_FILTER
    je .filter
    cmp eax, MK_LABELS
    je .labels
    cmp eax, MK_PROJECT
    jne .field
    cmp byte [rbx + MI_ICON], IC_PLUS
    jne .field
    call create_project                     ; -> eax = its number, or 0
    test eax, eax
    jz .close
    mov r12d, eax
.field:
    ; MK_STATUS..MK_PROJECT line up with FIELD_STATUS..FIELD_PROJECT.
    mov esi, [menu_kind]
    inc esi
    test r13d, r13d
    jz .draft
    mov edi, r13d
    mov edx, r12d
    call sync_set_field
    jmp .close
.draft:
    mov [new_status + rsi * 4 - 4], r12d    ; new_status..new_project are in field order
    jmp .close
.labels:
    cmp byte [rbx + MI_ICON], IC_PLUS
    jne .toggle
    call create_label                       ; -> eax = its slot, or -1
    test eax, eax
    js .done
    mov r12d, eax
.toggle:
    mov eax, 1
    mov ecx, r12d
    shl eax, cl
    test r13d, r13d
    jz .draft_labels
    mov r12d, eax
    mov edi, r13d
    call find_view_issue
    test rax, rax
    jz .close
    movzx edx, word [rax + CI_LABELS]
    xor edx, r12d
    mov edi, r13d
    mov esi, FIELD_LABELS
    call sync_set_field
    jmp .keep_open
.draft_labels:
    xor [new_labels], eax
.keep_open:
    mov edi, F_MENU                         ; labels stay open for more picks
    call field_clear
    jmp .done
.filter:
    test r12d, r12d
    js .filter_label
    test r12d, FILTER_ASSIGNEE
    jnz .filter_assignee
    test r12d, FILTER_PRIORITY
    jnz .filter_priority
    mov [filter_project], r12d
    jmp .refilter
.filter_label:
    not r12d
    mov [filter_label], r12d
    jmp .refilter
.filter_assignee:
    and r12d, ~FILTER_ASSIGNEE
    mov [filter_assignee], r12d
    jmp .refilter
.filter_priority:
    and r12d, ~FILTER_PRIORITY
    mov [filter_priority], r12d
.refilter:
    mov byte [list_dirty], 1
    jmp .close
.command:
    ; A pick a right click's menu leads to opens where it was.
    movzx r13d, byte [menu_context]
    call close_menu
    mov edi, r12d
    call run_command
    cmp byte [menu_open], 0
    je .done
    mov [menu_context], r13b
    jmp .done
.close:
    call close_menu
.done:
    mov byte [need_redraw], 1
    pop r13
    pop r12
    pop rbx
    ret

; -> the menu's current value for the issue or draft it changes: eax for
; single choices, the label bitmask for labels
menu_current:
    mov edi, [menu_issue]
    test edi, edi
    jz .draft
    call find_view_issue
    test rax, rax
    jz .none
    mov ecx, [menu_kind]
    movzx edx, byte [rax + CI_STATUS]
    cmp ecx, MK_STATUS
    je .edx
    movzx edx, byte [rax + CI_PRIORITY]
    cmp ecx, MK_PRIORITY
    je .edx
    mov edx, [rax + CI_ASSIGNEE]
    cmp ecx, MK_ASSIGNEE
    je .edx
    movzx edx, byte [rax + CI_PROJECT]
    cmp ecx, MK_PROJECT
    je .edx
    movzx edx, word [rax + CI_LABELS]
.edx:
    mov eax, edx
    ret
.draft:
    mov ecx, [menu_kind]
    cmp ecx, MK_LABELS
    ja .none
    mov eax, [new_status + rcx * 4]
    ret
.none:
    mov eax, -1
    ret

; Adds an item if it matches the filter text.
; rdi = text, esi = length, edx = value, ecx = icon, r8d = icon arg,
; r9d = checked | hint << 8
push_item:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    push r9
    push r9
    cmp dword [menu_count], MENU_MAX
    jae .skip
    cmp r14d, IC_PLUS
    je .add                                 ; "create" items carry the filter text itself
    cmp r14d, IC_ISSUE
    je .add
    mov rdi, rbx
    mov esi, r12d
    call matches_filter
    test eax, eax
    jz .skip
.add:
    mov eax, [menu_count]
    inc dword [menu_count]
    imul eax, eax, MI_SIZE
    lea rax, [menu_items + rax]
    mov [rax + MI_TEXT], rbx
    mov [rax + MI_LEN], r12d
    mov [rax + MI_ICON], r14d
    mov [rax + MI_ICON_ARG], r15d
    mov [rax + MI_VALUE], r13d
    mov rcx, [rsp]
    mov [rax + MI_CHECK], cl
    mov [rax + MI_HINT], ch
    mov ecx, [menu_group]
    mov [rax + MI_GROUP], cl
.skip:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi = text, esi = length -> eax = 1 if the menu's filter text is in it, any case
matches_filter:
    mov rdx, [fields + F_MENU * FD_SIZE + FD_BUF]
    mov ecx, [fields + F_MENU * FD_SIZE + FD_LEN]
    mov eax, 1
    test ecx, ecx
    jz .done
    xor r8d, r8d                            ; start in the text
.start:
    mov eax, esi
    sub eax, r8d
    cmp eax, ecx
    jl .no
    xor r9d, r9d
.char:
    cmp r9d, ecx
    jae .yes
    lea eax, [r8d + r9d]
    movzx eax, byte [rdi + rax]
    movzx r10d, byte [rdx + r9]
    or eax, 0x20
    or r10d, 0x20
    cmp eax, r10d
    jne .next_start
    inc r9d
    jmp .char
.next_start:
    inc r8d
    jmp .start
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
.done:
    ret

; rdi = names (labels or projects), esi = slot size, edx = slot count
; -> eax = 1 if one is named exactly the filter text, any case
filter_names_exist:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
.slot:
    test r13d, r13d
    jz .no
    movzx esi, byte [rbx + LB_NAME_LEN]
    cmp esi, [fields + F_MENU * FD_SIZE + FD_LEN]
    jne .next
    lea rdi, [rbx + LB_NAME]
    call matches_filter
    test eax, eax
    jnz .done
.next:
    add rbx, r12
    dec r13d
    jmp .slot
.no:
    xor eax, eax
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Fills menu_items for the open menu and its filter text.
build_menu:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov dword [menu_count], 0
    mov dword [menu_group], 0
    call menu_current
    mov r15d, eax
    mov eax, [menu_kind]
    cmp eax, MK_STATUS
    je .status
    cmp eax, MK_PRIORITY
    je .priority
    cmp eax, MK_ASSIGNEE
    je .assignee
    mov edi, r15d
    cmp eax, MK_PROJECT
    je .named
    cmp eax, MK_LABELS
    je .named
    cmp eax, MK_FILTER
    je .filter
    call menu_command_items
    jmp .done
.named:
    call menu_named_items
    jmp .done
.filter:
    call menu_filter_items
    jmp .done

.status:
    xor ebx, ebx
.status_item:
    movzx r12d, byte [board_order + rbx]
    mov edi, r12d
    call status_name
    mov rdi, rsi
    mov esi, edx
    mov edx, r12d
    mov ecx, IC_STATUS
    mov r8d, r12d
    xor r9d, r9d
    cmp r12d, r15d
    sete r9b
    call push_item
    inc ebx
    cmp ebx, STATUS_COUNT
    jb .status_item
    jmp .done

.priority:
    xor ebx, ebx
.priority_item:
    mov edi, ebx
    call priority_name
    mov rdi, rsi
    mov esi, edx
    mov edx, ebx
    mov ecx, IC_PRIORITY
    mov r8d, ebx
    xor r9d, r9d
    cmp ebx, r15d
    sete r9b
    call push_item
    inc ebx
    cmp ebx, PRIO_COUNT
    jb .priority_item
    jmp .done

.assignee:
    lea rdi, [s_no_assignee]
    mov esi, s_no_assignee_len
    xor edx, edx
    mov ecx, IC_AVATAR
    xor r8d, r8d
    xor r9d, r9d
    test r15d, r15d
    sete r9b
    call push_item
    lea rbx, [members]
    mov ebp, [member_count]
.member:
    test ebp, ebp
    jz .done
    lea rdi, [rbx + CM_NAME]
    movzx esi, byte [rbx + CM_NAME_LEN]
    mov edx, [rbx + CM_ID]
    mov ecx, IC_AVATAR
    mov r8d, edx
    xor r9d, r9d
    cmp edx, r15d
    sete r9b
    call push_item
    add rbx, CM_SIZE
    dec ebp
    jmp .member

.done:
    mov eax, [menu_count]
    dec eax
    mov ecx, [menu_sel]
    cmp ecx, eax
    cmovg ecx, eax
    xor eax, eax
    cmp ecx, eax
    cmovl ecx, eax
    mov [menu_sel], ecx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret


; The project or label menu's items, and one to create what the filter
; names if nothing has that name. edi = the current value
menu_named_items:
    push rbx
    push rbp
    push r12
    push r13
    push r15
    mov r15d, edi
    cmp dword [menu_kind], MK_LABELS
    je .labels
    lea rdi, [s_no_project]
    mov esi, s_no_project_len
    xor edx, edx
    mov ecx, IC_DOT
    mov r8d, C_FAINT
    xor r9d, r9d
    test r15d, r15d
    sete r9b
    call push_item
    lea rbx, [view_projects]
    mov ebp, 1
.project_item:
    movzx esi, byte [rbx + LB_NAME_LEN]
    test esi, esi
    jz .next_project
    lea rdi, [rbx + LB_NAME]
    mov edx, ebp
    mov ecx, IC_DOT
    mov r8d, [rbx + LB_COLOR]
    xor r9d, r9d
    cmp ebp, r15d
    sete r9b
    call push_item
.next_project:
    add rbx, PJ_SIZE
    inc ebp
    cmp ebp, PROJECT_SLOTS
    jbe .project_item
    lea rdi, [view_projects]
    mov esi, PJ_SIZE
    mov edx, PROJECT_SLOTS
    lea r12, [s_create_project]
    mov r13d, s_create_project_len
    jmp .create

.labels:
    lea rbx, [view_labels]
    xor ebp, ebp
.label_item:
    movzx esi, byte [rbx + LB_NAME_LEN]
    test esi, esi
    jz .next_label
    lea rdi, [rbx + LB_NAME]
    mov edx, ebp
    mov ecx, IC_DOT
    mov r8d, [rbx + LB_COLOR]
    xor r9d, r9d
    bt r15d, ebp
    setc r9b
    call push_item
.next_label:
    add rbx, LB_SIZE
    inc ebp
    cmp ebp, LABEL_SLOTS
    jb .label_item
    lea rdi, [view_labels]
    mov esi, LB_SIZE
    mov edx, LABEL_SLOTS
    lea r12, [s_create_label]
    mov r13d, s_create_label_len
.create:
    ; Typed a name nothing has: offer to create it.
    cmp dword [fields + F_MENU * FD_SIZE + FD_LEN], 0
    je .out
    call filter_names_exist
    test eax, eax
    jnz .out
    mov rdi, r12
    mov esi, r13d
    xor edx, edx
    mov ecx, IC_PLUS
    xor r8d, r8d
    xor r9d, r9d
    call push_item
    jmp .out
.out:
    pop r15
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The filter menu's items: labels, projects, priorities, then who it's
; assigned to. edi is unused, like
; the other item builders take it
menu_filter_items:
    push rbx
    push rbp
    push r12
    push r13
    push r15
    mov r15d, edi
    mov dword [menu_group], FG_LABEL
    lea rbx, [view_labels]
    xor ebp, ebp
.filter_label:
    movzx esi, byte [rbx + LB_NAME_LEN]
    test esi, esi
    jz .next_filter_label
    lea rdi, [rbx + LB_NAME]
    mov edx, ebp
    not edx                                 ; labels are negative, projects positive
    mov ecx, IC_DOT
    mov r8d, [rbx + LB_COLOR]
    xor r9d, r9d
    cmp ebp, [filter_label]
    sete r9b
    call push_item
.next_filter_label:
    add rbx, LB_SIZE
    inc ebp
    cmp ebp, LABEL_SLOTS
    jb .filter_label
    mov dword [menu_group], FG_PROJECT
    lea rbx, [view_projects]
    mov ebp, 1
.filter_project:
    movzx esi, byte [rbx + LB_NAME_LEN]
    test esi, esi
    jz .next_filter_project
    lea rdi, [rbx + LB_NAME]
    mov edx, ebp
    mov ecx, IC_DOT
    mov r8d, [rbx + LB_COLOR]
    xor r9d, r9d
    cmp ebp, [filter_project]
    sete r9b
    call push_item
.next_filter_project:
    add rbx, PJ_SIZE
    inc ebp
    cmp ebp, PROJECT_SLOTS
    jbe .filter_project
    mov dword [menu_group], FG_PRIORITY
    xor ebp, ebp
.filter_priority:
    mov edi, ebp
    call priority_name
    mov rdi, rsi
    mov esi, edx
    lea edx, [ebp + FILTER_PRIORITY]
    mov ecx, IC_PRIORITY
    mov r8d, ebp
    xor r9d, r9d
    cmp ebp, [filter_priority]
    sete r9b
    call push_item
    inc ebp
    cmp ebp, PRIO_COUNT
    jb .filter_priority
    mov dword [menu_group], FG_ASSIGNEE
    lea rdi, [s_no_assignee]
    mov esi, s_no_assignee_len
    mov edx, FILTER_ASSIGNEE
    mov ecx, IC_AVATAR
    xor r8d, r8d
    xor r9d, r9d
    cmp dword [filter_assignee], 0
    sete r9b
    call push_item
    lea rbx, [members]
    mov ebp, [member_count]
.filter_member:
    test ebp, ebp
    jz .out
    lea rdi, [rbx + CM_NAME]
    movzx esi, byte [rbx + CM_NAME_LEN]
    mov r8d, [rbx + CM_ID]
    lea edx, [r8d + FILTER_ASSIGNEE]
    mov ecx, IC_AVATAR
    xor r9d, r9d
    cmp r8d, [filter_assignee]
    sete r9b
    call push_item
    add rbx, CM_SIZE
    dec ebp
    jmp .filter_member
.out:
    mov dword [menu_group], 0
    pop r15
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The command menu's items: the commands that apply now, then the teams.
; edi is unused, like the other item builders take it
menu_command_items:
    push rbx
    push rbp
    push r12
    push r13
    push r15
    mov r15d, edi
    call target_issue
    mov r12d, eax
    lea rbx, [commands]
.command:
    cmp qword [rbx], 0
    je .teams
    movzx eax, byte [rbx + 17]
    cmp eax, WHEN_ISSUE
    jne .other
    test r12d, r12d
    jz .next_command
    jmp .add_command
.other:
    cmp byte [menu_context], 0              ; a right click's menu has only the issue's
    jne .next_command
.when_list:
    cmp eax, WHEN_LIST
    jne .when_board
    cmp byte [board], 0
    jne .next_command
.when_board:
    cmp eax, WHEN_BOARD
    jne .when_filtered
    cmp byte [board], 0
    je .next_command
.when_filtered:
    cmp eax, WHEN_FILTERED
    jne .add_command
    call filtered
    test eax, eax
    jz .next_command
.add_command:
    mov rdi, [rbx]
    mov esi, [rbx + 8]
    mov edx, [rbx + 12]
    mov ecx, IC_GLYPH
    movzx r8d, byte [rbx + 18]
    movzx r9d, byte [rbx + 16]
    shl r9d, 8
    call push_item
.next_command:
    add rbx, COMMAND_SIZE
    jmp .command
.teams:
    cmp byte [menu_context], 0
    jne .context_out
    lea rbx, [teams]
    xor ebp, ebp
.team:
    cmp ebp, [team_count]
    jae .out
    lea rdi, [rbx + CO_NAME]
    movzx esi, byte [rbx + CO_NAME_LEN]
    lea edx, [ebp + CMD_TEAM]
    mov ecx, IC_DOT
    mov r8d, C_ACCENT
    xor r9d, r9d
    mov eax, [rbx + CO_ID]
    cmp eax, [current_team]
    sete r9b
    call push_item
    add rbx, CO_SIZE
    inc ebp
    jmp .team
.out:
    call menu_issue_items
.context_out:
    pop r15
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The command menu's search: the team's issues with the filter text in their
; title or ID, after the commands.
menu_issue_items:
    cmp dword [fields + F_MENU * FD_SIZE + FD_LEN], 0
    je .none
    push rbx
    push rbp
    push r12
    lea rbx, [view_issues]
    mov ebp, [view_count]
    xor r12d, r12d                          ; results so far
.issue:
    test ebp, ebp
    jz .done
    cmp r12d, ISSUE_RESULTS
    jae .done
    test dword [rbx + CI_ID], PENDING_ID
    jnz .next                               ; nothing to open yet
    lea rdi, [scratch]
    mov rsi, rbx
    call put_issue_id
    lea rsi, [scratch]
    sub rdi, rsi
    xchg rdi, rsi
    call matches_filter
    test eax, eax
    jnz .add
    lea rdi, [rbx + CI_TITLE]
    movzx esi, byte [rbx + CI_TITLE_LEN]
    call matches_filter
    test eax, eax
    jz .next
.add:
    lea rdi, [rbx + CI_TITLE]
    movzx esi, byte [rbx + CI_TITLE_LEN]
    mov edx, [rbx + CI_ID]
    or edx, CMD_ISSUE
    mov ecx, IC_ISSUE
    movzx r8d, byte [rbx + CI_STATUS]
    xor r9d, r9d
    call push_item
    inc r12d
.next:
    add rbx, CI_SIZE
    dec ebp
    jmp .issue
.done:
    pop r12
    pop rbp
    pop rbx
.none:
    ret

; A searched issue's ID, at the right end of its menu row.
; edi = issue id, esi = the row's right edge, edx = baseline
draw_menu_issue_id:
    push rbx
    push r12
    push r13
    mov r12d, esi
    mov r13d, edx
    call find_view_issue
    test rax, rax
    jz .done
    lea rdi, [scratch]
    mov rsi, rax
    call put_issue_id
    lea rax, [scratch]
    sub rdi, rax
    mov ebx, edi
    lea rdi, [scratch]
    mov esi, ebx
    mov edx, ST_BODY
    call text_width
    mov edi, r12d
    sub edi, eax
    mov esi, r13d
    lea rdx, [scratch]
    mov ecx, ebx
    mov r8d, INK(C_DIM, ST_BODY)
    call draw_text
.done:
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
menu_check:     dd 0, 16, 10, 24, 26, 6
section .text

; The open menu, over a darkened window.
draw_menu:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 16
    call build_menu
    mov dword [menu_w], MENU_W
    cmp byte [menu_context], 0
    jne .context
    call shade_screen
    jmp .shaded
.context:
    mov dword [menu_w], MENU_CTX_W
.shaded:
    xor edi, edi
    xor esi, esi
    mov edx, [win_w]
    mov ecx, [win_h]
    mov r8d, A_DISMISS
    xor r9d, r9d
    call add_hit

    ; The filter's placeholder says what the menu does.
    mov eax, [menu_kind]
    shl eax, 4
    mov rcx, [menu_hints + rax]
    mov [fields + F_MENU * FD_SIZE + FD_HINT], rcx
    mov ecx, [menu_hints + rax + 8]
    mov [fields + F_MENU * FD_SIZE + FD_HINT_LEN], ecx

    ; Keep the selection in the visible rows.
    mov eax, [menu_sel]
    cmp eax, [menu_scroll]
    jge .below
    mov [menu_scroll], eax
.below:
    sub eax, MENU_SHOWN - 1
    cmp eax, [menu_scroll]
    jle .scrolled
    mov [menu_scroll], eax
.scrolled:
    mov ebp, [menu_count]
    sub ebp, [menu_scroll]
    cmp ebp, MENU_SHOWN
    jle .rows_known
    mov ebp, MENU_SHOWN
.rows_known:
    mov eax, 1                              ; an empty menu still has room to say so
    cmp ebp, eax
    cmovl ebp, eax
    mov r12d, [win_w]                       ; x
    sub r12d, [menu_w]
    sar r12d, 1
    mov r13d, 90                            ; y
    xor r14d, r14d                          ; context line height
    cmp dword [menu_issue], 0
    je .box
    mov r14d, 30
.box:
    imul ecx, ebp, MENU_ROW_H
    lea ecx, [ecx + r14d + 66]
    mov [rsp], ecx                          ; menu height
    cmp byte [menu_context], 0
    je .placed
    ; At the pointer, kept inside the window.
    mov r12d, [win_w]
    sub r12d, [menu_w]
    sub r12d, 8
    mov eax, [menu_ax]
    cmp eax, r12d
    cmovl r12d, eax
    mov r13d, [win_h]
    sub r13d, ecx
    sub r13d, 8
    mov eax, [menu_ay]
    cmp eax, r13d
    cmovl r13d, eax
    mov eax, 8
    cmp r13d, eax
    cmovl r13d, eax
.placed:
    mov edi, r12d
    mov esi, r13d
    mov edx, [menu_w]
    mov r8d, C_LINE
    mov r9d, C_RAISED
    mov r10d, 10
    call outline_rrect
    mov edi, r12d
    mov esi, r13d
    mov edx, [menu_w]
    mov ecx, [rsp]
    mov r8d, A_BLOCK
    xor r9d, r9d
    call add_hit

    test r14d, r14d
    jz .input
    mov edi, [menu_issue]                   ; which issue this changes
    call find_view_issue
    test rax, rax
    jz .input
    mov rbx, rax
    lea rdi, [scratch]
    mov rsi, rbx
    call put_issue_id
    mov byte [rdi], ' '
    inc rdi
    lea rsi, [rbx + CI_TITLE]
    movzx edx, byte [rbx + CI_TITLE_LEN]
    call put_mem
    lea rdx, [scratch]
    mov rcx, rdi
    sub rcx, rdx
    lea edi, [r12d + 16]
    lea esi, [r13d + 24]
    mov r8d, INK(C_DIM, ST_SMALL)
    mov r9d, [menu_w]
    sub r9d, 32
    call draw_text_fit
.input:
    mov edi, F_MENU
    lea esi, [r12d + 18]
    lea edx, [r13d + r14d + 30]
    mov ecx, [menu_w]
    sub ecx, 36
    call draw_field
    lea edi, [r12d + 1]
    lea esi, [r13d + r14d + 50]
    mov edx, [menu_w]
    sub edx, 2
    mov ecx, 1
    mov r8d, C_LINE
    call fill_rect
    mov edi, r12d
    lea esi, [r13d + r14d + 58]
    call draw_menu_rows
    add rsp, 16
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The menu's visible items, from menu_scroll down, or a note that nothing
; matches. edi = the menu's x, esi = the first row's top
draw_menu_rows:
    push rbx
    push rbp
    push r12
    push r13
    push r15
    mov r12d, edi
    mov r15d, esi
    cmp dword [menu_count], 0
    jne .rows
    lea edi, [r12d + 20]
    lea esi, [r15d + 23]
    lea rdx, [s_no_results]
    mov ecx, s_no_results_len
    mov r8d, INK(C_FAINT, ST_BODY)
    call draw_text
    jmp .done
.rows:
    mov r13d, [menu_count]
    sub r13d, [menu_scroll]
    mov eax, MENU_SHOWN
    cmp r13d, eax
    cmovg r13d, eax
    mov ebx, [menu_scroll]
.row:
    test r13d, r13d
    jz .done
    mov r8d, C_SELECT
    cmp ebx, [menu_sel]
    je .highlight
    mov edi, A_MENU_ITEM
    mov esi, ebx
    call hovering
    test eax, eax
    jz .item
    mov r8d, C_HOVER
.highlight:
    lea edi, [r12d + 6]
    mov esi, r15d
    mov edx, [menu_w]
    sub edx, 12
    mov ecx, MENU_ROW_H
    mov r9d, 6
    call fill_rrect
.item:
    lea edi, [r12d + 6]
    mov esi, r15d
    mov edx, [menu_w]
    sub edx, 12
    mov ecx, MENU_ROW_H
    mov r8d, A_MENU_ITEM
    mov r9d, ebx
    call add_hit
    imul eax, ebx, MI_SIZE
    lea rbp, [menu_items + rax]
    mov rdi, rbp
    lea esi, [r12d + 20]
    lea edx, [r15d + 11]
    call draw_item_icon
    mov rdx, [rbp + MI_TEXT]
    mov ecx, [rbp + MI_LEN]
    lea edi, [r12d + 46]
    lea esi, [r15d + 23]
    mov r8d, INK(C_TEXT, ST_BODY)
    mov r9d, [menu_w]
    sub r9d, 66
    cmp dword [rbp + MI_ICON], IC_ISSUE
    jne .text
    mov r9d, [menu_w]                       ; room for the ID
    sub r9d, 160
.text:
    call draw_text_fit
    cmp dword [rbp + MI_ICON], IC_ISSUE
    jne .create
    mov edi, [rbp + MI_VALUE]
    and edi, ~CMD_ISSUE
    mov esi, r12d
    add esi, [menu_w]
    sub esi, 20
    lea edx, [r15d + 23]
    call draw_menu_issue_id
    jmp .check
.create:
    add eax, r12d
    add eax, 46
    cmp dword [rbp + MI_ICON], IC_PLUS
    jne .check
    mov edi, eax                            ; the name being created
    lea esi, [r15d + 23]
    mov rdx, [fields + F_MENU * FD_SIZE + FD_BUF]
    mov ecx, [fields + F_MENU * FD_SIZE + FD_LEN]
    mov r8d, INK(C_DIM, ST_BODY)
    call draw_text
.check:
    movzx eax, byte [rbp + MI_GROUP]
    test eax, eax
    jz .checkmark
    ; What it filters by, dim at the right, left of the check if there is one.
    dec eax
    shl eax, 4
    lea rcx, [group_names]
    mov rdx, [rcx + rax]
    mov ecx, [rcx + rax + 8]
    mov edi, r12d
    add edi, [menu_w]
    sub edi, 20
    cmp byte [rbp + MI_CHECK], 0
    je .group
    sub edi, 36
.group:
    lea esi, [r15d + 23]
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_link
.checkmark:
    cmp byte [rbp + MI_CHECK], 0
    je .hint
    mov edx, r12d
    add edx, [menu_w]
    sub edx, 40
    lea ecx, [r15d + 6]
    lea rdi, [menu_check]
    mov esi, 3
    mov r8d, C_TEXT
    mov r9d, 6
    call aa_polyline
.hint:
    movzx edx, byte [rbp + MI_HINT]
    test edx, edx
    jz .next
    mov edi, r12d
    add edi, [menu_w]
    sub edi, 40
    lea esi, [r15d + 9]
    call draw_keycap
.next:
    add r15d, MENU_ROW_H
    inc ebx
    dec r13d
    jmp .row
.done:
    pop r15
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
