; Images attached to messages and comments. Each is a row in T_IMAGES and a
; file named by its id in the directory beside the database. The row comes
; first, when the upload starts, and the file grows a part at a time until
; it has every byte. Until it's attached the image is its uploader's alone,
; and starting another upload drops it.
;
; The server only checks that the file starts like a PNG of the size it was
; said to be. Decoding is the clients' business.

%define PNG_MAGIC           0x0a1a0a0d474e5089
%define PNG_IHDR            0x52444849      ; "IHDR"

section .rodata
images_suffix:      db ".images", 0
text e_image_size,      "images can be PNGs up to 8 MB and 16 megapixels"
text e_image_type,      "only PNG images can be attached"
text e_images_full,     "the server has no room for more images"
text e_image_store,     "the server couldn't store that image"
text e_no_image,        "that image is gone"
text e_no_conversation, "that conversation doesn't exist anymore"

section .bss
image_dir:          resb 4096
image_file:         resb 4096 + 16

section .text

; Makes the directory the image files go in, beside the database.
image_init:
    sub rsp, 8
    lea rdi, [image_dir]
    mov rsi, [db_path]
    lea rdx, [images_suffix]
    call path_with_suffix
    mov eax, SYS_mkdir
    lea rdi, [image_dir]
    mov esi, 0o700
    syscall                                 ; it's usually there already
    add rsp, 8
    ret

; edi = image id -> rdi = its file's path in image_file
image_path:
    push rbx
    mov ebx, edi
    lea rdi, [image_file]
    lea rsi, [image_dir]
    call put_cstr
    mov byte [rdi], '/'
    inc rdi
    mov ecx, 8
.digit:
    rol ebx, 4
    mov eax, ebx
    and eax, 15
    movzx eax, byte [hex_digits + rax]
    stosb
    dec ecx
    jnz .digit
    mov byte [rdi], 0
    lea rdi, [image_file]
    pop rbx
    ret

; edi = image id -> rax = its row, or 0
find_image:
    xor eax, eax
    test edi, edi
    jz .done
    lea rax, [images]
    mov ecx, [n_images]
.row:
    test ecx, ecx
    jz .none
    cmp [rax + IMG_ID], edi
    je .done
    add rax, IMG_SIZE
    dec ecx
    jmp .row
.none:
    xor eax, eax
.done:
    ret

; edi = IMAGE_ON_*, esi = the message or comment -> rax = its image's row, or 0
image_of:
    lea rax, [images]
    mov ecx, [n_images]
.row:
    test ecx, ecx
    jz .none
    movzx edx, byte [rax + IMG_KIND]
    cmp edx, edi
    jne .next
    cmp [rax + IMG_PARENT], esi
    je .done
.next:
    add rax, IMG_SIZE
    dec ecx
    jmp .row
.none:
    xor eax, eax
.done:
    ret

; Deletes an image's file and frees its row. rdi = row
free_image:
    push rbx
    mov rbx, rdi
    mov edi, [rbx + IMG_ID]
    call image_path
    mov eax, SYS_unlink
    syscall
    mov edi, T_IMAGES
    mov rsi, rbx
    call free_row
    pop rbx
    ret

; A message or comment being freed takes its image with it.
; edi = table, rsi = row. Anything but a message or comment is left alone.
drop_attached_image:
    mov edx, IMAGE_ON_MESSAGE
    cmp edi, T_MESSAGES
    je .drop
    mov edx, IMAGE_ON_COMMENT
    cmp edi, T_COMMENTS
    jne .done
.drop:
    mov edi, edx
    mov esi, [rsi]                          ; MS_ID and CMT_ID both come first
    test esi, esi
    jz .done
    sub rsp, 8
    call image_of
    add rsp, 8
    test rax, rax
    jz .done
    mov rdi, rax
    jmp free_image
.done:
    ret

; Frees the images a user uploaded that aren't attached to anything.
; edi = user
drop_unattached:
    push rbx
    push r12
    push r13
    mov r12d, edi
    lea rbx, [images]
    mov r13d, [n_images]
.row:
    test r13d, r13d
    jz .done
    cmp dword [rbx + IMG_ID], 0
    je .next
    cmp byte [rbx + IMG_KIND], 0
    jne .next
    cmp [rbx + IMG_OWNER], r12d
    jne .next
    mov rdi, rbx
    call free_image
.next:
    add rbx, IMG_SIZE
    dec r13d
    jmp .row
.done:
    pop r13
    pop r12
    pop rbx
    ret

; At startup: an upload the server stopped in the middle of won't be
; finished, since the client lost track of it when the connection went.
drop_partial_images:
    push rbx
    push r12
    sub rsp, 8
    lea rbx, [images]
    mov r12d, [n_images]
.row:
    test r12d, r12d
    jz .done
    cmp dword [rbx + IMG_ID], 0
    je .next
    mov eax, [rbx + IMG_GOT]
    cmp eax, [rbx + IMG_BYTES]
    je .next
    mov rdi, rbx
    call free_image
.next:
    add rbx, IMG_SIZE
    dec r12d
    jmp .row
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; rdi = cursor, esi = IMAGE_ON_*, edx = the message or comment -> rdi advanced.
; Writes the image as the wire has it, zeros for none.
wr_image_ref:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov edi, esi
    mov esi, edx
    call image_of
    mov r12, rax
    mov rdi, rbx
    xor esi, esi
    test r12, r12
    jz .id
    mov esi, [r12 + IMG_ID]
.id:
    call wr_u32
    xor esi, esi
    test r12, r12
    jz .width
    movzx esi, word [r12 + IMG_WIDTH]
.width:
    call wr_u16
    xor esi, esi
    test r12, r12
    jz .height
    movzx esi, word [r12 + IMG_HEIGHT]
.height:
    call wr_u16
    add rsp, 8
    pop r12
    pop rbx
    ret

; The text and image of an OP_COMMENT or OP_MESSAGE being applied: text,
; an image the user finished uploading for this conversation, or both.
; edi = team, esi = peer (0 for a comment), edx = max text length
; -> eax = 1 if acceptable, rdx = the image's row or 0
op_attachment:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov r13d, esi
    mov rsi, [op_body]
    mov ecx, edx
    mov edx, [op_body_len]
    call valid_body
    test eax, eax
    jz .no
    xor ebx, ebx
    mov edi, [op_image]
    test edi, edi
    jz .text_only
    call find_image
    test rax, rax
    jz .no
    mov rbx, rax
    mov eax, [op_user]
    cmp [rbx + IMG_OWNER], eax
    jne .no
    cmp [rbx + IMG_TEAM], r12d
    jne .no
    cmp [rbx + IMG_TO], r13d
    jne .no
    cmp byte [rbx + IMG_KIND], 0
    jne .no                                 ; already on something
    mov eax, [rbx + IMG_GOT]
    cmp eax, [rbx + IMG_BYTES]
    jne .no
    jmp .yes
.text_only:
    cmp dword [op_body_len], 0
    je .no
.yes:
    mov eax, 1
    mov rdx, rbx
    jmp .done
.no:
    xor eax, eax
    xor edx, edx
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Attaches an image op_attachment accepted. rdi = its row or 0,
; esi = IMAGE_ON_*, edx = the message or comment. Touched, not committed.
attach_image:
    test rdi, rdi
    jz .done
    mov [rdi + IMG_KIND], sil
    mov [rdi + IMG_PARENT], edx
    mov rsi, rdi
    mov edi, T_IMAGES
    jmp db_touch
.done:
    ret

; rdi = image row, esi = user -> eax = 1 if they can see it
image_readable:
    cmp [rdi + IMG_OWNER], esi
    je .yes
    cmp byte [rdi + IMG_KIND], 0
    je .no                                  ; not sent yet
    mov eax, [rdi + IMG_TO]
    test eax, eax
    jle .member                             ; #general, a channel or a comment
    cmp eax, esi
    jne .no                                 ; someone else's direct message
.member:
    sub rsp, 8
    mov edi, [rdi + IMG_TEAM]
    call find_member
    add rsp, 8
    test rax, rax
    setnz al
    movzx eax, al
    ret
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; Tells cur how much of an upload has arrived. edi = image, esi = bytes
send_upload_ready:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    lea rdi, [msg_buf]
    mov esi, MSG_UPLOAD_READY
    call wr_u8
    mov esi, ebx
    call wr_u32
    mov esi, r12d
    call wr_u32
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    call reply
    add rsp, 8
    pop r12
    pop rbx
    ret

; Checks the first part of an upload is a PNG of the size the upload said.
; rdi = image row, rsi = the part, edx = its length -> eax = 1 if it is
png_start_ok:
    xor eax, eax
    cmp edx, 24
    jb .done
    mov rcx, PNG_MAGIC
    cmp [rsi], rcx
    jne .done
    cmp dword [rsi + 12], PNG_IHDR
    jne .done
    mov ecx, [rsi + 16]
    bswap ecx
    movzx edx, word [rdi + IMG_WIDTH]
    cmp ecx, edx
    jne .done
    mov ecx, [rsi + 20]
    bswap ecx
    movzx edx, word [rdi + IMG_HEIGHT]
    cmp ecx, edx
    jne .done
    mov eax, 1
.done:
    ret

; Appends to an image's file. edi = image id, rsi = bytes, edx = length,
; ecx = 1 to sync it to disk after -> eax = 1 if it all got written
append_image:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    call image_path
    mov eax, SYS_open
    mov esi, O_WRONLY | O_APPEND | O_CLOEXEC
    xor edx, edx
    syscall
    mov ebx, eax
    xor eax, eax
    test ebx, ebx
    js .done
    mov edi, ebx
    mov rsi, r12
    mov edx, r13d
    call write_all
    mov r12d, eax                           ; 0 when it all went
    test r14d, r14d
    jz .close
    mov eax, SYS_fdatasync
    mov edi, ebx
    syscall
    or r12d, eax
    ; The file's name isn't on disk until its directory is synced too.
    mov eax, SYS_open
    lea rdi, [image_dir]
    mov esi, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor edx, edx
    syscall
    mov r14d, eax
    test eax, eax
    js .unsynced
    mov eax, SYS_fsync
    mov edi, r14d
    syscall
    or r12d, eax
    mov eax, SYS_close
    mov edi, r14d
    syscall
    jmp .close
.unsynced:
    or r12d, 1
.close:
    mov eax, SYS_close
    mov edi, ebx
    syscall
    xor eax, eax
    test r12d, r12d
    setz al
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; edi = width, esi = height -> eax = 1 if an image can be that big
image_size_ok:
    xor eax, eax
    lea ecx, [edi - 1]
    cmp ecx, IMAGE_SIDE_MAX
    jae .done
    lea ecx, [esi - 1]
    cmp ecx, IMAGE_SIDE_MAX
    jae .done
    mov ecx, edi
    imul ecx, esi
    cmp ecx, IMAGE_PIXELS_MAX
    ja .done
    mov eax, 1
.done:
    ret

; -> eax = a random id no image has, never 0
new_image_id:
    sub rsp, 24
.try:
    mov rdi, rsp
    mov esi, 4
    call random_bytes
    mov edi, [rsp]
    test edi, edi
    jz .try
    call find_image
    test rax, rax
    jnz .try
    mov eax, [rsp]
    add rsp, 24
    ret

; MSG_UPLOAD_IMAGE: makes the row and an empty file for a new image, and
; asks for its first part.
h_upload_image:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    call rd_u32
    mov r12d, eax                           ; team
    call rd_u32
    mov r13d, eax                           ; peer
    call rd_u32
    mov r14d, eax                           ; bytes
    call rd_u16
    mov r15d, eax                           ; width
    call rd_u16
    mov ebp, eax                            ; height
    call rd_ok
    test eax, eax
    jz .violation
    mov rax, [cur]
    mov ebx, [rax + C_USER]
    mov edi, r12d
    mov esi, ebx
    call find_member
    test rax, rax
    jz .not_member
    mov edi, r12d
    mov esi, r13d
    test esi, esi
    jz .sized
    js .channel
    call find_member
    test rax, rax
    jz .no_peer
    jmp .sized
.channel:
    call find_channel_peer
    test rax, rax
    jz .no_peer
.sized:
    lea eax, [r14d - 1]
    cmp eax, IMAGE_MAX
    jae .too_big
    mov edi, r15d
    mov esi, ebp
    call image_size_ok
    test eax, eax
    jz .too_big
    mov edi, ebx
    call drop_unattached
    mov edi, T_IMAGES
    call alloc_row
    test rax, rax
    jz .full
    mov [rax + IMG_HEIGHT], bp
    mov rbp, rax
    mov [rbp + IMG_TEAM], r12d
    mov [rbp + IMG_OWNER], ebx
    mov [rbp + IMG_TO], r13d
    mov [rbp + IMG_BYTES], r14d
    mov [rbp + IMG_WIDTH], r15w
    call new_image_id
    mov [rbp + IMG_ID], eax
    mov edi, eax
    call image_path
    mov eax, SYS_open
    mov esi, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov edx, 0o600
    syscall
    test eax, eax
    js .unstored
    mov edi, eax
    mov eax, SYS_close
    syscall
    mov edi, T_IMAGES
    mov rsi, rbp
    call db_touch
    call db_commit
    mov edi, [rbp + IMG_ID]
    xor esi, esi
    call send_upload_ready
    jmp .done
.unstored:
    mov edi, T_IMAGES
    mov rsi, rbp
    call free_row
    call db_commit
    lea rsi, [e_image_store]
    mov edx, e_image_store_len
    jmp .error
.violation:
    call kill_cur
    jmp .done
.not_member:
    lea rsi, [e_not_member]
    mov edx, e_not_member_len
    jmp .error
.no_peer:
    lea rsi, [e_no_conversation]
    mov edx, e_no_conversation_len
    jmp .error
.too_big:
    lea rsi, [e_image_size]
    mov edx, e_image_size_len
    jmp .error
.full:
    lea rsi, [e_images_full]
    mov edx, e_images_full_len
.error:
    call send_error
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; MSG_IMAGE_PART: the next bytes of the uploader's image, written to its
; file before the row says they're there.
h_image_part:
    push rbx
    push r12
    push r13
    call rd_u32
    mov ebx, eax
    call rd_str16
    mov r12, rax
    mov r13d, edx
    call rd_ok
    test eax, eax
    jz .violation
    mov edi, ebx
    call find_image
    test rax, rax
    jz .gone
    mov rbx, rax
    mov rax, [cur]
    mov eax, [rax + C_USER]
    cmp [rbx + IMG_OWNER], eax
    jne .gone
    test r13d, r13d
    jz .violation
    mov eax, [rbx + IMG_BYTES]
    sub eax, [rbx + IMG_GOT]
    cmp r13d, eax
    ja .violation                           ; more than it said it had
    cmp dword [rbx + IMG_GOT], 0
    jne .append
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    call png_start_ok
    test eax, eax
    jz .not_png
.append:
    mov eax, [rbx + IMG_BYTES]
    sub eax, [rbx + IMG_GOT]
    xor ecx, ecx
    cmp eax, r13d
    sete cl                                 ; the last part goes to disk before it counts
    mov edi, [rbx + IMG_ID]
    mov rsi, r12
    mov edx, r13d
    call append_image
    test eax, eax
    jz .unstored
    add [rbx + IMG_GOT], r13d
    mov edi, T_IMAGES
    mov rsi, rbx
    call db_touch
    call db_commit
    mov edi, [rbx + IMG_ID]
    mov esi, [rbx + IMG_GOT]
    call send_upload_ready
    jmp .done
.violation:
    call kill_cur
    jmp .done
.gone:
    lea rsi, [e_no_image]
    mov edx, e_no_image_len
    jmp .error
.not_png:
    lea r12, [e_image_type]
    mov r13d, e_image_type_len
    jmp .drop
.unstored:
    lea r12, [e_image_store]
    mov r13d, e_image_store_len
.drop:
    mov rdi, rbx
    call free_image
    call db_commit
    mov rsi, r12
    mov edx, r13d
.error:
    call send_error
.done:
    pop r13
    pop r12
    pop rbx
    ret

; MSG_GET_IMAGE: up to IMAGE_PART bytes of an image, from an offset. One the
; user can't see, or that isn't all there, comes back as 0 bytes long.
h_get_image:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call rd_u32
    mov ebx, eax
    call rd_u32
    mov r12d, eax
    call rd_ok
    test eax, eax
    jz .violation
    mov edi, ebx
    call find_image
    test rax, rax
    jz .none
    mov r13, rax
    mov eax, [r13 + IMG_GOT]
    cmp eax, [r13 + IMG_BYTES]
    jne .none
    mov rdi, r13
    mov rax, [cur]
    mov esi, [rax + C_USER]
    call image_readable
    test eax, eax
    jz .none
    mov r14d, [r13 + IMG_BYTES]
    sub r14d, r12d
    jb .none                                ; past the end
    mov eax, IMAGE_PART
    cmp r14d, eax
    cmova r14d, eax
    mov edi, ebx
    call image_path
    mov eax, SYS_open
    mov esi, O_RDONLY | O_CLOEXEC
    xor edx, edx
    syscall
    test eax, eax
    js .none
    mov r15d, eax
    lea rdi, [msg_buf]
    mov esi, MSG_IMAGE
    call wr_u8
    mov esi, ebx
    call wr_u32
    mov esi, [r13 + IMG_BYTES]
    call wr_u32
    mov esi, r12d
    call wr_u32
    mov esi, r14d
    call wr_u16
    mov rsi, rdi
    mov r13, rdi                            ; where the bytes go
    mov eax, SYS_pread64
    mov edi, r15d
    mov edx, r14d
    mov r10d, r12d
    syscall
    mov r12, rax
    mov eax, SYS_close
    mov edi, r15d
    syscall
    cmp r12, r14
    jne .none                               ; the file's shorter than its row says
    lea rsi, [msg_buf]
    lea rdx, [r13 + r14]
    sub rdx, rsi
    call reply
    jmp .done
.none:
    lea rdi, [msg_buf]
    mov esi, MSG_IMAGE
    call wr_u8
    mov esi, ebx
    call wr_u32
    xor esi, esi
    call wr_u32
    xor esi, esi
    call wr_u32
    xor esi, esi
    call wr_u16
    lea rsi, [msg_buf]
    mov rdx, rdi
    sub rdx, rsi
    call reply
    jmp .done
.violation:
    call kill_cur
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
