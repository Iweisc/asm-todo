; The buttons in a message or comment box, and the file dialog behind the
; image one. There's no portal client here, so the dialog is whichever of
; zenity, kdialog or yad is installed, run beside the client. It prints the
; chosen path, and main_loop polls its pipe with everything else.

%define PICK_NONE       127             ; the exit code when none of them ran

section .rodata
pick_zenity:    db "/usr/bin/zenity", 0
pick_kdialog:   db "/usr/bin/kdialog", 0
pick_yad:       db "/usr/bin/yad", 0
pa_file_sel:    db "--file-selection", 0
pa_title:       db "--title=Attach an image", 0
pa_png_filter:  db "--file-filter=PNG images | *.png", 0
pa_open:        db "--getopenfilename", 0
pa_here:        db ".", 0
pa_png_mime:    db "image/png", 0
pa_file:        db "--file", 0
align 8
pick_programs:  dq pick_zenity, pick_zenity_argv
                dq pick_kdialog, pick_kdialog_argv
                dq pick_yad, pick_yad_argv
                dq 0
pick_zenity_argv:   dq pick_zenity, pa_file_sel, pa_title, pa_png_filter, 0
pick_kdialog_argv:  dq pick_kdialog, pa_open, pa_here, pa_png_mime, 0
pick_yad_argv:      dq pick_yad, pa_file, pa_title, pa_png_filter, 0
text s_no_picker,       "No file dialog found. Paste or drop the PNG into the box instead."

section .data
pick_fd:        dd -1                   ; the dialog's output, while it's open

section .bss
alignb 8
client_env:     resq 1                  ; for the dialog, set by _start
pick_pid:       resd 1
pick_field:     resd 1
pick_len:       resd 1
pick_buf:       resb 4096

section .text

; The image button: opens the file dialog for a box. edi = field
pick_image:
    push rbx
    sub rsp, 16
    mov ebx, edi
    cmp dword [pick_fd], -1
    jne .done                               ; one's open already
    call attach_busy
    test eax, eax
    jnz .done
    mov eax, SYS_pipe2
    mov rdi, rsp
    mov esi, O_CLOEXEC
    syscall
    test eax, eax
    js .done
    mov eax, SYS_fork
    syscall
    test eax, eax
    jz pick_child
    js .unpiped
    mov [pick_pid], eax
    mov eax, [rsp]
    mov [pick_fd], eax
    mov [pick_field], ebx
    mov dword [pick_len], 0
    mov eax, SYS_close
    mov edi, [rsp + 4]
    syscall
    jmp .done
.unpiped:
    mov eax, SYS_close
    mov edi, [rsp]
    syscall
    mov eax, SYS_close
    mov edi, [rsp + 4]
    syscall
.done:
    add rsp, 16
    pop rbx
    ret

; The forked child: its stdout becomes the pipe, then it turns into the
; first dialog program that exists. Never returns. [rsp + 4] = the pipe's write end
pick_child:
    mov eax, SYS_dup2
    mov edi, [rsp + 4]
    mov esi, 1
    syscall
    lea rbx, [pick_programs]
.program:
    mov rdi, [rbx]
    test rdi, rdi
    jz .none
    mov rsi, [rbx + 8]
    mov rdx, [client_env]
    mov eax, SYS_execve
    syscall
    add rbx, 16
    jmp .program
.none:
    mov edi, PICK_NONE
    call exit

; The dialog's pipe has something: more of the path, or the end of it.
pick_readable:
    push rbx
    sub rsp, 16
    mov eax, SYS_read
    mov edi, [pick_fd]
    mov esi, [pick_len]
    lea rsi, [pick_buf + rsi]
    mov edx, 4095
    sub edx, [pick_len]
    jz .closed                              ; longer than any path
    syscall
    cmp rax, -EINTR
    je .done
    test rax, rax
    jle .closed
    add [pick_len], eax
    jmp .done
.closed:
    mov eax, SYS_close
    mov edi, [pick_fd]
    syscall
    mov dword [pick_fd], -1
    mov dword [rsp], 0
    mov eax, SYS_wait4
    mov edi, [pick_pid]
    mov rsi, rsp
    xor edx, edx
    xor r10d, r10d
    syscall
    mov eax, [rsp]
    shr eax, 8                              ; the exit code
    and eax, 0xff
    cmp eax, PICK_NONE
    je .no_picker
    ; A path and a newline, or nothing if it was cancelled.
    mov ecx, [pick_len]
.trim:
    test ecx, ecx
    jz .done
    cmp byte [pick_buf + rcx - 1], 10
    jne .path
    dec ecx
    jmp .trim
.path:
    lea rdi, [att_path]
    lea rsi, [pick_buf]
    mov edx, ecx
    call put_mem
    mov byte [rdi], 0
    call read_att_path
    test eax, eax
    jz .unread
    mov edi, [pick_field]
    mov esi, eax
    call attach_bytes
    jmp .done
.unread:
    lea rsi, [s_attach_unread]
    mov edx, s_attach_unread_len
    call set_status
    jmp .done
.no_picker:
    lea rsi, [s_no_picker]
    mov edx, s_no_picker_len
    call set_status
.done:
    mov byte [need_redraw], 1
    add rsp, 16
    pop rbx
    ret

; The send button: what Enter does in the box. edi = field
click_send:
    cmp edi, F_MESSAGE
    je .message
    mov edi, F_COMMENT
    mov esi, [detail_issue]
    mov edx, OP_COMMENT
    jmp send_field
.message:
    mov dword [chat_scroll], 0
    mov esi, [chat_peer]
    mov edx, OP_MESSAGE
    jmp send_field

; The image and send buttons at a box's bottom right. The box's text keeps
; BOX_BUTTONS_W clear of them. edi = field, esi = the box's right edge,
; edx = its bottom
draw_box_buttons:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov ebx, edi
    lea r12d, [esi - 36]                    ; the send button's x
    lea r13d, [edx - 36]                    ; both buttons' y
    ; Sending needs some text or an uploaded image.
    call field_trimmed
    mov ebp, edx
    cmp ebx, [att_field]
    jne .sendable
    cmp dword [att_state], AT_READY
    jne .sendable
    mov ebp, 1
.sendable:
    mov r14d, C_LINE
    test ebp, ebp
    jz .send_bg
    mov edi, A_SEND
    mov esi, ebx
    call hovering
    mov r14d, C_ACCENT
    mov ecx, C_ACCENT_HI
    test eax, eax
    cmovnz r14d, ecx
.send_bg:
    mov edi, r12d
    mov esi, r13d
    mov edx, 28
    mov ecx, 28
    mov r8d, r14d
    mov r9d, 7
    call fill_rrect
    mov edi, GL_SEND
    lea esi, [r12d + 7]
    lea edx, [r13d + 7]
    mov ecx, 0xffffff
    mov eax, C_FAINT
    test ebp, ebp
    cmovz ecx, eax
    call draw_glyph
    mov edi, r12d
    mov esi, r13d
    mov edx, 28
    mov ecx, 28
    mov r8d, A_SEND
    mov r9d, ebx
    call add_hit

    sub r12d, 34                            ; the image button
    mov edi, A_ATTACH_PICK
    mov esi, ebx
    call hovering
    mov ebp, eax
    test eax, eax
    jz .image
    mov edi, r12d
    mov esi, r13d
    mov edx, 28
    mov ecx, 28
    mov r8d, C_SELECT
    mov r9d, 7
    call fill_rrect
.image:
    mov edi, GL_IMAGE
    lea esi, [r12d + 7]
    lea edx, [r13d + 7]
    mov ecx, C_DIM
    mov eax, C_TEXT
    test ebp, ebp
    cmovnz ecx, eax
    call draw_glyph
    mov edi, r12d
    mov esi, r13d
    mov edx, 28
    mov ecx, 28
    mov r8d, A_ATTACH_PICK
    mov r9d, ebx
    call add_hit
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
