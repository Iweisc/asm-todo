; X25519 (RFC 7748).
;
; Field elements are 4 little-endian 64-bit limbs holding any value below
; 2^256 that's congruent to the real one mod p = 2^255 - 19. Only fe_freeze
; produces the canonical form. Reduction leans on 2^256 = 38 (mod p).
;
; Nothing here branches on or indexes memory by secret data. The ladder
; swaps with masks, and inversion uses the public exponent p - 2.

section .rodata
x25519_basepoint:
    db 9
    times 31 db 0

section .text

; rdi = out, rsi = a, rdx = b
fe_add:
    mov rax, [rsi]
    mov rcx, [rsi + 8]
    mov r8, [rsi + 16]
    mov r9, [rsi + 24]
    add rax, [rdx]
    adc rcx, [rdx + 8]
    adc r8, [rdx + 16]
    adc r9, [rdx + 24]
    sbb r10, r10
    and r10, 38
    add rax, r10
    adc rcx, 0
    adc r8, 0
    adc r9, 0
    sbb r10, r10                            ; a second wrap leaves a tiny value, so this can't carry
    and r10, 38
    add rax, r10
    mov [rdi], rax
    mov [rdi + 8], rcx
    mov [rdi + 16], r8
    mov [rdi + 24], r9
    ret

; rdi = out, rsi = a, rdx = b
fe_sub:
    mov rax, [rsi]
    mov rcx, [rsi + 8]
    mov r8, [rsi + 16]
    mov r9, [rsi + 24]
    sub rax, [rdx]
    sbb rcx, [rdx + 8]
    sbb r8, [rdx + 16]
    sbb r9, [rdx + 24]
    sbb r10, r10
    and r10, 38
    sub rax, r10
    sbb rcx, 0
    sbb r8, 0
    sbb r9, 0
    sbb r10, r10
    and r10, 38
    sub rax, r10
    mov [rdi], rax
    mov [rdi + 8], rcx
    mov [rdi + 16], r8
    mov [rdi + 24], r9
    ret

; out = a * b. out may alias either input.
; rdi = out, rsi = a, rdx = b
fe_mul:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 64                             ; 512-bit product t[0..7]
    mov rcx, rdx
    xor eax, eax
    mov [rsp], rax
    mov [rsp + 8], rax
    mov [rsp + 16], rax
    mov [rsp + 24], rax

    ; Schoolbook, one row per limb of a. Row i adds a[i]*b into t[i..i+3]
    ; and leaves its carry in t[i+4].
%assign i 0
%rep 4
    mov r8, [rsi + 8 * i]
    xor ebx, ebx
  %assign j 0
  %rep 4
    mov rax, [rcx + 8 * j]
    mul r8
    add rax, rbx
    adc rdx, 0
    add rax, [rsp + 8 * (i + j)]
    adc rdx, 0
    mov [rsp + 8 * (i + j)], rax
    mov rbx, rdx
    %assign j j + 1
  %endrep
    mov [rsp + 8 * (i + 4)], rbx
  %assign i i + 1
%endrep

    ; r = t[0..3] + 38 * t[4..7]
    mov r8d, 38
    xor ebx, ebx
%assign i 0
%rep 4
    mov rax, [rsp + 8 * (4 + i)]
    mul r8
    add rax, rbx
    adc rdx, 0
    add rax, [rsp + 8 * i]
    adc rdx, 0
    mov [rsp + 8 * i], rax
    mov rbx, rdx
  %assign i i + 1
%endrep
    mov r12, [rsp]
    mov r13, [rsp + 8]
    mov r14, [rsp + 16]
    mov r15, [rsp + 24]
    imul rbx, rbx, 38                       ; whatever spilled past 2^256
    add r12, rbx
    adc r13, 0
    adc r14, 0
    adc r15, 0
    sbb rax, rax                            ; a wrap here leaves a tiny value, adding 38 can't carry
    and rax, 38
    add r12, rax
    mov [rdi], r12
    mov [rdi + 8], r13
    mov [rdi + 16], r14
    mov [rdi + 24], r15
    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi = out, rsi = a
fe_sq:
    mov rdx, rsi
    jmp fe_mul

; out = a * 121665, the (A - 2) / 4 ladder constant. rdi = out, rsi = a
fe_mul_a24:
    push rbx
    mov r8d, 121665
    xor ebx, ebx
    xor ecx, ecx
.limb:
    mov rax, [rsi + rcx * 8]
    mul r8
    add rax, rbx
    adc rdx, 0
    mov [rdi + rcx * 8], rax
    mov rbx, rdx
    inc ecx
    cmp ecx, 4
    jb .limb
    imul rbx, rbx, 38
    add [rdi], rbx
    adc qword [rdi + 8], 0
    adc qword [rdi + 16], 0
    adc qword [rdi + 24], 0
    sbb rax, rax
    and rax, 38
    add [rdi], rax
    pop rbx
    ret

; Swaps a and b when swap is 1, without branching. rdi = a, rsi = b, rdx = swap (0/1)
fe_cswap:
    neg rdx
    xor ecx, ecx
.limb:
    mov rax, [rdi + rcx * 8]
    mov r8, [rsi + rcx * 8]
    mov r9, rax
    xor r9, r8
    and r9, rdx
    xor rax, r9
    xor r8, r9
    mov [rdi + rcx * 8], rax
    mov [rsi + rcx * 8], r8
    inc ecx
    cmp ecx, 4
    jb .limb
    ret

; Reduces to the canonical value in [0, p). rdi = in/out
fe_freeze:
    push rbx
    mov r8, [rdi]
    mov r9, [rdi + 8]
    mov r10, [rdi + 16]
    mov r11, [rdi + 24]
    ; Fold bit 255 down (2^255 = 19). Twice is enough to land below 2^255.
%rep 2
    mov rax, r11
    shr rax, 63
    btr r11, 63
    imul rax, rax, 19
    add r8, rax
    adc r9, 0
    adc r10, 0
    adc r11, 0
%endrep
    ; v >= p exactly when v + 19 reaches 2^255, and then v - p = v + 19 - 2^255.
    mov rax, r8
    add rax, 19
    mov rcx, r9
    adc rcx, 0
    mov rdx, r10
    adc rdx, 0
    mov rsi, r11
    adc rsi, 0
    mov rbx, rsi
    shr rbx, 63
    neg rbx                                 ; all ones when v >= p
    btr rsi, 63
    xor rax, r8
    and rax, rbx
    xor r8, rax
    xor rcx, r9
    and rcx, rbx
    xor r9, rcx
    xor rdx, r10
    and rdx, rbx
    xor r10, rdx
    xor rsi, r11
    and rsi, rbx
    xor r11, rsi
    mov [rdi], r8
    mov [rdi + 8], r9
    mov [rdi + 16], r10
    mov [rdi + 24], r11
    pop rbx
    ret

; out = z^(p-2) = 1/z. out may alias z. rdi = out, rsi = z
fe_invert:
    push rbx
    push r12
    sub rsp, 72                             ; acc, copy of z
    mov r12, rdi
    mov rdi, rsp
    mov ecx, 32
    push rsi
    rep movsb
    pop rsi
    lea rdi, [rsp + 32]
    mov ecx, 32
    rep movsb
    ; p - 2 = 2^255 - 21: bits 254..5 are set and bits 4..0 are 01011.
    ; acc = z covers bit 254, then square-and-multiply down to bit 0.
    mov ebx, 253
.bit:
    mov rdi, rsp
    mov rsi, rsp
    call fe_sq
    cmp ebx, 5
    jae .multiply
    cmp ebx, 3
    je .multiply
    cmp ebx, 2
    jae .next
.multiply:
    mov rdi, rsp
    mov rsi, rsp
    lea rdx, [rsp + 32]
    call fe_mul
.next:
    dec ebx
    jns .bit
    mov rdi, r12
    mov rsi, rsp
    mov ecx, 32
    rep movsb
    mov rdi, rsp
    mov esi, 64
    call wipe
    add rsp, 72
    pop r12
    pop rbx
    ret

; Ladder scratch, one 32-byte slot each.
%define S_K     0
%define S_X1    32
%define S_X2    64
%define S_Z2    96
%define S_X3    128
%define S_Z3    160
%define S_A     192
%define S_AA    224
%define S_B     256
%define S_BB    288
%define S_E     320
%define S_C     352
%define S_D     384
%define S_DA    416
%define S_CB    448
%define S_T     480
%define S_SIZE  512

%macro FE 4
    lea rdi, [rsp + %2]
    lea rsi, [rsp + %3]
    lea rdx, [rsp + %4]
    call %1
%endmacro

; rdi = out (32), rsi = scalar (32), rdx = u-coordinate (32)
; -> eax = 0, or -1 if the result is all zeros (a low-order input point)
x25519:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, S_SIZE + 8
    mov r12, rdi

    lea rdi, [rsp + S_K]
    mov ecx, 32
    rep movsb
    and byte [rsp + S_K], 248
    and byte [rsp + S_K + 31], 127
    or byte [rsp + S_K + 31], 64
    lea rdi, [rsp + S_X1]
    mov rsi, rdx
    mov ecx, 32
    rep movsb
    and byte [rsp + S_X1 + 31], 127

    xor eax, eax
    lea rdi, [rsp + S_X2]
    mov ecx, 32 * 2                         ; x2 and z2
    rep stosb
    mov byte [rsp + S_X2], 1
    lea rdi, [rsp + S_X3]
    lea rsi, [rsp + S_X1]
    mov ecx, 32
    rep movsb
    xor eax, eax
    lea rdi, [rsp + S_Z3]
    mov ecx, 32
    rep stosb
    mov byte [rsp + S_Z3], 1

    xor ebp, ebp                            ; swap
    mov ebx, 254
.ladder:
    mov eax, ebx
    shr eax, 3
    movzx r13d, byte [rsp + S_K + rax]
    mov ecx, ebx
    and ecx, 7
    shr r13d, cl
    and r13d, 1                             ; k_t
    xor ebp, r13d
    lea rdi, [rsp + S_X2]
    lea rsi, [rsp + S_X3]
    mov edx, ebp
    call fe_cswap
    lea rdi, [rsp + S_Z2]
    lea rsi, [rsp + S_Z3]
    mov edx, ebp
    call fe_cswap
    mov ebp, r13d

    FE fe_add, S_A, S_X2, S_Z2
    FE fe_mul, S_AA, S_A, S_A
    FE fe_sub, S_B, S_X2, S_Z2
    FE fe_mul, S_BB, S_B, S_B
    FE fe_sub, S_E, S_AA, S_BB
    FE fe_add, S_C, S_X3, S_Z3
    FE fe_sub, S_D, S_X3, S_Z3
    FE fe_mul, S_DA, S_D, S_A
    FE fe_mul, S_CB, S_C, S_B
    FE fe_add, S_X3, S_DA, S_CB
    FE fe_mul, S_X3, S_X3, S_X3
    FE fe_sub, S_Z3, S_DA, S_CB
    FE fe_mul, S_Z3, S_Z3, S_Z3
    FE fe_mul, S_Z3, S_X1, S_Z3
    FE fe_mul, S_X2, S_AA, S_BB
    lea rdi, [rsp + S_T]
    lea rsi, [rsp + S_E]
    call fe_mul_a24
    FE fe_add, S_T, S_AA, S_T
    FE fe_mul, S_Z2, S_E, S_T

    dec ebx
    jns .ladder

    lea rdi, [rsp + S_X2]
    lea rsi, [rsp + S_X3]
    mov edx, ebp
    call fe_cswap
    lea rdi, [rsp + S_Z2]
    lea rsi, [rsp + S_Z3]
    mov edx, ebp
    call fe_cswap

    lea rdi, [rsp + S_Z2]
    lea rsi, [rsp + S_Z2]
    call fe_invert
    FE fe_mul, S_X2, S_X2, S_Z2
    lea rdi, [rsp + S_X2]
    call fe_freeze

    mov rdi, r12
    lea rsi, [rsp + S_X2]
    mov ecx, 32
    rep movsb
    xor eax, eax                            ; OR of all output bytes
    xor ecx, ecx
.zero_check:
    or al, [r12 + rcx]
    inc ecx
    cmp ecx, 32
    jb .zero_check
    neg al                                  ; CF = 1 unless every byte was zero
    sbb ebx, ebx                            ; -1 if nonzero
    not ebx                                 ; -1 if all zero, else 0
    mov rdi, rsp
    mov esi, S_SIZE
    call wipe
    mov eax, ebx
    add rsp, S_SIZE + 8
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; rdi = public out (32), rsi = private (32)
x25519_public:
    lea rdx, [x25519_basepoint]
    jmp x25519
