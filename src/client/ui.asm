; The window's state: fields, selection, the list and board, menus and
; modals. Keys and clicks are handled in input.asm, drawing lives in
; widgets.asm (fields, menus, formatting) and views.asm (the screens).
;
; Keyboard first: with no text field focused, letters are shortcuts.
;   c new issue    j/k or arrows move    Enter open    Esc back
;   s status   p priority   a assignee   l labels   m project
;   Ctrl+K command menu    Ctrl+B list or board

%define SIDEBAR_W       232
%define GAP             8               ; around the main panel
%define HEADER_H        44
%define FILTER_H        40
%define ROW_H           38
%define GROUP_H         36
%define PROPS_W         256
%define CARD_GAP        8
%define COL_MIN_W       200
%define LINE_H          20              ; wrapped body text
%define MENU_W          520
%define MENU_ROW_H      36
%define MENU_MAX        96
%define MENU_SHOWN      9               ; rows visible at once
%define MODAL_W         640

%define C_BG            0x0b0c0e
%define C_PANEL         0x131417
%define C_RAISED        0x1a1b1f        ; cards, menus, modals
%define C_HOVER         0x1d1e23
%define C_SELECT        0x23252b
%define C_GROUP         0x17181c
%define C_LINE          0x25272c
%define C_TEXT          0xe6e7ea
%define C_DIM           0x8a8f98
%define C_FAINT         0x5a5e66
%define C_ACCENT        0x5e6ad2
%define C_ACCENT_HI     0x717ce0
%define C_DANGER        0xeb5757
%define C_ONLINE        0x4cb782
%define C_SHADE         0x070809        ; behind a modal

; wp_cursor_shape_device_v1 shapes
%define CURSOR_DEFAULT  1
%define CURSOR_POINTER  4
%define CURSOR_TEXT     9
%define CURSOR_GRABBING 17

%define DRAG_SLOP       4               ; pixels a held card moves before it's dragged

; evdev key codes
%define KEY_ESC         1
%define KEY_BACKSPACE   14
%define KEY_TAB         15
%define KEY_ENTER       28
%define KEY_KPENTER     96
%define KEY_UP          103
%define KEY_HOME        102
%define KEY_LEFT        105
%define KEY_RIGHT       106
%define KEY_END         107
%define KEY_DOWN        108
%define KEY_DELETE      111
%define KEY_A           30
%define KEY_B           48
%define KEY_C           46
%define KEY_J           36
%define KEY_K           37
%define KEY_L           38
%define KEY_M           50
%define KEY_P           25
%define KEY_S           31

; wl_keyboard modifier bits
%define MOD_SHIFT       1
%define MOD_CAPS        2
%define MOD_CTRL        4
%define MOD_ALT         8

; Text fields
%define FD_BUF          0               ; qword
%define FD_MAX          8
%define FD_LEN          12
%define FD_CURSOR       16
%define FD_SCROLL       20              ; first character shown, single-line fields
%define FD_FLAGS        24
%define FD_STYLE        28
%define FD_HINT         32              ; qword, the placeholder
%define FD_HINT_LEN     40
%define FD_SIZE         48
%define FF_MASKED       1
%define FF_MULTILINE    2

%define F_NONE          -1
%define F_USER          0
%define F_PASS          1
%define F_MENU          2               ; the menu's filter
%define F_NEW_TITLE     3
%define F_NEW_DESC      4
%define F_TEAM_NAME     5
%define F_TEAM_KEY      6
%define F_MEMBER        7
%define F_TITLE         8               ; editing the open issue
%define F_DESC          9
%define F_COMMENT       10

; Clickable regions
%define HIT_X           0
%define HIT_Y           4
%define HIT_W           8
%define HIT_H           12
%define HIT_ACTION      16
%define HIT_ARG         20
%define HIT_SIZE        24
%define HIT_MAX         1024

%define A_NONE          0
%define A_BLOCK         1               ; swallows clicks, does nothing
%define A_FIELD         2               ; arg = field
%define A_LOGIN         3
%define A_SIGNUP        4
%define A_TEAM          5               ; arg = team id
%define A_VIEW          6               ; arg = V_*
%define A_PROJECT       7               ; arg = project number, filters by it
%define A_NEW_ISSUE     8               ; arg = status
%define A_NEW_TEAM      9
%define A_LOGOUT        10
%define A_REMOVE        11              ; arg = user id
%define A_LEAVE         12
%define A_ISSUE         13              ; arg = issue id
%define A_LAYOUT        14              ; arg = 0 list, 1 board
%define A_FILTER        15
%define A_UNFILTER      16              ; arg = 0 label, 1 project
%define A_PICK          17              ; arg = MK_*, for the open issue or the draft
%define A_MENU_ITEM     18              ; arg = item index
%define A_DISMISS       19              ; the shade around a modal or menu
%define A_CREATE        20
%define A_CREATE_TEAM   21
%define A_CLOSE         22              ; leaves the detail view
%define A_DELETE        23
%define A_ROW_STATUS    24              ; arg = issue id
%define A_ROW_PRIORITY  25              ; arg = issue id

; Views of a team's issues
%define V_ALL           0
%define V_ACTIVE        1
%define V_BACKLOG       2
%define V_MINE          3

; Modals
%define M_NONE          0
%define M_CREATE        1
%define M_TEAM          2

; Menus. The first five are one less than the FIELD_* they change.
%define MK_STATUS       0
%define MK_PRIORITY     1
%define MK_ASSIGNEE     2
%define MK_PROJECT      3
%define MK_LABELS       4
%define MK_FILTER       5
%define MK_COMMAND      6

%define MI_TEXT         0               ; qword
%define MI_LEN          8
%define MI_ICON         12
%define MI_ICON_ARG     16
%define MI_VALUE        20
%define MI_CHECK        24
%define MI_HINT         25              ; a shortcut letter, 0 for none
%define MI_SIZE         32
%define IC_NONE         0
%define IC_STATUS       1
%define IC_PRIORITY     2
%define IC_AVATAR       3               ; arg = user id
%define IC_DOT          4               ; arg = color
%define IC_PLUS         5

; Command menu entries, in MI_VALUE
%define CMD_NEW_ISSUE   1
%define CMD_LAYOUT      2
%define CMD_VIEW        3               ; + V_*
%define CMD_TEAM        8               ; + index in teams
%define CMD_NEW_TEAM    (CMD_TEAM + USER_TEAM_MAX)
%define CMD_LOGOUT      (CMD_NEW_TEAM + 1)
%define CMD_PICK        (CMD_LOGOUT + 1) ; + MK_*, for the selected issue
%define CMD_DELETE      (CMD_PICK + MK_FILTER)
%define CMD_FILTER      (CMD_DELETE + 1)
%define CMD_CLEAR       (CMD_FILTER + 1)

; Rows of the list view
%define RW_ISSUE        0               ; qword, 0 for a group header
%define RW_STATUS       8
%define RW_COUNT        12              ; issues in the group, for headers
%define RW_SIZE         16
%define ROWS_MAX        (VIEW_MAX + STATUS_COUNT)

section .data

text s_app,             "Issues"
text s_subtitle,        "Log in or sign up to plan and track work with your team."
text s_username,        "Username"
text s_password,        "Password"
text s_log_in,          "Log in"
text s_sign_up,         "Sign up"
text s_checking,        "Checking..."
text s_filter_hint,     "Filter..."
text s_command_hint,    "Type a command or search..."
text s_title_hint,      "Issue title"
text s_desc_hint,       "Add description..."
text s_team_name_hint,  "Team name"
text s_team_key_hint,   "KEY"
text s_member_hint,     "Invite by username"
text s_comment_hint,    "Leave a comment..."

; US layout, indexed by evdev key code. 0 means the key types nothing.
keymap_plain:
    db 0, 0, "1234567890-=", 0, 0
    db "qwertyuiop[]", 0, 0
    db "asdfghjkl;'`", 0, "\"
    db "zxcvbnm,./", 0, "*", 0, " "
    times 128 - ($ - keymap_plain) db 0
keymap_shift:
    db 0, 0, "!@#$%^&*()_+", 0, 0
    db "QWERTYUIOP{}", 0, 0
    db 'ASDFGHJKL:"~', 0, "|"
    db "ZXCVBNM<>?", 0, "*", 0, " "
    times 128 - ($ - keymap_shift) db 0

%macro FIELD 5                          ; buffer, max, flags, style, hint
    dq %1
    dd %2, 0, 0, 0, %3, %4
    dq %5
    dd %5_len, 0
%endmacro

align 8
fields:
    FIELD user_buf, USERNAME_MAX, 0, ST_BODY, s_username
    FIELD pass_buf, PASSWORD_MAX, FF_MASKED, ST_BODY, s_password
    FIELD menu_buf, 40, 0, ST_BODY, s_filter_hint
    FIELD new_title_buf, TITLE_MAX, 0, ST_TITLE, s_title_hint
    FIELD new_desc_buf, DESC_MAX, FF_MULTILINE, ST_BODY, s_desc_hint
    FIELD team_name_buf, TEAMNAME_MAX, 0, ST_BODY, s_team_name_hint
    FIELD team_key_buf, TEAM_KEY_MAX, 0, ST_BODY, s_team_key_hint
    FIELD member_buf, USERNAME_MAX, 0, ST_SMALL, s_member_hint
    FIELD title_buf, TITLE_MAX, 0, ST_TITLE, s_title_hint
    FIELD desc_buf, DESC_MAX, FF_MULTILINE, ST_BODY, s_desc_hint
    FIELD comment_buf, COMMENT_MAX, FF_MULTILINE, ST_BODY, s_comment_hint

focus:          dd F_USER
filter_label:   dd -1                   ; a label slot, or -1
repeat_rate:    dd 25                   ; until the compositor tells us otherwise
repeat_delay:   dd 600

section .bss

user_buf:       resb USERNAME_MAX
pass_buf:       resb PASSWORD_MAX
menu_buf:       resb 40
new_title_buf:  resb TITLE_MAX
new_desc_buf:   resb DESC_MAX
team_name_buf:  resb TEAMNAME_MAX
team_key_buf:   resb TEAM_KEY_MAX
member_buf:     resb USERNAME_MAX
title_buf:      resb TITLE_MAX
desc_buf:       resb DESC_MAX
comment_buf:    resb COMMENT_MAX
mask_buf:       resb PASSWORD_MAX       ; a row of '*' for the password field
alignb 8
server_label:   resq 1                  ; "ip:port" for the status line

hit_count:      resd 1
hits:           resb HIT_MAX * HIT_SIZE
hover_action:   resd 1
hover_arg:      resd 1

pointer_x:      resd 1
pointer_y:      resd 1
pointer_serial: resd 1
pointer_inside: resb 1
alignb 4
cursor_shape:   resd 1
keyboard_focus: resb 1
need_redraw:    resb 1
alignb 4
modifiers:      resd 1
locked_modifiers: resd 1
repeat_key:     resd 1
alignb 8
repeat_next:    resq 1

modal:          resb 1
menu_open:      resb 1
board:          resb 1                  ; board layout instead of the list
board_reveal:   resb 1                  ; scroll the board to the selection next frame
list_dirty:     resb 1
key_edited:     resb 1                  ; the new team's key was typed, stop deriving it
alignb 4
menu_kind:      resd 1
menu_issue:     resd 1                  ; what the menu changes, 0 for the new issue draft
menu_sel:       resd 1
menu_scroll:    resd 1
menu_count:     resd 1
menu_items:     resb MENU_MAX * MI_SIZE
view_mode:      resd 1
filter_project: resd 1                  ; a project number, or 0
sel_id:         resd 1                  ; the selected issue, 0 for none
scroll_y:       resd 1
board_x:        resd 1
board_area:     resd 4                  ; x, y, w, h of the board last frame
board_col_w:    resd 1
drag_id:        resd 1                  ; the board card held down, 0 for none
drag_from_x:    resd 1                  ; where the button went down
drag_from_y:    resd 1
drag_dx:        resd 1                  ; where in the card it was grabbed
drag_dy:        resd 1
drag_moving:    resb 1                  ; it moved past DRAG_SLOP, so release drops it
alignb 4
detail_scroll:  resd 1
content_h:      resd 1                  ; how tall the scrolled content was last frame

; The new issue being written in the create modal.
new_status:     resd 1
new_priority:   resd 1
new_assignee:   resd 1
new_project:    resd 1
new_labels:     resd 1

row_count:      resd 1
rows:           resb ROWS_MAX * RW_SIZE
col_count:      resd STATUS_COUNT
col_items:      resq STATUS_COUNT * VIEW_MAX

scratch:        resb 512

section .text

; edi = field -> rax = its struct
field_addr:
    imul eax, edi, FD_SIZE
    lea rax, [fields + rax]
    ret

; edi = field -> rax = its struct. Wipes the text too, which matters for the password.
field_clear:
    push rbx
    call field_addr
    mov rbx, rax
    mov rdi, [rbx + FD_BUF]
    mov esi, [rbx + FD_MAX]
    call wipe
    xor eax, eax
    mov [rbx + FD_LEN], eax
    mov [rbx + FD_CURSOR], eax
    mov [rbx + FD_SCROLL], eax
    mov rax, rbx
    pop rbx
    ret

; edi = field, rsi = text, edx = length. Replaces its text, cursor at the end.
field_set:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13d, edx
    call field_clear
    mov rbx, rax
    mov eax, [rbx + FD_MAX]
    cmp r13d, eax
    cmova r13d, eax
    mov rdi, [rbx + FD_BUF]
    mov rsi, r12
    mov edx, r13d
    call put_mem
    mov [rbx + FD_LEN], r13d
    mov [rbx + FD_CURSOR], r13d
    pop r13
    pop r12
    pop rbx
    ret

; edi = field -> rsi = text without surrounding spaces and newlines, edx = length
field_trimmed:
    call field_addr
    mov rsi, [rax + FD_BUF]
    mov edx, [rax + FD_LEN]
.front:
    test edx, edx
    jz .done
    cmp byte [rsi], ' '
    ja .back
    inc rsi
    dec edx
    jmp .front
.back:
    cmp byte [rsi + rdx - 1], ' '
    ja .done
    dec edx
    jnz .back
.done:
    ret

; Moves focus, saving an edit to the open issue that loses it. edi = field
set_focus:
    push rbx
    mov ebx, edi
    mov eax, [focus]
    cmp eax, ebx
    je .same
    cmp eax, F_TITLE
    je .commit
    cmp eax, F_DESC
    jne .same
.commit:
    mov edi, eax
    call commit_edit
.same:
    mov [focus], ebx
    mov byte [need_redraw], 1
    pop rbx
    ret

; Sends an edited title or description if it changed. edi = F_TITLE or F_DESC
commit_edit:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov edi, [detail_issue]
    call find_view_issue
    test rax, rax
    jz .done
    mov r12, rax
    cmp ebx, F_TITLE
    jne .desc
    mov edi, F_TITLE
    call field_trimmed
    test edx, edx
    jz .done                                ; an issue needs a title
    movzx ecx, byte [r12 + CI_TITLE_LEN]
    cmp edx, ecx
    jne .send_title
    push rsi
    push rdx
    lea rdi, [r12 + CI_TITLE]
    call mem_eq
    pop rdx
    pop rsi
    test eax, eax
    jnz .done
.send_title:
    mov edi, [detail_issue]
    call sync_set_title
    jmp .done
.desc:
    mov edi, F_DESC
    call field_addr
    mov rsi, [rax + FD_BUF]
    mov edx, [rax + FD_LEN]
    cmp edx, [view_desc_len]
    jne .send_desc
    push rsi
    push rdx
    mov rdi, [view_desc]
    call mem_eq
    pop rdx
    pop rsi
    test eax, eax
    jnz .done
.send_desc:
    mov edi, [detail_issue]
    call sync_set_description
.done:
    pop r13
    pop r12
    pop rbx
    ret

; The sync layer logged us in.
ui_logged_in:
    mov edi, F_PASS
    call field_clear
    mov dword [focus], F_NONE
    mov byte [modal], M_NONE
    mov byte [menu_open], 0
    ret

; The sync layer switched teams, or the team list changed under us.
ui_team_opened:
    xor eax, eax
    mov [scroll_y], eax
    mov [board_x], eax
    mov [sel_id], eax
    mov [drag_id], eax
    mov [drag_moving], al
    mov [filter_project], eax
    mov [view_mode], eax
    mov dword [filter_label], -1
    mov [menu_open], al
    cmp byte [modal], M_TEAM
    jne .focus
    mov [modal], al                         ; the team we were creating is here
.focus:
    mov eax, [focus]
    cmp eax, F_USER
    je .done
    cmp eax, F_PASS
    je .done
    cmp byte [modal], M_NONE
    jne .done
    mov dword [focus], F_NONE
.done:
    mov byte [list_dirty], 1
    ret

; The issues changed. The detail view closes if its issue is gone.
ui_view_changed:
    mov byte [list_dirty], 1
    mov edi, [detail_issue]
    test edi, edi
    jz .done
    cmp byte [loaded], 0
    je .done
    call find_view_issue
    test rax, rax
    jnz .done
    mov dword [focus], F_NONE
    xor edi, edi
    jmp sync_open_issue
.done:
    ret

; --- hit regions ---

; edi = x, esi = y, edx = w, ecx = h, r8d = action, r9d = arg
add_hit:
    mov eax, [hit_count]
    cmp eax, HIT_MAX
    jae .full
    imul eax, eax, HIT_SIZE
    lea rax, [hits + rax]
    mov [rax + HIT_X], edi
    mov [rax + HIT_Y], esi
    mov [rax + HIT_W], edx
    mov [rax + HIT_H], ecx
    mov [rax + HIT_ACTION], r8d
    mov [rax + HIT_ARG], r9d
    inc dword [hit_count]
.full:
    ret

; edi = x, esi = y -> rax = the topmost hit region there, or 0
hit_at:
    mov ecx, [hit_count]
.find:
    ; Last drawn wins, like the pixels.
    test ecx, ecx
    jz .none
    dec ecx
    imul eax, ecx, HIT_SIZE
    lea rax, [hits + rax]
    mov edx, edi
    sub edx, [rax + HIT_X]
    js .find
    cmp edx, [rax + HIT_W]
    jge .find
    mov edx, esi
    sub edx, [rax + HIT_Y]
    js .find
    cmp edx, [rax + HIT_H]
    jge .find
    ret
.none:
    xor eax, eax
    ret

; Recomputes what's under the pointer and updates hover state and cursor.
update_hover:
    xor r8d, r8d                            ; action
    xor r9d, r9d                            ; arg
    cmp byte [pointer_inside], 0
    je .apply
    mov edi, [pointer_x]
    mov esi, [pointer_y]
    call hit_at
    test rax, rax
    jz .apply
    mov r8d, [rax + HIT_ACTION]
    mov r9d, [rax + HIT_ARG]
.apply:
    cmp r8d, [hover_action]
    jne .changed
    cmp r9d, [hover_arg]
    je .cursor
.changed:
    mov [hover_action], r8d
    mov [hover_arg], r9d
    mov byte [need_redraw], 1
.cursor:
    cmp byte [pointer_inside], 0
    je .done
    mov edi, CURSOR_POINTER
    mov eax, CURSOR_DEFAULT
    cmp r8d, A_BLOCK
    cmovbe edi, eax
    cmp r8d, A_DISMISS
    cmove edi, eax
    mov eax, CURSOR_TEXT
    cmp r8d, A_FIELD
    cmove edi, eax
    mov eax, CURSOR_GRABBING
    cmp byte [drag_moving], 0
    cmovne edi, eax
    cmp edi, [cursor_shape]
    je .done
    mov [cursor_shape], edi
    call wl_set_cursor_shape
.done:
    ret

; edi = action, esi = arg -> eax = 1 if that's what the pointer is over
hovering:
    xor eax, eax
    cmp edi, [hover_action]
    jne .done
    cmp esi, [hover_arg]
    sete al
.done:
    ret

; --- the issue list ---

; rdi = view issue -> eax = 1 if the current view and filters show it
issue_shown:
    movzx ecx, byte [rdi + CI_STATUS]
    mov eax, [view_mode]
    cmp eax, V_ACTIVE
    je .active
    cmp eax, V_BACKLOG
    je .backlog
    cmp eax, V_MINE
    jne .filters
    mov eax, [my_id]
    cmp [rdi + CI_ASSIGNEE], eax
    jne .no
    jmp .filters
.active:
    cmp ecx, STATUS_TODO
    je .filters
    cmp ecx, STATUS_IN_PROGRESS
    je .filters
    jmp .no
.backlog:
    cmp ecx, STATUS_BACKLOG
    jne .no
.filters:
    mov eax, [filter_project]
    test eax, eax
    jz .label
    cmp [rdi + CI_PROJECT], al
    jne .no
.label:
    mov ecx, [filter_label]
    test ecx, ecx
    js .yes
    movzx eax, word [rdi + CI_LABELS]
    bt eax, ecx
    jnc .no
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; rdi = view issue -> rax = its sort key: priority (urgent first, none last),
; then newest first. Unsent issues have no number yet and go on top.
issue_key:
    movzx eax, byte [rdi + CI_PRIORITY]
    mov ecx, 5
    test eax, eax
    cmovz eax, ecx
    shl rax, 32
    mov ecx, [rdi + CI_NUMBER]
    test ecx, ecx
    jnz .numbered
    mov ecx, [rdi + CI_ID]                  ; PENDING_ID | op number, so later ones sort first
    and ecx, ~PENDING_ID
    add ecx, 0x7fffffff
.numbered:
    not ecx
    or rax, rcx
    ret

; Fills col_items[status] with the shown issues of that status, sorted.
build_columns:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    xor eax, eax
    lea rdi, [col_count]
    mov ecx, STATUS_COUNT
    rep stosd
    lea rbx, [view_issues]
    mov ebp, [view_count]
.issue:
    test ebp, ebp
    jz .done
    mov rdi, rbx
    call issue_shown
    test eax, eax
    jz .next
    mov rdi, rbx
    call issue_key
    mov r14, rax
    movzx r12d, byte [rbx + CI_STATUS]
    cmp r12d, STATUS_COUNT
    jae .next
    imul r13d, r12d, VIEW_MAX * 8
    lea r13, [col_items + r13]              ; the column
    mov ecx, [col_count + r12 * 4]
    inc dword [col_count + r12 * 4]
    ; Insertion: shift bigger keys up one.
.shift:
    test ecx, ecx
    jz .place
    mov rdi, [r13 + rcx * 8 - 8]
    mov r15d, ecx
    call issue_key
    mov ecx, r15d
    cmp rax, r14
    jbe .place
    mov rdi, [r13 + rcx * 8 - 8]
    mov [r13 + rcx * 8], rdi
    dec ecx
    jmp .shift
.place:
    mov [r13 + rcx * 8], rbx
.next:
    add rbx, CI_SIZE
    dec ebp
    jmp .issue
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

section .rodata
list_order:     db STATUS_IN_PROGRESS, STATUS_TODO, STATUS_BACKLOG, STATUS_DONE, STATUS_CANCELED
board_order:    db STATUS_BACKLOG, STATUS_TODO, STATUS_IN_PROGRESS, STATUS_DONE, STATUS_CANCELED
section .text

; Rebuilds the columns and, from them, the list rows: a header per non-empty
; status, then its issues.
build_list:
    push rbx
    push r12
    push r13
    mov byte [list_dirty], 0
    call build_columns
    lea rdi, [rows]
    xor r12d, r12d                          ; position in list_order
.group:
    cmp r12d, STATUS_COUNT
    jae .done
    movzx ebx, byte [list_order + r12]
    mov ecx, [col_count + rbx * 4]
    test ecx, ecx
    jz .next_group
    mov qword [rdi + RW_ISSUE], 0
    mov [rdi + RW_STATUS], ebx
    mov [rdi + RW_COUNT], ecx
    add rdi, RW_SIZE
    imul eax, ebx, VIEW_MAX * 8
    lea rsi, [col_items + rax]
.issue:
    mov rax, [rsi]
    mov [rdi + RW_ISSUE], rax
    mov [rdi + RW_STATUS], ebx
    add rdi, RW_SIZE
    add rsi, 8
    dec ecx
    jnz .issue
.next_group:
    inc r12d
    jmp .group
.done:
    lea rax, [rows]
    sub rdi, rax
    shr edi, 4                              ; / RW_SIZE
    mov [row_count], edi
    pop r13
    pop r12
    pop rbx
    ret

; -> eax = the row index of the selected issue, or -1
selected_row:
    mov edi, [sel_id]
    xor eax, eax
    lea rcx, [rows]
.row:
    cmp eax, [row_count]
    jae .none
    mov rdx, [rcx + RW_ISSUE]
    test rdx, rdx
    jz .next
    cmp [rdx + CI_ID], edi
    je .done
.next:
    inc eax
    add rcx, RW_SIZE
    jmp .row
.none:
    mov eax, -1
.done:
    ret

; -> eax = the selected issue's column (index into board_order), edx = its
; position in it, or eax = -1
selected_cell:
    mov edi, [sel_id]
    xor eax, eax
.column:
    cmp eax, STATUS_COUNT
    jae .none
    movzx ecx, byte [board_order + rax]
    mov r8d, [col_count + rcx * 4]
    imul ecx, ecx, VIEW_MAX * 8
    lea rsi, [col_items + rcx]
    xor edx, edx
.cell:
    cmp edx, r8d
    jae .next_column
    mov rcx, [rsi + rdx * 8]
    cmp [rcx + CI_ID], edi
    je .done
    inc edx
    jmp .cell
.next_column:
    inc eax
    jmp .column
.none:
    mov eax, -1
.done:
    ret

; Moves the selection by edi issues (+1 down, -1 up), in list order or
; within the board column.
move_selection:
    push rbx
    mov ebx, edi
    cmp byte [board], 0
    jne .board
    call selected_row
    mov ecx, eax
.step:
    cmp ecx, -1
    jne .from_sel
    xor ecx, ecx                            ; nothing selected: start at the top
    dec ecx
    mov ebx, 1
.from_sel:
    add ecx, ebx
    cmp ecx, [row_count]
    jae .done
    imul eax, ecx, RW_SIZE
    mov rax, [rows + rax + RW_ISSUE]
    test rax, rax
    jz .from_sel                            ; skip headers
    mov eax, [rax + CI_ID]
    mov [sel_id], eax
    call reveal_selection
    jmp .done
.board:
    call selected_cell
    cmp eax, -1
    je .first_cell
    movzx ecx, byte [board_order + rax]
    add edx, ebx
    js .done
    cmp edx, [col_count + rcx * 4]
    jae .done
    imul ecx, ecx, VIEW_MAX * 8
    mov rax, [col_items + rcx + rdx * 8]
    mov eax, [rax + CI_ID]
    mov [sel_id], eax
    mov byte [board_reveal], 1
    jmp .done
.first_cell:
    xor edi, edi
    call select_column
.done:
    mov byte [need_redraw], 1
    pop rbx
    ret

; Selects the first issue of a board column, looking further right for a
; non-empty one. edi = index into board_order
select_column:
.column:
    cmp edi, STATUS_COUNT
    jae .done
    movzx ecx, byte [board_order + rdi]
    cmp dword [col_count + rcx * 4], 0
    je .next
    imul ecx, ecx, VIEW_MAX * 8
    mov rax, [col_items + rcx]
    mov eax, [rax + CI_ID]
    mov [sel_id], eax
    mov byte [board_reveal], 1
    ret
.next:
    inc edi
    jmp .column
.done:
    ret

; edi = -1 or +1. Moves the board selection to the next non-empty column.
move_column:
    push rbx
    mov ebx, edi
    call selected_cell
    cmp eax, -1
    jne .from
    xor edi, edi
    call select_column
    jmp .done
.from:
    mov edi, eax
.try:
    add edi, ebx
    cmp edi, STATUS_COUNT
    jae .done
    movzx ecx, byte [board_order + rdi]
    cmp dword [col_count + rcx * 4], 0
    je .try
    call select_column
.done:
    mov byte [need_redraw], 1
    pop rbx
    ret

; Scrolls the list so the selected row is visible.
reveal_selection:
    call selected_row
    cmp eax, -1
    je .done
    ; Rows above it: headers are GROUP_H, issues ROW_H.
    xor ecx, ecx                            ; y of the row
    xor edx, edx
.sum:
    cmp edx, eax
    jae .have_y
    imul r8d, edx, RW_SIZE
    cmp qword [rows + r8 + RW_ISSUE], 0
    mov r9d, ROW_H
    mov r10d, GROUP_H
    cmove r9d, r10d
    add ecx, r9d
    inc edx
    jmp .sum
.have_y:
    cmp ecx, [scroll_y]
    jge .below_top
    mov [scroll_y], ecx
    jmp .done
.below_top:
    push rcx
    call list_height                        ; clobbers ecx
    pop rcx
    lea edx, [ecx + ROW_H]
    sub edx, eax
    cmp edx, [scroll_y]
    jle .done
    mov [scroll_y], edx
.done:
    ret

; -> rax = the selected view issue if it's a real one, else 0
selected_issue:
    mov edi, [sel_id]
    test edi, edi
    jz .none
    test edi, PENDING_ID
    jnz .none
    jmp find_view_issue
.none:
    xor eax, eax
    ret

; -> eax = the issue shortcuts act on: the open one, else the selected one, or 0
target_issue:
    mov eax, [detail_issue]
    test eax, eax
    jnz .done
    call selected_issue
    test rax, rax
    jz .done
    mov eax, [rax + CI_ID]
.done:
    ret

; --- geometry ---

; -> eax = x, ecx = y, edx = w, r8d = h of the main panel
panel_rect:
    mov eax, SIDEBAR_W
    mov ecx, GAP
    mov edx, [win_w]
    sub edx, SIDEBAR_W + GAP
    mov r8d, [win_h]
    sub r8d, GAP * 2
    xor r9d, r9d
    cmp edx, r9d
    cmovl edx, r9d
    cmp r8d, r9d
    cmovl r8d, r9d
    ret

; -> eax = how tall the scrolling part of the list or board is
list_height:
    call panel_rect
    lea eax, [r8d - HEADER_H - FILTER_H]
    xor ecx, ecx
    cmp eax, ecx
    cmovl eax, ecx
    ret

; Keeps a scroll offset within what last frame's content needs.
; rdi = the offset, esi = visible height
clamp_scroll:
    mov eax, [content_h]
    sub eax, esi
    xor ecx, ecx
    cmp eax, ecx
    cmovl eax, ecx
    mov ecx, [rdi]
    cmp ecx, eax
    cmovg ecx, eax
    xor eax, eax
    cmp ecx, eax
    cmovl ecx, eax
    mov [rdi], ecx
    ret

; --- menus ---

; Opens a menu. edi = MK_*, esi = the issue it changes (0: the draft)
open_menu:
    mov [menu_kind], edi
    mov [menu_issue], esi
    mov byte [menu_open], 1
    xor eax, eax
    mov [menu_sel], eax
    mov [menu_scroll], eax
    mov edi, F_MENU
    call field_clear
    mov edi, F_MENU
    jmp set_focus

close_menu:
    mov byte [menu_open], 0
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

; --- input ---

; A held card starts moving once the pointer travels DRAG_SLOP, so a
; click with a shaky hand still opens it.
ui_pointer_moved:
    cmp dword [drag_id], 0
    je update_hover
    cmp byte [pointer_inside], 0
    je .cancel
    cmp byte [drag_moving], 0
    jne .moving
    mov eax, [pointer_x]
    sub eax, [drag_from_x]
    mov ecx, eax
    neg ecx
    cmovs ecx, eax
    cmp ecx, DRAG_SLOP
    jge .start
    mov eax, [pointer_y]
    sub eax, [drag_from_y]
    mov ecx, eax
    neg ecx
    cmovs ecx, eax
    cmp ecx, DRAG_SLOP
    jl update_hover
.start:
    mov byte [drag_moving], 1
.moving:
    mov byte [need_redraw], 1
    jmp update_hover
.cancel:
    call cancel_drag
    jmp update_hover

cancel_drag:
    mov dword [drag_id], 0
    mov byte [drag_moving], 0
    mov byte [need_redraw], 1
    ret

ui_layout_changed:
    mov byte [need_redraw], 1
    jmp update_hover

; edi = MSG_LOGIN or MSG_REGISTER
do_auth:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov edi, F_USER
    call field_addr
    mov r12, rax
    cmp dword [r12 + FD_LEN], 0
    je .need_user
    mov edi, F_PASS
    call field_addr
    cmp dword [rax + FD_LEN], 0
    je .need_pass
    mov rcx, [rax + FD_BUF]
    mov r8d, [rax + FD_LEN]
    mov edi, ebx
    mov rsi, [r12 + FD_BUF]
    mov edx, [r12 + FD_LEN]
    call sync_auth
    jmp .done
.need_user:
    mov dword [focus], F_USER
    jmp .done
.need_pass:
    mov dword [focus], F_PASS
.done:
    mov byte [need_redraw], 1
    add rsp, 8
    pop r12
    pop rbx
    ret

; Opens the create modal. edi = the status it starts in
open_create:
    push rbx
    mov ebx, edi
    cmp dword [current_team], 0
    je .done
    mov byte [menu_open], 0
    mov byte [modal], M_CREATE
    mov [new_status], ebx
    xor eax, eax
    mov [new_priority], eax
    mov [new_assignee], eax
    mov [new_labels], eax
    mov eax, [filter_project]               ; start inside the project being looked at
    mov [new_project], eax
    cmp dword [view_mode], V_MINE
    jne .fields
    mov eax, [my_id]
    mov [new_assignee], eax
.fields:
    mov edi, F_NEW_TITLE
    call field_clear
    mov edi, F_NEW_DESC
    call field_clear
    mov edi, F_NEW_TITLE
    call set_focus
.done:
    pop rbx
    ret

submit_create:
    push rbx
    mov edi, F_NEW_TITLE
    call field_trimmed
    test edx, edx
    jz .need_title
    push rsi
    push rdx
    mov edi, OP_CREATE_ISSUE
    call new_op
    mov rbx, rax
    pop rdx
    pop rsi
    call draft_text
    mov edi, F_NEW_DESC
    call field_trimmed
    call draft_body
    mov eax, [new_status]
    mov [rbx + PO_STATUS], al
    mov eax, [new_priority]
    mov [rbx + PO_PRIORITY], al
    mov eax, [new_assignee]
    mov [rbx + PO_ASSIGNEE], eax
    mov eax, [new_project]
    mov [rbx + PO_PROJECT], al
    mov eax, [new_labels]
    mov [rbx + PO_LABELS], eax
    call queue_draft
    test eax, eax
    jz .done
    mov byte [modal], M_NONE
    mov edi, F_NONE
    call set_focus
    jmp .done
.need_title:
    mov edi, F_NEW_TITLE
    call set_focus
.done:
    pop rbx
    ret

open_team_modal:
    mov byte [menu_open], 0
    mov byte [modal], M_TEAM
    mov byte [key_edited], 0
    mov edi, F_TEAM_NAME
    call field_clear
    mov edi, F_TEAM_KEY
    call field_clear
    mov edi, F_TEAM_NAME
    jmp set_focus

submit_team:
    push rbx
    push r12
    sub rsp, 8
    mov edi, F_TEAM_KEY
    call field_trimmed
    mov rbx, rsi
    mov r12d, edx
    mov edi, F_TEAM_NAME
    call field_trimmed
    test edx, edx
    jz .done
    mov rcx, rsi
    mov r8d, edx
    mov rsi, rbx
    mov edx, r12d
    call sync_create_team
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; The key follows the name until it's typed by hand: the first letters of
; up to three words, or of the one word, uppercased.
derive_team_key:
    cmp byte [key_edited], 0
    jne .done
    lea rdi, [team_key_buf]
    mov rsi, [fields + F_TEAM_NAME * FD_SIZE + FD_BUF]
    mov ecx, [fields + F_TEAM_NAME * FD_SIZE + FD_LEN]
    xor edx, edx                            ; letters written
    mov r8d, 1                              ; at the start of a word
    xor r9d, r9d                            ; words seen
.char:
    test ecx, ecx
    jz .one_word
    movzx eax, byte [rsi]
    inc rsi
    dec ecx
    or eax, 0x20
    lea r10d, [eax - 'a']
    cmp r10d, 'z' - 'a'
    ja .space
    test r8d, r8d
    jz .char
    xor r8d, r8d
    inc r9d
    cmp edx, 3
    jae .char
    sub eax, 0x20
    mov [rdi + rdx], al
    inc edx
    jmp .char
.space:
    mov r8d, 1
    jmp .char
.one_word:
    ; A single word gives one letter, so take its first three instead.
    cmp r9d, 1
    jne .store
    mov rsi, [fields + F_TEAM_NAME * FD_SIZE + FD_BUF]
    mov ecx, [fields + F_TEAM_NAME * FD_SIZE + FD_LEN]
    xor edx, edx
.letter:
    test ecx, ecx
    jz .store
    cmp edx, 3
    jae .store
    movzx eax, byte [rsi]
    inc rsi
    dec ecx
    or eax, 0x20
    lea r10d, [eax - 'a']
    cmp r10d, 'z' - 'a'
    ja .letter
    sub eax, 0x20
    mov [rdi + rdx], al
    inc edx
    jmp .letter
.store:
    mov [fields + F_TEAM_KEY * FD_SIZE + FD_LEN], edx
    mov [fields + F_TEAM_KEY * FD_SIZE + FD_CURSOR], edx
.done:
    ret

; edi = issue id. Selects it and opens the detail view.
open_issue:
    push rbx
    mov ebx, edi
    test ebx, PENDING_ID
    jnz .done                               ; not created yet
    mov [sel_id], ebx
    mov dword [detail_scroll], 0
    mov edi, F_NONE
    call set_focus
    mov edi, F_COMMENT
    call field_clear
    mov edi, ebx
    call sync_open_issue
.done:
    pop rbx
    ret

close_detail:
    mov edi, F_NONE
    call set_focus
    xor edi, edi
    jmp sync_open_issue

; edi = team id
select_team:
    push rdi
    call close_detail
    pop rdi
    call sync_select_team
    jmp ui_team_opened

; Starts editing the open issue's title or description. edi = F_TITLE or F_DESC
begin_edit:
    push rbx
    mov ebx, edi
    cmp [focus], ebx
    je .done
    mov edi, [detail_issue]
    call find_view_issue
    test rax, rax
    jz .done
    mov edi, ebx
    cmp ebx, F_TITLE
    jne .desc
    lea rsi, [rax + CI_TITLE]
    movzx edx, byte [rax + CI_TITLE_LEN]
    jmp .set
.desc:
    mov rsi, [view_desc]
    mov edx, [view_desc_len]
.set:
    call field_set
    mov edi, ebx
    call set_focus
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
    mov [filter_project], r12d
    jmp .refilter
.filter_label:
    not r12d
    mov [filter_label], r12d
.refilter:
    mov byte [list_dirty], 1
    jmp .close
.command:
    call close_menu
    mov edi, r12d
    call run_command
    jmp .done
.close:
    call close_menu
.done:
    mov byte [need_redraw], 1
    pop r13
    pop r12
    pop rbx
    ret
