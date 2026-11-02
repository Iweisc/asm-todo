; The moderation half of team settings: a member's page with their
; nickname, roles, timeouts, Transfer ownership, Kick and Ban, and the ban
; list. The audit log is in audit.asm. The server sends the bans only to
; those whose permissions get them, and decides who may do what to whom.
; access.asm mirrors it so we only offer what it will take.

; A ban, as MSG_BANS lists it.
%define BN_USER         0
%define BN_AT           4
%define BN_NAME_LEN     8
%define BN_NAME         9               ; USERNAME_MAX bytes
%define BN_REASON_LEN   41
%define BN_REASON       42              ; REASON_MAX bytes
%define BN_SIZE         144
fits BN_NAME, USERNAME_MAX, BN_REASON_LEN
fits BN_REASON, REASON_MAX, BN_SIZE

%define OPTION_X        120             ; where a page row's options start, past its label
%define SWITCH_ROW_H    30              ; a role on a member's page

; The parts of a member's page, see page_sections
%define PG_NICK         1
%define PG_OWNER        2
%define PG_ROLES        4
%define PG_TIMEOUT      8
%define PG_REASON       16
%define PG_HISTORY      32
%define PG_KICK         64
%define PG_BAN          128
%define PG_TRANSFER     256
%define PG_BUTTONS      (PG_KICK | PG_BAN | PG_TRANSFER)

section .rodata
text s_back,            "Back to members"
text s_member_online,   "Online"
text s_member_offline,  "Offline"
text s_timed_out_until, "Timed out until "
text s_role_label,      "Access"
text s_roles_label,     "Roles"
text s_nick_label,      "Nickname"
text s_nick_hint,       "Shown instead of their username"
text s_no_roles,        "The team has no roles yet. Make some in the Roles tab."
text s_history_label,   "Delete"
text s_keep_messages,   "None of their messages"
text s_last_hour,       "Last hour"
text s_last_day,        "Last day"
text s_last_week,       "Last 7 days"
text s_timeout_label,   "Timeout"
text s_reason_label,    "Reason"
text s_reason_hint,     "Optional, shown in the audit log"
text s_end_timeout,     "End timeout"
text s_kick,            "Kick"
text s_kick_sure,       "Kick?"
text s_ban,             "Ban"
text s_ban_sure,        "Ban?"
text s_transfer,        "Transfer ownership"
text s_transfer_sure,   "Transfer ownership?"
text s_unban,           "Unban"
text s_banned_on,       "Banned "
text s_no_bans,         "Nobody's banned from this team."
text s_for,             " for "
text s_mins,            " mins"
text s_60_secs,         "60 secs"
text s_5_mins,          "5 mins"
text s_10_mins,         "10 mins"
text s_1_hour,          "1 hour"
text s_1_day,           "1 day"
text s_1_week,          "1 week"
text s_everyone,        "@everyone"
text middot_sep,        " ", GLYPH_MIDDOT, " "

; Discord's timeout lengths.
align 4
timeout_secs:   dd 60, 300, 600, 3600, 86400, 604800
TIMEOUT_PRESETS equ ($ - timeout_secs) / 4
history_secs:   dd 0, 3600, 86400, BAN_HISTORY_MAX
HISTORY_PRESETS equ ($ - history_secs) / 4
role_order:     db ROLE_OWNER, ROLE_MEMBER
align 8
history_names:  NAME s_keep_messages
                NAME s_last_hour
                NAME s_last_day
                NAME s_last_week
timeout_names:  NAME s_60_secs
                NAME s_5_mins
                NAME s_10_mins
                NAME s_1_hour
                NAME s_1_day
                NAME s_1_week

section .bss
alignb 4
ban_count:      resd 1
ban_rows:       resb TEAM_BAN_MAX * BN_SIZE
reason_buf:     resb REASON_MAX
nick_buf:       resb NICKNAME_MAX
ban_history:    resd 1                  ; seconds of their messages Ban deletes

section .text

; MSG_BANS: the current team's ban list.
on_bans:
    push rbx
    push r12
    push r13
    call rd_u32
    mov ebx, eax
    call rd_u8
    mov r12d, eax
    cmp ebx, [current_team]
    jne .skip
    cmp r12d, TEAM_BAN_MAX
    ja .bad
    lea rbx, [ban_rows]
    xor r13d, r13d
.ban:
    cmp r13d, r12d
    jae .read
    call rd_u32
    mov [rbx + BN_USER], eax
    call rd_u32
    mov [rbx + BN_AT], eax
    lea rdi, [rbx + BN_NAME_LEN]
    mov esi, USERNAME_MAX
    call read_named_str
    lea rdi, [rbx + BN_REASON_LEN]
    mov esi, REASON_MAX
    call read_named_str
    add rbx, BN_SIZE
    inc r13d
    jmp .ban
.read:
    mov [ban_count], r12d
    jmp .done
.bad:
    mov byte [rd_bad], 1
    jmp .done
.skip:
    call rd_skip
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Sends MSG_REMOVE_MEMBER or MSG_BAN. edi = the message, esi = user id,
; rdx = reason, ecx = its length, r8d = seconds of messages a ban deletes
; -> eax = 1 if it went out
sync_moderate:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    mov r15d, r8d
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, ebx
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    mov esi, r12d
    call wr_u32
    cmp ebx, MSG_BAN
    jne .reason
    mov esi, r15d
    call wr_u32
.reason:
    mov rsi, r13
    mov edx, r14d
    call wr_str
    call send_built
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; edi = user id, esi = seconds, 0 to end it, rdx = reason, ecx = its length
; -> eax = 1 if it went out
sync_timeout:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_TIMEOUT
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    mov esi, ebx
    call wr_u32
    mov esi, r12d
    call wr_u32
    mov rsi, r13
    mov edx, r14d
    call wr_str
    call send_built
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Lets someone be invited again. edi = user id
click_unban:
    push rbx
    mov ebx, edi
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_UNBAN
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    mov esi, ebx
    call wr_u32
    call send_built
.done:
    pop rbx
    ret

; Times out the member being managed, or ends it, with the reason typed.
; edi = seconds, 0 to end it
click_timeout:
    push rbx
    mov ebx, edi
    mov edi, F_REASON
    call field_trimmed
    mov ecx, edx
    mov rdx, rsi
    mov esi, ebx
    mov edi, [managing]
    call sync_timeout
    test eax, eax
    jz .done
    mov edi, F_REASON
    call field_clear
.done:
    pop rbx
    ret

; Kick on a member's page. The first click asks.
click_kick:
    mov esi, A_KICK
    mov edx, MSG_REMOVE_MEMBER
    jmp moderate_managed
; Ban on a member's page. The first click asks.
click_ban:
    mov esi, A_BAN
    mov edx, MSG_BAN
; esi = A_KICK or A_BAN, edx = the message it sends, with the reason typed
moderate_managed:
    push rbx
    mov ebx, edx
    mov edi, [managing]
    call confirm_member
    test eax, eax
    jz .done
    mov edi, F_REASON
    call field_trimmed
    mov ecx, edx
    mov rdx, rsi
    mov esi, [managing]
    mov edi, ebx
    mov r8d, [ban_history]
    call sync_moderate
    test eax, eax
    jz .done
    mov edi, F_REASON
    call field_clear
.done:
    pop rbx
    ret

; Transfer ownership on a member's page: they become the owner and we a
; member. The first click asks.
click_transfer:
    sub rsp, 8
    mov edi, [managing]
    mov esi, A_TRANSFER
    call confirm_member
    test eax, eax
    jz .done
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_TRANSFER_OWNER
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    mov esi, [managing]
    call wr_u32
    call send_built
.done:
    add rsp, 8
    ret

; Gives the member being managed a role, or takes it away. edi = role slot
click_toggle_role:
    push rbx
    mov ebx, edi
    mov edi, [managing]
    call find_member_row
    test rax, rax
    jz .done
    movzx esi, word [rax + CM_ROLES]
    btc esi, ebx
    mov edi, [managing]
    call sync_member_roles
.done:
    pop rbx
    ret

; Sends the nickname typed on a member's page, empty to clear it.
save_nickname:
    sub rsp, 8
    mov edi, F_NICK
    call field_trimmed
    mov edi, [managing]
    call sync_nickname
    test eax, eax
    jz .done
    mov edi, F_NONE
    call set_focus
.done:
    add rsp, 8
    ret

; How much of their messages Ban deletes. edi = seconds
click_ban_history:
    mov [ban_history], edi
    ret

; rdi = cursor, esi = 0-99 -> rdi advanced past it as two digits
put_two:
    mov eax, esi
    xor edx, edx
    mov ecx, 10
    div ecx
    add al, '0'
    add dl, '0'
    mov [rdi], al
    mov [rdi + 1], dl
    add rdi, 2
    ret

; rdi = cursor, esi = unix seconds -> rdi advanced past "Nov 3, 14:05", local time
put_time:
    push rbx
    mov ebx, esi
    call put_date
    mov word [rdi], ', '
    add rdi, 2
    mov eax, ebx
    add eax, [tz_offset]
    xor edx, edx
    mov ecx, 86400
    div ecx
    mov eax, edx
    xor edx, edx
    mov ecx, 60
    div ecx                                 ; minutes into the day
    xor edx, edx
    div ecx
    mov ebx, edx
    mov esi, eax
    call put_two
    mov byte [rdi], ':'
    inc rdi
    mov esi, ebx
    call put_two
    pop rbx
    ret

; rdi = cursor -> rdi advanced past " · "
put_middot:
    lea rsi, [middot_sep]
    mov edx, middot_sep_len
    jmp put_mem

; A link starting at x, dim until hovered. edi = x, esi = baseline,
; rdx = text, ecx = length, r8d = action, r9d = arg -> eax = the x after it
left_link:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov ebx, edi
    mov ebp, esi
    mov r12, rdx
    mov r13d, ecx
    mov r14d, r8d
    mov r15d, r9d
    mov rdi, rdx
    mov esi, ecx
    mov edx, ST_SMALL
    call text_width
    mov [rsp], eax
    mov edi, r14d
    mov esi, r15d
    call hovering
    mov r8d, C_DIM
    mov ecx, C_TEXT
    test eax, eax
    cmovnz r8d, ecx
    mov edi, ebx
    mov esi, ebp
    mov rdx, r12
    mov ecx, r13d
    call draw_text
    mov edi, ebx
    mov edx, [rsp]
    mov esi, ebp
    mov r8d, r14d
    mov r9d, r15d
    call add_link_hit
    mov eax, ebx
    add eax, [rsp]
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; A row's label on the left of a member's page. edi = x, esi = baseline, rdx = text, ecx = length
draw_page_label:
    mov r8d, INK(C_DIM, ST_SMALL)
    jmp draw_text

; Back, then who they are: avatar, name, role, whether they're online and
; any timeout. edi = x, esi = top, rdx = member row
draw_page_header:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    lea edi, [ebx + 28]
    lea esi, [r12d + 14]
    lea rdx, [s_back]
    mov ecx, s_back_len
    mov r8d, A_MANAGE
    xor r9d, r9d
    call left_link
    mov rdi, r13
    call display_name
    mov r8, rsi
    lea edi, [ebx + 28]
    lea esi, [r12d + 30]
    mov edx, 36
    mov ecx, [r13 + CM_ID]
    call draw_avatar
    mov rdi, r13
    call display_name
    mov ecx, edx
    mov rdx, rsi
    lea edi, [ebx + 76]
    lea esi, [r12d + 46]
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    lea rdi, [scratch]
    mov rsi, r13
    call put_rank_name
    cmp byte [r13 + CM_NICK_LEN], 0
    je .online
    call put_middot
    lea rsi, [r13 + CM_NAME]
    movzx edx, byte [r13 + CM_NAME_LEN]
    call put_mem
.online:
    call put_middot
    lea rsi, [s_member_offline]
    mov edx, s_member_offline_len
    lea rax, [s_member_online]
    mov ecx, s_member_online_len
    cmp byte [r13 + CM_ONLINE], 0
    cmovne rsi, rax
    cmovne edx, ecx
    call put_mem
    mov rcx, rdi
    lea edi, [ebx + 76]
    lea esi, [r12d + 64]
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_scratch
    mov ebx, eax
    mov rdi, r13
    call member_timed_out
    test eax, eax
    jz .done
    lea rdi, [scratch]
    call put_middot
    lea rsi, [s_timed_out_until]
    mov edx, s_timed_out_until_len
    call put_mem
    mov esi, [r13 + CM_TIMEOUT]
    call put_time
    mov rcx, rdi
    mov edi, ebx
    lea esi, [r12d + 64]
    mov r8d, INK(C_DANGER, ST_SMALL)
    call draw_scratch
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Owners make the member an owner or a member. The one they are isn't a link.
; edi = x, esi = baseline, rdx = member row
draw_role_options:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov ebx, edi
    mov ebp, esi
    mov r12, rdx
    lea edi, [ebx + 28]
    lea rdx, [s_role_label]
    mov ecx, s_role_label_len
    call draw_page_label
    lea r13d, [ebx + OPTION_X]
    xor r14d, r14d
.role:
    movzx edi, byte [role_order + r14]
    call role_name
    mov ecx, edx
    mov rdx, rsi
    mov edi, r13d
    mov esi, ebp
    movzx r9d, byte [role_order + r14]
    cmp r9b, [r12 + CM_ROLE]
    je .current
    mov r8d, A_SET_ROLE
    call left_link
    jmp .next
.current:
    mov r8d, INK(C_ACCENT_HI, ST_SMALL)
    call draw_text
.next:
    lea r13d, [eax + 18]
    inc r14d
    cmp r14d, 2
    jb .role
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The team's roles, highest first, each with a switch saying whether the
; member has it. Only roles below ours switch.
; edi = x, esi = baseline, rdx = member row -> eax = the next row's baseline
draw_role_switches:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov ebx, edi
    mov ebp, esi
    mov r12, rdx
    lea edi, [ebx + 28]
    lea rdx, [s_roles_label]
    mov ecx, s_roles_label_len
    call draw_page_label
    mov r14d, [role_count]
    test r14d, r14d
    jnz .ranked
    lea edi, [ebx + OPTION_X]
    mov esi, ebp
    lea rdx, [s_no_roles]
    mov ecx, s_no_roles_len
    mov r8d, INK(C_FAINT, ST_SMALL)
    call draw_text
    add ebp, SWITCH_ROW_H + 2
    jmp .done
.ranked:
    call my_rank
    mov [rsp], eax
.role:
    mov edi, r14d                           ; positions run from the role count down to 1
    call role_at_pos
    test rax, rax
    jz .next
    mov r13, rax
    lea edi, [ebx + OPTION_X + 5]
    lea esi, [ebp - 5]
    mov edx, 5
    mov ecx, [r13 + RO_COLOR]
    call fill_disc
    lea edi, [ebx + OPTION_X + 18]
    mov esi, ebp
    lea rdx, [r13 + RO_NAME]
    movzx ecx, byte [r13 + RO_NAME_LEN]
    mov r8d, INK(C_TEXT, ST_BODY)
    call draw_text
    movzx r15d, byte [r13 + RO_SLOT]
    movzx edx, word [r12 + CM_ROLES]
    bt edx, r15d
    setc dl
    movzx edx, dl
    movzx ecx, byte [r13 + RO_POS]
    cmp ecx, [rsp]
    setb cl
    movzx ecx, cl
    lea edi, [ebx + SETTINGS_W - 28 - SWITCH_W]
    lea esi, [ebp - 14]
    mov r8d, A_TOGGLE_ROLE
    mov r9d, r15d
    call draw_switch
    add ebp, SWITCH_ROW_H
.next:
    dec r14d
    jnz .role
    add ebp, 2
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

; How much of their messages Ban deletes. edi = x, esi = baseline
draw_history_options:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 8
    mov ebx, edi
    mov ebp, esi
    lea edi, [ebx + 28]
    lea rdx, [s_history_label]
    mov ecx, s_history_label_len
    call draw_page_label
    lea r12d, [ebx + OPTION_X]
    xor r13d, r13d
.preset:
    mov eax, r13d
    shl eax, 4
    mov rdx, [history_names + rax]
    mov ecx, [history_names + rax + 8]
    mov edi, r12d
    mov esi, ebp
    mov r9d, [history_secs + r13 * 4]
    cmp r9d, [ban_history]
    je .current
    mov r8d, A_BAN_HISTORY
    call left_link
    jmp .next
.current:
    mov r8d, INK(C_ACCENT_HI, ST_SMALL)
    call draw_text
.next:
    lea r12d, [eax + 16]
    inc r13d
    cmp r13d, HISTORY_PRESETS
    jb .preset
    add rsp, 8
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Discord's timeout lengths, and End timeout while they're timed out.
; edi = x, esi = baseline, rdx = member row
draw_timeout_options:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov ebx, edi
    mov ebp, esi
    mov r12, rdx
    lea edi, [ebx + 28]
    lea rdx, [s_timeout_label]
    mov ecx, s_timeout_label_len
    call draw_page_label
    lea r13d, [ebx + OPTION_X]
    xor r14d, r14d
.preset:
    mov eax, r14d
    shl eax, 4
    mov rdx, [timeout_names + rax]
    mov ecx, [timeout_names + rax + 8]
    mov edi, r13d
    mov esi, ebp
    mov r8d, A_TIMEOUT
    mov r9d, [timeout_secs + r14 * 4]
    call left_link
    lea r13d, [eax + 16]
    inc r14d
    cmp r14d, TIMEOUT_PRESETS
    jb .preset
    mov rdi, r12
    call member_timed_out
    test eax, eax
    jz .done
    lea edi, [ebx + SETTINGS_W - 28]
    mov esi, ebp
    lea rdx, [s_end_timeout]
    mov ecx, s_end_timeout_len
    mov r8d, C_DANGER
    call draw_link
    mov edi, eax
    mov esi, ebp
    mov r8d, A_TIMEOUT
    xor r9d, r9d
    call add_link_hit
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Kick, Ban and Transfer ownership, each asking with a second click.
; edi = x, esi = y, edx = user id, ecx = the PG_BUTTONS their page has
draw_page_buttons:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    test r14d, PG_KICK
    jz .no_kick
    lea rdx, [s_kick]
    mov ecx, s_kick_len
    cmp r13d, [member_armed]
    jne .kick
    cmp dword [armed_action], A_KICK
    jne .kick
    lea rdx, [s_kick_sure]
    mov ecx, s_kick_sure_len
.kick:
    mov edi, ebx
    mov esi, r12d
    mov r8d, A_KICK
    xor r9d, r9d
    call draw_button
    lea ebx, [ebx + eax + 8]
.no_kick:
    test r14d, PG_BAN
    jz .no_ban
    lea rdx, [s_ban]
    mov ecx, s_ban_len
    cmp r13d, [member_armed]
    jne .ban
    cmp dword [armed_action], A_BAN
    jne .ban
    lea rdx, [s_ban_sure]
    mov ecx, s_ban_sure_len
.ban:
    mov edi, ebx
    mov esi, r12d
    mov r8d, A_BAN
    mov r9d, BTN_DANGER
    call draw_button
    lea ebx, [ebx + eax + 8]
.no_ban:
    test r14d, PG_TRANSFER
    jz .done
    lea rdx, [s_transfer]
    mov ecx, s_transfer_len
    cmp r13d, [member_armed]
    jne .transfer
    cmp dword [armed_action], A_TRANSFER
    jne .transfer
    lea rdx, [s_transfer_sure]
    mov ecx, s_transfer_sure_len
.transfer:
    mov edi, ebx
    mov esi, r12d
    mov r8d, A_TRANSFER
    xor r9d, r9d
    call draw_button
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi = cursor, rsi = member row -> rdi advanced past what they rank as:
; Owner, their highest role's name, or Member
put_rank_name:
    push rbx
    mov rbx, rdi
    cmp byte [rsi + CM_ROLE], ROLE_OWNER
    je .role
    push rsi
    mov rdi, rsi
    call top_role
    pop rsi
    test rax, rax
    jz .role
    mov rdi, rbx
    lea rsi, [rax + RO_NAME]
    movzx edx, byte [rax + RO_NAME_LEN]
    pop rbx
    jmp put_mem
.role:
    movzx edi, byte [rsi + CM_ROLE]
    call role_name
    mov rdi, rbx
    pop rbx
    jmp put_mem

; rdi = member row -> eax = the PG_* parts their page has for us
page_sections:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    xor r12d, r12d
    mov eax, [rbx + CM_ID]
    cmp eax, [my_id]
    jne .others
    mov edi, PERM_CHANGE_NICKNAME
    call has_perm
    neg eax
    and eax, PG_NICK
    or r12d, eax
    mov edi, PERM_MANAGE_ROLES
    call has_perm
    neg eax
    and eax, PG_ROLES
    or r12d, eax
    jmp .done
.others:
    mov rdi, rbx
    mov esi, PERM_MANAGE_NICKNAMES
    call may_act_on
    neg eax
    and eax, PG_NICK
    or r12d, eax
    mov rdi, rbx
    mov esi, PERM_MANAGE_ROLES
    call may_act_on
    neg eax
    and eax, PG_ROLES
    or r12d, eax
    call am_owner
    test eax, eax
    jz .moderation
    or r12d, PG_OWNER
    cmp byte [rbx + CM_ROLE], ROLE_OWNER
    je .moderation
    or r12d, PG_TRANSFER
.moderation:
    mov rdi, rbx
    mov esi, PERM_KICK
    call may_act_on
    neg eax
    and eax, PG_KICK | PG_REASON
    or r12d, eax
    mov rdi, rbx
    mov esi, PERM_BAN
    call may_act_on
    neg eax
    and eax, PG_BAN | PG_HISTORY | PG_REASON
    or r12d, eax
    mov rdi, rbx
    call member_perms
    test eax, PERM_ADMIN
    jnz .done                               ; owners and admins can't be timed out
    mov rdi, rbx
    mov esi, PERM_TIMEOUT
    call may_act_on
    neg eax
    and eax, PG_TIMEOUT | PG_REASON
    or r12d, eax
.done:
    mov eax, r12d
    add rsp, 8
    pop r12
    pop rbx
    ret

; rdi = member row -> eax = their page's height, as draw_member_page lays it out
page_height:
    sub rsp, 8
    call page_sections
    mov ecx, 104                            ; the first row's baseline
    test eax, PG_NICK
    jz .owner
    add ecx, FIELD_ROW_H
.owner:
    test eax, PG_OWNER
    jz .roles
    add ecx, 32
.roles:
    test eax, PG_ROLES
    jz .timeout
    mov edx, [role_count]
    mov r8d, 1
    test edx, edx
    cmovz edx, r8d
    imul edx, edx, SWITCH_ROW_H
    lea ecx, [ecx + edx + 2]
.timeout:
    test eax, PG_TIMEOUT
    jz .reason
    add ecx, 32
.reason:
    test eax, PG_REASON
    jz .history
    add ecx, FIELD_ROW_H
.history:
    test eax, PG_HISTORY
    jz .buttons
    add ecx, 32
.buttons:
    test eax, PG_BUTTONS
    jz .done
    add ecx, 40
.done:
    lea eax, [ecx - 12]
    add rsp, 8
    ret

; A label, a field and a button at the right. edi = x, esi = baseline,
; rdx = label, ecx = its length, r8d = field, r9d = the button's action, 0 for none
draw_page_field:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 8
    mov ebx, edi
    mov ebp, esi
    mov r12d, r8d
    mov r13d, r9d
    lea edi, [ebx + 28]
    call draw_page_label
    test r13d, r13d
    jz .alone
    mov edi, r12d
    lea esi, [ebx + OPTION_X]
    lea edx, [ebp - 23]
    lea rcx, [s_save]
    mov r8d, s_save_len
    mov r9d, r13d
    mov r10d, SETTINGS_W - OPTION_X - 28
    call draw_field_with_button
    jmp .done
.alone:
    mov edi, r12d
    lea esi, [ebx + OPTION_X]
    lea edx, [ebp - 23]
    mov ecx, SETTINGS_W - OPTION_X - 28
    call draw_field_box
.done:
    add rsp, 8
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; A member's page: who they are, then what we can do to them, as
; page_sections says. edi = x, esi = top, rdx = member row
draw_member_page:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    call draw_page_header
    mov rdi, r13
    call page_sections
    mov r15d, eax
    lea r14d, [r12d + 104]                  ; the next row's baseline
    test r15d, PG_NICK
    jz .owner
    mov edi, ebx
    mov esi, r14d
    lea rdx, [s_nick_label]
    mov ecx, s_nick_label_len
    mov r8d, F_NICK
    mov r9d, A_SAVE_NICK
    call draw_page_field
    add r14d, FIELD_ROW_H
.owner:
    test r15d, PG_OWNER
    jz .roles
    mov edi, ebx
    mov esi, r14d
    mov rdx, r13
    call draw_role_options
    add r14d, 32
.roles:
    test r15d, PG_ROLES
    jz .timeout
    mov edi, ebx
    mov esi, r14d
    mov rdx, r13
    call draw_role_switches
    mov r14d, eax
.timeout:
    test r15d, PG_TIMEOUT
    jz .reason
    mov edi, ebx
    mov esi, r14d
    mov rdx, r13
    call draw_timeout_options
    add r14d, 32
.reason:
    test r15d, PG_REASON
    jz .history
    mov edi, ebx
    mov esi, r14d
    lea rdx, [s_reason_label]
    mov ecx, s_reason_label_len
    mov r8d, F_REASON
    xor r9d, r9d
    call draw_page_field
    add r14d, FIELD_ROW_H
.history:
    test r15d, PG_HISTORY
    jz .buttons
    mov edi, ebx
    mov esi, r14d
    call draw_history_options
    add r14d, 32
.buttons:
    test r15d, PG_BUTTONS
    jz .done
    lea edi, [ebx + OPTION_X]
    lea esi, [r14d - 18]
    mov edx, [r13 + CM_ID]
    mov ecx, r15d
    call draw_page_buttons
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Who's banned, with Unban, or a line saying nobody is. edi = x, esi = top
draw_bans:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12d, esi
    mov r13d, [ban_count]
    test r13d, r13d
    jz .none
    lea r14, [ban_rows]
.ban:
    lea edi, [ebx + 28]
    lea esi, [r12d + 14]
    mov edx, 24
    mov ecx, [r14 + BN_USER]
    lea r8, [r14 + BN_NAME]
    call draw_avatar
    lea edi, [ebx + SETTINGS_W - 28]
    lea esi, [r12d + 24]
    lea rdx, [s_unban]
    mov ecx, s_unban_len
    mov r8d, C_DIM
    call draw_link
    mov r15d, eax
    mov edi, eax
    lea esi, [r12d + 24]
    mov r8d, A_UNBAN
    mov r9d, [r14 + BN_USER]
    call add_link_hit
    lea edi, [ebx + 62]
    lea esi, [r12d + 24]
    lea rdx, [r14 + BN_NAME]
    movzx ecx, byte [r14 + BN_NAME_LEN]
    mov r8d, INK(C_TEXT, ST_BODY)
    lea r9d, [r15d - 16]
    sub r9d, edi
    call draw_text_fit
    lea rdi, [scratch]
    lea rsi, [s_banned_on]
    mov edx, s_banned_on_len
    call put_mem
    mov esi, [r14 + BN_AT]
    call put_date
    movzx edx, byte [r14 + BN_REASON_LEN]
    test edx, edx
    jz .line
    call put_middot
    lea rsi, [r14 + BN_REASON]
    movzx edx, byte [r14 + BN_REASON_LEN]
    call put_mem
.line:
    lea rdx, [scratch]
    mov rcx, rdi
    sub rcx, rdx
    lea edi, [ebx + 62]
    lea esi, [r12d + 42]
    mov r8d, INK(C_FAINT, ST_SMALL)
    mov r9d, SETTINGS_W - 62 - 28
    call draw_text_fit
    add r12d, LIST_ROW_H
    add r14, BN_SIZE
    dec r13d
    jnz .ban
    jmp .done
.none:
    lea edi, [ebx + 28]
    lea esi, [r12d + 26]
    lea rdx, [s_no_bans]
    mov ecx, s_no_bans_len
    mov r8d, INK(C_DIM, ST_BODY)
    call draw_text
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi = cursor, ecx = seconds -> rdi advanced past one of the timeout
; lengths' names, or the minutes for a length we don't offer
put_duration:
    xor eax, eax
.preset:
    cmp ecx, [timeout_secs + rax * 4]
    je .named
    inc eax
    cmp eax, TIMEOUT_PRESETS
    jb .preset
    mov eax, ecx
    xor edx, edx
    mov ecx, 60
    div ecx
    mov esi, eax
    call put_u32
    lea rsi, [s_mins]
    mov edx, s_mins_len
    jmp put_mem
.named:
    shl eax, 4
    mov rsi, [timeout_names + rax]
    mov edx, [timeout_names + rax + 8]
    jmp put_mem
