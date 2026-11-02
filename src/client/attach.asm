; Pasting an image into the message or comment box. A PNG on the clipboard,
; or a PNG file copied in a file manager, is decoded for a preview above the
; box and uploaded a part at a time, and goes out with the text on Enter.
;
; One box has an attachment at a time, and it lasts as long as the box's
; text does: emptying the box, by sending or switching conversations, drops
; it. The server drops an upload that's never sent when the next one starts.
;
; Only one start is out at a time. The server answers each with its id or an
; error, in order, so a dropped upload's id can't be taken for the next one's.

%define AT_UPLOADING    1
%define AT_READY        2
%define AT_FAILED       3
%define ATTACH_H        84              ; the preview's height, with the gap under it
%define ATTACH_PREVIEW  72
%define ATTACH_PREVIEW_W 200            ; the widest it gets

section .rodata
text s_attach_type,     "Only PNG images can be attached"
text s_attach_big,      "Images can be PNGs up to 8 MB and 16 megapixels"
text s_attach_wait,     "The image is still uploading"
text s_attach_failed,   "The image didn't upload. Remove it or paste it again."
text s_uploading,       "Uploading "
text s_upload_failed,   "Upload failed"
file_scheme:            db "file://"
FILE_SCHEME_LEN equ $ - file_scheme

section .data
att_field:      dd F_NONE               ; the box the attachment is for

section .bss
alignb 4
att_peer:       resd 1                  ; the conversation it's for, 0 for a comment
att_state:      resd 1                  ; AT_*
att_waiting:    resd 1                  ; 1 while a start's answer is on the way
att_id:         resd 1                  ; the server's id for it, once it's said
att_bytes:      resd 1
att_got:        resd 1                  ; bytes the server has
att_w:          resd 1                  ; its size
att_h:          resd 1
att_tw:         resd 1                  ; the preview's size, as decoded
att_th:         resd 1
att_path:       resb 4096
alignb 16
att_px:         resd THUMB_W * THUMB_H
att_new:        resd THUMB_W * THUMB_H  ; a paste's preview, until it's taken
up_msg:         resb IMAGE_PART + 16
up_buf:         resb IMAGE_MAX + 1      ; one more, to tell a file that's too big

section .text

; Ctrl+V in a box that takes images, with an image or a file on the
; clipboard. edi = field -> eax = 1 if it was one, 0 to paste text instead
attach_paste:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, edi
    xor eax, eax
    cmp r12d, F_MESSAGE
    je .box
    cmp r12d, F_COMMENT
    jne .done
.box:
    cmp dword [id_data_source], 0
    jne .done                               ; our own copy, which is text
    cmp dword [clip_offer], 0
    je .done
    test dword [clip_types], (1 << PASTE_PNG) | (1 << PASTE_URI)
    jz .done
    ; Reading another image would land on the bytes still going up.
    cmp dword [att_waiting], 0
    jne .busy
    cmp dword [att_state], AT_UPLOADING
    je .busy
    bt dword [clip_types], PASTE_PNG
    jc .png
    bt dword [clip_types], PASTE_URI
    jnc .done
    call read_pasted_file
    test eax, eax
    jz .done
    jmp .got
.png:
    mov rbx, [paste_types + PASTE_PNG * 8]
    lea rdi, [up_buf]
    mov esi, IMAGE_MAX + 1
    call read_offer
.got:
    mov edi, r12d
    mov esi, eax
    call attach_bytes
    mov eax, 1
    jmp .done
.busy:
    lea rsi, [s_attach_wait]
    mov edx, s_attach_wait_len
    call set_status
    mov eax, 1
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; Reads the file a file manager put on the clipboard into up_buf, if it's
; a local one. -> eax = its length, or 0 for no file
read_pasted_file:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16 + STAT_SIZE                 ; a hex byte, then the file's stat
    mov rbx, [paste_types + PASTE_URI * 8]
    lea rdi, [paste_buf]
    mov esi, PASTE_MAX
    call read_offer
    mov r12d, eax
    cmp r12d, FILE_SCHEME_LEN
    jbe .none
    lea rdi, [paste_buf]
    lea rsi, [file_scheme]
    mov edx, FILE_SCHEME_LEN
    call mem_eq
    test eax, eax
    jz .none
    lea r13, [paste_buf + FILE_SCHEME_LEN]  ; where we're reading
    lea r14, [paste_buf + r12]              ; the end
.host:
    cmp r13, r14                            ; file://host/path, the host usually empty
    jae .none
    cmp byte [r13], '/'
    je .path
    inc r13
    jmp .host
.path:
    lea r15, [att_path]                     ; where the path's going
.char:
    cmp r13, r14
    jae .ended
    lea rax, [att_path + 4095]
    cmp r15, rax
    jae .none
    movzx eax, byte [r13]
    cmp al, 13
    je .ended                               ; just the first file
    cmp al, 10
    je .ended
    inc r13
    cmp al, '%'
    jne .put
    lea rax, [r13 + 2]
    cmp rax, r14
    ja .none
    mov rdi, rsp
    mov rsi, r13
    mov edx, 1
    call parse_hex
    test eax, eax
    jz .none
    add r13, 2
    movzx eax, byte [rsp]
.put:
    mov [r15], al
    inc r15
    jmp .char
.ended:
    mov byte [r15], 0
    mov eax, SYS_open
    lea rdi, [att_path]
    ; Nonblocking so a FIFO can't hang the client, and only a plain file is read.
    mov esi, O_RDONLY | O_CLOEXEC | O_NONBLOCK
    xor edx, edx
    syscall
    test eax, eax
    js .none
    mov ebx, eax
    xor r12d, r12d
    mov eax, SYS_fstat
    mov edi, ebx
    lea rsi, [rsp + 16]
    syscall
    test eax, eax
    jnz .close
    mov eax, [rsp + 16 + STAT_MODE]
    and eax, S_IFMT
    cmp eax, S_IFREG
    jne .close
.read:
    mov eax, SYS_read
    mov edi, ebx
    lea rsi, [up_buf + r12]
    mov edx, IMAGE_MAX + 1
    sub edx, r12d
    jz .close
    syscall
    cmp rax, -EINTR
    je .read
    test rax, rax
    jle .close
    add r12d, eax
    jmp .read
.close:
    mov eax, SYS_close
    mov edi, ebx
    syscall
    mov eax, r12d
    jmp .done
.none:
    xor eax, eax
.done:
    add rsp, 16 + STAT_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Takes the image in up_buf as the box's attachment and starts uploading it.
; edi = field, esi = its length
attach_bytes:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    lea rsi, [s_attach_big]
    mov edx, s_attach_big_len
    cmp r12d, IMAGE_MAX
    ja .say
    lea rdi, [up_buf]
    mov esi, r12d
    lea rdx, [att_new]
    mov ecx, THUMB_W
    mov r8d, THUMB_H
    call png_decode
    lea rsi, [s_attach_type]
    mov edx, s_attach_type_len
    test eax, eax
    jz .say
    call require_online
    test eax, eax
    jz .done
    mov [att_field], ebx
    xor eax, eax
    cmp ebx, F_MESSAGE
    jne .peer
    mov eax, [chat_peer]
.peer:
    mov [att_peer], eax
    mov dword [att_state], AT_UPLOADING
    mov dword [att_id], 0
    mov dword [att_got], 0
    mov [att_bytes], r12d
    mov eax, [png_w]
    mov [att_w], eax
    mov eax, [png_h]
    mov [att_h], eax
    mov eax, [png_dw]
    mov [att_tw], eax
    mov eax, [png_dh]
    mov [att_th], eax
    imul edx, eax, 4
    imul edx, [att_tw]
    lea rdi, [att_px]
    lea rsi, [att_new]
    call put_mem
    mov dword [att_waiting], 1
    lea rdi, [out_msg]
    mov esi, MSG_UPLOAD_IMAGE
    call wr_u8
    mov esi, [current_team]
    call wr_u32
    mov esi, [att_peer]
    call wr_u32
    mov esi, r12d
    call wr_u32
    mov esi, [att_w]
    call wr_u16
    mov esi, [att_h]
    call wr_u16
    call send_built
    mov byte [need_redraw], 1
    jmp .done
.say:
    call set_status
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; MSG_UPLOAD_READY: the server has this much of the upload, so the next
; part goes, or it's all there.
on_upload_ready:
    push rbx
    push r12
    sub rsp, 8
    call rd_u32
    mov ebx, eax
    call rd_u32
    mov r12d, eax
    cmp byte [rd_bad], 0
    jne .done
    test r12d, r12d
    jnz .part
    ; Nothing in yet answers the start that's out. If the attachment was
    ; dropped meanwhile, that upload is just left for the server to drop.
    mov dword [att_waiting], 0
    cmp dword [att_state], AT_UPLOADING
    jne .done
    cmp dword [att_id], 0
    jne .done
    mov [att_id], ebx
.part:
    cmp dword [att_state], AT_UPLOADING
    jne .done
    mov eax, [att_id]
    cmp eax, ebx
    jne .done
    mov [att_got], r12d
    mov byte [need_redraw], 1
    mov eax, [att_bytes]
    sub eax, r12d
    jbe .uploaded
    mov ecx, IMAGE_PART
    cmp eax, ecx
    cmova eax, ecx
    mov r12d, eax                           ; this part's length
    lea rdi, [up_msg]
    mov esi, MSG_IMAGE_PART
    call wr_u8
    mov esi, ebx
    call wr_u32
    mov eax, [att_got]
    lea rsi, [up_buf + rax]
    mov edx, r12d
    call wr_str16
    lea rsi, [up_msg]
    mov rdx, rdi
    sub rdx, rsi
    call net_send
    jmp .done
.uploaded:
    mov dword [att_state], AT_READY
    mov edi, ebx
    lea rsi, [att_px]
    mov edx, [att_tw]
    mov ecx, [att_th]
    call seed_thumb
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; An upload that was going won't finish: the server said no, or the
; connection went. Either way no answer to a start is still coming.
attach_failed:
    mov dword [att_waiting], 0
    cmp dword [att_state], AT_UPLOADING
    jne .done
    mov dword [att_state], AT_FAILED
    mov byte [need_redraw], 1
.done:
    ret

; Drops the box's attachment, if it has one. edi = field
attach_drop:
    cmp edi, [att_field]
    jne .done
    mov dword [att_field], F_NONE
    mov dword [att_state], 0
    mov byte [need_redraw], 1
.done:
    ret

; Enter in a box: what to send with its text. edi = field
; -> eax = the image id, 0 for none, or -1 if it can't go yet and the footer says why
attachment_to_send:
    xor eax, eax
    cmp edi, [att_field]
    jne .done
    mov eax, [att_id]
    cmp dword [att_state], AT_READY
    je .done
    sub rsp, 8
    lea rsi, [s_attach_wait]
    mov edx, s_attach_wait_len
    cmp dword [att_state], AT_UPLOADING
    je .say
    lea rsi, [s_attach_failed]
    mov edx, s_attach_failed_len
.say:
    call set_status
    add rsp, 8
    mov eax, -1
.done:
    ret

; edi = field -> eax = the room its attachment takes above it, 0 for none
attachment_height:
    xor eax, eax
    cmp edi, [att_field]
    jne .done
    mov eax, ATTACH_H
.done:
    ret

; The attachment's preview, with how the upload is going and an X to drop
; it. edi = field, esi = x, edx = y
draw_attachment:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 16
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    cmp ebx, [att_field]
    jne .done
    mov edi, [att_tw]
    mov esi, [att_th]
    mov edx, ATTACH_PREVIEW_W
    mov ecx, ATTACH_PREVIEW
    call fit_box
    mov r14d, eax                           ; preview width
    mov ebp, edx                            ; and height
    lea edi, [r12d - 1]
    lea esi, [r13d - 1]
    lea edx, [r14d + 2]
    lea ecx, [ebp + 2]
    mov r8d, C_LINE
    mov r9d, C_RAISED
    mov r10d, 4
    call outline_rrect
    lea rdi, [att_px]
    mov esi, [att_tw]
    mov edx, [att_th]
    mov ecx, r12d
    mov r8d, r13d
    mov r9d, r14d
    call draw_image
    ; The X sits on the preview's top right corner.
    lea edi, [r12d + r14d - 9]
    lea esi, [r13d + 9]
    mov edx, 12
    mov ecx, C_TEXT
    call draw_cross
    lea edi, [r12d + r14d - 20]
    lea esi, [r13d - 2]
    mov edx, 22
    mov ecx, 22
    mov r8d, A_DROP_ATTACHMENT
    mov r9d, ebx
    call add_hit
    ; How the upload's going, beside it.
    lea rdi, [scratch]
    cmp dword [att_state], AT_FAILED
    je .failed
    cmp dword [att_state], AT_UPLOADING
    jne .done
    lea rsi, [s_uploading]
    mov edx, s_uploading_len
    call put_mem
    mov eax, [att_got]
    imul rax, rax, 100
    xor edx, edx
    mov ecx, [att_bytes]
    div rcx
    mov esi, eax
    call put_u32
    mov byte [rdi], '%'
    inc rdi
    mov r8d, INK(C_DIM, ST_SMALL)
    jmp .say
.failed:
    lea rsi, [s_upload_failed]
    mov edx, s_upload_failed_len
    call put_mem
    mov r8d, INK(C_DANGER, ST_SMALL)
.say:
    mov rcx, rdi
    lea edi, [r12d + r14d + 12]
    mov esi, ebp
    shr esi, 1
    add esi, r13d
    add esi, 5
    call draw_scratch
.done:
    add rsp, 16
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
