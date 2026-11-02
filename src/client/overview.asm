; Team settings' Overview tab: the team's numbers, its issues by status, how
; many hold each role, the newest of the audit log for those who may see
; it, and deleting the team, for owners. It's all from what we already have
; for the open team, so it follows every change as it arrives.

%define TILE_W          ((SETTINGS_W - 56 - 3 * 12) / 4)
%define TILE_H          64
%define TILES_H         88              ; the tiles and the gap under them
%define BAR_ROW_H       26
%define BAR_X           170             ; where a row's bar starts, from the dialog's x
%define BAR_W           (SETTINGS_W - BAR_X - 28 - 48)
%define SECTION_HEAD    30              ; a section's heading, above its rows
%define SECTION_GAP     16
%define STATUS_H        (SECTION_HEAD + STATUS_COUNT * BAR_ROW_H + SECTION_GAP)
%define RECENT_SHOWN    3               ; audit entries the overview shows
%define DELETE_H        146             ; the Delete team section
%define KEY_FIELD_W     160

section .rodata
text s_stat_online,     "Online"
text s_stat_open,       "Open issues"
text s_by_status,       "Issues by status"
text s_owners,          "Owners"
text s_recent,          "Recent activity"
text s_view_all,        "View all"
text s_delete_team,     "Delete team"
text s_delete_team_sure, "Delete team?"
text s_delete_team_hint, "Deletes every issue, comment, channel and message in the team, for everyone."
text s_type_key,        "Type "
text s_to_confirm,      " to confirm"
text st_type_key,       "type the team's key to delete it"

section .bss
delete_key_buf: resb TEAM_KEY_MAX
team_delete_armed: resb 1               ; Delete team was clicked once
alignb 4
status_counts:  resd STATUS_COUNT

section .text

; Counts the team's issues by status into status_counts.
; -> eax = the biggest count, at least 1
count_statuses:
    lea rdi, [status_counts]
    mov esi, STATUS_COUNT * 4
    call wipe
    lea rcx, [view_issues]
    mov edx, [view_count]
.issue:
    test edx, edx
    jz .most
    movzx eax, byte [rcx + CI_STATUS]
    cmp eax, STATUS_COUNT
    jae .next
    inc dword [status_counts + rax * 4]
.next:
    add rcx, CI_SIZE
    dec edx
    jmp .issue
.most:
    mov eax, 1
    xor ecx, ecx
.status:
    cmp eax, [status_counts + rcx * 4]
    cmovb eax, [status_counts + rcx * 4]
    inc ecx
    cmp ecx, STATUS_COUNT
    jb .status
    ret

; edi = role slot, -1 for owners -> eax = how many members have it
count_holders:
    lea rcx, [members]
    mov edx, [member_count]
    xor eax, eax
.member:
    test edx, edx
    jz .done
    cmp edi, -1
    je .owner
    movzx r8d, word [rcx + CM_ROLES]
    bt r8d, edi
    jnc .next
    inc eax
    jmp .next
.owner:
    cmp byte [rcx + CM_ROLE], ROLE_OWNER
    jne .next
    inc eax
.next:
    add rcx, CM_SIZE
    dec edx
    jmp .member
.done:
    ret

; -> eax = how many members have the team open
count_online:
    lea rcx, [members]
    mov edx, [member_count]
    xor eax, eax
.member:
    test edx, edx
    jz .done
    movzx r8d, byte [rcx + CM_ONLINE]
    add eax, r8d
    add rcx, CM_SIZE
    dec edx
    jmp .member
.done:
    ret

; -> eax = 1 if the overview shows the newest of the audit log
recent_shown:
    mov edi, PERM_VIEW_AUDIT
    jmp has_perm

; -> eax = how many audit entries the overview shows, at least 1 row for saying there are none
recent_rows:
    mov eax, [audit_count]
    mov ecx, RECENT_SHOWN
    cmp eax, ecx
    cmova eax, ecx
    mov ecx, 1
    test eax, eax
    cmovz eax, ecx
    ret

; -> eax = the Overview tab's height, as draw_overview lays it out
overview_height:
    push rbx
    mov eax, [role_count]
    inc eax                                 ; the owners
    imul ebx, eax, BAR_ROW_H
    add ebx, TILES_H + STATUS_H + SECTION_HEAD + SECTION_GAP
    call recent_shown
    test eax, eax
    jz .delete
    call recent_rows
    imul eax, eax, LIST_ROW_H
    lea ebx, [ebx + eax + SECTION_HEAD + SECTION_GAP]
.delete:
    call am_owner
    imul eax, eax, DELETE_H
    add eax, ebx
    pop rbx
    ret

; One number in a box, with what it counts under it. edi = x, esi = y,
; edx = the number, rcx = label, r8d = its length
draw_stat_tile:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14, rcx
    mov r15d, r8d
    mov edi, ebx
    mov esi, r12d
    mov edx, TILE_W
    mov ecx, TILE_H
    mov r8d, C_LINE
    mov r9d, C_PANEL
    mov r10d, 8
    call outline_rrect
    lea rdi, [scratch]
    mov esi, r13d
    call put_u32
    mov rcx, rdi
    lea edi, [ebx + 14]
    lea esi, [r12d + 32]
    mov r8d, INK(C_TEXT, ST_TITLE)
    call draw_scratch
    lea edi, [ebx + 14]
    lea esi, [r12d + 52]
    mov rdx, r14
    mov ecx, r15d
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_text
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Members, who's online, open issues and done ones. edi = x, esi = top
draw_stat_tiles:
    push rbx
    push r12
    push r13
    mov ebx, edi
    lea r12d, [esi + 8]
    call count_statuses
    lea edi, [ebx + 28]
    mov esi, r12d
    mov edx, [member_count]
    lea rcx, [s_members]
    mov r8d, s_members_len
    call draw_stat_tile
    call count_online
    lea edi, [ebx + 28 + TILE_W + 12]
    mov esi, r12d
    mov edx, eax
    lea rcx, [s_stat_online]
    mov r8d, s_stat_online_len
    call draw_stat_tile
    mov edx, [status_counts + STATUS_BACKLOG * 4]
    add edx, [status_counts + STATUS_TODO * 4]
    add edx, [status_counts + STATUS_IN_PROGRESS * 4]
    lea edi, [ebx + 28 + 2 * (TILE_W + 12)]
    mov esi, r12d
    lea rcx, [s_stat_open]
    mov r8d, s_stat_open_len
    call draw_stat_tile
    lea edi, [ebx + 28 + 3 * (TILE_W + 12)]
    mov esi, r12d
    mov edx, [status_counts + STATUS_DONE * 4]
    lea rcx, [s_done]
    mov r8d, s_done_len
    call draw_stat_tile
    pop r13
    pop r12
    pop rbx
    ret

; A section's heading. edi = the dialog's x, esi = the section's top, rdx = text, ecx = length
draw_section_head:
    add edi, 28
    add esi, 20
    mov r8d, INK(C_DIM, ST_SMALL)
    jmp draw_text

; A row's bar, filled as far as its count goes, and the count at the right.
; edi = the dialog's x, esi = the row's top, edx = count, ecx = the count
; that fills it, r8d = color
draw_count_bar:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    lea edi, [ebx + BAR_X]
    lea esi, [r12d + 9]
    mov edx, BAR_W
    mov ecx, 8
    mov r8d, C_LINE
    mov r9d, 4
    call fill_rrect
    test r13d, r13d
    jz .count
    imul eax, r13d, BAR_W
    xor edx, edx
    div r14d
    mov edx, 8                              ; a sliver still shows as a pill
    cmp eax, edx
    cmovb eax, edx
    mov edx, eax
    lea edi, [ebx + BAR_X]
    lea esi, [r12d + 9]
    mov ecx, 8
    mov r8d, r15d
    mov r9d, 4
    call fill_rrect
.count:
    lea rdi, [scratch]
    mov esi, r13d
    call put_u32
    lea rdx, [scratch]
    mov rcx, rdi
    sub rcx, rdx
    lea edi, [ebx + SETTINGS_W - 28]
    lea esi, [r12d + 17]
    mov r8d, C_DIM
    call draw_link
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Issues by status, each a bar scaled to the biggest. edi = x, esi = top
draw_status_bars:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    lea rdx, [s_by_status]
    mov ecx, s_by_status_len
    call draw_section_head
    call count_statuses
    mov [rsp], eax
    lea ebp, [r12d + SECTION_HEAD]
    xor r13d, r13d
.status:
    lea edi, [ebx + 28]
    lea esi, [ebp + 5]
    mov edx, r13d
    mov ecx, C_RAISED
    call draw_status_icon
    mov edi, r13d
    call status_name
    mov ecx, edx
    mov rdx, rsi
    lea edi, [ebx + 52]
    lea esi, [ebp + 17]
    mov r8d, INK(C_TEXT, ST_BODY)
    call draw_text
    mov edi, ebx
    mov esi, ebp
    mov edx, [status_counts + r13 * 4]
    mov ecx, [rsp]
    mov r8d, C_ACCENT
    call draw_count_bar
    add ebp, BAR_ROW_H
    inc r13d
    cmp r13d, STATUS_COUNT
    jb .status
    add rsp, 8
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The owners, then each role highest first, with how much of the team has
; it. edi = x, esi = top -> eax = the y under them
draw_role_holders:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov ebx, edi
    mov r12d, esi
    lea rdx, [s_tab_roles]
    mov ecx, s_tab_roles_len
    call draw_section_head
    lea ebp, [r12d + SECTION_HEAD]
    lea edi, [ebx + 35]
    lea esi, [ebp + 13]
    mov edx, 5
    mov ecx, C_ACCENT_HI
    call fill_disc
    lea edi, [ebx + 52]
    lea esi, [ebp + 17]
    lea rdx, [s_owners]
    mov ecx, s_owners_len
    mov r8d, INK(C_TEXT, ST_BODY)
    call draw_text
    mov edi, -1
    call count_holders
    mov edi, ebx
    mov esi, ebp
    mov edx, eax
    mov ecx, [member_count]
    mov r8d, C_ACCENT_HI
    call draw_count_bar
    add ebp, BAR_ROW_H
    mov r13d, [role_count]
.role:
    test r13d, r13d
    jz .done
    mov edi, r13d                           ; positions run from the role count down to 1
    call role_at_pos
    test rax, rax
    jz .next
    mov r14, rax
    lea edi, [ebx + 35]
    lea esi, [ebp + 13]
    mov edx, 5
    mov ecx, [r14 + RO_COLOR]
    call fill_disc
    lea edi, [ebx + 52]
    lea esi, [ebp + 17]
    lea rdx, [r14 + RO_NAME]
    movzx ecx, byte [r14 + RO_NAME_LEN]
    mov r8d, INK(C_TEXT, ST_BODY)
    mov r9d, BAR_X - 52 - 12
    call draw_text_fit
    movzx edi, byte [r14 + RO_SLOT]
    call count_holders
    mov edi, ebx
    mov esi, ebp
    mov edx, eax
    mov ecx, [member_count]
    mov r8d, [r14 + RO_COLOR]
    call draw_count_bar
    add ebp, BAR_ROW_H
.next:
    dec r13d
    jmp .role
.done:
    lea eax, [ebp + SECTION_GAP]
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The newest audit entries, with View all for the rest. edi = x, esi = top
; -> eax = the y under them
draw_recent:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov ebx, edi
    mov r12d, esi
    lea rdx, [s_recent]
    mov ecx, s_recent_len
    call draw_section_head
    lea edi, [ebx + SETTINGS_W - 28]
    lea esi, [r12d + 20]
    lea rdx, [s_view_all]
    mov ecx, s_view_all_len
    mov r8d, A_TAB
    mov r9d, TAB_AUDIT
    call right_link
    lea ebp, [r12d + SECTION_HEAD]
    call recent_rows
    mov r13d, eax
    cmp dword [audit_count], 0
    je .none
    lea r14, [audit_rows]
.entry:
    mov edi, ebx
    mov esi, ebp
    mov rdx, r14
    call draw_audit_row
    add ebp, LIST_ROW_H
    add r14, AL_SIZE
    dec r13d
    jnz .entry
    jmp .done
.none:
    lea edi, [ebx + 28]
    lea esi, [ebp + 26]
    lea rdx, [s_no_audit]
    mov ecx, s_no_audit_len
    mov r8d, INK(C_DIM, ST_BODY)
    call draw_text
    add ebp, LIST_ROW_H
.done:
    lea eax, [ebp + SECTION_GAP]
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Delete team, for owners: what it does, the key to type, and the button,
; which asks with a first click. edi = x, esi = top
draw_delete_team:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    call current_team_row
    test rax, rax
    jz .done
    mov r13, rax
    lea edi, [ebx + 28]
    mov esi, r12d
    mov edx, SETTINGS_W - 56
    mov ecx, 1
    mov r8d, C_LINE
    call fill_rect
    lea edi, [ebx + 28]
    lea esi, [r12d + 32]
    lea rdx, [s_delete_team]
    mov ecx, s_delete_team_len
    mov r8d, INK(C_DANGER, ST_MEDIUM)
    call draw_text
    lea edi, [ebx + 28]
    lea esi, [r12d + 54]
    lea rdx, [s_delete_team_hint]
    mov ecx, s_delete_team_hint_len
    mov r8d, INK(C_DIM, ST_SMALL)
    mov r9d, SETTINGS_W - 56
    call draw_text_fit
    lea rdi, [scratch]
    lea rsi, [s_type_key]
    mov edx, s_type_key_len
    call put_mem
    lea rsi, [r13 + CO_KEY]
    movzx edx, byte [r13 + CO_KEY_LEN]
    call put_mem
    lea rsi, [s_to_confirm]
    mov edx, s_to_confirm_len
    call put_mem
    mov rcx, rdi
    lea edi, [ebx + 28]
    lea esi, [r12d + 84]
    mov r8d, INK(C_DIM, ST_SMALL)
    call draw_scratch
    mov edi, F_DELETE_KEY
    lea esi, [ebx + 28]
    lea edx, [r12d + 94]
    mov ecx, KEY_FIELD_W
    call draw_field_box
    lea rdx, [s_delete_team]
    mov ecx, s_delete_team_len
    cmp byte [team_delete_armed], 0
    je .button
    lea rdx, [s_delete_team_sure]
    mov ecx, s_delete_team_sure_len
.button:
    lea edi, [ebx + 28 + KEY_FIELD_W + 12]
    lea esi, [r12d + 97]
    mov r8d, A_DELETE_TEAM
    mov r9d, BTN_DANGER
    call draw_button
.done:
    pop r13
    pop r12
    pop rbx
    ret

; The Overview tab. edi = x, esi = top
draw_overview:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    call draw_stat_tiles
    mov edi, ebx
    lea esi, [r12d + TILES_H]
    call draw_status_bars
    mov edi, ebx
    lea esi, [r12d + TILES_H + STATUS_H]
    call draw_role_holders
    mov r12d, eax
    call recent_shown
    test eax, eax
    jz .delete
    mov edi, ebx
    mov esi, r12d
    call draw_recent
    mov r12d, eax
.delete:
    call am_owner
    test eax, eax
    jz .done
    mov edi, ebx
    mov esi, r12d
    call draw_delete_team
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; rdi = typed text, rsi = the team's key, edx = length -> eax = 1 if they're
; the same letters, in either case
key_matches:
    xor eax, eax
.char:
    test edx, edx
    jz .same
    movzx ecx, byte [rdi]
    movzx r8d, byte [rsi]
    or ecx, 0x20                            ; keys are only letters, so this folds case and nothing else
    or r8d, 0x20
    cmp ecx, r8d
    jne .done
    inc rdi
    inc rsi
    dec edx
    jmp .char
.same:
    inc eax
.done:
    ret

; Delete team: needs the key typed, asks with a first click, sends with the second.
click_delete_team:
    push rbx
    push r12
    sub rsp, 8
    call current_team_row
    test rax, rax
    jz .done
    mov rbx, rax
    mov edi, F_DELETE_KEY
    call field_trimmed
    movzx eax, byte [rbx + CO_KEY_LEN]
    cmp eax, edx
    jne .wrong
    mov rdi, rsi
    lea rsi, [rbx + CO_KEY]
    call key_matches
    test eax, eax
    jz .wrong
    cmp byte [team_delete_armed], 0
    jne .send
    mov byte [team_delete_armed], 1
    jmp .done
.send:
    mov byte [team_delete_armed], 0
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_DELETE_TEAM
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    lea rsi, [rbx + CO_KEY]
    movzx edx, byte [rbx + CO_KEY_LEN]
    call wr_str
    call send_built
    jmp .done
.wrong:
    lea rsi, [st_type_key]
    mov edx, st_type_key_len
    call set_status
    mov edi, F_DELETE_KEY
    call set_focus
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret
