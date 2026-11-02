; Copy and paste through the compositor's wl_data_device.
;
; Copying makes a wl_data_source holding the text, and the compositor asks
; for it with a send event and a pipe whenever someone pastes. Whatever
; someone else copied arrives as a wl_data_offer, announced by data_offer
; with its types, then made the clipboard by selection. Pasting asks the
; offer to write into a pipe and reads it. Pasting our own copy skips that,
; since we'd be waiting on ourselves.

%define CLIP_MAX        DESC_MAX                ; the longest field
%define PASTE_MAX       8192                    ; UTF-8 can take a few bytes per character
%define PASTE_WAIT_MS   500                     ; for a slow app to answer, per read

; wl_data_device_manager, wl_data_device, wl_data_source and wl_data_offer opcodes
%define DDM_CREATE_SOURCE   0
%define DDM_GET_DEVICE      1
%define DD_SET_SELECTION    1
%define DS_OFFER            0
%define DS_DESTROY          1
%define DO_RECEIVE          1
%define DO_DESTROY          2

section .rodata
s_type_utf8:        db "text/plain;charset=utf-8", 0
s_type_utf8_string: db "UTF8_STRING", 0
s_type_plain:       db "text/plain", 0
s_type_png:         db "image/png", 0
s_type_uri_list:    db "text/uri-list", 0
align 8
; The text types we give, the best first.
text_types:         dq s_type_utf8, s_type_utf8_string, s_type_plain, 0
; And what we take: those, then an image or a copied file for attach.asm.
; new_types and clip_types have a bit for each one an offer has.
paste_types:        dq s_type_utf8, s_type_utf8_string, s_type_plain, s_type_png, s_type_uri_list, 0
%define PASTE_TEXT      7               ; the text types' bits
%define PASTE_PNG       3
%define PASTE_URI       4

section .bss
alignb 4
id_data_manager:    resd 1
id_data_device:     resd 1
id_data_source:     resd 1                  ; our copy, while it's the clipboard
stale_source:       resd 1                  ; the copy before it, destroyed but maybe still asked for
new_offer:          resd 1                  ; the offer being described, before selection takes it
new_types:          resd 1
clip_offer:         resd 1                  ; what someone else copied, or 0
clip_types:         resd 1
input_serial:       resd 1                  ; the last key or button press, which set_selection needs
clip_len:           resd 1
clip_buf:           resb CLIP_MAX
paste_buf:          resb PASTE_MAX

section .text

; Makes the data device once the seat and the manager are both bound.
clip_init:
    cmp dword [id_data_manager], 0
    je .done
    cmp dword [id_seat], 0
    je .done
    mov edi, [id_data_manager]
    mov esi, DDM_GET_DEVICE
    call wl_begin
    lea rdi, [id_data_device]
    call wl_new_id
    call wl_u32
    mov edi, [id_seat]
    call wl_u32
    call wl_end
.done:
    ret

; edi = offer id
destroy_offer:
    mov esi, DO_DESTROY
    call wl_begin
    jmp wl_end

; wl_data_device.data_offer(new offer) / selection(offer or null)
on_data_device:
    test esi, esi
    jz .offer
    cmp esi, 5
    je .selection
    ret
.offer:
    ; One that came and went without becoming the clipboard, like a drag
    ; passing over the window, is done with.
    push qword [rdx]
    mov edi, [new_offer]
    test edi, edi
    jz .fresh
    cmp edi, [clip_offer]
    je .fresh
    call destroy_offer
.fresh:
    pop rax
    mov [new_offer], eax
    mov dword [new_types], 0
    ret
.selection:
    push qword [rdx]
    mov edi, [clip_offer]
    test edi, edi
    jz .take
    cmp edi, [rsp]
    je .take
    call destroy_offer
.take:
    pop rax
    mov [clip_offer], eax
    mov dword [clip_types], 0
    test eax, eax
    jz .done
    cmp eax, [new_offer]
    jne .done
    mov ecx, [new_types]
    mov [clip_types], ecx
    mov dword [new_offer], 0
.done:
    ret

; wl_data_offer.offer(type), for the offer data_offer just announced
on_data_offer:
    test esi, esi
    jnz .done
    cmp edi, [new_offer]
    jne .done
    push rbx
    push r12
    sub rsp, 8
    lea r12, [rdx + 4]
    xor ebx, ebx
.type:
    mov rsi, [paste_types + rbx * 8]
    test rsi, rsi
    jz .out
    mov rdi, r12
    call cstr_eq
    test eax, eax
    jz .next
    bts dword [new_types], ebx
    jmp .out
.next:
    inc ebx
    jmp .type
.out:
    add rsp, 8
    pop r12
    pop rbx
.done:
    ret

; wl_data_source.send(type, fd) writes our copy / cancelled: someone else's is the clipboard now
on_data_source:
    cmp esi, 1
    je .send
    cmp esi, 2
    je .cancelled
    ret
.send:
    ; The fd is ours to close even when the source is the stale one, or it
    ; would sit in front of every fd after it.
    push rbx
    push rdi
    call wl_take_fd
    pop rdi
    mov ebx, eax
    test eax, eax
    js .sent
    cmp edi, [id_data_source]
    jne .close
    mov edi, eax
    lea rsi, [clip_buf]
    mov edx, [clip_len]
    call write_all                          ; a pipe takes this much without blocking
.close:
    mov eax, SYS_close
    mov edi, ebx
    syscall
.sent:
    pop rbx
    ret
.cancelled:
    cmp edi, [id_data_source]
    jne .stale                              ; already destroyed
    mov esi, DS_DESTROY
    call wl_begin
    call wl_end
    mov dword [id_data_source], 0
.stale:
    ret

; Puts text on the clipboard. rsi = text, edx = length
clip_copy:
    cmp dword [id_data_device], 0
    je .done
    push rbx
    mov ecx, CLIP_MAX
    cmp edx, ecx
    cmova edx, ecx
    mov [clip_len], edx
    lea rdi, [clip_buf]
    call put_mem
    mov edi, [id_data_source]
    test edi, edi
    jz .create
    mov [stale_source], edi
    mov esi, DS_DESTROY
    call wl_begin
    call wl_end
.create:
    mov edi, [id_data_manager]
    mov esi, DDM_CREATE_SOURCE
    call wl_begin
    lea rdi, [id_data_source]
    call wl_new_id
    call wl_u32
    call wl_end
    xor ebx, ebx
.offer:
    mov rax, [text_types + rbx * 8]
    test rax, rax
    jz .select
    mov edi, [id_data_source]
    mov esi, DS_OFFER
    call wl_begin
    mov rdi, [text_types + rbx * 8]
    call wl_str
    call wl_end
    inc ebx
    jmp .offer
.select:
    mov edi, [id_data_device]
    mov esi, DD_SET_SELECTION
    call wl_begin
    mov edi, [id_data_source]
    call wl_u32
    mov edi, [input_serial]
    call wl_u32
    call wl_end
    pop rbx
.done:
    ret

; Pastes the clipboard into a field, over its selection. edi = field
clip_paste:
    push rbx
    push r12
    push r13
    mov r12d, edi
    call attach_paste
    test eax, eax
    jnz .done
    cmp dword [id_data_source], 0
    je .other
    mov edi, r12d
    lea rsi, [clip_buf]
    mov edx, [clip_len]
    call field_insert_text
    jmp .done
.other:
    mov eax, [clip_types]
    and eax, PASTE_TEXT
    jz .done
    cmp dword [clip_offer], 0
    je .done
    bsf eax, eax                            ; the best type it has
    mov rbx, [text_types + rax * 8]
    lea rdi, [paste_buf]
    mov esi, PASTE_MAX
    call read_offer
    test eax, eax
    jz .done
    mov r13d, eax
    mov edi, r12d
    lea rsi, [paste_buf]
    mov edx, r13d
    call field_insert_text
    lea rdi, [paste_buf]                    ; it might have been a password
    mov esi, r13d
    call wipe
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Has clip_offer write itself into a pipe and reads it.
; rbx = the type to ask for, rdi = where to, esi = room there -> eax = bytes read
read_offer:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 24
    mov r13, rdi
    mov r14d, esi
    mov eax, SYS_pipe2
    mov rdi, rsp
    mov esi, O_CLOEXEC
    syscall
    test eax, eax
    js .fail
    call wl_flush                           ; the fd goes with the next flush's first chunk
    mov edi, [clip_offer]
    mov esi, DO_RECEIVE
    call wl_begin
    mov rdi, rbx
    call wl_str
    call wl_end
    mov eax, [rsp + 4]
    mov [wl_pending_fd], eax
    call wl_flush
    mov eax, SYS_close
    mov edi, [rsp + 4]
    syscall
    xor r12d, r12d                          ; bytes read
.wait:
    mov eax, [rsp]
    mov [rsp + 8], eax                      ; struct pollfd
    mov dword [rsp + 12], POLLIN
    mov eax, SYS_poll
    lea rdi, [rsp + 8]
    mov esi, 1
    mov edx, PASTE_WAIT_MS
    syscall
    cmp rax, -EINTR
    je .wait
    test rax, rax
    jle .close                              ; it never answered
    mov eax, SYS_read
    mov edi, [rsp]
    lea rsi, [r13 + r12]
    mov edx, r14d
    sub edx, r12d
    jz .close
    syscall
    cmp rax, -EINTR
    je .wait
    test rax, rax
    jle .close                              ; the end, or it broke
    add r12d, eax
    jmp .wait
.close:
    mov eax, SYS_close
    mov edi, [rsp]
    syscall
    mov eax, r12d
    jmp .done
.fail:
    xor eax, eax
.done:
    add rsp, 24
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
