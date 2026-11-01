; crypto-test: checks the hand-written primitives.
;
;   crypto-test          runs published test vectors, exits 1 on any failure
;   crypto-test fuzz     reads "op hex-args..." lines on stdin and prints results,
;                        so the primitives can be compared against another
;                        implementation on random inputs. "-" is an empty argument,
;                        and the AEAD nonce counter is 8 little-endian bytes in hex.

default rel
bits 64

%include "sys.inc"
%include "macros.inc"

%define IN_MAX      (16 * 1024 * 1024)
%define ARG_MAX     65536

section .text
global _start

%include "util.asm"
%include "crypto/sha.asm"
%include "crypto/hmac.asm"
%include "crypto/chacha.asm"
%include "crypto/x25519.asm"

section .rodata

s_sha256_abc:   db "abc"
s_sha256_long:  db "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
s_jefe:         db "Jefe"
s_jefe_msg:     db "what do ya want for nothing?"
s_password:     db "password"
s_salt:         db "salt"
s_ws_key:       db "dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

x_scalar:       db 0xa5,0x46,0xe3,0x6b,0xf0,0x52,0x7c,0x9d,0x3b,0x16,0x15,0x4b,0x82,0x46,0x5e,0xdd
                db 0x62,0x14,0x4c,0x0a,0xc1,0xfc,0x5a,0x18,0x50,0x6a,0x22,0x44,0xba,0x44,0x9a,0xc4
x_u:            db 0xe6,0xdb,0x68,0x67,0x58,0x30,0x30,0xdb,0x35,0x94,0xc1,0xa4,0x24,0xb1,0x5f,0x7c
                db 0x72,0x66,0x24,0xec,0x26,0xb3,0x35,0x3b,0x10,0xa9,0x03,0xa6,0xd0,0xab,0x1c,0x4c
alice_priv:     db 0x77,0x07,0x6d,0x0a,0x73,0x18,0xa5,0x7d,0x3c,0x16,0xc1,0x72,0x51,0xb2,0x66,0x45
                db 0xdf,0x4c,0x2f,0x87,0xeb,0xc0,0x99,0x2a,0xb1,0x77,0xfb,0xa5,0x1d,0xb9,0x2c,0x2a
chacha_nonce:   db 0,0,0,9, 0,0,0,0x4a, 0,0,0,0

v_sha256_abc:   db "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", 0
v_sha256_long:  db "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", 0
v_sha1_abc:     db "a9993e364706816aba3e25717850c26c9cd0d89d", 0
v_hmac:         db "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", 0
v_pbkdf2_1:     db "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b", 0
v_pbkdf2_4096:  db "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a", 0
v_chacha:       db "10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4e"
                db "d2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e", 0
v_x25519:       db "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552", 0
v_alice_pub:    db "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a", 0
v_ws_accept:    db "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", 0

n_sha256_abc:   db "sha256 abc", 0
n_sha256_long:  db "sha256 two blocks", 0
n_sha1_abc:     db "sha1 abc", 0
n_hmac:         db "hmac-sha256 rfc4231 #2", 0
n_pbkdf2_1:     db "pbkdf2 1 iteration", 0
n_pbkdf2_4096:  db "pbkdf2 4096 iterations", 0
n_chacha:       db "chacha20 block rfc8439", 0
n_x25519:       db "x25519 rfc7748", 0
n_alice_pub:    db "x25519 public key rfc7748", 0
n_aead:         db "aead seal then open", 0
n_aead_forged:  db "aead rejects a flipped bit", 0
n_ws_accept:    db "websocket accept rfc6455", 0

s_ok:           db "ok    ", 0
s_fail:         db "FAIL  ", 0
s_got:          db "      got ", 0
s_newline:      db 10, 0
s_fuzz:         db "fuzz", 0
s_bad_line:     db "bad line", 10, 0

op_sha256:      db "sha256", 0
op_sha1:        db "sha1", 0
op_hmac:        db "hmac", 0
op_pbkdf2:      db "pbkdf2", 0
op_hkdf:        db "hkdf", 0
op_x25519:      db "x25519", 0
op_seal:        db "seal", 0
op_open:        db "open", 0
op_b64:         db "b64", 0
s_rejected:     db "FAIL", 0

section .bss

failures:       resd 1
out:            resb 256
hexbuf:         resb 2 * ARG_MAX + 64
input:          resb IN_MAX
arg1:           resb ARG_MAX
arg2:           resb ARG_MAX
arg3:           resb ARG_MAX
arg4:           resb ARG_MAX + 16
arg_len:        resq 4
md_ctx:         resb MD_CTX_SIZE
line_end:       resq 1

section .text

_start:
    cmp qword [rsp], 2
    jb vectors
    mov rdi, [rsp + 16]
    lea rsi, [s_fuzz]
    call cstr_eq
    test eax, eax
    jnz fuzz
    jmp vectors

; rdi = name, rsi = bytes, rdx = length, rcx = expected hex
check_hex:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rcx
    lea rdi, [hexbuf]
    call put_hex
    mov byte [rdi], 0
    lea rdi, [hexbuf]
    mov rsi, r12
    call cstr_eq
    mov r13d, eax
    jmp report

; rdi = name, eax-style result in esi (1 = pass)
check_true:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r13d, esi
    mov byte [hexbuf], 0
report:
    lea rdi, [s_ok]
    test r13d, r13d
    jnz .print
    inc dword [failures]
    lea rdi, [s_fail]
.print:
    call print_out
    mov rdi, rbx
    call print_out
    lea rdi, [s_newline]
    call print_out
    test r13d, r13d
    jnz .done
    lea rdi, [s_got]
    call print_out
    lea rdi, [hexbuf]
    call print_out
    lea rdi, [s_newline]
    call print_out
.done:
    pop r13
    pop r12
    pop rbx
    ret

print_out:
    push rdi
    call strlen
    pop rsi
    mov rdx, rax
    mov edi, 1
    jmp write_all

vectors:
    lea rdi, [s_sha256_abc]
    mov esi, 3
    lea rdx, [out]
    call sha256
    lea rdi, [n_sha256_abc]
    lea rsi, [out]
    mov edx, 32
    lea rcx, [v_sha256_abc]
    call check_hex

    lea rdi, [s_sha256_long]
    mov esi, 56
    lea rdx, [out]
    call sha256
    lea rdi, [n_sha256_long]
    lea rsi, [out]
    mov edx, 32
    lea rcx, [v_sha256_long]
    call check_hex

    lea rdi, [md_ctx]
    call sha1_init
    lea rdi, [md_ctx]
    lea rsi, [s_sha256_abc]
    mov edx, 3
    call sha1_update
    lea rdi, [md_ctx]
    lea rsi, [out]
    call sha1_final
    lea rdi, [n_sha1_abc]
    lea rsi, [out]
    mov edx, 20
    lea rcx, [v_sha1_abc]
    call check_hex

    lea rdi, [s_jefe]
    mov esi, 4
    lea rdx, [s_jefe_msg]
    mov ecx, 28
    lea r8, [out]
    call hmac_sha256
    lea rdi, [n_hmac]
    lea rsi, [out]
    mov edx, 32
    lea rcx, [v_hmac]
    call check_hex

    lea rdi, [s_password]
    mov esi, 8
    lea rdx, [s_salt]
    mov ecx, 4
    mov r8d, 1
    lea r9, [out]
    call pbkdf2_sha256
    lea rdi, [n_pbkdf2_1]
    lea rsi, [out]
    mov edx, 32
    lea rcx, [v_pbkdf2_1]
    call check_hex

    lea rdi, [s_password]
    mov esi, 8
    lea rdx, [s_salt]
    mov ecx, 4
    mov r8d, 4096
    lea r9, [out]
    call pbkdf2_sha256
    lea rdi, [n_pbkdf2_4096]
    lea rsi, [out]
    mov edx, 32
    lea rcx, [v_pbkdf2_4096]
    call check_hex

    ; RFC 8439 2.3.2: key 00..1f, counter 1
    xor ecx, ecx
.key:
    mov [arg1 + rcx], cl
    inc ecx
    cmp ecx, 32
    jb .key
    lea rdi, [arg1]
    mov esi, 1
    lea rdx, [chacha_nonce]
    lea rcx, [out]
    call chacha20_block
    lea rdi, [n_chacha]
    lea rsi, [out]
    mov edx, 64
    lea rcx, [v_chacha]
    call check_hex

    lea rdi, [out]
    lea rsi, [x_scalar]
    lea rdx, [x_u]
    call x25519
    lea rdi, [n_x25519]
    lea rsi, [out]
    mov edx, 32
    lea rcx, [v_x25519]
    call check_hex

    lea rdi, [out]
    lea rsi, [alice_priv]
    call x25519_public
    lea rdi, [n_alice_pub]
    lea rsi, [out]
    mov edx, 32
    lea rcx, [v_alice_pub]
    call check_hex

    ; Round trip: seal 100 bytes, open them, compare with the original.
    xor ecx, ecx
.plain:
    mov [arg2 + rcx], cl
    mov [arg3 + rcx], cl
    inc ecx
    cmp ecx, 100
    jb .plain
    lea rdi, [arg1]
    mov esi, 7
    lea rdx, [s_jefe]
    mov ecx, 4
    lea r8, [arg2]
    mov r9d, 100
    call aead_seal
    lea rdi, [arg1]
    mov esi, 7
    lea rdx, [s_jefe]
    mov ecx, 4
    lea r8, [arg2]
    mov r9d, 116
    call aead_open
    mov ebx, eax
    lea rdi, [arg2]
    lea rsi, [arg3]
    mov edx, 100
    call mem_eq
    test ebx, ebx
    mov esi, 0
    cmovz esi, eax
    lea rdi, [n_aead]
    call check_true

    lea rdi, [arg1]
    mov esi, 7
    lea rdx, [s_jefe]
    mov ecx, 4
    lea r8, [arg2]
    mov r9d, 100
    call aead_seal
    xor byte [arg2 + 50], 1
    lea rdi, [arg1]
    mov esi, 7
    lea rdx, [s_jefe]
    mov ecx, 4
    lea r8, [arg2]
    mov r9d, 116
    call aead_open
    xor esi, esi
    cmp eax, -1
    sete sil
    lea rdi, [n_aead_forged]
    call check_true

    lea rdi, [md_ctx]
    call sha1_init
    lea rdi, [md_ctx]
    lea rsi, [s_ws_key]
    mov edx, 60
    call sha1_update
    lea rdi, [md_ctx]
    lea rsi, [out]
    call sha1_final
    lea rdi, [arg1]
    lea rsi, [out]
    mov edx, 20
    call put_base64
    mov byte [rdi], 0
    lea rdi, [arg1]
    lea rsi, [v_ws_accept]
    call cstr_eq
    mov esi, eax
    lea rdi, [n_ws_accept]
    call check_true

    xor edi, edi
    cmp dword [failures], 0
    setne dil
    call exit

; --- fuzz mode ---

; rsi = cursor -> rsi past the token, rax = token start, rdx = token length
next_token:
.skip:
    cmp rsi, [line_end]
    jae .empty
    cmp byte [rsi], ' '
    jne .start
    inc rsi
    jmp .skip
.start:
    mov rax, rsi
.scan:
    cmp rsi, [line_end]
    jae .end
    cmp byte [rsi], ' '
    je .end
    inc rsi
    jmp .scan
.end:
    mov rdx, rsi
    sub rdx, rax
    ret
.empty:
    mov rax, rsi
    xor edx, edx
    ret

; Decodes the next hex token into dst. rsi = cursor, rdi = dst, rcx = arg index
; -> rsi advanced, arg_len[index] set
hex_arg:
    push rbx
    push r12
    push rdi
    mov rbx, rcx
    call next_token
    pop rdi
    mov r12, rsi
    cmp rdx, 1
    jne .decode
    cmp byte [rax], '-'
    jne .decode
    xor edx, edx
.decode:
    shr rdx, 1
    lea rcx, [arg_len]
    mov [rcx + rbx * 8], rdx
    mov rsi, rax
    call parse_hex
    mov rsi, r12
    pop r12
    pop rbx
    ret

; rsi = cursor -> eax = decimal number, rsi advanced
num_arg:
    call next_token
    push rsi
    mov rdi, rax
    mov rsi, rdx
    call parse_u32
    pop rsi
    ret

; prints out[0..rdx) as hex plus a newline
emit_hex:
    lea rsi, [out]
emit_hex_from:
    lea rdi, [hexbuf]
    call put_hex
    mov byte [rdi], 10
    inc rdi
    mov rdx, rdi
    lea rsi, [hexbuf]
    sub rdx, rsi
    mov edi, 1
    jmp write_all

fuzz:
    xor ebx, ebx
.read:
    mov eax, SYS_read
    xor edi, edi
    lea rsi, [input + rbx]
    mov edx, IN_MAX
    sub edx, ebx
    syscall
    test rax, rax
    jle .parse
    add rbx, rax
    jmp .read
.parse:
    lea r12, [input]
    lea r13, [input + rbx]
.line:
    cmp r12, r13
    jae .done
    mov rdi, r12
.find_nl:
    cmp rdi, r13
    jae .have_line
    cmp byte [rdi], 10
    je .have_line
    inc rdi
    jmp .find_nl
.have_line:
    mov [line_end], rdi
    lea r14, [rdi + 1]
    mov rsi, r12
    call next_token
    mov r15, rsi
    mov byte [rax + rdx], 0                 ; terminate the op name in place
    mov rbx, rax
    inc r15

    mov rdi, rbx
    lea rsi, [op_sha256]
    call cstr_eq
    test eax, eax
    jnz .sha256
    mov rdi, rbx
    lea rsi, [op_sha1]
    call cstr_eq
    test eax, eax
    jnz .sha1
    mov rdi, rbx
    lea rsi, [op_hmac]
    call cstr_eq
    test eax, eax
    jnz .hmac
    mov rdi, rbx
    lea rsi, [op_pbkdf2]
    call cstr_eq
    test eax, eax
    jnz .pbkdf2
    mov rdi, rbx
    lea rsi, [op_hkdf]
    call cstr_eq
    test eax, eax
    jnz .hkdf
    mov rdi, rbx
    lea rsi, [op_x25519]
    call cstr_eq
    test eax, eax
    jnz .x25519
    mov rdi, rbx
    lea rsi, [op_seal]
    call cstr_eq
    test eax, eax
    jnz .seal
    mov rdi, rbx
    lea rsi, [op_open]
    call cstr_eq
    test eax, eax
    jnz .open
    mov rdi, rbx
    lea rsi, [op_b64]
    call cstr_eq
    test eax, eax
    jnz .b64
    lea rdi, [s_bad_line]
    call print_out
    jmp .next

.sha256:
    mov rsi, r15
    lea rdi, [arg1]
    xor ecx, ecx
    call hex_arg
    lea rdi, [arg1]
    mov rsi, [arg_len]
    lea rdx, [out]
    call sha256
    mov edx, 32
    call emit_hex
    jmp .next
.sha1:
    mov rsi, r15
    lea rdi, [arg1]
    xor ecx, ecx
    call hex_arg
    lea rdi, [md_ctx]
    call sha1_init
    lea rdi, [md_ctx]
    lea rsi, [arg1]
    mov rdx, [arg_len]
    call sha1_update
    lea rdi, [md_ctx]
    lea rsi, [out]
    call sha1_final
    mov edx, 20
    call emit_hex
    jmp .next
.hmac:
    mov rsi, r15
    lea rdi, [arg1]
    xor ecx, ecx
    call hex_arg
    lea rdi, [arg2]
    mov ecx, 1
    call hex_arg
    lea rdi, [arg1]
    mov rsi, [arg_len]
    lea rdx, [arg2]
    mov rcx, [arg_len + 8]
    lea r8, [out]
    call hmac_sha256
    mov edx, 32
    call emit_hex
    jmp .next
.pbkdf2:
    mov rsi, r15
    lea rdi, [arg1]
    xor ecx, ecx
    call hex_arg
    lea rdi, [arg2]
    mov ecx, 1
    call hex_arg
    call num_arg
    mov r8d, eax
    lea rdi, [arg1]
    mov rsi, [arg_len]
    lea rdx, [arg2]
    mov rcx, [arg_len + 8]
    lea r9, [out]
    call pbkdf2_sha256
    mov edx, 32
    call emit_hex
    jmp .next
.hkdf:
    mov rsi, r15
    lea rdi, [arg1]
    xor ecx, ecx
    call hex_arg
    lea rdi, [arg2]
    mov ecx, 1
    call hex_arg
    lea rdi, [arg1]
    lea rsi, [arg2]
    mov rdx, [arg_len + 8]
    lea rcx, [out]
    lea r8, [out + 32]
    call hkdf2
    mov edx, 64
    call emit_hex
    jmp .next
.x25519:
    mov rsi, r15
    lea rdi, [arg1]
    xor ecx, ecx
    call hex_arg
    lea rdi, [arg2]
    mov ecx, 1
    call hex_arg
    lea rdi, [out]
    lea rsi, [arg1]
    lea rdx, [arg2]
    call x25519
    mov edx, 32
    call emit_hex
    jmp .next
.seal:
.open:
    push rbx
    mov rsi, r15
    lea rdi, [arg1]
    xor ecx, ecx
    call hex_arg
    lea rdi, [arg2]                         ; n as 8 little-endian bytes
    mov ecx, 1
    call hex_arg
    mov rbp, [arg2]
    lea rdi, [arg3]
    mov ecx, 2
    call hex_arg
    lea rdi, [arg4]
    mov ecx, 3
    call hex_arg
    pop rbx
    lea rdi, [arg1]
    mov rsi, rbp
    lea rdx, [arg3]
    mov rcx, [arg_len + 16]
    lea r8, [arg4]
    mov r9, [arg_len + 24]
    cmp byte [rbx], 's'
    jne .do_open
    call aead_seal
    mov rdx, [arg_len + 24]
    add rdx, 16
    lea rsi, [arg4]
    call emit_hex_from
    jmp .next
.do_open:
    call aead_open
    test eax, eax
    jnz .rejected
    mov rdx, [arg_len + 24]
    sub rdx, 16
    lea rsi, [arg4]
    call emit_hex_from
    jmp .next
.rejected:
    lea rdi, [s_rejected]
    call print_out
    lea rdi, [s_newline]
    call print_out
    jmp .next
.b64:
    mov rsi, r15
    lea rdi, [arg1]
    xor ecx, ecx
    call hex_arg
    lea rdi, [hexbuf]
    lea rsi, [arg1]
    mov rdx, [arg_len]
    call put_base64
    mov byte [rdi], 10
    inc rdi
    mov rdx, rdi
    lea rsi, [hexbuf]
    sub rdx, rsi
    mov edi, 1
    call write_all
.next:
    mov r12, r14
    jmp .line
.done:
    xor edi, edi
    call exit
