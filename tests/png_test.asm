; png-test: decodes the PNGs tests/images/make_images.py wrote and checks
; each comes out as the pixels it wrote beside it, or is refused when it
; wrote none. Exits 1 on any failure.

default rel
bits 64

%include "sys.inc"
%include "config.inc"
%include "macros.inc"

section .text
global _start

%include "util.asm"
%include "inflate.asm"
%include "png.asm"

; A PNG, the pixels it decodes to, and the box it's fitted in.
%macro png_case 3                       ; name, max width, max height
section .rodata
%%png:  incbin %str(tests/images/%1.png)
%%png_len equ $ - %%png
%%argb: incbin %str(tests/images/%1.argb)
%%argb_len equ $ - %%argb
%%name: db %str(%1), " decodes to the right pixels, or is refused", 10, 0
section .data
    dq %%png, %%png_len, %%argb, %%argb_len, %%name
    dd %2, %3
%endmacro

section .data
align 8
png_cases:
png_case rgb8, 64, 64
png_case rgba8, 64, 64
png_case ga16, 64, 64
png_case gray1, 64, 64
png_case pal4, 64, 64
png_case shrink, 2, 2
png_case two_ihdr, 64, 64
section .data
    dq 0

section .rodata
s_ok:           db "ok    ", 0
s_fail:         db "FAIL  ", 0

section .bss
failures:       resd 1
out:            resd 64 * 64

section .text

_start:
    lea rbx, [png_cases]
.case:
    cmp qword [rbx], 0
    je .done
    mov rdi, [rbx]
    mov esi, [rbx + 8]
    lea rdx, [out]
    mov ecx, [rbx + 40]
    mov r8d, [rbx + 44]
    call png_decode
    xor r12d, r12d
    cmp qword [rbx + 24], 0
    jne .decodes
    test eax, eax
    setz r12b
    jmp .checked
.decodes:
    test eax, eax
    jz .checked
    mov eax, [png_dw]
    imul eax, [png_dh]
    shl eax, 2
    cmp eax, [rbx + 24]
    jne .checked
    lea rdi, [out]
    mov rsi, [rbx + 16]
    mov edx, eax
    call mem_eq
    mov r12d, eax
.checked:
    lea rdi, [s_ok]
    test r12d, r12d
    jnz .say
    inc dword [failures]
    lea rdi, [s_fail]
.say:
    call print
    mov rdi, [rbx + 32]
    call print
    add rbx, 48
    jmp .case
.done:
    xor edi, edi
    cmp dword [failures], 0
    setne dil
    call exit

; rdi = NUL-terminated text, to stdout
print:
    push rbx
    mov rbx, rdi
    call strlen
    mov rdx, rax
    mov rsi, rbx
    mov edi, 1
    call write_all
    pop rbx
    ret
