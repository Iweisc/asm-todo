; The client half of the sync protocol.
;
; We keep the team's issues, labels and projects exactly as the server last
; described them (a snapshot plus every EVENT since, in seq order) and,
; separately, the ops we've sent that the server hasn't acknowledged yet.
; What the window shows is the confirmed state with the pending ops applied
; on top, rebuilt by rebuild_view whenever either changes. Ops made while
; offline wait in the same queue and go out after the session is resumed.
; The server tells us the last op it applied, so nothing gets applied twice.
;
; One issue at a time can be open in the detail view. Its description and
; comments are fetched with OPEN_ISSUE and kept current by events.
;
; Chat sits beside all that. One conversation at a time can be open: the
; team's channel or a direct message with a member, fetched with OPEN_CHAT
; and kept current by CHAT messages. Messages we send are ops too, so they
; queue while offline and show dimmed until the server has them.

%define CO_ID           0
%define CO_ROLE         4
%define CO_KEY_LEN      5
%define CO_KEY          6               ; TEAM_KEY_MAX bytes
%define CO_NAME_LEN     11
%define CO_NAME         12              ; TEAMNAME_MAX bytes
%define CO_SIZE         48

%define CM_ID           0
%define CM_ROLE         4
%define CM_ONLINE       5
%define CM_NAME_LEN     6
%define CM_NAME         7
%define CM_SIZE         40

; Labels and projects: u32 color, u8 name length, name. Empty means unused.
%define LB_COLOR        0
%define LB_NAME_LEN     4
%define LB_NAME         5
%define LB_SIZE         32
%define PJ_SIZE         40

%define CI_ID           0               ; PENDING_ID | op number for one not created yet
%define CI_NUMBER       4
%define CI_ASSIGNEE     8
%define CI_CREATOR      12
%define CI_CREATED      16
%define CI_UPDATED      20
%define CI_LABELS       24              ; u16
%define CI_STATUS       26
%define CI_PRIORITY     27
%define CI_PROJECT      28
%define CI_TITLE_LEN    29
%define CI_TITLE        30              ; TITLE_MAX bytes
%define CI_PENDING      150             ; a pending op touched it
%define CI_SIZE         152
%define PENDING_ID      0x80000000

%define CC_ID           0
%define CC_AUTHOR       4
%define CC_CREATED      8
%define CC_LEN          12              ; u16
%define CC_PENDING      14
%define CC_TEXT         16              ; COMMENT_MAX bytes
%define CC_EDITED       516             ; u8, 1 once its author changed it
%define CC_IMAGE        520             ; an image ref
%define CC_SIZE         528

; A message in the open conversation.
%define CH_ID           0
%define CH_AUTHOR       4
%define CH_CREATED      8
%define CH_LEN          12              ; u16
%define CH_PENDING      14
%define CH_TEXT         16              ; MESSAGE_MAX bytes
%define CH_EDITED       516             ; u8, 1 once its author changed it
%define CH_IMAGE        520             ; an image ref
%define CH_SIZE         528

; An image ref: what a message or comment says about its image.
%define RI_ID           0               ; 0 for no image
%define RI_W            4               ; u16
%define RI_H            6               ; u16
%define RI_SIZE         8
%define CHAT_MAX        200             ; kept for the open conversation, the oldest go first

%define PENDING_MAX     128
%define PO_NUM          0
%define PO_TEAM         4
%define PO_ISSUE        8
%define PO_VALUE        12              ; a field's value, or a label or project color
%define PO_ASSIGNEE     16
%define PO_LABELS       20
%define PO_KIND         24
%define PO_FIELD        25              ; or a label or project slot
%define PO_STATUS       26
%define PO_PRIORITY     27
%define PO_PROJECT      28
%define PO_TEXT_LEN     29
%define PO_BODY_LEN     30              ; u16
%define PO_TEXT         32              ; a title or name, TITLE_MAX bytes
%define PO_BODY         152             ; a description or comment, DESC_MAX bytes
%define PO_SIZE         1656
%define PO_IMAGE        PO_VALUE        ; a comment's or message's image id
%define PO_IMAGE_SIZE   PO_ASSIGNEE     ; and its width | height << 16, an image ref's last half

fits CO_KEY, TEAM_KEY_MAX, CO_NAME_LEN
fits CO_NAME, TEAMNAME_MAX, CO_SIZE
fits CM_NAME, USERNAME_MAX, CM_SIZE
fits LB_NAME, LABEL_NAME_MAX, LB_SIZE
fits LB_NAME, PROJECT_NAME_MAX, PJ_SIZE
fits CI_TITLE, TITLE_MAX, CI_PENDING
fits CC_TEXT, COMMENT_MAX, CC_EDITED
fits CC_EDITED, 1, CC_IMAGE
fits CC_IMAGE, RI_SIZE, CC_SIZE
fits PO_TEXT, TITLE_MAX, PO_BODY
fits PO_BODY, DESC_MAX, PO_SIZE
fits CH_LEN, 2, CH_PENDING
fits CH_PENDING, 1, CH_TEXT
fits CH_TEXT, MESSAGE_MAX, CH_EDITED
fits CH_EDITED, 1, CH_IMAGE
fits CH_IMAGE, RI_SIZE, CH_SIZE
fits RI_W, 2, RI_H
fits RI_H, 2, RI_SIZE

%define VIEW_MAX        (TEAM_ISSUE_MAX + PENDING_MAX)
%define VIEW_COMMENTS   (ISSUE_COMMENT_MAX + PENDING_MAX)
%define VIEW_CHAT       (CHAT_MAX + PENDING_MAX)
%define UNREAD_MAX      (TEAM_MEMBER_MAX + 1 + CHANNEL_SLOTS)
%define STATUS_MAX      128

section .rodata
text st_gone,       "someone deleted that issue first"
text st_forbidden,  "you're not a member of that team anymore"
text st_invalid,    "the server refused that change"
text st_full,       "that's over the limit for this team"
text st_queue_full, "too many unsynced changes, wait for the connection to come back"
text st_offline,    "you're offline, try again once reconnected"
text st_no_server,  "can't reach the server yet"

section .bss
logged_in:      resb 1                  ; show the app rather than the login screen
authed:         resb 1                  ; this connection is logged in
auth_busy:      resb 1                  ; a login or sign-up is being checked
auth_queued:    resb 1                  ; MSG_LOGIN or MSG_REGISTER to send once connected, 0 for none
restoring:      resb 1                  ; resuming the session saved by the last run
resync:         resb 1                  ; resubscribe and resend after the next TEAMS
loaded:         resb 1                  ; the current team's snapshot is complete
select_new:     resb 1                  ; switch to the team we just created once it shows up
detail_loaded:  resb 1
chat_open:      resb 1                  ; the panel shows a conversation instead of issues
chat_loaded:    resb 1
token:          resb 32
alignb 4
my_id:          resd 1
my_name_len:    resd 1
my_name:        resb USERNAME_MAX

alignb 4
team_count:     resd 1
teams:          resb USER_TEAM_MAX * CO_SIZE
current_team:   resd 1
team_seq:       resd 1
member_count:   resd 1
members:        resb TEAM_MEMBER_MAX * CM_SIZE
labels:         resb LABEL_SLOTS * LB_SIZE
projects:       resb PROJECT_SLOTS * PJ_SIZE
issue_count:    resd 1
issues:         resb TEAM_ISSUE_MAX * CI_SIZE

detail_issue:   resd 1                  ; the open issue's id, 0 for none
desc_len:       resd 1
desc:           resb DESC_MAX
alignb 4
comment_count:  resd 1
comments:       resb ISSUE_COMMENT_MAX * CC_SIZE

chat_peer:      resd 1                  ; 0 for the team's channel, else the member
chat_count:     resd 1
chat_msgs:      resb CHAT_MAX * CH_SIZE
unread_count:   resd 1
unread:         resd UNREAD_MAX         ; conversations with messages we haven't seen, by peer

pending_count:  resd 1
next_op:        resd 1
pending:        resb PENDING_MAX * PO_SIZE
op_draft:       resb PO_SIZE

; The confirmed state with pending ops applied. The UI reads only these.
alignb 4
view_count:     resd 1
view_issues:    resb VIEW_MAX * CI_SIZE
view_labels:    resb LABEL_SLOTS * LB_SIZE
view_projects:  resb PROJECT_SLOTS * PJ_SIZE
alignb 8
view_desc:      resq 1
view_desc_len:  resd 1
view_comment_count: resd 1
view_comments:  resb VIEW_COMMENTS * CC_SIZE
view_chat_count: resd 1
view_chat:      resb VIEW_CHAT * CH_SIZE

auth_msg_len:   resd 1
auth_msg:       resb STATUS_MAX
status_len:     resd 1
status_msg:     resb STATUS_MAX
status_until:   resq 1                  ; now_ms when the footer message goes away
out_msg:        resb 2048

section .text

; -> eax = unix seconds
unix_now:
    sub rsp, 16
    mov eax, SYS_clock_gettime
    mov edi, CLOCK_REALTIME
    mov rsi, rsp
    syscall
    mov eax, [rsp]
    add rsp, 16
    ret

; rdi = cursor in out_msg -> sends out_msg up to it. eax = 1 if sent
send_built:
    lea rsi, [out_msg]
    mov rdx, rdi
    sub rdx, rsi
    jmp net_send

%define STATUS_MS       5000            ; how long a footer message stays up

; rsi = text, edx = length. Footer message, shown until the next action or
; for STATUS_MS.
set_status:
    cmp edx, STATUS_MAX
    jbe .fits
    mov edx, STATUS_MAX
.fits:
    mov [status_len], edx
    lea rdi, [status_msg]
    call put_mem
    call now_ms
    add rax, STATUS_MS
    mov [status_until], rax
    lea rdi, [status_msg]
    jmp capitalize

; rsi = text, edx = length. The message on the login screen.
set_auth_msg:
    cmp edx, STATUS_MAX
    jbe .fits
    mov edx, STATUS_MAX
.fits:
    mov [auth_msg_len], edx
    lea rdi, [auth_msg]
    call put_mem
    lea rdi, [auth_msg]
; The server's messages start lowercase, so they can go mid-sentence too.
; rdi = a message to start with a capital, and redraw
capitalize:
    mov al, [rdi]
    sub al, 'a'
    cmp al, 'z' - 'a'
    ja .done
    sub byte [rdi], 'a' - 'A'
.done:
    mov byte [need_redraw], 1
    ret

; -> eax = poll timeout in ms until the footer message goes, -1 with none
status_timeout:
    mov eax, -1
    cmp dword [status_len], 0
    je .done
    call now_ms
    mov rcx, [status_until]
    sub rcx, rax
    xor eax, eax
    test rcx, rcx
    cmovg eax, ecx
.done:
    ret

; Takes the footer message down once its time is up.
status_tick:
    cmp dword [status_len], 0
    je .done
    call now_ms
    cmp rax, [status_until]
    jb .done
    mov dword [status_len], 0
    mov byte [need_redraw], 1
.done:
    ret

; Forgets the team being viewed.
clear_team_view:
    xor eax, eax
    mov [issue_count], eax
    mov [member_count], eax
    mov [team_seq], eax
    mov [loaded], al
    mov [detail_issue], eax
    mov [chat_open], al
    mov [chat_count], eax
    mov [unread_count], eax
    mov [chan_count], eax
    lea rdi, [labels]
    mov ecx, LABEL_SLOTS * LB_SIZE + PROJECT_SLOTS * PJ_SIZE  ; projects follows labels
    rep stosb
    jmp rebuild_view

; Back to a logged-out client.
sync_reset:
    lea rdi, [token]
    mov esi, 32
    call wipe
    call session_save                       ; the saved one is no good now either
    xor eax, eax
    mov [logged_in], al
    mov [authed], al
    mov [resync], al
    mov [pending_count], eax
    mov [team_count], eax
    mov [current_team], eax
    mov [status_len], eax
    mov byte [need_redraw], 1
    call ui_logged_out
    jmp clear_team_view

sync_on_open:
    movzx edi, byte [auth_queued]
    test edi, edi
    jz .resume
    mov byte [auth_queued], 0
    mov byte [auth_busy], 0
    jmp do_auth
.resume:
    mov al, [logged_in]
    or al, [restoring]
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_RESUME
    call wr_u8
    lea rsi, [token]
    mov ecx, 32
    rep movsb
    call send_built
.done:
    mov byte [need_redraw], 1
    ret

sync_on_offline:
    call images_offline
    call attach_failed
    mov byte [authed], 0
    mov byte [auth_busy], 0
    mov byte [password_busy], 0
    mov byte [need_redraw], 1
    cmp byte [auth_queued], 0
    je .done
    mov byte [auth_queued], 0               ; the retry failed too
    lea rsi, [st_no_server]
    mov edx, st_no_server_len
    jmp set_auth_msg
.done:
    ret

; rsi = plaintext, rdx = length
sync_on_message:
    push rbx
    mov rdi, rsi
    mov rsi, rdx
    call rd_begin
    call rd_u8
    sub eax, MSG_AUTH_OK
    cmp eax, MSG_UPLOAD_READY - MSG_AUTH_OK
    ja .bad
    lea rcx, [.table]
    call [rcx + rax * 8]
    call rd_ok
    test eax, eax
    jz .bad
    mov byte [need_redraw], 1
    pop rbx
    ret
.bad:
    ; The channel is authenticated, so this is a bug on one side. Reconnecting
    ; gets us a clean snapshot.
    pop rbx
    jmp net_drop
.table:
    dq on_auth_ok, on_auth_fail, on_error, on_teams, on_snapshot, on_event
    dq on_ack, on_members, on_logged_out, on_team_meta, on_issue_detail
    dq on_chat, on_chat_history, on_unread, on_password_changed, on_channels
    dq on_chat_edited, on_chat_deleted, on_image, on_upload_ready

on_auth_ok:
    push rbx
    call rd_u32
    mov [my_id], eax
    call rd_str
    cmp edx, USERNAME_MAX
    ja .bad
    mov [my_name_len], edx
    lea rdi, [my_name]
    mov rsi, rax
    call put_mem
    mov edi, 32
    call rd_bytes
    lea rdi, [token]
    mov rsi, rax
    mov ecx, 32
    rep movsb
    call rd_u32
    mov ebx, eax                            ; last op the server applied
    cmp byte [logged_in], 0
    jne .resumed
    ; A fresh login starts a fresh session with a fresh op count.
    mov dword [pending_count], 0
    lea eax, [ebx + 1]
    mov [next_op], eax
    mov dword [team_count], 0
    mov dword [current_team], 0
    call clear_team_view
    call ui_logged_in
    jmp .done
.resumed:
    ; A reconnect leaves whatever was open and focused alone.
    ; Ops the server applied before the old connection died: their ACKs got lost.
    cmp dword [pending_count], 0
    je .done
    cmp [pending + PO_NUM], ebx
    ja .done
    call pop_pending
    jmp .resumed
.done:
    mov byte [logged_in], 1
    mov byte [authed], 1
    mov byte [auth_busy], 0
    mov byte [restoring], 0
    call session_save
    mov byte [resync], 1
    mov dword [auth_msg_len], 0
    pop rbx
    ret
.bad:
    mov byte [rd_bad], 1
    pop rbx
    ret

on_auth_fail:
    call rd_str
    mov rsi, rax
    call set_auth_msg
    mov byte [auth_busy], 0
    cmp byte [restoring], 0
    je .live
    ; The saved session ran out: back to the form.
    mov byte [restoring], 0
    call ui_login_form
    jmp sync_reset
.live:
    cmp byte [logged_in], 0
    je .done
    jmp sync_reset                          ; our session is gone, back to the login screen
.done:
    ret

on_error:
    sub rsp, 8
    mov byte [password_busy], 0             ; the likely answer to a change
    call attach_failed                      ; or to an upload
    call rd_str
    add rsp, 8
    mov rsi, rax
    jmp set_status

on_logged_out:
    jmp sync_reset

; rdi = destination, esi = max length. Reads a str into a u8 length then bytes.
read_named_str:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    call rd_str
    cmp edx, r12d
    ja .bad
    mov [rbx], dl
    lea rdi, [rbx + 1]
    mov rsi, rax
    call put_mem
    jmp .done
.bad:
    mov byte [rd_bad], 1
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

on_teams:
    push rbx
    push r12
    push r13
    call rd_u8
    mov r12d, eax
    xor r13d, r13d
    lea rbx, [teams]
.team:
    cmp r13d, r12d
    jae .read
    cmp r13d, USER_TEAM_MAX
    jae .bad
    call rd_u32
    mov [rbx + CO_ID], eax
    call rd_u8
    mov [rbx + CO_ROLE], al
    lea rdi, [rbx + CO_KEY_LEN]
    mov esi, TEAM_KEY_MAX
    call read_named_str
    lea rdi, [rbx + CO_NAME_LEN]
    mov esi, TEAMNAME_MAX
    call read_named_str
    inc r13d
    add rbx, CO_SIZE
    jmp .team
.read:
    mov [team_count], r13d

    mov ebx, [current_team]
    cmp byte [select_new], 0
    je .check_current
    ; Team ids only grow, so the one we just created has the highest.
    mov byte [select_new], 0
    xor eax, eax
    lea rcx, [teams]
    mov edx, [team_count]
.newest:
    test edx, edx
    jz .switch
    cmp [rcx + CO_ID], eax
    cmova eax, [rcx + CO_ID]
    add rcx, CO_SIZE
    dec edx
    jmp .newest
.switch:
    test eax, eax
    jz .check_current
    mov [current_team], eax
    call clear_team_view
    call ui_team_opened
    jmp .subscribe
.check_current:
    test ebx, ebx
    jz .pick
    mov edi, ebx
    call find_team_row
    test rax, rax
    jnz .subscribe
    mov dword [current_team], 0             ; removed from it
    call clear_team_view
    call ui_team_opened
.pick:
    cmp dword [team_count], 0
    je .resend
    mov eax, [teams + CO_ID]
    mov [current_team], eax
    call clear_team_view
    call ui_team_opened
.subscribe:
    mov eax, [current_team]
    test eax, eax
    jz .resend
    cmp byte [resync], 0
    jne .send
    cmp eax, ebx
    je .resend
.send:
    call send_subscribe
.resend:
    cmp byte [resync], 0
    je .done
    mov byte [resync], 0
    xor ebx, ebx
.op:
    cmp ebx, [pending_count]
    jae .done
    imul edi, ebx, PO_SIZE
    lea rdi, [pending + rdi]
    call send_op
    inc ebx
    jmp .op
.bad:
    mov byte [rd_bad], 1
.done:
    pop r13
    pop r12
    pop rbx
    ret

; edi = team id -> rax = its row in teams, or 0
find_team_row:
    lea rax, [teams]
    mov ecx, [team_count]
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + CO_ID], edi
    je .done
    add rax, CO_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; -> rax = the current team's row, or 0
current_team_row:
    mov edi, [current_team]
    test edi, edi
    jnz find_team_row
    xor eax, eax
    ret

send_subscribe:
    mov byte [loaded], 0
    lea rdi, [out_msg]
    mov esi, MSG_SUBSCRIBE
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    jmp send_built

; Asks for the open issue's description and comments.
send_open_issue:
    mov byte [detail_loaded], 0
    mov eax, [detail_issue]
    test eax, eax
    jz .done
    test eax, PENDING_ID
    jnz .done
    lea rdi, [out_msg]
    mov esi, MSG_OPEN_ISSUE
    call wr_u8
    mov esi, [detail_issue]
    call wr_u32
    jmp send_built
.done:
    ret

; Reads an issue off the wire into a row. rdi = row
read_issue:
    push rbx
    mov rbx, rdi
    call rd_u32
    mov [rbx + CI_ID], eax
    call rd_u32
    mov [rbx + CI_NUMBER], eax
    call rd_u8
    mov [rbx + CI_STATUS], al
    call rd_u8
    mov [rbx + CI_PRIORITY], al
    call rd_u32
    mov [rbx + CI_ASSIGNEE], eax
    call rd_u8
    mov [rbx + CI_PROJECT], al
    call rd_u16
    mov [rbx + CI_LABELS], ax
    call rd_u32
    mov [rbx + CI_CREATOR], eax
    call rd_u32
    mov [rbx + CI_CREATED], eax
    call rd_u32
    mov [rbx + CI_UPDATED], eax
    lea rdi, [rbx + CI_TITLE_LEN]
    mov esi, TITLE_MAX
    call read_named_str
    mov byte [rbx + CI_PENDING], 0
    pop rbx
    ret

; Reads a label or project. rdi = slot, esi = max name length
read_named:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    call rd_u32
    mov [rbx + LB_COLOR], eax
    lea rdi, [rbx + LB_NAME_LEN]
    mov esi, r12d
    call read_named_str
    add rsp, 8
    pop r12
    pop rbx
    ret

on_team_meta:
    push rbx
    push r12
    sub rsp, 8
    call rd_u32
    cmp eax, [current_team]
    jne .skip
    lea rbx, [labels]
    mov r12d, LABEL_SLOTS
.label:
    mov rdi, rbx
    mov esi, LABEL_NAME_MAX
    call read_named
    add rbx, LB_SIZE
    dec r12d
    jnz .label
    lea rbx, [projects]
    mov r12d, PROJECT_SLOTS
.project:
    mov rdi, rbx
    mov esi, PROJECT_NAME_MAX
    call read_named
    add rbx, PJ_SIZE
    dec r12d
    jnz .project
    call rebuild_view
    jmp .done
.skip:
    call rd_skip
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

on_snapshot:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 8
    call rd_u32
    mov ebx, eax                            ; team
    call rd_u32
    mov r12d, eax                           ; seq
    call rd_u8
    mov r13d, eax                           ; first chunk
    call rd_u8
    mov ebp, eax                            ; last chunk
    cmp ebx, [current_team]
    jne .skip
    test r13d, r13d
    jz .count
    mov dword [issue_count], 0
.count:
    call rd_u16
    mov r13d, eax
.issue:
    test r13d, r13d
    jz .end
    cmp byte [rd_bad], 0
    jne .end
    mov eax, [issue_count]
    cmp eax, TEAM_ISSUE_MAX
    jae .bad
    imul eax, eax, CI_SIZE
    lea rdi, [issues + rax]
    call read_issue
    inc dword [issue_count]
    dec r13d
    jmp .issue
.end:
    mov [team_seq], r12d
    test ebp, ebp
    jz .rebuild
    mov byte [loaded], 1
    call send_open_issue                    ; after a reconnect the detail view needs it again
    call send_open_chat                     ; and so does the chat, subscribing closed it
.rebuild:
    call rebuild_view
    jmp .done
.bad:
    mov byte [rd_bad], 1
    jmp .done
.skip:
    call rd_skip
.done:
    add rsp, 8
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = issue id -> rax = its confirmed row, or 0
find_issue_row:
    lea rax, [issues]
    mov ecx, [issue_count]
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + CI_ID], edi
    je .done
    add rax, CI_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; Clears a label or project from every issue in a list. Order doesn't matter.
; rdi = issue rows, esi = count, edx = label bit (0 for a project), ecx = project number
forget_named:
.row:
    test esi, esi
    jz .done
    test edx, edx
    jz .project
    mov eax, edx
    not eax
    and [rdi + CI_LABELS], ax
    jmp .next
.project:
    cmp [rdi + CI_PROJECT], cl
    jne .next
    mov byte [rdi + CI_PROJECT], 0
.next:
    add rdi, CI_SIZE
    dec esi
    jmp .row
.done:
    ret

; EV_LABEL and EV_PROJECT: a slot's new name and color. An emptied one is
; gone, so the team's issues drop it. edi = event kind
on_named_event:
    push rbx
    cmp edi, EV_PROJECT
    je .project
.label:
    call rd_u8
    cmp eax, LABEL_SLOTS
    jae .bad
    mov ebx, eax
    imul edi, eax, LB_SIZE
    add rdi, labels
    mov esi, LABEL_NAME_MAX
    call read_named
    imul eax, ebx, LB_SIZE
    cmp byte [labels + rax + LB_NAME_LEN], 0
    jne .done
    lea rdi, [issues]
    mov esi, [issue_count]
    mov edx, 1
    mov ecx, ebx
    shl edx, cl
    call forget_named
    jmp .done

.project:
    call rd_u8
    lea ecx, [eax - 1]
    cmp ecx, PROJECT_SLOTS
    jae .bad
    mov ebx, eax
    imul edi, ecx, PJ_SIZE
    add rdi, projects
    mov esi, PROJECT_NAME_MAX
    call read_named
    lea eax, [ebx - 1]
    imul eax, eax, PJ_SIZE
    cmp byte [projects + rax + LB_NAME_LEN], 0
    jne .done
    lea rdi, [issues]
    mov esi, [issue_count]
    xor edx, edx
    mov ecx, ebx
    call forget_named

.done:
    pop rbx
    ret
.bad:
    mov byte [rd_bad], 1
    pop rbx
    ret

; EVENT: one change to a team, in its sequence. A gap asks for a new snapshot.
on_event:
    push rbx
    push r12
    push r13
    call rd_u32
    mov ebx, eax                            ; team
    call rd_u32
    mov r12d, eax                           ; seq
    call rd_u8
    mov r13d, eax                           ; kind
    cmp ebx, [current_team]
    jne .skip
    cmp byte [loaded], 0
    je .skip
    cmp r12d, [team_seq]
    jbe .skip                               ; already in the snapshot
    mov eax, [team_seq]
    inc eax
    cmp r12d, eax
    jne .gap
    cmp r13d, EV_ISSUE
    je .issue
    cmp r13d, EV_DESCRIPTION
    je .description
    cmp r13d, EV_DELETED
    je .deleted
    cmp r13d, EV_COMMENT
    je .comment
    cmp r13d, EV_COMMENT_EDITED
    je .comment
    cmp r13d, EV_COMMENT_DELETED
    je .comment
    cmp r13d, EV_LABEL
    je .named
    cmp r13d, EV_PROJECT
    je .named
    jmp .bad

.issue:
    sub rsp, CI_SIZE + 8
    mov rdi, rsp
    call read_issue
    mov edi, [rsp + CI_ID]
    call find_issue_row
    test rax, rax
    jnz .replace
    mov eax, [issue_count]
    cmp eax, TEAM_ISSUE_MAX
    jae .issue_bad
    imul eax, eax, CI_SIZE
    lea rax, [issues + rax]
    inc dword [issue_count]
.replace:
    mov rdi, rax
    mov rsi, rsp
    mov ecx, CI_SIZE
    rep movsb
    add rsp, CI_SIZE + 8
    jmp .applied
.issue_bad:
    add rsp, CI_SIZE + 8
    jmp .bad

.description:
    call rd_u32
    mov ebx, eax
    call rd_u32
    mov r13d, eax
    call rd_str16
    cmp edx, DESC_MAX
    ja .bad
    push rax
    push rdx
    mov edi, ebx
    call find_issue_row
    pop rdx
    pop rsi
    test rax, rax
    jz .applied
    mov [rax + CI_UPDATED], r13d
    cmp ebx, [detail_issue]
    jne .applied
    mov [desc_len], edx
    lea rdi, [desc]
    call put_mem
    jmp .applied

.deleted:
    call rd_u32
    mov edi, eax
    call find_issue_row
    test rax, rax
    jz .applied
    mov rdi, rax                            ; the last row fills the gap
    dec dword [issue_count]
    mov eax, [issue_count]
    imul eax, eax, CI_SIZE
    lea rsi, [issues + rax]
    mov ecx, CI_SIZE
    rep movsb
    jmp .applied

.comment:
    mov edi, r13d
    call on_comment_event
    jmp .applied

.named:
    mov edi, r13d
    call on_named_event
    jmp .applied

.applied:
    cmp byte [rd_bad], 0
    jne .done
    mov [team_seq], r12d
    call rebuild_view
    jmp .done
.gap:
    ; We missed something. Start over from a fresh snapshot.
    call rd_skip
    call send_subscribe
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

; ISSUE_DETAIL: the open issue's description and comments.
on_issue_detail:
    push rbx
    push r12
    push r13
    call rd_u32
    cmp eax, [detail_issue]
    jne .skip
    call rd_str16
    cmp edx, DESC_MAX
    ja .bad
    mov [desc_len], edx
    lea rdi, [desc]
    mov rsi, rax
    call put_mem
    call rd_u8
    cmp eax, ISSUE_COMMENT_MAX
    ja .bad
    mov r12d, eax
    lea rbx, [comments]
    xor r13d, r13d
.comment:
    cmp r13d, r12d
    jae .read
    mov rdi, rbx
    call read_comment
    add rbx, CC_SIZE
    inc r13d
    jmp .comment
.read:
    mov [comment_count], r12d
    mov byte [detail_loaded], 1
    call rebuild_view
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

pop_pending:
    dec dword [pending_count]
    lea rdi, [pending]
    lea rsi, [pending + PO_SIZE]
    mov eax, [pending_count]
    imul edx, eax, PO_SIZE
    jmp memmove

on_ack:
    push rbx
    push r12
    sub rsp, 8
    call rd_u32
    mov ebx, eax
    call rd_u8
    mov r12d, eax
    cmp dword [pending_count], 0
    je .status
    cmp [pending + PO_NUM], ebx
    jne .status
    call pop_pending
.status:
    test r12d, r12d
    jz .rebuild
    lea rsi, [st_gone]
    mov edx, st_gone_len
    cmp r12d, ACK_GONE
    je .show
    lea rsi, [st_forbidden]
    mov edx, st_forbidden_len
    cmp r12d, ACK_FORBIDDEN
    je .show
    lea rsi, [st_full]
    mov edx, st_full_len
    cmp r12d, ACK_FULL
    je .show
    lea rsi, [st_invalid]
    mov edx, st_invalid_len
.show:
    call set_status
.rebuild:
    call rebuild_view
    add rsp, 8
    pop r12
    pop rbx
    ret

on_members:
    push rbx
    push r12
    push r13
    call rd_u32
    mov ebx, eax
    call rd_u8
    mov r12d, eax
    cmp ebx, [current_team]
    jne .skip
    cmp r12d, TEAM_MEMBER_MAX
    ja .bad
    lea rbx, [members]
    xor r13d, r13d
.member:
    cmp r13d, r12d
    jae .read
    call rd_u32
    mov [rbx + CM_ID], eax
    call rd_u8
    mov [rbx + CM_ROLE], al
    call rd_u8
    mov [rbx + CM_ONLINE], al
    lea rdi, [rbx + CM_NAME_LEN]
    mov esi, USERNAME_MAX
    call read_named_str
    add rbx, CM_SIZE
    inc r13d
    jmp .member
.read:
    mov [member_count], r12d
    call ui_members_changed
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

; edi = user id -> rax = their member row, or 0
find_member_row:
    lea rax, [members]
    mov ecx, [member_count]
    test edi, edi
    jz .none
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + CM_ID], edi
    je .done
    add rax, CM_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; rdi = pending op
send_op:
    push rbx
    mov rbx, rdi
    lea rdi, [out_msg]
    mov esi, MSG_OP
    call wr_u8
    mov esi, [rbx + PO_NUM]
    call wr_u32
    movzx esi, byte [rbx + PO_KIND]
    call wr_u8
    mov esi, [rbx + PO_TEAM]
    call wr_u32
    movzx eax, byte [rbx + PO_KIND]
    cmp eax, OP_CREATE_ISSUE
    je .create
    cmp eax, OP_SET_FIELD
    je .set
    cmp eax, OP_SET_LABEL
    je .named
    cmp eax, OP_SET_PROJECT
    je .named
    mov esi, [rbx + PO_ISSUE]               ; deletes, comments and messages
    call wr_u32
    cmp byte [rbx + PO_KIND], OP_DELETE_ISSUE
    je .send
    cmp byte [rbx + PO_KIND], OP_DELETE_COMMENT
    je .send
    jmp .body
.create:
    movzx esi, byte [rbx + PO_STATUS]
    call wr_u8
    movzx esi, byte [rbx + PO_PRIORITY]
    call wr_u8
    mov esi, [rbx + PO_ASSIGNEE]
    call wr_u32
    movzx esi, byte [rbx + PO_PROJECT]
    call wr_u8
    mov esi, [rbx + PO_LABELS]
    call wr_u16
    call .title
    jmp .body
.set:
    mov esi, [rbx + PO_ISSUE]
    call wr_u32
    movzx esi, byte [rbx + PO_FIELD]
    call wr_u8
    cmp byte [rbx + PO_FIELD], FIELD_TITLE
    je .set_title
    cmp byte [rbx + PO_FIELD], FIELD_DESCRIPTION
    je .body
    mov esi, [rbx + PO_VALUE]
    call wr_u32
    jmp .send
.set_title:
    call .title
    jmp .send
.named:
    movzx esi, byte [rbx + PO_FIELD]
    call wr_u8
    mov esi, [rbx + PO_VALUE]
    call wr_u32
    call .title
    jmp .send
.body:
    lea rsi, [rbx + PO_BODY]
    movzx edx, word [rbx + PO_BODY_LEN]
    call wr_str16
    cmp byte [rbx + PO_KIND], OP_COMMENT
    je .image
    cmp byte [rbx + PO_KIND], OP_MESSAGE
    jne .send
.image:
    mov esi, [rbx + PO_IMAGE]
    call wr_u32
.send:
    pop rbx
    jmp send_built
.title:
    lea rsi, [rbx + PO_TEXT]
    movzx edx, byte [rbx + PO_TEXT_LEN]
    jmp wr_str

; edi = kind -> rax = op_draft, zeroed with its kind set. Fill it in, then queue_draft.
new_op:
    push rdi
    lea rdi, [op_draft]
    mov esi, PO_SIZE
    call wipe
    pop rdi
    mov [op_draft + PO_KIND], dil
    lea rax, [op_draft]
    ret

; Queues op_draft for the current team and sends it if we can.
; -> eax = 1 if queued
queue_draft:
    push rbx
    cmp dword [current_team], 0
    je .refused
    mov eax, [pending_count]
    cmp eax, PENDING_MAX
    jae .full
    imul eax, eax, PO_SIZE
    lea rbx, [pending + rax]
    mov rdi, rbx
    lea rsi, [op_draft]
    mov ecx, PO_SIZE
    rep movsb
    mov eax, [next_op]
    mov [rbx + PO_NUM], eax
    inc dword [next_op]
    mov eax, [current_team]
    mov [rbx + PO_TEAM], eax
    inc dword [pending_count]
    ; Before TEAMS arrives the resend loop will pick it up instead.
    call can_send
    test eax, eax
    jz .queued
    mov rdi, rbx
    call send_op
.queued:
    call rebuild_view
    mov eax, 1
    pop rbx
    ret
.full:
    lea rsi, [st_queue_full]
    mov edx, st_queue_full_len
    call set_status
.refused:
    xor eax, eax
    pop rbx
    ret

; rsi = text, edx = length. Into op_draft's title or name...
draft_text:
    mov [op_draft + PO_TEXT_LEN], dl
    lea rdi, [op_draft + PO_TEXT]
    jmp put_mem
; ...or its description or comment.
draft_body:
    mov [op_draft + PO_BODY_LEN], dx
    lea rdi, [op_draft + PO_BODY]
    jmp put_mem

; edi = issue, esi = field, edx = value (for the u32 fields)
sync_set_field:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov edi, OP_SET_FIELD
    call new_op
    mov [rax + PO_ISSUE], ebx
    mov [rax + PO_FIELD], r12b
    mov [rax + PO_VALUE], r13d
    call queue_draft
    pop r13
    pop r12
    pop rbx
    ret

; edi = issue, rsi = title, edx = length
sync_set_title:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12, rsi
    mov r13d, edx
    mov edi, OP_SET_FIELD
    call new_op
    mov [rax + PO_ISSUE], ebx
    mov byte [rax + PO_FIELD], FIELD_TITLE
    mov rsi, r12
    mov edx, r13d
    call draft_text
    call queue_draft
    pop r13
    pop r12
    pop rbx
    ret

; edi = issue, rsi = description, edx = length
sync_set_description:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12, rsi
    mov r13d, edx
    mov edi, OP_SET_FIELD
    call new_op
    mov [rax + PO_ISSUE], ebx
    mov byte [rax + PO_FIELD], FIELD_DESCRIPTION
    mov rsi, r12
    mov edx, r13d
    call draft_body
    call queue_draft
    pop r13
    pop r12
    pop rbx
    ret

; A comment on an issue, or a message to the channel or a member.
; edi = the issue or peer, rsi = text, edx = length, ecx = OP_COMMENT or OP_MESSAGE,
; r8d = image id or 0, r9d = its width | height << 16 -> eax = 1 if queued
sync_text:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12, rsi
    mov r13d, edx
    mov r14d, r8d
    mov r15d, r9d
    mov edi, ecx
    call new_op
    mov [rax + PO_ISSUE], ebx
    mov [rax + PO_IMAGE], r14d
    mov [rax + PO_IMAGE_SIZE], r15d
    mov rsi, r12
    mov edx, r13d
    call draft_body
    call queue_draft
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Reads an image ref off the wire. rdi = where it goes
read_image_ref:
    push rbx
    mov rbx, rdi
    call rd_u32
    mov [rbx + RI_ID], eax
    call rd_u16
    mov [rbx + RI_W], ax
    call rd_u16
    mov [rbx + RI_H], ax
    pop rbx
    ret

; A pending comment's or message's image, as a ref. rdi = where it goes, rsi = the op
op_image_ref:
    mov eax, [rsi + PO_IMAGE]
    mov [rdi + RI_ID], eax
    mov eax, [rsi + PO_IMAGE_SIZE]
    mov [rdi + RI_W], eax
    ret

; edi = issue
sync_delete_issue:
    push rbx
    mov ebx, edi
    mov edi, OP_DELETE_ISSUE
    call new_op
    mov [rax + PO_ISSUE], ebx
    call queue_draft
    pop rbx
    ret

; edi = OP_SET_LABEL or OP_SET_PROJECT, esi = slot, edx = color, rcx = name, r8d = length
sync_set_named:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, esi
    mov r12d, edx
    mov r13, rcx
    mov r14d, r8d
    call new_op
    mov [rax + PO_FIELD], bl
    mov [rax + PO_VALUE], r12d
    mov rsi, r13
    mov edx, r14d
    call draft_text
    call queue_draft
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -> eax = 1 if we're logged in and caught up, so requests can go out now
can_send:
    xor eax, eax
    cmp byte [authed], 0
    je .done
    cmp byte [resync], 0
    sete al
.done:
    ret

; -> eax = 1 if online and logged in, else the footer says why not
require_online:
    call can_send
    test eax, eax
    jnz .done
    lea rsi, [st_offline]
    mov edx, st_offline_len
    call set_status
    xor eax, eax
.done:
    ret

; rsi = key, edx = length, rcx = name, r8d = length
sync_create_team:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rsi
    mov r12d, edx
    mov r13, rcx
    mov r14d, r8d
    call require_online
    test eax, eax
    jz .done
    lea rdi, [out_msg]
    mov esi, MSG_CREATE_TEAM
    call wr_u8
    mov rsi, rbx
    mov edx, r12d
    call wr_str
    mov rsi, r13
    mov edx, r14d
    call wr_str
    call send_built
    mov [select_new], al
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rsi = username, edx = length
sync_add_member:
    push rsi
    push rdx
    call require_online
    pop rdx
    pop rsi
    test eax, eax
    jz .done
    push rdx
    push rsi
    lea rdi, [out_msg]
    mov esi, MSG_ADD_MEMBER
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    pop rsi
    pop rdx
    call wr_str
    call send_built
.done:
    ret

; edi = user id, yourself to leave
sync_remove_member:
    push rdi
    call require_online
    pop rdi
    test eax, eax
    jz .done
    push rdi
    lea rdi, [out_msg]
    mov esi, MSG_REMOVE_MEMBER
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    pop rsi
    call wr_u32
    call send_built
.done:
    ret

; edi = team id
sync_select_team:
    cmp edi, [current_team]
    je .done
    mov [current_team], edi
    call clear_team_view
    call can_send
    test eax, eax
    jz .done
    jmp send_subscribe
.done:
    ret

; Opens an issue in the detail view, 0 to close it. edi = issue id
sync_open_issue:
    mov [detail_issue], edi
    xor eax, eax
    mov [desc_len], eax
    mov [comment_count], eax
    mov [detail_loaded], al
    call can_send
    test eax, eax
    jz .done
    cmp byte [loaded], 0
    je .done                                ; the snapshot's end asks for it
    call send_open_issue
.done:
    jmp rebuild_view

; Opens a conversation in the panel. edi = peer, 0 for the team's channel
sync_open_chat:
    mov [chat_peer], edi
    mov byte [chat_open], 1
    xor eax, eax
    mov [chat_count], eax
    mov [chat_loaded], al
    call clear_unread
    call can_send
    test eax, eax
    jz .done
    cmp byte [loaded], 0
    je .done                                ; the snapshot's end asks for it
    call send_open_chat
.done:
    jmp rebuild_chat

; Closes the open conversation, here and on the server.
sync_close_chat:
    cmp byte [chat_open], 0
    je .done
    mov byte [chat_open], 0
    mov dword [chat_count], 0
    call rebuild_chat
    call can_send
    test eax, eax
    jz .done                                ; subscribing again closes it on the server anyway
    mov esi, -1
    jmp send_chat_request
.done:
    ret

; Asks for the open conversation's messages.
send_open_chat:
    mov byte [chat_loaded], 0
    cmp byte [chat_open], 0
    je .done
    mov esi, [chat_peer]
    jmp send_chat_request
.done:
    ret

; esi = the peer to open, or -1 to close
send_chat_request:
    push rsi
    lea rdi, [out_msg]
    mov esi, MSG_OPEN_CHAT
    call wr_u8
    pop rsi
    call wr_u32
    jmp send_built

; edi = peer -> eax = its index in unread, or -1
find_unread:
    xor eax, eax
.loop:
    cmp eax, [unread_count]
    jae .none
    cmp [unread + rax * 4], edi
    je .done
    inc eax
    jmp .loop
.none:
    mov eax, -1
.done:
    ret

; edi = peer
mark_unread:
    call find_unread
    cmp eax, -1
    jne .done
    mov eax, [unread_count]
    cmp eax, UNREAD_MAX
    jae .done
    mov [unread + rax * 4], edi
    inc dword [unread_count]
.done:
    ret

; edi = peer
clear_unread:
    call find_unread
    cmp eax, -1
    je .done
    dec dword [unread_count]                ; the last one fills the gap
    mov ecx, [unread_count]
    mov edx, [unread + rcx * 4]
    mov [unread + rax * 4], edx
.done:
    ret

; Reads a message off the wire into a chat row. rdi = row -> eax = who it went to
read_message:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    call rd_u32
    mov [rbx + CH_ID], eax
    call rd_u32
    mov [rbx + CH_AUTHOR], eax
    call rd_u32
    mov r12d, eax
    call rd_u32
    mov [rbx + CH_CREATED], eax
    call rd_str16
    cmp edx, MESSAGE_MAX
    ja .bad
    mov [rbx + CH_LEN], dx
    mov byte [rbx + CH_PENDING], 0
    lea rdi, [rbx + CH_TEXT]
    mov rsi, rax
    call put_mem
    call rd_u8
    mov [rbx + CH_EDITED], al
    lea rdi, [rbx + CH_IMAGE]
    call read_image_ref
    jmp .done
.bad:
    mov byte [rd_bad], 1
.done:
    mov eax, r12d
    add rsp, 8
    pop r12
    pop rbx
    ret

; MSG_CHAT: a new message. Shown if its conversation is open, otherwise it marks that one unread.
on_chat:
    push rbx
    push r12
    push r13
    sub rsp, CH_SIZE + 8
    call rd_u32
    mov ebx, eax                            ; team
    mov rdi, rsp
    call read_message
    cmp byte [rd_bad], 0
    jne .done
    cmp ebx, [current_team]
    jne .done
    ; The conversation it's in, from our side: a channel, whoever we sent
    ; it to, or whoever sent it to us.
    mov r12d, eax
    test r12d, r12d
    jz .have_peer
    js .have_peer                           ; another channel
    mov r13d, [rsp + CH_AUTHOR]
    cmp r13d, [my_id]
    je .have_peer
    mov r12d, r13d
.have_peer:
    cmp byte [chat_open], 0
    je .unread
    cmp r12d, [chat_peer]
    jne .unread
    cmp byte [chat_loaded], 0
    je .done                                ; CHAT_HISTORY will include it
    mov rsi, rsp
    call append_chat
    call rebuild_chat
    jmp .done
.unread:
    mov eax, [rsp + CH_AUTHOR]
    cmp eax, [my_id]
    je .done
    mov edi, r12d
    call mark_unread
.done:
    add rsp, CH_SIZE + 8
    pop r13
    pop r12
    pop rbx
    ret

; Adds a message to the open conversation, dropping the oldest when full. rsi = row
append_chat:
    push rbx
    mov rbx, rsi
    cmp dword [chat_count], CHAT_MAX
    jb .copy
    lea rdi, [chat_msgs]
    lea rsi, [chat_msgs + CH_SIZE]
    mov edx, (CHAT_MAX - 1) * CH_SIZE
    call memmove
    dec dword [chat_count]
.copy:
    mov eax, [chat_count]
    imul eax, eax, CH_SIZE
    lea rdi, [chat_msgs + rax]
    mov rsi, rbx
    mov ecx, CH_SIZE
    rep movsb
    inc dword [chat_count]
    pop rbx
    ret

; MSG_CHAT_HISTORY: the open conversation's newest messages, replacing what's shown.
on_chat_history:
    push rbx
    push r12
    push r13
    call rd_u32
    mov ebx, eax
    call rd_u32
    mov r12d, eax
    call rd_u8
    mov r13d, eax
    cmp ebx, [current_team]
    jne .skip
    cmp byte [chat_open], 0
    je .skip
    cmp r12d, [chat_peer]
    jne .skip
    cmp r13d, CHAT_MAX
    ja .bad
    mov [chat_count], r13d
    lea rbx, [chat_msgs]
.message:
    test r13d, r13d
    jz .read
    mov rdi, rbx
    call read_message
    add rbx, CH_SIZE
    dec r13d
    jmp .message
.read:
    mov byte [chat_loaded], 1
    mov edi, r12d                           ; UNREAD may have come in after we asked
    call clear_unread
    call rebuild_chat
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

; MSG_UNREAD: the conversations with messages we haven't seen, replacing the old list.
on_unread:
    push rbx
    push r12
    sub rsp, 8
    call rd_u32
    mov ebx, eax
    call rd_u8
    mov r12d, eax
    cmp ebx, [current_team]
    jne .skip
    cmp r12d, UNREAD_MAX
    ja .bad
    mov dword [unread_count], 0
.peer:
    test r12d, r12d
    jz .done
    call rd_u32
    mov edi, eax
    call mark_unread
    dec r12d
    jmp .peer
.bad:
    mov byte [rd_bad], 1
    jmp .done
.skip:
    call rd_skip
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; The open conversation with our unsent messages to it after: what the chat shows.
rebuild_chat:
    push rbx
    push rbp
    push r12
    mov ecx, [chat_count]
    mov [view_chat_count], ecx
    imul ecx, ecx, CH_SIZE
    lea rdi, [view_chat]
    lea rsi, [chat_msgs]
    rep movsb
    cmp byte [chat_open], 0
    je .done
    lea rbx, [pending]
    mov ebp, [pending_count]
.op:
    test ebp, ebp
    jz .done
    cmp byte [rbx + PO_KIND], OP_MESSAGE
    jne .next
    mov eax, [current_team]
    cmp [rbx + PO_TEAM], eax
    jne .next
    mov eax, [chat_peer]
    cmp [rbx + PO_ISSUE], eax
    jne .next
    mov eax, [view_chat_count]
    imul eax, eax, CH_SIZE
    lea r12, [view_chat + rax]
    inc dword [view_chat_count]
    mov dword [r12 + CH_ID], 0
    mov eax, [my_id]
    mov [r12 + CH_AUTHOR], eax
    call unix_now
    mov [r12 + CH_CREATED], eax
    mov byte [r12 + CH_PENDING], 1
    mov byte [r12 + CH_EDITED], 0
    lea rdi, [r12 + CH_IMAGE]
    mov rsi, rbx
    call op_image_ref
    movzx ecx, word [rbx + PO_BODY_LEN]
    mov [r12 + CH_LEN], cx
    lea rdi, [r12 + CH_TEXT]
    lea rsi, [rbx + PO_BODY]
    rep movsb
.next:
    add rbx, PO_SIZE
    dec ebp
    jmp .op
.done:
    mov byte [need_redraw], 1
    pop r12
    pop rbp
    pop rbx
    ret

; Unsynced changes are dropped along with the session.
sync_logout:
    cmp byte [authed], 0
    je sync_reset
    lea rdi, [out_msg]
    mov esi, MSG_LOGOUT
    call wr_u8
    call send_built
    jmp sync_reset

; edi = MSG_LOGIN or MSG_REGISTER, rsi = username, edx = its length,
; rcx = password, r8d = its length
sync_auth:
    cmp byte [auth_busy], 0
    jne .done
    cmp byte [net_state], NET_OPEN
    jne .no_server
    push rcx
    push r8
    push rdx
    push rsi
    mov esi, edi
    lea rdi, [out_msg]
    call wr_u8
    pop rsi
    pop rdx
    call wr_str
    pop rdx
    pop rsi
    call wr_str
    call send_built
    lea rdi, [out_msg]                      ; it held the password
    mov esi, 512
    call wipe
    mov byte [auth_busy], 1
    mov dword [auth_msg_len], 0
    mov byte [need_redraw], 1
.done:
    ret
.no_server:
    ; The server drops a connection that hasn't logged in after 30 seconds,
    ; so a login screen left open is often mid-reconnect. Try right away and
    ; send this once we're through.
    mov [auth_queued], dil
    mov byte [auth_busy], 1
    mov dword [auth_msg_len], 0
    mov qword [net_retry_at], 0
    mov byte [need_redraw], 1
    ret

; edi = issue id -> rax = its row in view_issues, or 0
find_view_issue:
    lea rax, [view_issues]
    mov ecx, [view_count]
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + CI_ID], edi
    je .done
    add rax, CI_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; The confirmed state with the pending ops applied: what the window shows.
rebuild_view:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov ecx, [issue_count]
    mov [view_count], ecx
    imul ecx, ecx, CI_SIZE
    lea rdi, [view_issues]
    lea rsi, [issues]
    rep movsb
    lea rdi, [view_labels]                  ; view_projects follows view_labels
    lea rsi, [labels]
    mov ecx, LABEL_SLOTS * LB_SIZE + PROJECT_SLOTS * PJ_SIZE
    rep movsb
    lea rax, [desc]
    mov [view_desc], rax
    mov eax, [desc_len]
    mov [view_desc_len], eax
    mov ecx, [comment_count]
    mov [view_comment_count], ecx
    imul ecx, ecx, CC_SIZE
    lea rdi, [view_comments]
    lea rsi, [comments]
    rep movsb

    lea rbx, [pending]
    mov ebp, [pending_count]
.op:
    test ebp, ebp
    jz .done
    mov eax, [current_team]
    cmp [rbx + PO_TEAM], eax
    jne .next
    movzx eax, byte [rbx + PO_KIND]
    cmp eax, OP_CREATE_ISSUE
    je .create
    cmp eax, OP_SET_FIELD
    je .set
    cmp eax, OP_DELETE_ISSUE
    je .delete
    cmp eax, OP_COMMENT
    je .comment
    cmp eax, OP_SET_LABEL
    je .label
    cmp eax, OP_SET_PROJECT
    je .project
    cmp eax, OP_EDIT_COMMENT
    je .comment_op
    cmp eax, OP_DELETE_COMMENT
    je .comment_op
    jmp .next                               ; messages show in the chat

.create:
    mov eax, [view_count]
    cmp eax, VIEW_MAX
    jae .next
    imul eax, eax, CI_SIZE
    lea r12, [view_issues + rax]
    inc dword [view_count]
    mov rdi, r12
    mov esi, CI_SIZE
    call wipe
    mov eax, [rbx + PO_NUM]
    or eax, PENDING_ID
    mov [r12 + CI_ID], eax
    mov eax, [rbx + PO_ASSIGNEE]
    mov [r12 + CI_ASSIGNEE], eax
    mov eax, [my_id]
    mov [r12 + CI_CREATOR], eax
    call unix_now
    mov [r12 + CI_CREATED], eax
    mov [r12 + CI_UPDATED], eax
    mov eax, [rbx + PO_LABELS]
    mov [r12 + CI_LABELS], ax
    mov al, [rbx + PO_STATUS]
    mov [r12 + CI_STATUS], al
    mov al, [rbx + PO_PRIORITY]
    mov [r12 + CI_PRIORITY], al
    mov al, [rbx + PO_PROJECT]
    mov [r12 + CI_PROJECT], al
    mov byte [r12 + CI_PENDING], 1
    lea rdi, [r12 + CI_TITLE_LEN]
    call .copy_text
    jmp .next

.set:
    mov edi, [rbx + PO_ISSUE]
    call find_view_issue
    test rax, rax
    jz .next
    mov r12, rax
    mov byte [r12 + CI_PENDING], 1
    mov ecx, [rbx + PO_VALUE]
    movzx eax, byte [rbx + PO_FIELD]
    cmp eax, FIELD_STATUS
    je .status
    cmp eax, FIELD_PRIORITY
    je .priority
    cmp eax, FIELD_ASSIGNEE
    je .assignee
    cmp eax, FIELD_PROJECT
    je .set_project
    cmp eax, FIELD_LABELS
    je .labels
    cmp eax, FIELD_TITLE
    je .title
    mov eax, [rbx + PO_ISSUE]               ; description
    cmp eax, [detail_issue]
    jne .next
    lea rax, [rbx + PO_BODY]
    mov [view_desc], rax
    movzx eax, word [rbx + PO_BODY_LEN]
    mov [view_desc_len], eax
    jmp .next
.status:
    mov [r12 + CI_STATUS], cl
    jmp .next
.priority:
    mov [r12 + CI_PRIORITY], cl
    jmp .next
.assignee:
    mov [r12 + CI_ASSIGNEE], ecx
    jmp .next
.set_project:
    mov [r12 + CI_PROJECT], cl
    jmp .next
.labels:
    mov [r12 + CI_LABELS], cx
    jmp .next
.title:
    lea rdi, [r12 + CI_TITLE_LEN]
    call .copy_text
    jmp .next

.delete:
    mov edi, [rbx + PO_ISSUE]
    call find_view_issue
    test rax, rax
    jz .next
    mov rdi, rax
    dec dword [view_count]
    mov eax, [view_count]
    imul eax, eax, CI_SIZE
    lea rsi, [view_issues + rax]
    mov ecx, CI_SIZE
    rep movsb
    jmp .next

.comment:
    mov eax, [rbx + PO_ISSUE]
    cmp eax, [detail_issue]
    jne .next
    mov eax, [view_comment_count]
    cmp eax, VIEW_COMMENTS
    jae .next
    imul eax, eax, CC_SIZE
    lea r12, [view_comments + rax]
    inc dword [view_comment_count]
    mov dword [r12 + CC_ID], 0
    mov eax, [my_id]
    mov [r12 + CC_AUTHOR], eax
    call unix_now
    mov [r12 + CC_CREATED], eax
    mov byte [r12 + CC_PENDING], 1
    mov byte [r12 + CC_EDITED], 0
    lea rdi, [r12 + CC_IMAGE]
    mov rsi, rbx
    call op_image_ref
    movzx ecx, word [rbx + PO_BODY_LEN]
    mov [r12 + CC_LEN], cx
    lea rdi, [r12 + CC_TEXT]
    lea rsi, [rbx + PO_BODY]
    rep movsb
    jmp .next
.comment_op:
    mov rdi, rbx
    call apply_comment_op
    jmp .next

.label:
    movzx eax, byte [rbx + PO_FIELD]
    imul edi, eax, LB_SIZE
    add rdi, view_labels
    call .copy_named
    test eax, eax
    jnz .next
    movzx ecx, byte [rbx + PO_FIELD]
    mov edx, 1
    shl edx, cl
    jmp .forget
.project:
    movzx eax, byte [rbx + PO_FIELD]
    dec eax
    imul edi, eax, PJ_SIZE
    add rdi, view_projects
    call .copy_named
    test eax, eax
    jnz .next
    xor edx, edx
    movzx ecx, byte [rbx + PO_FIELD]
.forget:
    lea rdi, [view_issues]
    mov esi, [view_count]
    call forget_named

.next:
    add rbx, PO_SIZE
    dec ebp
    jmp .op
.done:
    mov byte [need_redraw], 1
    call rebuild_chat
    call ui_view_changed
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; rdi = u8 length then bytes <- the op's text
.copy_text:
    movzx ecx, byte [rbx + PO_TEXT_LEN]
    mov [rdi], cl
    inc rdi
    lea rsi, [rbx + PO_TEXT]
    rep movsb
    ret

; rdi = label or project slot <- the op's color and name. -> eax = name length
.copy_named:
    mov eax, [rbx + PO_VALUE]
    mov [rdi + LB_COLOR], eax
    add rdi, LB_NAME_LEN
    call .copy_text
    movzx eax, byte [rbx + PO_TEXT_LEN]
    ret
