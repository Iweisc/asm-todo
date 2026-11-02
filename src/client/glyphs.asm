; Line icons for buttons and the sidebar, in the same 14px box and quarter
; pixel units as icons.asm. Each is a list of strokes, ended by GS_END.

%define GS_END          0
%define GS_LINE         1               ; n, then n points
%define GS_RING         2               ; cx, cy, r
%define GS_DISC         3               ; cx, cy, r
%define GS_HALF         4               ; cx, cy, r: the right half of a disc
%define GS_DASHED       5               ; cx, cy, r

section .rodata
align 4
line_icons:     dq g_send, g_image, g_settings, g_person, g_issues, g_active, g_backlog, g_hash
                dq g_plus, g_bars, g_tag, g_cube, g_copy, g_trash, g_grid, g_list
                dq g_funnel, g_cross, g_lock, g_logout

g_send:         dd GS_LINE, 2, 28, 46, 28, 12
                dd GS_LINE, 3, 14, 25, 28, 11, 42, 25
                dd GS_END
g_image:        dd GS_LINE, 5, 6, 10, 50, 10, 50, 46, 6, 46, 6, 10
                dd GS_LINE, 5, 7, 41, 20, 28, 31, 38, 37, 32, 49, 43
                dd GS_RING, 37, 21, 5
                dd GS_END
g_settings:     dd GS_LINE, 2, 6, 17, 50, 17
                dd GS_LINE, 2, 6, 39, 50, 39
                dd GS_DISC, 36, 17, 8
                dd GS_DISC, 20, 39, 8
                dd GS_END
g_person:       dd GS_RING, 28, 18, 9
                dd GS_LINE, 7, 10, 50, 12, 43, 18, 37, 28, 35, 38, 37, 44, 43, 46, 50
                dd GS_END
g_issues:       dd GS_LINE, 5, 8, 8, 48, 8, 48, 48, 8, 48, 8, 8
                dd GS_LINE, 2, 18, 22, 38, 22
                dd GS_LINE, 2, 18, 34, 32, 34
                dd GS_END
g_active:       dd GS_RING, 28, 28, 21
                dd GS_HALF, 28, 28, 11
                dd GS_END
g_backlog:      dd GS_DASHED, 28, 28, 21
                dd GS_END
g_hash:         dd GS_LINE, 2, 22, 8, 18, 48
                dd GS_LINE, 2, 38, 8, 34, 48
                dd GS_LINE, 2, 10, 21, 48, 21
                dd GS_LINE, 2, 8, 35, 46, 35
                dd GS_END
g_plus:         dd GS_LINE, 2, 28, 8, 28, 48
                dd GS_LINE, 2, 8, 28, 48, 28
                dd GS_END
g_bars:         dd GS_LINE, 2, 12, 46, 12, 34
                dd GS_LINE, 2, 28, 46, 28, 22
                dd GS_LINE, 2, 44, 46, 44, 10
                dd GS_END
g_tag:          dd GS_LINE, 6, 8, 8, 28, 8, 50, 30, 30, 50, 8, 28, 8, 8
                dd GS_RING, 19, 19, 3
                dd GS_END
g_cube:         dd GS_LINE, 7, 28, 6, 48, 17, 48, 39, 28, 50, 8, 39, 8, 17, 28, 6
                dd GS_LINE, 3, 8, 17, 28, 28, 48, 17
                dd GS_LINE, 2, 28, 28, 28, 50
                dd GS_END
g_copy:         dd GS_LINE, 5, 6, 16, 40, 16, 40, 50, 6, 50, 6, 16
                dd GS_LINE, 5, 16, 16, 16, 6, 50, 6, 50, 40, 40, 40
                dd GS_END
g_trash:        dd GS_LINE, 2, 6, 13, 50, 13
                dd GS_LINE, 4, 20, 13, 20, 6, 36, 6, 36, 13
                dd GS_LINE, 4, 11, 13, 14, 50, 42, 50, 45, 13
                dd GS_END
g_grid:         dd GS_LINE, 5, 6, 8, 50, 8, 50, 48, 6, 48, 6, 8
                dd GS_LINE, 2, 21, 8, 21, 48
                dd GS_LINE, 2, 35, 8, 35, 48
                dd GS_END
g_list:         dd GS_LINE, 2, 8, 12, 48, 12
                dd GS_LINE, 2, 8, 28, 48, 28
                dd GS_LINE, 2, 8, 44, 48, 44
                dd GS_END
g_funnel:       dd GS_LINE, 7, 6, 8, 50, 8, 32, 28, 32, 48, 24, 43, 24, 28, 6, 8
                dd GS_END
g_cross:        dd GS_LINE, 2, 14, 14, 42, 42
                dd GS_LINE, 2, 42, 14, 14, 42
                dd GS_END
g_lock:         dd GS_LINE, 5, 10, 24, 46, 24, 46, 50, 10, 50, 10, 24
                dd GS_LINE, 7, 18, 24, 18, 16, 22, 9, 28, 7, 34, 9, 38, 16, 38, 24
                dd GS_END
g_logout:       dd GS_LINE, 4, 30, 8, 10, 8, 10, 48, 30, 48
                dd GS_LINE, 2, 22, 28, 50, 28
                dd GS_LINE, 3, 42, 20, 50, 28, 42, 36
                dd GS_END

section .text

; edi = GL_*, esi = x, edx = y (the box's top left), ecx = color
draw_glyph:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, [line_icons + rdi * 8]
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
.stroke:
    mov eax, [rbx]
    cmp eax, GS_LINE
    je .line
    cmp eax, GS_END
    je .done
    lea edi, [r12d * 4]
    add edi, [rbx + 4]
    lea esi, [r13d * 4]
    add esi, [rbx + 8]
    mov edx, [rbx + 12]
    mov ecx, r14d
    mov r8d, 6
    add rbx, 16
    cmp eax, GS_RING
    je .ring
    cmp eax, GS_DISC
    je .disc
    cmp eax, GS_HALF
    je .half
    call aa_dashed_ring
    jmp .stroke
.ring:
    call aa_ring
    jmp .stroke
.disc:
    call aa_disc
    jmp .stroke
.half:
    call aa_half_disc
    jmp .stroke
.line:
    lea rdi, [rbx + 8]
    mov esi, [rbx + 4]
    lea rbx, [rdi + rsi * 8]
    mov edx, r12d
    mov ecx, r13d
    mov r8d, r14d
    mov r9d, 6
    call aa_polyline
    jmp .stroke
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
