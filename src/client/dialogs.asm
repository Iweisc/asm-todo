; The new issue and new team dialogs: opening, submitting and closing them.
; Drawing them is in views.asm.

section .text

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

; Creates the issue the dialog describes, if it has a title.
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

; Closes whatever dialog is open, wiping the password fields in case it held them.
close_modal:
    sub rsp, 8
    mov byte [modal], M_NONE
    mov edi, F_NONE
    call set_focus
    call clear_password_fields
    add rsp, 8
    ret

; Opens the new team dialog, empty.
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

; Creates the team the dialog describes, if it has a name.
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
    mov [fields + F_TEAM_KEY * FD_SIZE + FD_ANCHOR], edx
.done:
    ret
