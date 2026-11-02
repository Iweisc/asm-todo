; Channels: the list the server sends of the ones we can see, #general
; among them, the sidebar rows that open them, and the dialog that makes,
; renames and deletes one and sets its slowmode and overrides.

%define CN_SLOT         0               ; u8, 0 for #general, or 1 to CHANNEL_SLOTS
%define CN_NAME_LEN     1
%define CN_NAME         2               ; CHANNEL_NAME_MAX bytes, empty for #general
%define CN_ACCESS       26              ; u8, the CH_* we have there
%define CN_SLOWMODE     28              ; u16 seconds
%define CN_CREATOR      32
%define CN_OVERRIDES    36              ; ROLE_SLOTS + 1 bytes, @everyone's first
%define CN_SIZE         56
fits CN_NAME, CHANNEL_NAME_MAX, CN_ACCESS
fits CN_ACCESS, 1, CN_SLOWMODE
fits CN_SLOWMODE, 2, CN_CREATOR
fits CN_CREATOR, 4, CN_OVERRIDES
fits CN_OVERRIDES, ROLE_SLOTS + 1, CN_SIZE

%define CHANNEL_MODAL_W 460
%define GRID_ROW_H      28              ; a role's overrides in the dialog
%define GRID_X          220             ; where the overrides' columns start
%define GRID_COL_W      74

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
text s_slowmode_label,  "Slowmode"
text s_overrides_label, "Permissions"
text s_col_view,        "View"
text s_col_send,        "Send"
text s_col_manage,      "Manage"
text s_inherit,         "Default"
text s_allow,           "Allow"
text s_deny,            "Deny"
text s_grid_hint,       "Manage deletes others' messages. Default follows the team's roles."
text s_off,             "Off"
text s_5s,              "5s"
text s_10s,             "10s"
text s_30s,             "30s"
text s_1m,              "1m"
text s_5m,              "5m"
text s_15m,             "15m"
text s_1h,              "1h"
text s_cant_send,       "You don't have permission to send messages here."
text s_slowmode_on,     "Slowmode is on: one message every "

align 4
slowmode_secs:  dd 0, 5, 10, 30, 60, 300, 900, 3600
SLOWMODE_PRESETS equ ($ - slowmode_secs) / 4
align 8
slowmode_names: NAME s_off
                NAME s_5s
                NAME s_10s
                NAME s_30s
                NAME s_1m
                NAME s_5m
                NAME s_15m
                NAME s_1h
column_names:   NAME s_col_view         ; by CH_* bit number
                NAME s_col_send
                NAME s_col_manage

section .bss
alignb 4
chan_count:     resd 1
chans:          resb (CHANNEL_SLOTS + 1) * CN_SIZE
chan_editing:   resd 1                  ; the slot the dialog edits, CHAN_NEW for a new one
chan_slowmode:  resd 1                  ; the dialog's, until Save
chan_scroll:    resd 1                  ; how far the overrides are scrolled
chan_armed:     resb 1                  ; Delete was clicked once
chan_open_new:  resb 1                  ; open the channel we make once the server lists it
chan_overrides: resb ROLE_SLOTS + 1     ; the dialog's, until Save
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

; edi = slot -> eax = 1 if we may rename it and change its settings, as the server says
can_edit_chan:
    sub rsp, 8
    call find_chan
    test rax, rax
    jz .done
    movzx eax, byte [rax + CN_ACCESS]
    and eax, CH_EDIT
    shr eax, 3
.done:
    add rsp, 8
    ret

; edi = a conversation's peer -> eax = the CH_* we have in it, edx = its
; slowmode in seconds. Direct messages, and channels the list hasn't brought
; yet, let us read and write.
chan_access:
    sub rsp, 8
    mov eax, CH_VIEW | CH_SEND
    xor edx, edx
    test edi, edi
    jg .done
    and edi, ~CHANNEL_PEER
    call find_chan
    mov rcx, rax
    mov eax, CH_VIEW | CH_SEND
    xor edx, edx
    test rcx, rcx
    jz .done
    movzx eax, byte [rcx + CN_ACCESS]
    movzx edx, word [rcx + CN_SLOWMODE]
.done:
    add rsp, 8
    ret

; MSG_CHANNELS: the channels of the team we can see. A conversation or
; dialog for one that's gone closes, and a channel we just made opens.
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
    cmp r12d, CHANNEL_SLOTS + 1
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
    cmp eax, CHANNEL_SLOTS
    ja .bad
    call rd_u32
    mov [rbx + CN_CREATOR], eax
    lea rdi, [rbx + CN_NAME_LEN]
    mov esi, CHANNEL_NAME_MAX
    call read_named_str
    call rd_u8
    mov [rbx + CN_ACCESS], al
    call rd_u16
    mov [rbx + CN_SLOWMODE], ax
    mov edi, ROLE_SLOTS + 1
    call rd_bytes
    lea rdi, [rbx + CN_OVERRIDES]
    mov rsi, rax
    mov ecx, ROLE_SLOTS + 1
    rep movsb
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
    cmp edi, CHAN_NEW
    je .chat
    call find_chan
    test rax, rax
    jnz .chat
    call close_modal
.chat:
    cmp byte [chat_open], 0
    je .done
    mov edi, [chat_peer]
    test edi, edi
    jg .done                                ; a direct message
    and edi, ~CHANNEL_PEER
    call find_chan
    test rax, rax
    jnz .done
    call close_detail
.done:
    add rsp, 8
    ret

; Opens the dialog, with an existing channel's name and settings to change.
; edi = the slot to edit, CHAN_NEW to make a new channel
open_channel_dialog:
    push rbx
    mov ebx, edi
    mov byte [menu_open], 0
    mov byte [modal], M_CHANNEL
    mov [chan_editing], ebx
    mov byte [chan_armed], 0
    mov edi, F_CHANNEL
    call field_clear
    mov dword [chan_slowmode], 0
    mov dword [chan_scroll], 0
    lea rdi, [chan_overrides]
    xor eax, eax
    mov ecx, ROLE_SLOTS + 1
    rep stosb
    cmp ebx, CHAN_NEW
    je .focus
    mov edi, ebx
    call find_chan
    test rax, rax
    jz .focus
    mov rbx, rax
    movzx eax, word [rbx + CN_SLOWMODE]
    mov [chan_slowmode], eax
    lea rdi, [chan_overrides]
    lea rsi, [rbx + CN_OVERRIDES]
    mov ecx, ROLE_SLOTS + 1
    rep movsb
    lea rsi, [rbx + CN_NAME]
    movzx edx, byte [rbx + CN_NAME_LEN]
    mov edi, F_CHANNEL
    call field_set
    cmp byte [rbx + CN_SLOT], 0
    je .general
.focus:
    mov edi, F_CHANNEL
    call set_focus
    pop rbx
    ret
.general:
    mov edi, F_NONE                         ; #general has no name to change
    call set_focus
    pop rbx
    ret

; Save in the dialog: makes the channel, or sends whichever of its name and
; settings changed.
submit_channel:
    push rbx
    mov edi, [chan_editing]
    cmp edi, CHAN_NEW
    je .new
    call find_chan
    test rax, rax
    jz .done
    mov rbx, rax
    cmp byte [rbx + CN_SLOT], 0
    je .settings
    mov edi, F_CHANNEL
    call field_trimmed
    test edx, edx
    jz .done
    movzx ecx, byte [rbx + CN_NAME_LEN]
    cmp ecx, edx
    jne .rename
    lea rdi, [rbx + CN_NAME]
    push rsi
    push rdx
    call mem_eq
    pop rdx
    pop rsi
    test eax, eax
    jnz .settings
.rename:
    movzx edi, byte [rbx + CN_SLOT]
    call sync_set_channel
    test eax, eax
    jz .done
.settings:
    movzx eax, word [rbx + CN_SLOWMODE]
    cmp eax, [chan_slowmode]
    jne .send_settings
    lea rdi, [rbx + CN_OVERRIDES]
    lea rsi, [chan_overrides]
    mov edx, ROLE_SLOTS + 1
    call mem_eq
    test eax, eax
    jnz .close
.send_settings:
    movzx edi, byte [rbx + CN_SLOT]
    call sync_channel_settings
    test eax, eax
    jz .done
.close:
    call close_modal
    jmp .done
.new:
    mov edi, F_CHANNEL
    call field_trimmed
    test edx, edx
    jz .done
    xor edi, edi
    call sync_set_channel
    test eax, eax
    jz .done
    mov byte [chan_open_new], 1
    call close_modal
.done:
    pop rbx
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

; Slowmode in the dialog. edi = seconds
click_slowmode:
    mov [chan_slowmode], edi
    ret

; Steps a role's override in the dialog: default, allow, deny, default.
; edi = role slot * 4 + CH_* bit number
click_override:
    mov ecx, edi
    and ecx, 3
    shr edi, 2
    cmp edi, ROLE_SLOTS
    ja .done
    movzx eax, byte [chan_overrides + rdi]
    mov edx, 1
    shl edx, cl                             ; allow
    mov r8d, edx
    shl r8d, 4                              ; deny
    test eax, edx
    jnz .deny
    test eax, r8d
    jnz .default
    or eax, edx
    jmp .store
.deny:
    xor eax, edx
    or eax, r8d
    jmp .store
.default:
    xor eax, r8d
.store:
    mov [chan_overrides + rdi], al
.done:
    ret

; edi = slot -> eax = 1 if the dialog's slowmode and overrides for it went out
sync_channel_settings:
    push rbx
    mov ebx, edi
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_CHANNEL_SETTINGS
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    mov esi, ebx
    call wr_u8
    mov esi, [chan_slowmode]
    call wr_u16
    lea rsi, [chan_overrides]
    mov ecx, ROLE_SLOTS + 1
    rep movsb
    call send_built
.done:
    pop rbx
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

; The sidebar's channels we can see: #general first, then the rest by
; slot, under a heading whose "+" makes another. edi = top -> eax = the y under them
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
    mov edx, CHAN_NEW
    call side_plus
    add ebx, 28
    mov r13d, -1                            ; the slot, #general first
    jmp .next_slot
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
    push rdi
    push rdi
    mov edi, GL_HASH
    mov esi, 18
    lea edx, [ebx + 7]
    mov ecx, C_DIM
    call draw_glyph
    pop rdi
    pop rdi
    lea rdx, [scratch + 1]                  ; the glyph stands in for the "#"
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
    lea r12d, [r13d + CHANNEL_PEER]         ; the row's peer
    test r13d, r13d
    cmovz r12d, r13d                        ; #general's is 0
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
    jg .done                                ; a direct message
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

; Slowmode's lengths in the dialog, the one picked highlighted.
; edi = x, esi = baseline
draw_slowmode_options:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 8
    mov ebx, edi
    mov ebp, esi
    lea edi, [ebx + 28]
    lea rdx, [s_slowmode_label]
    mov ecx, s_slowmode_label_len
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    lea r12d, [ebx + 110]
    xor r13d, r13d
.preset:
    mov eax, r13d
    shl eax, 4
    mov rdx, [slowmode_names + rax]
    mov ecx, [slowmode_names + rax + 8]
    mov edi, r12d
    mov esi, ebp
    mov r9d, [slowmode_secs + r13 * 4]
    cmp r9d, [chan_slowmode]
    je .current
    mov r8d, A_SLOWMODE
    call left_link
    jmp .next
.current:
    mov r8d, INK(C_ACCENT_HI, ST_SMALL)
    call draw_text
.next:
    lea r12d, [eax + 14]
    inc r13d
    cmp r13d, SLOWMODE_PRESETS
    jb .preset
    add rsp, 8
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; One role's overrides: its name, then Default, Allow or Deny for each of
; View, Send and Manage, each a link to the next.
; edi = x, esi = baseline, edx = role slot, rcx = name, r8d = its length, r9d = dot color or -1
draw_override_row:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov ebx, edi
    mov ebp, esi
    mov r12d, edx
    mov r13, rcx
    mov r14d, r8d
    lea r15d, [ebx + 28]                    ; the name's x
    test r9d, r9d
    js .name
    lea edi, [ebx + 33]
    lea esi, [ebp - 5]
    mov edx, 5
    mov ecx, r9d
    call fill_disc
    lea r15d, [ebx + 46]
.name:
    mov edi, r15d
    mov esi, ebp
    mov rdx, r13
    mov ecx, r14d
    mov r8d, INK(C_TEXT, ST_BODY)
    mov r9d, GRID_X - 12
    sub r9d, r15d
    add r9d, ebx
    call draw_text_fit
    xor r13d, r13d                          ; the CH_* bit number
.cell:
    movzx eax, byte [chan_overrides + r12]
    lea rdx, [s_inherit]
    mov ecx, s_inherit_len
    mov r15d, C_FAINT
    bt eax, r13d
    jnc .denied
    lea rdx, [s_allow]
    mov ecx, s_allow_len
    mov r15d, C_ONLINE
.denied:
    lea r8d, [r13d + 4]
    bt eax, r8d
    jnc .draw
    lea rdx, [s_deny]
    mov ecx, s_deny_len
    mov r15d, C_DANGER
.draw:
    mov [rsp], ecx
    push rdx
    push rdx
    mov rdi, rdx
    mov esi, ecx
    mov edx, ST_SMALL
    call text_width
    pop rdx
    pop rdx
    mov r14d, eax
    imul edi, r13d, GRID_COL_W
    lea edi, [ebx + edi + GRID_X]
    mov esi, ebp
    mov ecx, [rsp]
    mov r8d, r15d
    or r8d, ST_SMALL << 24
    call draw_text
    imul edi, r13d, GRID_COL_W
    lea edi, [ebx + edi + GRID_X]
    lea esi, [ebp - 18]
    mov edx, r14d
    mov ecx, GRID_ROW_H
    mov r8d, A_OVERRIDE
    lea r9d, [r12d * 4 + r13d]
    call add_hit
    inc r13d
    cmp r13d, 3
    jb .cell
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The overrides: a heading per column, @everyone's row, then each role's,
; highest first. edi = x, esi = the headings' baseline -> eax = the baseline under them
draw_override_grid:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 8
    mov ebx, edi
    mov ebp, esi
    lea edi, [ebx + 28]
    lea rdx, [s_overrides_label]
    mov ecx, s_overrides_label_len
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    xor r12d, r12d
.heading:
    mov eax, r12d
    shl eax, 4
    mov rdx, [column_names + rax]
    mov ecx, [column_names + rax + 8]
    imul edi, r12d, GRID_COL_W
    lea edi, [ebx + edi + GRID_X]
    mov esi, ebp
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    inc r12d
    cmp r12d, 3
    jb .heading
    add ebp, GRID_ROW_H
    mov edi, ebx
    mov esi, ebp
    xor edx, edx
    lea rcx, [s_everyone]
    mov r8d, s_everyone_len
    mov r9d, -1
    call draw_override_row
    add ebp, GRID_ROW_H
    mov r12d, [role_count]
.role:
    test r12d, r12d
    jz .done
    mov edi, r12d
    call role_at_pos
    test rax, rax
    jz .next
    mov r13, rax
    mov edi, ebx
    mov esi, ebp
    movzx edx, byte [r13 + RO_SLOT]
    lea rcx, [r13 + RO_NAME]
    movzx r8d, byte [r13 + RO_NAME_LEN]
    mov r9d, [r13 + RO_COLOR]
    call draw_override_row
    add ebp, GRID_ROW_H
.next:
    dec r12d
    jmp .role
.done:
    mov eax, ebp
    add rsp, 8
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -> eax = the dialog's height with every override showing: a name for a new
; channel, and for an existing one its slowmode and overrides too, #general
; without a name
channel_dialog_height:
    mov eax, 250
    mov edi, [chan_editing]
    cmp edi, CHAN_NEW
    je .done
    mov eax, [role_count]
    imul eax, eax, GRID_ROW_H
    add eax, 2 * GRID_ROW_H + 282           ; the headings and @everyone's row
    test edi, edi
    jnz .done
    sub eax, 70                             ; #general has no name to change
.done:
    ret

; -> eax = how much of the overrides fits on screen, edx = their full height.
; With many roles the dialog would run off the window, so they scroll.
chan_grid_window:
    sub rsp, 8
    call channel_dialog_height
    mov ecx, [win_h]
    sub ecx, 100                            ; modal_box's top, and a margin under it
    sub eax, ecx                            ; how much it runs over
    mov edx, [role_count]
    add edx, 2                              ; the headings and @everyone
    imul edx, edx, GRID_ROW_H
    mov ecx, edx
    test eax, eax
    jle .fits
    sub ecx, eax
    mov eax, 3 * GRID_ROW_H
    cmp ecx, eax
    cmovl ecx, eax
.fits:
    mov eax, ecx
    add rsp, 8
    ret

; Slowmode, then the overrides, scrolled when they don't fit, and the hint.
; edi = x, esi = baseline, edx = how much of the overrides shows
draw_channel_settings:
    push rbx
    push rbp
    push r12
    mov ebx, edi
    mov ebp, esi
    mov r12d, edx
    call draw_slowmode_options
    add ebp, 40
    call chan_grid_window
    lea rdi, [chan_scroll]
    mov esi, r12d
    call clamp_scroll_to
    mov edi, ebx
    lea esi, [ebp - 20]                     ; the headings' tops
    lea edx, [ebx + CHANNEL_MODAL_W]
    lea ecx, [esi + r12d]
    call set_clip
    mov edi, ebx
    mov esi, ebp
    sub esi, [chan_scroll]
    call draw_override_grid
    call reset_clip
    lea edi, [ebx + 28]
    lea esi, [ebp + r12d]
    lea rdx, [s_grid_hint]
    mov ecx, s_grid_hint_len
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_text
    pop r12
    pop rbp
    pop rbx
    ret

; The dialog: the name, and for an existing channel its slowmode, its
; overrides and a way to delete it. #general only has the settings.
draw_channel_dialog:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    call channel_dialog_height
    mov r14d, eax
    call chan_grid_window
    mov [rsp], eax
    sub r14d, edx
    add r14d, eax                           ; less what doesn't fit
    mov edi, CHANNEL_MODAL_W
    mov esi, r14d
    call modal_box
    mov ebx, eax
    mov r12d, edx
    mov r13d, [chan_editing]
    lea rdx, [s_new_channel]
    mov ecx, s_new_channel_len
    lea rax, [s_edit_channel]
    mov esi, s_edit_channel_len
    cmp r13d, CHAN_NEW
    cmovne rdx, rax
    cmovne ecx, esi
    lea rax, [s_general]
    mov esi, s_general_len
    test r13d, r13d
    cmovz rdx, rax
    cmovz ecx, esi
    lea edi, [ebx + 28]
    lea esi, [r12d + 46]
    mov r8d, INK(C_TEXT, ST_TITLE)
    call draw_text
    lea ebp, [r12d + 84]                    ; the next row's baseline
    test r13d, r13d
    jz .settings
    lea edi, [ebx + 28]
    mov esi, ebp
    lea rdx, [s_channel_name]
    mov ecx, s_channel_name_len
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    mov edi, F_CHANNEL
    lea esi, [ebx + 28]
    lea edx, [ebp + 10]
    mov ecx, CHANNEL_MODAL_W - 56
    call draw_field_box
    add ebp, 70
    cmp r13d, CHAN_NEW
    jne .settings
    lea edi, [ebx + 28]
    mov esi, ebp
    lea rdx, [s_channel_hint]
    mov ecx, s_channel_hint_len
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_text
    jmp .buttons
.settings:
    mov edi, ebx
    mov esi, ebp
    mov edx, [rsp]
    call draw_channel_settings
.buttons:
    lea r15d, [r12d + r14d - 58]            ; the buttons' top
    lea rdx, [s_create_channel]
    mov ecx, s_create_channel_len
    lea rax, [s_save_channel]
    mov esi, s_save_channel_len
    cmp r13d, CHAN_NEW
    cmovne rdx, rax
    cmovne ecx, esi
    lea edi, [ebx + 28]
    mov esi, r15d
    mov r8d, A_SAVE_CHANNEL
    mov r9d, BTN_PRIMARY
    call draw_button
    cmp r13d, CHAN_NEW
    je .done
    test r13d, r13d
    jz .done                                ; #general can't be deleted
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
    mov esi, r15d
    mov r8d, A_DELETE_CHANNEL
    mov r9d, BTN_DANGER
    cmp byte [chan_armed], 0
    jne .delete
    xor r9d, r9d
.delete:
    call draw_button
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
