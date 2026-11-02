; ui-test's checks of editing, deleting and opening the images of messages,
; and of their Edit and Delete matching a comment's. ui_test.asm includes this
; at its end.

section .rodata
n_msg_edited:   db "an edited message shows its new text and its mark", 0
n_msg_deleted:  db "a deleted message leaves the conversation", 0
n_msg_edit:     db "hovering your message offers Edit, which opens it in place", 0
n_same_actions: db "a comment's Edit and Delete sit where a message's do", 0
n_msg_image:    db "a message's image opens over the conversation, and Esc closes just it", 0
n_image_gone:   db "the server saying an image is gone ends a download partway in", 0
; MSG_CHAT_EDITED for message 22, with image 77, and MSG_CHAT_DELETED for 21, past the type byte.
t_chat_edited:  dd 1, 22, 1, 0, 0
                dw 1
                db "Z", 1
                dd 77
                dw 640, 480
t_chat_edited_len equ $ - t_chat_edited
t_chat_deleted: dd 1, 21
t_chat_deleted_len equ $ - t_chat_deleted
; MSG_IMAGE saying image 77 can't be sent: no bytes, at offset 0, past the type byte.
t_image_gone:   dd 77, 0, 0
                dw 0
t_image_gone_len equ $ - t_image_gone

section .bss
alignb 4
comment_inset:  resd 1                  ; from actions_inset, for message_tests to match

section .text

; edi = A_COMMENT or A_MESSAGE, esi = its id -> eax = how far its Delete
; ends from its right edge, or -1 if either isn't on screen
actions_inset:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    call find_hit
    test rax, rax
    jz .none
    mov r13d, [rax + HIT_X]
    add r13d, [rax + HIT_W]
    lea edi, [ebx + 2]
    mov esi, r12d
    call find_hit
    test rax, rax
    jz .none
    sub r13d, [rax + HIT_X]
    sub r13d, [rax + HIT_W]
    mov eax, r13d
    jmp .done
.none:
    mov eax, -1
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Editing and deleting messages in #general.
message_tests:
    push rbx
    xor edi, edi
    call open_chat
    mov byte [chat_loaded], 1
    xor ebx, ebx
.add:
    imul eax, ebx, CH_SIZE
    lea rdi, [chat_msgs + rax]
    lea ecx, [ebx + 21]
    mov [rdi + CH_ID], ecx
    mov dword [rdi + CH_AUTHOR], 1
    mov word [rdi + CH_LEN], 1
    lea ecx, [ebx + 'a']
    mov [rdi + CH_TEXT], cl
    inc ebx
    cmp ebx, 3
    jb .add
    mov dword [chat_count], 3
    call rebuild_chat

    lea rdi, [t_chat_edited]
    mov esi, t_chat_edited_len
    call rd_begin
    call on_chat_edited
    call rd_ok
    xor esi, esi
    test eax, eax
    jz .edited
    cmp byte [view_chat + CH_SIZE + CH_TEXT], 'Z'
    jne .edited
    cmp byte [view_chat + CH_SIZE + CH_EDITED], 1
    sete sil
.edited:
    lea rdi, [n_msg_edited]
    call check

    lea rdi, [t_chat_deleted]
    mov esi, t_chat_deleted_len
    call rd_begin
    call on_chat_deleted
    call rd_ok
    xor esi, esi
    test eax, eax
    jz .deleted
    cmp dword [view_chat_count], 2
    jne .deleted
    cmp dword [view_chat + CH_ID], 22
    jne .deleted
    cmp dword [view_chat + CH_SIZE + CH_ID], 23
    sete sil
.deleted:
    lea rdi, [n_msg_deleted]
    call check

    call frame
    xor ebx, ebx
    mov edi, A_MESSAGE
    mov esi, 22
    call find_hit
    test rax, rax
    jz .edit
    call point_at_hit
    call frame                              ; hover follows the frame before
    call frame
    mov edi, A_MESSAGE
    mov esi, 22
    call actions_inset
    xor esi, esi
    test eax, eax
    js .same
    cmp eax, [comment_inset]
    sete sil
.same:
    lea rdi, [n_same_actions]
    call check
    mov edi, A_EDIT_MESSAGE
    mov esi, 22
    call click_hit
    test eax, eax
    jz .edit
    cmp dword [editing_message], 22
    jne .edit
    cmp dword [focus], F_EDIT
    jne .edit
    mov edi, KEY_ESC
    call field_command
    cmp dword [editing_message], 0
    sete bl
.edit:
    mov esi, ebx
    lea rdi, [n_msg_edit]
    call check

    call frame
    xor ebx, ebx
    mov edi, A_IMAGE
    mov esi, 77
    call click_hit
    test eax, eax
    jz .image
    cmp byte [modal], M_IMAGE
    jne .image
    cmp dword [view_id], 77
    jne .image
    mov edi, KEY_ESC
    call ui_key
    cmp byte [modal], M_NONE
    jne .image
    movzx ebx, byte [chat_open]
.image:
    mov esi, ebx
    lea rdi, [n_msg_image]
    call check

    mov dword [dl_id], 77
    mov dword [dl_got], IMAGE_PART
    lea rdi, [t_image_gone]
    mov esi, t_image_gone_len
    call rd_begin
    call on_image
    xor esi, esi
    cmp dword [dl_id], 0
    sete sil
    lea rdi, [n_image_gone]
    call check
    call close_detail
    mov dword [chat_count], 0
    call rebuild_chat
    pop rbx
    ret
