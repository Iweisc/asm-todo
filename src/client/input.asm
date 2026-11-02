; Keys and clicks.

section .rodata
label_palette:  dd 0xeb5757, 0xf2994a, 0xf2c94c, 0x4cb782, 0x26b5ce, 0x4ea7fc, 0x5e6ad2, 0xbb87fc
text st_no_slots,   "this team has used every label or project slot"
text s_copied,      "copied "

; Fields that Tab moves between: from, to.
tab_pairs:
    dd F_USER, F_PASS, F_PASS, F_USER
    dd F_NEW_TITLE, F_NEW_DESC, F_NEW_DESC, F_NEW_TITLE
    dd F_TEAM_NAME, F_TEAM_KEY, F_TEAM_KEY, F_TEAM_NAME
    dd F_OLD_PASS, F_NEW_PASS, F_NEW_PASS, F_OLD_PASS
    dd -1

section .bss
field_changed:  resb 1

section .text

; Creates a label named after the menu's filter text in the first free slot.
; -> eax = the slot, or -1
create_label:
    xor ecx, ecx
.slot:
    imul eax, ecx, LB_SIZE
    cmp byte [view_labels + rax + LB_NAME_LEN], 0
    je .found
    inc ecx
    cmp ecx, LABEL_SLOTS
    jb .slot
    jmp no_slots
.found:
    mov edi, OP_SET_LABEL
    jmp create_named

; Same for a project. -> eax = its number, or 0
create_project:
    xor ecx, ecx
.slot:
    imul eax, ecx, PJ_SIZE
    cmp byte [view_projects + rax + LB_NAME_LEN], 0
    je .found
    inc ecx
    cmp ecx, PROJECT_SLOTS
    jb .slot
    call no_slots
    xor eax, eax
    ret
.found:
    inc ecx
    mov edi, OP_SET_PROJECT
    call create_named
    xor ecx, ecx
    cmp eax, -1
    cmove eax, ecx
    ret

no_slots:
    lea rsi, [st_no_slots]
    mov edx, st_no_slots_len
    call set_status
    mov eax, -1
    ret

; edi = op kind, ecx = slot as the op numbers it -> eax = that slot, or -1
create_named:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, edi
    mov ebx, ecx
    mov edi, F_MENU
    call field_trimmed
    mov rcx, rsi
    mov r8d, edx
    mov eax, ebx
    and eax, 7
    mov edx, [label_palette + rax * 4]
    mov edi, r12d
    mov esi, ebx
    call sync_set_named
    mov ecx, eax
    mov eax, ebx
    test ecx, ecx
    jnz .done
    mov eax, -1
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; edi = CMD_*
run_command:
    push rbx
    mov ebx, edi
    test ebx, CMD_ISSUE
    jnz .issue
    cmp ebx, CMD_COPY_ID
    je .copy_id
    cmp ebx, CMD_LABELS
    je .labels
    cmp ebx, CMD_PASSWORD
    je .password
    cmp ebx, CMD_NEW_ISSUE
    je .new_issue
    cmp ebx, CMD_LAYOUT
    je .layout
    cmp ebx, CMD_TEAM
    jb .view
    cmp ebx, CMD_NEW_TEAM
    jb .team
    je .new_team
    cmp ebx, CMD_LOGOUT
    je .logout
    cmp ebx, CMD_DELETE
    jb .pick
    je .delete
    cmp ebx, CMD_FILTER
    je .filter
    cmp ebx, CMD_CHAT
    je .chat
    call clear_filters
    jmp .done
.chat:
    xor edi, edi
    call open_chat
    jmp .done
.issue:
    call close_detail
    mov edi, ebx
    and edi, ~CMD_ISSUE
    call open_issue
    jmp .done
.copy_id:
    call copy_issue_id
    jmp .done
.labels:
    call open_labels_modal
    jmp .done
.password:
    call open_password_modal
    jmp .done
.new_issue:
    call default_status
    mov edi, eax
    call open_create
    jmp .done
.layout:
    xor byte [board], 1
    jmp .done
.view:
    lea edi, [ebx - CMD_VIEW]
    call set_view
    jmp .done
.team:
    lea eax, [ebx - CMD_TEAM]
    imul eax, eax, CO_SIZE
    mov edi, [teams + rax + CO_ID]
    call select_team
    jmp .done
.new_team:
    call open_team_modal
    jmp .done
.logout:
    call logout
    jmp .done
.pick:
    lea edi, [ebx - CMD_PICK]
    call pick_for_target
    jmp .done
.delete:
    call target_issue
    test eax, eax
    jz .done
    mov edi, eax
    call sync_delete_issue
    call close_detail
    jmp .done
.filter:
    mov edi, MK_FILTER
    xor esi, esi
    call open_menu
.done:
    mov byte [need_redraw], 1
    pop rbx
    ret

; Puts the open or selected issue's ID, like ENG-12, on the clipboard.
copy_issue_id:
    push rbx
    push r12
    sub rsp, 8
    call target_issue
    test eax, eax
    jz .done
    test eax, PENDING_ID
    jnz .done                               ; no number until the server has it
    mov edi, eax
    call find_view_issue
    test rax, rax
    jz .done
    mov r12, rax
    lea rdi, [scratch]
    lea rsi, [s_copied]
    mov edx, s_copied_len
    call put_mem
    mov rbx, rdi                            ; where the ID starts
    mov rsi, r12
    call put_issue_id
    mov r12, rdi                            ; and ends
    mov rsi, rbx
    mov edx, r12d
    sub edx, ebx
    call clip_copy
    lea rsi, [scratch]
    mov edx, r12d
    sub edx, esi
    call set_status
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -> eax = the status a new issue starts in for the current view
default_status:
    mov eax, STATUS_TODO
    mov ecx, STATUS_BACKLOG
    cmp dword [view_mode], V_BACKLOG
    cmove eax, ecx
    ret

; edi = V_*
set_view:
    mov [view_mode], edi
    mov dword [scroll_y], 0
    mov byte [list_dirty], 1
    jmp close_detail

; Turns every filter off.
clear_filters:
    mov dword [filter_label], -1
    mov dword [filter_priority], -1
    mov dword [filter_assignee], -1
    mov dword [filter_project], 0
    mov byte [list_dirty], 1
    ret

logout:
    call sync_logout
    mov byte [modal], M_NONE
    mov byte [menu_open], 0
    mov dword [focus], F_USER
    ret

; A button press: does whatever the region under the pointer is for.
ui_click:
    call update_hover
    mov byte [need_redraw], 1
    mov dword [status_len], 0               ; clicking dismisses the message
    mov eax, [hover_action]
    mov edi, [hover_arg]
    cmp eax, A_DELETE
    je .armed
    mov dword [delete_armed], 0             ; any other click backs out of deleting
.armed:
    cmp eax, A_DELETE_COMMENT
    je .comment_armed
    mov dword [comment_armed], 0
.comment_armed:
    cmp eax, A_CHANGE_PASSWORD
    ja .done
    jmp [.table + rax * 8]
.table:
    dq .nothing, .done, .field, .login, .signup, .team, .view, .project
    dq .new_issue, open_team_modal, logout, .remove, .leave, .issue, .layout, .filter
    dq .unfilter, .pick, choose_item, .dismiss, submit_create, submit_team, close_detail, .delete
    dq .row_status, .row_priority, open_chat, .nothing, start_comment_edit, click_delete_comment
    dq .dismiss, start_rename, click_remove_named, submit_password
.nothing:
    ; Clicking empty space leaves whatever field was being edited.
    cmp dword [focus], F_PASS
    jbe .done
    mov edi, F_NONE
    jmp set_focus
.field:
    jmp click_field
.login:
    mov edi, MSG_LOGIN
    jmp do_auth
.signup:
    mov edi, MSG_REGISTER
    jmp do_auth
.team:
    jmp select_team
.view:
    jmp set_view
.project:
    cmp edi, [filter_project]
    jne .set_project
    xor edi, edi                            ; clicking the filtered project again clears it
.set_project:
    mov [filter_project], edi
    mov dword [scroll_y], 0
    mov byte [list_dirty], 1
    jmp close_detail
.new_issue:
    test edi, edi                           ; the sidebar button passes -1: whatever the view suggests
    jns .create
    call default_status
    mov edi, eax
.create:
    jmp open_create
.remove:
    jmp sync_remove_member
.leave:
    mov edi, [my_id]
    jmp sync_remove_member
.issue:
    cmp byte [board], 0
    je open_issue
    test edi, PENDING_ID
    jnz .done                               ; not created yet, so it can't move or open
    ; Board cards open on release instead, so they can be dragged first.
    mov [drag_id], edi
    mov [sel_id], edi
    mov edi, [pointer_x]
    mov esi, [pointer_y]
    mov [drag_from_x], edi
    mov [drag_from_y], esi
    call hit_at
    mov ecx, [pointer_x]
    sub ecx, [rax + HIT_X]
    mov [drag_dx], ecx
    mov ecx, [pointer_y]
    sub ecx, [rax + HIT_Y]
    mov [drag_dy], ecx
    ret
.layout:
    mov [board], dil
    ret
.filter:
    mov edi, MK_FILTER
    xor esi, esi
    jmp open_menu
.unfilter:
    mov byte [list_dirty], 1
    cmp edi, 1
    je .unfilter_project
    ja .unfilter_more
    mov dword [filter_label], -1
    ret
.unfilter_project:
    mov dword [filter_project], 0
    ret
.unfilter_more:
    lea rax, [filter_priority]
    lea rcx, [filter_assignee]
    cmp edi, 3
    cmove rax, rcx
    mov dword [rax], -1
    ret
.pick:
    xor esi, esi
    cmp byte [modal], M_CREATE
    je .open_pick
    mov esi, [detail_issue]
.open_pick:
    jmp open_menu
.dismiss:
    cmp byte [menu_open], 0
    jne close_menu
    jmp close_modal
.delete:
    mov edi, [detail_issue]
    cmp edi, [delete_armed]
    je .confirmed
    mov [delete_armed], edi
    ret
.confirmed:
    mov dword [delete_armed], 0
    call sync_delete_issue
    jmp close_detail
.row_status:
    mov [sel_id], edi
    mov esi, edi
    mov edi, MK_STATUS
    jmp open_menu
.row_priority:
    mov [sel_id], edi
    mov esi, edi
    mov edi, MK_PRIORITY
    jmp open_menu
.done:
    ret

; Drops a dragged card on the column under the pointer, or opens a card
; that was only clicked.
ui_release:
    push rbx
    push r12
    sub rsp, 8
    mov dword [sel_drag], F_NONE
    mov ebx, [drag_id]
    test ebx, ebx
    jz .done
    movzx r12d, byte [drag_moving]
    call cancel_drag
    mov edi, ebx
    test r12d, r12d
    jz .open
    call drop_column
    cmp eax, -1
    je .done
    movzx r12d, byte [board_order + rax]
    mov edi, ebx
    call find_view_issue
    test rax, rax
    jz .done                                ; deleted while it was held
    cmp [rax + CI_STATUS], r12b
    je .done
    mov edi, ebx
    mov esi, FIELD_STATUS
    mov edx, r12d
    call sync_set_field
    jmp .done
.open:
    call open_issue
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; edi = scroll amount in pixels, as reported by the compositor,
; esi = 1 when it's sideways
ui_scroll:
    cmp byte [menu_open], 0
    jne .menu
    cmp byte [modal], M_NONE
    jne .done
    lea edi, [edi + edi * 2]
    cmp dword [pointer_x], SIDEBAR_W
    jl .sidebar
    cmp byte [chat_open], 0
    jne .chat
    cmp dword [detail_issue], 0
    jne .detail
    cmp byte [board], 0
    je .list
    test esi, esi
    jnz .sideways
    test dword [modifiers], MOD_SHIFT       ; Shift turns the wheel sideways
    jz .list
.sideways:
    add [board_x], edi
    jmp .redraw
.sidebar:
    lea rax, [side_scroll]
    jmp .vertical
.detail:
    lea rax, [detail_scroll]
    jmp .vertical
.chat:
    neg edi                                 ; it counts up from the bottom
    lea rax, [chat_scroll]
    jmp .vertical
.list:
    lea rax, [scroll_y]
.vertical:
    test esi, esi                           ; only the board scrolls sideways
    jnz .done
    add [rax], edi
.redraw:
    mov byte [need_redraw], 1
.done:
    ret
.menu:
    test esi, esi
    jz menu_wheel_by
    ret

; edi = key code -> eax = the character it types with the current modifiers, or 0
key_char:
    xor eax, eax
    test dword [modifiers], MOD_CTRL | MOD_ALT
    jnz .done
    cmp edi, 128
    jae .done
    lea rax, [keymap_plain]
    lea rcx, [keymap_shift]
    test dword [modifiers], MOD_SHIFT
    cmovnz rax, rcx
    movzx eax, byte [rax + rdi]
    test dword [locked_modifiers], MOD_CAPS
    jz .done
    mov ecx, eax
    or ecx, 0x20
    sub ecx, 'a'
    cmp ecx, 'z' - 'a'
    ja .done
    xor eax, 0x20                           ; caps lock flips letter case
.done:
    ret

; Enter, Esc and Tab in the focused field. edi = key code
; -> eax = 1 if handled here
field_command:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, edi
    mov ebx, [focus]
    cmp r12d, KEY_ESC
    je .esc
    cmp r12d, KEY_TAB
    je .tab
    cmp r12d, KEY_ENTER
    je .enter
    cmp r12d, KEY_KPENTER
    jne .not_mine
.enter:
    mov eax, [modifiers]
    cmp ebx, F_USER
    je .enter_user
    cmp ebx, F_PASS
    je .log_in
    cmp ebx, F_MENU
    je .choose
    cmp ebx, F_NEW_TITLE
    je .create
    cmp ebx, F_TEAM_NAME
    je .team
    cmp ebx, F_TEAM_KEY
    je .team
    cmp ebx, F_MEMBER
    je .member
    cmp ebx, F_TITLE
    je .unfocus
    cmp ebx, F_COMMENT
    je .comment
    cmp ebx, F_MESSAGE
    je .message
    cmp ebx, F_EDIT
    je .edit
    cmp ebx, F_RENAME
    je .rename
    cmp ebx, F_OLD_PASS
    je .password
    cmp ebx, F_NEW_PASS
    je .password
    test eax, MOD_CTRL                      ; descriptions: Ctrl+Enter finishes
    jz .newline
    cmp ebx, F_NEW_DESC
    je .create
    jmp .unfocus
.newline:
    mov edi, ebx
    mov esi, 10
    call field_insert
    jmp .handled
.enter_user:
    cmp dword [fields + F_PASS * FD_SIZE + FD_LEN], 0
    jne .log_in
    mov dword [focus], F_PASS
    jmp .handled
.log_in:
    mov edi, MSG_LOGIN
    call do_auth
    jmp .handled
.choose:
    mov edi, [menu_sel]
    call choose_item
    jmp .handled
.create:
    call submit_create
    jmp .handled
.team:
    call submit_team
    jmp .handled
.member:
    ; The box empties when the name joins, so a failed invite keeps it.
    mov edi, F_MEMBER
    call field_trimmed
    test edx, edx
    jz .handled
    call sync_add_member
    jmp .handled
.comment:
    test eax, MOD_SHIFT
    jnz .newline
    mov edi, F_COMMENT
    mov esi, [detail_issue]
    mov edx, OP_COMMENT
    call send_field
    jmp .handled
.edit:
    test eax, MOD_SHIFT
    jnz .newline
    call save_comment_edit
    jmp .handled
.rename:
    call save_rename
    jmp .handled
.password:
    call submit_password
    jmp .handled
.message:
    test eax, MOD_SHIFT
    jnz .newline
    mov dword [chat_scroll], 0              ; back down to the newest
    mov edi, F_MESSAGE
    mov esi, [chat_peer]
    mov edx, OP_MESSAGE
    call send_field
    jmp .handled
.esc:
    mov edi, ebx
    call field_escape
    jmp .handled
.unfocus:
    mov edi, F_NONE
    call set_focus
    jmp .handled
.tab:
    lea rcx, [tab_pairs]
.pair:
    mov edi, [rcx + 4]
    cmp ebx, [rcx]
    je .move
    add rcx, 8
    cmp dword [rcx], -1
    jne .pair
    jmp .handled
.move:
    call set_focus
.handled:
    mov eax, 1
    jmp .done
.not_mine:
    xor eax, eax
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; Esc in the focused field backs out of whatever it's for. edi = the field
field_escape:
    cmp edi, F_PASS
    jbe field_clear
    cmp edi, F_MENU
    je close_menu
    cmp edi, F_MESSAGE                      ; typing anywhere refocuses the box, so leave
    je close_detail
    cmp edi, F_EDIT
    je stop_comment_edit
    cmp edi, F_RENAME
    je stop_rename
    cmp edi, F_OLD_PASS
    jae close_modal
    cmp edi, F_TEAM_KEY
    ja .unfocus
    mov byte [modal], M_NONE                ; F_NEW_TITLE..F_TEAM_KEY
.unfocus:
    cmp edi, F_TITLE
    je .drop
    mov edi, F_NONE
    jmp set_focus
.drop:
    mov dword [focus], F_NONE               ; a title edit is dropped, not saved
    ret

; Sends a comment or message box's text and empties the box.
; edi = field, esi = the issue or peer, edx = OP_COMMENT or OP_MESSAGE
send_field:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    call field_trimmed
    test edx, edx
    jz .done
    mov edi, r12d
    mov ecx, r13d
    call sync_text
    test eax, eax
    jz .done
    mov edi, ebx
    call field_clear
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Menu navigation. edi = key code -> eax = 1 if handled here
menu_key:
    cmp edi, KEY_DOWN
    je .down
    cmp edi, KEY_UP
    je .up
    xor eax, eax
    ret
.down:
    mov eax, [menu_sel]
    inc eax
    cmp eax, [menu_count]
    jae .handled
    mov [menu_sel], eax
    jmp .handled
.up:
    cmp dword [menu_sel], 0
    je .handled
    dec dword [menu_sel]
.handled:
    mov eax, 1
    ret

; Shortcuts, when no field has focus. edi = key code -> eax = 1 to repeat
shortcut:
    push rbx
    call shortcut_key
    mov ebx, eax
    cmp byte [modal], M_NONE                ; a dialog with nothing focused only closes
    jne .in_modal
    test dword [modifiers], MOD_CTRL
    jnz .ctrl
    cmp ebx, KEY_ESC
    je .esc
    cmp ebx, KEY_C
    je .create
    cmp ebx, KEY_J
    je .down
    cmp ebx, KEY_DOWN
    je .down
    cmp ebx, KEY_K
    je .up
    cmp ebx, KEY_UP
    je .up
    cmp ebx, KEY_LEFT
    je .left
    cmp ebx, KEY_RIGHT
    je .right
    cmp ebx, KEY_ENTER
    je .open
    cmp ebx, KEY_KPENTER
    je .open
    mov edi, MK_STATUS
    cmp ebx, KEY_S
    je .pick
    mov edi, MK_PRIORITY
    cmp ebx, KEY_P
    je .pick
    mov edi, MK_ASSIGNEE
    cmp ebx, KEY_A
    je .pick
    mov edi, MK_LABELS
    cmp ebx, KEY_L
    je .pick
    mov edi, MK_PROJECT
    cmp ebx, KEY_M
    je .pick
    jmp .no_repeat
.ctrl:
    cmp ebx, KEY_C
    je .copy_id
    cmp ebx, KEY_B
    jne .no_repeat
    xor byte [board], 1
    jmp .no_repeat
.copy_id:
    call copy_issue_id
    jmp .no_repeat
.esc:
    cmp dword [detail_issue], 0
    jne .close
    cmp dword [sel_id], 0
    je .unfilter
    mov dword [sel_id], 0
    jmp .no_repeat
.unfilter:
    call clear_filters
    jmp .no_repeat
.close:
    call close_detail
    jmp .no_repeat
.create:
    call default_status
    mov edi, eax
    call open_create
    jmp .no_repeat
.down:
    mov edi, 1
    jmp .move
.up:
    mov edi, -1
.move:
    call move_selection
    cmp dword [detail_issue], 0             ; the detail view follows the selection
    je .repeat
    mov edi, [sel_id]
    call open_issue
    jmp .repeat
.left:
    mov edi, -1
    jmp .column
.right:
    mov edi, 1
.column:
    cmp byte [board], 0
    je .no_repeat
    cmp dword [detail_issue], 0
    jne .no_repeat
    call move_column
    jmp .repeat
.open:
    cmp dword [detail_issue], 0
    jne .no_repeat
    mov edi, [sel_id]
    test edi, edi
    jz .no_repeat
    call open_issue
    jmp .no_repeat
.pick:
    call pick_for_target
    jmp .no_repeat
.in_modal:
    cmp ebx, KEY_ESC
    jne .no_repeat
    call close_modal
.no_repeat:
    xor eax, eax
    jmp .done
.repeat:
    mov eax, 1
.done:
    pop rbx
    ret

; edi = key code -> eax = 1 if holding the key should repeat it
ui_key:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov byte [need_redraw], 1
    mov byte [field_changed], 0
    mov dword [status_len], 0               ; any key dismisses the message, like a click
    ; While a card is held, keys could open menus or switch layouts under it.
    ; Only Esc does something: it puts the card back.
    cmp dword [drag_id], 0
    je .not_dragging
    cmp ebx, KEY_ESC
    jne .no_repeat
    call cancel_drag
    jmp .no_repeat
.not_dragging:
    cmp byte [logged_in], 0
    je .field
    test dword [modifiers], MOD_CTRL
    jz .menu
    mov edi, ebx
    call shortcut_key
    cmp eax, KEY_K
    jne .menu
    cmp byte [menu_open], 0                 ; Ctrl+K toggles the command menu
    je .open_commands
    call close_menu
    jmp .no_repeat
.open_commands:
    cmp byte [modal], M_NONE
    jne .no_repeat
    mov edi, MK_COMMAND
    xor esi, esi
    call open_menu
    jmp .no_repeat
.menu:
    cmp byte [menu_open], 0
    je .field
    mov edi, ebx
    call menu_key
    test eax, eax
    jnz .repeat
.field:
    cmp dword [focus], F_NONE
    je .shortcut
    mov edi, ebx
    call field_command
    test eax, eax
    jnz .no_repeat
    mov edi, [focus]
    mov esi, ebx
    call field_key
    mov r12d, eax
    cmp byte [field_changed], 0
    je .typed
    cmp dword [focus], F_MENU
    jne .key_typed
    mov dword [menu_sel], 0                 ; a new filter starts at the top
    mov dword [menu_scroll], 0
.key_typed:
    cmp dword [focus], F_TEAM_KEY
    jne .name_typed
    mov byte [key_edited], 1
.name_typed:
    cmp dword [focus], F_TEAM_NAME
    jne .typed
    call derive_team_key
.typed:
    mov eax, r12d
    jmp .out
.shortcut:
    cmp byte [chat_open], 0
    jne .chat_key
    mov edi, ebx
    call shortcut
    jmp .out
.chat_key:
    ; Nothing's focused in a conversation: Esc leaves it, and anything else
    ; goes to the message box.
    cmp ebx, KEY_ESC
    je .leave_chat
    test dword [modifiers], MOD_CTRL
    jnz .no_repeat
    mov edi, F_MESSAGE
    call set_focus
    cmp ebx, KEY_ENTER
    je .no_repeat
    cmp ebx, KEY_KPENTER
    je .no_repeat
    jmp .field
.leave_chat:
    call close_detail
    jmp .no_repeat
.no_repeat:
    xor eax, eax
    jmp .out
.repeat:
    mov eax, 1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; edi = key code, esi = 1 pressed / 0 released
ui_key_event:
    push rbx
    mov ebx, edi
    test esi, esi
    jz .released
    call ui_key
    test eax, eax
    jz .stop
    cmp dword [repeat_rate], 0
    jle .stop
    mov [repeat_key], ebx
    call now_ms
    movsxd rcx, dword [repeat_delay]
    add rax, rcx
    mov [repeat_next], rax
    jmp .done
.released:
    cmp ebx, [repeat_key]
    jne .done
.stop:
    mov dword [repeat_key], 0
.done:
    pop rbx
    ret

; -> eax = poll timeout in ms, -1 when no key is held
repeat_timeout:
    mov eax, -1
    cmp dword [repeat_key], 0
    je .done
    call now_ms
    mov rcx, [repeat_next]
    sub rcx, rax
    xor eax, eax
    test rcx, rcx
    cmovg eax, ecx
.done:
    ret

repeat_tick:
    cmp dword [repeat_key], 0
    je .done
    cmp dword [repeat_rate], 0
    jle .stop
    call now_ms
    cmp rax, [repeat_next]
    jb .done
    push rax
    mov edi, [repeat_key]
    call ui_key
    pop rcx
    mov eax, 1000
    xor edx, edx
    div dword [repeat_rate]
    add rax, rcx
    mov [repeat_next], rax
.done:
    ret
.stop:
    mov dword [repeat_key], 0
    ret
