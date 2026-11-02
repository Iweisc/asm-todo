; Issues, comments, labels and projects, and the sync that carries them.
;
; The server is the single source of truth and applies ops one at a time.
; Every change to a team bumps its seq and goes out as an EVENT to everyone
; viewing the team. Each session numbers its ops 1, 2, 3...; the server
; remembers the highest one applied, so an op resent after a dropped
; connection is acknowledged instead of applied twice.

%define SNAPSHOT_CHUNK  15000

section .bss
; The op being applied, as h_op parsed it.
op_team:        resq 1                      ; team row
op_user:        resd 1
op_issue:       resd 1                      ; or who a message goes to
op_field:       resd 1                      ; or a label or project slot
op_value:       resd 1                      ; or a color
op_status:      resd 1
op_priority:    resd 1
op_assignee:    resd 1
op_project:     resd 1
op_labels:      resd 1
op_text_len:    resd 1
op_body_len:    resd 1
op_image:       resd 1                      ; a comment's or message's, 0 for none
op_text:        resq 1                      ; a title or name
op_body:        resq 1                      ; a description, comment or message

section .rodata
align 8
op_handlers:
    dq 0, op_create_issue, op_set_field, op_delete_issue, op_comment, op_set_label, op_set_project
    dq op_message, op_edit_comment, op_delete_comment
OP_KINDS equ ($ - op_handlers) / 8

section .text

; rdi = cursor, rsi = issue row -> rdi advanced. The wire layout is in config.inc.
wr_issue:
    push rbx
    mov rbx, rsi
    mov esi, [rbx + ISS_ID]
    call wr_u32
    mov esi, [rbx + ISS_NUMBER]
    call wr_u32
    movzx esi, byte [rbx + ISS_STATUS]
    call wr_u8
    movzx esi, byte [rbx + ISS_PRIORITY]
    call wr_u8
    mov esi, [rbx + ISS_ASSIGNEE]
    call wr_u32
    movzx esi, byte [rbx + ISS_PROJECT]
    call wr_u8
    movzx esi, word [rbx + ISS_LABELS]
    call wr_u16
    mov esi, [rbx + ISS_CREATOR]
    call wr_u32
    mov esi, [rbx + ISS_CREATED]
    call wr_u32
    mov esi, [rbx + ISS_UPDATED]
    call wr_u32
    lea rsi, [rbx + ISS_TITLE]
    movzx edx, byte [rbx + ISS_TITLE_LEN]
    call wr_str
    pop rbx
    ret

; rdi = cursor, rsi = label or project slot -> rdi advanced. u32 color, str name
wr_named:
    push rbx
    mov rbx, rsi
    mov esi, [rbx]
    call wr_u32
    movzx edx, byte [rbx + 4]
    lea rsi, [rbx + 5]
    call wr_str
    pop rbx
    ret

; Sends a team's labels and projects. edi = connection index, rsi = team row
send_team_meta:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov rbx, rsi
    lea rdi, [msg_buf]
    mov esi, MSG_TEAM_META
    call wr_u8
    mov esi, [rbx + TEAM_ID]
    call wr_u32
    xor r13d, r13d
.label:
    imul esi, r13d, LABEL_SIZE
    lea rsi, [rbx + TEAM_LABELS + rsi]
    call wr_named
    inc r13d
    cmp r13d, LABEL_SLOTS
    jb .label
    xor r13d, r13d
.project:
    imul esi, r13d, PROJ_SIZE
    lea rsi, [rbx + TEAM_PROJECTS + rsi]
    call wr_named
    inc r13d
    cmp r13d, PROJECT_SLOTS
    jb .project
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    mov edi, r12d
    call send_msg
    pop r13
    pop r12
    pop rbx
    ret

; Sends a team's labels and projects, then its issues in chunks. The first
; chunk replaces what the client had, the last one says the snapshot is
; complete. edi = index, esi = team
send_snapshot:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov [rsp], edi
    mov r12d, esi
    mov edi, r12d
    call find_team
    mov r13d, [rax + TEAM_SEQ]
    mov edi, [rsp]
    mov rsi, rax
    call send_team_meta
    mov byte [rsp + 4], 1                   ; first chunk
    lea rbx, [issues]
    mov ebp, [n_issues]
.chunk:
    lea rdi, [msg_buf]
    mov esi, MSG_SNAPSHOT
    call wr_u8
    mov esi, r12d
    call wr_u32
    mov esi, r13d
    call wr_u32
    movzx esi, byte [rsp + 4]
    call wr_u8
    mov r14, rdi                            ; "last" flag, then the u16 count
    add rdi, 3
    xor r15d, r15d
.row:
    test ebp, ebp
    jz .final
    lea rax, [msg_buf + SNAPSHOT_CHUNK]
    cmp rdi, rax
    jae .flush
    cmp [rbx + ISS_TEAM], r12d
    jne .skip
    mov rsi, rbx
    call wr_issue
    inc r15d
.skip:
    add rbx, ISSUE_SIZE
    dec ebp
    jmp .row
.flush:
    mov byte [r14], 0
    mov [r14 + 1], r15w
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    mov edi, [rsp]
    call send_msg
    mov byte [rsp + 4], 0
    jmp .chunk
.final:
    mov byte [r14], 1
    mov [r14 + 1], r15w
    lea rsi, [msg_buf]
    mov rdx, rdi
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

h_subscribe:
    push rbx
    push r12
    sub rsp, 8
    call rd_u32
    mov r12d, eax
    call rd_ok
    test eax, eax
    jz .violation
    mov rax, [cur]
    mov edi, r12d
    mov esi, [rax + C_USER]
    call find_member
    test rax, rax
    jz .not_member
    mov rax, [cur]
    mov ebx, [rax + C_TEAM]
    mov [rax + C_TEAM], r12d
    and byte [rax + C_FLAGS], ~F_CHAT       ; conversations belong to the team left behind
    mov edi, [cur_idx]
    mov esi, r12d
    call send_snapshot
    mov edi, r12d
    call build_roles
    mov edi, [cur_idx]
    lea rsi, [msg_buf]
    call send_msg
    mov edi, [cur_idx]
    mov esi, r12d
    call send_channels
    mov rax, [cur]
    mov edi, [cur_idx]
    mov esi, r12d
    mov edx, [rax + C_USER]
    call send_unread
    mov edi, r12d
    mov esi, [cur_idx]
    call send_moderation
    mov edi, r12d
    call broadcast_members
    test ebx, ebx
    jz .done
    cmp ebx, r12d
    je .done
    mov edi, ebx                            ; and they've left the team they were viewing
    call broadcast_members
    jmp .done
.violation:
    call kill_cur
    jmp .done
.not_member:
    lea rsi, [e_not_member]
    mov edx, e_not_member_len
    call send_error
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; rdi = cursor, rsi = comment row -> rdi advanced
wr_comment:
    push rbx
    mov rbx, rsi
    mov esi, [rbx + CMT_ID]
    call wr_u32
    mov esi, [rbx + CMT_AUTHOR]
    call wr_u32
    mov esi, [rbx + CMT_CREATED]
    call wr_u32
    lea rsi, [rbx + CMT_TEXT]
    movzx edx, word [rbx + CMT_LEN]
    call wr_str16
    movzx esi, byte [rbx + CMT_EDITED]
    call wr_u8
    mov esi, IMAGE_ON_COMMENT
    mov edx, [rbx + CMT_ID]
    call wr_image_ref
    pop rbx
    ret

; An issue's description and comments, oldest comment first. Only for the
; team the connection is viewing. An issue that's gone gets no answer: the
; client hears about the deletion anyway.
h_open_issue:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    call rd_u32
    mov r12d, eax
    call rd_ok
    test eax, eax
    jz .violation
    mov edi, r12d
    call find_issue
    test rax, rax
    jz .done
    mov rbx, rax
    mov rcx, [cur]
    mov ecx, [rcx + C_TEAM]
    cmp [rbx + ISS_TEAM], ecx
    jne .done
    lea rdi, [msg_buf]
    mov esi, MSG_ISSUE_DETAIL
    call wr_u8
    mov esi, r12d
    call wr_u32
    lea rsi, [rbx + ISS_DESC]
    movzx edx, word [rbx + ISS_DESC_LEN]
    call wr_str16
    mov r14, rdi                            ; count goes here
    inc rdi
    mov r15, rdi
    xor r13d, r13d                          ; comments written
    xor ebp, ebp                            ; the last id written
    ; Slots get reused, so table order isn't age order. Comment ids only
    ; grow, so pick the next-lowest id each round. 100 rounds at most.
.round:
    lea rax, [comments]
    mov ecx, [n_comments]
    xor ebx, ebx                            ; best row this round
.scan:
    test ecx, ecx
    jz .picked
    cmp [rax + CMT_ISSUE], r12d
    jne .next
    cmp [rax + CMT_ID], ebp
    jbe .next
    test rbx, rbx
    jz .better
    mov edx, [rax + CMT_ID]
    cmp edx, [rbx + CMT_ID]
    jae .next
.better:
    mov rbx, rax
.next:
    add rax, CMT_SIZE
    dec ecx
    jmp .scan
.picked:
    test rbx, rbx
    jz .send
    mov ebp, [rbx + CMT_ID]
    mov rdi, r15
    mov rsi, rbx
    call wr_comment
    mov r15, rdi
    inc r13d
    cmp r13d, ISSUE_COMMENT_MAX
    jb .round
.send:
    mov [r14], r13b
    lea rsi, [msg_buf]
    mov rdx, r15
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

; edi = op number, esi = status
send_ack:
    push rbx
    mov ebx, esi
    mov esi, edi
    lea rdi, [msg_buf]
    push rsi
    mov esi, MSG_ACK
    call wr_u8
    pop rsi
    call wr_u32
    mov esi, ebx
    call wr_u8
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    pop rbx
    jmp reply

; Starts an EVENT. rdi = team row, esi = event kind, edx = its seq
; -> rdi = cursor for the event's fields
begin_event_seq:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    lea rdi, [msg_buf]
    mov esi, MSG_EVENT
    call wr_u8
    mov esi, [rbx + TEAM_ID]
    call wr_u32
    mov esi, r13d
    call wr_u32
    mov esi, r12d
    call wr_u8
    pop r13
    pop r12
    pop rbx
    ret

; The same, for a team whose seq was just bumped.
begin_event:
    mov edx, [rdi + TEAM_SEQ]
    jmp begin_event_seq

; rdi = end of the event, esi = team id
finish_event:
    lea rax, [msg_buf]
    mov rdx, rdi
    sub rdx, rax
    mov edi, esi
    mov rsi, rax
    jmp broadcast_team

; Descriptions and comments: printable ASCII and newlines, possibly empty.
; rsi = text, edx = length, ecx = max length -> eax = 1 if acceptable
valid_body:
    xor eax, eax
    cmp edx, ecx
    ja .done
    xor ecx, ecx
.char:
    cmp ecx, edx
    jae .ok
    mov r8b, [rsi + rcx]
    inc ecx
    cmp r8b, 10
    je .char
    cmp r8b, ' '
    jb .done
    cmp r8b, '~'
    jbe .char
    jmp .done
.ok:
    mov eax, 1
.done:
    ret

; edi = op kind. Reads the fields that kind has into op_*.
; -> eax = 1 if it's a kind we know
read_op:
    cmp edi, OP_CREATE_ISSUE
    je .create
    cmp edi, OP_SET_FIELD
    je .set
    cmp edi, OP_DELETE_ISSUE
    je .id
    cmp edi, OP_DELETE_COMMENT
    je .id
    cmp edi, OP_COMMENT
    je .attached
    cmp edi, OP_MESSAGE
    je .attached                            ; the same shape: u32, str16, u32
    cmp edi, OP_EDIT_COMMENT
    je .body
    cmp edi, OP_SET_LABEL
    je .named
    cmp edi, OP_SET_PROJECT
    je .named
    xor eax, eax
    ret
.named:
    call rd_u8
    mov [op_field], eax
    call rd_u32
    mov [op_value], eax
    call rd_str
    mov [op_text], rax
    mov [op_text_len], edx
    jmp .known
.create:
    call rd_u8
    mov [op_status], eax
    call rd_u8
    mov [op_priority], eax
    call rd_u32
    mov [op_assignee], eax
    call rd_u8
    mov [op_project], eax
    call rd_u16
    mov [op_labels], eax
    call rd_str
    mov [op_text], rax
    mov [op_text_len], edx
    jmp .read_body
.attached:
    call rd_u32
    mov [op_issue], eax
    call rd_str16
    mov [op_body], rax
    mov [op_body_len], edx
    call rd_u32
    mov [op_image], eax
    jmp .known
.body:
    call rd_u32
    mov [op_issue], eax
.read_body:
    call rd_str16
    mov [op_body], rax
    mov [op_body_len], edx
    jmp .known
.set:
    call rd_u32
    mov [op_issue], eax
    call rd_u8
    mov [op_field], eax
    cmp eax, FIELD_TITLE
    je .title
    cmp eax, FIELD_DESCRIPTION
    je .read_body
    call rd_u32
    mov [op_value], eax
    jmp .known
.title:
    call rd_str
    mov [op_text], rax
    mov [op_text_len], edx
    jmp .known
.id:
    call rd_u32
    mov [op_issue], eax
.known:
    mov eax, 1
    ret

; MSG_OP: applies one change, in the order the session numbered them.
h_op:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    call rd_u32
    mov r12d, eax                           ; op number
    call rd_u8
    mov r13d, eax                           ; kind
    call rd_u32
    mov r14d, eax                           ; team
    mov edi, r13d
    call read_op
    test eax, eax
    jz .violation
    call rd_ok
    test eax, eax
    jz .violation

    mov rax, [cur]
    mov eax, [rax + C_SESSION]
    imul eax, eax, SESS_SIZE
    lea rbx, [sessions + rax]
    mov eax, [rbx + SESS_LAST_OP]
    cmp r12d, eax
    jbe .duplicate
    inc eax
    cmp r12d, eax
    jne .violation                          ; ops must arrive in order without gaps
    mov [rbx + SESS_LAST_OP], r12d
    mov edi, T_SESSIONS
    mov rsi, rbx
    call db_touch

    mov rax, [cur]
    mov eax, [rax + C_USER]
    mov [op_user], eax
    mov edi, r14d
    mov esi, eax
    call find_member
    test rax, rax
    jz .forbidden
    mov rdi, rax
    call is_timed_out
    test eax, eax
    jnz .timed_out
    mov edi, r14d
    call find_team
    mov [op_team], rax
    ; The handler commits and broadcasts if it applies the op, and leaves
    ; the session's op number for us to commit if it doesn't.
    call [op_handlers + r13 * 8]
    mov ebx, eax
    test ebx, ebx
    jz .ack
    call db_commit
.ack:
    mov edi, r12d
    mov esi, ebx
    call send_ack
    jmp .done
.timed_out:
    mov ebx, ACK_TIMED_OUT
    jmp .refused
.forbidden:
    mov ebx, ACK_FORBIDDEN
.refused:
    call db_commit
    mov edi, r12d
    mov esi, ebx
    call send_ack
    jmp .done
.duplicate:
    mov edi, r12d
    mov esi, ACK_OK
    call send_ack
    jmp .done
.violation:
    call kill_cur
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; --- op handlers: -> eax = ACK status. They read op_* and the team row. ---

; Bumps the team's seq, commits, and starts the event. esi = event kind
; -> rdi = cursor for the event's fields
commit_event:
    push rbx
    mov ebx, esi
    mov rsi, [op_team]
    inc dword [rsi + TEAM_SEQ]
    mov edi, T_TEAMS
    call db_touch
    call db_commit
    mov rdi, [op_team]
    mov esi, ebx
    pop rbx
    jmp begin_event

; Sends the event that commit_event started. rdi = its end
send_event:
    mov rax, [op_team]
    mov esi, [rax + TEAM_ID]
    jmp finish_event

; -> rax = the op's issue if it's in the op's team, else 0
op_find_issue:
    mov edi, [op_issue]
    call find_issue
    test rax, rax
    jz .done
    mov rcx, [op_team]
    mov ecx, [rcx + TEAM_ID]
    cmp [rax + ISS_TEAM], ecx
    je .done
    xor eax, eax
.done:
    ret

; edi = user -> eax = 1 if nobody (0) or a member of the op's team
valid_assignee:
    mov eax, 1
    test edi, edi
    jz .done
    mov esi, edi
    mov rax, [op_team]
    mov edi, [rax + TEAM_ID]
    call find_member
    test rax, rax
    setnz al
    movzx eax, al
.done:
    ret

; edi = project -> eax = 1 if none (0) or a project the team has
valid_project:
    mov eax, 1
    test edi, edi
    jz .done
    xor eax, eax
    cmp edi, PROJECT_SLOTS
    ja .done
    dec edi
    imul edi, edi, PROJ_SIZE
    mov rcx, [op_team]
    cmp byte [rcx + TEAM_PROJECTS + rdi + PROJ_NAME_LEN], 0
    setne al
.done:
    ret

; edi = label bitmask -> eax = 1 if every bit is a label the team has
valid_labels:
    xor eax, eax
    cmp edi, 0xffff
    ja .done
    mov rcx, [op_team]
    lea rcx, [rcx + TEAM_LABELS]
    xor edx, edx
.slot:
    bt edi, edx
    jnc .next
    cmp byte [rcx + LABEL_NAME_LEN], 0
    je .done
.next:
    add rcx, LABEL_SIZE
    inc edx
    cmp edx, LABEL_SLOTS
    jb .slot
    mov eax, 1
.done:
    ret

op_create_issue:
    push rbx
    push r12
    sub rsp, 8
    cmp dword [op_status], STATUS_COUNT
    jae .invalid
    cmp dword [op_priority], PRIO_COUNT
    jae .invalid
    mov edi, [op_assignee]
    call valid_assignee
    test eax, eax
    jz .invalid
    mov edi, [op_project]
    call valid_project
    test eax, eax
    jz .invalid
    mov edi, [op_labels]
    call valid_labels
    test eax, eax
    jz .invalid
    mov rsi, [op_text]
    mov edx, [op_text_len]
    mov ecx, TITLE_MAX
    call valid_text
    test eax, eax
    jz .invalid
    mov rsi, [op_body]
    mov edx, [op_body_len]
    mov ecx, DESC_MAX
    call valid_body
    test eax, eax
    jz .invalid
    mov r12, [op_team]
    mov edi, T_ISSUES
    mov esi, ISS_TEAM
    mov edx, [r12 + TEAM_ID]
    call count_where
    cmp eax, TEAM_ISSUE_MAX
    jae .full
    mov edi, T_ISSUES
    call alloc_row
    test rax, rax
    jz .full
    mov rbx, rax
    mov eax, [next_issue_id]
    inc dword [next_issue_id]
    mov [rbx + ISS_ID], eax
    mov eax, [r12 + TEAM_ID]
    mov [rbx + ISS_TEAM], eax
    mov eax, [r12 + TEAM_NEXT_NUM]
    inc dword [r12 + TEAM_NEXT_NUM]
    mov [rbx + ISS_NUMBER], eax
    mov eax, [op_assignee]
    mov [rbx + ISS_ASSIGNEE], eax
    mov eax, [op_user]
    mov [rbx + ISS_CREATOR], eax
    call now_unix
    mov [rbx + ISS_CREATED], eax
    mov [rbx + ISS_UPDATED], eax
    mov eax, [op_labels]
    mov [rbx + ISS_LABELS], ax
    mov eax, [op_status]
    mov [rbx + ISS_STATUS], al
    mov eax, [op_priority]
    mov [rbx + ISS_PRIORITY], al
    mov eax, [op_project]
    mov [rbx + ISS_PROJECT], al
    mov ecx, [op_text_len]
    mov [rbx + ISS_TITLE_LEN], cl
    lea rdi, [rbx + ISS_TITLE]
    mov rsi, [op_text]
    rep movsb
    mov ecx, [op_body_len]
    mov [rbx + ISS_DESC_LEN], cx
    lea rdi, [rbx + ISS_DESC]
    mov rsi, [op_body]
    rep movsb
    mov edi, T_ISSUES
    mov rsi, rbx
    call db_touch
    mov esi, EV_ISSUE
    call commit_event
    mov rsi, rbx
    call wr_issue
    call send_event
    xor eax, eax
    jmp .done
.invalid:
    mov eax, ACK_INVALID
    jmp .done
.full:
    mov eax, ACK_FULL
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

op_set_field:
    push rbx
    push r12
    sub rsp, 8
    call op_find_issue
    test rax, rax
    jz .gone
    mov rbx, rax
    mov r12d, [op_value]
    mov eax, [op_field]
    cmp eax, FIELD_STATUS
    je .status
    cmp eax, FIELD_PRIORITY
    je .priority
    cmp eax, FIELD_ASSIGNEE
    je .assignee
    cmp eax, FIELD_PROJECT
    je .project
    cmp eax, FIELD_LABELS
    je .labels
    cmp eax, FIELD_TITLE
    je .title
    cmp eax, FIELD_DESCRIPTION
    jne .invalid
    mov rsi, [op_body]
    mov edx, [op_body_len]
    mov ecx, DESC_MAX
    call valid_body
    test eax, eax
    jz .invalid
    mov ecx, [op_body_len]
    mov [rbx + ISS_DESC_LEN], cx
    lea rdi, [rbx + ISS_DESC]
    mov rsi, [op_body]
    rep movsb
    call .touch
    mov esi, EV_DESCRIPTION
    call commit_event
    mov esi, [rbx + ISS_ID]
    call wr_u32
    mov esi, [rbx + ISS_UPDATED]
    call wr_u32
    lea rsi, [rbx + ISS_DESC]
    movzx edx, word [rbx + ISS_DESC_LEN]
    call wr_str16
    call send_event
    jmp .ok
.status:
    cmp r12d, STATUS_COUNT
    jae .invalid
    mov [rbx + ISS_STATUS], r12b
    jmp .changed
.priority:
    cmp r12d, PRIO_COUNT
    jae .invalid
    mov [rbx + ISS_PRIORITY], r12b
    jmp .changed
.assignee:
    mov edi, r12d
    call valid_assignee
    test eax, eax
    jz .invalid
    mov [rbx + ISS_ASSIGNEE], r12d
    jmp .changed
.project:
    mov edi, r12d
    call valid_project
    test eax, eax
    jz .invalid
    mov [rbx + ISS_PROJECT], r12b
    jmp .changed
.labels:
    mov edi, r12d
    call valid_labels
    test eax, eax
    jz .invalid
    mov [rbx + ISS_LABELS], r12w
    jmp .changed
.title:
    mov rsi, [op_text]
    mov edx, [op_text_len]
    mov ecx, TITLE_MAX
    call valid_text
    test eax, eax
    jz .invalid
    mov ecx, [op_text_len]
    mov [rbx + ISS_TITLE_LEN], cl
    lea rdi, [rbx + ISS_TITLE]
    mov rsi, [op_text]
    rep movsb
.changed:
    call .touch
    mov esi, EV_ISSUE
    call commit_event
    mov rsi, rbx
    call wr_issue
    call send_event
.ok:
    xor eax, eax
    jmp .done
.gone:
    mov eax, ACK_GONE
    jmp .done
.invalid:
    mov eax, ACK_INVALID
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret
.touch:
    call now_unix
    mov [rbx + ISS_UPDATED], eax
    mov edi, T_ISSUES
    mov rsi, rbx
    jmp db_touch

op_delete_issue:
    push rbx
    push r12
    push r13
    call op_find_issue
    test rax, rax
    jz .gone
    mov rbx, rax
    mov r13d, [rbx + ISS_ID]
    lea r12, [comments]
.comment:
    lea rax, [comments]
    mov ecx, [n_comments]
    imul rcx, rcx, CMT_SIZE
    add rax, rcx
    cmp r12, rax
    jae .comments_gone
    cmp [r12 + CMT_ISSUE], r13d
    jne .next
    mov edi, T_COMMENTS
    mov rsi, r12
    call free_row
.next:
    add r12, CMT_SIZE
    jmp .comment
.comments_gone:
    mov edi, T_ISSUES
    mov rsi, rbx
    call free_row
    mov esi, EV_DELETED
    call commit_event
    mov esi, r13d
    call wr_u32
    call send_event
    xor eax, eax
    jmp .done
.gone:
    mov eax, ACK_GONE
.done:
    pop r13
    pop r12
    pop rbx
    ret

op_comment:
    push rbx
    push r12
    push r13
    call op_find_issue
    test rax, rax
    jz .gone
    mov r12, rax
    mov rax, [op_team]
    mov edi, [rax + TEAM_ID]
    xor esi, esi
    mov edx, COMMENT_MAX
    call op_attachment
    test eax, eax
    jz .invalid
    mov r13, rdx                            ; its image
    mov edi, T_COMMENTS
    mov esi, CMT_ISSUE
    mov edx, [r12 + ISS_ID]
    call count_where
    cmp eax, ISSUE_COMMENT_MAX
    jae .full
    mov edi, T_COMMENTS
    call alloc_row
    test rax, rax
    jz .full
    mov rbx, rax
    mov eax, [next_comment_id]
    inc dword [next_comment_id]
    mov [rbx + CMT_ID], eax
    mov eax, [r12 + ISS_ID]
    mov [rbx + CMT_ISSUE], eax
    mov eax, [op_user]
    mov [rbx + CMT_AUTHOR], eax
    call now_unix
    mov [rbx + CMT_CREATED], eax
    mov ecx, [op_body_len]
    mov [rbx + CMT_LEN], cx
    lea rdi, [rbx + CMT_TEXT]
    mov rsi, [op_body]
    rep movsb
    mov edi, T_COMMENTS
    mov rsi, rbx
    call db_touch
    mov rdi, r13
    mov esi, IMAGE_ON_COMMENT
    mov edx, [rbx + CMT_ID]
    call attach_image
    mov esi, EV_COMMENT
    call commit_event
    mov esi, [r12 + ISS_ID]
    call wr_u32
    mov rsi, rbx
    call wr_comment
    call send_event
    xor eax, eax
    jmp .done
.gone:
    mov eax, ACK_GONE
    jmp .done
.invalid:
    mov eax, ACK_INVALID
    jmp .done
.full:
    mov eax, ACK_FULL
.done:
    pop r13
    pop r12
    pop rbx
    ret

; edi = comment id -> rax = its row and rdx = its issue's if the issue is in
; the op's team, else rax = 0
op_find_comment:
    lea rax, [comments]
    mov ecx, [n_comments]
.row:
    test ecx, ecx
    jz .none
    cmp [rax + CMT_ID], edi
    je .found
    add rax, CMT_SIZE
    dec ecx
    jmp .row
.found:
    test edi, edi
    jz .none                                ; 0 is a free slot
    push rax
    mov edi, [rax + CMT_ISSUE]
    mov [op_issue], edi
    call op_find_issue
    mov rdx, rax
    pop rax
    test rdx, rdx
    jnz .done
.none:
    xor eax, eax
.done:
    ret

; Only its author can change a comment's text.
op_edit_comment:
    push rbx
    push r12
    sub rsp, 8
    mov edi, [op_issue]
    call op_find_comment
    test rax, rax
    jz .gone
    mov rbx, rax
    mov r12, rdx
    mov eax, [op_user]
    cmp [rbx + CMT_AUTHOR], eax
    jne .forbidden
    cmp dword [op_body_len], 0
    je .invalid
    mov rsi, [op_body]
    mov edx, [op_body_len]
    mov ecx, COMMENT_MAX
    call valid_body
    test eax, eax
    jz .invalid
    lea rdi, [rbx + CMT_TEXT]
    mov esi, COMMENT_MAX
    call wipe                               ; in memory. The journal keeps it until compaction
    mov ecx, [op_body_len]
    mov [rbx + CMT_LEN], cx
    lea rdi, [rbx + CMT_TEXT]
    mov rsi, [op_body]
    rep movsb
    mov byte [rbx + CMT_EDITED], 1
    mov edi, T_COMMENTS
    mov rsi, rbx
    call db_touch
    mov esi, EV_COMMENT_EDITED
    call commit_event
    mov esi, [r12 + ISS_ID]
    call wr_u32
    mov rsi, rbx
    call wr_comment
    call send_event
    xor eax, eax
    jmp .done
.gone:
    mov eax, ACK_GONE
    jmp .done
.forbidden:
    mov eax, ACK_FORBIDDEN
    jmp .done
.invalid:
    mov eax, ACK_INVALID
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; Its author can delete a comment, and so can the team's owners and
; moderators, which goes in the audit log.
op_delete_comment:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 8
    xor ebp, ebp                            ; 1 when it's someone else's
    mov edi, [op_issue]
    call op_find_comment
    test rax, rax
    jz .gone
    mov rbx, rax
    mov r12d, [rdx + ISS_ID]
    mov eax, [op_user]
    cmp [rbx + CMT_AUTHOR], eax
    je .allowed
    mov rdi, [op_team]
    mov edi, [rdi + TEAM_ID]
    mov esi, eax
    call find_member
    test rax, rax
    jz .forbidden
    mov rdi, rax
    call member_perms
    test eax, PERM_MANAGE_MESSAGES
    jz .forbidden
    inc ebp
    mov rdi, [op_team]
    mov edi, [rdi + TEAM_ID]
    mov esi, AU_DELETE_COMMENT
    mov edx, [rbx + CMT_AUTHOR]
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call audit_add
.allowed:
    mov r13d, [rbx + CMT_ID]
    mov edi, T_COMMENTS
    mov rsi, rbx
    call free_row
    mov esi, EV_COMMENT_DELETED
    call commit_event
    mov esi, r12d
    call wr_u32
    mov esi, r13d
    call wr_u32
    call send_event
    test ebp, ebp
    jz .ok
    mov rax, [op_team]
    mov edi, [rax + TEAM_ID]
    mov esi, -1
    call send_moderation
.ok:
    xor eax, eax
    jmp .done
.gone:
    mov eax, ACK_GONE
    jmp .done
.forbidden:
    mov eax, ACK_FORBIDDEN
.done:
    add rsp, 8
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Writes a label or project slot from the op and announces it. An empty name
; deletes it, and every issue of the team lets go of it. Clients do the same
; when they see the event, so no per-issue events are needed.
; rdi = the slot, esi = max name length, edx = event kind, ecx = issue field
; offset, r8d = the value that field holds for this slot (its bit or number)
set_named:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12d, edx
    mov r13d, ecx
    mov r14d, r8d
    cmp dword [op_value], 0xffffff
    ja .invalid
    mov edx, [op_text_len]
    test edx, edx
    jz .delete
    mov ecx, esi
    mov rsi, [op_text]
    call valid_text
    test eax, eax
    jz .invalid
    mov eax, [op_value]
    mov [rbx], eax
    mov ecx, [op_text_len]
    mov [rbx + 4], cl
    lea rdi, [rbx + 5]
    mov rsi, [op_text]
    rep movsb
    jmp .announce
.delete:
    mov dword [rbx], 0
    mov byte [rbx + 4], 0
    mov rax, [op_team]
    mov r15d, [rax + TEAM_ID]
    lea rbp, [issues]
    mov ecx, [n_issues]
.issue:
    test ecx, ecx
    jz .announce
    cmp [rbp + ISS_TEAM], r15d
    jne .next
    cmp r13d, ISS_LABELS
    je .label
    cmp [rbp + r13], r14b                   ; a project number
    jne .next
    mov byte [rbp + r13], 0
    jmp .touch
.label:
    test [rbp + ISS_LABELS], r14w
    jz .next
    not r14d
    and [rbp + ISS_LABELS], r14w
    not r14d
.touch:
    push rcx
    mov edi, T_ISSUES
    mov rsi, rbp
    call db_touch
    pop rcx
.next:
    add rbp, ISSUE_SIZE
    dec ecx
    jmp .issue
.announce:
    mov esi, r12d
    call commit_event
    mov esi, [op_field]
    call wr_u8
    mov rsi, rbx
    call wr_named
    call send_event
    xor eax, eax
    jmp .done
.invalid:
    mov eax, ACK_INVALID
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

op_set_label:
    mov ecx, [op_field]
    cmp ecx, LABEL_SLOTS
    jae .invalid
    mov r8d, 1
    shl r8d, cl
    imul edi, ecx, LABEL_SIZE
    add rdi, [op_team]
    add rdi, TEAM_LABELS
    mov esi, LABEL_NAME_MAX
    mov edx, EV_LABEL
    mov ecx, ISS_LABELS
    jmp set_named
.invalid:
    mov eax, ACK_INVALID
    ret

op_set_project:
    mov r8d, [op_field]
    lea eax, [r8d - 1]
    cmp eax, PROJECT_SLOTS
    jae .invalid
    imul edi, eax, PROJ_SIZE
    add rdi, [op_team]
    add rdi, TEAM_PROJECTS
    mov esi, PROJECT_NAME_MAX
    mov edx, EV_PROJECT
    mov ecx, ISS_PROJECT
    jmp set_named
.invalid:
    mov eax, ACK_INVALID
    ret
