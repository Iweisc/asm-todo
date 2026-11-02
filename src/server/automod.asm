; AutoMod: a team's blocked words, checked against every message posted or
; edited in its channels. A word matches whole and ignoring case, and a *
; at either end lets it run on into the rest of a word there, so "spam*"
; catches "spammer". A blocked message isn't stored, goes in the audit log,
; and times its author out when the team set a timeout. PERM_MANAGE_AUTOMOD
; skips the check.

section .rodata
text e_automod_words,   "blocked words are up to 1000 printable characters, one per line"
text e_automod_full,    "the server has no room for that team's AutoMod rules right now"

section .text

; edi = team -> rax = its rules row, or 0 if it has none
find_automod:
    lea rax, [automod]
    mov ecx, [n_automod]
    test edi, edi
    jz .none
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + AM_TEAM], edi
    je .done
    add rax, AM_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; edi = byte -> eax = it lowercased, for the ASCII letters
lower_byte:
    mov eax, edi
    lea ecx, [eax - 'A']
    cmp ecx, 'Z' - 'A'
    ja .done
    add eax, 'a' - 'A'
.done:
    ret

; edi = byte -> eax = 1 if it can be part of a word: letters, digits and anything past ASCII
word_byte:
    mov eax, 1
    cmp edi, 0x80
    jae .done
    lea ecx, [edi - '0']
    cmp ecx, 9
    jbe .done
    or edi, 0x20
    lea ecx, [edi - 'a']
    cmp ecx, 'z' - 'a'
    jbe .done
    xor eax, eax
.done:
    ret

; Whether one blocked word matches anywhere in a text.
; rdi = text, esi = its length, rdx = the word, ecx = its length, * included
; -> eax = 1 if it matches
word_matches:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    mov r13d, esi
    mov r14, rdx
    mov r15d, ecx
    xor ebp, ebp                            ; bit 0: * in front, bit 1: * behind
    cmp byte [r14], '*'
    jne .tail
    or ebp, 1
    inc r14
    dec r15d
.tail:
    test r15d, r15d
    jz .no
    cmp byte [r14 + r15 - 1], '*'
    jne .start
    or ebp, 2
    dec r15d
    jz .no                                  ; "*" or "**" alone would match everything
.start:
    xor ebx, ebx                            ; where in the text
.at:
    mov eax, r13d
    sub eax, ebx
    cmp eax, r15d
    jb .no
    test ebp, 1
    jnz .compare
    test ebx, ebx
    jz .compare
    movzx edi, byte [r12 + rbx - 1]
    call word_byte
    test eax, eax
    jnz .next                               ; it would start mid-word
.compare:
    xor ecx, ecx
.char:
    cmp ecx, r15d
    jae .end
    mov [rsp], ecx
    lea eax, [ebx + ecx]
    movzx edi, byte [r12 + rax]
    call lower_byte
    mov edx, eax
    mov ecx, [rsp]
    movzx edi, byte [r14 + rcx]
    call lower_byte                         ; leaves edx alone
    cmp eax, edx
    jne .next
    mov ecx, [rsp]
    inc ecx
    jmp .char
.end:
    test ebp, 2
    jnz .yes
    lea eax, [ebx + r15d]
    cmp eax, r13d
    jae .yes
    movzx edi, byte [r12 + rax]
    call word_byte
    test eax, eax
    jz .yes
.next:
    inc ebx
    jmp .at
.yes:
    mov eax, 1
    jmp .done
.no:
    xor eax, eax
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = team, rsi = text, edx = its length -> rax = the first of the team's
; blocked words in it and edx = that word's length, or rax = 0
automod_match:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rsi
    mov r13d, edx
    call find_automod
    test rax, rax
    jz .none
    lea rbx, [rax + AM_WORDS]               ; this line
    movzx r14d, word [rax + AM_LEN]
    add r14, rbx                            ; the end of them
.line:
    cmp rbx, r14
    jae .none
    mov rbp, rbx
.scan:
    cmp rbp, r14
    jae .word
    cmp byte [rbp], 10
    je .word
    inc rbp
    jmp .scan
.word:
    mov r15, rbp
    sub r15, rbx                            ; its length
    jz .next_line
    mov rdi, r12
    mov esi, r13d
    mov rdx, rbx
    mov ecx, r15d
    call word_matches
    test eax, eax
    jz .next_line
    mov rax, rbx
    mov edx, r15d
    jmp .done
.next_line:
    lea rbx, [rbp + 1]
    jmp .line
.none:
    xor eax, eax
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Checks what cur posts in a channel against the team's blocked words. A
; match is logged, committed, and times cur out if the team says to.
; edi = team, esi = the channel's peer, rdx = text, ecx = its length -> eax = 1 if blocked
automod_check:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, edi
    mov r13d, esi
    mov r14, rdx
    mov r15d, ecx
    mov rax, [cur]
    mov esi, [rax + C_USER]
    call find_member
    test rax, rax
    jz .pass
    mov rbx, rax
    mov rdi, rax
    call member_perms
    test eax, PERM_MANAGE_AUTOMOD           ; owners and admins have it too
    jnz .pass
    mov edi, r12d
    mov rsi, r14
    mov edx, r15d
    call automod_match
    test rax, rax
    jz .pass
    mov r14, rax
    mov r15d, edx
    cmp r15d, REASON_MAX
    jbe .logged
    mov r15d, REASON_MAX
.logged:
    mov rax, [cur]
    mov edx, [rax + C_USER]
    mov edi, r12d
    mov esi, AU_AUTOMOD_BLOCK
    mov ecx, r13d
    and ecx, ~CHANNEL_PEER
    mov r8, r14
    mov r9d, r15d
    call audit_add
    xor r13d, r13d                          ; 1 once they're timed out
    mov edi, r12d
    call find_automod
    mov ecx, [rax + AM_TIMEOUT]
    test ecx, ecx
    jz .commit
    mov r13d, ecx
    call now_unix
    add eax, r13d
    mov [rbx + MEM_TIMEOUT], eax
    mov edi, T_MEMBERS
    mov rsi, rbx
    call db_touch
    mov r13d, 1
.commit:
    call db_commit
    test r13d, r13d
    jz .told
    mov edi, r12d
    call broadcast_members
.told:
    mov edi, r12d
    mov esi, -1
    call send_moderation
    mov eax, 1
    jmp .done
.pass:
    xor eax, eax
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Builds MSG_AUTOMOD for a team in msg_buf. edi = team -> rdx = its length
build_automod:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, edi
    call find_automod
    mov rbx, rax
    lea rdi, [msg_buf]
    mov esi, MSG_AUTOMOD
    call wr_u8
    mov esi, r12d
    call wr_u32
    xor esi, esi
    xor edx, edx
    test rbx, rbx
    jz .empty
    mov esi, [rbx + AM_TIMEOUT]
    call wr_u32
    lea rsi, [rbx + AM_WORDS]
    movzx edx, word [rbx + AM_LEN]
    call wr_str16
    jmp .built
.empty:
    call wr_u32
    xor edx, edx
    call wr_str16
.built:
    lea rax, [msg_buf]
    mov rdx, rdi
    sub rdx, rax
    add rsp, 8
    pop r12
    pop rbx
    ret

; MSG_SET_AUTOMOD: a team's blocked words and the timeout for using one.
h_set_automod:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call rd_u32
    mov r12d, eax                           ; team
    call rd_u32
    mov r13d, eax                           ; timeout
    call rd_str16
    mov r14, rax
    mov r15d, edx                           ; words
    call rd_ok
    test eax, eax
    jz .violation
    cmp r13d, TIMEOUT_MAX
    ja .violation
    mov rsi, r14
    mov edx, r15d
    mov ecx, AUTOMOD_MAX
    call valid_body
    test eax, eax
    jz .bad_words
    mov edi, r12d
    mov esi, PERM_MANAGE_AUTOMOD
    call require_perm
    test rax, rax
    jz .done
    mov edi, r12d
    call find_automod
    test rax, rax
    jnz .have
    mov edi, T_AUTOMOD
    call alloc_row
    test rax, rax
    jz .full
    mov [rax + AM_TEAM], r12d
.have:
    mov rbx, rax
    mov [rbx + AM_TIMEOUT], r13d
    lea rdi, [rbx + AM_WORDS]               ; the old words go, not just their length
    mov esi, AUTOMOD_MAX
    call wipe
    mov [rbx + AM_LEN], r15w
    lea rdi, [rbx + AM_WORDS]
    mov rsi, r14
    mov ecx, r15d
    rep movsb
    mov edi, T_AUTOMOD
    mov rsi, rbx
    mov eax, r13d
    or eax, r15d
    jz .drop
    call db_touch
    jmp .record
.drop:
    call free_row
.record:
    mov edi, r12d
    mov esi, AU_AUTOMOD
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call audit_add
    call db_commit
    mov edi, r12d
    mov esi, -1
    call send_moderation
    jmp .done
.violation:
    call kill_cur
    jmp .done
.bad_words:
    lea rsi, [e_automod_words]
    mov edx, e_automod_words_len
    jmp .error
.full:
    lea rsi, [e_automod_full]
    mov edx, e_automod_full_len
.error:
    call send_error
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
