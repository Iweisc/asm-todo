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
%include "wayland.asm"
%include "net.asm"
%include "sync.asm"
%include "ui.asm"
%include "input.asm"
%include "widgets.asm"
%include "menu.asm"
%include "views.asm"
%include "sidebar.asm"
%include "chat.asm"

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
    call input_tests
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
