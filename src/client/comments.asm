; Comments on the open issue: reading them off the wire, the events that add,
; change and remove them, editing and deleting your own, and drawing one.
; Owners can delete anyone's. Edits and deletions are ops like any other, so
; they show right away and wait in the queue while offline. Messages share
; the Edit and Delete links drawn here.

%define ACTIONS_W 96                    ; room for Edit and "Delete?"

section .rodata
text s_edit,            "Edit"
text s_delete_short,    "Delete"
text s_delete_sure,     "Delete?"
text s_edited,          " (edited)"
text s_edit_hint,       "Enter to save, Esc to cancel"

section .bss
alignb 4
editing_comment:    resd 1              ; the comment open for editing, 0 for none
comment_armed:      resd 1              ; the comment whose Delete was clicked once, 0 for none

section .text

; Reads a comment off the wire into a row. rdi = row
read_comment:
    push rbx
    mov rbx, rdi
    call rd_u32
    mov [rbx + CC_ID], eax
    call rd_u32
    mov [rbx + CC_AUTHOR], eax
    call rd_u32
    mov [rbx + CC_CREATED], eax
    call rd_str16
    cmp edx, COMMENT_MAX
    jbe .fits
    mov byte [rd_bad], 1
    xor edx, edx
.fits:
    mov [rbx + CC_LEN], dx
    mov byte [rbx + CC_PENDING], 0
    lea rdi, [rbx + CC_TEXT]
    mov rsi, rax
    call put_mem
    call rd_u8
    mov [rbx + CC_EDITED], al
    lea rdi, [rbx + CC_IMAGE]
    call read_image_ref
    pop rbx
    ret

; rdi = rows, esi = how many, edx = comment id -> rax = its row, or 0
find_comment:
    test esi, esi
    jz .none
    cmp [rdi + CC_ID], edx
    je .found
    add rdi, CC_SIZE
    dec esi
    jmp find_comment
.found:
    mov rax, rdi
    ret
.none:
    xor eax, eax
    ret

; Takes a row out of a list of comments, keeping the order.
; rdi = the row, rsi = the list's count, rdx = the list
drop_comment:
    mov eax, [rsi]
    dec dword [rsi]
    imul eax, eax, CC_SIZE
    add rdx, rax                            ; the old end
    lea rsi, [rdi + CC_SIZE]
    sub rdx, rsi
    jmp memmove

; EV_COMMENT, EV_COMMENT_EDITED and EV_COMMENT_DELETED. They only matter to
; the open issue, once its comments have loaded. edi = event kind
on_comment_event:
    push rbx
    push r12
    sub rsp, CC_SIZE + 8
    mov r12d, edi
    call rd_u32
    mov ebx, eax                            ; the issue
    cmp r12d, EV_COMMENT_DELETED
    je .deleted
    mov rdi, rsp
    call read_comment
    cmp byte [rd_bad], 0
    jne .done
    cmp ebx, [detail_issue]
    jne .done
    cmp byte [detail_loaded], 0
    je .done                                ; ISSUE_DETAIL will have it
    cmp r12d, EV_COMMENT_EDITED
    je .edited
    mov eax, [comment_count]
    cmp eax, ISSUE_COMMENT_MAX
    jae .done
    inc dword [comment_count]
    imul eax, eax, CC_SIZE
    lea rdi, [comments + rax]
    jmp .copy
.edited:
    lea rdi, [comments]
    mov esi, [comment_count]
    mov edx, [rsp + CC_ID]
    call find_comment
    test rax, rax
    jz .done
    mov rdi, rax
.copy:
    mov rsi, rsp
    mov ecx, CC_SIZE
    rep movsb
    jmp .done
.deleted:
    call rd_u32
    mov r12d, eax
    cmp byte [rd_bad], 0
    jne .done
    cmp ebx, [detail_issue]
    jne .done
    lea rdi, [comments]
    mov esi, [comment_count]
    mov edx, r12d
    call find_comment
    test rax, rax
    jz .gone
    mov rdi, rax
    lea rsi, [comment_count]
    lea rdx, [comments]
    call drop_comment
.gone:
    cmp r12d, [editing_comment]
    jne .done
    call stop_comment_edit
.done:
    add rsp, CC_SIZE + 8
    pop r12
    pop rbx
    ret

; A pending edit or deletion, applied to view_comments. rdi = the pending op
apply_comment_op:
    push rbx
    mov rbx, rdi
    lea rdi, [view_comments]
    mov esi, [view_comment_count]
    mov edx, [rbx + PO_ISSUE]
    call find_comment
    test rax, rax
    jz .done
    cmp byte [rbx + PO_KIND], OP_DELETE_COMMENT
    je .delete
    mov byte [rax + CC_PENDING], 1
    mov byte [rax + CC_EDITED], 1
    movzx ecx, word [rbx + PO_BODY_LEN]
    mov [rax + CC_LEN], cx
    lea rdi, [rax + CC_TEXT]
    lea rsi, [rbx + PO_BODY]
    rep movsb
    jmp .done
.delete:
    mov rdi, rax
    lea rsi, [view_comment_count]
    lea rdx, [view_comments]
    call drop_comment
.done:
    pop rbx
    ret

; edi = comment, rsi = its new text, edx = length -> eax = 1 if queued
sync_edit_comment:
    mov ecx, OP_EDIT_COMMENT
    xor r8d, r8d                            ; an edit keeps the image it had
    xor r9d, r9d
    jmp sync_text

; edi = comment
sync_delete_comment:
    push rdi
    mov edi, OP_DELETE_COMMENT
    call new_op
    pop rdi
    mov [rax + PO_ISSUE], edi
    jmp queue_draft

; Opens a comment for editing, its text in F_EDIT. edi = comment
start_comment_edit:
    push rbx
    mov ebx, edi
    lea rdi, [view_comments]
    mov esi, [view_comment_count]
    mov edx, ebx
    call find_comment
    test rax, rax
    jz .done
    mov [editing_comment], ebx
    lea rsi, [rax + CC_TEXT]
    movzx edx, word [rax + CC_LEN]
    mov edi, F_EDIT
    call field_set
    mov edi, F_EDIT
    call set_focus
.done:
    pop rbx
    ret

; Closes the comment or message being edited without saving.
stop_comment_edit:
    sub rsp, 8
    mov dword [editing_comment], 0
    mov dword [editing_message], 0
    mov edi, F_EDIT
    call field_clear
    cmp dword [focus], F_EDIT
    jne .done
    mov dword [focus], F_NONE
.done:
    mov byte [need_redraw], 1
    add rsp, 8
    ret

; Sends the edited comment if its text changed, and closes it. An emptied
; one keeps its old text: deleting is its own button.
save_comment_edit:
    push rbx
    push r12
    push r13
    lea rdi, [view_comments]
    mov esi, [view_comment_count]
    mov edx, [editing_comment]
    call find_comment
    test rax, rax
    jz .close
    mov rbx, rax
    mov edi, F_EDIT
    call field_trimmed
    test edx, edx
    jz .close
    mov r12, rsi
    mov r13d, edx
    movzx ecx, word [rbx + CC_LEN]
    cmp edx, ecx
    jne .send
    lea rdi, [rbx + CC_TEXT]
    call mem_eq
    test eax, eax
    jnz .close
.send:
    mov edi, [editing_comment]
    mov rsi, r12
    mov edx, r13d
    call sync_edit_comment
.close:
    call stop_comment_edit
    pop r13
    pop r12
    pop rbx
    ret

; The first click on Delete asks, the second deletes. edi = comment
click_delete_comment:
    cmp edi, [comment_armed]
    je .sure
    mov [comment_armed], edi
    ret
.sure:
    mov dword [comment_armed], 0
    cmp edi, [editing_comment]
    jne .send
    push rdi
    call stop_comment_edit
    pop rdi
.send:
    jmp sync_delete_comment

; rdi = view comment -> eax = 1 if we can delete it, edx = 1 if we can edit it
comment_rights:
    xor eax, eax
    xor edx, edx
    cmp dword [rdi + CC_ID], 0
    je .done                                ; not on the server yet
    mov ecx, [my_id]
    cmp [rdi + CC_AUTHOR], ecx
    jne .owner
    mov eax, 1
    mov edx, 1
    ret
.owner:
    push rdx
    call current_team_row
    pop rdx
    test rax, rax
    jz .done
    cmp byte [rax + CO_ROLE], ROLE_OWNER
    sete al
    movzx eax, al
.done:
    ret

; edi = A_COMMENT or A_MESSAGE, esi = its id, edx = its image or 0
; -> eax = 1 if the pointer is on it, its Edit or Delete, or its image
actions_hovered:
    xor eax, eax
    mov ecx, [hover_action]
    cmp ecx, A_IMAGE
    je .image
    sub ecx, edi
    cmp ecx, 2                              ; itself, its Edit or its Delete
    ja .done
    mov edx, esi
.image:
    test edx, edx
    jz .done
    cmp edx, [hover_arg]
    sete al
.done:
    ret

; Edit and Delete as links ending at a comment's or message's right edge.
; Delete turns red and asks once it's been clicked. edi = A_COMMENT or
; A_MESSAGE, whose Edit and Delete actions follow it, esi = its id, edx = the
; right edge, ecx = the baseline, r8d = 1 to show Edit too, r9d = 1 if Delete is asking
draw_actions:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov ebx, edi
    mov ebp, esi
    mov r12d, edx
    mov r13d, ecx
    mov r14d, r8d
    mov r15d, r9d
    ; A message without a header has them on its first line, so blank the
    ; text under them.
    lea edi, [r12d - ACTIONS_W]
    lea esi, [r13d - 15]
    mov edx, ACTIONS_W
    mov ecx, 20
    mov r8d, C_PANEL
    call fill_rect
    lea rdx, [s_delete_short]
    mov ecx, s_delete_short_len
    mov r8d, C_DIM
    test r15d, r15d
    jz .delete
    lea rdx, [s_delete_sure]
    mov ecx, s_delete_sure_len
    mov r8d, C_DANGER
.delete:
    mov edi, r12d
    mov esi, r13d
    call draw_link
    mov r12d, eax
    mov edi, eax
    mov esi, r13d
    lea r8d, [ebx + 2]
    mov r9d, ebp
    call add_link_hit
    test r14d, r14d
    jz .done
    lea edi, [r12d - 14]
    mov esi, r13d
    lea rdx, [s_edit]
    mov ecx, s_edit_len
    mov r8d, C_DIM
    call draw_link
    mov edi, eax
    mov esi, r13d
    lea r8d, [ebx + 1]
    mov r9d, ebp
    call add_link_hit
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; A comment's Edit and Delete, while the pointer is on it or Delete is asking.
; rdi = view comment, esi = the right edge, edx = the baseline
draw_comment_actions:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov esi, [rbx + CC_ID]
    test esi, esi
    jz .done
    cmp esi, [editing_comment]
    je .done
    cmp esi, [comment_armed]
    je .shown
    mov edi, A_COMMENT
    mov edx, [rbx + CC_IMAGE + RI_ID]
    call actions_hovered
    test eax, eax
    jz .done
.shown:
    mov rdi, rbx
    call comment_rights
    test eax, eax
    jz .done
    mov r8d, edx
    mov esi, [rbx + CC_ID]
    xor r9d, r9d
    cmp esi, [comment_armed]
    sete r9b
    mov edi, A_COMMENT
    mov edx, r12d
    mov ecx, r13d
    call draw_actions
.done:
    pop r13
    pop r12
    pop rbx
    ret

; The box editing a comment, and the hint under it.
; edi = x, esi = top, edx = width -> eax = the height used
draw_comment_editor:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14d, edi
    mov r12d, esi
    mov r15d, edx
    mov edi, F_EDIT
    call field_addr
    mov rdi, [rax + FD_BUF]
    mov esi, [rax + FD_LEN]
    lea edx, [r15d - 24]
    mov ecx, ST_BODY
    call text_height
    lea ebx, [eax + 24]
    mov edi, F_EDIT
    call field_focused
    mov r8d, C_LINE
    mov ecx, C_ACCENT
    test eax, eax
    cmovnz r8d, ecx
    mov edi, r14d
    mov esi, r12d
    mov edx, r15d
    mov ecx, ebx
    mov r9d, C_RAISED
    mov r10d, 8
    call outline_rrect
    mov edi, r14d
    mov esi, r12d
    mov edx, r15d
    mov ecx, ebx
    mov r8d, A_FIELD
    mov r9d, F_EDIT
    call add_hit
    mov edi, F_EDIT
    lea esi, [r14d + 12]
    lea edx, [r12d + 12]
    lea ecx, [r15d - 24]
    call draw_area
    mov edi, r14d
    lea esi, [r12 + rbx + 20]
    lea rdx, [s_edit_hint]
    mov ecx, s_edit_hint_len
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_text
    lea eax, [ebx + 30]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; One comment: who and when, its actions, and its text or the box editing it.
; rdi = view comment, esi = x, edx = top, ecx = width -> eax = the height used
draw_comment:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r14d, esi
    mov r12d, edx
    mov r15d, ecx
    mov edi, [rbx + CC_AUTHOR]
    call user_name
    push rsi
    push rdx
    mov r8, rsi
    mov edi, r14d
    mov esi, r12d
    mov edx, 18
    mov ecx, [rbx + CC_AUTHOR]
    call draw_avatar
    pop rcx
    pop rdx
    lea edi, [r14d + 28]
    lea esi, [r12d + 14]
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    mov [rsp], eax
    lea rdi, [scratch]
    mov esi, [rbx + CC_CREATED]
    call put_ago
    cmp byte [rbx + CC_EDITED], 0
    je .when
    lea rsi, [s_edited]
    mov edx, s_edited_len
    call put_mem
.when:
    mov rcx, rdi
    mov edi, [rsp]
    add edi, 8
    lea esi, [r12d + 14]
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_scratch
    mov eax, [rbx + CC_ID]
    cmp eax, [editing_comment]
    jne .text
    test eax, eax
    jz .text
    lea edi, [r14d + 28]
    lea esi, [r12d + 26]
    lea edx, [r15d - 28]
    call draw_comment_editor
    lea ebp, [eax + 44]
    jmp .actions
.text:
    xor eax, eax
    cmp word [rbx + CC_LEN], 0
    je .image                               ; just an image
    mov r9d, INK(C_TEXT, ST_BODY)
    mov eax, INK(C_DIM, ST_BODY)            ; not on the server yet
    cmp byte [rbx + CC_PENDING], 0
    cmovne r9d, eax
    lea rdi, [rbx + CC_TEXT]
    movzx esi, word [rbx + CC_LEN]
    lea edx, [r14d + 28]
    lea ecx, [r12d + 24]
    lea r8d, [r15d - 28]
    call draw_wrapped
.image:
    mov [rsp], eax                          ; the text's height
    lea rdi, [rbx + CC_IMAGE]
    lea esi, [r15d - 28]
    call image_ref_height
    add eax, [rsp]
    lea ebp, [eax + 44]
    ; The whole comment, so hovering anywhere on it shows its actions.
    mov edi, r14d
    lea esi, [r12d - 6]
    mov edx, r15d
    lea ecx, [ebp - 8]
    mov r8d, A_COMMENT
    mov r9d, [rbx + CC_ID]
    call add_hit
    ; The image after the comment's region, so clicks on it open it.
    lea rdi, [rbx + CC_IMAGE]
    lea esi, [r14d + 28]
    mov edx, [rsp]
    lea edx, [edx + r12d + 24]
    lea ecx, [r15d - 28]
    call draw_image_ref
.actions:
    mov rdi, rbx
    mov esi, r14d
    add esi, r15d
    lea edx, [r12d + 14]
    call draw_comment_actions
    mov eax, ebp
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
