; Pieces the screens are built from: names and dates, wrapped text, text
; fields, buttons, chips and the menu.

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
text s_create_label,    "Create label: "
text s_create_project,  "Create project: "
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

text c_new_issue,       "Create new issue"
text c_board,           "Switch to board view"
text c_list,            "Switch to list view"
text c_status,          "Change status"
text c_priority,        "Change priority"
text c_assign,          "Assign to"
text c_project,         "Move to project"
text c_labels,          "Change labels"
text c_delete,          "Delete issue"
text c_all,             "Go to all issues"
text c_active,          "Go to active issues"
text c_backlog,         "Go to backlog"
text c_mine,            "Go to my issues"
text c_filter,          "Filter by label or project"
text c_clear,           "Clear filters"
text c_new_team,        "Create new team"
text c_log_out,         "Log out"

text h_status,          "Change status..."
text h_priority,        "Set priority..."
text h_assignee,        "Assign to..."
text h_project,         "Move to project..."
text h_labels,          "Add or remove labels..."
text h_filter,          "Filter by..."
text h_command,         "Type a command or search..."
menu_hints:     NAME h_status
                NAME h_priority
                NAME h_assignee
                NAME h_project
                NAME h_labels
                NAME h_filter
                NAME h_command

; The command menu, top to bottom: text, value, hint key, and when it shows.
%define WHEN_ALWAYS     0
%define WHEN_ISSUE      1               ; there's an issue to act on
%define WHEN_LIST       2               ; in the list layout
%define WHEN_BOARD      3
%define WHEN_FILTERED   4
%macro COMMAND 4
    dq %1
    dd %1_len, %2
    db %3, %4, 0, 0, 0, 0, 0, 0
%endmacro
commands:
    COMMAND c_new_issue, CMD_NEW_ISSUE, 'C', WHEN_ALWAYS
    COMMAND c_status, CMD_PICK + MK_STATUS, 'S', WHEN_ISSUE
    COMMAND c_priority, CMD_PICK + MK_PRIORITY, 'P', WHEN_ISSUE
    COMMAND c_assign, CMD_PICK + MK_ASSIGNEE, 'A', WHEN_ISSUE
    COMMAND c_labels, CMD_PICK + MK_LABELS, 'L', WHEN_ISSUE
    COMMAND c_project, CMD_PICK + MK_PROJECT, 'M', WHEN_ISSUE
    COMMAND c_delete, CMD_DELETE, 0, WHEN_ISSUE
    COMMAND c_board, CMD_LAYOUT, 0, WHEN_LIST
    COMMAND c_list, CMD_LAYOUT, 0, WHEN_BOARD
    COMMAND c_all, CMD_VIEW + V_ALL, 0, WHEN_ALWAYS
    COMMAND c_active, CMD_VIEW + V_ACTIVE, 0, WHEN_ALWAYS
    COMMAND c_backlog, CMD_VIEW + V_BACKLOG, 0, WHEN_ALWAYS
    COMMAND c_mine, CMD_VIEW + V_MINE, 0, WHEN_ALWAYS
    COMMAND c_filter, CMD_FILTER, 0, WHEN_ALWAYS
    COMMAND c_clear, CMD_CLEAR, 0, WHEN_FILTERED
    COMMAND c_new_team, CMD_NEW_TEAM, 0, WHEN_ALWAYS
    COMMAND c_log_out, CMD_LOGOUT, 0, WHEN_ALWAYS
    dq 0
%define COMMAND_SIZE 24

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

; rdi = cursor, esi = unix seconds -> rdi advanced past "Nov 1"
put_date:
    push rbx
    mov eax, esi
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
; unless that's -1. Resets both.
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
    mov edi, r15d
    call field_focused
    test eax, eax
    jz .text
    mov eax, [rbx + FD_CURSOR]
    mov [wrap_caret], eax
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
; r9d = 1 for the accent-filled primary kind -> eax = its width
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

; A small rounded chip: an optional colored dot and some text, 24px tall.
; edi = x, esi = y, rdx = text, ecx = length, r8d = dot color, or -1 for none
; -> eax = its width
draw_chip:
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
    mov rdi, rbx
    mov esi, ebp
    mov edx, ST_SMALL
    call text_width
    lea eax, [eax + 18]
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

; --- the menu ---

; -> the menu's current value for the issue or draft it changes: eax for
; single choices, the label bitmask for labels
menu_current:
    mov edi, [menu_issue]
    test edi, edi
    jz .draft
    call find_view_issue
    test rax, rax
    jz .none
    mov ecx, [menu_kind]
    movzx edx, byte [rax + CI_STATUS]
    cmp ecx, MK_STATUS
    je .edx
    movzx edx, byte [rax + CI_PRIORITY]
    cmp ecx, MK_PRIORITY
    je .edx
    mov edx, [rax + CI_ASSIGNEE]
    cmp ecx, MK_ASSIGNEE
    je .edx
    movzx edx, byte [rax + CI_PROJECT]
    cmp ecx, MK_PROJECT
    je .edx
    movzx edx, word [rax + CI_LABELS]
.edx:
    mov eax, edx
    ret
.draft:
    mov ecx, [menu_kind]
    cmp ecx, MK_LABELS
    ja .none
    mov eax, [new_status + rcx * 4]
    ret
.none:
    mov eax, -1
    ret

; Adds an item if it matches the filter text.
; rdi = text, esi = length, edx = value, ecx = icon, r8d = icon arg,
; r9d = checked | hint << 8
push_item:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    push r9
    push r9
    cmp dword [menu_count], MENU_MAX
    jae .skip
    cmp r14d, IC_PLUS
    je .add                                 ; "create" items carry the filter text itself
    mov rdi, rbx
    mov esi, r12d
    call matches_filter
    test eax, eax
    jz .skip
.add:
    mov eax, [menu_count]
    inc dword [menu_count]
    imul eax, eax, MI_SIZE
    lea rax, [menu_items + rax]
    mov [rax + MI_TEXT], rbx
    mov [rax + MI_LEN], r12d
    mov [rax + MI_ICON], r14d
    mov [rax + MI_ICON_ARG], r15d
    mov [rax + MI_VALUE], r13d
    mov rcx, [rsp]
    mov [rax + MI_CHECK], cl
    mov [rax + MI_HINT], ch
.skip:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi = text, esi = length -> eax = 1 if the menu's filter text is in it, any case
matches_filter:
    mov rdx, [fields + F_MENU * FD_SIZE + FD_BUF]
    mov ecx, [fields + F_MENU * FD_SIZE + FD_LEN]
    mov eax, 1
    test ecx, ecx
    jz .done
    xor r8d, r8d                            ; start in the text
.start:
    mov eax, esi
    sub eax, r8d
    cmp eax, ecx
    jl .no
    xor r9d, r9d
.char:
    cmp r9d, ecx
    jae .yes
    lea eax, [r8d + r9d]
    movzx eax, byte [rdi + rax]
    movzx r10d, byte [rdx + r9]
    or eax, 0x20
    or r10d, 0x20
    cmp eax, r10d
    jne .next_start
    inc r9d
    jmp .char
.next_start:
    inc r8d
    jmp .start
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
.done:
    ret

; rdi = names (labels or projects), esi = slot size, edx = slot count
; -> eax = 1 if one is named exactly the filter text, any case
filter_names_exist:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
.slot:
    test r13d, r13d
    jz .no
    movzx esi, byte [rbx + LB_NAME_LEN]
    cmp esi, [fields + F_MENU * FD_SIZE + FD_LEN]
    jne .next
    lea rdi, [rbx + LB_NAME]
    call matches_filter
    test eax, eax
    jnz .done
.next:
    add rbx, r12
    dec r13d
    jmp .slot
.no:
    xor eax, eax
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Fills menu_items for the open menu and its filter text.
build_menu:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov dword [menu_count], 0
    call menu_current
    mov r15d, eax
    mov eax, [menu_kind]
    cmp eax, MK_STATUS
    je .status
    cmp eax, MK_PRIORITY
    je .priority
    cmp eax, MK_ASSIGNEE
    je .assignee
    cmp eax, MK_PROJECT
    je .project
    cmp eax, MK_LABELS
    je .labels
    cmp eax, MK_FILTER
    je .filter
    jmp .commands

.status:
    xor ebx, ebx
.status_item:
    movzx r12d, byte [board_order + rbx]
    mov edi, r12d
    call status_name
    mov rdi, rsi
    mov esi, edx
    mov edx, r12d
    mov ecx, IC_STATUS
    mov r8d, r12d
    xor r9d, r9d
    cmp r12d, r15d
    sete r9b
    call push_item
    inc ebx
    cmp ebx, STATUS_COUNT
    jb .status_item
    jmp .done

.priority:
    xor ebx, ebx
.priority_item:
    mov edi, ebx
    call priority_name
    mov rdi, rsi
    mov esi, edx
    mov edx, ebx
    mov ecx, IC_PRIORITY
    mov r8d, ebx
    xor r9d, r9d
    cmp ebx, r15d
    sete r9b
    call push_item
    inc ebx
    cmp ebx, PRIO_COUNT
    jb .priority_item
    jmp .done

.assignee:
    lea rdi, [s_no_assignee]
    mov esi, s_no_assignee_len
    xor edx, edx
    mov ecx, IC_AVATAR
    xor r8d, r8d
    xor r9d, r9d
    test r15d, r15d
    sete r9b
    call push_item
    lea rbx, [members]
    mov ebp, [member_count]
.member:
    test ebp, ebp
    jz .done
    lea rdi, [rbx + CM_NAME]
    movzx esi, byte [rbx + CM_NAME_LEN]
    mov edx, [rbx + CM_ID]
    mov ecx, IC_AVATAR
    mov r8d, edx
    xor r9d, r9d
    cmp edx, r15d
    sete r9b
    call push_item
    add rbx, CM_SIZE
    dec ebp
    jmp .member

.project:
    lea rdi, [s_no_project]
    mov esi, s_no_project_len
    xor edx, edx
    mov ecx, IC_DOT
    mov r8d, C_FAINT
    xor r9d, r9d
    test r15d, r15d
    sete r9b
    call push_item
    lea rbx, [view_projects]
    mov ebp, 1
.project_item:
    movzx esi, byte [rbx + LB_NAME_LEN]
    test esi, esi
    jz .next_project
    lea rdi, [rbx + LB_NAME]
    mov edx, ebp
    mov ecx, IC_DOT
    mov r8d, [rbx + LB_COLOR]
    xor r9d, r9d
    cmp ebp, r15d
    sete r9b
    call push_item
.next_project:
    add rbx, PJ_SIZE
    inc ebp
    cmp ebp, PROJECT_SLOTS
    jbe .project_item
    lea rdi, [view_projects]
    mov esi, PJ_SIZE
    mov edx, PROJECT_SLOTS
    lea r12, [s_create_project]
    mov r13d, s_create_project_len
    jmp .create

.labels:
    lea rbx, [view_labels]
    xor ebp, ebp
.label_item:
    movzx esi, byte [rbx + LB_NAME_LEN]
    test esi, esi
    jz .next_label
    lea rdi, [rbx + LB_NAME]
    mov edx, ebp
    mov ecx, IC_DOT
    mov r8d, [rbx + LB_COLOR]
    xor r9d, r9d
    bt r15d, ebp
    setc r9b
    call push_item
.next_label:
    add rbx, LB_SIZE
    inc ebp
    cmp ebp, LABEL_SLOTS
    jb .label_item
    lea rdi, [view_labels]
    mov esi, LB_SIZE
    mov edx, LABEL_SLOTS
    lea r12, [s_create_label]
    mov r13d, s_create_label_len
.create:
    ; Typed a name nothing has: offer to create it.
    cmp dword [fields + F_MENU * FD_SIZE + FD_LEN], 0
    je .done
    call filter_names_exist
    test eax, eax
    jnz .done
    mov rdi, r12
    mov esi, r13d
    xor edx, edx
    mov ecx, IC_PLUS
    xor r8d, r8d
    xor r9d, r9d
    call push_item
    jmp .done

.filter:
    lea rbx, [view_labels]
    xor ebp, ebp
.filter_label:
    movzx esi, byte [rbx + LB_NAME_LEN]
    test esi, esi
    jz .next_filter_label
    lea rdi, [rbx + LB_NAME]
    mov edx, ebp
    not edx                                 ; labels are negative, projects positive
    mov ecx, IC_DOT
    mov r8d, [rbx + LB_COLOR]
    xor r9d, r9d
    cmp ebp, [filter_label]
    sete r9b
    call push_item
.next_filter_label:
    add rbx, LB_SIZE
    inc ebp
    cmp ebp, LABEL_SLOTS
    jb .filter_label
    lea rbx, [view_projects]
    mov ebp, 1
.filter_project:
    movzx esi, byte [rbx + LB_NAME_LEN]
    test esi, esi
    jz .next_filter_project
    lea rdi, [rbx + LB_NAME]
    mov edx, ebp
    mov ecx, IC_DOT
    mov r8d, [rbx + LB_COLOR]
    xor r9d, r9d
    cmp ebp, [filter_project]
    sete r9b
    call push_item
.next_filter_project:
    add rbx, PJ_SIZE
    inc ebp
    cmp ebp, PROJECT_SLOTS
    jbe .filter_project
    jmp .done

.commands:
    call target_issue
    mov r12d, eax
    lea rbx, [commands]
.command:
    cmp qword [rbx], 0
    je .teams
    movzx eax, byte [rbx + 17]
    cmp eax, WHEN_ISSUE
    jne .when_list
    test r12d, r12d
    jz .next_command
.when_list:
    cmp eax, WHEN_LIST
    jne .when_board
    cmp byte [board], 0
    jne .next_command
.when_board:
    cmp eax, WHEN_BOARD
    jne .when_filtered
    cmp byte [board], 0
    je .next_command
.when_filtered:
    cmp eax, WHEN_FILTERED
    jne .add_command
    cmp dword [filter_project], 0
    jne .add_command
    cmp dword [filter_label], -1
    je .next_command
.add_command:
    mov rdi, [rbx]
    mov esi, [rbx + 8]
    mov edx, [rbx + 12]
    xor ecx, ecx
    xor r8d, r8d
    movzx r9d, byte [rbx + 16]
    shl r9d, 8
    call push_item
.next_command:
    add rbx, COMMAND_SIZE
    jmp .command
.teams:
    lea rbx, [teams]
    xor ebp, ebp
.team:
    cmp ebp, [team_count]
    jae .done
    lea rdi, [rbx + CO_NAME]
    movzx esi, byte [rbx + CO_NAME_LEN]
    lea edx, [ebp + CMD_TEAM]
    mov ecx, IC_DOT
    mov r8d, C_ACCENT
    xor r9d, r9d
    mov eax, [rbx + CO_ID]
    cmp eax, [current_team]
    sete r9b
    call push_item
    add rbx, CO_SIZE
    inc ebp
    jmp .team

.done:
    mov eax, [menu_count]
    dec eax
    mov ecx, [menu_sel]
    cmp ecx, eax
    cmovg ecx, eax
    xor eax, eax
    cmp ecx, eax
    cmovl ecx, eax
    mov [menu_sel], ecx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
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

section .rodata
menu_check:     dd 0, 16, 10, 24, 26, 6
section .text

; The open menu, over a darkened window.
draw_menu:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    call build_menu
    call shade_screen
    xor edi, edi
    xor esi, esi
    mov edx, [win_w]
    mov ecx, [win_h]
    mov r8d, A_DISMISS
    xor r9d, r9d
    call add_hit

    ; The filter's placeholder says what the menu does.
    mov eax, [menu_kind]
    shl eax, 4
    mov rcx, [menu_hints + rax]
    mov [fields + F_MENU * FD_SIZE + FD_HINT], rcx
    mov ecx, [menu_hints + rax + 8]
    mov [fields + F_MENU * FD_SIZE + FD_HINT_LEN], ecx

    ; Keep the selection in the visible rows.
    mov eax, [menu_sel]
    cmp eax, [menu_scroll]
    jge .below
    mov [menu_scroll], eax
.below:
    sub eax, MENU_SHOWN - 1
    cmp eax, [menu_scroll]
    jle .scrolled
    mov [menu_scroll], eax
.scrolled:
    mov ebp, [menu_count]
    sub ebp, [menu_scroll]
    cmp ebp, MENU_SHOWN
    jle .rows_known
    mov ebp, MENU_SHOWN
.rows_known:
    mov r12d, [win_w]                       ; x
    sub r12d, MENU_W
    sar r12d, 1
    mov r13d, 90                            ; y
    xor r14d, r14d                          ; context line height
    cmp dword [menu_issue], 0
    je .box
    mov r14d, 30
.box:
    imul ecx, ebp, MENU_ROW_H
    lea ecx, [ecx + r14d + 66]
    mov [rsp], ecx                          ; menu height
    mov edi, r12d
    mov esi, r13d
    mov edx, MENU_W
    mov r8d, C_LINE
    mov r9d, C_RAISED
    mov r10d, 10
    call outline_rrect
    mov edi, r12d
    mov esi, r13d
    mov edx, MENU_W
    mov ecx, [rsp]
    mov r8d, A_BLOCK
    xor r9d, r9d
    call add_hit

    test r14d, r14d
    jz .input
    mov edi, [menu_issue]                   ; which issue this changes
    call find_view_issue
    test rax, rax
    jz .input
    mov rbx, rax
    lea rdi, [scratch]
    mov rsi, rbx
    call put_issue_id
    mov byte [rdi], ' '
    inc rdi
    lea rsi, [rbx + CI_TITLE]
    movzx edx, byte [rbx + CI_TITLE_LEN]
    call put_mem
    lea rdx, [scratch]
    mov rcx, rdi
    sub rcx, rdx
    lea edi, [r12d + 16]
    lea esi, [r13d + 24]
    mov r8d, INK(C_DIM, ST_SMALL)
    mov r9d, MENU_W - 32
    call draw_text_fit
.input:
    mov edi, F_MENU
    lea esi, [r12d + 18]
    lea edx, [r13d + r14d + 30]
    mov ecx, MENU_W - 36
    call draw_field
    lea edi, [r12d + 1]
    lea esi, [r13d + r14d + 50]
    mov edx, MENU_W - 2
    mov ecx, 1
    mov r8d, C_LINE
    call fill_rect

    lea r15d, [r13d + r14d + 58]            ; first row
    mov ebx, [menu_scroll]
    mov [rsp + 4], ebp
.row:
    cmp dword [rsp + 4], 0
    je .done
    mov edi, A_MENU_ITEM
    mov esi, ebx
    call hovering
    test eax, eax
    jz .highlight
    mov [menu_sel], ebx                     ; the pointer moves the selection
.highlight:
    cmp ebx, [menu_sel]
    jne .item
    lea edi, [r12d + 6]
    mov esi, r15d
    mov edx, MENU_W - 12
    mov ecx, MENU_ROW_H
    mov r8d, C_SELECT
    mov r9d, 6
    call fill_rrect
.item:
    lea edi, [r12d + 6]
    mov esi, r15d
    mov edx, MENU_W - 12
    mov ecx, MENU_ROW_H
    mov r8d, A_MENU_ITEM
    mov r9d, ebx
    call add_hit
    imul eax, ebx, MI_SIZE
    lea rbp, [menu_items + rax]
    mov rdi, rbp
    lea esi, [r12d + 20]
    lea edx, [r15d + 11]
    call draw_item_icon
    mov rdx, [rbp + MI_TEXT]
    mov ecx, [rbp + MI_LEN]
    lea edi, [r12d + 46]
    lea esi, [r15d + 23]
    mov r8d, INK(C_TEXT, ST_BODY)
    call draw_text
    cmp dword [rbp + MI_ICON], IC_PLUS
    jne .check
    mov edi, eax                            ; the name being created, quoted
    lea esi, [r15d + 23]
    mov rdx, [fields + F_MENU * FD_SIZE + FD_BUF]
    mov ecx, [fields + F_MENU * FD_SIZE + FD_LEN]
    mov r8d, INK(C_DIM, ST_BODY)
    call draw_text
.check:
    cmp byte [rbp + MI_CHECK], 0
    je .hint
    mov edx, r12d
    add edx, MENU_W - 40
    lea ecx, [r15d + 6]
    lea rdi, [menu_check]
    mov esi, 3
    mov r8d, C_TEXT
    mov r9d, 6
    call aa_polyline
.hint:
    movzx edx, byte [rbp + MI_HINT]
    test edx, edx
    jz .next
    mov edi, r12d
    add edi, MENU_W - 40
    lea esi, [r15d + 9]
    call draw_keycap
.next:
    add r15d, MENU_ROW_H
    inc ebx
    dec dword [rsp + 4]
    jmp .row
.done:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
