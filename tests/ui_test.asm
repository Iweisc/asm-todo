; ui-test: drives the client's UI without a compositor or a server.
;
;   ui-test     draws frames into memory, feeds them clicks, keys and wheel
;               turns, and checks what changed. Exits 1 on any failure.
;
; It includes the client's sources but not client.asm, so nothing here opens
; a window or a socket. Sync calls see a client that's offline.

default rel
bits 64

%include "sys.inc"
%include "config.inc"
%include "macros.inc"

%define TEST_W      860
%define TEST_H      640
%define ISSUE_ID    7

section .text
global _start

%include "util.asm"
%include "crypto/sha.asm"
%include "crypto/hmac.asm"
%include "crypto/chacha.asm"
%include "crypto/x25519.asm"
%include "noise.asm"
%include "ws.asm"
%include "wire.asm"
%include "font.asm"
%include "draw.asm"
%include "text.asm"
%include "shapes.asm"
%include "icons.asm"
%include "glyphs.asm"
%include "wayland.asm"
%include "net.asm"
%include "sync.asm"
%include "ui.asm"
%include "input.asm"
%include "widgets.asm"
%include "menu.asm"
%include "views.asm"
%include "chips.asm"
%include "sidebar.asm"
%include "chat.asm"
%include "comments.asm"
%include "labels.asm"
%include "account.asm"
%include "dialogs.asm"
%include "keymap.asm"
%include "members.asm"
%include "channel.asm"
%include "chatedit.asm"
%include "undo.asm"
%include "edit.asm"
%include "clipboard.asm"
%include "session.asm"
%include "localtime.asm"
%include "inflate.asm"
%include "png.asm"
%include "thumbs.asm"
%include "attach.asm"
%include "pick.asm"

section .rodata
t_server:       db "127.0.0.1:18080", 0
t_lewis:        db "lewis", 0
t_maria:        db "maria", 0
t_draft:        db "draft", 0
t_le:           db "le", 0
t_hello:        db "hello", 0
t_one_command:  db "New issue", 0
t_no_command:   db "zzz", 0
t_title:        db "Crash when uploading a large file"

n_menu_current: db "menus open on the current value", 0
n_menu_rest:    db "a resting pointer leaves the menu selection alone", 0
n_menu_wheel:   db "the wheel scrolls a long menu", 0
n_menu_empty:   db "a filter with no matches keeps a row for saying so", 0
n_chat_esc:     db "esc in the message box closes the conversation, keeps the draft", 0
n_narrow:       db "a narrow detail view keeps a usable text column", 0
n_board_side:   db "the sideways wheel scrolls the board", 0
n_list_side:    db "the sideways wheel leaves the list alone", 0
n_no_team:      db "no new issue button without a team", 0
n_invite_fail:  db "a failed invite keeps the name", 0
n_invite_ok:    db "the invite box empties once they join", 0
n_capital:      db "messages start with a capital", 0
n_timeout:      db "messages go away on their own", 0
n_delete_ask:   db "the first delete click only asks", 0
n_delete_back:  db "another click backs out of deleting", 0
n_caret:        db "a click puts the caret where it lands", 0
n_sidebar:      db "the wheel scrolls the sidebar", 0
n_clip_hit:     db "rows scrolled out of view can't be clicked", 0
n_tz:           db "dates use the zone's offset in effect, before and after transitions", 0
n_cmt_edited:   db "an edited comment's event replaces it in place", 0
n_cmt_deleted:  db "a deleted comment's event removes it, keeping the order", 0
n_cmt_open:     db "hovering your comment offers Edit, which opens it in a box", 0
n_cmt_saved:    db "a saved edit shows right away, marked edited", 0
n_cmt_delete:   db "deleting a comment asks first, then hides it", 0
n_filter_hide:  db "priority and assignee filters hide issues that don't match", 0
n_filter_chip:  db "a filter's chip removes only that filter", 0
n_rename:       db "renaming a label shows the new name right away", 0
n_remove_named: db "deleting a label asks first, then drops it and its filter", 0
n_password_esc: db "closing the password dialog wipes both fields", 0
n_rename_gone:  db "a label deleted while being renamed isn't brought back", 0
n_logout_modal: db "being logged out closes the open dialog and wipes its passwords", 0
n_keymap:       db "keys type, and shortcuts follow, what the compositor's keymap says", 0
n_settings:     db "team settings show an owner every member's actions, and Remove asks first", 0
n_member_view:  db "a member's team settings only offer leaving", 0
n_dm_rows:      db "direct messages list everyone but you", 0
n_chan_row:     db "a channel gets a sidebar row and, for its maker, an edit link", 0
n_chan_members: db "a member list update keeps an open channel open", 0
n_chan_gone:    db "a deleted channel's conversation closes", 0
n_undo:         db "undo takes back a word at a time, and redo puts it back", 0
n_undo_reset:   db "a field given new text can't undo back into the old one", 0
n_chan_switch:  db "switching teams closes the channel dialog", 0
n_auth_wait:    db "logging in mid-reconnect waits for the connection, and says so if it fails", 0

; A zone file: +1h, then -2h from t = 1000, then +1h again from t = 2000.
t_zone:         db "TZif", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 4
                db 0, 0, 0x03, 0xe8, 0, 0, 0x07, 0xd0
                db 1, 0
                db 0, 0, 0x0e, 0x10, 0, 0
                db 0xff, 0xff, 0xe3, 0xe0, 1, 0
                db "AB", 0, 0
t_zone_len      equ $ - t_zone

; EV_COMMENT_EDITED for comment 12, and EV_COMMENT_DELETED for 11, past the kind byte.
t_edited_event: dd ISSUE_ID, 12, 1, 0
                dw 1
                db "B", 1
                dd 0                    ; no image
                dw 0, 0
t_edited_event_len equ $ - t_edited_event
t_deleted_event: dd ISSUE_ID, 11
t_deleted_event_len equ $ - t_deleted_event
t_x:            db "x", 0
t_hi_yo_keys:   db 35, 23, 57, 21, 24, 0  ; "hi yo" on a US keyboard
t_maya:         db "maya"
t_design:       db "design"
; A French keymap, cut down to four keys, in the shapes xkbcommon and
; Hyprland write.
t_keymap:       db 'xkb_keycodes "evdev" {', 10
                db 9, '<AE01>               = 10;', 10
                db 9, '<AD01>               = 24;', 10
                db 9, '<AC01> = 38;', 10
                db 9, '<AB01> = 52;', 10
                db 9, 'alias <LatQ>         = <AC01>;', 10
                db '};', 10, 'xkb_symbols "pc_fr" {', 10
                db 9, 'name[Group1]="French";', 10
                db 9, 'key <AE01>               {', 9, '[       ampersand,               1 ] };', 10
                db 9, 'key <AD01>               {', 9, '[               a,               A,              ae,              AE ] };', 10
                db 9, 'key <AC01> { type= "ALPHABETIC", symbols[Group1]= [ q, Q ] };', 10
                db 9, 'key <AB01> {', 9, '[ 0x77, 0x57, 0x7c5, 0x6c2 ] };', 10
                db '};', 10
t_keymap_len    equ $ - t_keymap

s_ok:           db "ok    ", 0
s_fail:         db "FAIL  ", 0
s_newline:      db 10, 0

section .bss
alignb 16
test_fb:        resb TEST_W * TEST_H * 4
failures:       resd 1
block_h:        resd 1

section .text

_start:
    lea rax, [test_fb]
    mov [fb], rax
    mov dword [fb_w], TEST_W
    mov dword [fb_h], TEST_H
    mov dword [win_w], TEST_W
    mov dword [win_h], TEST_H
    lea rax, [t_server]
    mov [server_label], rax
    mov byte [pointer_inside], 1
    mov byte [keyboard_focus], 1
    call text_init
    call login_tests
    call sign_in
    call menu_tests
    call panel_tests
    call detail_tests
    call comment_tests
    call filter_tests
    call labels_tests
    call password_tests
    call settings_tests
    call channel_tests
    call message_tests
    call undo_tests
    call input_tests
    call logout_tests
    call auth_tests
    call tz_tests
    call keymap_tests
    call controls_tests
    xor edi, edi
    cmp dword [failures], 0
    setne dil
    call exit

; --- helpers ---

; rdi = test name, esi = 1 if it passed
check:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    lea rdi, [s_ok]
    test r12d, r12d
    jnz .print
    inc dword [failures]
    lea rdi, [s_fail]
.print:
    call say
    mov rdi, rbx
    call say
    lea rdi, [s_newline]
    call say
    add rsp, 8
    pop r12
    pop rbx
    ret

; rdi = a zero-terminated string for stdout
say:
    push rdi
    call strlen
    pop rsi
    mov rdx, rax
    mov eax, SYS_write
    mov edi, 1
    syscall
    ret

; Draws a frame and settles the hover, like render does after presenting.
frame:
    sub rsp, 8
    call draw_frame
    call update_hover
    add rsp, 8
    ret

; edi = action, esi = arg -> rax = the last hit region drawn for them, or 0
find_hit:
    mov ecx, [hit_count]
    lea rax, [hits]
.next:
    test ecx, ecx
    jz .none
    cmp [rax + HIT_ACTION], edi
    jne .skip
    cmp [rax + HIT_ARG], esi
    je .done
.skip:
    add rax, HIT_SIZE
    dec ecx
    jmp .next
.none:
    xor eax, eax
.done:
    ret

; rax = hit region. Puts the pointer in its middle.
point_at_hit:
    mov ecx, [rax + HIT_W]
    shr ecx, 1
    add ecx, [rax + HIT_X]
    mov [pointer_x], ecx
    mov ecx, [rax + HIT_H]
    shr ecx, 1
    add ecx, [rax + HIT_Y]
    mov [pointer_y], ecx
    ret

; edi = action, esi = arg. Clicks the middle of their region, then draws.
; -> eax = 1 if it was on screen
click_hit:
    sub rsp, 8
    call find_hit
    test rax, rax
    jz .done
    call point_at_hit
    call ui_click
    call frame
    mov eax, 1
.done:
    add rsp, 8
    ret

; edi = field, rsi = zero-terminated text to type into it
type_into:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12, rsi
.char:
    movzx esi, byte [r12]
    test esi, esi
    jz .done
    mov edi, ebx
    call field_insert
    inc r12
    jmp .char
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; edi = field -> eax = its text length
field_len:
    call field_addr
    mov eax, [rax + FD_LEN]
    ret

; Logs lewis in to the Engineering team, which has one issue.
sign_in:
    sub rsp, 8
    mov byte [logged_in], 1
    mov dword [my_id], 1
    mov dword [my_name_len], 5
    mov eax, [t_lewis]
    mov [my_name], eax
    mov byte [my_name + 4], 's'
    mov dword [team_count], 1
    mov dword [teams + CO_ID], 1
    mov byte [teams + CO_ROLE], ROLE_OWNER
    mov byte [teams + CO_KEY_LEN], 3
    mov dword [teams + CO_KEY], 'ENG'
    mov byte [teams + CO_NAME_LEN], 3
    mov dword [teams + CO_NAME], 'Eng'
    mov dword [current_team], 1
    mov dword [member_count], 1
    mov dword [members + CM_ID], 1
    mov byte [members + CM_ROLE], ROLE_OWNER
    mov byte [members + CM_NAME_LEN], 5
    mov eax, [t_lewis]
    mov [members + CM_NAME], eax
    mov byte [members + CM_NAME + 4], 's'
    mov dword [issue_count], 1
    mov dword [issues + CI_ID], ISSUE_ID
    mov dword [issues + CI_NUMBER], 1
    mov dword [issues + CI_CREATOR], 1
    mov byte [issues + CI_STATUS], STATUS_TODO
    mov byte [issues + CI_TITLE_LEN], 33
    lea rdi, [issues + CI_TITLE]
    lea rsi, [t_title]
    mov ecx, 33
    rep movsb
    mov dword [focus], F_NONE
    mov byte [list_dirty], 1
    call rebuild_view
    call frame
    add rsp, 8
    ret

; --- the cases ---

; The login screen, before anyone signs in.
login_tests:
    push rbx
    mov ebx, -1
    mov edi, F_USER
    lea rsi, [t_lewis]
    call type_into
    call frame
    ; Clicking between "le" and "wis" puts the caret there, not at the end.
    mov edi, A_FIELD
    mov esi, F_USER
    call find_hit
    test rax, rax
    jz .caret
    call point_at_hit
    lea rdi, [t_le]
    mov esi, 2
    mov edx, ST_BODY
    call text_width
    add eax, [fields + F_USER * FD_SIZE + FD_X]
    inc eax
    mov [pointer_x], eax
    call ui_click
    mov ebx, [fields + F_USER * FD_SIZE + FD_CURSOR]
.caret:
    xor esi, esi
    cmp ebx, 2
    sete sil
    lea rdi, [n_caret]
    call check
    mov edi, F_USER
    call field_clear
    pop rbx
    ret

; The command menu and the pickers.
menu_tests:
    push rbx
    push r12
    sub rsp, 8
    mov byte [modal], M_CREATE
    mov dword [new_status], STATUS_DONE
    mov edi, MK_STATUS
    xor esi, esi
    call open_menu
    call frame
    xor esi, esi
    cmp dword [menu_sel], STATUS_DONE
    sete sil
    lea rdi, [n_menu_current]
    call check

    ; A frame drawn under a pointer that hasn't moved doesn't select its row.
    mov edi, A_MENU_ITEM
    xor esi, esi
    call find_hit
    xor esi, esi
    test rax, rax
    jz .rest
    call point_at_hit
    call frame
    call frame
    cmp dword [menu_sel], STATUS_DONE
    sete sil
.rest:
    lea rdi, [n_menu_rest]
    call check
    call close_menu
    mov byte [modal], M_NONE

    mov edi, MK_COMMAND
    xor esi, esi
    call open_menu
    call frame
    mov edi, WHEEL_NOTCH
    xor esi, esi
    call ui_scroll
    xor esi, esi
    cmp dword [menu_count], MENU_SHOWN
    jle .wheel
    cmp dword [menu_scroll], 1
    sete sil
.wheel:
    lea rdi, [n_menu_wheel]
    call check

    ; No matches still leaves a row's height, for "No results".
    mov edi, F_MENU
    lea rsi, [t_one_command]
    call type_into
    call build_menu
    call frame
    mov ebx, [menu_count]
    mov edi, A_BLOCK
    xor esi, esi
    call find_hit
    xor r12d, r12d
    test rax, rax
    jz .one
    mov r12d, [rax + HIT_H]
.one:
    mov edi, F_MENU
    lea rsi, [t_no_command]
    call type_into
    call build_menu
    call frame
    mov edi, A_BLOCK
    xor esi, esi
    call find_hit
    xor esi, esi
    test rax, rax
    jz .empty
    cmp ebx, 1
    jne .empty
    cmp dword [menu_count], 0
    jne .empty
    cmp [rax + HIT_H], r12d
    sete sil
.empty:
    lea rdi, [n_menu_empty]
    call check
    call close_menu
    add rsp, 8
    pop r12
    pop rbx
    ret

; The sidebar, the board and the footer message.
panel_tests:
    sub rsp, 8
    mov dword [pointer_x], 50
    mov dword [pointer_y], 200
    mov dword [side_scroll], 0
    mov edi, 10
    xor esi, esi
    call ui_scroll
    xor esi, esi
    cmp dword [side_scroll], 30
    sete sil
    lea rdi, [n_sidebar]
    call check
    mov dword [side_scroll], 0

    mov dword [pointer_x], 500
    mov byte [board], 1
    mov dword [board_x], 0
    mov edi, 10
    mov esi, 1
    call ui_scroll
    xor esi, esi
    cmp dword [board_x], 30
    sete sil
    lea rdi, [n_board_side]
    call check
    mov byte [board], 0
    mov dword [board_x], 0
    mov dword [scroll_y], 0
    mov edi, 10
    mov esi, 1
    call ui_scroll
    xor esi, esi
    cmp dword [scroll_y], 0
    jne .list
    cmp dword [board_x], 0
    sete sil
.list:
    lea rdi, [n_list_side]
    call check

    lea rsi, [t_hello]
    mov edx, 5
    call set_status
    xor esi, esi
    cmp byte [status_msg], 'H'
    sete sil
    lea rdi, [n_capital]
    call check
    mov qword [status_until], 0
    call status_tick
    xor esi, esi
    cmp dword [status_len], 0
    sete sil
    lea rdi, [n_timeout]
    call check

    mov edi, F_MEMBER
    lea rsi, [t_maria]
    call type_into
    call ui_members_changed
    mov edi, F_MEMBER
    call field_len
    xor esi, esi
    cmp eax, 5
    sete sil
    lea rdi, [n_invite_fail]
    call check
    mov dword [member_count], 2
    mov dword [members + CM_SIZE + CM_ID], 2
    mov byte [members + CM_SIZE + CM_NAME_LEN], 5
    mov eax, [t_maria]
    mov [members + CM_SIZE + CM_NAME], eax
    mov byte [members + CM_SIZE + CM_NAME + 4], 'a'
    call ui_members_changed
    mov edi, F_MEMBER
    call field_len
    xor esi, esi
    test eax, eax
    sete sil
    lea rdi, [n_invite_ok]
    call check
    mov dword [member_count], 1
    add rsp, 8
    ret

; The open issue, in a window too narrow for the wide layout.
detail_tests:
    sub rsp, 8
    mov edi, ISSUE_ID
    call sync_open_issue
    mov byte [detail_loaded], 1
    call frame
    mov edi, A_FIELD
    mov esi, F_DESC
    call find_hit
    xor esi, esi
    test rax, rax
    jz .narrow
    cmp dword [rax + HIT_W], 320 + 16
    setge sil
.narrow:
    lea rdi, [n_narrow]
    call check

    mov edi, A_DELETE
    xor esi, esi
    call click_hit
    xor esi, esi
    cmp dword [detail_issue], ISSUE_ID
    jne .ask
    cmp dword [delete_armed], ISSUE_ID
    sete sil
.ask:
    lea rdi, [n_delete_ask]
    call check
    mov dword [pointer_x], 300
    mov dword [pointer_y], TEST_H - 20
    call ui_click
    xor esi, esi
    cmp dword [delete_armed], 0
    sete sil
    lea rdi, [n_delete_back]
    call check
    call close_detail
    add rsp, 8
    ret

; edi = action, esi = arg. Moves the pointer onto their region and redraws.
hover_hit:
    sub rsp, 8
    call find_hit
    test rax, rax
    jz .done
    call point_at_hit
    call update_hover
    call frame
.done:
    add rsp, 8
    ret

; Comments 11, 12 and 13 on the open issue: their events, then editing and
; deleting one by hand.
comment_tests:
    push rbx
    mov edi, ISSUE_ID
    call sync_open_issue
    mov byte [detail_loaded], 1
    xor ebx, ebx
.add:
    imul eax, ebx, CC_SIZE
    lea rdi, [comments + rax]
    lea ecx, [ebx + 11]
    mov [rdi + CC_ID], ecx
    mov dword [rdi + CC_AUTHOR], 1
    mov word [rdi + CC_LEN], 1
    lea ecx, [ebx + 'a']
    mov [rdi + CC_TEXT], cl
    inc ebx
    cmp ebx, 3
    jb .add
    mov dword [comment_count], 3

    lea rdi, [t_edited_event]
    mov esi, t_edited_event_len
    call rd_begin
    mov edi, EV_COMMENT_EDITED
    call on_comment_event
    call rd_ok
    xor esi, esi
    test eax, eax
    jz .edited
    cmp dword [comment_count], 3
    jne .edited
    cmp byte [comments + CC_SIZE + CC_TEXT], 'B'
    jne .edited
    cmp byte [comments + CC_SIZE + CC_EDITED], 1
    sete sil
.edited:
    lea rdi, [n_cmt_edited]
    call check

    lea rdi, [t_deleted_event]
    mov esi, t_deleted_event_len
    call rd_begin
    mov edi, EV_COMMENT_DELETED
    call on_comment_event
    call rd_ok
    xor esi, esi
    test eax, eax
    jz .deleted
    cmp dword [comment_count], 2
    jne .deleted
    cmp dword [comments + CC_ID], 12
    jne .deleted
    cmp dword [comments + CC_SIZE + CC_ID], 13
    sete sil
.deleted:
    lea rdi, [n_cmt_deleted]
    call check

    call rebuild_view
    call frame
    mov edi, A_COMMENT
    mov esi, 13
    call hover_hit
    mov edi, A_COMMENT
    mov esi, 13
    call actions_inset
    mov [comment_inset], eax
    mov edi, A_EDIT_COMMENT
    mov esi, 13
    call click_hit
    xor esi, esi
    test eax, eax
    jz .open
    cmp dword [editing_comment], 13
    jne .open
    cmp dword [focus], F_EDIT
    sete sil
.open:
    lea rdi, [n_cmt_open]
    call check

    mov edi, F_EDIT
    lea rsi, [t_x]
    call type_into
    mov edi, KEY_ENTER
    call field_command
    xor esi, esi
    cmp dword [pending_count], 1
    jne .saved
    cmp dword [editing_comment], 0
    jne .saved
    cmp word [view_comments + CC_SIZE + CC_LEN], 2
    jne .saved
    cmp word [view_comments + CC_SIZE + CC_TEXT], 'cx'
    jne .saved
    cmp byte [view_comments + CC_SIZE + CC_EDITED], 1
    sete sil
.saved:
    lea rdi, [n_cmt_saved]
    call check

    call frame
    mov edi, A_COMMENT
    mov esi, 12
    call hover_hit
    mov edi, A_DELETE_COMMENT
    mov esi, 12
    call click_hit
    xor esi, esi
    cmp dword [view_comment_count], 2
    jne .delete
    mov edi, A_DELETE_COMMENT
    mov esi, 12
    call click_hit
    cmp dword [view_comment_count], 1
    sete sil
.delete:
    lea rdi, [n_cmt_delete]
    call check
    mov dword [pending_count], 0
    call close_detail
    pop rbx
    ret

; The test issue has no priority and nobody assigned.
filter_tests:
    push rbx
    xor ebx, ebx
    mov dword [filter_priority], PRIO_URGENT
    lea rdi, [view_issues]
    call issue_shown
    test eax, eax
    jnz .hide
    mov dword [filter_priority], PRIO_NONE
    mov dword [filter_assignee], 1
    lea rdi, [view_issues]
    call issue_shown
    test eax, eax
    jnz .hide
    mov dword [filter_assignee], 0
    lea rdi, [view_issues]
    call issue_shown
    mov ebx, eax
.hide:
    mov esi, ebx
    lea rdi, [n_filter_hide]
    call check

    mov byte [list_dirty], 1
    call frame
    mov edi, A_UNFILTER
    mov esi, 3
    call click_hit
    xor esi, esi
    cmp dword [filter_assignee], -1
    jne .chip
    cmp dword [filter_priority], PRIO_NONE
    sete sil
.chip:
    lea rdi, [n_filter_chip]
    call check
    call clear_filters
    pop rbx
    ret

; The labels and projects dialog, with one label, "bug".
labels_tests:
    sub rsp, 8
    mov byte [labels + LB_NAME_LEN], 3
    mov dword [labels + LB_NAME], 'bug'
    call rebuild_view
    call open_labels_modal
    call frame
    mov edi, A_RENAME
    xor esi, esi
    call click_hit
    mov edi, F_RENAME
    lea rsi, [t_x]
    call type_into
    mov edi, KEY_ENTER
    call field_command
    xor esi, esi
    cmp dword [renaming], 0
    jne .renamed
    cmp byte [view_labels + LB_NAME_LEN], 4
    jne .renamed
    cmp dword [view_labels + LB_NAME], 'bugx'
    sete sil
.renamed:
    lea rdi, [n_rename]
    call check

    mov dword [filter_label], 0
    call frame
    mov edi, A_REMOVE_NAMED
    xor esi, esi
    call click_hit
    xor esi, esi
    cmp byte [view_labels + LB_NAME_LEN], 4
    jne .removed
    mov edi, A_REMOVE_NAMED
    xor esi, esi
    call click_hit
    cmp dword [filter_label], -1
    jne .removed
    cmp byte [view_labels + LB_NAME_LEN], 0
    sete sil
.removed:
    lea rdi, [n_remove_named]
    call check
    mov dword [pending_count], 0

    ; Someone else deletes it while we're typing its new name.
    mov byte [labels + LB_NAME_LEN], 3
    call rebuild_view
    xor edi, edi
    call start_rename
    mov byte [labels + LB_NAME_LEN], 0
    call rebuild_view
    mov edi, F_RENAME
    lea rsi, [t_x]
    call type_into
    mov edi, KEY_ENTER
    call field_command
    xor esi, esi
    cmp dword [pending_count], 0
    sete sil
    lea rdi, [n_rename_gone]
    call check
    mov byte [modal], M_NONE
    call rebuild_view
    add rsp, 8
    ret

; The change password dialog keeps nothing once it's gone.
password_tests:
    push rbx
    call open_password_modal
    mov edi, F_OLD_PASS
    lea rsi, [t_hello]
    call type_into
    mov edi, KEY_TAB
    call field_command
    mov edi, F_NEW_PASS
    lea rsi, [t_draft]
    call type_into
    mov edi, KEY_ESC
    call field_command
    xor ebx, ebx
    cmp byte [modal], M_NONE
    jne .done
    mov edi, F_OLD_PASS
    call field_len
    test eax, eax
    jnz .done
    mov edi, F_NEW_PASS
    call field_len
    test eax, eax
    jnz .done
    cmp byte [old_pass_buf], 0
    jne .done
    cmp byte [new_pass_buf], 0
    sete bl
.done:
    mov esi, ebx
    lea rdi, [n_password_esc]
    call check
    pop rbx
    ret

; Keys, a conversation, and hit regions under a clip.
input_tests:
    push rbx
    mov edi, 0
    call open_chat
    mov edi, F_MESSAGE
    lea rsi, [t_draft]
    call type_into
    mov edi, KEY_ESC
    call field_command
    mov edi, F_MESSAGE
    call field_len
    xor esi, esi
    cmp eax, 5
    jne .chat
    cmp byte [chat_open], 0
    sete sil
.chat:
    lea rdi, [n_chat_esc]
    call check

    mov dword [current_team], 0
    mov dword [team_count], 0
    call frame
    mov edi, A_NEW_ISSUE
    mov esi, -1
    call find_hit
    xor esi, esi
    test rax, rax
    sete sil
    lea rdi, [n_no_team]
    call check

    ; Only the part of a row inside the clip can be clicked.
    mov dword [hit_count], 0
    xor edi, edi
    mov esi, 100
    mov edx, 500
    mov ecx, 400
    call set_clip
    xor edi, edi
    mov esi, 50
    mov edx, 100
    mov ecx, 20
    mov r8d, A_FIELD
    mov r9d, F_USER
    call add_hit
    mov ebx, [hit_count]
    xor edi, edi
    mov esi, 90
    mov edx, 100
    mov ecx, 20
    mov r8d, A_FIELD
    mov r9d, F_USER
    call add_hit
    xor esi, esi
    test ebx, ebx
    jnz .clip
    cmp dword [hit_count], 1
    jne .clip
    cmp dword [hits + HIT_Y], 100
    jne .clip
    cmp dword [hits + HIT_H], 10
    sete sil
.clip:
    lea rdi, [n_clip_hit]
    call check
    call reset_clip
    pop rbx
    ret

; tz_parse picks the offset of the last transition at or before the time.
; edi = the time -> eax = the offset it finds
zone_at:
    push rdi
    lea rdi, [tz_file]
    lea rsi, [t_zone]
    mov ecx, t_zone_len
    rep movsb
    pop rdx
    mov esi, t_zone_len
    jmp tz_parse

; The server logs us out with the change password dialog half filled in.
; Leaves the client logged out.
logout_tests:
    push rbx
    call open_password_modal
    mov edi, F_OLD_PASS
    lea rsi, [t_hello]
    call type_into
    call sync_reset
    xor ebx, ebx
    cmp byte [modal], M_NONE
    jne .done
    cmp dword [focus], F_USER
    jne .done
    cmp byte [old_pass_buf], 0
    sete bl
.done:
    mov esi, ebx
    lea rdi, [n_logout_modal]
    call check
    pop rbx
    ret

; Runs last: it swaps the layout for the rest of the run.
keymap_tests:
    sub rsp, 8
    lea rsi, [t_keymap]
    mov edx, t_keymap_len
    call keymap_parse
    xor esi, esi
    cmp byte [keymap_plain + 16], 'a'       ; evdev codes, 8 under XKB's
    jne .done
    cmp byte [keymap_shift + 16], 'A'
    jne .done
    cmp byte [keymap_plain + 30], 'q'
    jne .done
    cmp byte [keymap_plain + 2], '&'
    jne .done
    cmp byte [keymap_shift + 2], '1'
    jne .done
    cmp byte [keymap_shift + 44], 'W'
    jne .done
    cmp byte [keymap_plain + 17], 0         ; a key the keymap doesn't have
    jne .done
    mov edi, 16                             ; types 'a' here, so it's Ctrl+A
    call shortcut_key
    cmp eax, KEY_A
    sete sil
.done:
    lea rdi, [n_keymap]
    call check
    add rsp, 8
    ret

; A second member, maya, for the tests that need someone else on the team.
add_maya:
    mov dword [member_count], 2
    mov dword [members + CM_SIZE + CM_ID], 2
    mov byte [members + CM_SIZE + CM_ROLE], ROLE_MEMBER
    mov byte [members + CM_SIZE + CM_NAME_LEN], 4
    mov eax, [t_maya]
    mov [members + CM_SIZE + CM_NAME], eax
    ret

; Team settings and the direct messages under the channels.
settings_tests:
    push rbx
    call add_maya
    mov edi, F_NONE
    call open_team_settings
    call frame
    xor ebx, ebx
    mov edi, A_SET_ROLE
    mov esi, 2
    call find_hit
    test rax, rax
    jz .owner
    mov edi, A_LEAVE
    mov esi, 1
    call find_hit
    test rax, rax
    jz .owner
    mov edi, A_REMOVE
    mov esi, 2
    call click_hit
    cmp dword [member_armed], 2             ; asks rather than removes
    jne .owner
    mov edi, A_FIELD
    mov esi, F_MEMBER
    call click_hit
    cmp dword [member_armed], 0
    sete bl
.owner:
    mov esi, ebx
    lea rdi, [n_settings]
    call check

    xor ebx, ebx
    mov byte [teams + CO_ROLE], ROLE_MEMBER
    call frame
    mov edi, A_REMOVE
    mov esi, 2
    call find_hit
    test rax, rax
    jnz .member
    mov edi, A_SET_ROLE
    mov esi, 2
    call find_hit
    test rax, rax
    jnz .member
    mov edi, A_LEAVE
    mov esi, 1
    call find_hit
    test rax, rax
    setnz bl
.member:
    mov esi, ebx
    lea rdi, [n_member_view]
    call check
    mov byte [teams + CO_ROLE], ROLE_OWNER

    call close_modal
    call frame
    xor ebx, ebx
    mov edi, A_CHAT
    mov esi, 1
    call find_hit
    test rax, rax
    jnz .rows
    mov edi, A_CHAT
    mov esi, 2
    call find_hit
    test rax, rax
    setnz bl
.rows:
    mov esi, ebx
    lea rdi, [n_dm_rows]
    call check
    mov dword [member_count], 1
    pop rbx
    ret

; A channel besides #general, from the sidebar to its deletion.
channel_tests:
    push rbx
    call add_maya
    mov dword [chan_count], 1
    mov byte [chans + CN_SLOT], 1
    mov dword [chans + CN_CREATOR], 1
    mov byte [chans + CN_NAME_LEN], 6
    lea rdi, [chans + CN_NAME]
    lea rsi, [t_design]
    mov edx, 6
    call put_mem
    call frame
    xor ebx, ebx
    mov edi, A_CHAT
    mov esi, CHANNEL_PEER + 1
    call click_hit
    test eax, eax
    jz .row
    cmp dword [chat_peer], CHANNEL_PEER + 1
    jne .row
    mov edi, A_CHANNEL_DIALOG
    mov esi, 1
    call find_hit
    test rax, rax
    setnz bl
.row:
    mov esi, ebx
    lea rdi, [n_chan_row]
    call check

    call ui_members_changed
    movzx esi, byte [chat_open]
    lea rdi, [n_chan_members]
    call check

    mov dword [chan_count], 0
    call channels_changed
    xor esi, esi
    cmp byte [chat_open], 0
    sete sil
    lea rdi, [n_chan_gone]
    call check

    mov dword [chan_count], 1
    mov edi, 1
    call open_channel_dialog
    call ui_team_opened
    xor esi, esi
    cmp byte [modal], M_NONE
    sete sil
    lea rdi, [n_chan_switch]
    call check
    mov dword [chan_count], 0
    mov dword [member_count], 1
    mov byte [modal], M_NONE
    mov dword [focus], F_NONE
    call frame
    pop rbx
    ret

; edi = field, esi = expected length, edx = its first byte -> eax = 1 if it matches
field_is:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, esi
    mov r12d, edx
    call field_addr
    xor ecx, ecx
    cmp [rax + FD_LEN], ebx
    jne .done
    test ebx, ebx
    jz .yes
    mov rax, [rax + FD_BUF]
    movzx edx, byte [rax]
    cmp edx, r12d
    jne .done
.yes:
    mov ecx, 1
.done:
    mov eax, ecx
    add rsp, 8
    pop r12
    pop rbx
    ret

; edi = key code, pressed with Ctrl and whatever's in esi, in the comment box
ctrl_key:
    sub rsp, 8
    or esi, MOD_CTRL
    mov [modifiers], esi
    mov esi, edi
    mov edi, F_COMMENT
    call field_key
    mov dword [modifiers], 0
    add rsp, 8
    ret

; Types "hi yo" key by key, undoes it a word at a time, then redoes it with both shortcuts.
undo_tests:
    push rbx
    push r12
    sub rsp, 8
    mov edi, F_COMMENT
    call field_clear
    lea r12, [t_hi_yo_keys]
.key:
    movzx esi, byte [r12]
    test esi, esi
    jz .typed
    mov edi, F_COMMENT
    call field_key
    inc r12
    jmp .key
.typed:
    xor ebx, ebx
    mov edi, KEY_Z
    xor esi, esi
    call ctrl_key
    mov edi, F_COMMENT
    mov esi, 2                              ; "hi"
    mov edx, 'h'
    call field_is
    test eax, eax
    jz .done
    mov edi, KEY_Z
    xor esi, esi
    call ctrl_key
    mov edi, F_COMMENT
    xor esi, esi
    xor edx, edx
    call field_is
    test eax, eax
    jz .done
    mov edi, KEY_Y
    xor esi, esi
    call ctrl_key
    mov edi, KEY_Z
    mov esi, MOD_SHIFT
    call ctrl_key
    mov edi, F_COMMENT
    mov esi, 5                              ; "hi yo"
    mov edx, 'h'
    call field_is
    mov ebx, eax
.done:
    mov esi, ebx
    lea rdi, [n_undo]
    call check
    mov edi, F_COMMENT
    call field_clear
    mov edi, KEY_Z
    xor esi, esi
    call ctrl_key
    mov edi, F_COMMENT
    xor esi, esi
    xor edx, edx
    call field_is
    mov esi, eax
    lea rdi, [n_undo_reset]
    call check
    add rsp, 8
    pop r12
    pop rbx
    ret

; The login screen's connection gets dropped for idling, so a login can
; land while it's coming back.
auth_tests:
    push rbx
    xor ebx, ebx
    mov byte [auth_busy], 0
    mov edi, F_USER
    lea rsi, [t_x]
    mov edx, 1
    call field_set
    mov edi, F_PASS
    lea rsi, [t_x]
    mov edx, 1
    call field_set
    mov byte [net_state], NET_CONNECTING
    mov edi, MSG_LOGIN
    call do_auth
    cmp byte [auth_queued], MSG_LOGIN
    jne .done
    cmp dword [auth_msg_len], 0
    jne .done
    call sync_on_offline
    cmp byte [auth_queued], 0
    jne .done
    cmp dword [auth_msg_len], 0
    setne bl
.done:
    mov byte [net_state], NET_OFF
    mov edi, F_USER
    call field_clear
    mov edi, F_PASS
    call field_clear
    mov esi, ebx
    lea rdi, [n_auth_wait]
    call check
    pop rbx
    ret

; The local time zone, from a zone file.
tz_tests:
    push rbx
    xor ebx, ebx
    mov edi, 500
    call zone_at
    cmp eax, 3600
    jne .done
    mov edi, 1500
    call zone_at
    cmp eax, -7200
    jne .done
    mov edi, 2500
    call zone_at
    cmp eax, 3600
    sete bl
.done:
    mov esi, ebx
    lea rdi, [n_tz]
    call check
    pop rbx
    ret
%include "tests/ui_messages.asm"
%include "tests/ui_controls.asm"
