; The dialog for renaming and deleting the team's labels and projects. New
; ones are still made from an issue's label and project menus.
;
; An item is a label slot, or LABEL_SLOTS + a project's number - 1, so one
; number covers both columns.

%define LABELS_W        600
%define LABELS_COL_W    262
%define LABELS_ROW_H    40

section .rodata
text s_labels_title,    "Labels and projects"
text s_labels_head,     "Labels"
text s_projects_head,   "Projects"
text s_rename,          "Rename"
text s_none_yet,        "None yet"
text s_labels_hint,     "Make new ones from an issue's label or project menu."
text s_rename_hint,     "Enter to save, Esc to cancel"

section .bss
alignb 4
renaming:       resd 1                  ; the item being renamed + 1, 0 for none
named_armed:    resd 1                  ; the item whose Delete was clicked once + 1

section .text

; edi = item -> rax = its view row, edx = its op kind, ecx = its slot as the op numbers it,
; r8d = the longest name it takes
named_row:
    cmp edi, LABEL_SLOTS
    jae .project
    imul eax, edi, LB_SIZE
    lea rax, [view_labels + rax]
    mov edx, OP_SET_LABEL
    mov ecx, edi
    mov r8d, LABEL_NAME_MAX
    ret
.project:
    lea ecx, [edi - LABEL_SLOTS]
    imul eax, ecx, PJ_SIZE
    lea rax, [view_projects + rax]
    mov edx, OP_SET_PROJECT
    inc ecx
    mov r8d, PROJECT_NAME_MAX
    ret

; Opens the dialog, nothing being renamed or deleted yet.
open_labels_modal:
    mov byte [menu_open], 0
    mov byte [modal], M_LABELS
    xor eax, eax
    mov [renaming], eax
    mov [named_armed], eax
    mov edi, F_NONE
    jmp set_focus

; Opens an item's name for editing. edi = item
start_rename:
    push rbx
    mov ebx, edi
    call named_row
    ; Labels take shorter names than projects, so the field stops where the item does.
    mov [fields + F_RENAME * FD_SIZE + FD_MAX], r8d
    lea rsi, [rax + LB_NAME]
    movzx edx, byte [rax + LB_NAME_LEN]
    mov edi, F_RENAME
    call field_set
    lea eax, [ebx + 1]
    mov [renaming], eax
    mov dword [named_armed], 0
    mov edi, F_RENAME
    call set_focus
    pop rbx
    ret

; Closes the name being edited without saving.
stop_rename:
    sub rsp, 8
    mov dword [renaming], 0
    mov edi, F_RENAME
    call field_clear
    mov dword [focus], F_NONE
    mov byte [need_redraw], 1
    add rsp, 8
    ret

; Sends the edited name if it changed, and closes it. An emptied one keeps
; its old name: deleting is its own button.
save_rename:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov edi, [renaming]
    dec edi
    js .close
    call named_row
    cmp byte [rax + LB_NAME_LEN], 0
    je .close                               ; someone deleted it meanwhile
    mov rbx, rax
    mov r12d, edx
    mov r13d, ecx
    mov r14d, r8d
    mov edi, F_RENAME
    call field_trimmed
    test edx, edx
    jz .close
    cmp edx, r14d
    cmova edx, r14d
    mov r8d, edx
    mov rcx, rsi
    movzx eax, byte [rbx + LB_NAME_LEN]
    cmp eax, edx
    jne .send
    lea rdi, [rbx + LB_NAME]
    push rcx
    push r8
    call mem_eq
    pop r8
    pop rcx
    test eax, eax
    jnz .close
.send:
    mov edi, r12d
    mov esi, r13d
    mov edx, [rbx + LB_COLOR]
    call sync_set_named
.close:
    call stop_rename
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; The first click on Delete asks, the second deletes the label or project,
; and takes it off every issue. edi = item
click_remove_named:
    push rbx
    lea ebx, [edi + 1]
    cmp ebx, [named_armed]
    je .sure
    mov [named_armed], ebx
    pop rbx
    ret
.sure:
    mov dword [named_armed], 0
    dec ebx
    mov edi, ebx
    call named_row
    mov edi, edx
    mov esi, ecx
    mov edx, [rax + LB_COLOR]
    xor ecx, ecx
    xor r8d, r8d
    push rsi
    call sync_set_named
    pop rsi
    ; A filter on it would hide every issue.
    cmp ebx, LABEL_SLOTS
    jae .project
    cmp esi, [filter_label]
    jne .done
    mov dword [filter_label], -1
    jmp .refilter
.project:
    cmp esi, [filter_project]
    jne .done
    mov dword [filter_project], 0
.refilter:
    mov byte [list_dirty], 1
.done:
    pop rbx
    ret

; Text ending at a right edge, small, for a link next to others.
; edi = right edge, esi = baseline, rdx = text, ecx = length, r8d = color
; -> eax = its left x, edx = its width
draw_link:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    mov r15d, r8d
    mov rdi, rdx
    mov esi, ecx
    mov edx, ST_SMALL
    call text_width
    sub ebx, eax
    push rax
    push rax
    mov edi, ebx
    mov esi, r12d
    mov rdx, r13
    mov ecx, r14d
    mov r8d, r15d
    call draw_text
    pop rdx
    pop rdx
    mov eax, ebx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; edi = left x, edx = width, esi = baseline, r8d = action, r9d = arg.
; The hit region for a link draw_link drew.
add_link_hit:
    sub esi, 13
    mov ecx, 18
    jmp add_hit

; One label or project: its dot and name with Rename and Delete, or the box
; renaming it. edi = item, esi = x, edx = top
draw_named_row:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    call named_row
    mov rbp, rax
    lea eax, [ebx + 1]
    cmp eax, [renaming]
    jne .shown
    mov edi, F_RENAME
    mov esi, r12d
    mov edx, r13d
    mov ecx, LABELS_COL_W
    call draw_field_box
    jmp .done
.shown:
    lea edi, [r12d * 4 + 24]
    lea esi, [r13d * 4 + 72]
    mov edx, 18
    mov ecx, [rbp + LB_COLOR]
    call aa_disc
    lea r14d, [r12d + LABELS_COL_W]         ; links, from the right
    lea rdx, [s_delete_short]
    mov ecx, s_delete_short_len
    mov r8d, C_DIM
    lea eax, [ebx + 1]
    cmp eax, [named_armed]
    jne .delete
    lea rdx, [s_delete_sure]
    mov ecx, s_delete_sure_len
    mov r8d, C_DANGER
.delete:
    mov edi, r14d
    lea esi, [r13d + 23]
    call draw_link
    mov r14d, eax
    mov edi, eax
    lea esi, [r13d + 23]
    mov r8d, A_REMOVE_NAMED
    mov r9d, ebx
    call add_link_hit
    lea edi, [r14d - 14]
    lea esi, [r13d + 23]
    lea rdx, [s_rename]
    mov ecx, s_rename_len
    mov r8d, C_DIM
    call draw_link
    mov r14d, eax
    mov edi, eax
    lea esi, [r13d + 23]
    mov r8d, A_RENAME
    mov r9d, ebx
    call add_link_hit
    lea edi, [r12d + 20]
    lea esi, [r13d + 23]
    lea rdx, [rbp + LB_NAME]
    movzx ecx, byte [rbp + LB_NAME_LEN]
    mov r8d, INK(C_TEXT, ST_BODY)
    lea r9d, [r14d - 16]
    sub r9d, edi
    call draw_text_fit
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; A column of named items under a heading. edi = first item, esi = how many
; slots, edx = x, ecx = top, r8 = heading, r9d = its length
draw_named_column:
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
    mov edi, edx
    mov esi, ecx
    mov rdx, r8
    mov ecx, r9d
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    add r13d, 10
    xor r15d, r15d                          ; rows drawn
.item:
    test ebp, ebp
    jz .empty
    mov edi, ebx
    call named_row
    cmp byte [rax + LB_NAME_LEN], 0
    je .next
    mov edi, ebx
    mov esi, r12d
    mov edx, r13d
    call draw_named_row
    add r13d, LABELS_ROW_H
    inc r15d
.next:
    inc ebx
    dec ebp
    jmp .item
.empty:
    test r15d, r15d
    jnz .done
    mov edi, r12d
    lea esi, [r13d + 23]
    lea rdx, [s_none_yet]
    mov ecx, s_none_yet_len
    mov r8d, INK(C_FAINT, ST_BODY)
    call draw_text
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; rdi = rows, esi = their size, edx = how many -> eax = how many have names
count_named:
    xor eax, eax
.row:
    test edx, edx
    jz .done
    cmp byte [rdi + LB_NAME_LEN], 0
    je .next
    inc eax
.next:
    add rdi, rsi
    dec edx
    jmp .row
.done:
    ret

; Labels on the left, projects on the right, as tall as the longer column.
draw_labels_modal:
    push rbx
    push r12
    push r13
    lea rdi, [view_labels]
    mov esi, LB_SIZE
    mov edx, LABEL_SLOTS
    call count_named
    mov ebx, eax
    lea rdi, [view_projects]
    mov esi, PJ_SIZE
    mov edx, PROJECT_SLOTS
    call count_named
    cmp eax, ebx
    cmova ebx, eax
    mov eax, 1                              ; room for "None yet"
    cmp ebx, eax
    cmovb ebx, eax
    imul esi, ebx, LABELS_ROW_H
    add esi, 150
    mov r13d, esi
    mov edi, LABELS_W
    call modal_box
    mov ebx, eax
    mov r12d, edx
    lea edi, [ebx + 28]
    lea esi, [r12d + 46]
    lea rdx, [s_labels_title]
    mov ecx, s_labels_title_len
    mov r8d, INK(C_TEXT, ST_TITLE)
    call draw_text
    xor edi, edi
    mov esi, LABEL_SLOTS
    lea edx, [ebx + 28]
    lea ecx, [r12d + 90]
    lea r8, [s_labels_head]
    mov r9d, s_labels_head_len
    call draw_named_column
    mov edi, LABEL_SLOTS
    mov esi, PROJECT_SLOTS
    lea edx, [ebx + 28 + LABELS_COL_W + 20]
    lea ecx, [r12d + 90]
    lea r8, [s_projects_head]
    mov r9d, s_projects_head_len
    call draw_named_column
    ; The hint sits on the bottom edge, whatever the columns' heights.
    mov eax, [renaming]
    lea rdx, [s_labels_hint]
    mov ecx, s_labels_hint_len
    lea rsi, [s_rename_hint]
    mov edi, s_rename_hint_len
    test eax, eax
    cmovnz rdx, rsi
    cmovnz ecx, edi
    lea edi, [ebx + 28]
    lea esi, [r12d + r13d - 24]
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_text
    pop r13
    pop r12
    pop rbx
    ret
