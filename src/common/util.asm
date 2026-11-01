; Small helpers shared by the server and the client.
; Calling convention is SysV: args in rdi, rsi, rdx, rcx, r8, r9, result in rax.

section .text

; Writes are pointless once the peer is gone, and SIGPIPE would kill us instead
; of letting write() return EPIPE.
ignore_sigpipe:
    sub rsp, 32
    mov qword [rsp], SIG_IGN
    mov qword [rsp + 8], 0
    mov qword [rsp + 16], 0
    mov qword [rsp + 24], 0
    mov eax, SYS_rt_sigaction
    mov edi, SIGPIPE
    mov rsi, rsp
    xor edx, edx
    mov r10d, 8
    syscall
    add rsp, 32
    ret

; rdi = exit code
exit:
    mov eax, SYS_exit
    syscall

; rdi = fd, rsi = buf, rdx = len -> rax = 0 on success, -1 on failure
write_all:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
.loop:
    test r13, r13
    jz .ok
    mov eax, SYS_write
    mov edi, ebx
    mov rsi, r12
    mov rdx, r13
    syscall
    cmp rax, -EINTR
    je .loop
    test rax, rax
    jle .fail
    add r12, rax
    sub r13, rax
    jmp .loop
.ok:
    xor eax, eax
    jmp .done
.fail:
    mov rax, -1
.done:
    pop r13
    pop r12
    pop rbx
    ret

; rdi = NUL-terminated string -> rax = length
strlen:
    mov rax, rdi
.loop:
    cmp byte [rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    sub rax, rdi
    ret

; rdi = NUL-terminated string, written to stderr
print_err:
    push rdi
    call strlen
    pop rsi
    mov rdx, rax
    mov edi, 2
    jmp write_all

; rdi = a, rsi = b, both NUL-terminated -> eax = 1 if equal
cstr_eq:
.loop:
    mov al, [rdi]
    cmp al, [rsi]
    jne .no
    test al, al
    jz .yes
    inc rdi
    inc rsi
    jmp .loop
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; rdi = a, rsi = b, rdx = len -> eax = 1 if the bytes match
mem_eq:
    mov rcx, rdx
    test rcx, rcx               ; repe leaves the flags alone when len is 0
    repe cmpsb
    sete al
    movzx eax, al
    ret

; rdi = dst, rsi = src, rdx = len. Safe for overlapping ranges.
memmove:
    mov rcx, rdx
    cmp rdi, rsi
    jbe .forward
    lea rsi, [rsi + rcx - 1]
    lea rdi, [rdi + rcx - 1]
    std
    rep movsb
    cld
    ret
.forward:
    rep movsb
    ret

; The put_* helpers use rdi as a write cursor and return it advanced, which
; keeps string building down to a list of calls.

; rdi = cursor, rsi = NUL-terminated source
put_cstr:
.loop:
    lodsb
    test al, al
    jz .done
    stosb
    jmp .loop
.done:
    ret

; rdi = cursor, rsi = source, rdx = len
put_mem:
    mov rcx, rdx
    rep movsb
    ret

; rdi = cursor, esi = value written as decimal
put_u32:
    mov eax, esi
    mov r8, rsp                 ; digits go into the red zone, last digit first
    mov ecx, 10
.div:
    xor edx, edx
    div ecx
    add dl, '0'
    dec r8
    mov [r8], dl
    test eax, eax
    jnz .div
.copy:
    mov al, [r8]
    stosb
    inc r8
    cmp r8, rsp
    jne .copy
    ret

; rdi = ptr, rsi = len -> eax = value, edx = digits consumed (0 means no number).
; More than 9 digits counts as no number, so the result always fits in 32 bits.
parse_u32:
    xor eax, eax
    xor edx, edx
.loop:
    cmp rdx, rsi
    jae .done
    movzx ecx, byte [rdi + rdx]
    sub ecx, '0'
    cmp ecx, 9
    ja .done
    imul eax, eax, 10
    add eax, ecx
    inc edx
    cmp edx, 9
    ja .overflow
    jmp .loop
.overflow:
    xor eax, eax
    xor edx, edx
.done:
    ret

; rdi = ptr, rsi = len -> rax = offset just past the first "\r\n\r\n", or -1
find_header_end:
    xor eax, eax
.loop:
    lea rcx, [rax + 4]
    cmp rcx, rsi
    ja .none
    cmp dword [rdi + rax], 0x0A0D0A0D
    je .found
    inc rax
    jmp .loop
.found:
    add rax, 4
    ret
.none:
    mov rax, -1
    ret

; Sets SO_RCVTIMEO and SO_SNDTIMEO so a stuck peer can't hang us.
; rdi = socket fd, rsi = seconds
set_socket_timeouts:
    push rbx
    sub rsp, 16
    mov ebx, edi
    mov [rsp], rsi
    mov qword [rsp + 8], 0
    mov eax, SYS_setsockopt
    mov edi, ebx
    mov esi, SOL_SOCKET
    mov edx, SO_RCVTIMEO
    mov r10, rsp
    mov r8d, 16
    syscall
    mov eax, SYS_setsockopt
    mov edi, ebx
    mov esi, SOL_SOCKET
    mov edx, SO_SNDTIMEO
    mov r10, rsp
    mov r8d, 16
    syscall
    add rsp, 16
    pop rbx
    ret

; Zeroes memory. Used to scrub keys and secrets once we're done with them.
; rdi = ptr, rsi = len
wipe:
    mov rcx, rsi
    xor eax, eax
    rep stosb
    ret

; Compares without an early exit, so timing doesn't reveal where they differ.
; rdi = a, rsi = b, rdx = len -> eax = 1 if equal
ct_equal:
    xor eax, eax
    xor ecx, ecx
.loop:
    cmp rcx, rdx
    jae .done
    mov r8b, [rdi + rcx]
    xor r8b, [rsi + rcx]
    or al, r8b
    inc rcx
    jmp .loop
.done:
    sub eax, 1                              ; borrows only when every byte matched
    sbb eax, eax
    neg eax
    ret

; Fills a buffer from the kernel CSPRNG. Exits if that's impossible, since
; nothing secure can happen without randomness.
; rdi = ptr, rsi = len
random_bytes:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
.loop:
    test r12, r12
    jz .done
    mov eax, SYS_getrandom
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    syscall
    cmp rax, -EINTR
    je .loop
    test rax, rax
    jle .fail
    add rbx, rax
    sub r12, rax
    jmp .loop
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret
.fail:
    lea rdi, [msg_no_random]
    call print_err
    mov edi, 1
    call exit

section .rodata
msg_no_random:  db "fatal: getrandom failed", 10, 0
hex_digits:     db "0123456789abcdef"
base64_chars:   db "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
section .text

; rdi = out (2 * len chars), rsi = bytes, rdx = len -> rdi advanced
put_hex:
    lea r8, [hex_digits]
.loop:
    test rdx, rdx
    jz .done
    movzx eax, byte [rsi]
    mov ecx, eax
    shr ecx, 4
    mov cl, [r8 + rcx]
    mov [rdi], cl
    and eax, 15
    mov al, [r8 + rax]
    mov [rdi + 1], al
    add rdi, 2
    inc rsi
    dec rdx
    jmp .loop
.done:
    ret

; rdi = out bytes, rsi = hex chars, rdx = number of bytes to decode
; -> eax = 1 on success, 0 if a character isn't hex
parse_hex:
.loop:
    test rdx, rdx
    jz .ok
    xor r8d, r8d
    mov ecx, 2
.nibble:
    movzx eax, byte [rsi]
    inc rsi
    sub eax, '0'
    cmp eax, 9
    jbe .digit
    or eax, 0x20                            ; 'A'-'0' | 0x20 = 'a'-'0'
    sub eax, 'a' - '0'
    cmp eax, 5
    ja .bad
    add eax, 10
.digit:
    shl r8d, 4
    or r8d, eax
    dec ecx
    jnz .nibble
    mov [rdi], r8b
    inc rdi
    dec rdx
    jmp .loop
.ok:
    mov eax, 1
    ret
.bad:
    xor eax, eax
    ret

; Standard base64 with padding. rdi = out, rsi = bytes, rdx = len -> rdi advanced
put_base64:
    push rbx
    lea rbx, [base64_chars]
.loop:
    cmp rdx, 3
    jb .tail
    movzx eax, byte [rsi]
    shl eax, 8
    mov al, [rsi + 1]
    shl eax, 8
    mov al, [rsi + 2]
    mov ecx, 4
.chars:
    mov r8d, eax
    shr r8d, 18
    and r8d, 63
    mov r8b, [rbx + r8]
    mov [rdi], r8b
    inc rdi
    shl eax, 6
    dec ecx
    jnz .chars
    add rsi, 3
    sub rdx, 3
    jmp .loop
.tail:
    test rdx, rdx
    jz .done
    movzx eax, byte [rsi]
    shl eax, 16
    cmp rdx, 2
    jb .one
    movzx ecx, byte [rsi + 1]
    shl ecx, 8
    or eax, ecx
.one:
    mov ecx, eax
    shr ecx, 18
    mov cl, [rbx + rcx]
    mov [rdi], cl
    mov ecx, eax
    shr ecx, 12
    and ecx, 63
    mov cl, [rbx + rcx]
    mov [rdi + 1], cl
    mov byte [rdi + 3], '='
    mov byte [rdi + 2], '='
    cmp rdx, 2
    jb .padded
    mov ecx, eax
    shr ecx, 6
    and ecx, 63
    mov cl, [rbx + rcx]
    mov [rdi + 2], cl
.padded:
    add rdi, 4
.done:
    pop rbx
    ret

; Parses "a.b.c.d:port" into a sockaddr_in.
; rdi = NUL-terminated string, rsi = out (16 bytes) -> eax = 1 on success
parse_addr:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov word [r12], AF_INET
    mov qword [r12 + 8], 0
    xor r13d, r13d                          ; octets parsed
.octet:
    mov rdi, rbx
    mov esi, 4
    call parse_u32
    test edx, edx
    jz .bad
    cmp eax, 255
    ja .bad
    mov [r12 + 4 + r13], al
    add rbx, rdx
    inc r13d
    mov cl, [rbx]
    inc rbx
    cmp r13d, 4
    je .port
    cmp cl, '.'
    jne .bad
    jmp .octet
.port:
    cmp cl, ':'
    jne .bad
    mov rdi, rbx
    mov esi, 6
    call parse_u32
    test edx, edx
    jz .bad
    cmp byte [rbx + rdx], 0
    jne .bad
    test eax, eax
    jz .bad
    cmp eax, 65535
    ja .bad
    xchg al, ah                             ; network byte order
    mov [r12 + 2], ax
    mov eax, 1
    jmp .done
.bad:
    xor eax, eax
.done:
    pop r13
    pop r12
    pop rbx
    ret

; -> rax = milliseconds on the monotonic clock
now_ms:
    sub rsp, 16
    mov eax, SYS_clock_gettime
    mov edi, CLOCK_MONOTONIC
    mov rsi, rsp
    syscall
    imul rcx, [rsp], 1000
    mov rax, [rsp + 8]
    xor edx, edx
    mov r8d, 1000000
    div r8
    add rax, rcx
    add rsp, 16
    ret

; rdi = headers, rsi = their length, rdx = lowercase name (NUL-terminated)
; -> rax = value with surrounding spaces trimmed, edx = its length; rax = 0 if missing
find_header:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    lea r13, [rdi + rsi]                    ; end
    mov r14, rdx
    mov rdi, r14
    call strlen
    mov r15, rax                            ; name length
    mov rbx, r12
.line:
    ; Advance to the start of the next line.
    cmp rbx, r13
    jae .missing
    cmp byte [rbx], 10
    je .line_start
    inc rbx
    jmp .line
.line_start:
    inc rbx
    lea rax, [rbx + r15 + 1]
    cmp rax, r13
    ja .missing
    cmp byte [rbx + r15], ':'
    jne .line
    xor ecx, ecx
.name:
    cmp rcx, r15
    jae .value
    movzx eax, byte [rbx + rcx]
    lea edx, [eax - 'A']
    cmp edx, 'Z' - 'A'
    ja .compare
    add eax, 32
.compare:
    cmp al, [r14 + rcx]
    jne .line
    inc rcx
    jmp .name
.value:
    lea rax, [rbx + r15 + 1]
.skip_space:
    cmp rax, r13
    jae .missing
    cmp byte [rax], ' '
    jne .find_end
    inc rax
    jmp .skip_space
.find_end:
    mov rdx, rax
.scan:
    cmp rdx, r13
    jae .trim
    cmp byte [rdx], 13
    je .trim
    inc rdx
    jmp .scan
.trim:
    cmp rdx, rax
    je .measure
    cmp byte [rdx - 1], ' '
    jne .measure
    dec rdx
    jmp .trim
.measure:
    sub rdx, rax
    jmp .done
.missing:
    xor eax, eax
    xor edx, edx
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
