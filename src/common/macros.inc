; Calling convention, as in System V: arguments in rdi, rsi, rdx, rcx, r8, r9,
; results in rax and sometimes rdx. Every function preserves rbx, rbp, r12-r15
; and may clobber the rest. One that preserves more says so in its comment.
;
; Every function has a one-line comment above it naming its registers in and
; out, like "; rdi = message, rsi = length -> eax = 1 if valid". One without
; arguments still gets a line saying what it does. make lint checks for it.

; text name, "bytes"...  defines name and name_len
%macro text 2+
%1: db %2
%1_len equ $ - %1
%endmacro

; fits field, length, next  fails the build when a field would run into the
; one after it. Every row layout ends with these, since the offsets are typed
; by hand and the limits they're built from live in config.inc.
%macro fits 3
%if %1 + %2 > %3
%error "this field runs into the one after it"
%endif
%endmacro
