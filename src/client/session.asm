; Remembers the server and the login between runs, so starting the client
; again picks up where it left off. The file holds the server's key, its
; address and the session token, and lives in $XDG_STATE_HOME/asm-todo, or
; ~/.local/state/asm-todo without it. Logging out forgets the token but keeps
; the server, so a bare todo-client still knows where to connect.

%define SS_MAGIC        0
%define SS_KEY          4
%define SS_TOKEN        36              ; all zeros when logged out
%define SS_ADDR_LEN     68
%define SS_ADDR         69
%define SS_ADDR_MAX     21              ; "255.255.255.255:65535"
%define SS_SIZE         92
fits SS_KEY, 32, SS_TOKEN
fits SS_TOKEN, 32, SS_ADDR_LEN
fits SS_ADDR_LEN, 1, SS_ADDR
fits SS_ADDR, SS_ADDR_MAX, SS_SIZE
%define SESSION_MAGIC   0x31535441      ; "ATS1"
%define SESSION_PATH_MAX 470            ; for the directory from the environment, leaving
                                        ; room for "/.local/state/asm-todo/session.tmp"

section .rodata
s_state_env:    db "XDG_STATE_HOME=", 0
s_home_env:     db "HOME=", 0
s_state_dir:    db "/.local/state", 0
s_session_file: db "/asm-todo/session", 0
s_tmp_suffix:   db ".tmp", 0

section .bss
session_path:   resb 512                ; empty when there's nowhere to keep it
session_tmp:    resb 512
session_buf:    resb SS_SIZE
session_addr:   resb SS_ADDR_MAX + 1    ; the saved address, NUL-terminated for parse_addr

section .text

; Works out where the file goes. rdi = envp
session_init:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    lea rsi, [s_state_env]
    call getenv
    test rax, rax
    jz .home
    cmp byte [rax], '/'                     ; a relative one is to be ignored
    jne .home
    mov r12, rax
    mov rdi, rax
    call strlen
    cmp rax, SESSION_PATH_MAX
    ja .none
    lea rdi, [session_path]
    mov rsi, r12
    call put_cstr
    jmp .file
.home:
    mov rdi, rbx
    lea rsi, [s_home_env]
    call getenv
    test rax, rax
    jz .none
    cmp byte [rax], '/'
    jne .none
    mov r12, rax
    mov rdi, rax
    call strlen
    cmp rax, SESSION_PATH_MAX
    ja .none
    lea rdi, [session_path]
    mov rsi, r12
    call put_cstr
    lea rsi, [s_state_dir]
    call put_cstr
.file:
    lea rsi, [s_session_file]
    call put_cstr
    mov byte [rdi], 0
    lea rdi, [session_tmp]
    lea rsi, [session_path]
    call put_cstr
    lea rsi, [s_tmp_suffix]
    call put_cstr
    mov byte [rdi], 0
.none:
    add rsp, 8
    pop r12
    pop rbx
    ret

; Reads the file into session_buf and its address into session_addr.
; -> eax = 1 if there was a sound one
session_load:
    push rbx
    cmp byte [session_path], 0
    je .no
    mov eax, SYS_open
    lea rdi, [session_path]
    mov esi, O_RDONLY | O_CLOEXEC
    syscall
    test eax, eax
    js .no
    mov ebx, eax
    mov eax, SYS_read
    mov edi, ebx
    lea rsi, [session_buf]
    mov edx, SS_SIZE
    syscall
    push rax
    mov eax, SYS_close
    mov edi, ebx
    syscall
    pop rax
    cmp rax, SS_SIZE
    jne .no
    cmp dword [session_buf + SS_MAGIC], SESSION_MAGIC
    jne .no
    movzx edx, byte [session_buf + SS_ADDR_LEN]
    cmp edx, SS_ADDR_MAX
    ja .no
    lea rdi, [session_addr]
    lea rsi, [session_buf + SS_ADDR]
    call put_mem
    mov byte [rdi], 0
    mov eax, 1
    pop rbx
    ret
.no:
    xor eax, eax
    pop rbx
    ret

; Picks up the saved token if it's for this server, so the first connection
; resumes it. Call after session_load. -> eax = 1 if there was one
session_restore:
    push rbx
    lea rdi, [session_buf + SS_KEY]
    lea rsi, [server_key]
    mov edx, 32
    call mem_eq
    test eax, eax
    jz .done
    xor eax, eax
    xor ecx, ecx
.any:
    or al, [session_buf + SS_TOKEN + rcx]
    inc ecx
    cmp ecx, 32
    jb .any
    test al, al
    jz .done
    lea rdi, [token]
    lea rsi, [session_buf + SS_TOKEN]
    mov ecx, 32
    rep movsb
    mov eax, 1
.done:
    push rax
    lea rdi, [session_buf]
    mov esi, SS_SIZE
    call wipe
    pop rax
    pop rbx
    ret

; Makes every directory above the file, private to the user. Ones that are
; already there just fail.
session_dirs:
    lea rdi, [session_path + 1]
.slash:
    mov al, [rdi]
    test al, al
    jz .done
    cmp al, '/'
    jne .next
    mov byte [rdi], 0
    push rdi
    mov eax, SYS_mkdir
    lea rdi, [session_path]
    mov esi, 0o700
    syscall
    pop rdi
    mov byte [rdi], '/'
.next:
    inc rdi
    jmp .slash
.done:
    ret

; Writes the server and the current token, zeros if logged out. A temp file
; renamed over the old one, so a crash leaves one or the other.
session_save:
    push rbx
    cmp byte [session_path], 0
    je .done
    mov dword [session_buf + SS_MAGIC], SESSION_MAGIC
    lea rdi, [session_buf + SS_KEY]
    lea rsi, [server_key]
    mov edx, 32
    call put_mem
    lea rdi, [session_buf + SS_TOKEN]
    lea rsi, [token]
    mov edx, 32
    call put_mem
    mov rdi, [server_label]
    call strlen
    mov ecx, SS_ADDR_MAX
    cmp eax, ecx
    cmova eax, ecx
    mov [session_buf + SS_ADDR_LEN], al
    lea rdi, [session_buf + SS_ADDR]
    mov rsi, [server_label]
    mov edx, eax
    call put_mem
    call session_dirs
    mov eax, SYS_open
    lea rdi, [session_tmp]
    mov esi, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov edx, 0o600
    syscall
    test eax, eax
    js .wipe
    mov ebx, eax
    mov edi, eax
    lea rsi, [session_buf]
    mov edx, SS_SIZE
    call write_all
    push rax
    mov eax, SYS_close
    mov edi, ebx
    syscall
    pop rax
    test rax, rax
    jnz .wipe
    mov eax, SYS_rename
    lea rdi, [session_tmp]
    lea rsi, [session_path]
    syscall
.wipe:
    lea rdi, [session_buf]
    mov esi, SS_SIZE
    call wipe
.done:
    pop rbx
    ret
