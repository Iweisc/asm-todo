; Mentions on the client: the "@" on channels where a message we haven't
; seen mentions us, mentions drawn in messages, comments and descriptions,
; and the list of members that comes up while one is typed. What counts as
; a mention is in common/mention.asm, shared with the server.

%define MENTION_SHOWN   6               ; members the list offers at once
%define MENTION_W       240
%define MENTION_ROW_H   32
%define C_MENTION       0x9ba3f2        ; a mention's text, the accent lightened

%if CHANNEL_SLOTS > 31
%error "mention_marks needs a bit for each channel"
%endif

section .rodata
text s_at,              "@"

section .data
mention_shut_field: dd F_NONE           ; the mention whose list Esc closed, until its "@" goes
mention_shut_at:    dd -1

section .bss
alignb 8
mention_rows:   resq MENTION_SHOWN      ; the member rows the list offers
mention_marks:  resd 1                  ; bit 0 #general, bit n channel slot n
mention_sel:    resd 1
mention_from:   resd 1                  ; where the "@" of the one being typed is

section .text

; edi = peer -> eax = its bit in mention_marks, 0 for a direct message.
; Clobbers only eax and ecx.
mention_bit:
    xor eax, eax
    test edi, edi
    jg .done
    mov ecx, edi
    and ecx, 31                             ; the slot, 0 for #general
    mov eax, 1
    shl eax, cl
.done:
    ret

; edi = peer. Clobbers only eax and ecx.
clear_mentioned:
    call mention_bit
    not eax
    and [mention_marks], eax
    ret

; edi = peer -> eax = 1 if a message there we haven't seen mentions us
is_mentioned:
    call mention_bit
    and eax, [mention_marks]
    setnz al
    movzx eax, al
    ret

; A message we haven't seen marks its channel if it mentions us.
; rdi = the message's row, esi = the peer it's in
note_mention:
    push rbx
    mov ebx, esi
    lea rax, [rdi + CH_TEXT]
    movzx esi, word [rdi + CH_LEN]
    mov rdi, rax
    lea rdx, [my_name]
    mov ecx, [my_name_len]
    call text_mentions
    test eax, eax
    jz .done
    mov edi, ebx
    call mention_bit
    or [mention_marks], eax
.done:
    pop rbx
    ret

; The end of MSG_UNREAD: the channels that mention us, replacing the old ones.
read_mentions:
    push rbx
    mov dword [mention_marks], 0
    call rd_u8
    mov ebx, eax
.peer:
    test ebx, ebx
    jz .done
    call rd_u32
    mov edi, eax
    call mention_bit
    or [mention_marks], eax
    dec ebx
    jmp .peer
.done:
    pop rbx
    ret

; The "@" a sidebar row shows instead of the unread dot. edi = the dot's x, esi = the row's y
draw_mention_badge:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    lea edi, [ebx - 9]
    lea esi, [r12d + 6]
    mov edx, 18
    mov ecx, 16
    mov r8d, C_ACCENT
    mov r9d, 8
    call fill_rrect
    lea rdi, [s_at]
    mov esi, s_at_len
    mov edx, ST_SMALL
    call text_width
    shr eax, 1
    mov edi, ebx
    sub edi, eax
    lea esi, [r12d + 18]
    lea rdx, [s_at]
    mov ecx, s_at_len
    mov r8d, INK(0xffffff, ST_SMALL)
    call draw_text
    add rsp, 8
    pop r12
    pop rbx
    ret

; rdi = text, esi = length, edx = position -> eax = the length of a member's
; "@name" there, or 0, and edx = 1 if it's us
member_mention_at:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13d, esi
    mov r14d, edx
    lea rbx, [members]
    imul eax, [member_count], CM_SIZE
    lea r15, [rbx + rax]
.member:
    cmp rbx, r15
    jae .none
    mov rdi, r12
    mov esi, r13d
    mov edx, r14d
    lea rcx, [rbx + CM_NAME]
    movzx r8d, byte [rbx + CM_NAME_LEN]
    call mention_at
    test eax, eax
    jnz .found
    add rbx, CM_SIZE
    jmp .member
.found:
    xor edx, edx
    mov ecx, [rbx + CM_ID]
    cmp ecx, [my_id]
    sete dl
    jmp .done
.none:
    xor eax, eax
    xor edx, edx
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Like draw_text, but members' mentions are in C_MENTION, and ours sit on a
; highlight too. edi = x, esi = baseline, rdx = text, ecx = length, r8d = ink
; -> eax = x after it
draw_mention_line:
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
    mov r14d, ecx
    mov r15d, r8d
    xor ebp, ebp                            ; position
    mov dword [rsp], 0                      ; where the plain text since the last mention starts
.scan:
    cmp ebp, r14d
    jae .rest
    cmp byte [rbx + rbp], '@'
    jne .next
    mov rdi, rbx
    mov esi, r14d
    mov edx, ebp
    call member_mention_at
    test eax, eax
    jz .next
    mov [rsp + 4], eax                      ; its length
    mov [rsp + 8], edx                      ; 1 if it's us
    mov edi, r12d
    mov esi, r13d
    mov eax, [rsp]
    lea rdx, [rbx + rax]
    mov ecx, ebp
    sub ecx, eax
    mov r8d, r15d
    call draw_text
    mov r12d, eax
    cmp dword [rsp + 8], 0
    je .mention
    lea rdi, [rbx + rbp]
    mov esi, [rsp + 4]
    mov edx, r15d
    shr edx, 24
    call text_width
    lea edi, [r12d - 2]
    lea esi, [r13d - 14]
    lea edx, [eax + 4]
    mov ecx, 19
    mov r8d, C_SELECTION
    mov r9d, 4
    call fill_rrect
.mention:
    mov edi, r12d
    mov esi, r13d
    lea rdx, [rbx + rbp]
    mov ecx, [rsp + 4]
    mov r8d, r15d
    and r8d, 0xff000000                     ; the style, in the mention's color
    or r8d, C_MENTION
    call draw_text
    mov r12d, eax
    add ebp, [rsp + 4]
    mov [rsp], ebp
    jmp .scan
.next:
    inc ebp
    jmp .scan
.rest:
    mov edi, r12d
    mov esi, r13d
    mov eax, [rsp]
    lea rdx, [rbx + rax]
    mov ecx, r14d
    sub ecx, eax
    mov r8d, r15d
    call draw_text
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The mention being typed in the focused box: the caret just after "@" and
; part of a name, with nothing selected. Esc closes its list until that "@"
; goes. -> rax = the field's struct and mention_from set, or rax = 0
mention_query:
    push rbx
    cmp byte [keyboard_focus], 0
    je .none
    mov edi, [focus]
    cmp edi, F_NEW_DESC
    je .box
    lea eax, [edi - F_DESC]                 ; F_DESC, F_COMMENT, F_MESSAGE and F_EDIT
    cmp eax, F_EDIT - F_DESC
    ja .none
.box:
    call field_addr
    mov rbx, rax
    mov ecx, [rbx + FD_CURSOR]
    cmp ecx, [rbx + FD_ANCHOR]
    jne .none
    mov rsi, [rbx + FD_BUF]
    mov edx, ecx
.back:
    test edx, edx
    jz .none
    movzx edi, byte [rsi + rdx - 1]
    cmp edi, '@'
    je .at
    call mention_char
    test eax, eax
    jz .none
    dec edx
    mov eax, ecx
    sub eax, edx
    cmp eax, USERNAME_MAX
    ja .none
    jmp .back
.at:
    dec edx
    jz .found
    movzx edi, byte [rsi + rdx - 1]
    call mention_char
    test eax, eax
    jnz .none                               ; an address, like x@y
.found:
    mov eax, [focus]
    cmp eax, [mention_shut_field]
    jne .open
    cmp edx, [mention_shut_at]
    je .shut
.open:
    mov dword [mention_shut_field], F_NONE
    mov [mention_from], edx
    mov rax, rbx
    pop rbx
    ret
.none:
    mov dword [mention_shut_field], F_NONE
.shut:
    xor eax, eax
    pop rbx
    ret

; The members, us aside, whose names start with what's typed after the "@",
; into mention_rows. rdi = the field's struct -> eax = how many
match_mentions:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov rax, [rdi + FD_BUF]
    mov ecx, [mention_from]
    lea r12, [rax + rcx + 1]                ; what's typed
    mov r13d, [rdi + FD_CURSOR]
    sub r13d, ecx
    dec r13d                                ; and its length
    lea rbx, [members]
    mov r14d, [member_count]
    xor ebp, ebp
.member:
    test r14d, r14d
    jz .done
    cmp ebp, MENTION_SHOWN
    jae .done
    mov eax, [rbx + CM_ID]
    cmp eax, [my_id]
    je .next
    movzx eax, byte [rbx + CM_NAME_LEN]
    cmp eax, r13d
    jb .next
    xor ecx, ecx
.char:
    cmp ecx, r13d
    jae .match
    movzx eax, byte [r12 + rcx]
    lea edx, [eax - 'A']
    cmp edx, 'Z' - 'A'
    ja .compare
    or eax, 0x20                            ; usernames are lowercase
.compare:
    cmp al, [rbx + CM_NAME + rcx]
    jne .next
    inc ecx
    jmp .char
.match:
    mov [mention_rows + rbp * 8], rbx
    inc ebp
.next:
    add rbx, CM_SIZE
    dec r14d
    jmp .member
.done:
    cmp [mention_sel], ebp
    jb .selected
    mov dword [mention_sel], 0
.selected:
    mov eax, ebp
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -> rax = the focused field's struct while a mention typed in it matches
; someone, edx = how many, or rax = 0 with no list to show
mention_list:
    sub rsp, 8
    call mention_query
    test rax, rax
    jz .done
    mov [rsp], rax
    mov rdi, rax
    call match_mentions
    mov edx, eax
    mov rax, [rsp]
    test edx, edx
    jnz .done
    xor eax, eax
.done:
    add rsp, 8
    ret

; Keys while the mention list is up: the arrows move through it, Enter or
; Tab picks, and Esc closes it. edi = key code -> eax = 1 if handled here
mention_key:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    call mention_list
    test rax, rax
    jz .not_mine
    mov r12d, edx
    test dword [modifiers], MOD_SHIFT | MOD_CTRL | MOD_ALT
    jnz .not_mine                           ; Shift+Enter is still a new line
    cmp ebx, KEY_DOWN
    je .down
    cmp ebx, KEY_UP
    je .up
    cmp ebx, KEY_ENTER
    je .pick
    cmp ebx, KEY_KPENTER
    je .pick
    cmp ebx, KEY_TAB
    je .pick
    cmp ebx, KEY_ESC
    jne .not_mine
    mov eax, [focus]
    mov [mention_shut_field], eax
    mov eax, [mention_from]
    mov [mention_shut_at], eax
    jmp .handled
.down:
    mov eax, [mention_sel]
    inc eax
    cmp eax, r12d
    jb .move
    xor eax, eax
    jmp .move
.up:
    mov eax, [mention_sel]
    test eax, eax
    jnz .up_one
    mov eax, r12d
.up_one:
    dec eax
.move:
    mov [mention_sel], eax
    jmp .handled
.pick:
    mov edi, [mention_sel]
    call pick_mention
.handled:
    mov eax, 1
    jmp .done
.not_mine:
    xor eax, eax
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; Replaces the mention being typed with a member's whole name and a space.
; edi = the row in mention_rows
pick_mention:
    push rbx
    push r12
    push r13
    mov r12d, edi
    call mention_list
    test rax, rax
    jz .done
    cmp r12d, edx
    jae .done
    mov rbx, rax
    mov r13, [mention_rows + r12 * 8]
    ; With the caret inside a name, all of it goes, not just what's before.
    mov ecx, [rbx + FD_CURSOR]
    mov rsi, [rbx + FD_BUF]
.name_end:
    cmp ecx, [rbx + FD_LEN]
    jae .select
    movzx edi, byte [rsi + rcx]
    call mention_char
    test eax, eax
    jz .select
    inc ecx
    jmp .name_end
.select:
    mov [rbx + FD_CURSOR], ecx
    mov eax, [mention_from]
    inc eax
    mov [rbx + FD_ANCHOR], eax
    mov edi, [focus]
    lea rsi, [r13 + CM_NAME]
    movzx edx, byte [r13 + CM_NAME_LEN]
    call field_insert_text
    mov dword [mention_sel], 0
    mov ecx, [rbx + FD_CURSOR]
    cmp ecx, [rbx + FD_LEN]
    jae .space
    mov rax, [rbx + FD_BUF]
    cmp byte [rax + rcx], ' '
    jne .space
    inc ecx                                 ; one's there already
    mov [rbx + FD_CURSOR], ecx
    mov [rbx + FD_ANCHOR], ecx
    jmp .done
.space:
    mov edi, [focus]
    mov esi, ' '
    call field_insert
.done:
    mov byte [need_redraw], 1
    pop r13
    pop r12
    pop rbx
    ret

; The list of members a mention being typed could be, over everything else,
; above the caret, or under it when there's no room above.
draw_mentions:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, [wrap_caret_x]
    mov r13d, [wrap_caret_y]
    mov dword [wrap_caret_y], -1            ; until a caret is drawn again
    cmp r13d, -1
    je .done
    call mention_list
    test rax, rax
    jz .done
    mov ebp, edx
    imul r14d, ebp, MENTION_ROW_H
    add r14d, 12                            ; its height
    sub r12d, 16
    mov eax, [win_w]
    sub eax, MENTION_W + 8
    cmp r12d, eax
    cmovg r12d, eax
    mov eax, 8
    cmp r12d, eax
    cmovl r12d, eax
    mov eax, r13d
    sub eax, r14d
    sub eax, 6
    cmp eax, 8
    jge .above
    lea eax, [r13d + 22]
.above:
    mov r13d, [win_h]                       ; and inside the window either way
    sub r13d, r14d
    sub r13d, 8
    cmp eax, r13d
    cmovl r13d, eax
    mov edi, r12d
    mov esi, r13d
    mov edx, MENTION_W
    mov ecx, r14d
    mov r8d, C_LINE
    mov r9d, C_RAISED
    mov r10d, 10
    call outline_rrect
    mov edi, r12d
    mov esi, r13d
    mov edx, MENTION_W
    mov ecx, r14d
    mov r8d, A_BLOCK
    xor r9d, r9d
    call add_hit
    xor ebx, ebx
.row:
    cmp ebx, ebp
    jae .done
    imul r15d, ebx, MENTION_ROW_H
    lea r15d, [r15d + r13d + 6]             ; the row's top
    mov r8d, C_SELECT
    cmp ebx, [mention_sel]
    je .highlight
    mov edi, A_MENTION
    mov esi, ebx
    call hovering
    test eax, eax
    jz .item
    mov r8d, C_HOVER
.highlight:
    lea edi, [r12d + 6]
    mov esi, r15d
    mov edx, MENTION_W - 12
    mov ecx, MENTION_ROW_H
    mov r9d, 6
    call fill_rrect
.item:
    lea edi, [r12d + 6]
    mov esi, r15d
    mov edx, MENTION_W - 12
    mov ecx, MENTION_ROW_H
    mov r8d, A_MENTION
    mov r9d, ebx
    call add_hit
    mov rax, [mention_rows + rbx * 8]
    lea edi, [r12d + 16]
    lea esi, [r15d + 7]
    mov edx, 18
    mov ecx, [rax + CM_ID]
    lea r8, [rax + CM_NAME]
    call draw_avatar
    mov rax, [mention_rows + rbx * 8]
    lea edi, [r12d + 44]
    lea esi, [r15d + 21]
    lea rdx, [rax + CM_NAME]
    movzx ecx, byte [rax + CM_NAME_LEN]
    mov r8d, INK(C_TEXT, ST_BODY)
    mov r9d, MENTION_W - 60
    call draw_text_fit
    inc ebx
    jmp .row
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
