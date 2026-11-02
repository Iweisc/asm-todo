; The window's state: fields, selection, the list and board, menus and
; modals. Keys and clicks are handled in input.asm, menus in menu.asm, and
; drawing lives in widgets.asm (fields, formatting), views.asm (the screens)
; and chat.asm (conversations).
;
; Keyboard first: with no text field focused, letters are shortcuts.
;   c new issue    j/k or arrows move    Enter open    Esc back
;   s status   p priority   a assignee   l labels   m project
;   Ctrl+K command menu    Ctrl+B list or board
; In a conversation, typing goes to the message box instead.

%define SIDEBAR_W       232
%define GAP             8               ; around the main panel
%define HEADER_H        44
%define FILTER_H        40
%define ROW_H           38
%define GROUP_H         36
%define PROPS_W         256
%define PROPS_NARROW_W  232             ; in a detail view narrower than DETAIL_NARROW
%define DETAIL_NARROW   760
%define CARD_GAP        8
%define COL_MIN_W       200
%define LINE_H          20              ; wrapped body text
%define MENU_W          520
%define MENU_ROW_H      36
%define MENU_MAX        128             ; the filter menu: every label, project, priority and member
%define MENU_SHOWN      9               ; rows visible at once
%define WHEEL_NOTCH     15              ; pixels compositors report per wheel notch
%define BTN_PRIMARY     1               ; draw_button kinds, 0 is the outlined one
%define BTN_DANGER      2
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
%define C_DANGER_HI     0xf07070
%define C_ONLINE        0x4cb782
%define C_SHADE         0x070809        ; behind a modal
%define C_SELECTION     0x2d3258        ; selected text, the accent dimmed

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
%define KEY_V           47
%define KEY_X           45
%define KEY_Y           21
%define KEY_Z           44

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
%define FD_X            44              ; where its text was last drawn, for clicks
%define FD_Y            48              ; the top, wrapped text only
%define FD_W            52              ; 0 until it's drawn
%define FD_ANCHOR       56              ; the selection's other end, FD_CURSOR when there's none
%define FD_SIZE         64
fits FD_ANCHOR, 4, FD_SIZE
%define FF_MASKED       1
%define FF_MULTILINE    2

; Kinds of edit, which undo.asm groups into steps
%define UK_TYPE         1
%define UK_DELETE       2
%define UK_OTHER        3               ; paste or cut: a step each

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
%define F_MESSAGE       11
%define F_EDIT          12              ; a comment being edited
%define F_RENAME        13              ; a label or project's name
%define F_OLD_PASS      14              ; changing your password
%define F_NEW_PASS      15
%define F_TEAM_RENAME   16              ; the team's name in its settings
%define F_CHANNEL       17              ; a channel's name

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
%define A_UNFILTER      16              ; arg = 0 label, 1 project, 2 priority, 3 assignee
%define A_PICK          17              ; arg = MK_*, for the open issue or the draft
%define A_MENU_ITEM     18              ; arg = item index
%define A_DISMISS       19              ; the shade around a modal or menu
%define A_CREATE        20
%define A_CREATE_TEAM   21
%define A_CLOSE         22              ; leaves the detail view
%define A_DELETE        23
%define A_ROW_STATUS    24              ; arg = issue id
%define A_ROW_PRIORITY  25              ; arg = issue id
%define A_CHAT          26              ; arg = peer, 0 for the team's channel
%define A_COMMENT       27              ; arg = comment id, shows its actions on hover
%define A_EDIT_COMMENT  28              ; arg = comment id
%define A_DELETE_COMMENT 29             ; arg = comment id
%define A_CLOSE_MODAL   30              ; the X in a modal's corner
%define A_RENAME        31              ; arg = label or project item, see labels.asm
%define A_REMOVE_NAMED  32              ; arg = label or project item
%define A_CHANGE_PASSWORD 33
%define A_SETTINGS      34              ; arg = the field to focus, F_NONE for none
%define A_INVITE        35
%define A_SET_ROLE      36              ; arg = user id, switches them between owner and member
%define A_SAVE_TEAM_NAME 37
%define A_CHANNEL_DIALOG 38             ; arg = the channel's slot, 0 for a new one
%define A_SAVE_CHANNEL  39
%define A_DELETE_CHANNEL 40
%define A_MESSAGE       41              ; arg = message id, shows its actions on hover
%define A_EDIT_MESSAGE  42              ; arg = message id
%define A_DELETE_MESSAGE 43             ; arg = message id
%define A_IMAGE         44              ; arg = image id, opens it
%define A_DROP_ATTACHMENT 45            ; arg = the field whose attachment goes

; Views of a team's issues
%define V_ALL           0
%define V_ACTIVE        1
%define V_BACKLOG       2
%define V_MINE          3

; Modals
%define M_NONE          0
%define M_CREATE        1
%define M_TEAM          2
%define M_LABELS        3
%define M_PASSWORD      4
%define M_SETTINGS      5
%define M_CHANNEL       6
%define M_IMAGE         7

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
%define IC_ISSUE        6               ; arg = status. Matched by the caller, by title or ID

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
%define CMD_CHAT        (CMD_CLEAR + 1)  ; the team's channel
%define CMD_COPY_ID     (CMD_CHAT + 1)
%define CMD_LABELS      (CMD_COPY_ID + 1)
%define CMD_PASSWORD    (CMD_LABELS + 1)
%define CMD_SETTINGS    (CMD_PASSWORD + 1)
%define CMD_INVITE      (CMD_SETTINGS + 1)
%define CMD_NEW_CHANNEL (CMD_INVITE + 1)
%define CMD_ISSUE       0x40000000      ; + issue id, opens it

; Filter menu values. Labels are ~slot and projects their number.
%define FILTER_PRIORITY 0x10000000      ; + priority
%define FILTER_ASSIGNEE 0x20000000      ; + user id, 0 for nobody

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
text s_signing_in,      "Signing in..."
text s_filter_hint,     "Filter..."
text s_command_hint,    "Type a command or search..."
text s_title_hint,      "Issue title"
text s_desc_hint,       "Add description..."
text s_team_name_hint,  "Team name"
text s_team_key_hint,   "KEY"
text s_member_hint,     "Invite by username"
text s_comment_hint,    "Leave a comment..."
text s_message_hint,    "Write a message..."
text s_rename_field_hint, "Name"

%macro FIELD 5                          ; buffer, max, flags, style, hint
    dq %1
    dd %2, 0, 0, 0, %3, %4
    dq %5
    dd %5_len, 0, 0, 0, 0, 0
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
    FIELD member_buf, USERNAME_MAX, 0, ST_BODY, s_member_hint
    FIELD title_buf, TITLE_MAX, 0, ST_TITLE, s_title_hint
    FIELD desc_buf, DESC_MAX, FF_MULTILINE, ST_BODY, s_desc_hint
    FIELD comment_buf, COMMENT_MAX, FF_MULTILINE, ST_BODY, s_comment_hint
    FIELD message_buf, MESSAGE_MAX, FF_MULTILINE, ST_BODY, s_message_hint
    FIELD edit_buf, COMMENT_MAX, FF_MULTILINE, ST_BODY, s_comment_hint
    FIELD rename_buf, PROJECT_NAME_MAX, 0, ST_BODY, s_rename_field_hint
    FIELD old_pass_buf, PASSWORD_MAX, FF_MASKED, ST_BODY, s_password
    FIELD new_pass_buf, PASSWORD_MAX, FF_MASKED, ST_BODY, s_password
    FIELD team_rename_buf, TEAMNAME_MAX, 0, ST_BODY, s_team_name_hint
    FIELD channel_buf, CHANNEL_NAME_MAX, 0, ST_BODY, s_channel_field_hint

focus:          dd F_USER
filter_label:   dd -1                   ; a label slot, or -1
filter_priority: dd -1                  ; a priority, or -1
filter_assignee: dd -1                  ; a user id, 0 for unassigned, or -1
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
message_buf:    resb MESSAGE_MAX
edit_buf:       resb COMMENT_MAX
rename_buf:     resb PROJECT_NAME_MAX   ; the longer of a label's and a project's
old_pass_buf:   resb PASSWORD_MAX
new_pass_buf:   resb PASSWORD_MAX
team_rename_buf: resb TEAMNAME_MAX
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
menu_wheel:     resd 1                  ; wheel pixels short of a whole notch
delete_armed:   resd 1                  ; the issue whose Delete was clicked once, or 0
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
    call undo_drop
    call attach_drop
    call field_addr
    mov rbx, rax
    mov rdi, [rbx + FD_BUF]
    mov esi, [rbx + FD_MAX]
    call wipe
    xor eax, eax
    mov [rbx + FD_LEN], eax
    mov [rbx + FD_CURSOR], eax
    mov [rbx + FD_ANCHOR], eax
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
    mov [rbx + FD_ANCHOR], r13d
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
    sub rsp, 8
    mov edi, F_PASS
    call field_clear
    call close_dialogs
    add rsp, 8
    ret

; Logged out, by us or the server: nothing of the last login stays open,
; and typing goes to the form again.
ui_logged_out:
    sub rsp, 8
    call close_dialogs
    call undo_wipe
    call images_reset
    mov edi, [att_field]
    call attach_drop
    mov dword [focus], F_USER
    add rsp, 8
    ret

; Closes every dialog, menu and edit in progress, dropping what they held.
close_dialogs:
    sub rsp, 8
    mov byte [menu_open], 0
    call stop_comment_edit
    call stop_rename
    call close_modal
    add rsp, 8
    ret

; The session saved by the last run didn't work out, so the form comes back.
ui_login_form:
    mov dword [focus], F_USER
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
    mov dword [filter_priority], -1
    mov dword [filter_assignee], -1
    mov [menu_open], al
    cmp byte [modal], M_TEAM
    jne .labels
    mov [modal], al                         ; the team we were creating is here
.labels:
    cmp byte [modal], M_LABELS              ; its slots are the old team's
    je .old_team
    cmp byte [modal], M_SETTINGS
    je .old_team
    cmp byte [modal], M_CHANNEL
    jne .draft
.old_team:
    call stop_rename
    call close_modal
.draft:
    mov byte [chan_open_new], 0
    mov edi, F_MESSAGE                      ; drafts belong to the old team
    call field_clear
    mov edi, F_MEMBER
    call field_clear
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

; Cut to the clip like the pixels are, so whatever scrolled out of sight
; under a header can't be clicked through it.
; edi = x, esi = y, edx = w, ecx = h, r8d = action, r9d = arg
add_hit:
    add edx, edi                            ; right and bottom edges
    add ecx, esi
    cmp edi, [clip_x0]
    cmovl edi, [clip_x0]
    cmp esi, [clip_y0]
    cmovl esi, [clip_y0]
    cmp edx, [clip_x1]
    cmovg edx, [clip_x1]
    cmp ecx, [clip_y1]
    cmovg ecx, [clip_y1]
    sub edx, edi
    jle .full
    sub ecx, esi
    jle .full
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
    cmp r8d, A_COMMENT
    cmove edi, eax
    cmp r8d, A_MESSAGE
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
    js .priority
    movzx eax, word [rdi + CI_LABELS]
    bt eax, ecx
    jnc .no
.priority:
    mov eax, [filter_priority]
    test eax, eax
    js .assignee
    cmp [rdi + CI_PRIORITY], al
    jne .no
.assignee:
    mov eax, [filter_assignee]
    test eax, eax
    js .yes
    cmp [rdi + CI_ASSIGNEE], eax
    jne .no
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; -> eax = 1 if any filter is on
filtered:
    xor eax, eax
    cmp dword [filter_project], 0
    setne al
    mov ecx, [filter_label]                 ; -1 when off, so the AND stays -1 only if all are
    and ecx, [filter_priority]
    and ecx, [filter_assignee]
    shr ecx, 31
    xor ecx, 1
    or eax, ecx
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
    xor eax, eax
    cmp byte [chat_open], 0
    jne .done                               ; the list isn't showing
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
    mov edx, [content_h]
; rdi = the offset, esi = visible height, edx = content height
clamp_scroll_to:
    mov eax, edx
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

; --- input ---

; A held card starts moving once the pointer travels DRAG_SLOP, so a
; click with a shaky hand still opens it.
ui_pointer_moved:
    call drag_select
    test eax, eax
    jnz update_hover
    cmp dword [drag_id], 0
    je pointer_hover
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

; Hover follows the pointer, and a menu's selection follows it too, but only
; when it moves. One resting over a menu leaves the arrow keys alone.
pointer_hover:
    call update_hover
    cmp byte [menu_open], 0
    je .done
    cmp dword [hover_action], A_MENU_ITEM
    jne .done
    mov eax, [hover_arg]
    cmp eax, [menu_sel]
    je .done
    mov [menu_sel], eax
    mov byte [need_redraw], 1
.done:
    ret

; Lets go of a held card without moving it.
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
    call stop_comment_edit
    mov edi, ebx
    call sync_open_issue
.done:
    pop rbx
    ret

; Back to the list, from the open issue or conversation.
close_detail:
    call stop_comment_edit
    mov edi, F_NONE
    call set_focus
    call sync_close_chat
    xor edi, edi
    jmp sync_open_issue

; edi = team id
select_team:
    push rdi
    call close_detail
    pop rdi
    call sync_select_team
    jmp ui_team_opened

; Starts editing the open issue's title or description at the pointer.
; edi = F_TITLE or F_DESC
begin_edit:
    push rbx
    mov ebx, edi
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
    ; It was showing wrapped until now, the title 28px apart.
    cmp ebx, F_TITLE
    jne .caret
    mov dword [wrap_lh], 28
.caret:
    mov edi, ebx
    call field_addr
    mov rbx, rax
    mov rdi, rax
    call wrapped_caret_at
    mov [rbx + FD_CURSOR], eax
    mov [rbx + FD_ANCHOR], eax
.done:
    pop rbx
    ret
