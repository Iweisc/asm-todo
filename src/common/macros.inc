; text name, "bytes"...  defines name and name_len
%macro text 2+
%1: db %2
%1_len equ $ - %1
%endmacro
