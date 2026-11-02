; The local time zone's offset from UTC, so dates fall on the user's day.
;
; It comes from the zone file TZ names, or /etc/localtime: the offset of the
; last transition before startup. Version 2 files have a second, 64-bit copy
; of the data after the first, which is the one to read when it's there.
; Anything unreadable leaves the offset at 0, UTC.

%define TZ_FILE_MAX     16384           ; the biggest zone files are about 4 KB
%define TZ_HEADER       44              ; "TZif", version, 15 reserved, six u32 counts

section .rodata
s_tz_env:       db "TZ=", 0
s_localtime:    db "/etc/localtime", 0
s_zoneinfo:     db "/usr/share/zoneinfo/", 0

section .bss
alignb 4
tz_offset:      resd 1                  ; seconds east of UTC
tz_path:        resb 256
tz_file:        resb TZ_FILE_MAX

section .text

; Finds the zone file and reads tz_offset from it. rdi = envp
tz_init:
    push rbx
    lea rsi, [s_tz_env]
    call getenv
    lea rdi, [s_localtime]
    test rax, rax
    jz .open
    cmp byte [rax], ':'
    jne .named
    inc rax
.named:
    cmp byte [rax], 0
    je .done                                ; TZ= is UTC
    mov rdi, rax
    cmp byte [rax], '/'
    je .open
    mov rbx, rax
    mov rdi, rax
    call strlen
    cmp rax, 200
    ja .done
    lea rdi, [tz_path]
    lea rsi, [s_zoneinfo]
    call put_cstr
    mov rsi, rbx
    call put_cstr
    mov byte [rdi], 0
    lea rdi, [tz_path]
.open:
    mov eax, SYS_open
    mov esi, O_RDONLY | O_CLOEXEC
    syscall
    test eax, eax
    js .done
    mov ebx, eax
    mov eax, SYS_read
    mov edi, ebx
    lea rsi, [tz_file]
    mov edx, TZ_FILE_MAX
    syscall
    push rax
    mov eax, SYS_close
    mov edi, ebx
    syscall
    pop rsi
    test rsi, rsi
    jle .done
    call unix_now
    mov edx, eax
    call tz_parse
    mov [tz_offset], eax
.done:
    pop rbx
    ret

; rsi = bytes of tz_file read, edx = unix seconds now -> eax = the offset then, 0 if unreadable
tz_parse:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    lea rbx, [tz_file]
    lea r15, [rbx + rsi]                    ; the end
    movsxd rdx, edx
    mov [rsp], rdx
    mov r12d, 4                             ; bytes per transition time
    call tz_header
    jc .bad
    cmp byte [rbx + 4], 0
    je .data
    ; Skip the 32-bit data for the 64-bit copy after it.
    lea rbx, [rbx + rax + TZ_HEADER]
    mov r12d, 8
    call tz_header
    jc .bad
.data:
    ; rcx = transitions, r8 = types. Times, then a type index per time,
    ; then 6 bytes per type: i32 offset, isdst, name index.
    lea r13, [rbx + TZ_HEADER]
    mov rax, rcx
    imul rax, r12
    lea r14, [r13 + rax]                    ; type indexes
    lea rbp, [r14 + rcx]                    ; types
    imul rax, r8, 6
    add rax, rbp
    cmp rax, r15
    ja .bad
    xor edx, edx                            ; type in effect: the first before any transition
    xor esi, esi
.transition:
    cmp rsi, rcx
    jae .found
    cmp r12d, 8
    je .wide
    mov eax, [r13 + rsi * 4]
    bswap eax
    movsxd rax, eax
    jmp .compare
.wide:
    mov rax, [r13 + rsi * 8]
    bswap rax
.compare:
    cmp rax, [rsp]
    jg .found
    movzx edx, byte [r14 + rsi]
    inc rsi
    jmp .transition
.found:
    cmp rdx, r8
    jae .bad
    imul rdx, rdx, 6
    mov eax, [rbp + rdx]
    bswap eax
    jmp .done
.bad:
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

; Checks the header at rbx, with r12 bytes per time, against the end at r15.
; -> carry set if it's bad, else rcx = transitions, r8 = types,
; rax = the size of the data after the header
tz_header:
    lea rax, [rbx + TZ_HEADER]
    cmp rax, r15
    ja .bad
    cmp dword [rbx], 'TZif'
    jne .bad
    mov eax, [rbx + 20]                     ; UT/local indicators
    bswap eax
    mov r9, rax
    mov eax, [rbx + 24]                     ; standard/wall indicators
    bswap eax
    add r9, rax
    mov eax, [rbx + 28]                     ; leap seconds, a time and a count each
    bswap eax
    lea r10, [r12 + 4]
    imul rax, r10
    add r9, rax
    mov eax, [rbx + 32]
    bswap eax
    mov ecx, eax                            ; transitions
    lea r10, [r12 + 1]
    imul rax, r10
    add r9, rax
    mov eax, [rbx + 36]
    bswap eax
    mov r8d, eax                            ; types
    imul rax, rax, 6
    add r9, rax
    mov eax, [rbx + 40]                     ; name bytes
    bswap eax
    add r9, rax
    test r8, r8
    jz .bad
    lea rax, [rbx + TZ_HEADER]
    add rax, r9
    cmp rax, r15
    ja .bad
    mov rax, r9
    clc
    ret
.bad:
    stc
    ret
