; The keyboard layout, read from the XKB keymap the compositor sends, so
; AZERTY, QWERTZ, Dvorak and the like type what their keys say.
;
; Only enough of the format to fill two tables: xkb_keycodes gives each key
; name a code ("<AD01> = 24;"), and xkb_symbols gives each key name its
; keysyms ("key <AD01> { [ q, Q ] };"), of which we take the first two of the
; first group. Keysyms outside printable ASCII type nothing, since fields
; only hold ASCII. A keymap we can't make sense of leaves the US layout.

%define KEYCODES        256             ; XKB codes, evdev + 8

section .data
; Indexed by evdev key code. 0 means the key types nothing. US until the
; compositor says otherwise.
keymap_plain:
    db 0, 0, "1234567890-=", 0, 0
    db "qwertyuiop[]", 0, 0
    db "asdfghjkl;'`", 0, "\"
    db "zxcvbnm,./", 0, "*", 0, " "
    times 128 - ($ - keymap_plain) db 0
keymap_shift:
    db 0, 0, "!@#$%^&*()_+", 0, 0
    db "QWERTYUIOP{}", 0, 0
    db 'ASDFGHJKL:"~', 0, "|"
    db "ZXCVBNM<>?", 0, "*", 0, " "
    times 128 - ($ - keymap_shift) db 0

section .rodata
s_xkb_keycodes: db "xkb_keycodes", 0
s_xkb_symbols:  db "xkb_symbols", 0
s_xkb_key:      db "key <", 0
s_lt:           db "<", 0
; The US key code of each letter a-z, which is what the KEY_* shortcuts name.
us_letter_keys: db 30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50
                db 49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44
; Keysym names for the printable ASCII that isn't a letter or digit, each
; followed by its character. Letters and digits are their own names.
keysym_names:
    db "space", 0, ' ', "exclam", 0, '!', "quotedbl", 0, '"'
    db "numbersign", 0, '#', "dollar", 0, '$', "percent", 0, '%'
    db "ampersand", 0, '&', "apostrophe", 0, "'", "quoteright", 0, "'"
    db "parenleft", 0, '(', "parenright", 0, ')', "asterisk", 0, '*'
    db "plus", 0, '+', "comma", 0, ',', "minus", 0, '-', "period", 0, '.'
    db "slash", 0, '/', "colon", 0, ':', "semicolon", 0, ';', "less", 0, '<'
    db "equal", 0, '=', "greater", 0, '>', "question", 0, '?', "at", 0, '@'
    db "bracketleft", 0, '[', "backslash", 0, '\', "bracketright", 0, ']'
    db "asciicircum", 0, '^', "underscore", 0, '_', "grave", 0, '`'
    db "quoteleft", 0, '`', "braceleft", 0, '{', "bar", 0, '|'
    db "braceright", 0, '}', "asciitilde", 0, '~'
    db 0

section .bss
alignb 4
key_names:      resd KEYCODES           ; up to 4 characters, zero padded
new_plain:      resb 128
new_shift:      resb 128

section .text

; wl_keyboard.keymap: maps the fd, reads it, and lets it go.
; edi = fd, esi = size
keymap_load:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    test esi, esi
    jz .close
    mov eax, SYS_mmap
    xor edi, edi
    mov esi, r12d
    mov edx, PROT_READ
    mov r10d, MAP_PRIVATE
    mov r8d, ebx
    xor r9d, r9d
    syscall
    cmp rax, -4096
    ja .close
    mov r13, rax
    mov rsi, rax
    mov edx, r12d
    call keymap_parse
    mov eax, SYS_munmap
    mov rdi, r13
    mov esi, r12d
    syscall
.close:
    mov eax, SYS_close
    mov edi, ebx
    syscall
    pop r13
    pop r12
    pop rbx
    ret

; rsi = keymap text, edx = length. Replaces the tables if it found any letters.
keymap_parse:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rsi
    lea r12, [rsi + rdx]
    lea rdi, [key_names]
    mov esi, KEYCODES * 4 + 256             ; new_plain and new_shift follow
    call wipe
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [s_xkb_keycodes]
    call find_text
    test rax, rax
    jz .done
    mov rsi, rax
    mov rdx, r12
    call read_keycodes
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [s_xkb_symbols]
    call find_text
    test rax, rax
    jz .done
    mov rsi, rax
    mov rdx, r12
    call read_symbols
    xor ecx, ecx
.letter:
    movzx eax, byte [new_plain + rcx]
    sub eax, 'a'
    cmp eax, 'z' - 'a'
    jbe .adopt
    inc ecx
    cmp ecx, 128
    jb .letter
    jmp .done
.adopt:
    lea rdi, [keymap_plain]
    lea rsi, [new_plain]
    mov ecx, 256                            ; keymap_shift follows too
    rep movsb
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; rdi = text, rsi = its end, rdx = NUL-terminated needle -> rax = just past
; its first match, or 0
find_text:
    movzx ecx, byte [rdx]
.scan:
    cmp rdi, rsi
    jae .none
    cmp [rdi], cl
    je .try
    inc rdi
    jmp .scan
.try:
    xor eax, eax
.same:
    movzx r8d, byte [rdx + rax]
    test r8d, r8d
    jz .found
    lea r9, [rdi + rax]
    cmp r9, rsi
    jae .none
    cmp [r9], r8b
    jne .next
    inc eax
    jmp .same
.found:
    lea rax, [rdi + rax]
    ret
.next:
    inc rdi
    jmp .scan
.none:
    xor eax, eax
    ret

; Reads "<NAME>" at the cursor. rsi = just past the '<', rdx = end
; -> eax = the name packed into 4 bytes, rsi = past the '>'. Carry set if it isn't one.
read_key_name:
    xor eax, eax
    xor ecx, ecx
.char:
    cmp rsi, rdx
    jae .bad
    movzx r8d, byte [rsi]
    inc rsi
    cmp r8d, '>'
    je .done
    cmp ecx, 32
    jae .bad                                ; longer than 4
    shl r8d, cl
    or eax, r8d
    add ecx, 8
    jmp .char
.done:
    clc
    ret
.bad:
    stc
    ret

; rsi = cursor, rdx = end -> rsi past any spaces, tabs and newlines
skip_blank:
    cmp rsi, rdx
    jae .done
    cmp byte [rsi], ' '
    ja .done
    inc rsi
    jmp skip_blank
.done:
    ret

; "<NAME> = 24;" lines, from rsi up to rdx, into key_names.
read_keycodes:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdx
.find:
    mov rdi, rsi
    mov rsi, r12
    lea rdx, [s_lt]
    call find_text
    test rax, rax
    jz .done
    mov rsi, rax
    mov rdx, r12
    call read_key_name
    jc .find
    mov ebx, eax
    call skip_blank
    cmp rsi, r12
    jae .done
    cmp byte [rsi], '='
    jne .find
    inc rsi
    call skip_blank
    xor eax, eax
    xor ecx, ecx                            ; digits seen
.digit:
    cmp rsi, r12
    jae .done
    movzx r8d, byte [rsi]
    sub r8d, '0'
    cmp r8d, 9
    ja .number
    imul eax, eax, 10
    add eax, r8d
    inc rsi
    inc ecx
    cmp eax, KEYCODES
    jb .digit
    jmp .find
.number:
    test ecx, ecx
    jz .find                                ; an alias
    mov [key_names + rax * 4], ebx
    jmp .find
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; "key <NAME> { [ sym, sym ] };" blocks, from rsi up to rdx, into new_plain
; and new_shift.
read_symbols:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rdx
.key:
    mov rdi, rsi
    mov rsi, r12
    lea rdx, [s_xkb_key]
    call find_text
    test rax, rax
    jz .done
    mov rsi, rax
    mov rdx, r12
    call read_key_name
    jc .key
    call key_code
    mov ebx, eax                            ; evdev code, or -1
.bracket:
    ; The keysyms' '[', not the one in "symbols[Group1]", before the block ends.
    cmp rsi, r12
    jae .done
    movzx eax, byte [rsi]
    inc rsi
    cmp eax, '}'
    je .key
    cmp eax, '['
    jne .bracket
    movzx eax, byte [rsi - 2]
    or eax, 0x20
    sub eax, 'a'
    cmp eax, 'z' - 'a'
    jbe .bracket
    call read_keysym
    mov r13d, eax
    mov r14d, eax                           ; one keysym is both levels
    cmp ecx, ','
    jne .store
    call read_keysym
    mov r14d, eax
.store:
    cmp ebx, 128
    jae .key
    mov [new_plain + rbx], r13b
    mov [new_shift + rbx], r14b
    jmp .key
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Shortcuts go by the letter on the key, so Ctrl+A is Ctrl+A on AZERTY too.
; edi = key code -> eax = the US code of the letter it types, or the code itself
shortcut_key:
    mov eax, edi
    cmp edi, 128
    jae .done
    movzx ecx, byte [keymap_plain + rdi]
    sub ecx, 'a'
    cmp ecx, 'z' - 'a'
    ja .done
    movzx eax, byte [us_letter_keys + rcx]
.done:
    ret

; eax = a key name -> eax = its evdev code, or -1 if no keycode has it
key_code:
    xor ecx, ecx
.code:
    cmp [key_names + rcx * 4], eax
    je .found
    inc ecx
    cmp ecx, KEYCODES
    jb .code
    mov eax, -1
    ret
.found:
    lea eax, [ecx - 8]
    ret

; Reads one keysym of a list. rsi = cursor, r12 = end
; -> eax = its character or 0, ecx = the ',' or ']' after it, rsi past that
read_keysym:
    mov rdx, r12
    call skip_blank
    mov rdi, rsi                            ; the name's start
.name:
    xor ecx, ecx
    cmp rsi, r12
    jae .end
    movzx ecx, byte [rsi]
    inc rsi
    cmp ecx, ','
    je .end
    cmp ecx, ']'
    je .end
    jmp .name
.end:
    ; Back over the separator and any blanks before it.
    mov rdx, rsi
    test ecx, ecx
    jz .trim
    dec rdx
.trim:
    cmp rdx, rdi
    jbe .measured
    cmp byte [rdx - 1], ' '
    ja .measured
    dec rdx
    jmp .trim
.measured:
    sub rdx, rdi
    push rcx
    push rsi
    mov rsi, rdi
    call keysym_char
    pop rsi
    pop rcx
    ret

; rsi = keysym name, edx = its length -> eax = its printable ASCII character, or 0
keysym_char:
    xor eax, eax
    cmp edx, 1
    jne .unicode
    movzx eax, byte [rsi]
    cmp eax, '!'
    jb .none
    cmp eax, '~'
    ja .none
    ret
.unicode:
    ; U0041, or a keysym's value like 0x61, which is the character itself in
    ; the ASCII range. Some compositors write every keysym that way.
    mov ecx, 1
    cmp edx, 5
    jne .value
    cmp byte [rsi], 'U'
    je .hex
.value:
    cmp edx, 3
    jb .named
    cmp word [rsi], '0x'
    jne .named
    mov ecx, 2
.hex:
    movzx r8d, byte [rsi + rcx]
    sub r8d, '0'
    cmp r8d, 9
    jbe .digit
    or r8d, 0x20
    sub r8d, 'a' - '0' - 10
    cmp r8d, 10
    jb .named
    cmp r8d, 15
    ja .named
.digit:
    cmp eax, 0x1000000
    jae .none                               ; too long to be ASCII anyway
    shl eax, 4
    or eax, r8d
    inc ecx
    cmp ecx, edx
    jb .hex
    cmp eax, ' '
    jb .none
    cmp eax, '~'
    ja .none
    ret
.named:
    lea rdi, [keysym_names]
.entry:
    cmp byte [rdi], 0
    je .none
    xor ecx, ecx
.compare:
    cmp ecx, edx
    je .ends
    movzx eax, byte [rdi + rcx]
    cmp al, [rsi + rcx]
    jne .skip
    inc ecx
    jmp .compare
.ends:
    cmp byte [rdi + rcx], 0
    jne .skip
    movzx eax, byte [rdi + rcx + 1]
    ret
.skip:
    ; Past this entry's name, its NUL and its character.
    cmp byte [rdi], 0
    je .past
    inc rdi
    jmp .skip
.past:
    add rdi, 2
    jmp .entry
.none:
    xor eax, eax
    ret
