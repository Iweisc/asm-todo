; Team chat: every team has a channel, and its members can message each
; other directly.
;
; Messages aren't part of the issue sync. They don't bump the team's seq,
; and they go only to the connections viewing the team whose user may read
; them. A conversation is named from one side by its peer: 0 for the
; channel, or the other member. Opening one fetches its newest messages.
; Seen marks remember the newest message each member has seen in each
; conversation, so unread ones still show after a restart.

%define UNREAD_MAX      128

section .bss
alignb 8
history:        resq CHAT_HISTORY           ; rows h_open_chat sends, oldest first
unread_peer:    resd UNREAD_MAX
unread_newest:  resd UNREAD_MAX

section .text

; rdi = cursor, rsi = message row -> rdi advanced. The wire layout is in config.inc.
wr_message:
    push rbx
    mov rbx, rsi
    mov esi, [rbx + MS_ID]
    call wr_u32
    mov esi, [rbx + MS_FROM]
    call wr_u32
    mov esi, [rbx + MS_TO]
    call wr_u32
    mov esi, [rbx + MS_CREATED]
    call wr_u32
    lea rsi, [rbx + MS_TEXT]
    movzx edx, word [rbx + MS_LEN]
    call wr_str16
    pop rbx
    ret

; Which of a user's conversations a message is in. The team isn't checked.
; rdi = message row, esi = user -> eax = the peer, or -1 if it isn't theirs
message_peer:
    mov eax, [rdi + MS_TO]
    test eax, eax
    jz .done                                ; the channel
    cmp [rdi + MS_FROM], esi
    je .done                                ; they sent it, so it's with whoever got it
    cmp eax, esi
    jne .theirs_not
    mov eax, [rdi + MS_FROM]
.done:
    ret
.theirs_not:
    mov eax, -1
    ret

; Whether a connection gets a message.
; edi = connection index, rsi = message row
; -> eax = the peer it's in for that connection, or -1, rdx = the connection
message_target:
    push rsi
    call conn_addr
    pop rdi
    mov rdx, rax
    mov eax, -1
    cmp byte [rdx + C_STATE], ST_OPEN
    jne .done
    mov esi, [rdx + C_USER]
    test esi, esi
    jz .done
    mov ecx, [rdx + C_TEAM]
    cmp ecx, [rdi + MS_TEAM]
    jne .done
    jmp message_peer
.done:
    ret

; edi = user, esi = team, edx = peer -> rax = their seen row, or 0
find_seen:
    lea rax, [seen]
    mov ecx, [n_seen]
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + SEEN_USER], edi
    jne .next
    cmp [rax + SEEN_TEAM], esi
    jne .next
    cmp [rax + SEEN_PEER], edx
    je .done
.next:
    add rax, SEEN_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; Remembers that a user has seen a conversation up to a message. The row is
; touched, not committed. A full table only costs a stale unread dot.
; edi = user, esi = team, edx = peer, ecx = message id
mark_seen:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    call find_seen
    test rax, rax
    jnz .have
    mov edi, T_SEEN
    call alloc_row
    test rax, rax
    jz .done
    mov [rax + SEEN_USER], ebx
    mov [rax + SEEN_TEAM], r12d
    mov [rax + SEEN_PEER], r13d
.have:
    cmp [rax + SEEN_LAST], r14d
    jae .done
    mov [rax + SEEN_LAST], r14d
    mov edi, T_SEEN
    mov rsi, rax
    call db_touch
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; A removed member's seen marks in the team go with them. edi = team, esi = user
forget_seen:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    lea rbx, [seen]
    mov r14d, [n_seen]
.row:
    test r14d, r14d
    jz .done
    cmp [rbx + SEEN_USER], r13d
    jne .next
    cmp [rbx + SEEN_TEAM], r12d
    jne .next
    mov edi, T_SEEN
    mov rsi, rbx
    call free_row
.next:
    add rbx, SEEN_SIZE
    dec r14d
    jmp .row
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Frees the oldest message's row for a new one. Only for a full table.
; -> rax = the row, wiped
evict_oldest_message:
    push rbx
    lea rax, [messages]
    mov rbx, rax
    mov ecx, [n_messages]
.row:
    mov edx, [rax + MS_ID]
    cmp edx, [rbx + MS_ID]
    cmovb rbx, rax
    add rax, MS_SIZE
    dec ecx
    jnz .row
    mov rdi, rbx
    mov esi, MS_SIZE
    call wipe
    mov rax, rbx
    pop rbx
    ret

; Sends a message to the team's channel or to one member, and to everyone
; who may read it. A message arriving in a conversation someone has open
; counts as seen by them.
op_message:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov rax, [op_team]
    mov r12d, [rax + TEAM_ID]
    mov r13d, [op_issue]                    ; who it goes to
    cmp dword [op_body_len], 0
    je .invalid
    mov rsi, [op_body]
    mov edx, [op_body_len]
    mov ecx, MESSAGE_MAX
    call valid_body
    test eax, eax
    jz .invalid
    test r13d, r13d
    jz .store
    mov edi, r12d
    mov esi, r13d
    call find_member
    test rax, rax
    jz .invalid
.store:
    mov edi, T_MESSAGES
    call alloc_row
    test rax, rax
    jnz .row
    call evict_oldest_message
.row:
    mov rbx, rax
    mov eax, [next_message_id]
    inc dword [next_message_id]
    mov [rbx + MS_ID], eax
    mov [rbx + MS_TEAM], r12d
    mov eax, [op_user]
    mov [rbx + MS_FROM], eax
    mov [rbx + MS_TO], r13d
    call now_unix
    mov [rbx + MS_CREATED], eax
    mov ecx, [op_body_len]
    mov [rbx + MS_LEN], cx
    lea rdi, [rbx + MS_TEXT]
    mov rsi, [op_body]
    rep movsb
    mov edi, T_MESSAGES
    mov rsi, rbx
    call db_touch

    ; Seen marks first, so they're committed along with the message, which
    ; must be on disk before anyone hears about it.
    xor ebp, ebp
.seen:
    mov edi, ebp
    mov rsi, rbx
    call message_target
    cmp eax, -1
    je .next_seen
    test byte [rdx + C_FLAGS], F_CHAT
    jz .next_seen
    cmp [rdx + C_CHAT], eax
    jne .next_seen
    mov edi, [rdx + C_USER]
    mov esi, r12d
    mov edx, eax
    mov ecx, [rbx + MS_ID]
    call mark_seen
.next_seen:
    inc ebp
    cmp ebp, MAX_CONN
    jb .seen
    call db_commit

    lea rdi, [msg_buf]
    mov esi, MSG_CHAT
    call wr_u8
    mov esi, r12d
    call wr_u32
    mov rsi, rbx
    call wr_message
    lea rax, [msg_buf]
    sub rdi, rax
    mov r14d, edi                           ; the message's length
    xor ebp, ebp
.send:
    mov edi, ebp
    mov rsi, rbx
    call message_target
    cmp eax, -1
    je .next_send
    mov edi, ebp
    lea rsi, [msg_buf]
    mov edx, r14d
    call send_msg
.next_send:
    inc ebp
    cmp ebp, MAX_CONN
    jb .send
    xor eax, eax
    jmp .done
.invalid:
    mov eax, ACK_INVALID
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Opens one of the user's conversations in the team the connection is
; viewing: its newest messages, oldest first, and they count as seen. Any
; peer is fine, since only messages the user was part of come back.
h_open_chat:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    call rd_u32
    mov r12d, eax                           ; peer
    call rd_ok
    test eax, eax
    jz .violation
    mov rbx, [cur]
    and byte [rbx + C_FLAGS], ~F_CHAT
    cmp r12d, -1
    je .done                                ; closing it
    mov r13d, [rbx + C_TEAM]
    test r13d, r13d
    jz .done
    mov r14d, [rbx + C_USER]
    mov [rbx + C_CHAT], r12d
    or byte [rbx + C_FLAGS], F_CHAT

    ; Slots get reused, so table order isn't age order. Keep the newest
    ; CHAT_HISTORY in history, sorted by id as they're found.
    xor ebp, ebp                            ; rows kept
    lea r15, [messages]
    mov ecx, [n_messages]
.scan:
    test ecx, ecx
    jz .write
    cmp [r15 + MS_TEAM], r13d
    jne .next
    mov rdi, r15
    mov esi, r14d
    call message_peer
    cmp eax, r12d
    jne .next
    mov edx, [r15 + MS_ID]
    cmp ebp, CHAT_HISTORY
    jb .insert
    mov rax, [history]                      ; full: it has to beat the oldest kept
    cmp edx, [rax + MS_ID]
    jb .next
    push rcx
    push rdx
    lea rdi, [history]
    lea rsi, [history + 8]
    mov edx, (CHAT_HISTORY - 1) * 8
    call memmove
    pop rdx
    pop rcx
    dec ebp
.insert:
    mov eax, ebp
.shift:
    test eax, eax
    jz .place
    mov rsi, [history + rax * 8 - 8]
    cmp edx, [rsi + MS_ID]
    ja .place
    mov [history + rax * 8], rsi
    dec eax
    jmp .shift
.place:
    mov [history + rax * 8], r15
    inc ebp
.next:
    add r15, MS_SIZE
    dec ecx
    jmp .scan

.write:
    test ebp, ebp
    jz .reply
    mov rax, [history + rbp * 8 - 8]
    mov edi, r14d
    mov esi, r13d
    mov edx, r12d
    mov ecx, [rax + MS_ID]
    call mark_seen
    call db_commit
.reply:
    lea rdi, [msg_buf]
    mov esi, MSG_CHAT_HISTORY
    call wr_u8
    mov esi, r13d
    call wr_u32
    mov esi, r12d
    call wr_u32
    mov esi, ebp
    call wr_u8
    xor r15d, r15d
.row:
    cmp r15d, ebp
    jae .send
    mov rsi, [history + r15 * 8]
    call wr_message
    inc r15d
    jmp .row
.send:
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    call reply
    jmp .done
.violation:
    call kill_cur
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Tells a connection which of its user's conversations in a team have
; messages from others they haven't seen. Only the channel and current
; members count, since those are the conversations a client can open.
; edi = connection index, esi = team, edx = user
send_unread:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov [rsp], edi
    mov r12d, esi
    mov r13d, edx
    ; The newest message from someone else in each conversation.
    xor ebp, ebp                            ; conversations found
    lea rbx, [messages]
    mov r14d, [n_messages]
.message:
    test r14d, r14d
    jz .check
    cmp [rbx + MS_TEAM], r12d
    jne .next
    cmp [rbx + MS_FROM], r13d
    je .next
    mov rdi, rbx
    mov esi, r13d
    call message_peer
    cmp eax, -1
    je .next
    xor ecx, ecx
.find:
    cmp ecx, ebp
    jae .add
    cmp [unread_peer + rcx * 4], eax
    je .newest
    inc ecx
    jmp .find
.add:
    cmp ebp, UNREAD_MAX
    jae .next
    mov [unread_peer + rcx * 4], eax
    mov dword [unread_newest + rcx * 4], 0
    inc ebp
.newest:
    mov edx, [rbx + MS_ID]
    cmp edx, [unread_newest + rcx * 4]
    jbe .next
    mov [unread_newest + rcx * 4], edx
.next:
    add rbx, MS_SIZE
    dec r14d
    jmp .message

.check:
    lea rdi, [msg_buf]
    mov esi, MSG_UNREAD
    call wr_u8
    mov esi, r12d
    call wr_u32
    mov r15, rdi                            ; count goes here
    mov byte [r15], 0
    lea rbx, [r15 + 1]
    xor r14d, r14d
.conversation:
    cmp r14d, ebp
    jae .send
    mov esi, [unread_peer + r14 * 4]
    test esi, esi
    jz .seen_yet
    mov edi, r12d
    call find_member
    test rax, rax
    jz .next_conversation
.seen_yet:
    mov edi, r13d
    mov esi, r12d
    mov edx, [unread_peer + r14 * 4]
    call find_seen
    test rax, rax
    jz .unread
    mov ecx, [unread_newest + r14 * 4]
    cmp ecx, [rax + SEEN_LAST]
    jbe .next_conversation
.unread:
    mov eax, [unread_peer + r14 * 4]
    mov [rbx], eax
    add rbx, 4
    inc byte [r15]
.next_conversation:
    inc r14d
    jmp .conversation
.send:
    lea rsi, [msg_buf]
    mov rdx, rbx
    sub rdx, rsi
    mov edi, [rsp]
    call send_msg
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
