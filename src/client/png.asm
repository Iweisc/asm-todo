; Decoding a PNG straight to the size it's shown at. Rows come out of
; inflate, get unfiltered, turn into 8-bit RGBA, and are averaged down into
; the output a box of source pixels at a time, so a big screenshot shrinks
; without its text turning to noise. The output is premultiplied ARGB, the
; framebuffer's order, ready to blend.
;
; Every color type and bit depth PNG has is read, except interlaced images.
; 16-bit samples keep their high byte, and tRNS only does palette alpha.

%define PNG_ROW_MAX     (IMAGE_SIDE_MAX * 8 + 1)    ; a row of 16-bit RGBA and its filter byte
%define PNG_RAW_MAX     (128 * 1024 * 1024)         ; inflated bytes we'll make room for
%define PNG_OUT_W_MAX   2048                        ; widest output

section .bss
alignb 8
png_w:          resd 1
png_h:          resd 1
png_depth:      resd 1
png_ctype:      resd 1
png_samples:    resd 1                  ; per pixel
png_bpp:        resd 1                  ; bytes per pixel for the filters, at least 1
png_stride:     resd 1                  ; bytes in a row, without its filter byte
png_idat:       resq 1                  ; bytes of compressed data, over every IDAT
png_dw:         resd 1                  ; the output's size
png_dh:         resd 1
png_dy:         resd 1                  ; the output row being summed
png_out:        resq 1                  ; where the next output row goes
png_map:        resq 1                  ; the mmap holding the compressed and inflated bytes
png_map_len:    resq 1
png_palette:    resd 256                ; straight ARGB
png_cols:       resw IMAGE_SIDE_MAX     ; each source column's output column
png_acc:        resd PNG_OUT_W_MAX * 5  ; per output column: a, r, g, b sums and a count
png_rgba:       resd IMAGE_SIDE_MAX     ; one row, straight ARGB
png_zero_row:   resb PNG_ROW_MAX        ; the row above the first

section .text

; Reads the chunks: the header, palette and transparency, and how much
; compressed data there is. rdi = PNG, esi = its length -> eax = 1 if it's one we can decode
png_read:
    push rbx
    push r12
    sub rsp, 8
    xor eax, eax
    cmp esi, 33                             ; signature and IHDR
    jb .done
    mov rcx, 0x0a1a0a0d474e5089
    cmp [rdi], rcx
    jne .done
    lea r12, [rdi + rsi]                    ; the end
    lea rbx, [rdi + 8]
    mov qword [png_idat], 0
    mov dword [png_w], 0
    lea rdi, [png_palette]
    mov eax, 0xff000000
    mov ecx, 256
    rep stosd
.chunk:
    mov rax, r12
    sub rax, rbx
    cmp rax, 12
    jb .bad
    mov ecx, [rbx]
    bswap ecx                               ; its length
    sub rax, 12
    cmp rcx, rax
    ja .bad
    mov eax, [rbx + 4]
    lea rsi, [rbx + 8]                      ; its data
    lea rbx, [rsi + rcx + 4]                ; the next, past the CRC
    cmp eax, 'IHDR'
    je .ihdr
    cmp dword [png_w], 0
    je .bad                                 ; IHDR comes first
    cmp eax, 'PLTE'
    je .plte
    cmp eax, 'tRNS'
    je .trns
    cmp eax, 'IDAT'
    je .idat
    cmp eax, 'IEND'
    jne .chunk
    cmp qword [png_idat], 0
    setne al
    movzx eax, al
    jmp .done
.ihdr:
    cmp dword [png_w], 0
    jne .bad                                ; a second one would change the size under the server's check
    cmp ecx, 13
    jne .bad
    mov rdi, rsi
    call png_header
    test eax, eax
    jz .bad
    jmp .chunk
.plte:
    xor edx, edx
.color:
    cmp ecx, 3
    jb .chunk
    cmp edx, 256
    jae .chunk
    movzx eax, byte [rsi]
    shl eax, 16
    mov ah, [rsi + 1]
    mov al, [rsi + 2]
    or eax, 0xff000000
    mov [png_palette + rdx * 4], eax
    add rsi, 3
    sub ecx, 3
    inc edx
    jmp .color
.trns:
    cmp dword [png_ctype], 3
    jne .chunk
    xor edx, edx
.alpha:
    cmp edx, ecx
    jae .chunk
    cmp edx, 256
    jae .chunk
    mov al, [rsi + rdx]
    mov [png_palette + rdx * 4 + 3], al
    inc edx
    jmp .alpha
.idat:
    add [png_idat], rcx
    jmp .chunk
.bad:
    xor eax, eax
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; rdi = IHDR's 13 bytes -> eax = 1 if we can decode an image like it
png_header:
    xor eax, eax
    mov ecx, [rdi]
    bswap ecx
    mov edx, [rdi + 4]
    bswap edx
    lea r8d, [ecx - 1]
    cmp r8d, IMAGE_SIDE_MAX
    jae .done
    lea r8d, [edx - 1]
    cmp r8d, IMAGE_SIDE_MAX
    jae .done
    mov r8d, ecx
    imul r8d, edx
    cmp r8d, IMAGE_PIXELS_MAX
    ja .done
    mov [png_w], ecx
    mov [png_h], edx
    movzx ecx, byte [rdi + 8]
    mov [png_depth], ecx
    movzx edx, byte [rdi + 9]
    mov [png_ctype], edx
    cmp word [rdi + 10], 0                  ; compression and filter method
    jne .done
    cmp byte [rdi + 12], 0
    jne .done                               ; interlaced
    ; Samples per pixel by color type, 0 where the type doesn't exist.
    cmp edx, 6
    ja .done
    movzx r8d, byte [.samples + rdx]
    test r8d, r8d
    jz .done
    mov [png_samples], r8d
    ; The depths each type allows: 1, 2, 4 and 8 for gray and palette, 8
    ; and 16 for the rest, and 16 for gray too.
    cmp ecx, 16
    je .sixteen
    cmp ecx, 8
    je .depth_ok
    cmp edx, 0
    je .low
    cmp edx, 3
    jne .done
.low:
    cmp ecx, 1
    je .depth_ok
    cmp ecx, 2
    je .depth_ok
    cmp ecx, 4
    je .depth_ok
    jmp .done
.sixteen:
    cmp edx, 3
    je .done
.depth_ok:
    imul r8d, ecx                           ; bits per pixel
    lea eax, [r8d + 7]
    shr eax, 3
    mov [png_bpp], eax
    mov eax, [png_w]
    imul rax, r8
    add rax, 7
    shr rax, 3
    mov [png_stride], eax
    mov eax, 1
.done:
    ret
.samples: db 1, 0, 3, 1, 2, 0, 4

; Fits a size inside a box without making it bigger.
; edi = width, esi = height, edx = max width, ecx = max height -> eax = width, edx = height
fit_box:
    cmp edi, edx
    ja .shrink
    cmp esi, ecx
    ja .shrink
    mov eax, edi
    mov edx, esi
    ret
.shrink:
    push rbx
    mov r8d, edx
    mov r9d, ecx
    ; Whichever side is the tighter fit sets the scale: w * max_h against h * max_w.
    mov eax, edi
    imul rax, r9
    mov r10d, esi
    imul r10, r8
    cmp rax, r10
    jbe .tall
    mov eax, esi
    imul rax, r8
    xor edx, edx
    mov ebx, edi
    div rbx
    mov edx, eax                            ; height
    mov eax, r8d
    jmp .done
.tall:
    mov eax, edi
    imul rax, r9
    xor edx, edx
    mov ebx, esi
    div rbx                                 ; width
    mov edx, r9d
.done:
    mov ecx, 1
    cmp eax, ecx
    cmovb eax, ecx
    cmp edx, ecx
    cmovb edx, ecx
    pop rbx
    ret

; Fits the image inside a box. edi = max width, esi = max height. Sets png_dw and png_dh.
png_fit:
    sub rsp, 8
    mov edx, edi
    mov ecx, esi
    mov edi, [png_w]
    mov esi, [png_h]
    call fit_box
    mov [png_dw], eax
    mov [png_dh], edx
    add rsp, 8
    ret

; Undoes one row's filter in place. rdi = the row's filter byte, then its
; bytes, rsi = the row above, already unfiltered -> eax = 1, or 0 for no such filter
png_unfilter:
    push rbx
    push r12
    push r13
    movzx eax, byte [rdi]
    inc rdi
    mov ecx, [png_stride]
    mov r8d, [png_bpp]
    xor edx, edx                            ; byte index
    cmp eax, 4
    ja .bad
    jmp [.filters + rax * 8]
.sub:
    cmp edx, ecx
    jae .ok
    cmp edx, r8d
    jb .sub_next
    mov rax, rdx
    sub rax, r8
    mov al, [rdi + rax]
    add [rdi + rdx], al
.sub_next:
    inc edx
    jmp .sub
.up:
    cmp edx, ecx
    jae .ok
    mov al, [rsi + rdx]
    add [rdi + rdx], al
    inc edx
    jmp .up
.average:
    cmp edx, ecx
    jae .ok
    movzx eax, byte [rsi + rdx]             ; above
    cmp edx, r8d
    jb .half
    mov r9, rdx
    sub r9, r8
    movzx r9d, byte [rdi + r9]              ; left
    add eax, r9d
.half:
    shr eax, 1
    add [rdi + rdx], al
    inc edx
    jmp .average
.paeth:
    cmp edx, ecx
    jae .ok
    movzx r10d, byte [rsi + rdx]            ; b, above
    xor r9d, r9d                            ; a, left
    xor r11d, r11d                          ; c, above left
    cmp edx, r8d
    jb .predict
    mov rax, rdx
    sub rax, r8
    movzx r9d, byte [rdi + rax]
    movzx r11d, byte [rsi + rax]
.predict:
    ; p = a + b - c, then whichever of a, b, c is closest to it, in that order on ties.
    mov eax, r10d
    sub eax, r11d                           ; p - a
    mov ebx, eax
    neg ebx
    cmovl ebx, eax                          ; pa
    mov eax, r9d
    sub eax, r11d                           ; p - b
    mov r12d, eax
    neg r12d
    cmovl r12d, eax                         ; pb
    mov eax, r9d
    add eax, r10d
    sub eax, r11d
    sub eax, r11d                           ; p - c
    mov r13d, eax
    neg r13d
    cmovl r13d, eax                         ; pc
    mov eax, r9d
    cmp ebx, r12d
    ja .not_a
    cmp ebx, r13d
    jbe .add
.not_a:
    mov eax, r10d
    cmp r12d, r13d
    jbe .add
    mov eax, r11d
.add:
    add [rdi + rdx], al
    inc edx
    jmp .paeth
.none:
.ok:
    mov eax, 1
    jmp .done
.bad:
    xor eax, eax
.done:
    pop r13
    pop r12
    pop rbx
    ret
align 8
.filters: dq .none, .sub, .up, .average, .paeth

; Sample number esi of an unfiltered row, as 0-255. Palette indexes come
; back as they are. rdi = the row's bytes
png_sample:
    mov ecx, [png_depth]
    cmp ecx, 8
    jne .not_8
    movzx eax, byte [rdi + rsi]
    ret
.not_8:
    cmp ecx, 16
    jne .packed
    movzx eax, byte [rdi + rsi * 2]         ; the high byte
    ret
.packed:
    ; 1, 2 or 4 bits, the first sample in a byte's high bits.
    push rbx
    mov ebx, ecx
    mov eax, esi
    imul eax, ebx                           ; its first bit
    mov edx, eax
    shr edx, 3
    movzx edx, byte [rdi + rdx]
    and eax, 7
    add eax, ebx
    mov ecx, 8
    sub ecx, eax
    shr edx, cl                             ; down to the byte's low bits
    mov ecx, ebx
    mov eax, 1
    shl eax, cl
    dec eax                                 ; the biggest value
    and edx, eax
    cmp dword [png_ctype], 3
    je .index
    mov ecx, eax                            ; gray, stretched to 0-255
    imul eax, edx, 255
    xor edx, edx
    div ecx
    pop rbx
    ret
.index:
    mov eax, edx
    pop rbx
    ret

; An unfiltered row into png_rgba as straight ARGB. rdi = the row's bytes
png_expand:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rdi
    xor ebx, ebx                            ; pixel
.pixel:
    cmp ebx, [png_w]
    jae .done
    mov r13d, ebx
    imul r13d, [png_samples]                ; its first sample
    mov rdi, r12
    mov esi, r13d
    call png_sample
    mov ecx, [png_ctype]
    cmp ecx, 3
    je .indexed
    cmp ecx, 2
    je .color
    cmp ecx, 6
    je .color
    imul r14d, eax, 0x010101                ; gray, and gray with alpha
    or r14d, 0xff000000
    cmp ecx, 4
    jne .store
    mov esi, 1
    jmp .alpha
.indexed:
    mov r14d, [png_palette + rax * 4]
    jmp .store
.color:
    shl eax, 16
    or eax, 0xff000000
    mov r14d, eax
    lea esi, [r13d + 1]
    mov rdi, r12
    call png_sample
    shl eax, 8
    or r14d, eax
    lea esi, [r13d + 2]
    mov rdi, r12
    call png_sample
    or r14d, eax
    cmp dword [png_ctype], 6
    jne .store
    mov esi, 3
.alpha:
    add esi, r13d
    mov rdi, r12
    call png_sample
    shl eax, 24
    and r14d, 0xffffff
    or r14d, eax
.store:
    mov [png_rgba + rbx * 4], r14d
    inc ebx
    jmp .pixel
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; edx = a color channel, ecx = alpha -> edx = the channel times alpha, over 255, rounded
png_premultiply:
    imul edx, ecx
    add edx, 128
    mov eax, edx
    shr eax, 8
    add edx, eax
    shr edx, 8
    ret

; Adds png_rgba into the output row it belongs to, writing out the row
; before first when this is the first source row of the next.
; edi = source row
png_scale_row:
    push rbx
    push r12
    sub rsp, 8
    mov eax, edi
    mov ecx, [png_dh]
    imul rax, rcx
    xor edx, edx
    mov ecx, [png_h]
    div rcx
    cmp eax, [png_dy]
    je .add
    mov ebx, eax
    call png_flush_row
    mov [png_dy], ebx
.add:
    xor ebx, ebx
.pixel:
    cmp ebx, [png_w]
    jae .done
    movzx eax, word [png_cols + rbx * 2]
    lea rax, [rax + rax * 4]
    lea r12, [png_acc + rax * 4]
    mov eax, [png_rgba + rbx * 4]
    mov ecx, eax
    shr ecx, 24
    add [r12], ecx
    mov edx, eax
    shr edx, 16
    and edx, 0xff
    mov r8d, eax
    call png_premultiply
    add [r12 + 4], edx
    movzx edx, r8b
    shr r8d, 8
    movzx eax, r8b
    mov r8d, edx                            ; blue, for after green
    mov edx, eax
    call png_premultiply
    add [r12 + 8], edx
    mov edx, r8d
    call png_premultiply
    add [r12 + 12], edx
    inc dword [r12 + 16]
    inc ebx
    jmp .pixel
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; Writes out the output row being summed as the averages, and clears the sums.
png_flush_row:
    push rbx
    push r12
    mov rdi, [png_out]
    xor ebx, ebx
.pixel:
    cmp ebx, [png_dw]
    jae .done
    lea rax, [rbx + rbx * 4]
    lea rsi, [png_acc + rax * 4]
    mov ecx, [rsi + 16]                     ; how many pixels went in
    xor r12d, r12d
    test ecx, ecx
    jz .store
    xor r8d, r8d                            ; channel offset
.channel:
    mov eax, ecx
    shr eax, 1
    add eax, [rsi + r8]
    xor edx, edx
    div ecx
    shl r12d, 8
    or r12d, eax
    mov dword [rsi + r8], 0
    add r8d, 4
    cmp r8d, 16
    jb .channel
    mov dword [rsi + 16], 0
.store:
    mov [rdi + rbx * 4], r12d
    inc ebx
    jmp .pixel
.done:
    mov eax, [png_dw]
    lea rdi, [rdi + rax * 4]
    mov [png_out], rdi
    pop r12
    pop rbx
    ret

; Copies every IDAT's data, one after another. png_read has checked the
; chunks are all there. rdi = PNG, rsi = where to
png_gather:
    lea rdx, [rdi + 8]
.chunk:
    mov ecx, [rdx]
    bswap ecx
    mov eax, [rdx + 4]
    cmp eax, 'IEND'
    je .done
    cmp eax, 'IDAT'
    jne .next
    push rsi
    push rdi
    lea r8, [rdx + 8]
    mov rdi, rsi
    mov rsi, r8
    push rcx
    rep movsb
    pop rcx
    pop rdi
    pop rsi
    add rsi, rcx
.next:
    lea rdx, [rdx + rcx + 12]
    jmp .chunk
.done:
    ret

; Decodes a PNG, fitted inside a box. rdi = PNG, esi = its length, rdx = out,
; room for max width * max height pixels, ecx = max width, r8d = max height
; -> eax = 1 with png_dw and png_dh its size, or 0 if it can't be decoded
png_decode:
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
    mov ebx, PNG_OUT_W_MAX
    cmp ecx, ebx
    cmovb ebx, ecx
    mov ebp, r8d
    call png_read
    test eax, eax
    jz .bad
    mov edi, ebx
    mov esi, ebp
    call png_fit
    mov eax, [png_stride]
    inc rax
    mov ecx, [png_h]
    imul rax, rcx
    cmp rax, PNG_RAW_MAX
    ja .bad
    mov r15, rax                            ; inflated bytes
    add rax, [png_idat]
    mov [png_map_len], rax
    mov eax, SYS_mmap
    xor edi, edi
    mov rsi, [png_map_len]
    mov edx, PROT_RW
    mov r10d, MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    syscall
    cmp rax, -4096
    ja .bad
    mov [png_map], rax
    mov rdi, r12
    mov rsi, rax
    call png_gather
    mov rdx, [png_map]
    mov rdi, rdx
    add rdi, [png_idat]
    mov rsi, r15
    mov rcx, [png_idat]
    call inflate
    cmp rax, r15
    jne .unmap
    xor ecx, ecx
.column:
    cmp ecx, [png_w]
    jae .columns
    mov eax, ecx
    mov edx, [png_dw]
    imul rax, rdx
    xor edx, edx
    mov r8d, [png_w]
    div r8
    mov [png_cols + rcx * 2], ax
    inc ecx
    jmp .column
.columns:
    lea rdi, [png_acc]
    xor eax, eax
    mov ecx, PNG_OUT_W_MAX * 5
    rep stosd
    mov dword [png_dy], 0
    mov [png_out], r14
    lea rbp, [png_zero_row + 1]             ; the row above
    mov r15, [png_map]
    add r15, [png_idat]                     ; this row's filter byte
    xor ebx, ebx
.row:
    cmp ebx, [png_h]
    jae .rows
    mov rdi, r15
    mov rsi, rbp
    call png_unfilter
    test eax, eax
    jz .unmap
    lea rdi, [r15 + 1]
    call png_expand
    mov edi, ebx
    call png_scale_row
    lea rbp, [r15 + 1]
    mov eax, [png_stride]
    lea r15, [r15 + rax + 1]
    inc ebx
    jmp .row
.rows:
    call png_flush_row
    mov r12d, 1
    jmp .free
.unmap:
    xor r12d, r12d
.free:
    mov eax, SYS_munmap
    mov rdi, [png_map]
    mov rsi, [png_map_len]
    syscall
    mov eax, r12d
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
