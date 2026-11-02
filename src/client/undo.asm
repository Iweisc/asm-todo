; Undo and redo in text fields: Ctrl+Z, and Ctrl+Shift+Z or Ctrl+Y.
;
; Only the field being edited has a history, and moving on to another one
; starts it over. Typing is one step until a space or a different kind of
; edit, the way most editors group it. Password fields keep no history, so
; nothing typed in one sits in memory longer than the field does.

%define UNDO_MAX        32
%define UN_LEN          0               ; u16
%define UN_CURSOR       2               ; u16
%define UN_ANCHOR       4               ; u16
%define UN_TEXT         8               ; DESC_MAX bytes, the longest field
%define UN_SIZE         1512
fits UN_TEXT, DESC_MAX, UN_SIZE

section .data
undo_field:     dd F_NONE               ; the field the history is for

section .bss
alignb 4
undo_kind:      resd 1                  ; the kind of the last edit, 0 after an undo
undo_count:     resd 1
redo_count:     resd 1
undo_stack:     resb UNDO_MAX * UN_SIZE
redo_stack:     resb UNDO_MAX * UN_SIZE

section .text

; Copies a field's text and caret into a history entry. rdi = entry, rsi = field struct
undo_save:
    mov eax, [rsi + FD_LEN]
    mov [rdi + UN_LEN], ax
    mov eax, [rsi + FD_CURSOR]
    mov [rdi + UN_CURSOR], ax
    mov eax, [rsi + FD_ANCHOR]
    mov [rdi + UN_ANCHOR], ax
    mov edx, [rsi + FD_LEN]
    mov rsi, [rsi + FD_BUF]
    add rdi, UN_TEXT
    jmp put_mem

; Puts a history entry back into a field. rdi = field struct, rsi = entry
undo_load:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rbx + FD_BUF]
    mov esi, [rbx + FD_MAX]
    call wipe
    movzx edx, word [r12 + UN_LEN]
    mov [rbx + FD_LEN], edx
    movzx eax, word [r12 + UN_CURSOR]
    mov [rbx + FD_CURSOR], eax
    movzx eax, word [r12 + UN_ANCHOR]
    mov [rbx + FD_ANCHOR], eax
    mov dword [rbx + FD_SCROLL], 0
    mov rdi, [rbx + FD_BUF]
    lea rsi, [r12 + UN_TEXT]
    call put_mem
    mov byte [field_changed], 1
    mov byte [need_redraw], 1
    add rsp, 8
    pop r12
    pop rbx
    ret

; Pushes a field's state on a stack, dropping the oldest when it's full.
; rdi = stack, rsi = its count, rdx = field struct
undo_push:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp dword [r12], UNDO_MAX
    jb .room
    mov rdi, rbx
    lea rsi, [rbx + UN_SIZE]
    mov edx, (UNDO_MAX - 1) * UN_SIZE
    call memmove
    dec dword [r12]
.room:
    imul edi, [r12], UN_SIZE
    add rdi, rbx
    mov rsi, r13
    call undo_save
    inc dword [r12]
    pop r13
    pop r12
    pop rbx
    ret

; Before an edit: remembers the field as it is, unless the edit continues
; the step before. edi = field, esi = UK_*, edx = 1 to start a new step anyway
undo_note:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    call field_addr
    test dword [rax + FD_FLAGS], FF_MASKED
    jnz .done
    cmp ebx, [undo_field]
    je .same_field
    mov [undo_field], ebx
    xor ecx, ecx
    mov [undo_count], ecx
    mov [undo_kind], ecx
.same_field:
    mov dword [redo_count], 0
    test r13d, r13d
    jnz .step
    cmp r12d, UK_OTHER
    je .step
    cmp r12d, [undo_kind]
    je .done
.step:
    mov [undo_kind], r12d
    lea rdi, [undo_stack]
    lea rsi, [undo_count]
    mov rdx, rax
    call undo_push
.done:
    pop r13
    pop r12
    pop rbx
    ret

; The field got new text, so its history no longer applies. edi = field
undo_drop:
    cmp edi, [undo_field]
    jne .done
    mov dword [undo_field], F_NONE
.done:
    ret

; Logging out: drops the history and wipes the text it held.
undo_wipe:
    sub rsp, 8
    mov dword [undo_field], F_NONE
    lea rdi, [undo_stack]
    mov esi, UNDO_MAX * UN_SIZE
    call wipe
    lea rdi, [redo_stack]
    mov esi, UNDO_MAX * UN_SIZE
    call wipe
    add rsp, 8
    ret

; Ctrl+Z, or with esi = 1, redo. edi = field
undo_step:
    push rbx
    push r12
    push r13
    cmp edi, [undo_field]
    jne .done
    call field_addr
    mov rbx, rax
    lea r12, [undo_stack]                   ; taken from
    lea r13, [redo_stack]                   ; saved to
    lea rdi, [undo_count]
    lea rcx, [redo_count]
    test esi, esi
    jz .pick
    xchg r12, r13
    xchg rdi, rcx
.pick:
    cmp dword [rdi], 0
    je .done
    push rdi
    push rdi
    mov rdi, r13
    mov rsi, rcx
    mov rdx, rbx
    call undo_push
    pop rdi
    pop rdi
    dec dword [rdi]
    imul esi, [rdi], UN_SIZE
    add rsi, r12
    mov rdi, rbx
    call undo_load
    mov dword [undo_kind], 0                ; the next edit is a step of its own
.done:
    pop r13
    pop r12
    pop rbx
    ret
