; The sidebar: the account, the teams with their views, the projects, the
; channels and direct messages.

section .bss
side_scroll:    resd 1
side_h:         resd 1                  ; last frame's height of the scrolling rows

section .text

; One sidebar row: highlight and hit region. side_selected marks the current
; one, but while a conversation is open only its row can be current.
; edi = y, esi = action, edx = arg. 28px tall. -> eax = the row's background
side_row:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, C_SELECT
    cmp byte [side_selected], 0
    je .hover
    cmp byte [chat_open], 0
    je .fill
    cmp r12d, A_CHAT
    je .fill
.hover:
    mov edi, r12d
    mov esi, r13d
    call hovering
    mov r14d, C_BG
    test eax, eax
    jz .hit
    mov r14d, C_HOVER
.fill:
    mov edi, 8
    mov esi, ebx
    mov edx, SIDEBAR_W - 16
    mov ecx, 28
    mov r8d, r14d
    mov r9d, 6
    call fill_rrect
.hit:
    mov edi, 8
    mov esi, ebx
    mov edx, SIDEBAR_W - 16
    mov ecx, 28
    mov r8d, r12d
    mov r9d, r13d
    call add_hit
    mov byte [side_selected], 0
    mov eax, r14d
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; A sidebar row that opens a conversation: current while it's open, with a
; dot when it has messages we haven't seen, or an "@" when one mentions us.
; edi = y, esi = peer, edx = the dot's x -> eax = the row's background, ecx = 1 if unread
chat_side_row:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    xor eax, eax
    cmp byte [chat_open], 0
    je .current
    cmp r12d, [chat_peer]
    sete al
.current:
    mov [side_selected], al
    mov edi, ebx
    mov esi, A_CHAT
    mov edx, r12d
    call side_row
    mov r14d, eax
    mov edi, r12d
    call find_unread
    xor ecx, ecx
    cmp eax, -1
    je .done
    mov edi, r12d
    call is_mentioned
    test eax, eax
    jz .dot
    mov edi, r13d
    mov esi, ebx
    call draw_mention_badge
    jmp .unread
.dot:
    lea edi, [r13d * 4]
    lea esi, [ebx * 4 + 56]
    mov edx, 12
    mov ecx, C_ACCENT_HI
    call aa_disc
.unread:
    mov ecx, 1
.done:
    mov eax, r14d
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Sidebar row text. edi = x, esi = row y, rdx = text, ecx = length
side_text:
    add esi, 19
    mov r8d, INK(C_TEXT, ST_BODY)
    mov r9d, SIDEBAR_W - 24
    sub r9d, edi
    jmp draw_text_fit

; A section heading. edi = y, rsi = text, edx = length
side_heading:
    mov ecx, edx
    mov rdx, rsi
    lea esi, [edi + 18]
    mov edi, 18
    mov r8d, INK(C_FAINT, ST_SMALL)
    jmp draw_text

; A "+" at the end of a section heading. edi = heading y, esi = action, edx = arg
side_plus:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov edi, esi
    mov esi, edx
    call hovering
    mov r8d, C_FAINT
    mov ecx, C_TEXT
    test eax, eax
    cmovnz r8d, ecx
    push r8
    push r8
    mov edi, SIDEBAR_W - 30
    lea esi, [ebx + 7]
    mov edx, 2
    mov ecx, 10
    call fill_rect
    mov edi, SIDEBAR_W - 34
    lea esi, [ebx + 11]
    mov edx, 10
    mov ecx, 2
    mov r8d, [rsp]
    call fill_rect
    pop r8
    pop r8
    mov edi, SIDEBAR_W - 40
    mov esi, ebx
    mov edx, 24
    mov ecx, 24
    mov r8d, r12d
    mov r9d, r13d
    call add_hit
    pop r13
    pop r12
    pop rbx
    ret

; The sidebar: who's logged in and the new issue button, then the teams,
; projects and members, which scroll when they don't fit.
draw_sidebar:
    push rbx
    push r12
    sub rsp, 8
    xor edi, edi
    xor esi, esi
    mov edx, SIDEBAR_W
    mov ecx, [win_h]
    sub ecx, 64
    call set_clip

    mov edi, 16                             ; who's logged in
    mov esi, 14
    mov edx, 20
    mov ecx, [my_id]
    lea r8, [my_name]
    call draw_avatar
    mov edi, 44
    mov esi, 29
    lea rdx, [my_name]
    mov ecx, [my_name_len]
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    mov r9d, SIDEBAR_W - 60
    call draw_text_fit

    mov r12d, 44                            ; where the scrolling rows start
    cmp dword [current_team], 0             ; nowhere to put a new issue yet
    je .rows
    mov edi, A_NEW_ISSUE                    ; the new issue button
    mov esi, -1
    call hovering
    mov r9d, C_RAISED
    mov ecx, C_SELECT
    test eax, eax
    cmovnz r9d, ecx
    mov edi, 10
    mov esi, 48
    mov edx, SIDEBAR_W - 20
    mov ecx, 32
    mov r8d, C_LINE
    mov r10d, 7
    call outline_rrect
    mov edi, 10
    mov esi, 48
    mov edx, SIDEBAR_W - 20
    mov ecx, 32
    mov r8d, A_NEW_ISSUE
    mov r9d, -1
    call add_hit
    mov dword [pi_item + MI_ICON], IC_PLUS
    lea rdi, [pi_item]
    mov esi, 22
    mov edx, 57
    call draw_item_icon
    mov edi, 44
    mov esi, 69
    lea rdx, [s_new_issue]
    mov ecx, s_new_issue_len
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    mov edi, SIDEBAR_W - 40
    mov esi, 55
    mov edx, 'C'
    call draw_keycap

    mov r12d, 88
.rows:
    xor edi, edi
    mov esi, r12d
    mov edx, SIDEBAR_W
    mov ecx, [win_h]
    sub ecx, 64
    call set_clip
    lea rdi, [side_scroll]
    mov esi, [win_h]
    sub esi, 64
    sub esi, r12d
    mov edx, [side_h]
    call clamp_scroll_to
    lea ebx, [r12d + 4]
    sub ebx, [side_scroll]
    mov edi, ebx
    call draw_side_teams
    cmp dword [current_team], 0
    je .measured
    mov edi, eax
    call draw_side_projects
    mov edi, eax
    call draw_side_channels
    mov edi, eax
    call draw_side_members
.measured:
    sub eax, ebx
    add eax, 8
    mov [side_h], eax

    call reset_clip
    mov edi, 8
    mov esi, [win_h]
    sub esi, 60
    mov edx, SIDEBAR_W - 16
    mov ecx, 1
    mov r8d, C_LINE
    call fill_rect
    mov edi, A_LOGOUT
    xor esi, esi
    call hovering
    mov r8d, INK(C_DIM, ST_SMALL)
    mov ecx, INK(C_TEXT, ST_SMALL)
    test eax, eax
    cmovnz r8d, ecx
    mov edi, 16
    mov esi, [win_h]
    sub esi, 40
    lea rdx, [s_log_out]
    mov ecx, s_log_out_len
    call draw_text
    mov edi, 8
    mov esi, [win_h]
    sub esi, 56
    mov edx, 80
    mov ecx, 24
    mov r8d, A_LOGOUT
    xor r9d, r9d
    call add_hit
    mov edi, 16
    mov esi, [win_h]
    sub esi, 16
    mov edx, SIDEBAR_W - 24
    call draw_net_status
    add rsp, 8
    pop r12
    pop rbx
    ret

; "My issues", then each team, with the current one's views and channel.
; edi = top -> eax = the y under them
draw_side_teams:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov ebx, edi
    cmp dword [current_team], 0
    je .teams
    cmp dword [view_mode], V_MINE
    sete byte [side_selected]
    mov edi, ebx
    mov esi, A_VIEW
    mov edx, V_MINE
    call side_row
    mov edi, GL_PERSON
    mov esi, 18
    lea edx, [ebx + 7]
    mov ecx, C_DIM
    call draw_glyph
    mov edi, 44
    mov esi, ebx
    lea rdx, [s_my_issues]
    mov ecx, s_my_issues_len
    call side_text
    add ebx, 40

.teams:
    mov edi, ebx
    lea rsi, [s_your_teams]
    mov edx, s_your_teams_len
    call side_heading
    mov edi, ebx                            ; "+" to make another
    mov esi, A_NEW_TEAM
    xor edx, edx
    call side_plus
    add ebx, 28

    lea r12, [teams]
    mov r13d, [team_count]
.team:
    test r13d, r13d
    jz .done
    mov edi, ebx
    mov esi, A_TEAM
    mov edx, [r12 + CO_ID]
    call side_row
    mov edi, 16                             ; the team's badge
    lea esi, [ebx + 5]
    mov edx, 18
    mov ecx, 18
    mov r8d, C_ACCENT
    mov r9d, 5
    call fill_rrect
    ; The name's first letter, so a renamed team's badge follows it.
    movzx eax, byte [r12 + CO_NAME]
    lea ecx, [eax - 'a']
    cmp ecx, 25
    ja .upper
    sub eax, 32
.upper:
    mov [rsp], al
    mov rdi, rsp
    mov esi, 1
    mov edx, ST_SMALL
    call text_width
    mov edi, 18
    sub edi, eax
    sar edi, 1
    add edi, 16
    lea esi, [ebx + 18]
    mov rdx, rsp
    mov ecx, 1
    mov r8d, INK(0xffffff, ST_SMALL)
    call draw_text
    mov r9d, SIDEBAR_W - 60
    mov eax, [r12 + CO_ID]
    cmp eax, [current_team]
    jne .name
    mov edi, ebx
    mov esi, eax
    call draw_settings_link
    mov r9d, SIDEBAR_W - 44 - 44            ; the name stops short of it
.name:
    mov edi, 44
    lea esi, [ebx + 19]
    lea rdx, [r12 + CO_NAME]
    movzx ecx, byte [r12 + CO_NAME_LEN]
    mov r8d, INK(C_TEXT, ST_BODY)
    call draw_text_fit
    add ebx, 30
    mov eax, [r12 + CO_ID]
    cmp eax, [current_team]
    jne .next_team
    mov edi, ebx
    call draw_team_views
    mov ebx, eax
.next_team:
    add r12, CO_SIZE
    dec r13d
    jmp .team
.done:
    mov eax, ebx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; The settings button at the end of the current team's row, which only
; shows while the row or the button is under the pointer.
; edi = row y, esi = the team
draw_settings_link:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov edi, A_SETTINGS
    mov esi, F_NONE
    call hovering
    mov r13d, eax
    test eax, eax
    jnz .draw
    mov edi, A_TEAM
    mov esi, r12d
    call hovering
    test eax, eax
    jz .hit
.draw:
    test r13d, r13d
    jz .glyph
    mov edi, SIDEBAR_W - 41
    lea esi, [ebx + 2]
    mov edx, 24
    mov ecx, 24
    mov r8d, C_LINE
    mov r9d, 5
    call fill_rrect
.glyph:
    mov edi, GL_SETTINGS
    mov esi, SIDEBAR_W - 36
    lea edx, [ebx + 7]
    mov ecx, C_DIM
    mov eax, C_TEXT
    test r13d, r13d
    cmovnz ecx, eax
    call draw_glyph
.hit:
    mov edi, SIDEBAR_W - 41
    lea esi, [ebx + 2]
    mov edx, 24
    mov ecx, 24
    mov r8d, A_SETTINGS
    mov r9d, F_NONE
    call add_hit
    pop r13
    pop r12
    pop rbx
    ret

; The current team's views, indented.
; edi = top -> eax = the y under them
draw_team_views:
    push rbx
    push r14
    sub rsp, 8
    mov ebx, edi
    xor r14d, r14d
.team_view:
    cmp r14d, V_MINE
    jae .views_done
    cmp [view_mode], r14d
    jne .not_current
    cmp dword [filter_project], 0
    sete byte [side_selected]
.not_current:
    mov edi, ebx
    mov esi, A_VIEW
    mov edx, r14d
    call side_row
    lea edi, [r14d + GL_ISSUES]             ; V_ALL, V_ACTIVE and V_BACKLOG in order
    mov esi, 30
    lea edx, [ebx + 7]
    mov ecx, C_DIM
    call draw_glyph
    lea rdi, [s_issues]
    mov esi, s_issues_len
    cmp r14d, V_ALL
    je .view_text
    lea rdi, [s_active]
    mov esi, s_active_len
    cmp r14d, V_ACTIVE
    je .view_text
    lea rdi, [s_backlog]
    mov esi, s_backlog_len
.view_text:
    mov rdx, rdi
    mov ecx, esi
    mov edi, 54
    mov esi, ebx
    call side_text
    add ebx, 30
    inc r14d
    jmp .team_view
.views_done:
    mov eax, ebx
    add rsp, 8
    pop r14
    pop rbx
    ret

; The team's projects, under a heading if it has any.
; edi = top -> eax = the y under them
draw_side_projects:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    add ebx, 12
    lea r12, [view_projects]
    mov r13d, 1
    mov r14d, ebx                           ; heading goes here if there are any
    add ebx, 28
.project:
    cmp r13d, PROJECT_SLOTS
    ja .projects_done
    cmp byte [r12 + LB_NAME_LEN], 0
    je .next_project
    cmp [filter_project], r13d
    sete byte [side_selected]
    mov edi, ebx
    mov esi, A_PROJECT
    mov edx, r13d
    call side_row
    mov edi, 4 * 25
    lea esi, [ebx * 4 + 56]
    mov edx, 18
    mov ecx, [r12 + LB_COLOR]
    call aa_disc
    mov edi, 44
    mov esi, ebx
    lea rdx, [r12 + LB_NAME]
    movzx ecx, byte [r12 + LB_NAME_LEN]
    call side_text
    add ebx, 30
.next_project:
    add r12, PJ_SIZE
    inc r13d
    jmp .project
.projects_done:
    lea eax, [r14d + 28]
    cmp ebx, eax
    jne .project_heading
    lea ebx, [r14d - 12]                    ; no projects, no heading and no gap
    jmp .done
.project_heading:
    mov edi, r14d
    lea rsi, [s_projects]
    mov edx, s_projects_len
    call side_heading
.done:
    mov eax, ebx
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Everyone else on the team, each row opening a conversation with them.
; Owners and moderators get a "+" to invite people, and an invite row while they're alone.
; edi = top -> eax = the y under them
draw_side_members:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    lea ebx, [edi + 12]
    mov edi, PERM_INVITE
    call has_perm
    mov ebp, eax
    mov edi, ebx
    lea rsi, [s_direct_messages]
    mov edx, s_direct_messages_len
    call side_heading
    test ebp, ebp
    jz .heading_done
    mov edi, ebx
    mov esi, A_SETTINGS
    mov edx, F_MEMBER
    call side_plus
.heading_done:
    add ebx, 28
    lea r12, [members]
    mov r13d, [member_count]
    xor r15d, r15d                          ; rows drawn
.member:
    test r13d, r13d
    jz .alone
    mov eax, [r12 + CM_ID]
    cmp eax, [my_id]
    je .next_member
    mov edi, ebx                            ; the row opens a conversation with them
    mov esi, eax
    mov edx, SIDEBAR_W - 26
    call chat_side_row
    mov [rsp], eax                          ; the row's background
    mov r14d, INK(C_TEXT, ST_BODY)
    test ecx, ecx
    jz .avatar
    mov r14d, INK(0xffffff, ST_MEDIUM)      ; unread
.avatar:
    mov edi, 16
    lea esi, [ebx + 5]
    mov edx, 18
    mov ecx, [r12 + CM_ID]
    lea r8, [r12 + CM_NAME]
    call draw_avatar
    mov edi, 4 * 31                         ; online dot on the avatar's corner
    lea esi, [ebx * 4 + 4 * 21]
    mov edx, 14
    mov ecx, [rsp]
    call aa_disc
    mov ecx, C_ONLINE
    cmp byte [r12 + CM_ONLINE], 0
    jne .dot
    mov ecx, C_FAINT
.dot:
    mov edi, 4 * 31
    lea esi, [ebx * 4 + 4 * 21]
    mov edx, 9
    call aa_disc
    mov edi, 44
    lea esi, [ebx + 19]
    lea rdx, [r12 + CM_NAME]
    movzx ecx, byte [r12 + CM_NAME_LEN]
    mov r8d, r14d
    mov r9d, SIDEBAR_W - 86
    call draw_text_fit
    add ebx, 28
    inc r15d
.next_member:
    add r12, CM_SIZE
    dec r13d
    jmp .member
.alone:
    test r15d, r15d
    jnz .done
    test ebp, ebp
    jz .done
    mov edi, ebx
    mov esi, A_SETTINGS
    mov edx, F_MEMBER
    call side_row
    mov dword [pi_item + MI_ICON], IC_PLUS
    lea rdi, [pi_item]
    mov esi, 16
    lea edx, [ebx + 5]
    call draw_item_icon
    mov edi, 44
    mov esi, ebx
    lea rdx, [s_invite_people]
    mov ecx, s_invite_people_len
    call side_text
    add ebx, 28
.done:
    mov eax, ebx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
