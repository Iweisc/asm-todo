; ui-test's checks of mentions: what counts as one, the list that comes up
; while one is typed, and the "@" on a channel where one is waiting for us.
; ui_test.asm includes this at its end.

section .rodata
n_mention_rules: db "@name is a mention alone or before a full stop, not inside a word or a longer name", 0
n_mention_who:  db "mentions of members are found, and ours told apart", 0
n_mention_pick: db "Enter in the mention list picks the member rather than sending", 0
n_mention_esc:  db "Esc closes the mention list and leaves the conversation open", 0
n_mention_live: db "a message mentioning us marks its channel until it's opened", 0
n_mention_unread: db "UNREAD's mentions put an @ on their channel's row", 0

; Each case: 1 if it mentions maya, the text's length, the text. 0xff ends them.
%macro MENTION_CASE 2
    db %1, %%end - %%text
%%text: db %2
%%end:
%endmacro
t_mention_cases:
    MENTION_CASE 1, "hi @maya"
    MENTION_CASE 1, "@maya."
    MENTION_CASE 1, "(@Maya) thanks"
    MENTION_CASE 1, "@maya..."
    MENTION_CASE 0, "x@maya"
    MENTION_CASE 0, "@mayabe"
    MENTION_CASE 0, "@maya.lee"
    MENTION_CASE 0, "@maya_"
    MENTION_CASE 0, "@may"
    db 0xff

t_at_maya:      db "@maya"
t_at_lewis:     db "@lewis"
t_at_nobody:    db "@nobody"
t_hey_ma:       db "hey @ma", 0
t_hey_maya:     db "hey @maya "
t_hey_maya_len  equ $ - t_hey_maya
t_at_m:         db "@m", 0
; MSG_CHAT past the type byte: maya to #general, plain and then mentioning us.
%macro GENERAL_MESSAGE 2                ; id, text
    dd 1, %1, 2, 0, 0
    dw %%end - %%text
%%text: db %2
%%end:
    db 0
    dd 0
    dw 0, 0
%endmacro
t_chat_plain:   GENERAL_MESSAGE 30, "lunch?"
t_chat_plain_len equ $ - t_chat_plain
t_chat_tagged:  GENERAL_MESSAGE 31, "ping @lewis"
t_chat_tagged_len equ $ - t_chat_tagged
; MSG_UNREAD past the type byte: #general unread, and mentioning us.
t_unread_tagged: dd 1
                db 1
                dd 0
                db 1
                dd 0
t_unread_tagged_len equ $ - t_unread_tagged

section .text

; Signs in again, with maya on the team, since logout_tests ran before these.
mention_tests:
    push rbx
    push r12
    sub rsp, 8
    call sign_in
    call add_maya

    mov ebx, 1
    lea r12, [t_mention_cases]
.case:
    movzx eax, byte [r12]
    cmp eax, 0xff
    je .cases_done
    lea rdi, [r12 + 2]
    movzx esi, byte [r12 + 1]
    lea rdx, [t_maya]
    mov ecx, 4
    call text_mentions
    movzx ecx, byte [r12]
    cmp eax, ecx
    je .case_ok
    xor ebx, ebx
.case_ok:
    movzx eax, byte [r12 + 1]
    lea r12, [r12 + rax + 2]
    jmp .case
.cases_done:
    mov esi, ebx
    lea rdi, [n_mention_rules]
    call check

    xor ebx, ebx
    lea rdi, [t_at_maya]
    mov esi, 5
    xor edx, edx
    call member_mention_at
    cmp eax, 5
    jne .who
    test edx, edx
    jnz .who
    lea rdi, [t_at_lewis]
    mov esi, 6
    xor edx, edx
    call member_mention_at
    cmp eax, 6
    jne .who
    cmp edx, 1
    jne .who
    lea rdi, [t_at_nobody]
    mov esi, 7
    xor edx, edx
    call member_mention_at
    test eax, eax
    sete bl
.who:
    mov esi, ebx
    lea rdi, [n_mention_who]
    call check

    call typing_tests
    call channel_mark_tests
    add rsp, 8
    pop r12
    pop rbx
    ret

; The list while a mention is typed in the message box.
typing_tests:
    push rbx
    xor edi, edi
    call open_chat
    mov byte [chat_loaded], 1
    mov edi, F_MESSAGE                      ; an earlier test's draft
    call field_clear
    mov edi, F_MESSAGE
    lea rsi, [t_hey_ma]
    call type_into
    call frame
    xor ebx, ebx
    mov edi, A_MENTION
    xor esi, esi
    call find_hit
    test rax, rax
    jz .picked
    mov edi, KEY_ENTER
    call ui_key
    mov edi, F_MESSAGE
    call field_addr
    cmp dword [rax + FD_LEN], t_hey_maya_len
    jne .picked
    mov rdi, [rax + FD_BUF]
    lea rsi, [t_hey_maya]
    mov edx, t_hey_maya_len
    call mem_eq
    mov ebx, eax
.picked:
    mov esi, ebx
    lea rdi, [n_mention_pick]
    call check

    mov edi, F_MESSAGE
    call field_clear
    mov edi, F_MESSAGE
    lea rsi, [t_at_m]
    call type_into
    call frame
    xor ebx, ebx
    mov edi, A_MENTION
    xor esi, esi
    call find_hit
    test rax, rax
    jz .closed
    mov edi, KEY_ESC
    call ui_key
    call frame
    cmp byte [chat_open], 1
    jne .closed
    cmp dword [focus], F_MESSAGE
    jne .closed
    mov edi, A_MENTION
    xor esi, esi
    call find_hit
    test rax, rax
    setz bl
.closed:
    mov esi, ebx
    lea rdi, [n_mention_esc]
    call check
    mov edi, F_MESSAGE
    call field_clear
    call close_detail
    pop rbx
    ret

; Mentions arriving, live and in UNREAD, with #general closed.
channel_mark_tests:
    push rbx
    xor ebx, ebx
    lea rdi, [t_chat_plain]
    mov esi, t_chat_plain_len
    call rd_begin
    call on_chat
    xor edi, edi
    call is_mentioned
    test eax, eax
    jnz .live
    lea rdi, [t_chat_tagged]
    mov esi, t_chat_tagged_len
    call rd_begin
    call on_chat
    xor edi, edi
    call is_mentioned
    test eax, eax
    jz .live
    xor edi, edi
    call open_chat
    xor edi, edi
    call is_mentioned
    test eax, eax
    setz bl
.live:
    call close_detail
    mov esi, ebx
    lea rdi, [n_mention_live]
    call check

    xor ebx, ebx
    lea rdi, [t_unread_tagged]
    mov esi, t_unread_tagged_len
    call rd_begin
    call on_unread
    call rd_ok
    test eax, eax
    jz .unread
    call frame
    mov edi, A_CHAT
    xor esi, esi
    call find_hit
    test rax, rax
    jz .unread
    ; Left of where the dot would be, so only the badge reaches it.
    mov ecx, [rax + HIT_Y]
    add ecx, 14
    imul ecx, ecx, TEST_W
    add ecx, SIDEBAR_W - 26 - 7
    mov eax, [test_fb + rcx * 4]
    and eax, 0xffffff
    cmp eax, C_ACCENT
    sete bl
.unread:
    mov esi, ebx
    lea rdi, [n_mention_unread]
    call check
    mov dword [mention_marks], 0
    mov dword [unread_count], 0
    pop rbx
    ret
