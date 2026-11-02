; Images in messages and comments: fetching them, keeping them decoded at
; the size they're shown at, and drawing them. Clicking one opens it as big
; as the window allows, decoded again at that size.
;
; One image downloads at a time, a part per request, into dl_buf. Its bytes
; stay there until the next download, so opening the one just fetched
; doesn't fetch it again.

%define THUMB_W         360             ; the most an image takes in the conversation
%define THUMB_H         240
%define THUMB_SLOTS     24
%define VIEW_W          1600            ; and opened
%define VIEW_H          1200
%define VIEW_MARGIN     48
%define TS_WANTED       1
%define TS_LOADING      2
%define TS_READY        3
%define TS_FAILED       4

%define TH_ID           0
%define TH_STATE        4               ; TS_*, 0 for a free slot
%define TH_W            8               ; the decoded size
%define TH_H            12
%define TH_USED         16              ; thumb_clock when it was last drawn
%define TH_SIZE         20
fits TH_USED, 4, TH_SIZE

section .rodata
text s_image_loading,   "Loading image"
text s_image_failed,    "Image unavailable"

section .bss
alignb 4
thumbs:         resb THUMB_SLOTS * TH_SIZE
thumb_clock:    resd 1                  ; counts frames
dl_id:          resd 1                  ; the image downloading, 0 for none
dl_bytes:       resd 1
dl_got:         resd 1
dl_done:        resd 1                  ; the image whole in dl_buf, 0 for none
view_id:        resd 1                  ; the opened image
view_state:     resd 1                  ; TS_*
view_max_w:     resd 1                  ; the room it had when it was opened
view_max_h:     resd 1
view_w:         resd 1
view_h:         resd 1
alignb 16
thumb_px:       resd THUMB_SLOTS * THUMB_W * THUMB_H
view_px:        resd VIEW_W * VIEW_H
dl_buf:         resb IMAGE_MAX

section .text

; The size an image shows at in a column. edi = its width, esi = its height,
; edx = the column's width -> eax = width, edx = height
thumb_size:
    mov ecx, THUMB_W
    cmp edx, ecx
    cmova edx, ecx
    mov ecx, THUMB_H
    jmp fit_box

; edi = image id -> rax = its slot, made and wanted if it had none, the
; least recently drawn slot making way
thumb_slot:
    push rbx
    lea rax, [thumbs]
    xor ecx, ecx
    xor ebx, ebx                            ; the slot to take
.slot:
    cmp ecx, THUMB_SLOTS
    jae .take
    cmp [rax + TH_ID], edi
    jne .other
    cmp dword [rax + TH_STATE], 0
    jne .found
.other:
    cmp dword [rax + TH_STATE], TS_LOADING
    je .next                                ; its bytes are on the way
    test rbx, rbx
    jz .candidate
    cmp dword [rax + TH_STATE], 0
    je .candidate
    cmp dword [rbx + TH_STATE], 0
    je .next
    mov edx, [rax + TH_USED]
    cmp edx, [rbx + TH_USED]
    jae .next
.candidate:
    mov rbx, rax
.next:
    add rax, TH_SIZE
    inc ecx
    jmp .slot
.take:
    mov rax, rbx
    test rax, rax
    jz .done                                ; every one is loading
    mov [rax + TH_ID], edi
    mov dword [rax + TH_STATE], TS_WANTED
.found:
    mov ecx, [thumb_clock]
    mov [rax + TH_USED], ecx
.done:
    pop rbx
    ret

; rax = a slot -> rax = its pixels
thumb_pixels:
    sub rax, thumbs
    xor edx, edx
    mov ecx, TH_SIZE
    div ecx
    imul rax, rax, THUMB_W * THUMB_H * 4
    add rax, thumb_px
    ret

; Blends premultiplied pixels into the framebuffer, scaled to a width, the
; height following. rdi = pixels, esi = their width, edx = their height,
; ecx = x, r8d = y, r9d = width to draw at
draw_image:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov r12d, ecx                           ; x
    mov r13d, r8d                           ; y
    mov [rsp], rdi
    mov [rsp + 8], esi                      ; source width
    mov [rsp + 12], edx                     ; source height
    mov eax, edx
    imul eax, r9d
    xor edx, edx
    div esi
    mov ecx, 1
    cmp eax, ecx
    cmovb eax, ecx
    mov [rsp + 16], eax                     ; height to draw at
    mov eax, esi
    shl rax, 16
    xor edx, edx
    div r9                                  ; source step per pixel, 16.16
    mov [rsp + 20], eax
    mov eax, [rsp + 12]
    shl rax, 16
    xor edx, edx
    mov ebx, [rsp + 16]
    div rbx
    mov [rsp + 24], eax
    lea r14d, [r12d + r9d]                  ; right
    mov r15d, r13d
    add r15d, [rsp + 16]                    ; bottom
    mov eax, [clip_x0]
    cmp eax, r12d
    cmovl eax, r12d
    mov [rsp + 28], eax                     ; first column drawn
    cmp r14d, [clip_x1]
    cmovg r14d, [clip_x1]
    cmp r15d, [clip_y1]
    cmovg r15d, [clip_y1]
    mov ebx, [clip_y0]
    cmp ebx, r13d
    cmovl ebx, r13d                         ; row
.row:
    cmp ebx, r15d
    jge .done
    mov eax, ebx
    sub eax, r13d
    imul eax, [rsp + 24]
    shr eax, 16
    imul eax, [rsp + 8]
    mov rsi, [rsp]
    lea rsi, [rsi + rax * 4]                ; the source row
    mov eax, ebx
    imul eax, [fb_w]
    mov rdi, [fb]
    lea rdi, [rdi + rax * 4]                ; the framebuffer row
    mov ebp, [rsp + 28]
.pixel:
    cmp ebp, r14d
    jge .next_row
    mov eax, ebp
    sub eax, r12d
    imul eax, [rsp + 20]
    shr eax, 16
    mov eax, [rsi + rax * 4]
    mov ecx, eax
    shr ecx, 24
    jz .skip                                ; clear
    cmp ecx, 255
    je .opaque
    ; dst = src + dst * (256 - alpha) / 256, red and blue together, then green.
    neg ecx
    add ecx, 256
    mov edx, [rdi + rbp * 4]
    mov r8d, edx
    and r8d, 0xff00ff
    imul r8d, ecx
    shr r8d, 8
    and r8d, 0xff00ff
    and edx, 0xff00
    imul edx, ecx
    shr edx, 8
    and edx, 0xff00
    add eax, r8d
    add eax, edx
.opaque:
    and eax, 0xffffff
    mov [rdi + rbp * 4], eax
.skip:
    inc ebp
    jmp .pixel
.next_row:
    inc ebx
    jmp .row
.done:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Where an image will be: a box the size it'll take, with a word on why
; there's no picture yet. edi = x, esi = y, edx = w, ecx = h, r8 = text, r9d = its length
draw_image_box:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov ebx, edi
    mov ebp, esi
    mov r12d, edx
    mov r13d, ecx
    mov r14, r8
    mov r15d, r9d
    mov r8d, C_LINE
    mov r9d, C_RAISED
    mov r10d, 6
    call outline_rrect
    mov edi, ebx
    mov esi, r12d
    mov edx, r13d
    shr edx, 1
    add edx, ebp
    add edx, 5
    mov rcx, r14
    mov r8d, r15d
    mov r9d, INK(C_FAINT, ST_SMALL)
    call draw_centered
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; A message's or comment's image, which opens big when clicked.
; edi = image id, esi = its width, edx = its height, ecx = x, r8d = y,
; r9d = the column's width -> eax = the height it takes
draw_attached_image:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov ebx, edi
    mov r12d, ecx
    mov r13d, r8d
    mov edi, esi
    mov esi, edx
    mov edx, r9d
    call thumb_size
    mov r14d, eax                           ; width
    mov r15d, edx                           ; height
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r15d
    mov r8d, A_IMAGE
    mov r9d, ebx
    call add_hit
    mov edi, ebx
    call thumb_slot
    test rax, rax
    jz .loading
    cmp dword [rax + TH_STATE], TS_READY
    je .ready
    cmp dword [rax + TH_STATE], TS_FAILED
    jne .loading
    lea r8, [s_image_failed]
    mov r9d, s_image_failed_len
    jmp .box
.loading:
    lea r8, [s_image_loading]
    mov r9d, s_image_loading_len
.box:
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r15d
    call draw_image_box
    jmp .done
.ready:
    mov rbp, rax
    ; The room was made from the size the message says, so a PNG that's
    ; another shape than it claimed gets cut to it, not drawn over the next one.
    mov eax, [clip_y1]
    mov [rsp], eax
    lea ecx, [r13d + r15d]
    cmp eax, ecx
    cmovg eax, ecx
    mov [clip_y1], eax
    mov rax, rbp
    call thumb_pixels
    mov rdi, rax
    mov esi, [rbp + TH_W]
    mov edx, [rbp + TH_H]
    mov ecx, r12d
    mov r8d, r13d
    mov r9d, r14d
    call draw_image
    mov eax, [rsp]
    mov [clip_y1], eax
.done:
    mov eax, r15d
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = image id, esi = byte offset. Asks the server for the next part.
request_image_part:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    lea rdi, [out_msg]
    mov esi, MSG_GET_IMAGE
    call wr_u8
    mov esi, ebx
    call wr_u32
    mov esi, r12d
    call wr_u32
    call send_built
    add rsp, 8
    pop r12
    pop rbx
    ret

; Starts the next download if none is going: the opened image first, then
; the thumbnails drawn most recently. Called after every frame.
images_pump:
    push rbx
    inc dword [thumb_clock]
    cmp dword [dl_id], 0
    jne .done
    call can_send
    test eax, eax
    jz .done
    cmp dword [view_state], TS_WANTED
    jne .thumbs
    mov edi, [view_id]
    cmp edi, [dl_done]
    je .have_view
    mov dword [view_state], TS_LOADING
    jmp .fetch
.have_view:
    call decode_view
    jmp .done
.thumbs:
    lea rbx, [thumbs]
    mov ecx, THUMB_SLOTS
.slot:
    cmp dword [rbx + TH_STATE], TS_WANTED
    je .thumb
    add rbx, TH_SIZE
    dec ecx
    jnz .slot
    jmp .done
.thumb:
    mov dword [rbx + TH_STATE], TS_LOADING
    mov edi, [rbx + TH_ID]
.fetch:
    mov [dl_id], edi
    xor esi, esi
    mov [dl_got], esi
    mov [dl_bytes], esi
    mov [dl_done], esi
    call request_image_part
.done:
    pop rbx
    ret

; Decodes dl_buf, which holds the opened image, at the size it was opened at.
decode_view:
    sub rsp, 8
    lea rdi, [dl_buf]
    mov esi, [dl_bytes]
    lea rdx, [view_px]
    mov ecx, [view_max_w]
    mov r8d, [view_max_h]
    call png_decode
    mov ecx, TS_FAILED
    test eax, eax
    jz .state
    mov eax, [png_dw]
    mov [view_w], eax
    mov eax, [png_dh]
    mov [view_h], eax
    mov ecx, TS_READY
.state:
    mov [view_state], ecx
    mov byte [need_redraw], 1
    add rsp, 8
    ret

; The download finished, or failed with eax = 0. Whatever was waiting on it
; gets decoded, or marked as failed.
image_fetched:
    push rbx
    push r12
    push r13
    mov r12d, eax
    mov r13d, [dl_id]
    mov dword [dl_id], 0
    test r12d, r12d
    jz .view
    mov [dl_done], r13d
.view:
    cmp [view_id], r13d
    jne .thumbs
    cmp dword [view_state], TS_LOADING
    jne .thumbs
    mov dword [view_state], TS_FAILED
    test r12d, r12d
    jz .thumbs
    call decode_view
.thumbs:
    lea rbx, [thumbs]
    mov ecx, THUMB_SLOTS
.slot:
    cmp [rbx + TH_ID], r13d
    jne .next
    cmp dword [rbx + TH_STATE], TS_LOADING
    jne .next
    mov dword [rbx + TH_STATE], TS_FAILED
    test r12d, r12d
    jz .done
    mov rax, rbx
    call thumb_pixels
    lea rdi, [dl_buf]
    mov esi, [dl_bytes]
    mov rdx, rax
    mov ecx, THUMB_W
    mov r8d, THUMB_H
    call png_decode
    test eax, eax
    jz .done
    mov eax, [png_dw]
    mov [rbx + TH_W], eax
    mov eax, [png_dh]
    mov [rbx + TH_H], eax
    mov dword [rbx + TH_STATE], TS_READY
    jmp .done
.next:
    add rbx, TH_SIZE
    dec ecx
    jnz .slot
.done:
    mov byte [need_redraw], 1
    pop r13
    pop r12
    pop rbx
    jmp images_pump

; MSG_IMAGE: the next part of the image downloading.
on_image:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    call rd_u32
    mov ebx, eax
    call rd_u32
    mov r12d, eax                           ; bytes
    call rd_u32
    mov r13d, eax                           ; offset
    call rd_str16
    mov r14, rax
    cmp byte [rd_bad], 0
    jne .done
    cmp ebx, [dl_id]
    jne .done
    test r12d, r12d                         ; the server can't send it, at any offset
    jz .failed
    cmp r13d, [dl_got]
    jne .done
    test r13d, r13d
    jz .first
    ; Later parts have to agree on the size, or bytes - offset below can wrap.
    cmp r12d, [dl_bytes]
    jne .failed
    jmp .sized
.first:
    cmp r12d, IMAGE_MAX
    ja .failed
    mov [dl_bytes], r12d
.sized:
    mov eax, r12d
    sub eax, r13d
    cmp edx, eax
    ja .failed
    test edx, edx
    jz .failed
    lea rdi, [dl_buf + r13]
    mov rsi, r14
    add [dl_got], edx
    call put_mem
    mov esi, [dl_got]
    cmp esi, [dl_bytes]
    je .whole
    mov edi, ebx
    call request_image_part
    jmp .done
.whole:
    mov eax, 1
    call image_fetched
    jmp .done
.failed:
    xor eax, eax
    call image_fetched
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; The connection went: what was downloading starts over once it's back.
images_offline:
    mov dword [dl_id], 0
    lea rax, [thumbs]
    mov ecx, THUMB_SLOTS
.slot:
    cmp dword [rax + TH_STATE], TS_LOADING
    jne .next
    mov dword [rax + TH_STATE], TS_WANTED
.next:
    add rax, TH_SIZE
    dec ecx
    jnz .slot
    cmp dword [view_state], TS_LOADING
    jne .done
    mov dword [view_state], TS_WANTED
.done:
    ret

; Logging out forgets every image, since the next account may not be allowed them.
images_reset:
    xor eax, eax
    mov [dl_id], eax
    mov [dl_done], eax
    mov [view_id], eax
    mov [view_state], eax
    lea rdi, [thumbs]
    mov ecx, THUMB_SLOTS * TH_SIZE / 4
    rep stosd
    ret

; Puts pixels we already have in as an image's thumbnail, so our own
; upload doesn't come back down. edi = id, rsi = pixels, edx = width, ecx = height
seed_thumb:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    call thumb_slot
    test rax, rax
    jz .done
    mov rbx, rax
    mov [rbx + TH_W], r13d
    mov [rbx + TH_H], r14d
    mov dword [rbx + TH_STATE], TS_READY
    call thumb_pixels
    mov rdi, rax
    mov rsi, r12
    imul edx, r13d, 4
    imul edx, r14d
    call put_mem
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Opens an image as big as the window has room for. edi = image id
open_image_view:
    mov [view_id], edi
    mov dword [view_state], TS_WANTED
    mov eax, [win_w]
    sub eax, VIEW_MARGIN * 2
    mov ecx, VIEW_W
    cmp eax, ecx
    cmova eax, ecx
    mov ecx, 64
    cmp eax, ecx
    cmovl eax, ecx
    mov [view_max_w], eax
    mov eax, [win_h]
    sub eax, VIEW_MARGIN * 2
    mov ecx, VIEW_H
    cmp eax, ecx
    cmova eax, ecx
    mov ecx, 64
    cmp eax, ecx
    cmovl eax, ecx
    mov [view_max_h], eax
    mov byte [modal], M_IMAGE
    mov byte [menu_open], 0
    mov edi, F_NONE
    jmp set_focus

; The opened image over a shade, centered. A click anywhere closes it.
draw_image_view:
    push rbx
    push r12
    sub rsp, 8
    call shade_screen
    xor edi, edi
    xor esi, esi
    mov edx, [win_w]
    mov ecx, [win_h]
    mov r8d, A_DISMISS
    xor r9d, r9d
    call add_hit
    cmp dword [view_state], TS_READY
    je .ready
    lea rcx, [s_image_loading]
    mov r8d, s_image_loading_len
    cmp dword [view_state], TS_FAILED
    jne .word
    lea rcx, [s_image_failed]
    mov r8d, s_image_failed_len
.word:
    xor edi, edi
    mov esi, [win_w]
    mov edx, [win_h]
    shr edx, 1
    mov r9d, INK(C_TEXT, ST_MEDIUM)
    call draw_centered
    jmp .done
.ready:
    mov ebx, [win_w]
    sub ebx, [view_w]
    sar ebx, 1
    mov r12d, [win_h]
    sub r12d, [view_h]
    sar r12d, 1
    lea rdi, [view_px]
    mov esi, [view_w]
    mov edx, [view_h]
    mov ecx, ebx
    mov r8d, r12d
    mov r9d, [view_w]
    call draw_image
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; The room an image ref takes under a message's or comment's text, gap
; included. rdi = ref, esi = column width -> eax = height, 0 for no image
image_ref_height:
    xor eax, eax
    cmp dword [rdi + RI_ID], 0
    je .done
    mov edx, esi
    movzx esi, word [rdi + RI_H]
    movzx edi, word [rdi + RI_W]
    sub rsp, 8
    call thumb_size
    add rsp, 8
    lea eax, [edx + 8]
.done:
    ret

; Draws an image ref under a message's or comment's text.
; rdi = ref, esi = x, edx = the text's bottom, ecx = column width
draw_image_ref:
    cmp dword [rdi + RI_ID], 0
    je .done
    mov r9d, ecx
    lea r8d, [edx + 4]
    mov ecx, esi
    movzx esi, word [rdi + RI_W]
    movzx edx, word [rdi + RI_H]
    mov edi, [rdi + RI_ID]
    jmp draw_attached_image
.done:
    ret
