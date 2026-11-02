; Channels besides #general. Any member makes one, and its maker or anyone
; with PERM_MANAGE_CHANNELS renames or deletes it and changes its settings.
; Deleting one deletes its messages, seen marks and settings too, so a slot
; can be reused without the old conversation showing up in the new channel.
;
; A channel's settings are its slowmode and its overrides, which allow or
; deny CH_VIEW, CH_SEND and CH_MANAGE per role on top of what the team's
; permissions give: @everyone's override first, then every role the member
; has together, denials before allowances. Admins skip them.

section .rodata
text e_channel_name,    "channel names are 1-24 printable characters"
text e_channels_full,   "that team has as many channels as it can have"
text e_no_channel,      "that channel doesn't exist anymore"
text e_channel_rights,  "only the channel's maker or someone who manages channels can change it"
text e_channels_busy,   "the server has no room for that channel's settings right now"

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

; edi = team, esi = slot -> rax = the channel's settings row, or 0 if it has none
find_chancfg:
    lea rax, [chancfg]
    mov ecx, [n_chancfg]
    test edi, edi
    jz .none
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + CC_TEAM], edi
    jne .next
    movzx edx, byte [rax + CC_SLOT]
    cmp edx, esi
    je .done
.next:
    add rax, CC_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; edi = team, esi = slot (0 for #general), rdx = member row
; -> eax = the CH_VIEW, CH_SEND and CH_MANAGE they have in that channel
channel_access:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov r14, rdx
    mov rdi, rdx
    call member_perms
    mov ebx, CH_VIEW | CH_SEND | CH_MANAGE
    test eax, PERM_ADMIN
    jnz .done
    xor ebx, ebx
    test eax, PERM_VIEW_CHANNELS
    jz .send
    or ebx, CH_VIEW
.send:
    test eax, PERM_SEND_MESSAGES
    jz .manage
    or ebx, CH_SEND
.manage:
    test eax, PERM_MANAGE_MESSAGES
    jz .overrides
    or ebx, CH_MANAGE
.overrides:
    mov edi, r12d
    mov esi, r13d
    call find_chancfg
    test rax, rax
    jz .view
    movzx ecx, byte [rax + CC_OVERRIDES]
    call .apply
    movzx r8d, word [r14 + MEM_ROLES]
    xor ecx, ecx                            ; every role's together
    mov edx, 1
.role:
    bt r8d, edx
    jnc .next_role
    or cl, [rax + CC_OVERRIDES + rdx]
.next_role:
    inc edx
    cmp edx, ROLE_SLOTS
    jbe .role
    call .apply
.view:
    test ebx, CH_VIEW
    jnz .done
    xor ebx, ebx                            ; nothing in a channel they can't see
.done:
    mov eax, ebx
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; ecx = an override, applied to ebx
.apply:
    mov edx, ecx
    shr edx, 4
    not edx
    and ebx, edx
    and ecx, 0x0f
    or ebx, ecx
    ret

; rdi = member row, rsi = channel row, 0 for #general -> eax = 1 if they can
; rename it and change its settings
channel_editable:
    push rbx
    mov rbx, rsi
    push rdi
    call member_perms
    pop rdi
    mov ecx, eax
    mov eax, 1
    test ecx, PERM_MANAGE_CHANNELS
    jnz .done
    xor eax, eax
    test rbx, rbx
    jz .done
    mov ecx, [rdi + MEM_USER]
    cmp [rbx + CHN_CREATOR], ecx
    sete al
.done:
    pop rbx
    ret

; edi = team, esi = peer, edx = user -> eax = 1 if it's a member, or a channel
; that still exists and the user, a member, can see
peer_visible:
    push rbx
    push r12
    push r13
    mov eax, 1
    test esi, esi
    jg .done
    mov r12d, edi
    mov r13d, esi
    and r13d, ~CHANNEL_PEER
    mov ebx, edx
    test r13d, r13d
    jz .member
    mov esi, r13d
    call find_channel
    test rax, rax
    jz .no
.member:
    mov edi, r12d
    mov esi, ebx
    call find_member
    test rax, rax
    jz .no
    mov edi, r12d
    mov esi, r13d
    mov rdx, rax
    call channel_access
    and eax, CH_VIEW
    jmp .done
.no:
    xor eax, eax
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Writes a channel's settings: u16 slowmode and its overrides.
; rdi = cursor, esi = team, edx = slot -> rdi advanced
wr_chancfg:
    push rbx
    mov rbx, rdi
    mov edi, esi
    mov esi, edx
    call find_chancfg
    mov rdi, rbx
    xor esi, esi
    test rax, rax
    jz .none
    mov rbx, rax
    movzx esi, word [rbx + CC_SLOWMODE]
    call wr_u16
    lea rsi, [rbx + CC_OVERRIDES]
    mov ecx, ROLE_SLOTS + 1
    rep movsb
    pop rbx
    ret
.none:
    call wr_u16
    xor eax, eax
    mov ecx, ROLE_SLOTS + 1
    rep stosb
    pop rbx
    ret

; Builds MSG_CHANNELS for one member in msg_buf: the team's channels they
; can see, #general first. edi = team, rsi = member row -> rdx = its length
build_channels:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24                             ; their access, the channel, can they edit it
    mov r12d, edi
    mov r13, rsi
    lea rdi, [msg_buf]
    mov esi, MSG_CHANNELS
    call wr_u8
    mov esi, r12d
    call wr_u32
    mov r14, rdi                            ; the count goes here
    lea rbp, [rdi + 1]
    xor ebx, ebx
    xor r15d, r15d
.slot:
    mov edi, r12d
    mov esi, r15d
    mov rdx, r13
    call channel_access
    test eax, CH_VIEW
    jz .next
    mov [rsp], eax
    xor eax, eax
    test r15d, r15d
    jz .found
    mov edi, r12d
    mov esi, r15d
    call find_channel
    test rax, rax
    jz .next
.found:
    mov [rsp + 8], rax
    mov rdi, r13
    mov rsi, rax
    call channel_editable
    test eax, eax
    jz .write
    or dword [rsp], CH_EDIT
.write:
    mov rdi, rbp
    mov esi, r15d
    call wr_u8
    mov rax, [rsp + 8]
    xor esi, esi
    xor edx, edx
    test rax, rax
    jz .general
    mov esi, [rax + CHN_CREATOR]
    call wr_u32
    mov rax, [rsp + 8]
    lea rsi, [rax + CHN_NAME]
    movzx edx, byte [rax + CHN_NAME_LEN]
    call wr_str
    jmp .settings
.general:
    call wr_u32
    xor edx, edx
    call wr_str
.settings:
    mov esi, [rsp]
    call wr_u8
    mov esi, r12d
    mov edx, r15d
    call wr_chancfg
    mov rbp, rdi
    inc ebx
.next:
    inc r15d
    cmp r15d, CHANNEL_SLOTS
    jbe .slot
    mov [r14], bl
    lea rax, [msg_buf]
    mov rdx, rbp
    sub rdx, rax
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Sends a team's channels to one connection viewing it. edi = connection index, esi = team
send_channels:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    call viewing_member
    test rax, rax
    jz .done
    mov edi, r12d
    mov rsi, rax
    call build_channels
    mov edi, ebx
    lea rsi, [msg_buf]
    call send_msg
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; Every connection viewing a team gets the channels its user can see. edi = team
send_channels_all:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, edi
    xor ebx, ebx
.conn:
    mov edi, ebx
    mov esi, r12d
    call send_channels
    inc ebx
    cmp ebx, MAX_CONN
    jb .conn
    add rsp, 8
    pop r12
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
; viewing the team gets their new list.
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
    call writable_member
    test rax, rax
    jz .done
    mov rbx, rax                            ; cur's member row
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
    push rax
    push rax
    mov rdi, rbx
    mov rsi, rax
    call channel_editable
    test eax, eax
    pop rax
    pop rax
    jz .rights
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
    mov edi, r12d
    mov esi, r13d
    call find_chancfg
    test rax, rax
    jz .commit
    mov edi, T_CHANCFG
    mov rsi, rax
    call free_row
.commit:
    call db_commit
    mov edi, r12d
    call send_channels_all
    jmp .done
.violation:
    call kill_cur
    jmp .done
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

; edi = team, esi = user, edx = peer -> eax = when they last posted in that
; conversation, 0 if their messages there are gone
newest_post:
    lea rcx, [messages]
    mov r8d, [n_messages]
    xor eax, eax
.row:
    test r8d, r8d
    jz .done
    cmp [rcx + MS_TEAM], edi
    jne .next
    cmp [rcx + MS_FROM], esi
    jne .next
    cmp [rcx + MS_TO], edx
    jne .next
    mov r9d, [rcx + MS_CREATED]
    cmp r9d, eax
    cmova eax, r9d
.next:
    add rcx, MS_SIZE
    dec r8d
    jmp .row
.done:
    ret

; Checks op_user may post op_body in a channel: they need CH_SEND there, and
; slowmode and AutoMod have to let it through. CH_MANAGE and
; PERM_MANAGE_CHANNELS skip slowmode. edi = team, esi = the channel's peer
; -> eax = ACK status
channel_post:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov esi, [op_user]
    call find_member
    mov rbx, rax
    mov edi, r12d
    mov esi, r13d
    and esi, ~CHANNEL_PEER
    mov rdx, rbx
    call channel_access
    test eax, CH_SEND
    jz .forbidden
    test eax, CH_MANAGE
    jnz .automod
    mov edi, r12d
    mov esi, r13d
    and esi, ~CHANNEL_PEER
    call find_chancfg
    test rax, rax
    jz .automod
    movzx r14d, word [rax + CC_SLOWMODE]
    test r14d, r14d
    jz .automod
    mov rdi, rbx
    call member_perms
    test eax, PERM_MANAGE_CHANNELS
    jnz .automod
    mov edi, r12d
    mov esi, [op_user]
    mov edx, r13d
    call newest_post
    test eax, eax
    jz .automod
    add r14d, eax                           ; when they can post again
    call now_unix
    cmp eax, r14d
    jb .slow
.automod:
    mov edi, r12d
    mov esi, r13d
    mov rdx, [op_body]
    mov ecx, [op_body_len]
    call automod_check
    test eax, eax
    jnz .blocked
    xor eax, eax
    jmp .done
.forbidden:
    mov eax, ACK_FORBIDDEN
    jmp .done
.slow:
    mov eax, ACK_SLOWMODE
    jmp .done
.blocked:
    mov eax, ACK_BLOCKED
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rsi = ROLE_SLOTS + 1 overrides -> eax = 1 if each only has CH_VIEW, CH_SEND
; and CH_MANAGE, none both allowed and denied
valid_overrides:
    xor ecx, ecx
.byte:
    movzx edx, byte [rsi + rcx]
    test edx, 0x88
    jnz .no
    mov eax, edx
    shr eax, 4
    test eax, edx
    jnz .no
    inc ecx
    cmp ecx, ROLE_SLOTS
    jbe .byte
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; Writes a channel's settings, and drops the row once they're back to
; nothing. The row is touched, not committed. edi = team, esi = slot,
; edx = slowmode, rcx = overrides -> eax = 0 if the table had no room
set_chancfg:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov r14, rcx
    mov ebx, edx
    call find_chancfg
    test rax, rax
    jnz .have
    mov edi, T_CHANCFG
    call alloc_row
    test rax, rax
    jz .done
    mov [rax + CC_TEAM], r12d
    mov [rax + CC_SLOT], r13b
.have:
    mov [rax + CC_SLOWMODE], bx
    lea rdi, [rax + CC_OVERRIDES]
    mov rsi, r14
    mov ecx, ROLE_SLOTS + 1
    rep movsb
    mov rsi, rax
    mov edi, T_CHANCFG
    test ebx, ebx
    jnz .keep
    lea rdi, [rsi + CC_OVERRIDES]
    xor eax, eax
    mov ecx, ROLE_SLOTS + 1
    repe scasb
    mov edi, T_CHANCFG
    jne .keep
    call free_row
    jmp .ok
.keep:
    call db_touch
.ok:
    mov eax, 1
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; MSG_CHANNEL_SETTINGS: a channel's slowmode and overrides.
h_channel_settings:
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
    mov r13d, eax                           ; slot
    call rd_u16
    mov r14d, eax                           ; slowmode
    mov edi, ROLE_SLOTS + 1
    call rd_bytes
    mov r15, rax                            ; overrides
    call rd_ok
    test eax, eax
    jz .violation
    cmp r13d, CHANNEL_SLOTS
    ja .violation
    cmp r14d, SLOWMODE_MAX
    ja .violation
    mov rsi, r15
    call valid_overrides
    test eax, eax
    jz .violation
    mov edi, r12d
    call writable_member
    test rax, rax
    jz .done
    mov rbx, rax
    xor ebp, ebp                            ; the channel's row, none for #general
    test r13d, r13d
    jz .found
    mov edi, r12d
    mov esi, r13d
    call find_channel
    test rax, rax
    jz .no_channel
    mov rbp, rax
.found:
    mov rdi, rbx
    mov rsi, rbp
    call channel_editable
    test eax, eax
    jz .rights
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov rcx, r15
    call set_chancfg
    test eax, eax
    jz .busy
    xor r8d, r8d
    xor r9d, r9d
    test rbp, rbp
    jz .record
    lea r8, [rbp + CHN_NAME]
    movzx r9d, byte [rbp + CHN_NAME_LEN]
.record:
    mov edi, r12d
    mov esi, AU_CHANNEL
    xor edx, edx
    mov ecx, r13d
    call audit_add
    call db_commit
    mov edi, r12d
    call send_channels_all
    mov edi, r12d
    mov esi, -1
    call send_moderation
    jmp .done
.violation:
    call kill_cur
    jmp .done
.no_channel:
    lea rsi, [e_no_channel]
    mov edx, e_no_channel_len
    jmp .error
.rights:
    lea rsi, [e_channel_rights]
    mov edx, e_channel_rights_len
    jmp .error
.busy:
    lea rsi, [e_channels_busy]
    mov edx, e_channels_busy_len
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
