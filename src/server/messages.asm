; Team chat: every team has #general and the channels its members make
; (channels.asm), and its members can message each other directly.
;
; Messages aren't part of the issue sync. They don't bump the team's seq,
; and they go only to the connections viewing the team whose user may read
; them. A conversation is named from one side by its peer: 0 for #general,
; CHANNEL_PEER + slot for another channel, or the other member. Opening one fetches its newest messages.
; Seen marks remember the newest message each member has seen in each
; conversation, so unread ones still show after a restart.

%define UNREAD_MAX      128

section .bss
alignb 8
history:        resq CHAT_HISTORY           ; rows h_open_chat sends, oldest first
unread_peer:    resd UNREAD_MAX
unread_newest:  resd UNREAD_MAX
unread_mention: resd UNREAD_MAX         ; the newest message mentioning them, then whether it is unseen
deleted_heads:  resb MAX_MESSAGES * 16      ; the first 16 bytes of the messages a ban deleted

section .rodata
text e_no_message,      "that message is gone"
text e_message_rights,  "that's someone else's message"
text e_message_text,    "messages are 1-500 characters"
text e_blocked,         "AutoMod blocked that, it has a word this team doesn't allow"

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
    movzx esi, byte [rbx + MS_EDITED]
    call wr_u8
    mov esi, IMAGE_ON_MESSAGE
    mov edx, [rbx + MS_ID]
    call wr_image_ref
    pop rbx
    ret

; Which of a user's conversations a message is in. The team isn't checked.
; rdi = message row, esi = user -> eax = the peer, or -1 if it isn't theirs
message_peer:
    mov eax, [rdi + MS_TO]
    test eax, eax
    jz .done                                ; #general
    js .done                                ; another channel
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

; Whether a connection gets a message, which in a channel takes seeing it.
; edi = connection index, rsi = message row
; -> eax = the peer it's in for that connection, or -1, rdx = the connection
message_target:
    push rbx
    push r12
    push r13
    mov r12, rsi
    call conn_addr
    mov rbx, rax
    mov eax, -1
    cmp byte [rbx + C_STATE], ST_OPEN
    jne .done
    mov esi, [rbx + C_USER]
    test esi, esi
    jz .done
    mov ecx, [rbx + C_TEAM]
    cmp ecx, [r12 + MS_TEAM]
    jne .done
    mov rdi, r12
    call message_peer
    cmp eax, -1
    je .done
    test eax, eax
    jg .done                                ; a direct message
    mov r13d, eax
    mov edi, [r12 + MS_TEAM]
    mov esi, eax
    mov edx, [rbx + C_USER]
    call peer_visible
    test eax, eax
    mov eax, -1
    jz .done
    mov eax, r13d
.done:
    mov rdx, rbx
    pop r13
    pop r12
    pop rbx
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
    mov edi, T_MESSAGES
    mov rsi, rbx
    call drop_attached_image
    mov rdi, rbx
    mov esi, MS_SIZE
    call wipe
    mov rax, rbx
    pop rbx
    ret

; Sends a message to one of the team's channels or to one member, and to
; everyone who may read it. A message arriving in a conversation someone has
; open counts as seen by them. channel_post has the rules for channels.
op_message:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov rax, [op_team]
    mov r12d, [rax + TEAM_ID]
    mov r13d, [op_issue]                    ; who it goes to
    mov edi, r12d
    mov esi, r13d
    mov edx, MESSAGE_MAX
    call op_attachment
    test eax, eax
    jz .invalid
    mov r14, rdx                            ; its image
    test r13d, r13d
    jz .post
    js .channel
    mov edi, r12d
    mov esi, r13d
    call find_member
    test rax, rax
    jz .invalid
    jmp .store
.channel:
    mov edi, r12d
    mov esi, r13d
    call find_channel_peer
    test rax, rax
    jz .invalid
.post:
    mov edi, r12d
    mov esi, r13d
    call channel_post
    test eax, eax
    jnz .done
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
    mov rdi, r14
    mov esi, IMAGE_ON_MESSAGE
    mov edx, [rbx + MS_ID]
    call attach_image

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
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    mov rdi, rbx
    call send_to_readers
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
    mov edi, r13d
    mov esi, r12d
    mov edx, r14d
    call peer_visible
    test eax, eax
    jz .reply                               ; a channel they can't see is empty to them
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

; The newest message from someone else in each of a user's conversations in
; a team, in unread_peer and unread_newest, and in unread_mention the newest
; in a channel that mentions them. edi = team, esi = user -> eax = conversations
gather_unread:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov r12d, edi
    mov r13d, esi
    mov edi, esi
    call find_user
    xor r15d, r15d                          ; their name's length
    test rax, rax
    jz .named
    movzx r15d, byte [rax + USER_NAME_LEN]
    lea rax, [rax + USER_NAME]
.named:
    mov [rsp], rax
    xor ebp, ebp                            ; conversations found
    lea rbx, [messages]
    mov r14d, [n_messages]
.message:
    test r14d, r14d
    jz .done
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
    mov dword [unread_mention + rcx * 4], 0
    inc ebp
.newest:
    mov edx, [rbx + MS_ID]
    cmp edx, [unread_newest + rcx * 4]
    jbe .mention
    mov [unread_newest + rcx * 4], edx
.mention:
    ; Only in channels. Everything in a direct message is for them anyway.
    test eax, eax
    jg .next
    test r15d, r15d
    jz .next
    cmp edx, [unread_mention + rcx * 4]
    jbe .next
    mov [rsp + 8], ecx
    lea rdi, [rbx + MS_TEXT]
    movzx esi, word [rbx + MS_LEN]
    mov rdx, [rsp]
    mov ecx, r15d
    call text_mentions
    test eax, eax
    jz .next
    mov ecx, [rsp + 8]
    mov edx, [rbx + MS_ID]
    mov [unread_mention + rcx * 4], edx
.next:
    add rbx, MS_SIZE
    dec r14d
    jmp .message
.done:
    mov eax, ebp
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Tells a connection which of its user's conversations in a team have
; messages from others they haven't seen, and which of those channels
; mention them in one. Only channels that still exist and they can see, and
; current members count, since those are the conversations a client can open.
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
    mov edi, esi
    mov esi, edx
    call gather_unread
    mov ebp, eax

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
    jae .mentions
    mov esi, [unread_peer + r14 * 4]
    test esi, esi
    jle .channel
    mov edi, r12d
    call find_member
    test rax, rax
    jz .gone
    jmp .seen_yet
.channel:
    mov edi, r12d
    mov edx, r13d
    call peer_visible
    test eax, eax
    jz .gone
.seen_yet:
    mov edi, r13d
    mov esi, r12d
    mov edx, [unread_peer + r14 * 4]
    call find_seen
    xor ecx, ecx
    test rax, rax
    jz .seen_up_to
    mov ecx, [rax + SEEN_LAST]
.seen_up_to:
    ; A mention counts while it's unseen. From here unread_mention says whether it is.
    xor eax, eax
    cmp [unread_mention + r14 * 4], ecx
    seta al
    mov [unread_mention + r14 * 4], eax
    cmp [unread_newest + r14 * 4], ecx
    jbe .next_conversation
    mov eax, [unread_peer + r14 * 4]
    mov [rbx], eax
    add rbx, 4
    inc byte [r15]
    jmp .next_conversation
.gone:
    mov dword [unread_mention + r14 * 4], 0
.next_conversation:
    inc r14d
    jmp .conversation
.mentions:
    mov r15, rbx                            ; their count goes here
    mov byte [r15], 0
    inc rbx
    xor r14d, r14d
.mention:
    cmp r14d, ebp
    jae .send
    cmp dword [unread_mention + r14 * 4], 0
    je .next_mention
    mov eax, [unread_peer + r14 * 4]
    mov [rbx], eax
    add rbx, 4
    inc byte [r15]
.next_mention:
    inc r14d
    jmp .mention
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

; Sends a built message to every connection that may read a stored one.
; rdi = the stored message's row, rsi = built message, edx = length
send_to_readers:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    xor ebx, ebx
.conn:
    mov edi, ebx
    mov rsi, r12
    call message_target
    cmp eax, -1
    je .next
    mov edi, ebx
    mov rsi, r13
    mov edx, r14d
    call send_msg
.next:
    inc ebx
    cmp ebx, MAX_CONN
    jb .conn
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; edi = team, esi = message id -> rax = its row, or 0
find_message:
    lea rax, [messages]
    mov ecx, [n_messages]
    test esi, esi
    jz .none
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + MS_ID], esi
    jne .next
    cmp [rax + MS_TEAM], edi
    je .done
.next:
    add rax, MS_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; Checks cur is still in the team, not timed out, and the message is there. edi = team, esi = message
; -> rax = the message's row and rdx = cur's member row, or rax = 0 when the error has been sent
editable_message:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    call writable_member
    test rax, rax
    jz .done
    mov rdx, rax
    push rdx
    push rdx
    mov edi, ebx
    mov esi, r12d
    call find_message
    pop rdx
    pop rdx
    test rax, rax
    jz .gone
    jmp .done
.gone:
    lea rsi, [e_no_message]
    mov edx, e_no_message_len
.error:
    call send_error
    xor eax, eax
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; MSG_EDIT_MESSAGE: its author changes a message's text. Whoever can read it
; gets the new one.
h_edit_message:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    call rd_u32
    mov r12d, eax                           ; team
    call rd_u32
    mov ebx, eax                            ; message
    call rd_str16
    mov r13, rax
    mov r14d, edx
    call rd_ok
    test eax, eax
    jz .violation
    mov edi, r12d
    mov esi, ebx
    call editable_message
    test rax, rax
    jz .done
    mov rbx, rax
    mov rax, [cur]
    mov eax, [rax + C_USER]
    cmp [rbx + MS_FROM], eax
    jne .rights
    test r14d, r14d
    jz .bad_text
    mov rsi, r13
    mov edx, r14d
    mov ecx, MESSAGE_MAX
    call valid_body
    test eax, eax
    jz .bad_text
    cmp dword [rbx + MS_TO], 0
    jg .checked                             ; AutoMod leaves direct messages alone
    mov edi, r12d
    mov esi, [rbx + MS_TO]
    mov rdx, r13
    mov ecx, r14d
    call automod_check
    test eax, eax
    jnz .blocked
.checked:
    lea rdi, [rbx + MS_TEXT]                ; the old text goes, not just its length
    mov esi, MESSAGE_MAX
    call wipe
    mov [rbx + MS_LEN], r14w
    lea rdi, [rbx + MS_TEXT]
    mov rsi, r13
    mov ecx, r14d
    rep movsb
    mov byte [rbx + MS_EDITED], 1
    mov edi, T_MESSAGES
    mov rsi, rbx
    call db_touch
    call db_commit
    lea rdi, [msg_buf]
    mov esi, MSG_CHAT_EDITED
    call wr_u8
    mov esi, r12d
    call wr_u32
    mov rsi, rbx
    call wr_message
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    mov rdi, rbx
    call send_to_readers
    jmp .done
.violation:
    call kill_cur
    jmp .done
.rights:
    lea rsi, [e_message_rights]
    mov edx, e_message_rights_len
    jmp .error
.bad_text:
    lea rsi, [e_message_text]
    mov edx, e_message_text_len
    jmp .error
.blocked:
    lea rsi, [e_blocked]
    mov edx, e_blocked_len
.error:
    call send_error
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; MSG_DELETE_MESSAGE: its author deletes a message, or someone with
; CH_MANAGE one in that channel, which goes in the audit log. Nobody else
; reads others' direct messages, so not those.
h_delete_message:
    push rbx
    push r12
    sub rsp, 24                             ; the row's head, to address readers after it's freed
    call rd_u32
    mov r12d, eax                           ; team
    call rd_u32
    mov ebx, eax                            ; message
    call rd_ok
    test eax, eax
    jz .violation
    mov edi, r12d
    mov esi, ebx
    call editable_message
    test rax, rax
    jz .done
    mov rbx, rax
    mov byte [rsp + 16], 0                  ; 1 when it's someone else's
    mov rax, [cur]
    mov eax, [rax + C_USER]
    cmp [rbx + MS_FROM], eax
    je .allowed
    mov esi, [rbx + MS_TO]
    test esi, esi
    jg .rights                              ; a direct message
    and esi, ~CHANNEL_PEER
    mov edi, r12d
    call channel_access
    test eax, CH_MANAGE
    jz .rights
    mov byte [rsp + 16], 1
    mov edi, r12d
    mov esi, AU_DELETE_MESSAGE
    mov edx, [rbx + MS_FROM]
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call audit_add
.allowed:
    mov rax, [rbx]
    mov [rsp], rax
    mov rax, [rbx + 8]
    mov [rsp + 8], rax
    mov edi, T_MESSAGES
    mov rsi, rbx
    call free_row
    call db_commit
    lea rdi, [msg_buf]
    mov esi, MSG_CHAT_DELETED
    call wr_u8
    mov esi, r12d
    call wr_u32
    mov esi, [rsp + MS_ID]
    call wr_u32
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    mov rdi, rsp
    call send_to_readers
    cmp byte [rsp + 16], 0
    je .done
    mov edi, r12d
    mov esi, -1
    call send_moderation
    jmp .done
.violation:
    call kill_cur
    jmp .done
.rights:
    lea rsi, [e_message_rights]
    mov edx, e_message_rights_len
    call send_error
.done:
    add rsp, 24
    pop r12
    pop rbx
    ret

; Deletes a user's channel messages in a team from the last seconds. The rows
; are touched, not committed, and their heads kept for announce_deleted.
; edi = team, esi = user, edx = seconds -> eax = how many
delete_recent_messages:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov r15d, edx
    xor ebp, ebp
    test edx, edx
    jz .done
    call now_unix
    sub eax, r15d
    mov r15d, eax                           ; the oldest that goes
    lea rbx, [messages]
    mov r14d, [n_messages]
.row:
    test r14d, r14d
    jz .done
    cmp [rbx + MS_TEAM], r12d
    jne .next
    cmp [rbx + MS_FROM], r13d
    jne .next
    cmp dword [rbx + MS_TO], 0
    jg .next                                ; a direct message
    cmp [rbx + MS_CREATED], r15d
    jb .next
    mov eax, ebp
    shl eax, 4
    mov rcx, [rbx]
    mov [deleted_heads + rax], rcx
    mov rcx, [rbx + 8]
    mov [deleted_heads + rax + 8], rcx
    inc ebp
    mov edi, T_MESSAGES
    mov rsi, rbx
    call free_row
.next:
    add rbx, MS_SIZE
    dec r14d
    jmp .row
.done:
    mov eax, ebp
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Tells whoever could read the messages delete_recent_messages kept the
; heads of that they're gone. edi = how many
announce_deleted:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, edi
    xor ebx, ebx
.head:
    cmp ebx, r12d
    jae .done
    lea rdi, [msg_buf]
    mov esi, MSG_CHAT_DELETED
    call wr_u8
    mov eax, ebx
    shl eax, 4
    mov esi, [deleted_heads + rax + MS_TEAM]
    call wr_u32
    mov eax, ebx
    shl eax, 4
    mov esi, [deleted_heads + rax + MS_ID]
    call wr_u32
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    mov eax, ebx
    shl eax, 4
    lea rdi, [deleted_heads + rax]
    call send_to_readers
    inc ebx
    jmp .head
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret
