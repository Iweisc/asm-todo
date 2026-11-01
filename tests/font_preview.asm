; font-preview: renders every text style and icon to a PPM on stdout, for
; eyeballing glyph shapes and spacing without starting the app.
;
;   font-preview > preview.ppm

default rel
bits 64

%include "sys.inc"
%include "config.inc"
%include "macros.inc"

%define PW  960
%define PH  560
%define BG  0x191a1f
%define FG  0xe3e4e6
%define DIM 0x8a8f98

section .text
global _start

%include "util.asm"
%include "font.asm"
%include "draw.asm"
%include "text.asm"
%include "icons.asm"

section .rodata
text s_pangram, "The quick brown fox jumps over the lazy dog. 0123456789"
text s_upper, "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz"
text s_punct, "!", 34, "#$%&'()*+,-./:;<=>?@[\]^_`{|}~ ", 127, " ", 128, " ", 129
text s_issue, "ENG-142  Fix login redirect when the session expires"
text s_title, "Board view with drag between columns"
text s_large, "Engineering"
text s_meta, "Backlog  Todo  In Progress  Done  Canceled   Nov 1"
text s_fit, "This title is far too long to fit inside the box it was given"
ppm_header: db "P6", 10, "960 560", 10, "255", 10
ppm_header_len equ $ - ppm_header
s_name: db "lewis"

section .bss
pixels: resd PW * PH
out:    resb PW * PH * 3

section .text

%macro SAMPLE 4                         ; x, baseline, ink, text
    mov edi, %1
    mov esi, %2
    lea rdx, [%4]
    mov ecx, %4_len
    mov r8d, %3
    call draw_text
%endmacro

_start:
    lea rax, [pixels]
    mov [fb], rax
    mov dword [fb_w], PW
    mov dword [fb_h], PH
    call reset_clip
    call text_init
    xor edi, edi
    xor esi, esi
    mov edx, PW
    mov ecx, PH
    mov r8d, BG
    call fill_rect

    SAMPLE 20, 40, INK(FG, ST_SMALL), s_pangram
    SAMPLE 20, 64, INK(FG, ST_BODY), s_pangram
    SAMPLE 20, 88, INK(FG, ST_MEDIUM), s_pangram
    SAMPLE 20, 124, INK(FG, ST_TITLE), s_pangram
    SAMPLE 20, 168, INK(FG, ST_LARGE), s_large
    SAMPLE 20, 200, INK(FG, ST_BODY), s_upper
    SAMPLE 20, 224, INK(FG, ST_MEDIUM), s_upper
    SAMPLE 20, 248, INK(FG, ST_BODY), s_punct
    SAMPLE 20, 272, INK(DIM, ST_SMALL), s_meta
    SAMPLE 20, 296, INK(FG, ST_BODY), s_issue
    SAMPLE 20, 334, INK(FG, ST_TITLE), s_title

    mov edi, 20                             ; ellipsis cut at 300px
    mov esi, 362
    lea rdx, [s_fit]
    mov ecx, s_fit_len
    mov r8d, INK(FG, ST_BODY)
    mov r9d, 300
    call draw_text_fit
    mov edi, 20
    mov esi, 366
    mov edx, 300
    mov ecx, 1
    mov r8d, 0x3b3d45
    call fill_rect

    xor ebx, ebx                            ; status icons
.status:
    imul edi, ebx, 24
    add edi, 20
    mov esi, 390
    mov edx, ebx
    mov ecx, BG
    call draw_status_icon
    inc ebx
    cmp ebx, STATUS_COUNT
    jb .status
    xor ebx, ebx
.priority:
    imul edi, ebx, 24
    add edi, 160
    mov esi, 390
    mov edx, ebx
    mov ecx, FG
    mov r8d, 0x4a4c54
    mov r9d, BG
    call draw_priority_icon
    inc ebx
    cmp ebx, PRIO_COUNT
    jb .priority
    xor ebx, ebx
.avatar:
    imul edi, ebx, 26
    add edi, 300
    mov esi, 388
    mov edx, 18
    mov ecx, ebx
    lea r8, [s_name]
    call draw_avatar
    inc ebx
    cmp ebx, 8
    jb .avatar

    mov edi, 20                             ; a chip, a button and an input
    mov esi, 420
    mov edx, 90
    mov ecx, 24
    mov r8d, 0x2a2c33
    mov r9d, 6
    call fill_rrect
    mov edi, 130
    mov esi, 420
    mov edx, 110
    mov ecx, 28
    mov r8d, 0x5e6ad2
    mov r9d, 6
    call fill_rrect
    mov edi, 260
    mov esi, 420
    mov edx, 220
    mov ecx, 30
    mov r8d, 0x3b3d45
    mov r9d, 0x1f2026
    mov r10d, 6
    call outline_rrect
    SAMPLE 30, 436, INK(FG, ST_SMALL), s_meta
    mov edi, 20                             ; the clip should cut this one off at x = 500
    mov esi, 480
    mov edx, 500
    mov ecx, 540
    call set_clip
    SAMPLE 400, 510, INK(FG, ST_TITLE), s_title
    call reset_clip

    lea rsi, [pixels]                       ; XRGB to packed RGB
    lea rdi, [out]
    mov ecx, PW * PH
.convert:
    mov eax, [rsi]
    mov edx, eax
    shr edx, 16
    mov [rdi], dl
    mov [rdi + 1], ah
    mov [rdi + 2], al
    add rsi, 4
    add rdi, 3
    dec ecx
    jnz .convert
    mov edi, 1
    lea rsi, [ppm_header]
    mov edx, ppm_header_len
    call write_all
    mov edi, 1
    lea rsi, [out]
    mov edx, PW * PH * 3
    call write_all
    xor edi, edi
    call exit
