; The chat: opening a conversation, and drawing it with the box for the
; next message. The sidebar rows that open one live in sidebar.asm and
; channel.asm, and editing messages in chatedit.asm.

section .rodata
text s_channel_intro,   "This is the start of the channel. Everyone in the team can read it."
text s_dm_intro,        "This is the start of your conversation with "

section .bss
alignb 4
chat_scroll:    resd 1                  ; how far up from the newest message
draft_peer:     resd 1                  ; whose conversation the message box's text was written in
chat_heights:   resd VIEW_CHAT          ; each message's height, measured before drawing

section .text

; Opens a conversation, ready to type, with what was typed in it last time
; if it's the same one. edi = peer, 0 for the team's channel
open_chat:
    push rbx
    mov ebx, edi
    cmp dword [current_team], 0
    je .done
    cmp byte [chat_open], 0
    je .open
    cmp [chat_peer], ebx
    je .focus                               ; already open, keep the draft
.open:
    call close_detail
    mov dword [chat_scroll], 0
    cmp [draft_peer], ebx
    je .keep_draft
    mov [draft_peer], ebx
    mov edi, F_MESSAGE
    call field_clear
.keep_draft:
    mov edi, ebx
    call sync_open_chat
.focus:
    mov edi, F_MESSAGE
    call set_focus
.done:
    pop rbx
    ret

; The member list changed. A conversation with someone who left closes.
ui_members_changed:
    call clear_joined_invite
    cmp byte [chat_open], 0
    je .done
    mov edi, [chat_peer]
    test edi, edi
    jle .done                               ; a channel
    call find_member_row
    test rax, rax
    jz close_detail
.done:
    ret

; Empties the invite box once the name typed in it is a member.
clear_joined_invite:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov edi, F_MEMBER
    call field_trimmed
    test edx, edx
    jz .done
    mov r12, rsi
    mov r13d, edx
    lea rbx, [members]
    imul eax, [member_count], CM_SIZE
    lea r14, [rbx + rax]
.member:
    cmp rbx, r14
    jae .done
    movzx edx, byte [rbx + CM_NAME_LEN]
    cmp edx, r13d
    jne .next
    lea rdi, [rbx + CM_NAME]
    mov rsi, r12
    call mem_eq
    test eax, eax
    jz .next
    mov edi, F_MEMBER
    call field_clear
    jmp .done
.next:
    add rbx, CM_SIZE
    jmp .member
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%define CHAT_AVATAR     32
%define CHAT_TEXT_X     44              ; where text starts, right of the avatars
%define CHAT_RUN        300             ; seconds apart that still read as one run of messages
%define CHAT_INTRO_H    84

; One message. The first of a run from one person shows their avatar, name
; and time, and the rest of the run is only its text.
; rdi = the message, rsi = the one before it or 0, edx = x, ecx = y,
; r8d = width, r9d = 1 to draw, 0 to only measure -> eax = height
lay_message:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov r12d, edx
    mov r13d, ecx
    mov r14d, r8d
    mov r15d, r9d
    xor ebp, ebp                            ; the text's offset from y
    test rsi, rsi
    jz .header
    mov eax, [rsi + CH_AUTHOR]
    cmp eax, [rbx + CH_AUTHOR]
    jne .gap
    mov eax, [rbx + CH_CREATED]
    sub eax, [rsi + CH_CREATED]
    cmp eax, CHAT_RUN
    ja .gap
    cmp byte [rbx + CH_EDITED], 0           ; its header is where "(edited)" goes
    jne .header
    jmp .text
.gap:
    mov ebp, 14
.header:
    test r15d, r15d
    jz .header_done
    mov rdi, rbx
    mov esi, r12d
    lea edx, [r13d + ebp]
    call draw_message_head
.header_done:
    add ebp, 20
.text:
    mov eax, [rbx + CH_ID]
    test eax, eax
    jz .plain
    cmp eax, [editing_message]
    jne .plain
    lea edi, [r14d - CHAT_TEXT_X]
    test r15d, r15d
    jnz .editor
    call edit_box_height
    jmp .height
.editor:
    lea edi, [r12d + CHAT_TEXT_X]
    lea esi, [r13d + ebp]
    lea edx, [r14d - CHAT_TEXT_X]
    call draw_comment_editor
    jmp .height
.plain:
    xor eax, eax
    cmp word [rbx + CH_LEN], 0
    je .text_done                           ; just an image
    lea rdi, [rbx + CH_TEXT]
    movzx esi, word [rbx + CH_LEN]
    lea edx, [r14d - CHAT_TEXT_X]
    test r15d, r15d
    jnz .draw
    mov ecx, ST_BODY
    call text_height
    jmp .text_done
.draw:
    mov r8d, edx
    lea edx, [r12d + CHAT_TEXT_X]
    lea ecx, [r13d + ebp]
    mov r9d, INK(C_TEXT, ST_BODY)
    mov eax, INK(C_DIM, ST_BODY)            ; not on the server yet
    cmp byte [rbx + CH_PENDING], 0
    cmovne r9d, eax
    call draw_wrapped
.text_done:
    mov [rsp + 8], eax
    lea rdi, [rbx + CH_IMAGE]
    lea esi, [r14d - CHAT_TEXT_X]
    call image_ref_height
    add eax, [rsp + 8]
.height:
    add eax, ebp
    test r15d, r15d
    jz .out
    mov [rsp], eax
    mov ecx, [rbx + CH_ID]
    cmp ecx, [editing_message]
    je .drawn                               ; the box takes the clicks
    ; The whole message, so hovering anywhere on it shows its actions.
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov r8d, A_MESSAGE
    mov r9d, ecx
    mov ecx, eax
    call add_hit
    lea edx, [ebp - 24]                     ; the strip sits on the header, or the first line
    mov eax, -2
    cmp edx, eax
    cmovl edx, eax
    add edx, r13d
    mov rdi, rbx
    lea esi, [r12d + r14d]
    call draw_message_actions
    ; The image last, so clicks on it open it rather than land on the message.
    lea rdi, [rbx + CH_IMAGE]
    lea esi, [r12d + CHAT_TEXT_X]
    mov edx, [rsp + 8]
    add edx, r13d
    add edx, ebp
    lea ecx, [r14d - CHAT_TEXT_X]
    call draw_image_ref
.drawn:
    mov eax, [rsp]
.out:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The first message of a run's avatar, name and time. rdi = the message, esi = x, edx = y
draw_message_head:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov edi, [rbx + CH_AUTHOR]
    call user_name
    mov r8, rsi
    mov edi, r12d
    lea esi, [r13d + 2]
    mov edx, CHAT_AVATAR
    mov ecx, [rbx + CH_AUTHOR]
    call draw_avatar
    mov edi, [rbx + CH_AUTHOR]
    call user_name
    mov ecx, edx
    mov rdx, rsi
    lea edi, [r12d + CHAT_TEXT_X]
    lea esi, [r13d + 14]
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    mov r12d, eax                           ; where the name ends
    lea rdi, [scratch]
    mov esi, [rbx + CH_CREATED]
    call put_ago
    cmp byte [rbx + CH_EDITED], 0
    je .when
    lea rsi, [s_edited]
    mov edx, s_edited_len
    call put_mem
.when:
    mov rcx, rdi
    lea edi, [r12d + 8]
    lea esi, [r13d + 14]
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_scratch
    pop r13
    pop r12
    pop rbx
    ret

; The top of a conversation, above its first message. edi = x, esi = y
draw_chat_intro:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    lea rdi, [scratch]
    call put_chat_name
    mov rcx, rdi
    mov edi, ebx
    lea esi, [r12d + 36]
    mov r8d, INK(C_TEXT, ST_TITLE)
    call draw_scratch
    lea rdi, [scratch]
    lea rsi, [s_channel_intro]
    mov edx, s_channel_intro_len
    cmp dword [chat_peer], 0
    jle .line                               ; a channel
    lea rsi, [s_dm_intro]
    mov edx, s_dm_intro_len
    call put_mem
    call put_chat_name
    mov byte [rdi], '.'
    inc rdi
    jmp .draw
.line:
    call put_mem
.draw:
    mov rcx, rdi
    mov edi, ebx
    lea esi, [r12d + 62]
    mov r8d, INK(C_DIM, ST_BODY)
    call draw_scratch
    add rsp, 8
    pop r12
    pop rbx
    ret

; The box for the next message, which grows upwards with what's typed.
; edi = x, esi = w, edx = bottom -> eax = the box's top
draw_composer:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 8
    mov ebx, edi
    mov [rsp], esi
    mov r12d, edx
    mov edi, F_MESSAGE
    call field_addr
    mov rdi, [rax + FD_BUF]
    mov esi, [rax + FD_LEN]
    mov edx, [rsp]
    sub edx, 24 + BOX_BUTTONS_W
    mov ecx, ST_BODY
    call text_height
    lea ebp, [eax + 24]                     ; the box's height
    sub r12d, ebp
    sub r12d, 32                            ; and its top
    mov edi, F_MESSAGE
    call attachment_height
    mov edi, F_MESSAGE
    mov esi, ebx
    mov edx, r12d
    sub edx, eax
    call draw_attachment
    mov edi, F_MESSAGE
    call field_focused
    mov r13d, eax
    mov r8d, C_LINE
    mov ecx, C_ACCENT
    test eax, eax
    cmovnz r8d, ecx
    mov edi, ebx
    mov esi, r12d
    mov edx, [rsp]
    mov ecx, ebp
    mov r9d, C_RAISED
    mov r10d, 8
    call outline_rrect
    mov edi, ebx
    mov esi, r12d
    mov edx, [rsp]
    mov ecx, ebp
    mov r8d, A_FIELD
    mov r9d, F_MESSAGE
    call add_hit
    mov edi, F_MESSAGE
    lea esi, [ebx + 12]
    lea edx, [r12d + 12]
    mov ecx, [rsp]
    sub ecx, 24 + BOX_BUTTONS_W
    call draw_area
    mov edi, F_MESSAGE
    mov esi, ebx
    add esi, [rsp]
    lea edx, [r12d + ebp]
    call draw_box_buttons
    test r13d, r13d
    jz .done
    mov edi, ebx
    lea esi, [r12d + ebp + 20]
    lea rdx, [s_enter_send]
    mov ecx, s_enter_send_len
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_text
.done:
    mov edi, F_MESSAGE
    call attachment_height
    neg eax
    add eax, r12d                           ; the attachment's top, or the box's
    add rsp, 8
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The open conversation: newest message at the bottom, scrolled up by
; chat_scroll, and the box for the next one under it.
; edi = x, esi = top, edx = w, ecx = h
draw_chat:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    lea eax, [edi + 24]
    mov [rsp], eax                          ; the column's x
    lea eax, [edx - 48]
    mov [rsp + 4], eax                      ; its width
    mov [rsp + 8], esi                      ; top
    add esi, ecx
    mov [rsp + 12], esi                     ; bottom

    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 12]
    call draw_composer
    lea r12d, [eax - 8]
    mov [rsp + 12], r12d                    ; the messages end above the box
    call save_clip
    mov [rsp + 16], rax
    mov edi, [rsp]
    sub edi, 24
    mov esi, [rsp + 8]
    mov edx, [rsp]
    add edx, [rsp + 4]
    add edx, 24
    mov ecx, [rsp + 12]
    call clip_to
    cmp byte [chat_loaded], 0
    je .loading

    ; Measure them all first, so the newest can sit at the bottom.
    mov r15d, CHAT_INTRO_H
    lea rbx, [view_chat]
    xor r14d, r14d
.measure:
    cmp r14d, [view_chat_count]
    jae .measured
    mov rdi, rbx
    call .previous
    mov edx, [rsp]
    xor ecx, ecx
    mov r8d, [rsp + 4]
    xor r9d, r9d
    call lay_message
    mov [chat_heights + r14 * 4], eax
    add r15d, eax
    add rbx, CH_SIZE
    inc r14d
    jmp .measure
.measured:
    add r15d, 12                            ; some room under the newest
    mov [content_h], r15d
    mov r13d, [rsp + 12]
    sub r13d, [rsp + 8]                     ; the visible height
    lea rdi, [chat_scroll]
    mov esi, r13d
    call clamp_scroll
    ; Short conversations start at the top, long ones end at the bottom.
    mov r12d, r13d
    sub r12d, r15d
    xor eax, eax
    cmp r12d, eax
    cmovg r12d, eax
    add r12d, [chat_scroll]
    add r12d, [rsp + 8]                     ; where the intro goes
    mov edi, [rsp]
    mov esi, r12d
    call draw_chat_intro
    add r12d, CHAT_INTRO_H
    lea rbx, [view_chat]
    xor r14d, r14d
.message:
    cmp r14d, [view_chat_count]
    jae .done
    cmp r12d, [rsp + 12]
    jge .done                               ; the rest are below what shows
    mov eax, [chat_heights + r14 * 4]
    add eax, r12d
    cmp eax, [rsp + 8]
    jle .next                               ; above it
    mov rdi, rbx
    call .previous
    mov edx, [rsp]
    mov ecx, r12d
    mov r8d, [rsp + 4]
    mov r9d, 1
    call lay_message
.next:
    add r12d, [chat_heights + r14 * 4]
    add rbx, CH_SIZE
    inc r14d
    jmp .message
.loading:
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    add edx, 80
    lea rcx, [s_loading]
    mov r8d, s_loading_len
    mov r9d, INK(C_DIM, ST_MEDIUM)
    call draw_centered
.done:
    mov rdi, [rsp + 16]
    call restore_clip
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
; rbx = a message, r14d = its index -> rsi = the one before it, or 0
.previous:
    xor esi, esi
    test r14d, r14d
    jz .first
    lea rsi, [rbx - CH_SIZE]
.first:
    ret
