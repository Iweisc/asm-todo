; The audit log: reading MSG_AUDIT and drawing its entries, for the audit
; log tab and the overview's newest few.

; An audit entry, as MSG_AUDIT lists it.
%define AL_KIND         0               ; u8, AU_*
%define AL_ACTOR        4
%define AL_TARGET       8
%define AL_AT           12
%define AL_EXTRA        16
%define AL_ACTOR_LEN    20
%define AL_ACTOR_NAME   21              ; USERNAME_MAX bytes
%define AL_TARGET_LEN   53
%define AL_TARGET_NAME  54              ; USERNAME_MAX bytes
%define AL_REASON_LEN   86
%define AL_REASON       87              ; REASON_MAX bytes
%define AL_SIZE         188
fits AL_KIND, 1, AL_ACTOR
fits AL_ACTOR_NAME, USERNAME_MAX, AL_TARGET_LEN
fits AL_TARGET_NAME, USERNAME_MAX, AL_REASON_LEN
fits AL_REASON, REASON_MAX, AL_SIZE

section .rodata
text s_no_audit,        "Nothing's happened yet."
text s_deleting,        ", deleting "
text s_of_messages,     " of their messages"
text s_deleted_user,    "Deleted user"
text v_invited,         " invited "
text v_removed,         " removed "
text v_banned,          " banned "
text v_unbanned,        " unbanned "
text v_timed_out,       " timed out "
text v_ended,           " ended the timeout of "
text v_made,            " made "
text v_deleted_message, " deleted a message by "
text v_deleted_comment, " deleted a comment by "
text v_renamed,         " renamed the team"
text v_saved_role,      " changed the role "
text v_deleted_role,    " deleted the role "
text v_member_roles,    " changed the roles of "
text v_nickname,        " changed the nickname of "
text v_channel,         " changed the settings of "
text v_automod,         " changed the AutoMod rules"
text v_automod_block,   " had a message blocked by AutoMod"
text v_transferred,     " transferred ownership to "
text s_an_owner,        " an owner"
text s_a_member,        " a member"

; What follows the verb in an audit entry, by AU_* - 1: 0 the target, 1
; nothing, 2 the reason, which is a role's name, 3 the channel
audit_objects:  db 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 0, 0, 3, 1, 1, 0
AUDIT_KINDS     equ $ - audit_objects
align 8
audit_verbs:    NAME v_invited          ; by AU_* - 1
                NAME v_removed
                NAME v_banned
                NAME v_unbanned
                NAME v_timed_out
                NAME v_ended
                NAME v_made
                NAME v_deleted_message
                NAME v_deleted_comment
                NAME v_renamed
                NAME v_saved_role
                NAME v_deleted_role
                NAME v_member_roles
                NAME v_nickname
                NAME v_channel
                NAME v_automod
                NAME v_automod_block
                NAME v_transferred
role_articles:  NAME s_an_owner         ; by ROLE_* - 1
                NAME s_a_member

section .bss
alignb 4
audit_count:    resd 1
audit_rows:     resb AUDIT_SHOWN * AL_SIZE

section .text

; MSG_AUDIT: the newest of the current team's audit log, newest first.
on_audit:
    push rbx
    push r12
    push r13
    call rd_u32
    mov ebx, eax
    call rd_u8
    mov r12d, eax
    cmp ebx, [current_team]
    jne .skip
    cmp r12d, AUDIT_SHOWN
    ja .bad
    lea rbx, [audit_rows]
    xor r13d, r13d
.entry:
    cmp r13d, r12d
    jae .read
    call rd_u8
    mov [rbx + AL_KIND], al
    call rd_u32
    mov [rbx + AL_ACTOR], eax
    call rd_u32
    mov [rbx + AL_TARGET], eax
    call rd_u32
    mov [rbx + AL_AT], eax
    call rd_u32
    mov [rbx + AL_EXTRA], eax
    lea rdi, [rbx + AL_ACTOR_LEN]
    mov esi, USERNAME_MAX
    call read_named_str
    lea rdi, [rbx + AL_TARGET_LEN]
    mov esi, USERNAME_MAX
    call read_named_str
    lea rdi, [rbx + AL_REASON_LEN]
    mov esi, REASON_MAX
    call read_named_str
    add rbx, AL_SIZE
    inc r13d
    jmp .entry
.read:
    mov [audit_count], r12d
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

; What follows the target in an entry: how long a timeout was for, what
; someone was made, or how much of a banned member's messages went.
; rdi = cursor, rsi = entry -> rdi advanced
put_audit_suffix:
    movzx eax, byte [rsi + AL_KIND]
    mov ecx, [rsi + AL_EXTRA]
    cmp eax, AU_ROLE
    je .role
    cmp eax, AU_BAN
    je .ban
    cmp eax, AU_TIMEOUT
    jne .done
    push rcx
    lea rsi, [s_for]
    mov edx, s_for_len
    call put_mem
    pop rcx
    jmp put_duration
.role:
    dec ecx
    cmp ecx, ROLE_MEMBER - 1
    ja .done
    shl ecx, 4
    mov rsi, [role_articles + rcx]
    mov edx, [role_articles + rcx + 8]
    jmp put_mem
.ban:
    test ecx, ecx
    jz .done
    push rcx
    lea rsi, [s_deleting]
    mov edx, s_deleting_len
    call put_mem
    pop rcx
    call put_duration
    lea rsi, [s_of_messages]
    mov edx, s_of_messages_len
    jmp put_mem
.done:
    ret

; What an entry's verb acts on, when it isn't a member: a role's name,
; @everyone, or a channel. rdi = cursor, rsi = entry -> rdi advanced
put_audit_object:
    movzx eax, byte [rsi + AL_KIND]
    movzx eax, byte [audit_objects + rax - 1]
    cmp eax, 3
    je .channel
    cmp dword [rsi + AL_EXTRA], 0
    je .everyone
.reason:
    movzx edx, byte [rsi + AL_REASON_LEN]
    lea rsi, [rsi + AL_REASON]
    jmp put_mem
.everyone:
    cmp byte [rsi + AL_KIND], AU_SAVE_ROLE
    jne .reason                             ; a deleted role's slot isn't kept
    lea rsi, [s_everyone]
    mov edx, s_everyone_len
    jmp put_mem
.channel:
    mov byte [rdi], '#'
    inc rdi
    cmp dword [rsi + AL_EXTRA], 0
    jne .reason
    lea rsi, [s_general + 1]                ; it has its own "#"
    mov edx, s_general_len - 1
    jmp put_mem

; rdi = an entry's name, at its length byte -> rdx = the name, ecx = its
; length, or "Deleted user" for an account that's gone
audit_name:
    lea rdx, [rdi + 1]
    movzx ecx, byte [rdi]
    test ecx, ecx
    jnz .done
    lea rdx, [s_deleted_user]
    mov ecx, s_deleted_user_len
.done:
    ret

; One audit entry: "maya banned sam" and when, and why if they said.
; edi = x, esi = top, rdx = entry
draw_audit_row:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    movzx r14d, byte [r13 + AL_KIND]
    dec r14d
    cmp r14d, AUDIT_KINDS - 1
    ja .done                                ; a kind newer than us
    shl r14d, 4
    lea rdi, [r13 + AL_ACTOR_LEN]
    call audit_name
    mov r8, rdx
    lea edi, [ebx + 28]
    lea esi, [r12d + 14]
    mov edx, 24
    mov ecx, [r13 + AL_ACTOR]
    call draw_avatar
    lea rdi, [r13 + AL_ACTOR_LEN]
    call audit_name
    lea edi, [ebx + 62]
    lea esi, [r12d + 24]
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    mov edi, eax
    lea esi, [r12d + 24]
    mov rdx, [audit_verbs + r14]
    mov ecx, [audit_verbs + r14 + 8]
    mov r8d, INK(C_DIM, ST_BODY)
    call draw_text
    movzx ecx, byte [r13 + AL_KIND]
    movzx ecx, byte [audit_objects + rcx - 1]
    cmp ecx, 1
    je .when
    ja .object
    push rax
    lea rdi, [r13 + AL_TARGET_LEN]
    call audit_name
    pop rdi
    lea esi, [r12d + 24]
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_text
    mov r14d, eax
    lea rdi, [scratch]
    mov rsi, r13
    call put_audit_suffix
    mov rcx, rdi
    mov edi, r14d
    lea esi, [r12d + 24]
    mov r8d, INK(C_DIM, ST_BODY)
    call draw_scratch
    jmp .when
.object:
    mov r14d, eax
    lea rdi, [scratch]
    mov rsi, r13
    call put_audit_object
    mov rcx, rdi
    mov edi, r14d
    lea esi, [r12d + 24]
    mov r8d, INK(C_TEXT, ST_MEDIUM)
    call draw_scratch
.when:
    lea rdi, [scratch]
    mov esi, [r13 + AL_AT]
    call put_ago
    movzx eax, byte [r13 + AL_KIND]
    cmp byte [audit_objects + rax - 1], 2
    jae .line                               ; the reason was the object
    cmp byte [r13 + AL_REASON_LEN], 0
    je .line
    call put_middot
    lea rsi, [r13 + AL_REASON]
    movzx edx, byte [r13 + AL_REASON_LEN]
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
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; The audit log, newest first, or a line saying it's empty. edi = x, esi = top
draw_audit:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov r13d, [audit_count]
    test r13d, r13d
    jz .none
    lea r14, [audit_rows]
.entry:
    mov edi, ebx
    mov esi, r12d
    mov rdx, r14
    call draw_audit_row
    add r12d, LIST_ROW_H
    add r14, AL_SIZE
    dec r13d
    jnz .entry
    jmp .done
.none:
    lea edi, [ebx + 28]
    lea esi, [r12d + 26]
    lea rdx, [s_no_audit]
    mov ecx, s_no_audit_len
    mov r8d, INK(C_DIM, ST_BODY)
    call draw_text
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
