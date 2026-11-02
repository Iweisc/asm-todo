; Channels besides #general: the list the server sends, the sidebar rows that
; open them, and the dialog that makes, renames and deletes one.

%define CN_SLOT         0               ; u8, 1 to CHANNEL_SLOTS
%define CN_NAME_LEN     1
%define CN_NAME         2               ; CHANNEL_NAME_MAX bytes
%define CN_CREATOR      28
%define CN_SIZE         32
fits CN_NAME, CHANNEL_NAME_MAX, CN_CREATOR
fits CN_CREATOR, 4, CN_SIZE

%define CHANNEL_MODAL_W 440

section .rodata
text s_channels_head,   "Channels"
text s_new_channel,     "New channel"
text s_edit_channel,    "Edit channel"
text s_channel_name,    "Name"
text s_create_channel,  "Create channel"
text s_save_channel,    "Save"
text s_delete_channel,  "Delete channel"
text s_delete_channel_sure, "Delete it and its messages?"
text s_channel_hint,    "Everyone in the team can read and write in it."
text s_channel_field_hint, "e.g. design"

section .bss
alignb 4
chan_count:     resd 1
chans:          resb CHANNEL_SLOTS * CN_SIZE
chan_editing:   resd 1                  ; the slot the dialog edits, 0 for a new one
chan_armed:     resb 1                  ; Delete was clicked once
chan_open_new:  resb 1                  ; open the channel we make once the server lists it
channel_buf:    resb CHANNEL_NAME_MAX

section .text

; edi = slot -> rax = its row, or 0
find_chan:
    lea rax, [chans]
    mov ecx, [chan_count]
.loop:
    test ecx, ecx
    jz .none
    movzx edx, byte [rax + CN_SLOT]
    cmp edx, edi
    je .done
    add rax, CN_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; rdi = cursor, esi = a peer with CHANNEL_PEER set -> rdi advanced past "#name"
put_channel_name:
    mov byte [rdi], '#'
    inc rdi
    push rdi
    mov edi, esi
    and edi, ~CHANNEL_PEER
    call find_chan
    pop rdi
    test rax, rax
    jz .done
    lea rsi, [rax + CN_NAME]
    movzx edx, byte [rax + CN_NAME_LEN]
    jmp put_mem
.done:
    ret

; edi = slot -> eax = 1 if we may rename or delete it: we made it, or own the team
can_edit_chan:
    sub rsp, 8
    call find_chan
    test rax, rax
    jz .done
    mov ecx, [rax + CN_CREATOR]
    mov eax, 1
    cmp ecx, [my_id]
    je .done
    call am_owner
.done:
    add rsp, 8
    ret

; MSG_CHANNELS: the team's whole list. A conversation or dialog for one
; that's gone closes, and a channel we just made opens.
on_channels:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call rd_u32
    mov ebx, eax
    call rd_u8
    mov r12d, eax
    cmp ebx, [current_team]
    jne .skip
    cmp r12d, CHANNEL_SLOTS
    ja .bad
    xor r15d, r15d                          ; the slots we had, as bits
    lea rbx, [chans]
    mov ecx, [chan_count]
.had:
    test ecx, ecx
    jz .read
    movzx eax, byte [rbx + CN_SLOT]
    bts r15d, eax
    add rbx, CN_SIZE
    dec ecx
    jmp .had
.read:
    lea rbx, [chans]
    xor r13d, r13d
.chan:
    cmp r13d, r12d
    jae .listed
    call rd_u8
    mov [rbx + CN_SLOT], al
    test eax, eax
    jz .bad                                 ; #general isn't on the list
    cmp eax, CHANNEL_SLOTS
    ja .bad
    call rd_u32
    mov [rbx + CN_CREATOR], eax
    lea rdi, [rbx + CN_NAME_LEN]
    mov esi, CHANNEL_NAME_MAX
    call read_named_str
    add rbx, CN_SIZE
    inc r13d
    jmp .chan
.bad:
    mov byte [rd_bad], 1
.listed:
    cmp byte [rd_bad], 0
    je .count
    xor r12d, r12d                          ; a broken list shows none until the reconnect sends it again
.count:
    mov [chan_count], r12d
    call channels_changed
    cmp byte [rd_bad], 0
    jne .done
    cmp byte [chan_open_new], 0
    je .done
    ; The new one is the slot we didn't have that we made.
    lea rbx, [chans]
    mov r14d, r12d
.new:
    test r14d, r14d
    jz .done
    movzx edi, byte [rbx + CN_SLOT]
    bt r15d, edi
    jc .next_new
    mov eax, [rbx + CN_CREATOR]
    cmp eax, [my_id]
    jne .next_new
    mov byte [chan_open_new], 0
    or edi, CHANNEL_PEER
    call open_chat
    jmp .done
.next_new:
    add rbx, CN_SIZE
    dec r14d
    jmp .new
.skip:
    call rd_skip
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; The list changed. Whatever showed a deleted channel lets go of it.
channels_changed:
    sub rsp, 8
    mov byte [need_redraw], 1
    cmp byte [modal], M_CHANNEL
    jne .chat
    mov edi, [chan_editing]
    test edi, edi
    jz .chat
    call find_chan
    test rax, rax
    jnz .chat
    call close_modal
.chat:
    cmp byte [chat_open], 0
    je .done
    mov edi, [chat_peer]
    test edi, edi
    jns .done
    and edi, ~CHANNEL_PEER
    call find_chan
    test rax, rax
    jnz .done
    call close_detail
.done:
    add rsp, 8
    ret

; Opens the dialog. edi = the slot to edit, 0 to make a new channel
open_channel_dialog:
    push rbx
    mov ebx, edi
    mov byte [menu_open], 0
    mov byte [modal], M_CHANNEL
    mov [chan_editing], ebx
    mov byte [chan_armed], 0
    mov edi, F_CHANNEL
    call field_clear
    test ebx, ebx
    jz .focus
    mov edi, ebx
    call find_chan
    test rax, rax
    jz .focus
    lea rsi, [rax + CN_NAME]
    movzx edx, byte [rax + CN_NAME_LEN]
    mov edi, F_CHANNEL
    call field_set
.focus:
    mov edi, F_CHANNEL
    call set_focus
    pop rbx
    ret

; Makes or renames the channel, if the dialog has a name.
submit_channel:
    sub rsp, 8
    mov edi, F_CHANNEL
    call field_trimmed
    test edx, edx
    jz .done
    mov edi, [chan_editing]
    call sync_set_channel
    test eax, eax
    jz .done
    cmp dword [chan_editing], 0
    sete [chan_open_new]
    call close_modal
.done:
    add rsp, 8
    ret

; The first click asks, the second deletes the channel and its messages.
click_delete_channel:
    sub rsp, 8
    cmp byte [chan_armed], 0
    jne .sure
    mov byte [chan_armed], 1
    jmp .done
.sure:
    mov edi, [chan_editing]
    xor edx, edx
    call sync_set_channel
    test eax, eax
    jz .done
    call close_modal
.done:
    add rsp, 8
    ret

; edi = slot, 0 for a new channel, rsi = name, edx = length, empty to delete
; -> eax = 1 if it went out
sync_set_channel:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12, rsi
    mov r13d, edx
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_SET_CHANNEL
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    mov esi, ebx
    call wr_u8
    mov rsi, r12
    mov edx, r13d
    call wr_str
    call send_built
    mov eax, 1
.done:
    pop r13
    pop r12
    pop rbx
    ret

; The sidebar's channels: #general first, then the rest by slot, under a
; heading whose "+" makes another. edi = top -> eax = the y under them
draw_side_channels:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea ebx, [edi + 12]
    mov edi, ebx
    lea rsi, [s_channels_head]
    mov edx, s_channels_head_len
    call side_heading
    mov edi, ebx
    mov esi, A_CHANNEL_DIALOG
    xor edx, edx
    call side_plus
    add ebx, 28
    xor r12d, r12d                          ; the peer, #general first
    xor r13d, r13d                          ; the next slot to look for
.row:
    mov edi, ebx
    mov esi, r12d
    mov edx, SIDEBAR_W - 26
    call chat_side_row
    mov r14d, INK(C_TEXT, ST_BODY)
    mov eax, INK(0xffffff, ST_MEDIUM)       ; unread
    test ecx, ecx
    cmovnz r14d, eax
    lea rdi, [scratch]
    lea rsi, [s_general]
    mov edx, s_general_len
    test r12d, r12d
    jz .general
    mov esi, r12d
    call put_channel_name
    jmp .named
.general:
    call put_mem
.named:
    lea rdx, [scratch]
    mov rcx, rdi
    sub rcx, rdx
    mov edi, 44
    lea esi, [ebx + 19]
    mov r8d, r14d
    mov r9d, SIDEBAR_W - 86
    call draw_text_fit
    add ebx, 30
.next_slot:
    inc r13d
    cmp r13d, CHANNEL_SLOTS
    ja .done
    mov edi, r13d
    call find_chan
    test rax, rax
    jz .next_slot
    lea r12d, [r13d + CHANNEL_PEER]
    jmp .row
.done:
    mov eax, ebx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; "Edit channel" in a channel's header, for whoever may. edi = the X's left
; edge, esi = the header's y
draw_channel_edit_link:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13d, [chat_peer]
    test r13d, r13d
    jns .done
    and r13d, ~CHANNEL_PEER
    mov edi, r13d
    call can_edit_chan
    test eax, eax
    jz .done
    lea edi, [ebx - 10]
    lea esi, [r12d + 27]
    lea rdx, [s_edit_channel]
    mov ecx, s_edit_channel_len
    mov r8d, C_DIM
    call draw_link
    mov edi, eax
    lea esi, [r12d + 27]
    mov r8d, A_CHANNEL_DIALOG
    mov r9d, r13d
    call add_link_hit
.done:
    pop r13
    pop r12
    pop rbx
    ret

; The dialog: the name, and for an existing channel a way to delete it.
draw_channel_dialog:
    push rbx
    push r12
    push r13
    mov edi, CHANNEL_MODAL_W
    mov esi, 250
    call modal_box
    mov ebx, eax
    mov r12d, edx
    mov r13d, [chan_editing]
    lea rdx, [s_new_channel]
    mov ecx, s_new_channel_len
    lea rax, [s_edit_channel]
    mov esi, s_edit_channel_len
    test r13d, r13d
    cmovnz rdx, rax
    cmovnz ecx, esi
    lea edi, [ebx + 28]
    lea esi, [r12d + 46]
    mov r8d, INK(C_TEXT, ST_TITLE)
    call draw_text
    lea edi, [ebx + 28]
    lea esi, [r12d + 84]
    lea rdx, [s_channel_name]
    mov ecx, s_channel_name_len
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    mov edi, F_CHANNEL
    lea esi, [ebx + 28]
    lea edx, [r12d + 94]
    mov ecx, CHANNEL_MODAL_W - 56
    call draw_field_box
    lea edi, [ebx + 28]
    lea esi, [r12d + 152]
    lea rdx, [s_channel_hint]
    mov ecx, s_channel_hint_len
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_text
    lea rdx, [s_create_channel]
    mov ecx, s_create_channel_len
    lea rax, [s_save_channel]
    mov esi, s_save_channel_len
    test r13d, r13d
    cmovnz rdx, rax
    cmovnz ecx, esi
    lea edi, [ebx + 28]
    lea esi, [r12d + 192]
    mov r8d, A_SAVE_CHANNEL
    mov r9d, BTN_PRIMARY
    call draw_button
    test r13d, r13d
    jz .done
    lea rdx, [s_delete_channel]
    mov ecx, s_delete_channel_len
    lea rax, [s_delete_channel_sure]
    mov esi, s_delete_channel_sure_len
    cmp byte [chan_armed], 0
    cmovne rdx, rax
    cmovne ecx, esi
    mov rdi, rdx
    push rdx
    push rcx
    mov esi, ecx
    mov edx, ST_MEDIUM
    call text_width
    pop rcx
    pop rdx
    lea edi, [ebx + CHANNEL_MODAL_W - 28 - 24]
    sub edi, eax                            ; right-aligned
    lea esi, [r12d + 192]
    mov r8d, A_DELETE_CHANNEL
    mov r9d, BTN_DANGER
    cmp byte [chan_armed], 0
    jne .delete
    xor r9d, r9d
.delete:
    call draw_button
.done:
    pop r13
    pop r12
    pop rbx
    ret
