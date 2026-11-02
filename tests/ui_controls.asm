; ui-test's checks of the right click menu, the filter menu's groups, where a
; drop goes, the send button, and reconnecting. ui_test.asm includes this at
; its end, having no room left of its own.

section .rodata
n_right_click:  db "a right click on an issue opens just its actions, at the pointer", 0
n_filter_groups: db "filter items say whether they're a priority or a person", 0
n_drop_field:   db "a drop goes to the open conversation's box, or else the open issue's", 0
n_send_button:  db "the send button sends what's in the message box", 0
n_resume_focus: db "a reconnect leaves the message box focused", 0
; MSG_AUTH_OK past the type byte: lewis, a zero token, no ops applied.
t_auth_resume:  dd 1
                db 5, "lewis"
                times 32 db 0
                dd 0
t_auth_resume_len equ $ - t_auth_resume

section .text

; Runs them, last, since sending leaves an op queued. logout_tests signed
; out before these, hence signing in again.
controls_tests:
    push rbx
    call sign_in
    call close_detail
    call frame
    xor ebx, ebx
    mov edi, A_ISSUE
    mov esi, ISSUE_ID
    call find_hit
    test rax, rax
    jz .right
    call point_at_hit
    call ui_right_click
    cmp byte [menu_context], 1
    jne .right
    cmp dword [menu_issue], ISSUE_ID
    jne .right
    call build_menu
    cmp dword [menu_count], 7               ; status, priority, assignee, labels, project, copy, delete
    sete bl
.right:
    call close_menu
    mov esi, ebx
    lea rdi, [n_right_click]
    call check

    mov edi, MK_FILTER
    xor esi, esi
    call open_menu
    call build_menu
    xor ebx, ebx                            ; items in the wrong group
    xor edx, edx                            ; priorities
    xor ecx, ecx
.item:
    cmp ecx, [menu_count]
    jae .items
    imul eax, ecx, MI_SIZE
    movzx r8d, byte [menu_items + rax + MI_GROUP]
    mov eax, [menu_items + rax + MI_ICON]
    cmp eax, IC_PRIORITY
    jne .person
    inc edx
    cmp r8d, FG_PRIORITY
    je .next
    inc ebx
.person:
    cmp eax, IC_AVATAR
    jne .next
    cmp r8d, FG_ASSIGNEE
    je .next
    inc ebx
.next:
    inc ecx
    jmp .item
.items:
    call close_menu
    xor esi, esi
    test ebx, ebx
    jnz .groups
    cmp edx, PRIO_COUNT
    sete sil
.groups:
    lea rdi, [n_filter_groups]
    call check

    xor ebx, ebx
    mov byte [chat_open], 1
    mov dword [detail_issue], ISSUE_ID
    call drop_field
    cmp eax, F_MESSAGE
    jne .dropped
    mov byte [chat_open], 0
    call drop_field
    cmp eax, F_COMMENT
    jne .dropped
    mov dword [detail_issue], 0
    call drop_field
    cmp eax, F_NONE
    sete bl
.dropped:
    mov byte [chat_open], 0
    mov dword [detail_issue], 0
    mov esi, ebx
    lea rdi, [n_drop_field]
    call check

    xor ebx, ebx
    xor edi, edi
    call open_chat
    mov edi, F_MESSAGE
    lea rsi, [t_hello]
    call type_into
    call frame
    mov edi, A_SEND
    mov esi, F_MESSAGE
    call click_hit
    test eax, eax
    jz .sent
    mov edi, F_MESSAGE
    xor esi, esi
    xor edx, edx
    call field_is
    mov ebx, eax
.sent:
    mov esi, ebx
    lea rdi, [n_send_button]
    call check
    call resume_tests
    call close_detail
    pop rbx
    ret

; The session resuming after a dropped connection, with the message box focused.
resume_tests:
    sub rsp, 8
    mov edi, F_MESSAGE
    call set_focus
    lea rdi, [t_auth_resume]
    mov esi, t_auth_resume_len
    call rd_begin
    call on_auth_ok
    call rd_ok
    xor esi, esi
    test eax, eax
    jz .done
    cmp dword [focus], F_MESSAGE
    sete sil
.done:
    lea rdi, [n_resume_focus]
    call check
    add rsp, 8
    ret
