; Pieces the screens are built from: names and dates, wrapped text, text
; fields, buttons and chips. The menus are in menu.asm.

section .rodata
text s_backlog,         "Backlog"
text s_todo,            "Todo"
text s_in_progress,     "In Progress"
text s_done,            "Done"
text s_canceled,        "Canceled"
text s_no_priority,     "No priority"
text s_urgent,          "Urgent"
text s_high,            "High"
text s_medium,          "Medium"
text s_low,             "Low"
text s_unknown_user,    "Unknown"
text s_no_assignee,     "No assignee"
text s_no_project,      "No project"
text s_general,         "#general"
text s_just_now,        "just now"
text s_m_ago,           "m ago"
text s_h_ago,           "h ago"
months:                 db "JanFebMarAprMayJunJulAugSepOctNovDec"

align 8
%macro NAME 1
    dq %1
    dd %1_len, 0
%endmacro
status_names:   NAME s_backlog
                NAME s_todo
                NAME s_in_progress
                NAME s_done
                NAME s_canceled
priority_names: NAME s_no_priority
                NAME s_urgent
                NAME s_high
                NAME s_medium
                NAME s_low

section .data
wrap_caret:     dd -1                   ; offset to draw the caret at in draw_wrapped, or -1
wrap_lh:        dd LINE_H               ; draw_wrapped's line height, for the next call only

section .text

; edi = status -> rsi = name, edx = length
status_name:
    shl edi, 4
    mov rsi, [status_names + rdi]
    mov edx, [status_names + rdi + 8]
    ret

; edi = priority -> rsi = name, edx = length
priority_name:
    shl edi, 4
    mov rsi, [priority_names + rdi]
    mov edx, [priority_names + rdi + 8]
    ret

; edi = user id -> rsi = their name, edx = length. Only members are known.
user_name:
    call find_member_row
    test rax, rax
    jz .unknown
    lea rsi, [rax + CM_NAME]
    movzx edx, byte [rax + CM_NAME_LEN]
    ret
.unknown:
    lea rsi, [s_unknown_user]
    mov edx, s_unknown_user_len
    ret

; rdi = cursor -> rdi advanced past the open conversation's name:
; "#general", another channel's or the member's
put_chat_name:
    mov esi, [chat_peer]
    test esi, esi
    js put_channel_name
    push rdi
    lea rsi, [s_general]
    mov edx, s_general_len
    mov edi, [chat_peer]
    test edi, edi
    jz .put
    call user_name
.put:
    pop rdi
    jmp put_mem

; rdi = cursor, rsi = view issue -> rdi advanced past "ENG-12"
put_issue_id:
    push rbx
    mov rbx, rsi
    push rdi
    call current_team_row
    pop rdi
    test rax, rax
    jz .number
    lea rsi, [rax + CO_KEY]
    movzx edx, byte [rax + CO_KEY_LEN]
    call put_mem
.number:
    mov byte [rdi], '-'
    inc rdi
    mov esi, [rbx + CI_NUMBER]
    test esi, esi
    jz .unsent
    call put_u32
    pop rbx
    ret
.unsent:
    mov byte [rdi], GLYPH_ELLIPSIS
    inc rdi
    pop rbx
    ret

; rdi = cursor, esi = unix seconds -> rdi advanced past "Nov 1", the local date
put_date:
    push rbx
    mov eax, esi
    add eax, [tz_offset]
    xor edx, edx
    mov ecx, 86400
    div ecx
    ; Days since 1970 to a civil date (Howard Hinnant's algorithm).
    add eax, 719468
    xor edx, edx
    mov ecx, 146097
    div ecx
    mov eax, edx                            ; day of the era
    mov ebx, eax
    xor edx, edx
    mov ecx, 1460
    div ecx
    mov r8d, ebx
    sub r8d, eax
    mov eax, ebx
    xor edx, edx
    mov ecx, 36524
    div ecx
    add r8d, eax
    mov eax, ebx
    xor edx, edx
    mov ecx, 146096
    div ecx
    sub r8d, eax
    mov eax, r8d
    xor edx, edx
    mov ecx, 365
    div ecx                                 ; year of the era
    mov r8d, eax
    imul r9d, r8d, 365
    shr eax, 2
    add r9d, eax
    mov eax, r8d
    xor edx, edx
    mov ecx, 100
    div ecx
    sub r9d, eax
    sub ebx, r9d                            ; day of the year, from March
    lea eax, [ebx * 4 + ebx + 2]
    xor edx, edx
    mov ecx, 153
    div ecx                                 ; month, from March
    mov r8d, eax
    imul eax, eax, 153
    add eax, 2
    xor edx, edx
    mov ecx, 5
    div ecx
    sub ebx, eax
    inc ebx                                 ; day of the month
    lea eax, [r8d + 2]                      ; month index from January
    cmp r8d, 10
    jb .month
    lea eax, [r8d - 10]
.month:
    lea eax, [eax * 2 + eax]
    lea rsi, [months + rax]
    mov edx, 3
    call put_mem
    mov byte [rdi], ' '
    inc rdi
    mov esi, ebx
    call put_u32
    pop rbx
    ret

; rdi = cursor, esi = unix seconds -> rdi advanced past "5m ago" or a date
put_ago:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    call unix_now
    mov rdi, rbx
    sub eax, r12d
    cmp eax, 60
    jl .now
    cmp eax, 3600
    jl .minutes
    cmp eax, 86400
    jl .hours
    mov esi, r12d
    call put_date
    jmp .done
.now:
    lea rsi, [s_just_now]
    mov edx, s_just_now_len
    call put_mem
    jmp .done
.minutes:
    xor edx, edx
    mov ecx, 60
    div ecx
    mov esi, eax
    call put_u32
    lea rsi, [s_m_ago]
    mov edx, s_m_ago_len
    call put_mem
    jmp .done
.hours:
    xor edx, edx
    mov ecx, 3600
    div ecx
    mov esi, eax
    call put_u32
    lea rsi, [s_h_ago]
    mov edx, s_h_ago_len
    call put_mem
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; edi = x, esi = baseline, rdx = text in scratch up to rcx, r8d = ink -> eax = end x
draw_scratch:
    lea rdx, [scratch]
    sub rcx, rdx
    jmp draw_text

; Where a line of wrapped text ends.
; rsi = text, edx = length, ecx = width, r8d = style
; -> eax = characters on the line, edx = characters it uses up (with the break)
wrap_line:
    push rbx
    push r12
    push r13
    push r14
    mov r12d, edx
    shl ecx, 2                              ; widths in quarter pixels, like adv4
    imul r13d, r8d, GLYPH_COUNT
    xor ebx, ebx                            ; width so far
    mov r14d, -1                            ; the last space
    xor r9d, r9d                            ; position
.char:
    cmp r9d, r12d
    jae .end
    movzx edi, byte [rsi + r9]
    cmp edi, 10
    je .newline
    cmp edi, ' '
    jne .measure
    mov r14d, r9d
.measure:
    call glyph_index
    add eax, r13d
    add ebx, [adv4 + rax * 4]
    cmp ebx, ecx
    jle .next
    test r9d, r9d
    jz .next                                ; at least one character per line
    test r14d, r14d
    jle .mid_word
    mov eax, r14d
    lea edx, [r14d + 1]
    jmp .done
.mid_word:
    mov eax, r9d
    mov edx, r9d
    jmp .done
.next:
    inc r9d
    jmp .char
.newline:
    mov eax, r9d
    lea edx, [r9d + 1]
    jmp .done
.end:
    mov eax, r12d
    mov edx, r12d
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Draws text wrapped to a width, wrap_lh apart, with the caret at wrap_caret
; unless that's -1, and wrap_sel_from to wrap_sel_to highlighted. Resets them all.
; rdi = text, esi = length, edx = x, ecx = top, r8d = width, r9d = ink
; -> eax = height used
draw_wrapped:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov r12d, esi
    mov [rsp], edx                          ; x
    mov r13d, ecx                           ; line top
    mov [rsp + 4], r8d                      ; width
    mov [rsp + 8], r9d                      ; ink
    xor ebp, ebp                            ; position
    xor r15d, r15d                          ; lines
.line:
    lea rsi, [rbx + rbp]
    mov edx, r12d
    sub edx, ebp
    mov ecx, [rsp + 4]
    mov r8d, [rsp + 8]
    shr r8d, 24
    call wrap_line
    mov r14d, eax                           ; characters shown
    mov [rsp + 12], edx                     ; characters used
    mov edi, [rsp]
    mov esi, r13d
    lea rdx, [rbx + rbp]
    mov ecx, ebp
    mov r8d, r14d
    mov r9d, [rsp + 8]
    shr r9d, 24
    call draw_line_selection
    mov edi, [rsp]
    mov esi, [wrap_lh]
    lea esi, [r13d + esi - 6]
    lea rdx, [rbx + rbp]
    mov ecx, r14d
    mov r8d, [rsp + 8]
    call draw_text
    mov eax, [wrap_caret]
    sub eax, ebp
    js .no_caret
    cmp eax, r14d
    ja .no_caret
    lea rdi, [rbx + rbp]
    mov esi, eax
    mov edx, [rsp + 8]
    shr edx, 24
    call text_width
    add eax, [rsp]
    mov edi, eax
    lea esi, [r13d + 2]
    mov edx, 1
    mov ecx, 16
    mov r8d, C_ACCENT_HI
    call fill_rect
    mov dword [wrap_caret], -1
.no_caret:
    inc r15d
    add r13d, [wrap_lh]
    add ebp, [rsp + 12]
    cmp ebp, r12d
    jb .line
    ; Text ending in a newline has an empty last line, which the caret can be on.
    test r12d, r12d
    jz .done
    cmp byte [rbx + r12 - 1], 10
    jne .done
    cmp dword [wrap_caret], -1
    je .empty_line
    mov edi, [rsp]
    lea esi, [r13d + 2]
    mov edx, 1
    mov ecx, 16
    mov r8d, C_ACCENT_HI
    call fill_rect
.empty_line:
    inc r15d
.done:
    mov dword [wrap_caret], -1
    mov dword [wrap_sel_from], -1
    mov dword [wrap_sel_to], -1
    mov eax, r15d
    imul eax, [wrap_lh]
    mov dword [wrap_lh], LINE_H
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = field -> eax = 1 if it has keyboard focus
field_focused:
    xor eax, eax
    cmp edi, [focus]
    jne .done
    cmp byte [keyboard_focus], 0
    setne al
.done:
    ret

; Keeps the cursor visible inside a single-line field, showing as much text as fits.
; rdi = field, rsi = the text as shown, edx = width available
fit_field_scroll:
    push rbx
    push rbp
    push r12
    mov rbx, rdi
    mov rbp, rsi
    mov r12d, edx
    mov eax, [rbx + FD_CURSOR]
    cmp eax, [rbx + FD_SCROLL]
    jae .right_edge
    mov [rbx + FD_SCROLL], eax
.right_edge:
    mov eax, [rbx + FD_SCROLL]
    lea rdi, [rbp + rax]
    mov esi, [rbx + FD_CURSOR]
    sub esi, eax
    mov edx, [rbx + FD_STYLE]
    call text_width
    cmp eax, r12d
    jle .fill_left
    inc dword [rbx + FD_SCROLL]
    jmp .right_edge
.fill_left:
    ; After deleting, pull earlier text back in if it fits.
    mov eax, [rbx + FD_SCROLL]
    test eax, eax
    jz .done
    dec eax
    push rax
    lea rdi, [rbp + rax]
    mov esi, [rbx + FD_LEN]
    sub esi, eax
    mov edx, [rbx + FD_STYLE]
    call text_width
    pop rcx
    cmp eax, r12d
    jg .done
    mov [rbx + FD_SCROLL], ecx
    jmp .fill_left
.done:
    pop r12
    pop rbp
    pop rbx
    ret

; A single-line field's text, placeholder and caret. The caller draws the box.
; edi = field, esi = x, edx = baseline, ecx = width
draw_field:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov [rsp], edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    call save_clip
    mov [rsp + 8], rax
    mov edi, [rsp]
    call field_focused
    mov ebp, eax
    mov edi, [rsp]
    call field_addr
    mov rbx, rax
    mov [rbx + FD_X], r12d
    mov [rbx + FD_W], r14d
    lea edi, [r12d - 1]
    lea esi, [r13d - 30]
    lea edx, [r12d + r14d + 1]
    lea ecx, [r13d + 12]
    call clip_to

    ; What gets drawn: the text, or a '*' for each character of a password.
    mov r15, [rbx + FD_BUF]
    test dword [rbx + FD_FLAGS], FF_MASKED
    jz .shown
    lea rdi, [mask_buf]
    mov al, '*'
    mov ecx, [rbx + FD_LEN]
    rep stosb
    lea r15, [mask_buf]
.shown:
    mov eax, [rbx + FD_STYLE]
    shl eax, 24
    mov [rsp + 16], eax                     ; ink style bits
    cmp dword [rbx + FD_LEN], 0
    jne .text
    mov edi, r12d
    mov esi, r13d
    mov rdx, [rbx + FD_HINT]
    mov ecx, [rbx + FD_HINT_LEN]
    mov r8d, [rsp + 16]
    or r8d, C_FAINT
    call draw_text
    jmp .caret
.text:
    mov rdi, rbx
    mov rsi, r15
    lea edx, [r14d - 4]
    call fit_field_scroll
    test ebp, ebp
    jz .unselected
    mov rdi, rbx
    mov rsi, r15
    mov edx, r12d
    mov ecx, r13d
    call draw_field_selection
.unselected:
    mov eax, [rbx + FD_SCROLL]
    mov edi, r12d
    mov esi, r13d
    lea rdx, [r15 + rax]
    mov ecx, [rbx + FD_LEN]
    sub ecx, eax
    mov r8d, [rsp + 16]
    or r8d, C_TEXT
    call draw_text
.caret:
    test ebp, ebp
    jz .done
    mov eax, [rbx + FD_SCROLL]
    lea rdi, [r15 + rax]
    mov esi, [rbx + FD_CURSOR]
    sub esi, eax
    mov edx, [rbx + FD_STYLE]
    call text_width
    lea edi, [r12d + eax]
    mov esi, r13d
    sub esi, 13
    mov ecx, 17
    cmp dword [rbx + FD_STYLE], ST_TITLE
    jne .caret_size
    sub esi, 5
    mov ecx, 24
.caret_size:
    mov edx, 1
    mov r8d, C_ACCENT_HI
    call fill_rect
.done:
    mov rdi, [rsp + 8]
    call restore_clip
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Which character x falls before on one line of text.
; rdi = text, esi = length, edx = style, ecx = x from the line's start -> eax
line_index_at:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    imul r13d, edx, GLYPH_COUNT
    lea r8d, [ecx * 4]                      ; quarter pixels, like adv4
    xor ecx, ecx                            ; width so far
    xor r9d, r9d
.char:
    cmp r9d, r12d
    jae .done
    movzx edi, byte [rbx + r9]
    call glyph_index
    add eax, r13d
    mov eax, [adv4 + rax * 4]
    mov edx, eax
    shr edx, 1
    add edx, ecx
    cmp r8d, edx
    jl .done                                ; left of this character's middle
    add ecx, eax
    inc r9d
    jmp .char
.done:
    mov eax, r9d
    pop r13
    pop r12
    pop rbx
    ret

; Which character the pointer is at in a field's text, wrapped the way
; draw_wrapped laid it out at FD_X, FD_Y, wrap_lh apart. Resets wrap_lh.
; rdi = field struct -> eax = the offset
wrapped_caret_at:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, [rbx + FD_BUF]
    mov r13d, [rbx + FD_LEN]
    mov r14d, [pointer_y]
    sub r14d, [rbx + FD_Y]
    mov eax, r13d                           ; never drawn: the end
    cmp dword [rbx + FD_W], 0
    je .done
    xor ebp, ebp                            ; where the line starts
.line:
    lea rsi, [r12 + rbp]
    mov edx, r13d
    sub edx, ebp
    mov ecx, [rbx + FD_W]
    mov r8d, [rbx + FD_STYLE]
    call wrap_line
    mov r15d, eax
    sub r14d, [wrap_lh]
    js .found
    lea ecx, [ebp + edx]
    cmp ecx, r13d
    jae .last
    mov ebp, ecx
    jmp .line
.last:
    ; Under the text. After a final newline that's the empty line there.
    test r13d, r13d
    jz .found
    mov eax, r13d
    cmp byte [r12 + r13 - 1], 10
    je .done
.found:
    lea rdi, [r12 + rbp]
    mov esi, r15d
    mov edx, [rbx + FD_STYLE]
    mov ecx, [pointer_x]
    sub ecx, [rbx + FD_X]
    call line_index_at
    add eax, ebp
.done:
    mov dword [wrap_lh], LINE_H
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Moves a field's caret to where the pointer is. edi = field
place_caret:
    push rbx
    call field_addr
    mov rbx, rax
    mov rdi, rax
    test dword [rbx + FD_FLAGS], FF_MULTILINE
    jnz .wrapped
    mov eax, [rbx + FD_LEN]
    cmp dword [rbx + FD_W], 0
    je .done
    mov rdi, [rbx + FD_BUF]
    test dword [rbx + FD_FLAGS], FF_MASKED
    jz .shown
    lea rdi, [mask_buf]
.shown:
    mov eax, [rbx + FD_SCROLL]
    add rdi, rax
    mov esi, [rbx + FD_LEN]
    sub esi, eax
    mov edx, [rbx + FD_STYLE]
    mov ecx, [pointer_x]
    sub ecx, [rbx + FD_X]
    call line_index_at
    add eax, [rbx + FD_SCROLL]
    jmp .done
.wrapped:
    call wrapped_caret_at
.done:
    mov [rbx + FD_CURSOR], eax
    pop rbx
    ret

; A multi-line field: wrapped text, or its placeholder, and the caret.
; edi = field, esi = x, edx = top, ecx = width -> eax = height used
draw_area:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15d, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    call field_addr
    mov rbx, rax
    mov [rbx + FD_X], r12d
    mov [rbx + FD_Y], r13d
    mov [rbx + FD_W], r14d
    mov edi, r15d
    call field_focused
    test eax, eax
    jz .text
    mov eax, [rbx + FD_CURSOR]
    mov [wrap_caret], eax
    mov rdi, rbx
    call sel_range
    mov [wrap_sel_from], eax
    mov [wrap_sel_to], edx
.text:
    cmp dword [rbx + FD_LEN], 0
    jne .wrapped
    cmp dword [wrap_caret], -1
    je .hint
    mov edi, r12d                           ; empty and focused: a caret before the hint
    lea esi, [r13d + 2]
    mov edx, 1
    mov ecx, 16
    mov r8d, C_ACCENT_HI
    call fill_rect
    mov dword [wrap_caret], -1
.hint:
    lea edi, [r12d + 2]
    lea esi, [r13d + 14]
    mov rdx, [rbx + FD_HINT]
    mov ecx, [rbx + FD_HINT_LEN]
    mov r8d, INK(C_FAINT, ST_BODY)
    call draw_text
    mov eax, LINE_H
    jmp .done
.wrapped:
    mov rdi, [rbx + FD_BUF]
    mov esi, [rbx + FD_LEN]
    mov edx, r12d
    mov ecx, r13d
    mov r8d, r14d
    mov r9d, INK(C_TEXT, ST_BODY)
    call draw_wrapped
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; A button. edi = x, esi = y, rdx = text, ecx = length, r8d = action,
; r9d = 0 outlined, BTN_PRIMARY or BTN_DANGER -> eax = its width
draw_button:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov rbx, rdx
    mov ebp, ecx
    mov r14d, r8d
    mov r15d, r9d
    mov rdi, rbx
    mov esi, ebp
    mov edx, ST_MEDIUM
    call text_width
    add eax, 24
    mov [rsp], eax
    mov edi, r14d
    xor esi, esi
    call hovering
    mov ecx, eax
    test r15d, r15d
    jz .secondary
    mov r8d, C_ACCENT
    mov eax, C_ACCENT_HI
    cmp r15d, BTN_DANGER
    jne .fill
    mov r8d, C_DANGER
    mov eax, C_DANGER_HI
.fill:
    test ecx, ecx
    cmovnz r8d, eax
    mov edi, r12d
    mov esi, r13d
    mov edx, [rsp]
    mov ecx, 30
    mov r9d, 6
    call fill_rrect
    jmp .label
.secondary:
    mov r9d, C_RAISED
    mov eax, C_SELECT
    test ecx, ecx
    cmovnz r9d, eax
    mov edi, r12d
    mov esi, r13d
    mov edx, [rsp]
    mov ecx, 30
    mov r8d, C_LINE
    mov r10d, 6
    call outline_rrect
.label:
    lea edi, [r12d + 12]
    lea esi, [r13d + 20]
    mov rdx, rbx
    mov ecx, ebp
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    mov edi, r12d
    mov esi, r13d
    mov edx, [rsp]
    mov ecx, 30
    mov r8d, r14d
    xor r9d, r9d
    call add_hit
    mov eax, [rsp]
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; A filter chip that ends in an X to remove it. Takes what draw_chip does.
draw_removable_chip:
    mov r9d, 1
    jmp chip
; A small rounded chip: an optional colored dot and some text, 24px tall.
; edi = x, esi = y, rdx = text, ecx = length, r8d = dot color, or -1 for none
; -> eax = its width
draw_chip:
    xor r9d, r9d
; The same, r9d = 1 to end in an X
chip:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 16
    mov r12d, edi
    mov r13d, esi
    mov rbx, rdx
    mov ebp, ecx
    mov r14d, r8d
    mov [rsp + 8], r9d
    mov rdi, rbx
    mov esi, ebp
    mov edx, ST_SMALL
    call text_width
    lea eax, [eax + 18]
    imul ecx, [rsp + 8], 14                 ; room for the X
    add eax, ecx
    xor ecx, ecx
    test r14d, r14d
    js .no_dot
    mov ecx, 14
.no_dot:
    add eax, ecx
    mov [rsp], eax
    mov [rsp + 4], ecx
    mov edi, r12d
    mov esi, r13d
    mov edx, eax
    mov ecx, 24
    mov r8d, C_LINE
    mov r9d, C_PANEL
    mov r10d, 12
    call outline_rrect
    test r14d, r14d
    js .text
    lea edi, [r12d * 4 + 44]                ; a 4px dot, 11px in
    lea esi, [r13d * 4 + 48]
    mov edx, 13
    mov ecx, r14d
    call aa_disc
.text:
    lea edi, [r12d + 9]
    add edi, [rsp + 4]
    lea esi, [r13d + 16]
    mov rdx, rbx
    mov ecx, ebp
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    cmp dword [rsp + 8], 0
    je .done
    mov edi, r12d
    add edi, [rsp]
    sub edi, 14
    lea esi, [r13d + 12]
    mov edx, 12
    mov ecx, C_DIM
    call draw_cross
.done:
    mov eax, [rsp]
    add rsp, 16
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; A shortcut key, drawn as a small key cap. edi = x, esi = y, edx = character
draw_keycap:
    push rbx
    push r12
    push r13
    sub rsp, 16
    mov r12d, edi
    mov r13d, esi
    mov [rsp], dl
    mov edx, 18
    mov ecx, 18
    mov r8d, C_LINE
    mov r9d, C_RAISED
    mov r10d, 4
    call outline_rrect
    mov rdi, rsp
    mov esi, 1
    mov edx, ST_SMALL
    call text_width
    mov edi, 18
    sub edi, eax
    sar edi, 1
    add edi, r12d
    lea esi, [r13d + 13]
    mov rdx, rsp
    mov ecx, 1
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret

; Darkens the whole window, behind a modal or menu.
shade_screen:
    mov rdi, [fb]
    mov ecx, [fb_w]
    imul ecx, [fb_h]
.pixel:
    test ecx, ecx
    jz .done
    mov eax, [rdi]
    shr eax, 1
    and eax, 0x7f7f7f
    mov [rdi], eax
    add rdi, 4
    dec ecx
    jmp .pixel
.done:
    ret

; An item's icon. rdi = item, esi = x, edx = y (icon box top)
draw_item_icon:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov eax, [rbx + MI_ICON]
    cmp eax, IC_STATUS
    je .status
    cmp eax, IC_ISSUE
    je .status
    cmp eax, IC_PRIORITY
    je .priority
    cmp eax, IC_AVATAR
    je .avatar
    cmp eax, IC_DOT
    je .dot
    cmp eax, IC_PLUS
    jne .done
    lea edi, [r12d + 6]
    lea esi, [r13d + 1]
    mov edx, 2
    mov ecx, 12
    mov r8d, C_DIM
    call fill_rect
    lea edi, [r12d + 1]
    lea esi, [r13d + 6]
    mov edx, 12
    mov ecx, 2
    mov r8d, C_DIM
    call fill_rect
    jmp .done
.status:
    mov edi, r12d
    mov esi, r13d
    mov edx, [rbx + MI_ICON_ARG]
    mov ecx, C_RAISED
    call draw_status_icon
    jmp .done
.priority:
    mov edi, r12d
    mov esi, r13d
    mov edx, [rbx + MI_ICON_ARG]
    mov ecx, C_DIM
    mov r8d, C_LINE
    mov r9d, C_RAISED
    call draw_priority_icon
    jmp .done
.avatar:
    mov ecx, [rbx + MI_ICON_ARG]
    test ecx, ecx
    jz .nobody
    lea edi, [r12d - 2]
    lea esi, [r13d - 2]
    mov edx, 18
    mov r8, [rbx + MI_TEXT]
    call draw_avatar
    jmp .done
.nobody:
    lea edi, [r12d * 4 + 28]
    lea esi, [r13d * 4 + 28]
    mov edx, 30
    mov ecx, C_FAINT
    mov r8d, 5
    call aa_dashed_ring
    jmp .done
.dot:
    lea edi, [r12d * 4 + 28]
    lea esi, [r13d * 4 + 28]
    mov edx, 18
    mov ecx, [rbx + MI_ICON_ARG]
    call aa_disc
.done:
    pop r13
    pop r12
    pop rbx
    ret
