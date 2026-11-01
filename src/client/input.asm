; Keys and clicks.

section .rodata
label_palette:  dd 0xeb5757, 0xf2994a, 0xf2c94c, 0x4cb782, 0x26b5ce, 0x4ea7fc, 0x5e6ad2, 0xbb87fc
text st_no_slots,   "this team has used every label or project slot"

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
    call clear_filters
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

clear_filters:
    mov dword [filter_label], -1
    mov dword [filter_project], 0
    mov byte [list_dirty], 1
    ret

logout:
    call sync_logout
    mov byte [modal], M_NONE
    mov byte [menu_open], 0
    mov dword [focus], F_USER
    ret

ui_click:
    call update_hover
    mov byte [need_redraw], 1
    mov dword [status_len], 0               ; clicking dismisses the message
    mov eax, [hover_action]
    mov edi, [hover_arg]
    cmp eax, A_ROW_PRIORITY
    ja .done
    jmp [.table + rax * 8]
.table:
    dq .nothing, .done, .field, .login, .signup, .team, .view, .project
    dq .new_issue, open_team_modal, logout, .remove, .leave, .issue, .layout, .filter
    dq .unfilter, .pick, choose_item, .dismiss, submit_create, submit_team, close_detail, .delete
    dq .row_status, .row_priority
.nothing:
    ; Clicking empty space leaves whatever field was being edited.
    cmp dword [focus], F_PASS
    jbe .done
    mov edi, F_NONE
    jmp set_focus
.field:
    cmp edi, F_TITLE
    je .edit
    cmp edi, F_DESC
    je .edit
    call set_focus
    mov edi, [focus]
    call field_addr
    mov ecx, [rax + FD_LEN]
    mov [rax + FD_CURSOR], ecx
    ret
.edit:
    jmp begin_edit
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
    jmp open_issue
.layout:
    mov [board], dil
    ret
.filter:
    mov edi, MK_FILTER
    xor esi, esi
    jmp open_menu
.unfilter:
    test edi, edi
    jnz .unfilter_project
    mov dword [filter_label], -1
    mov byte [list_dirty], 1
    ret
.unfilter_project:
    mov dword [filter_project], 0
    mov byte [list_dirty], 1
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
    mov byte [modal], M_NONE
    mov edi, F_NONE
    jmp set_focus
.delete:
    mov edi, [detail_issue]
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

; edi = scroll amount in pixels, as reported by the compositor
ui_scroll:
    cmp byte [menu_open], 0
    jne .done
    cmp byte [modal], M_NONE
    jne .done
    lea edi, [edi + edi * 2]
    cmp dword [detail_issue], 0
    jne .detail
    cmp byte [board], 0
    je .list
    test dword [modifiers], MOD_SHIFT
    jz .list
    add [board_x], edi
    jmp .redraw
.detail:
    add [detail_scroll], edi
    jmp .redraw
.list:
    add [scroll_y], edi
.redraw:
    mov byte [need_redraw], 1
.done:
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

; edi = field, esi = character. Inserts at the cursor if there's room.
field_insert:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, esi
    call field_addr
    mov rbx, rax
    mov ecx, [rbx + FD_LEN]
    cmp ecx, [rbx + FD_MAX]
    jae .done
    mov edx, [rbx + FD_CURSOR]
    mov rsi, [rbx + FD_BUF]
    add rsi, rdx
    lea rdi, [rsi + 1]
    sub ecx, edx
    mov edx, ecx
    call memmove
    mov rax, [rbx + FD_BUF]
    mov ecx, [rbx + FD_CURSOR]
    mov [rax + rcx], r12b
    inc dword [rbx + FD_CURSOR]
    inc dword [rbx + FD_LEN]
    mov byte [field_changed], 1
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; Editing keys in a field. edi = field, esi = key code
; -> eax = 1 if holding the key should repeat it
field_key:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, esi
    mov ebx, edi
    mov edi, r12d
    call key_char
    test eax, eax
    jz .special
    mov edi, ebx
    mov esi, eax
    call field_insert
    jmp .repeat
.special:
    mov edi, ebx
    call field_addr
    mov rbx, rax
    cmp r12d, KEY_BACKSPACE
    je .backspace
    cmp r12d, KEY_DELETE
    je .delete
    cmp r12d, KEY_LEFT
    je .left
    cmp r12d, KEY_RIGHT
    je .right
    cmp r12d, KEY_HOME
    je .home
    cmp r12d, KEY_END
    je .end
    jmp .no_repeat
.backspace:
    mov ecx, [rbx + FD_CURSOR]
    test ecx, ecx
    jz .repeat
    dec dword [rbx + FD_CURSOR]
    jmp .remove
.delete:
    mov ecx, [rbx + FD_CURSOR]
    cmp ecx, [rbx + FD_LEN]
    jae .repeat
.remove:
    mov ecx, [rbx + FD_CURSOR]
    mov rdi, [rbx + FD_BUF]
    add rdi, rcx
    lea rsi, [rdi + 1]
    mov edx, [rbx + FD_LEN]
    sub edx, ecx
    dec edx
    call memmove
    dec dword [rbx + FD_LEN]
    mov eax, [rbx + FD_LEN]                 ; don't leave a password's last byte behind
    mov rcx, [rbx + FD_BUF]
    mov byte [rcx + rax], 0
    mov byte [field_changed], 1
    jmp .repeat
.left:
    cmp dword [rbx + FD_CURSOR], 0
    je .repeat
    dec dword [rbx + FD_CURSOR]
    jmp .repeat
.right:
    mov eax, [rbx + FD_CURSOR]
    cmp eax, [rbx + FD_LEN]
    jae .repeat
    inc dword [rbx + FD_CURSOR]
    jmp .repeat
.home:
    mov dword [rbx + FD_CURSOR], 0
    jmp .no_repeat
.end:
    mov eax, [rbx + FD_LEN]
    mov [rbx + FD_CURSOR], eax
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
    mov edi, F_MEMBER
    call field_trimmed
    test edx, edx
    jz .handled
    call sync_add_member
    mov edi, F_MEMBER
    call field_clear
    jmp .handled
.comment:
    test eax, MOD_SHIFT
    jnz .newline
    mov edi, F_COMMENT
    call field_trimmed
    test edx, edx
    jz .handled
    mov edi, [detail_issue]
    call sync_comment
    test eax, eax
    jz .handled
    mov edi, F_COMMENT
    call field_clear
    jmp .handled
.esc:
    cmp ebx, F_PASS
    jbe .clear
    cmp ebx, F_MENU
    je .close_menu
    cmp ebx, F_TEAM_KEY
    jbe .close_modal                        ; F_NEW_TITLE..F_TEAM_KEY
    cmp ebx, F_TITLE
    jne .unfocus
    mov dword [focus], F_NONE               ; a title edit is dropped, not saved
    jmp .handled
.clear:
    mov edi, ebx
    call field_clear
    jmp .handled
.close_menu:
    call close_menu
    jmp .handled
.close_modal:
    mov byte [modal], M_NONE
.unfocus:
    mov edi, F_NONE
    call set_focus
    jmp .handled
.tab:
    ; Pairs of fields that Tab moves between.
    mov edi, F_PASS
    cmp ebx, F_USER
    je .move
    mov edi, F_USER
    cmp ebx, F_PASS
    je .move
    mov edi, F_NEW_DESC
    cmp ebx, F_NEW_TITLE
    je .move
    mov edi, F_NEW_TITLE
    cmp ebx, F_NEW_DESC
    je .move
    mov edi, F_TEAM_KEY
    cmp ebx, F_TEAM_NAME
    je .move
    mov edi, F_TEAM_NAME
    cmp ebx, F_TEAM_KEY
    jne .handled
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
    mov ebx, edi
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
    cmp ebx, KEY_B
    jne .no_repeat
    xor byte [board], 1
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
    cmp byte [logged_in], 0
    je .field
    test dword [modifiers], MOD_CTRL
    jz .menu
    cmp ebx, KEY_K
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
    mov edi, ebx
    call shortcut
    jmp .out
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
