; ui-test's checks of the dashboards: the account dialog with its sessions,
; teams and Delete account, and team settings' Overview with Delete team and
; Transfer ownership. ui_test.asm includes this at its end.

section .rodata
n_acc_sidebar:  db "clicking your name in the sidebar opens the account dialog", 0
n_acc_read:     db "ACCOUNT fills in the join date, the sessions and each team's size", 0
n_acc_too_many: db "an ACCOUNT with more sessions than fit is refused, keeping the last one", 0
n_acc_sessions: db "Log out is offered for other sessions only, and everywhere else once there are two", 0
n_acc_delete:   db "Delete account needs the password, then asks first", 0
n_acc_teams:    db "the Teams tab offers Settings and Leave, and Open for teams not open", 0
n_acc_leave:    db "Leave on the Teams tab asks first", 0
n_overview:     db "team settings open on the Overview, with Delete team for owners only", 0
n_delete_key:   db "Delete team needs the team's key in either case, then asks first", 0
n_transfer:     db "Transfer ownership asks first, and isn't offered for an owner", 0
n_au_transfer:  db "a transfer by a deleted account reads as Deleted user, linked from the Overview", 0
t_eng:          db "eng", 0
t_enx:          db "ENX", 0
t_secret:       db "password1", 0
; MSG_ACCOUNT past the type byte: this session and another, and Eng with two
; members and three open issues.
t_account:      dd 1700000000
                db 2
                dd 5, 1700000000, 1700000500
                db SS_CURRENT | SS_ONLINE
                dd 6, 1700000100, 1700000200
                db 0
                db 1
                dd 1
                db 2
                dw 3
t_account_len   equ $ - t_account
t_account_bad:  dd 0
                db ACCOUNT_SESSIONS + 1
t_account_bad_len equ $ - t_account_bad
; MSG_AUDIT past the type byte: an account since deleted handed maya the team.
t_audit_transfer: dd 1
                db 1
                db AU_TRANSFER
                dd 9, 2, 0, 0
                db 0, 4, "maya", 0
t_audit_transfer_len equ $ - t_audit_transfer

section .text

; Opening the dialog, and MSG_ACCOUNT as it arrives.
account_tests:
    push rbx
    mov edi, A_ACCOUNT
    mov esi, ACC_PROFILE
    call click_hit
    xor ebx, ebx
    cmp byte [modal], M_ACCOUNT
    jne .sidebar
    cmp dword [account_tab], ACC_PROFILE
    sete bl
.sidebar:
    mov esi, ebx
    lea rdi, [n_acc_sidebar]
    call check

    lea rdi, [t_account]
    mov esi, t_account_len
    call rd_begin
    call on_account
    xor ebx, ebx
    call rd_ok
    test eax, eax
    jz .read
    cmp dword [joined], 1700000000
    jne .read
    cmp dword [session_count], 2
    jne .read
    mov edi, 1
    call find_team_size
    test rax, rax
    jz .read
    cmp word [rax + AT_OPEN], 3
    sete bl
.read:
    mov esi, ebx
    lea rdi, [n_acc_read]
    call check

    lea rdi, [t_account_bad]
    mov esi, t_account_bad_len
    call rd_begin
    call on_account
    call rd_ok
    mov ebx, eax
    xor ebx, 1
    xor eax, eax
    cmp dword [session_count], 2
    sete al
    and ebx, eax
    mov esi, ebx
    lea rdi, [n_acc_too_many]
    call check

    call frame
    call account_security_tests
    call account_delete_tests
    call account_teams_tests
    call close_modal
    pop rbx
    ret

; The Security tab's sessions.
account_security_tests:
    push rbx
    mov edi, A_ACCOUNT_TAB
    mov esi, ACC_SECURITY
    call click_hit
    mov edi, A_END_SESSION
    mov esi, 6
    call has_hit
    mov ebx, eax
    mov edi, A_END_SESSION
    mov esi, 5
    call has_hit
    xor eax, 1
    and ebx, eax
    mov edi, A_END_SESSION
    mov esi, -1
    call has_hit
    and ebx, eax
    mov dword [session_count], 1
    call frame
    mov edi, A_END_SESSION
    mov esi, -1
    call has_hit
    xor eax, 1
    and ebx, eax
    mov dword [session_count], 2
    mov esi, ebx
    lea rdi, [n_acc_sessions]
    call check
    pop rbx
    ret

; Delete account on the Profile tab: empty, typed, asked, sent.
account_delete_tests:
    push rbx
    mov edi, A_ACCOUNT_TAB
    mov esi, ACC_PROFILE
    call click_hit
    mov dword [account_scroll], 100000      ; it's at the bottom
    call frame
    xor ebx, ebx
    mov edi, A_DELETE_ACCOUNT
    xor esi, esi
    call click_hit
    cmp dword [focus], F_DELETE_PASS
    jne .delete
    cmp dword [account_armed], 0
    jne .delete
    mov edi, F_DELETE_PASS
    lea rsi, [t_secret]
    call type_into
    mov edi, A_DELETE_ACCOUNT
    xor esi, esi
    call click_hit
    cmp dword [account_armed], -1
    jne .delete
    mov dword [status_len], 0
    mov edi, A_DELETE_ACCOUNT
    xor esi, esi
    call click_hit
    cmp dword [account_armed], 0
    jne .delete
    cmp dword [status_len], st_offline_len  ; we tried to send it
    sete bl
.delete:
    mov esi, ebx
    lea rdi, [n_acc_delete]
    call check
    mov dword [status_len], 0
    pop rbx
    ret

; The Teams tab, with Eng open.
account_teams_tests:
    push rbx
    mov edi, A_ACCOUNT_TAB
    mov esi, ACC_TEAMS
    call click_hit
    mov edi, A_TEAM_SETTINGS
    mov esi, 1
    call has_hit
    mov ebx, eax
    mov edi, A_LEAVE_TEAM
    mov esi, 1
    call has_hit
    and ebx, eax
    mov edi, A_GO_TEAM
    mov esi, 1
    call has_hit
    xor eax, 1
    and ebx, eax
    mov esi, ebx
    lea rdi, [n_acc_teams]
    call check

    xor ebx, ebx
    mov edi, A_LEAVE_TEAM
    mov esi, 1
    call click_hit
    cmp dword [account_armed], 1
    jne .leave
    mov dword [status_len], 0
    mov edi, A_LEAVE_TEAM
    mov esi, 1
    call click_hit
    cmp dword [account_armed], 0
    jne .leave
    cmp dword [status_len], st_offline_len
    sete bl
.leave:
    mov esi, ebx
    lea rdi, [n_acc_leave]
    call check
    mov dword [status_len], 0
    pop rbx
    ret

; Team settings' Overview, Delete team and Transfer ownership, with maya on the team.
team_dashboard_tests:
    push rbx
    call add_maya
    mov edi, F_NONE
    call open_team_settings
    mov dword [settings_scroll], 100000     ; Delete team is at the bottom
    call frame
    xor ebx, ebx
    cmp dword [settings_tab], TAB_OVERVIEW
    jne .overview
    mov edi, A_DELETE_TEAM
    xor esi, esi
    call has_hit
    mov ebx, eax
    mov byte [teams + CO_ROLE], ROLE_MEMBER
    call frame
    mov edi, A_DELETE_TEAM
    xor esi, esi
    call has_hit
    xor eax, 1
    and ebx, eax
    mov byte [teams + CO_ROLE], ROLE_OWNER
    mov dword [settings_scroll], 100000     ; a member's shorter page clamped it
    call frame
.overview:
    mov esi, ebx
    lea rdi, [n_overview]
    call check

    call delete_team_tests
    call transfer_tests
    call close_modal
    mov dword [member_count], 1
    mov dword [audit_count], 0
    pop rbx
    ret

; Delete team: a wrong key, then the right one in lower case.
delete_team_tests:
    push rbx
    xor ebx, ebx
    mov edi, F_DELETE_KEY
    lea rsi, [t_enx]
    call type_into
    mov edi, A_DELETE_TEAM
    xor esi, esi
    call click_hit
    cmp byte [team_delete_armed], 0
    jne .key
    cmp dword [status_len], st_type_key_len
    jne .key
    mov edi, F_DELETE_KEY
    call field_clear
    mov edi, F_DELETE_KEY
    lea rsi, [t_eng]
    call type_into
    mov edi, A_DELETE_TEAM
    xor esi, esi
    call click_hit
    cmp byte [team_delete_armed], 1
    jne .key
    mov dword [status_len], 0
    mov edi, A_DELETE_TEAM
    xor esi, esi
    call click_hit
    cmp byte [team_delete_armed], 0
    jne .key
    cmp dword [status_len], st_offline_len
    sete bl
.key:
    mov esi, ebx
    lea rdi, [n_delete_key]
    call check
    mov dword [status_len], 0
    mov edi, F_DELETE_KEY
    call field_clear
    pop rbx
    ret

; Transfer ownership on maya's page, and the audit entry it leaves.
transfer_tests:
    push rbx
    mov edi, A_TAB
    mov esi, TAB_MEMBERS
    call click_hit
    mov edi, A_MANAGE
    mov esi, 2
    call click_hit
    mov dword [settings_scroll], 100000     ; the buttons are at the bottom
    call frame
    xor ebx, ebx
    mov edi, A_TRANSFER
    xor esi, esi
    call click_hit
    test eax, eax
    jz .transfer
    cmp dword [member_armed], 2
    jne .transfer
    cmp dword [armed_action], A_TRANSFER
    jne .transfer
    mov byte [members + CM_SIZE + CM_ROLE], ROLE_OWNER
    call frame
    mov edi, A_TRANSFER
    xor esi, esi
    call has_hit
    mov ebx, eax
    xor ebx, 1
    mov byte [members + CM_SIZE + CM_ROLE], ROLE_MEMBER
.transfer:
    mov esi, ebx
    lea rdi, [n_transfer]
    call check

    lea rdi, [t_audit_transfer]
    mov esi, t_audit_transfer_len
    call rd_begin
    call on_audit
    xor ebx, ebx
    call rd_ok
    test eax, eax
    jz .audit
    cmp dword [audit_count], 1
    jne .audit
    lea rdi, [audit_rows + AL_ACTOR_LEN]
    call audit_name
    lea rax, [s_deleted_user]
    cmp rdx, rax
    jne .audit
    mov edi, A_TAB
    mov esi, TAB_OVERVIEW
    call click_hit
    mov dword [settings_scroll], 100000     ; down past the roles to the newest entries
    call frame
    ; The audit log's tab, and View all under the newest entries.
    mov ecx, [hit_count]
    lea rax, [hits]
    xor edx, edx
.hit:
    test ecx, ecx
    jz .counted
    cmp dword [rax + HIT_ACTION], A_TAB
    jne .next
    cmp dword [rax + HIT_ARG], TAB_AUDIT
    jne .next
    inc edx
.next:
    add rax, HIT_SIZE
    dec ecx
    jmp .hit
.counted:
    cmp edx, 2
    sete bl
.audit:
    mov esi, ebx
    lea rdi, [n_au_transfer]
    call check
    pop rbx
    ret
