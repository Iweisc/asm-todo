; Channels besides #general. Any member makes one, and its maker or a team
; owner renames or deletes it. Deleting one deletes its messages and seen
; marks too, so a slot can be reused without the old conversation showing
; up in the new channel.

section .rodata
text e_channel_name,    "channel names are 1-24 printable characters"
text e_channels_full,   "that team has as many channels as it can have"
text e_no_channel,      "that channel doesn't exist anymore"
text e_channel_rights,  "only the channel's maker or a team owner can change it"

section .text

; edi = team, esi = slot -> rax = its row, or 0
find_channel:
    lea rax, [channels]
    mov ecx, [n_channels]
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + CHN_TEAM], edi
    jne .next
    movzx edx, byte [rax + CHN_SLOT]
    cmp edx, esi
    je .done
.next:
    add rax, CHN_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; edi = team, esi = a peer with CHANNEL_PEER set -> rax = the channel's row, or 0
find_channel_peer:
    and esi, ~CHANNEL_PEER
    jmp find_channel

; edi = team -> eax = its lowest free slot, or 0 if it has them all
free_channel_slot:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, 1
.slot:
    mov edi, ebx
    mov esi, r12d
    call find_channel
    test rax, rax
    jz .found
    inc r12d
    cmp r12d, CHANNEL_SLOTS
    jbe .slot
    xor r12d, r12d
.found:
    mov eax, r12d
    add rsp, 8
    pop r12
    pop rbx
    ret

; Builds MSG_CHANNELS for a team in msg_buf. edi = team -> rdx = its length
build_channels:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12d, edi
    lea rdi, [msg_buf]
    mov esi, MSG_CHANNELS
    call wr_u8
    mov esi, r12d
    call wr_u32
    mov r14, rdi                            ; the count goes here
    inc rdi
    xor r13d, r13d
    lea rbx, [channels]
    mov eax, [n_channels]
    mov [rsp], eax
.row:
    cmp dword [rsp], 0
    je .counted
    cmp [rbx + CHN_TEAM], r12d
    jne .next
    movzx esi, byte [rbx + CHN_SLOT]
    call wr_u8
    mov esi, [rbx + CHN_CREATOR]
    call wr_u32
    lea rsi, [rbx + CHN_NAME]
    movzx edx, byte [rbx + CHN_NAME_LEN]
    call wr_str
    inc r13d
.next:
    add rbx, CHN_SIZE
    dec dword [rsp]
    jmp .row
.counted:
    mov [r14], r13b
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Sends a team's channels to one connection. edi = connection index, esi = team
send_channels:
    push rbx
    mov ebx, edi
    mov edi, esi
    call build_channels
    mov edi, ebx
    lea rsi, [msg_buf]
    call send_msg
    pop rbx
    ret

; Deletes a conversation's messages and seen marks, and closes it for whoever
; has it open. The rows are touched, not committed. edi = team, esi = peer
forget_conversation:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov r13d, esi
    lea rbx, [messages]
.message:
    imul eax, [n_messages], MS_SIZE
    lea rax, [messages + rax]
    cmp rbx, rax
    jae .seen
    cmp [rbx + MS_TEAM], r12d
    jne .next_message
    cmp [rbx + MS_TO], r13d
    jne .next_message
    mov edi, T_MESSAGES
    mov rsi, rbx
    call free_row
.next_message:
    add rbx, MS_SIZE
    jmp .message
.seen:
    lea rbx, [seen]
.mark:
    imul eax, [n_seen], SEEN_SIZE
    lea rax, [seen + rax]
    cmp rbx, rax
    jae .conns
    cmp [rbx + SEEN_TEAM], r12d
    jne .next_mark
    cmp [rbx + SEEN_PEER], r13d
    jne .next_mark
    mov edi, T_SEEN
    mov rsi, rbx
    call free_row
.next_mark:
    add rbx, SEEN_SIZE
    jmp .mark
.conns:
    xor ebx, ebx
.conn:
    mov edi, ebx
    call conn_addr
    cmp [rax + C_TEAM], r12d
    jne .next_conn
    cmp [rax + C_CHAT], r13d
    jne .next_conn
    and byte [rax + C_FLAGS], ~F_CHAT
.next_conn:
    inc ebx
    cmp ebx, MAX_CONN
    jb .conn
    pop r13
    pop r12
    pop rbx
    ret

; MSG_SET_CHANNEL: makes, renames or deletes a channel, then everyone
; viewing the team gets the new list.
h_set_channel:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    call rd_u32
    mov r12d, eax                           ; team
    call rd_u8
    mov r13d, eax                           ; slot, 0 for a new one
    call rd_str
    mov r14, rax
    mov r15d, edx                           ; the name, empty to delete
    call rd_ok
    test eax, eax
    jz .violation
    cmp r13d, CHANNEL_SLOTS
    ja .violation
    mov rax, [cur]
    mov ebp, [rax + C_USER]
    mov edi, r12d
    mov esi, ebp
    call find_member
    test rax, rax
    jz .not_member
    mov ebx, [rax + MEM_ROLE]
    test r15d, r15d
    jz .existing
    mov rsi, r14
    mov edx, r15d
    mov ecx, CHANNEL_NAME_MAX
    call valid_text
    test eax, eax
    jz .bad_name
    test r13d, r13d
    jnz .existing
    mov edi, r12d
    call free_channel_slot
    test eax, eax
    jz .full
    mov r13d, eax
    mov edi, T_CHANNELS
    call alloc_row
    test rax, rax
    jz .full
    mov [rax + CHN_TEAM], r12d
    mov [rax + CHN_CREATOR], ebp
    mov [rax + CHN_SLOT], r13b
    jmp .name
.existing:
    test r13d, r13d
    jz .violation                           ; deleting nothing
    mov edi, r12d
    mov esi, r13d
    call find_channel
    test rax, rax
    jz .no_channel
    cmp [rax + CHN_CREATOR], ebp
    je .allowed
    cmp ebx, ROLE_OWNER
    jne .rights
.allowed:
    test r15d, r15d
    jz .delete
.name:
    mov rbx, rax
    mov [rbx + CHN_NAME_LEN], r15b
    lea rdi, [rbx + CHN_NAME]
    mov rsi, r14
    mov ecx, r15d
    rep movsb
    mov edi, T_CHANNELS
    mov rsi, rbx
    call db_touch
    jmp .commit
.delete:
    mov edi, T_CHANNELS
    mov rsi, rax
    call free_row
    mov edi, r12d
    lea esi, [r13d + CHANNEL_PEER]
    call forget_conversation
.commit:
    call db_commit
    mov edi, r12d
    call build_channels
    mov edi, r12d
    lea rsi, [msg_buf]
    call broadcast_team
    jmp .done
.violation:
    call kill_cur
    jmp .done
.not_member:
    lea rsi, [e_not_member]
    mov edx, e_not_member_len
    jmp .error
.bad_name:
    lea rsi, [e_channel_name]
    mov edx, e_channel_name_len
    jmp .error
.full:
    lea rsi, [e_channels_full]
    mov edx, e_channels_full_len
    jmp .error
.no_channel:
    lea rsi, [e_no_channel]
    mov edx, e_no_channel_len
    jmp .error
.rights:
    lea rsi, [e_channel_rights]
    mov edx, e_channel_rights_len
.error:
    call send_error
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
