; zlib's deflate, undone: what a PNG's pixels are packed with (RFC 1950 and
; 1951). The whole output is one buffer, so back-references read straight
; out of it and no separate window is kept.
;
; Each Huffman code gets a 32768-entry table indexed by the next 15 bits of
; input, so a symbol takes one lookup. An entry is the symbol << 4 | its
; code length, and 0 where no code goes, which only a broken stream reaches.

%define INF_TABLE       32768           ; entries, one per 15-bit index
%define INF_MAX_SYMS    320             ; 288 literal/length + 32 distance codes

section .rodata
inf_len_base:   dw 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31
                dw 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
inf_len_extra:  db 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2
                db 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
inf_dist_base:  dw 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193
                dw 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145
                dw 8193, 12289, 16385, 24577
inf_dist_extra: db 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6
                db 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
inf_cl_order:   db 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15

section .bss
alignb 8
inf_in:         resq 1                  ; the next input byte
inf_in_end:     resq 1
inf_bits:       resq 1                  ; input bits not used yet, the next one lowest
inf_count:      resd 1                  ; how many
inf_over:       resd 1                  ; zero bytes fed in past the end of the input
inf_out_base:   resq 1
inf_out:        resq 1
inf_out_end:    resq 1
inf_counts:     resw 16
inf_next:       resw 16
inf_lens:       resb INF_MAX_SYMS
alignb 2
inf_litlen:     resw INF_TABLE
inf_dist:       resw INF_TABLE          ; also the code length code's, while that's read

section .text

; Tops the bit buffer up past 56 bits. Past the end of the input it feeds
; zeros, so a stream can end mid-buffer. Clobbers eax, ecx, rdx.
inf_fill:
    mov ecx, [inf_count]
    mov rdx, [inf_in]
.byte:
    cmp ecx, 56
    ja .done
    xor eax, eax
    cmp rdx, [inf_in_end]
    jae .past
    movzx eax, byte [rdx]
    inc rdx
    jmp .add
.past:
    inc dword [inf_over]
.add:
    shl rax, cl
    or [inf_bits], rax
    add ecx, 8
    jmp .byte
.done:
    mov [inf_count], ecx
    mov [inf_in], rdx
    ret

; ecx = how many bits, up to 16 -> eax = them. Clobbers ecx, rdx.
inf_get:
    push rcx
    call inf_fill
    pop rcx
    mov rax, [inf_bits]
    mov rdx, rax
    shr rdx, cl
    mov [inf_bits], rdx
    sub [inf_count], ecx
    mov edx, 1
    shl edx, cl
    dec edx
    and eax, edx
    ret

; rdi = table -> eax = the next symbol, or -1 for no code. Clobbers ecx, rdx.
inf_decode:
    call inf_fill
    mov rax, [inf_bits]
    and eax, INF_TABLE - 1
    movzx eax, word [rdi + rax * 2]
    mov ecx, eax
    and ecx, 15
    jz .bad
    shr qword [inf_bits], cl
    sub [inf_count], ecx
    shr eax, 4
    ret
.bad:
    mov eax, -1
    ret

; Builds a decoding table from code lengths, the canonical way deflate
; assigns codes. rdi = table, rsi = lengths, edx = how many
; -> eax = 1, or 0 if the lengths ask for more codes than there are
inf_build:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov ebx, edx
    lea rdi, [inf_counts]
    xor eax, eax
    mov ecx, 16
    rep stosw
    xor ecx, ecx
.count:
    cmp ecx, ebx
    jae .counted
    movzx eax, byte [r13 + rcx]
    inc word [inf_counts + rax * 2]
    inc ecx
    jmp .count
.counted:
    mov word [inf_counts], 0
    mov eax, 1                              ; codes still free at this length
    xor edx, edx                            ; the first code of this length
    mov ecx, 1
.length:
    add eax, eax
    movzx r8d, word [inf_counts + rcx * 2]
    sub eax, r8d
    js .bad
    movzx r8d, word [inf_counts + rcx * 2 - 2]
    add edx, r8d
    add edx, edx
    mov [inf_next + rcx * 2], dx
    inc ecx
    cmp ecx, 16
    jb .length
    mov rdi, r12
    xor eax, eax
    mov ecx, INF_TABLE
    rep stosw
    xor r11d, r11d                          ; symbol
.symbol:
    cmp r11d, ebx
    jae .built
    movzx ecx, byte [r13 + r11]             ; its length
    test ecx, ecx
    jz .next
    movzx eax, word [inf_next + rcx * 2]
    inc word [inf_next + rcx * 2]
    xor r9d, r9d                            ; the code, reversed, since deflate sends codes high bit first
    mov r10d, ecx
.reverse:
    shr eax, 1
    adc r9d, r9d
    dec r10d
    jnz .reverse
    mov r10d, 1
    shl r10d, cl                            ; the step between entries for this code
    mov eax, r11d
    shl eax, 4
    or eax, ecx
.fill:
    cmp r9d, INF_TABLE
    jae .next
    mov [r12 + r9 * 2], ax
    add r9d, r10d
    jmp .fill
.next:
    inc r11d
    jmp .symbol
.built:
    mov eax, 1
    jmp .done
.bad:
    xor eax, eax
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Deflate's fixed codes, for a block of type 1. -> eax = 1
inf_fixed:
    sub rsp, 8
    lea rdi, [inf_lens]
    mov al, 8
    mov ecx, 144
    rep stosb
    mov al, 9
    mov ecx, 112
    rep stosb
    mov al, 7
    mov ecx, 24
    rep stosb
    mov al, 8
    mov ecx, 8
    rep stosb
    lea rdi, [inf_litlen]
    lea rsi, [inf_lens]
    mov edx, 288
    call inf_build
    lea rdi, [inf_lens]
    mov al, 5
    mov ecx, 30
    rep stosb
    lea rdi, [inf_dist]
    lea rsi, [inf_lens]
    mov edx, 30
    call inf_build
    add rsp, 8
    ret

; A block of type 2 starts with its codes, themselves Huffman coded.
; -> eax = 1, or 0 if they're broken
inf_dynamic:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ecx, 5
    call inf_get
    lea r12d, [eax + 257]                   ; literal/length codes
    mov ecx, 5
    call inf_get
    lea r13d, [eax + 1]                     ; distance codes
    mov ecx, 4
    call inf_get
    lea r14d, [eax + 4]                     ; code length codes
    cmp r12d, 286
    ja .bad
    lea rdi, [inf_lens]
    xor eax, eax
    mov ecx, 19
    rep stosb
    xor ebx, ebx
.cl:
    cmp ebx, r14d
    jae .cl_read
    mov ecx, 3
    call inf_get
    movzx ecx, byte [inf_cl_order + rbx]
    mov [inf_lens + rcx], al
    inc ebx
    jmp .cl
.cl_read:
    lea rdi, [inf_dist]
    lea rsi, [inf_lens]
    mov edx, 19
    call inf_build
    test eax, eax
    jz .bad
    add r13d, r12d                          ; every length to read
    xor ebx, ebx
.len:
    cmp ebx, r13d
    jae .lens_read
    lea rdi, [inf_dist]
    call inf_decode
    cmp eax, 16
    jb .literal
    ja .zeros
    test ebx, ebx
    jz .bad                                 ; nothing to repeat
    mov ecx, 2
    call inf_get
    lea ecx, [eax + 3]
    movzx eax, byte [inf_lens + rbx - 1]
    jmp .repeat
.zeros:
    cmp eax, 18
    ja .bad
    je .long_zeros
    mov ecx, 3
    call inf_get
    lea ecx, [eax + 3]
    xor eax, eax
    jmp .repeat
.long_zeros:
    mov ecx, 7
    call inf_get
    lea ecx, [eax + 11]
    xor eax, eax
.repeat:
    lea edx, [ebx + ecx]
    cmp edx, r13d
    ja .bad
.again:
    mov [inf_lens + rbx], al
    inc ebx
    dec ecx
    jnz .again
    jmp .len
.literal:
    mov [inf_lens + rbx], al
    inc ebx
    jmp .len
.lens_read:
    cmp byte [inf_lens + 256], 0
    je .bad                                 ; no way to end the block
    lea rdi, [inf_litlen]
    lea rsi, [inf_lens]
    mov edx, r12d
    call inf_build
    test eax, eax
    jz .bad
    sub r13d, r12d
    lea rdi, [inf_dist]
    lea rsi, [inf_lens + r12]
    mov edx, r13d
    call inf_build
    jmp .done
.bad:
    xor eax, eax
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; A block of type 0: its bytes as they are. -> eax = 1, or 0 if broken
inf_stored:
    push rbx
    mov ecx, [inf_count]
    and ecx, 7
    call inf_get                            ; to a byte boundary
    mov ecx, 16
    call inf_get
    mov ebx, eax
    mov ecx, 16
    call inf_get
    not eax
    and eax, 0xffff
    cmp eax, ebx
    jne .bad
    mov rax, [inf_out_end]
    sub rax, [inf_out]
    cmp rbx, rax
    ja .bad
.byte:
    test ebx, ebx
    jz .ok
    mov ecx, 8
    call inf_get
    mov rdx, [inf_out]
    mov [rdx], al
    inc qword [inf_out]
    dec ebx
    jmp .byte
.ok:
    mov eax, 1
    pop rbx
    ret
.bad:
    xor eax, eax
    pop rbx
    ret

; A Huffman-coded block's symbols, up to its end code. -> eax = 1, or 0 if broken
inf_codes:
    push rbx
    push r12
    push r13
    mov r12, [inf_out]
    mov r13, [inf_out_end]
.symbol:
    lea rdi, [inf_litlen]
    call inf_decode
    cmp eax, 256
    ja .copy
    je .ok
    test eax, eax
    js .bad
    cmp r12, r13
    jae .bad
    mov [r12], al
    inc r12
    jmp .symbol
.copy:
    sub eax, 257
    cmp eax, 29
    jae .bad
    mov ebx, eax
    movzx ecx, byte [inf_len_extra + rbx]
    call inf_get
    movzx ebx, word [inf_len_base + rbx * 2]
    add ebx, eax                            ; length
    lea rdi, [inf_dist]
    call inf_decode
    cmp eax, 30
    jae .bad                                ; -1 included
    mov edi, eax
    movzx ecx, byte [inf_dist_extra + rdi]
    call inf_get
    movzx edx, word [inf_dist_base + rdi * 2]
    add eax, edx                            ; distance
    mov rsi, r12
    sub rsi, rax
    cmp rsi, [inf_out_base]
    jb .bad                                 ; before the start
    mov rax, r13
    sub rax, r12
    cmp rbx, rax
    ja .bad
.byte:
    mov al, [rsi]
    mov [r12], al
    inc rsi
    inc r12
    dec ebx
    jnz .byte
    jmp .symbol
.ok:
    mov eax, 1
    jmp .done
.bad:
    xor eax, eax
.done:
    mov [inf_out], r12
    pop r13
    pop r12
    pop rbx
    ret

; Inflates a zlib stream. rdi = out, rsi = room there, rdx = in, rcx = its
; length -> rax = bytes out, or -1 if the stream is broken or doesn't fit
inflate:
    push rbx
    mov [inf_out_base], rdi
    mov [inf_out], rdi
    add rsi, rdi
    mov [inf_out_end], rsi
    add rcx, rdx
    mov [inf_in_end], rcx
    mov [inf_in], rdx
    xor eax, eax
    mov [inf_bits], rax
    mov [inf_count], eax
    mov [inf_over], eax
    mov ecx, 16
    call inf_get
    mov ecx, eax
    and ecx, 0x0f
    cmp ecx, 8
    jne .bad                                ; not deflate
    test eax, 0x2000
    jnz .bad                                ; a preset dictionary, which PNG never has
    xchg al, ah                             ; the header reads big-endian
    xor edx, edx
    mov ecx, 31
    div ecx
    test edx, edx
    jnz .bad
.block:
    mov ecx, 1
    call inf_get
    mov ebx, eax                            ; the last one
    mov ecx, 2
    call inf_get
    test eax, eax
    jz .stored
    cmp eax, 2
    ja .bad
    je .dynamic
    call inf_fixed
    jmp .codes
.dynamic:
    call inf_dynamic
    test eax, eax
    jz .bad
.codes:
    call inf_codes
    jmp .ended
.stored:
    call inf_stored
.ended:
    test eax, eax
    jz .bad
    cmp dword [inf_over], 8
    ja .bad                                 ; ran well past the end of the input
    test ebx, ebx
    jz .block
    mov rax, [inf_out]
    sub rax, [inf_out_base]
    pop rbx
    ret
.bad:
    mov rax, -1
    pop rbx
    ret
