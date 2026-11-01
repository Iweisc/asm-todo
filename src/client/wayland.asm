; Wayland client spoken directly over the compositor's Unix socket.
;
; Wire format: every message is [object id u32][size << 16 | opcode u32][args].
; Strings are a u32 length (including the NUL) followed by padded bytes, and
; file descriptors travel out of band as SCM_RIGHTS ancillary data.
;
; The compositor only accepts client object ids handed out in order with no
; gaps, so ids come from wl_new_id as objects get created and each one lives in
; an id_* variable. 0 means "not created".

%define ID_DISPLAY          1

%define WL_OUT_MAX          4096
%define WL_IN_MAX           8192

; Two buffers big enough for a 4K window. memfd pages are only allocated once
; touched, so this costs memory proportional to the real window size.
%define MAX_W               3840
%define MAX_H               2160
%define SLOT_BYTES          (MAX_W * MAX_H * 4)
%define POOL_BYTES          (SLOT_BYTES * 2)
%define SHM_XRGB8888        1

%define SLOT_ID             0
%define SLOT_BUSY           4
%define SLOT_W              8
%define SLOT_H              12
%define SLOT_SIZE           16

section .data

s_wl_compositor:    db "wl_compositor", 0
s_wl_shm:           db "wl_shm", 0
s_xdg_wm_base:      db "xdg_wm_base", 0
s_wl_seat:          db "wl_seat", 0
s_cursor_shape:     db "wp_cursor_shape_manager_v1", 0
s_runtime_env:      db "XDG_RUNTIME_DIR=", 0
s_display_env:      db "WAYLAND_DISPLAY=", 0
s_default_display:  db "wayland-0", 0
s_app_id:           db "asm-todo", 0

msg_no_runtime:     db "asm-todo: XDG_RUNTIME_DIR is not set", 10, 0
msg_path_long:      db "asm-todo: Wayland socket path is too long", 10, 0
msg_connect:        db "asm-todo: can't connect to the Wayland compositor", 10, 0
msg_lost:           db "asm-todo: lost the connection to the compositor", 10, 0
msg_globals:        db "asm-todo: the compositor lacks wl_compositor, wl_shm or xdg_wm_base", 10, 0
msg_shm:            db "asm-todo: can't allocate the shared-memory framebuffer", 10, 0
msg_protocol:       db "asm-todo: Wayland protocol error: ", 0
msg_newline:        db 10, 0

; interface, highest version we speak, id variable
wanted_globals:
    dq s_wl_compositor, 4, id_compositor
    dq s_wl_shm,        1, id_shm
    dq s_xdg_wm_base,   1, id_wm_base
    dq s_wl_seat,       5, id_seat
    dq s_cursor_shape,  1, id_cursor_manager
    dq 0

; Objects whose events we handle. Buffers are matched separately.
event_handlers:
    dq id_display,      on_display
    dq id_registry,     on_registry
    dq id_sync,         on_sync
    dq id_wm_base,      on_wm_base
    dq id_seat,         on_seat
    dq id_xdg_surface,  on_xdg_surface
    dq id_toplevel,     on_toplevel
    dq id_pointer,      on_pointer
    dq id_keyboard,     on_keyboard
    dq 0

id_display:         dd ID_DISPLAY
wl_next_id:         dd ID_DISPLAY + 1
wl_pending_fd:      dd -1

section .bss

wl_fd:              resd 1
wl_out_len:         resd 1
wl_msg_start:       resd 1
wl_in_len:          resd 1
wl_out:             resb WL_OUT_MAX
wl_in:              resb WL_IN_MAX
wl_cmsg:            resb 64
wl_sockaddr:        resb 110

id_registry:        resd 1
id_sync:            resd 1
id_compositor:      resd 1
id_shm:             resd 1
id_wm_base:         resd 1
id_seat:            resd 1
id_cursor_manager:  resd 1
id_surface:         resd 1
id_xdg_surface:     resd 1
id_toplevel:        resd 1
id_pool:            resd 1
id_pointer:         resd 1
id_keyboard:        resd 1
id_cursor_device:   resd 1
sync_done:          resb 1
configured:         resb 1

pending_w:          resd 1
pending_h:          resd 1
win_w:              resd 1
win_h:              resd 1
shm_base:           resq 1
slots:              resb SLOT_SIZE * 2
current_slot:       resq 1

section .text

; rdi = message -> never returns
fatal:
    call print_err
    mov edi, 1
    call exit

; rdi = id variable -> edi = a fresh object id, also stored in the variable
wl_new_id:
    mov eax, [wl_next_id]
    inc dword [wl_next_id]
    mov [rdi], eax
    mov edi, eax
    ret

; --- outgoing messages ---

; edi = object id, esi = opcode. Follow with wl_u32 / wl_str, then wl_end.
wl_begin:
    cmp dword [wl_out_len], WL_OUT_MAX - 512
    jb .room
    push rdi
    push rsi
    call wl_flush
    pop rsi
    pop rdi
.room:
    mov eax, [wl_out_len]
    mov [wl_msg_start], eax
    lea rcx, [wl_out]
    mov [rcx + rax], edi
    mov [rcx + rax + 4], si                 ; size is patched in by wl_end
    add eax, 8
    mov [wl_out_len], eax
    ret

; edi = value
wl_u32:
    mov eax, [wl_out_len]
    lea rcx, [wl_out]
    mov [rcx + rax], edi
    add eax, 4
    mov [wl_out_len], eax
    ret

; rdi = NUL-terminated string
wl_str:
    push rdi
    call strlen
    pop rsi
    lea rdx, [rax + 1]                      ; length on the wire includes the NUL
    mov eax, [wl_out_len]
    lea rdi, [wl_out + rax]
    mov [rdi], edx
    add rdi, 4
    mov rcx, rdx
    rep movsb
    ; Pad to 4 bytes with zeros.
.pad:
    test edx, 3
    jz .done
    mov byte [rdi], 0
    inc rdi
    inc edx
    jmp .pad
.done:
    lea rax, [wl_out]
    sub rdi, rax
    mov [wl_out_len], edi
    ret

wl_end:
    mov eax, [wl_out_len]
    mov ecx, [wl_msg_start]
    sub eax, ecx
    lea rdx, [wl_out]
    mov [rdx + rcx + 6], ax
    ret

; Sends everything queued, plus wl_pending_fd if one is set.
wl_flush:
    push rbx
    sub rsp, 80                             ; msghdr (56) + iovec (16), and 8 spare
    xor ebx, ebx                            ; bytes sent
.again:
    mov eax, [wl_out_len]
    cmp ebx, eax
    jae .done
    lea rcx, [wl_out + rbx]
    mov [rsp + 56], rcx                     ; iov_base
    sub eax, ebx
    mov [rsp + 64], rax                     ; iov_len
    mov qword [rsp], 0                      ; msg_name
    mov qword [rsp + 8], 0                  ; msg_namelen
    lea rcx, [rsp + 56]
    mov [rsp + 16], rcx                     ; msg_iov
    mov qword [rsp + 24], 1                 ; msg_iovlen
    mov qword [rsp + 32], 0                 ; msg_control
    mov qword [rsp + 40], 0                 ; msg_controllen
    mov qword [rsp + 48], 0                 ; msg_flags
    mov eax, [wl_pending_fd]
    test eax, eax
    js .send
    lea rcx, [wl_cmsg]
    mov qword [rcx], 20                     ; cmsg_len = header + one int
    mov dword [rcx + 8], SOL_SOCKET
    mov dword [rcx + 12], SCM_RIGHTS
    mov [rcx + 16], eax
    mov [rsp + 32], rcx
    mov qword [rsp + 40], 24                ; CMSG_SPACE(sizeof(int))
.send:
    mov eax, SYS_sendmsg
    mov edi, [wl_fd]
    mov rsi, rsp
    xor edx, edx
    syscall
    cmp rax, -EINTR
    je .again
    test rax, rax
    js .lost
    mov dword [wl_pending_fd], -1           ; the fd went out with the first chunk
    add ebx, eax
    jmp .again
.done:
    mov dword [wl_out_len], 0
    add rsp, 80
    pop rbx
    ret
.lost:
    lea rdi, [msg_lost]
    call fatal

; --- incoming events ---

; Reads whatever the compositor sent and dispatches every complete message.
wl_read_events:
    push rbx
    push r12
    sub rsp, 72
    mov eax, [wl_in_len]
    lea rcx, [wl_in + rax]
    mov [rsp + 56], rcx
    mov ecx, WL_IN_MAX
    sub ecx, eax
    mov [rsp + 64], rcx
    mov qword [rsp], 0
    mov qword [rsp + 8], 0
    lea rcx, [rsp + 56]
    mov [rsp + 16], rcx
    mov qword [rsp + 24], 1
    lea rcx, [wl_cmsg]
    mov [rsp + 32], rcx
    mov qword [rsp + 40], 64
    mov qword [rsp + 48], 0
    mov eax, SYS_recvmsg
    mov edi, [wl_fd]
    mov rsi, rsp
    mov edx, MSG_CMSG_CLOEXEC
    syscall
    cmp rax, -EINTR
    je .out
    test rax, rax
    jle .lost
    add [wl_in_len], eax

    ; The only fd we can receive is the keymap. We hardcode a US layout
    ; instead of parsing XKB, so it gets closed right away.
    cmp qword [rsp + 40], 16
    jb .dispatch
    lea rbx, [wl_cmsg]
    cmp dword [rbx + 12], SCM_RIGHTS
    jne .dispatch
    mov r12, [rbx]
    sub r12, 16
    shr r12, 2                              ; number of fds
.close_fd:
    test r12, r12
    jz .dispatch
    mov eax, SYS_close
    mov edi, [rbx + 16]
    syscall
    add rbx, 4
    dec r12
    jmp .close_fd

.dispatch:
    xor ebx, ebx                            ; offset of the current message
.message:
    mov eax, [wl_in_len]
    sub eax, ebx
    cmp eax, 8
    jb .compact
    lea r12, [wl_in + rbx]
    movzx ecx, word [r12 + 6]               ; size
    cmp ecx, 8
    jb .lost
    cmp eax, ecx
    jb .compact                             ; rest of it hasn't arrived yet
    mov edi, [r12]
    movzx esi, word [r12 + 4]
    lea rdx, [r12 + 8]
    add ebx, ecx
    call dispatch_event
    jmp .message
.compact:
    lea rdi, [wl_in]
    lea rsi, [wl_in + rbx]
    mov edx, [wl_in_len]
    sub edx, ebx
    mov [wl_in_len], edx
    call memmove
.out:
    add rsp, 72
    pop r12
    pop rbx
    ret
.lost:
    lea rdi, [msg_lost]
    call fatal

; edi = object id, esi = opcode, rdx = args
dispatch_event:
    lea rax, [event_handlers]
.next:
    mov rcx, [rax]
    test rcx, rcx
    jz on_buffer
    cmp edi, [rcx]
    je .found
    add rax, 16
    jmp .next
.found:
    jmp [rax + 8]

; wl_display
on_display:
    test esi, esi
    jnz .ignore                             ; delete_id, nothing to clean up
    push rdx
    lea rdi, [msg_protocol]
    call print_err
    pop rdx
    lea rdi, [rdx + 12]                     ; error(object, code, message)
    call print_err
    lea rdi, [msg_newline]
    call fatal
.ignore:
    ret

; wl_registry.global(name, interface, version)
on_registry:
    test esi, esi
    jnz .done
    push rbx
    push r12
    push r13
    mov r12, rdx
    lea rbx, [wanted_globals]
.next:
    mov rsi, [rbx]
    test rsi, rsi
    jz .out
    mov rax, [rbx + 16]
    cmp dword [rax], 0
    jne .skip                               ; first one wins
    lea rdi, [r12 + 8]
    call cstr_eq
    test eax, eax
    jnz .bind
.skip:
    add rbx, 24
    jmp .next
.bind:
    mov eax, [r12 + 4]
    add eax, 3
    and eax, ~3
    mov r13d, [r12 + 8 + rax]               ; advertised version
    cmp r13, [rbx + 8]
    cmova r13, [rbx + 8]

    mov edi, [id_registry]
    xor esi, esi
    call wl_begin
    mov edi, [r12]
    call wl_u32
    mov rdi, [rbx]
    call wl_str
    mov edi, r13d
    call wl_u32
    mov rdi, [rbx + 16]
    call wl_new_id
    call wl_u32
    call wl_end
.out:
    pop r13
    pop r12
    pop rbx
.done:
    ret

on_sync:
    mov byte [sync_done], 1
    ret

; xdg_wm_base.ping -> pong, or the compositor decides we're frozen
on_wm_base:
    test esi, esi
    jnz .done
    push qword [rdx]
    mov edi, [id_wm_base]
    mov esi, 3
    call wl_begin
    pop rdi
    call wl_u32
    call wl_end
.done:
    ret

; xdg_toplevel.configure(width, height, states) / close
on_toplevel:
    cmp esi, 1
    je .close
    test esi, esi
    jnz .done
    mov eax, [rdx]
    mov [pending_w], eax
    mov eax, [rdx + 4]
    mov [pending_h], eax
.done:
    ret
.close:
    xor edi, edi
    call exit

; xdg_surface.configure(serial) ends a configure sequence: ack it and apply
; the size the toplevel asked for. 0 means "pick your own".
on_xdg_surface:
    test esi, esi
    jnz .done
    push qword [rdx]
    mov edi, [id_xdg_surface]
    mov esi, 4
    call wl_begin
    pop rdi
    call wl_u32
    call wl_end

    mov eax, [pending_w]
    test eax, eax
    jle .height
    mov ecx, MAX_W
    cmp eax, ecx
    cmova eax, ecx
    mov [win_w], eax
.height:
    mov eax, [pending_h]
    test eax, eax
    jle .apply
    mov ecx, MAX_H
    cmp eax, ecx
    cmova eax, ecx
    mov [win_h], eax
.apply:
    mov byte [configured], 1
    call ui_layout_changed
.done:
    ret

; wl_seat.capabilities: bit 0 pointer, bit 1 keyboard
on_seat:
    test esi, esi
    jnz .done
    push rbx
    mov ebx, [rdx]
    test ebx, 1
    jz .keyboard
    cmp dword [id_pointer], 0
    jne .keyboard
    mov edi, [id_seat]
    xor esi, esi
    call wl_begin
    lea rdi, [id_pointer]
    call wl_new_id
    call wl_u32
    call wl_end
    cmp dword [id_cursor_manager], 0
    je .keyboard
    mov edi, [id_cursor_manager]
    mov esi, 1
    call wl_begin
    lea rdi, [id_cursor_device]
    call wl_new_id
    call wl_u32
    mov edi, [id_pointer]
    call wl_u32
    call wl_end
.keyboard:
    test ebx, 2
    jz .out
    cmp dword [id_keyboard], 0
    jne .out
    mov edi, [id_seat]
    mov esi, 1
    call wl_begin
    lea rdi, [id_keyboard]
    call wl_new_id
    call wl_u32
    call wl_end
.out:
    pop rbx
.done:
    ret

; wl_pointer coordinates are 24.8 fixed point
on_pointer:
    cmp esi, 4
    ja .done
    lea rax, [.table]
    jmp [rax + rsi * 8]
.table:
    dq .enter, .leave, .motion, .button, .axis
.enter:
    mov eax, [rdx]
    mov [pointer_serial], eax
    mov eax, [rdx + 8]
    sar eax, 8
    mov [pointer_x], eax
    mov eax, [rdx + 12]
    sar eax, 8
    mov [pointer_y], eax
    mov byte [pointer_inside], 1
    mov dword [cursor_shape], 0             ; the compositor forgets it on enter
    jmp ui_pointer_moved
.leave:
    mov byte [pointer_inside], 0
    jmp ui_pointer_moved
.motion:
    mov eax, [rdx + 4]
    sar eax, 8
    mov [pointer_x], eax
    mov eax, [rdx + 8]
    sar eax, 8
    mov [pointer_y], eax
    jmp ui_pointer_moved
.button:
    cmp dword [rdx + 8], 0x110              ; BTN_LEFT
    jne .done
    cmp dword [rdx + 12], 1                 ; pressed
    jne .done
    jmp ui_click
.axis:
    cmp dword [rdx + 4], 0                  ; vertical scroll
    jne .done
    mov edi, [rdx + 8]
    sar edi, 8
    jmp ui_scroll
.done:
    ret

on_keyboard:
    cmp esi, 5
    ja .done
    lea rax, [.table]
    jmp [rax + rsi * 8]
.table:
    dq .done, .enter, .leave, .key, .modifiers, .repeat_info
.enter:
    mov byte [keyboard_focus], 1
    mov byte [need_redraw], 1
    ret
.leave:
    mov byte [keyboard_focus], 0
    mov dword [repeat_key], 0
    mov byte [need_redraw], 1
    ret
.key:
    mov edi, [rdx + 8]
    mov esi, [rdx + 12]
    jmp ui_key_event
.modifiers:
    mov eax, [rdx + 4]                      ; depressed
    or eax, [rdx + 8]                       ; latched
    mov [modifiers], eax
    mov eax, [rdx + 12]                     ; locked
    mov [locked_modifiers], eax
    ret
.repeat_info:
    mov eax, [rdx]
    mov [repeat_rate], eax
    mov eax, [rdx + 4]
    mov [repeat_delay], eax
.done:
    ret

; wl_buffer.release: the compositor is done reading that buffer
on_buffer:
    lea rax, [slots]
    cmp [rax + SLOT_ID], edi
    je .release
    add rax, SLOT_SIZE
    cmp [rax + SLOT_ID], edi
    jne .done
.release:
    mov dword [rax + SLOT_BUSY], 0
.done:
    ret

; --- setup ---

; rdi = envp, rsi = "NAME=" -> rax = value, or 0
getenv:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
.next:
    mov rdi, [rbx]
    test rdi, rdi
    jz .missing
    mov rsi, r12
.cmp:
    mov al, [rsi]
    test al, al
    jz .found
    cmp al, [rdi]
    jne .skip
    inc rsi
    inc rdi
    jmp .cmp
.skip:
    add rbx, 8
    jmp .next
.found:
    mov rax, rdi
    jmp .done
.missing:
    xor eax, eax
.done:
    pop r12
    pop rbx
    ret

; rdi = envp
wl_connect:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    lea rsi, [s_display_env]
    call getenv
    lea r12, [s_default_display]
    test rax, rax
    cmovnz r12, rax                         ; r12 = display name

    mov word [wl_sockaddr], AF_UNIX
    lea rdi, [wl_sockaddr + 2]
    cmp byte [r12], '/'
    je .absolute

    mov rdi, rbx
    lea rsi, [s_runtime_env]
    call getenv
    test rax, rax
    jz .no_runtime
    mov r13, rax
    mov rdi, rax
    call strlen
    mov rbx, rax
    mov rdi, r12
    call strlen
    lea rax, [rbx + rax + 1]                ; runtime dir + '/' + display
    cmp rax, 107
    ja .too_long
    lea rdi, [wl_sockaddr + 2]
    mov rsi, r13
    call put_cstr
    mov al, '/'
    stosb
    jmp .name
.absolute:
    mov rdi, r12
    call strlen
    cmp rax, 107
    ja .too_long
    lea rdi, [wl_sockaddr + 2]
.name:
    mov rsi, r12
    call put_cstr
    mov byte [rdi], 0

    mov eax, SYS_socket
    mov edi, AF_UNIX
    mov esi, SOCK_STREAM | SOCK_CLOEXEC
    xor edx, edx
    syscall
    test eax, eax
    js .connect_failed
    mov [wl_fd], eax
    mov edi, eax
    mov eax, SYS_connect
    lea rsi, [wl_sockaddr]
    mov edx, 110
    syscall
    test eax, eax
    jnz .connect_failed
    pop r13
    pop r12
    pop rbx
    ret
.no_runtime:
    lea rdi, [msg_no_runtime]
    call fatal
.too_long:
    lea rdi, [msg_path_long]
    call fatal
.connect_failed:
    lea rdi, [msg_connect]
    call fatal

; rdi = envp. Connects, binds globals, creates the window and the shm pool.
wl_init:
    push rbx
    call wl_connect

    mov edi, ID_DISPLAY
    mov esi, 1                              ; get_registry
    call wl_begin
    lea rdi, [id_registry]
    call wl_new_id
    call wl_u32
    call wl_end
    mov edi, ID_DISPLAY
    xor esi, esi                            ; sync, so we know when all globals are in
    call wl_begin
    lea rdi, [id_sync]
    call wl_new_id
    call wl_u32
    call wl_end
.roundtrip:
    call wl_flush
    cmp byte [sync_done], 0
    jne .bound
    call wl_read_events
    jmp .roundtrip
.bound:
    cmp dword [id_compositor], 0
    je .missing_globals
    cmp dword [id_shm], 0
    je .missing_globals
    cmp dword [id_wm_base], 0
    je .missing_globals

    mov edi, [id_compositor]
    xor esi, esi                            ; create_surface
    call wl_begin
    lea rdi, [id_surface]
    call wl_new_id
    call wl_u32
    call wl_end

    mov edi, [id_wm_base]
    mov esi, 2                              ; get_xdg_surface
    call wl_begin
    lea rdi, [id_xdg_surface]
    call wl_new_id
    call wl_u32
    mov edi, [id_surface]
    call wl_u32
    call wl_end

    mov edi, [id_xdg_surface]
    mov esi, 1                              ; get_toplevel
    call wl_begin
    lea rdi, [id_toplevel]
    call wl_new_id
    call wl_u32
    call wl_end

    mov edi, [id_toplevel]
    mov esi, 2                              ; set_title
    call wl_begin
    lea rdi, [s_app_id]
    call wl_str
    call wl_end

    mov edi, [id_toplevel]
    mov esi, 3                              ; set_app_id
    call wl_begin
    lea rdi, [s_app_id]
    call wl_str
    call wl_end

    mov edi, [id_toplevel]
    mov esi, 8                              ; set_min_size
    call wl_begin
    mov edi, 360
    call wl_u32
    mov edi, 320
    call wl_u32
    call wl_end

    ; The first commit has no buffer. It asks the compositor for a configure.
    mov edi, [id_surface]
    mov esi, 6
    call wl_begin
    call wl_end

    mov eax, SYS_memfd_create
    lea rdi, [s_app_id]
    mov esi, MFD_CLOEXEC
    syscall
    test eax, eax
    js .shm_failed
    mov ebx, eax
    mov eax, SYS_ftruncate
    mov edi, ebx
    mov rsi, POOL_BYTES
    syscall
    test eax, eax
    jnz .shm_failed
    mov eax, SYS_mmap
    xor edi, edi
    mov rsi, POOL_BYTES
    mov edx, PROT_RW
    mov r10d, MAP_SHARED
    mov r8d, ebx
    xor r9d, r9d
    syscall
    test rax, rax
    js .shm_failed
    mov [shm_base], rax

    ; create_pool's fd isn't part of the message bytes, so flush what's queued
    ; and send the pool request on its own with the fd attached.
    call wl_flush
    mov edi, [id_shm]
    xor esi, esi
    call wl_begin
    lea rdi, [id_pool]
    call wl_new_id
    call wl_u32
    mov edi, POOL_BYTES
    call wl_u32
    call wl_end
    mov [wl_pending_fd], ebx
    call wl_flush
    mov eax, SYS_close
    mov edi, ebx
    syscall
    pop rbx
    ret
.missing_globals:
    lea rdi, [msg_globals]
    call fatal
.shm_failed:
    lea rdi, [msg_shm]
    call fatal

; -> rax = framebuffer for a buffer that matches the window size, or 0 if the
; compositor still holds both. Sets fb, fb_w and fb_h.
wl_acquire_buffer:
    push rbx
    push r12
    lea rbx, [slots]
    xor r12d, r12d                          ; slot index
    cmp dword [rbx + SLOT_BUSY], 0
    je .found
    add rbx, SLOT_SIZE
    inc r12d
    cmp dword [rbx + SLOT_BUSY], 0
    je .found
    xor eax, eax
    jmp .done
.found:
    mov eax, [win_w]
    mov ecx, [win_h]
    cmp dword [rbx + SLOT_ID], 0
    je .create
    cmp [rbx + SLOT_W], eax
    jne .recreate
    cmp [rbx + SLOT_H], ecx
    je .ready
.recreate:
    mov edi, [rbx + SLOT_ID]
    xor esi, esi                            ; wl_buffer.destroy
    call wl_begin
    call wl_end
.create:
    mov edi, [id_pool]
    xor esi, esi                            ; create_buffer
    call wl_begin
    lea rdi, [rbx + SLOT_ID]
    call wl_new_id
    call wl_u32
    mov edi, r12d
    imul edi, edi, SLOT_BYTES
    call wl_u32
    mov edi, [win_w]
    mov [rbx + SLOT_W], edi
    call wl_u32
    mov edi, [win_h]
    mov [rbx + SLOT_H], edi
    call wl_u32
    mov edi, [win_w]
    shl edi, 2
    call wl_u32
    mov edi, SHM_XRGB8888
    call wl_u32
    call wl_end
.ready:
    mov [current_slot], rbx
    mov eax, [rbx + SLOT_W]
    mov [fb_w], eax
    mov eax, [rbx + SLOT_H]
    mov [fb_h], eax
    mov eax, r12d
    imul rax, rax, SLOT_BYTES
    add rax, [shm_base]
    mov [fb], rax
.done:
    pop r12
    pop rbx
    ret

; Shows the buffer handed out by wl_acquire_buffer.
wl_present:
    push rbx
    mov rbx, [current_slot]
    mov edi, [id_surface]
    mov esi, 1                              ; attach
    call wl_begin
    mov edi, [rbx + SLOT_ID]
    call wl_u32
    xor edi, edi
    call wl_u32
    xor edi, edi
    call wl_u32
    call wl_end
    mov edi, [id_surface]
    mov esi, 9                              ; damage_buffer
    call wl_begin
    xor edi, edi
    call wl_u32
    xor edi, edi
    call wl_u32
    mov edi, [rbx + SLOT_W]
    call wl_u32
    mov edi, [rbx + SLOT_H]
    call wl_u32
    call wl_end
    mov edi, [id_surface]
    mov esi, 6                              ; commit
    call wl_begin
    call wl_end
    mov dword [rbx + SLOT_BUSY], 1
    pop rbx
    ret

; edi = wp_cursor_shape_device_v1 shape
wl_set_cursor_shape:
    cmp dword [id_cursor_device], 0
    je .done
    push rdi
    mov edi, [id_cursor_device]
    mov esi, 1
    call wl_begin
    mov edi, [pointer_serial]
    call wl_u32
    pop rdi
    call wl_u32
    call wl_end
.done:
    ret
