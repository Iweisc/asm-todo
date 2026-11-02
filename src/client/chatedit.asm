; Editing and deleting messages in the open conversation. Your own you can
; edit and delete, and an owner can delete anyone's in a channel. Unlike
; comments these go straight to the server rather than through the op
; queue, so they need a connection.

section .bss
alignb 4
editing_message:    resd 1              ; the message open for editing, 0 for none
message_armed:      resd 1              ; the message whose Delete was clicked once, 0 for none

section .text

; edi = message id -> rax = its row in view_chat, or 0
find_view_message:
    lea rax, [view_chat]
    mov ecx, [view_chat_count]
    test edi, edi
    jz .none
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + CH_ID], edi
    je .done
    add rax, CH_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; edi = message id -> rax = its row in chat_msgs, or 0
find_chat_message:
    lea rax, [chat_msgs]
    mov ecx, [chat_count]
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + CH_ID], edi
    je .done
    add rax, CH_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; MSG_CHAT_EDITED: the open conversation shows a message's new text.
on_chat_edited:
    push rbx
    sub rsp, CH_SIZE + 8
    call rd_u32
    mov ebx, eax
    mov rdi, rsp
    call read_message
    cmp byte [rd_bad], 0
    jne .done
    cmp ebx, [current_team]
    jne .done
    cmp byte [chat_open], 0
    je .done
    mov edi, [rsp + CH_ID]
    call find_chat_message
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, rsp
    mov edx, CH_SIZE
    call put_mem
    call rebuild_chat
.done:
    add rsp, CH_SIZE + 8
    pop rbx
    ret

; MSG_CHAT_DELETED: the message leaves the open conversation, and stops
; being edited or asked about.
on_chat_deleted:
    push rbx
    push r12
    sub rsp, 8
    call rd_u32
    mov ebx, eax
    call rd_u32
    mov r12d, eax
    cmp byte [rd_bad], 0
    jne .done
    cmp ebx, [current_team]
    jne .done
    cmp r12d, [message_armed]
    jne .editing
    mov dword [message_armed], 0
.editing:
    cmp r12d, [editing_message]
    jne .find
    call stop_comment_edit
.find:
    mov edi, r12d
    call find_chat_message
    test rax, rax
    jz .done
    mov rdi, rax
    lea rsi, [rax + CH_SIZE]
    imul edx, [chat_count], CH_SIZE
    lea rcx, [chat_msgs + rdx]
    mov rdx, rcx
    sub rdx, rsi                            ; the rows after it
    call memmove
    dec dword [chat_count]
    call rebuild_chat
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; rdi = view message -> eax = 1 if we can delete it, edx = 1 if we can edit it
message_rights:
    xor eax, eax
    xor edx, edx
    cmp dword [rdi + CH_ID], 0
    je .done                                ; not on the server yet
    mov ecx, [my_id]
    cmp [rdi + CH_AUTHOR], ecx
    jne .others
    mov eax, 1
    mov edx, 1
    ret
.others:
    cmp dword [chat_peer], 0                ; owners, and only in channels
    jg .done
    sub rsp, 8
    call am_owner
    xor edx, edx
    add rsp, 8
.done:
    ret

; Opens a message for editing in place. edi = message id
start_message_edit:
    push rbx
    mov ebx, edi
    call find_view_message
    test rax, rax
    jz .done
    mov [editing_message], ebx
    mov dword [editing_comment], 0
    lea rsi, [rax + CH_TEXT]
    movzx edx, word [rax + CH_LEN]
    mov edi, F_EDIT
    call field_set
    mov edi, F_EDIT
    call set_focus
.done:
    pop rbx
    ret

; Enter in the edit box: saves whichever of a comment or a message is open.
save_edit:
    cmp dword [editing_message], 0
    je save_comment_edit
    push rbx
    push r12
    push r13
    mov edi, [editing_message]
    call find_view_message
    test rax, rax
    jz .close
    mov rbx, rax
    mov edi, F_EDIT
    call field_trimmed
    test edx, edx
    jz .close                               ; emptied: deleting is its own button
    mov r12, rsi
    mov r13d, edx
    movzx ecx, word [rbx + CH_LEN]
    cmp edx, ecx
    jne .send
    lea rdi, [rbx + CH_TEXT]
    call mem_eq
    test eax, eax
    jnz .close
.send:
    mov edi, MSG_EDIT_MESSAGE
    mov esi, [editing_message]
    mov rdx, r12
    mov ecx, r13d
    call sync_message_change
.close:
    call stop_comment_edit
    pop r13
    pop r12
    pop rbx
    ret

; The first click on Delete asks, the second deletes. edi = message id
click_delete_message:
    cmp edi, [message_armed]
    je .sure
    mov [message_armed], edi
    ret
.sure:
    mov dword [message_armed], 0
    mov esi, edi
    mov edi, MSG_DELETE_MESSAGE
    xor ecx, ecx
    jmp sync_message_change

; edi = MSG_EDIT_MESSAGE or MSG_DELETE_MESSAGE, esi = message id, rdx = the
; new text and ecx its length, for an edit
sync_message_change:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, ebx
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    mov esi, r12d
    call wr_u32
    cmp ebx, MSG_EDIT_MESSAGE
    jne .send
    mov rsi, r13
    mov edx, r14d
    call wr_str16
.send:
    call send_built
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; edi = width -> eax = the height draw_comment_editor will take for what's in the edit box
edit_box_height:
    push rbx
    mov ebx, edi
    mov edi, F_EDIT
    call field_addr
    mov rdi, [rax + FD_BUF]
    mov esi, [rax + FD_LEN]
    lea edx, [ebx - 24]
    mov ecx, ST_BODY
    call text_height
    add eax, 24 + 30
    pop rbx
    ret

; A message's Edit and Delete, while the pointer is on it or Delete is asking.
; rdi = view message, esi = the right edge, edx = the strip's top
draw_message_actions:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov esi, [rbx + CH_ID]
    test esi, esi
    jz .done
    cmp esi, [editing_message]
    je .done
    cmp esi, [message_armed]
    je .shown
    mov edi, A_MESSAGE
    mov edx, [rbx + CH_IMAGE + RI_ID]
    call actions_hovered
    test eax, eax
    jz .done
.shown:
    mov rdi, rbx
    call message_rights
    test eax, eax
    jz .done
    mov r8d, edx
    mov esi, [rbx + CH_ID]
    xor r9d, r9d
    cmp esi, [message_armed]
    sete r9b
    mov edi, A_MESSAGE
    mov edx, r12d
    mov ecx, r13d
    call draw_actions
.done:
    pop r13
    pop r12
    pop rbx
    ret
