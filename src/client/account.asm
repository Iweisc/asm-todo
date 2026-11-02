; Changing your password: the dialog, sending it, and the answer. A wrong
; current password comes back as an ERROR, which shows like any other and
; leaves the dialog open to try again.

%define PASSWORD_MODAL_W 440

section .rodata
text s_password_title,  "Change password"
text s_current_password, "Current password"
text s_new_password,    "New password, at least 8 characters"
text s_change_password, "Change password"
text s_changing,        "Changing..."
text st_password_changed, "password changed. Your other sessions were logged out"

section .bss
password_busy:  resb 1                  ; sent, waiting for the answer

section .text

; Opens the dialog with both fields empty.
open_password_modal:
    sub rsp, 8
    mov byte [menu_open], 0
    mov byte [modal], M_PASSWORD
    call clear_password_fields
    mov edi, F_OLD_PASS
    call set_focus
    add rsp, 8
    ret

; Wipes both fields, which matters more here than anywhere else.
clear_password_fields:
    sub rsp, 8
    mov edi, F_OLD_PASS
    call field_clear
    mov edi, F_NEW_PASS
    call field_clear
    add rsp, 8
    ret

; Enter in either field: moves on to the new password, or sends both.
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

; MSG_PASSWORD_CHANGED: closes the dialog and says so.
on_password_changed:
    sub rsp, 8
    mov byte [password_busy], 0
    cmp byte [modal], M_PASSWORD
    jne .said
    call close_modal
.said:
    lea rsi, [st_password_changed]
    mov edx, st_password_changed_len
    call set_status
    add rsp, 8
    ret

; The dialog: both fields, and a button that waits while the change is out.
draw_password_modal:
    push rbx
    push r12
    sub rsp, 8
    mov edi, PASSWORD_MODAL_W
    mov esi, 296
    call modal_box
    mov ebx, eax
    mov r12d, edx
    lea edi, [ebx + 28]
    lea esi, [r12d + 46]
    lea rdx, [s_password_title]
    mov ecx, s_password_title_len
    mov r8d, INK(C_TEXT, ST_TITLE)
    call draw_text
    lea edi, [ebx + 28]
    lea esi, [r12d + 84]
    lea rdx, [s_current_password]
    mov ecx, s_current_password_len
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    mov edi, F_OLD_PASS
    lea esi, [ebx + 28]
    lea edx, [r12d + 94]
    mov ecx, PASSWORD_MODAL_W - 56
    call draw_field_box
    lea edi, [ebx + 28]
    lea esi, [r12d + 154]
    lea rdx, [s_new_password]
    mov ecx, s_new_password_len
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    mov edi, F_NEW_PASS
    lea esi, [ebx + 28]
    lea edx, [r12d + 164]
    mov ecx, PASSWORD_MODAL_W - 56
    call draw_field_box
    lea edi, [ebx + 28]
    lea esi, [r12d + 236]
    lea rdx, [s_change_password]
    mov ecx, s_change_password_len
    mov r8d, A_CHANGE_PASSWORD
    cmp byte [password_busy], 0
    je .button
    lea rdx, [s_changing]
    mov ecx, s_changing_len
    mov r8d, A_BLOCK
.button:
    mov r9d, BTN_PRIMARY
    call draw_button
    add rsp, 8
    pop r12
    pop rbx
    ret
