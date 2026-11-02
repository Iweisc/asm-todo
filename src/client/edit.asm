; Editing text in a field: typing, the selection, words, lines of wrapped
; text, and selecting with the mouse. Copy and paste are in clipboard.asm.
;
; A field's selection runs between FD_ANCHOR and FD_CURSOR, in either order,
; and there's none when they're equal. Whatever moves the caret without Shift
; moves the anchor with it.

%define DOUBLE_CLICK_MS 400

section .rodata
; Characters pasted text often has that the font and the server don't take,
; and what stands in for them: code point, character.
paste_subs:
    dd 0x00a0, ' ', 0x2018, "'", 0x2019, "'", 0x201a, "'", 0x2032, "'"
    dd 0x201c, '"', 0x201d, '"', 0x201e, '"', 0x2033, '"'
    dd 0x2010, '-', 0x2011, '-', 0x2012, '-', 0x2013, '-', 0x2014, '-'
    dd 0x2015, '-', 0x2212, '-', 0x2022, '*', 0x2026, '.'
    dd 0

section .data
sel_drag:       dd F_NONE               ; the field a held button is selecting in
wrap_sel_from:  dd -1                   ; the selection draw_wrapped highlights, for the next call only
wrap_sel_to:    dd -1

section .bss
alignb 4
pointer_time:   resd 1                  ; the last button press, ms on the compositor's clock
click_time:     resd 1
click_x:        resd 1
click_y:        resd 1
click_count:    resd 1                  ; 1, 2 or 3 presses in a row on the same spot

section .text

; rdi = field struct -> eax = where the selection starts, edx = where it ends
sel_range:
    mov eax, [rdi + FD_ANCHOR]
    mov edx, [rdi + FD_CURSOR]
    cmp eax, edx
    jbe .done
    xchg eax, edx
.done:
    ret

; Removes characters and leaves the caret where they were.
; rdi = field struct, esi = start, edx = end
delete_range:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    sub r13d, r12d
    jz .done
    mov rdi, [rbx + FD_BUF]
    add rdi, r12
    lea rsi, [rdi + r13]
    mov edx, [rbx + FD_LEN]
    sub edx, r12d
    sub edx, r13d
    call memmove
    sub [rbx + FD_LEN], r13d
    mov rdi, [rbx + FD_BUF]                 ; don't leave a password's tail behind
    mov eax, [rbx + FD_LEN]
    add rdi, rax
    mov esi, r13d
    call wipe
    mov byte [field_changed], 1
.done:
    mov [rbx + FD_CURSOR], r12d
    mov [rbx + FD_ANCHOR], r12d
    pop r13
    pop r12
    pop rbx
    ret

; rdi = field struct -> eax = 1 if there was a selection to delete
delete_selection:
    sub rsp, 8
    call sel_range
    cmp eax, edx
    je .none
    mov esi, eax
    call delete_range
    mov eax, 1
    jmp .done
.none:
    xor eax, eax
.done:
    add rsp, 8
    ret

; edi = field, esi = character. Replaces the selection, then inserts at the
; caret if there's room.
field_insert:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, esi
    call field_addr
    mov rbx, rax
    mov rdi, rax
    call delete_selection
    mov ecx, [rbx + FD_LEN]
    cmp ecx, [rbx + FD_MAX]
    jae .done
    mov edx, [rbx + FD_CURSOR]
    mov rsi, [rbx + FD_BUF]
    add rsi, rdx
    lea rdi, [rsi + 1]
    sub ecx, edx
    mov edx, ecx
    call memmove
    mov rax, [rbx + FD_BUF]
    mov ecx, [rbx + FD_CURSOR]
    mov [rax + rcx], r12b
    inc ecx
    mov [rbx + FD_CURSOR], ecx
    mov [rbx + FD_ANCHOR], ecx
    inc dword [rbx + FD_LEN]
    mov byte [field_changed], 1
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; The next character of pasted UTF-8 as one the font and the server take:
; printable ASCII and newlines. Tabs become spaces, typographic quotes and
; dashes their plain versions, and anything else a '?'.
; rsi = bytes, edx = how many are left -> eax = the character, or 0 to drop
; it, edx = bytes used, ecx = how many times to insert it
clean_char:
    mov ecx, 1
    mov r8d, edx
    mov edx, 1
    movzx eax, byte [rsi]
    cmp eax, 10
    je .done
    cmp eax, 9
    je .space
    cmp eax, ' '
    jb .drop
    cmp eax, 0x7f
    jb .done
    je .drop
    mov r9d, 2
    and eax, 0x1f
    cmp byte [rsi], 0xc0
    jb .unknown                             ; a stray continuation byte
    cmp byte [rsi], 0xe0
    jb .decode
    mov r9d, 3
    and eax, 0x0f
    cmp byte [rsi], 0xf0
    jb .decode
    mov r9d, 4
    and eax, 0x07
    cmp byte [rsi], 0xf8
    jae .unknown
.decode:
    cmp r9d, r8d
    ja .unknown                             ; cut off at the end
.continuation:
    cmp edx, r9d
    jae .lookup
    movzx r10d, byte [rsi + rdx]
    mov r11d, r10d
    and r11d, 0xc0
    cmp r11d, 0x80
    jne .invalid
    shl eax, 6
    and r10d, 0x3f
    or eax, r10d
    inc edx
    jmp .continuation
.lookup:
    lea r10, [paste_subs]
.sub:
    mov r11d, [r10]
    test r11d, r11d
    jz .unknown
    cmp r11d, eax
    je .found
    add r10, 8
    jmp .sub
.found:
    cmp eax, 0x2026                         ; an ellipsis is three dots
    jne .one
    mov ecx, 3
.one:
    mov eax, [r10 + 4]
    ret
.invalid:
    mov edx, 1
.unknown:
    mov eax, '?'
    ret
.space:
    mov eax, ' '
    ret
.drop:
    xor eax, eax
.done:
    ret

; Replaces the selection with text, cleaned up by clean_char, as much as fits.
; A single-line field gets spaces for its newlines.
; edi = field, rsi = text, edx = length
field_insert_text:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, edi
    mov r13, rsi
    mov r14d, edx
    call field_addr
    mov rbx, rax
    mov rdi, rax
    call delete_selection
    mov r15d, [rbx + FD_FLAGS]
    and r15d, FF_MULTILINE
.next:
    test r14d, r14d
    jz .done
    mov rsi, r13
    mov edx, r14d
    call clean_char
    add r13, rdx
    sub r14d, edx
    test eax, eax
    jz .next
    cmp eax, 10
    jne .put
    test r15d, r15d
    jnz .put
    mov eax, ' '
.put:
    mov [rsp], eax
    mov ebp, ecx
.repeat:
    mov edi, r12d
    mov esi, [rsp]
    call field_insert
    dec ebp
    jnz .repeat
    jmp .next
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = character -> eax = 1 if it's part of a word. Clobbers only eax.
is_word_char:
    cmp edi, '_'
    je .yes
    mov eax, edi
    or eax, 0x20
    sub eax, 'a'
    cmp eax, 'z' - 'a'
    jbe .yes
    lea eax, [edi - '0']
    cmp eax, 9
    jbe .yes
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret

; rdi = field struct, esi = position -> eax = where the word before it starts
word_left:
    mov r8, [rdi + FD_BUF]
    mov edx, esi
.gap:
    test edx, edx
    jz .done
    movzx edi, byte [r8 + rdx - 1]
    call is_word_char
    test eax, eax
    jnz .word
    dec edx
    jmp .gap
.word:
    test edx, edx
    jz .done
    movzx edi, byte [r8 + rdx - 1]
    call is_word_char
    test eax, eax
    jz .done
    dec edx
    jmp .word
.done:
    mov eax, edx
    ret

; rdi = field struct, esi = position -> eax = where the word after it ends
word_right:
    mov r8, [rdi + FD_BUF]
    mov r9d, [rdi + FD_LEN]
    mov edx, esi
.gap:
    cmp edx, r9d
    jae .done
    movzx edi, byte [r8 + rdx]
    call is_word_char
    test eax, eax
    jnz .word
    inc edx
    jmp .gap
.word:
    cmp edx, r9d
    jae .done
    movzx edi, byte [r8 + rdx]
    call is_word_char
    test eax, eax
    jz .done
    inc edx
    jmp .word
.done:
    mov eax, edx
    ret

; Selects the word at the caret. Between words it takes the one character
; after the caret instead. rdi = field struct
select_word:
    mov r8, [rdi + FD_BUF]
    mov r9d, [rdi + FD_LEN]
    mov r10, rdi
    mov ecx, [rdi + FD_CURSOR]
.back:
    test ecx, ecx
    jz .forward
    movzx edi, byte [r8 + rcx - 1]
    call is_word_char
    test eax, eax
    jz .forward
    dec ecx
    jmp .back
.forward:
    mov edx, [r10 + FD_CURSOR]
.ahead:
    cmp edx, r9d
    jae .set
    movzx edi, byte [r8 + rdx]
    call is_word_char
    test eax, eax
    jz .set
    inc edx
    jmp .ahead
.set:
    cmp ecx, edx
    jne .store
    cmp edx, r9d
    jae .store
    inc edx
.store:
    mov [r10 + FD_ANCHOR], ecx
    mov [r10 + FD_CURSOR], edx
    ret

; The line a position is on, wrapped the way draw_wrapped lays the field out
; at its last drawn width. A single-line field is one line.
; rdi = field struct, esi = position -> eax = where the line starts,
; edx = characters on it, ecx = where the next one starts, or -1 if it's the last
line_at:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12d, esi
    xor ebp, ebp                            ; this line's start
    mov r14d, [rbx + FD_LEN]
    mov r13d, r14d
    mov ecx, -1
    test dword [rbx + FD_FLAGS], FF_MULTILINE
    jz .found
    cmp dword [rbx + FD_W], 0
    je .found
.line:
    mov rsi, [rbx + FD_BUF]
    add rsi, rbp
    mov edx, r14d
    sub edx, ebp
    mov ecx, [rbx + FD_W]
    mov r8d, [rbx + FD_STYLE]
    call wrap_line
    mov r13d, eax
    lea ecx, [ebp + edx]
    cmp ecx, r14d
    jae .last
    cmp r12d, ecx
    jb .found
    mov ebp, ecx
    jmp .line
.last:
    ; Text ending in a newline has an empty line after it.
    mov ecx, -1
    test r14d, r14d
    jz .found
    mov rax, [rbx + FD_BUF]
    cmp byte [rax + r14 - 1], 10
    jne .found
    lea eax, [ebp + r13d]
    cmp eax, r14d
    je .found                               ; that newline isn't this line's
    mov ecx, r14d
    cmp r12d, r14d
    jb .found
    mov ebp, r14d
    xor r13d, r13d
    mov ecx, -1
.found:
    mov eax, ebp
    mov edx, r13d
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Where Up or Down takes the caret: the same x on the line above or below,
; or the field's start or end past the first or last line.
; rdi = field struct, esi = -1 up, +1 down -> eax = the position
line_step:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12d, esi
    mov esi, [rbx + FD_CURSOR]
    call line_at
    mov ebp, eax
    mov r13d, ecx
    mov rdi, [rbx + FD_BUF]
    add rdi, rbp
    mov esi, [rbx + FD_CURSOR]
    sub esi, ebp
    mov edx, [rbx + FD_STYLE]
    call text_width
    mov r14d, eax                           ; the caret's x on its line
    test r12d, r12d
    js .up
    mov eax, [rbx + FD_LEN]
    cmp r13d, -1
    je .done
    mov esi, r13d
    jmp .other
.up:
    xor eax, eax
    test ebp, ebp
    jz .done
    lea esi, [ebp - 1]
.other:
    mov rdi, rbx
    call line_at
    mov ebp, eax
    mov rdi, [rbx + FD_BUF]
    add rdi, rbp
    mov esi, edx
    mov edx, [rbx + FD_STYLE]
    mov ecx, r14d
    call line_index_at
    add eax, ebp
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Where an arrow, Home or End key moves the caret, with Ctrl for words or
; the whole field. rdi = field struct, esi = key code -> eax = the position, or -1
caret_target:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    mov ecx, [modifiers]
    cmp r12d, KEY_LEFT
    je .left
    cmp r12d, KEY_RIGHT
    je .right
    cmp r12d, KEY_UP
    je .up
    cmp r12d, KEY_DOWN
    je .down
    cmp r12d, KEY_HOME
    je .home
    cmp r12d, KEY_END
    je .end
    mov eax, -1
    jmp .done
.left:
    call sel_range
    test ecx, MOD_SHIFT                     ; plain Left leaves a selection at its start
    jnz .left_move
    cmp eax, edx
    jne .done
.left_move:
    mov esi, [rbx + FD_CURSOR]
    test ecx, MOD_CTRL
    jz .left_one
    call word_left
    jmp .done
.left_one:
    lea eax, [esi - 1]
    test esi, esi
    cmovz eax, esi
    jmp .done
.right:
    call sel_range
    mov eax, edx
    test ecx, MOD_SHIFT
    jnz .right_move
    cmp eax, [rbx + FD_ANCHOR]
    jne .done
    cmp eax, [rbx + FD_CURSOR]
    jne .done
.right_move:
    mov esi, [rbx + FD_CURSOR]
    test ecx, MOD_CTRL
    jz .right_one
    call word_right
    jmp .done
.right_one:
    lea eax, [esi + 1]
    cmp esi, [rbx + FD_LEN]
    cmovae eax, esi
    jmp .done
.up:
    mov esi, -1
    call line_step
    jmp .done
.down:
    mov esi, 1
    call line_step
    jmp .done
.home:
    xor eax, eax
    test ecx, MOD_CTRL
    jnz .done
    mov esi, [rbx + FD_CURSOR]
    call line_at
    jmp .done
.end:
    mov eax, [rbx + FD_LEN]
    test ecx, MOD_CTRL
    jnz .done
    mov esi, [rbx + FD_CURSOR]
    call line_at
    add eax, edx
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; Editing keys in a field. edi = field, esi = key code
; -> eax = 1 if holding the key should repeat it
field_key:
    push rbx
    push r12
    push r13
    mov r12d, esi
    mov r13d, edi
    mov edi, r12d
    call key_char
    test eax, eax
    jz .special
    mov edi, r13d
    mov esi, eax
    call field_insert
    jmp .repeat
.special:
    mov edi, r13d
    call field_addr
    mov rbx, rax
    test dword [modifiers], MOD_CTRL
    jz .keys
    mov edi, r12d
    call shortcut_key
    mov r12d, eax
    cmp r12d, KEY_A
    je .all
    cmp r12d, KEY_C
    je .copy
    cmp r12d, KEY_X
    je .cut
    cmp r12d, KEY_V
    je .paste
.keys:
    cmp r12d, KEY_BACKSPACE
    je .backspace
    cmp r12d, KEY_DELETE
    je .delete
    mov rdi, rbx
    mov esi, r12d
    call caret_target
    cmp eax, -1
    je .no_repeat
    mov [rbx + FD_CURSOR], eax
    test dword [modifiers], MOD_SHIFT
    jnz .repeat
    mov [rbx + FD_ANCHOR], eax
    jmp .repeat
.backspace:
    mov rdi, rbx
    call delete_selection
    test eax, eax
    jnz .repeat
    mov esi, [rbx + FD_CURSOR]
    test esi, esi
    jz .repeat
    dec esi
    test dword [modifiers], MOD_CTRL
    jz .back_range
    mov rdi, rbx
    mov esi, [rbx + FD_CURSOR]
    call word_left
    mov esi, eax
.back_range:
    mov rdi, rbx
    mov edx, [rbx + FD_CURSOR]
    call delete_range
    jmp .repeat
.delete:
    mov rdi, rbx
    call delete_selection
    test eax, eax
    jnz .repeat
    mov edx, [rbx + FD_CURSOR]
    cmp edx, [rbx + FD_LEN]
    jae .repeat
    inc edx
    test dword [modifiers], MOD_CTRL
    jz .forward_range
    mov rdi, rbx
    mov esi, [rbx + FD_CURSOR]
    call word_right
    mov edx, eax
.forward_range:
    mov rdi, rbx
    mov esi, [rbx + FD_CURSOR]
    call delete_range
    jmp .repeat
.all:
    mov dword [rbx + FD_ANCHOR], 0
    mov eax, [rbx + FD_LEN]
    mov [rbx + FD_CURSOR], eax
    jmp .no_repeat
.copy:
    mov rdi, rbx
    call copy_selection
    jmp .no_repeat
.cut:
    mov rdi, rbx
    call copy_selection
    test eax, eax
    jz .no_repeat
    mov rdi, rbx
    call delete_selection
    jmp .no_repeat
.paste:
    mov edi, r13d
    call clip_paste
.no_repeat:
    xor eax, eax
    jmp .out
.repeat:
    mov eax, 1
.out:
    pop r13
    pop r12
    pop rbx
    ret

; Puts a field's selection on the clipboard. A password's never leaves it.
; rdi = field struct -> eax = 1 if something was copied
copy_selection:
    sub rsp, 8
    xor eax, eax
    test dword [rdi + FD_FLAGS], FF_MASKED
    jnz .done
    call sel_range
    sub edx, eax
    jz .none
    mov rsi, [rdi + FD_BUF]
    add rsi, rax
    call clip_copy
    mov eax, 1
    jmp .done
.none:
    xor eax, eax
.done:
    add rsp, 8
    ret

; -> eax = how many presses in a row this one makes, up to 3: quick enough
; and close enough to the one before
count_click:
    mov ecx, [pointer_time]
    mov eax, ecx
    sub eax, [click_time]
    mov [click_time], ecx
    cmp eax, DOUBLE_CLICK_MS
    jae .first
    mov eax, [pointer_x]
    sub eax, [click_x]
    add eax, 4
    cmp eax, 8
    ja .first
    mov eax, [pointer_y]
    sub eax, [click_y]
    add eax, 4
    cmp eax, 8
    ja .first
    mov eax, [click_count]
    test eax, eax
    jz .first
    inc eax
    cmp eax, 3
    jbe .store
    mov eax, 3
    jmp .store
.first:
    mov eax, 1
.store:
    mov [click_count], eax
    mov ecx, [pointer_x]
    mov [click_x], ecx
    mov ecx, [pointer_y]
    mov [click_y], ecx
    ret

; A press on a field: puts the caret there and starts a drag selection.
; With Shift it extends the selection, twice selects a word and three times
; everything. The open issue's title and description start being edited.
; edi = field
click_field:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    call count_click
    mov r12d, eax
    cmp ebx, [focus]
    je .focused
    cmp ebx, F_TITLE
    je .edit
    cmp ebx, F_DESC
    je .edit
    mov edi, ebx
    call set_focus
    jmp .place
.edit:
    mov edi, ebx
    call begin_edit
    mov [sel_drag], ebx
    jmp .done
.focused:
    test dword [modifiers], MOD_SHIFT
    jz .place
    mov edi, ebx
    call place_caret
    mov [sel_drag], ebx
    jmp .done
.place:
    mov edi, ebx
    call place_caret
    mov edi, ebx
    call field_addr
    mov rdi, rax
    mov eax, [rdi + FD_CURSOR]
    mov [rdi + FD_ANCHOR], eax
    cmp r12d, 2
    jb .drag
    je .word
    mov dword [rdi + FD_ANCHOR], 0
    mov eax, [rdi + FD_LEN]
    mov [rdi + FD_CURSOR], eax
    jmp .done
.word:
    call select_word
    jmp .done
.drag:
    mov [sel_drag], ebx
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; The pointer moved with the button held on a field: the caret follows it and
; the anchor stays. -> eax = 1 if a selection drag is going on
drag_select:
    sub rsp, 8
    xor eax, eax
    mov edi, [sel_drag]
    cmp edi, F_NONE
    je .done
    cmp edi, [focus]
    jne .stop
    call place_caret
    mov byte [need_redraw], 1
    mov eax, 1
    jmp .done
.stop:
    mov dword [sel_drag], F_NONE
    xor eax, eax
.done:
    add rsp, 8
    ret

; Highlights what's selected on one wrapped line, from wrap_sel_from and
; wrap_sel_to. A selection running on past the line's text, over its break,
; shows a little past the end.
; edi = x, esi = line top, rdx = the line's text, ecx = its offset in the
; field, r8d = characters on it, r9d = style
draw_line_selection:
    mov eax, [wrap_sel_from]
    cmp eax, [wrap_sel_to]
    jge .none
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov r12d, edi
    mov r13d, esi
    mov rbx, rdx
    mov ebp, ecx
    mov r14d, r8d
    mov r15d, r9d
    mov eax, [wrap_sel_from]
    sub eax, ebp
    xor ecx, ecx
    cmp eax, ecx
    cmovl eax, ecx
    cmp eax, r14d
    jg .out
    mov [rsp], eax                          ; first selected character on the line
    mov eax, [wrap_sel_to]
    sub eax, ebp
    jle .out
    xor edx, edx
    cmp eax, r14d
    jle .end
    mov eax, r14d
    mov edx, 6
.end:
    mov [rsp + 4], eax                      ; and the end
    mov [rsp + 8], edx
    mov rdi, rbx
    mov esi, [rsp]
    mov edx, r15d
    call text_width
    mov [rsp + 12], eax
    mov rdi, rbx
    mov esi, [rsp + 4]
    mov edx, r15d
    call text_width
    add eax, [rsp + 8]
    sub eax, [rsp + 12]
    jle .out
    mov edx, eax
    mov edi, r12d
    add edi, [rsp + 12]
    mov esi, r13d
    mov ecx, [wrap_lh]
    mov r8d, C_SELECTION
    call fill_rect
.out:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
.none:
    ret

; The selection of a single-line field drawn by draw_field, behind its text.
; rdi = field struct, rsi = the text as shown, edx = x, ecx = baseline
draw_field_selection:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov rbp, rsi
    mov r12d, edx
    mov r13d, ecx
    call sel_range
    cmp eax, edx
    je .done
    mov ecx, [rbx + FD_SCROLL]
    sub eax, ecx
    xor r8d, r8d
    cmp eax, r8d
    cmovl eax, r8d
    sub edx, ecx
    jle .done
    mov r15d, edx
    add rbp, rcx
    mov rdi, rbp
    mov esi, eax
    mov edx, [rbx + FD_STYLE]
    call text_width
    mov r14d, eax
    mov rdi, rbp
    mov esi, r15d
    mov edx, [rbx + FD_STYLE]
    call text_width
    sub eax, r14d
    jle .done
    mov edx, eax
    lea edi, [r12d + r14d]
    lea esi, [r13d - 14]
    mov ecx, 19
    cmp dword [rbx + FD_STYLE], ST_TITLE
    jne .fill
    sub esi, 5
    mov ecx, 26
.fill:
    mov r8d, C_SELECTION
    call fill_rect
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
