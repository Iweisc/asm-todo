; The font: every glyph is a few pen strokes along its centerline, in font
; units (1000 per em, y up, baseline at 0, x-height 500, caps 700). text.asm
; rasterizes them with a pen at whatever size and weight it needs, so one
; drawing covers every text style. Strokes meet round, and a stroke end that
; touches nothing is cut flat.
;
;   GLYPH code, advance     starts a glyph. Codes must come in order.
;   L x0, y0, x1, y1        a straight stroke
;   C x0, y0, ... x3, y3    a cubic Bezier stroke
;   ARC cx, cy, rx, ry, from, to
;                           an arc of a rounded-square ellipse, counterclockwise,
;                           with angles in steps of 45 degrees (0 east, 2 north,
;                           4 west, 6 south)
;   E cx, cy, rx, ry        a whole one

%define GO_END          0
%define GO_LINE         1
%define GO_CUBIC        2
%define GLYPH_FIRST     32
%define GLYPH_COUNT     98              ; ASCII, then the three below
%define GLYPH_ELLIPSIS  127
%define GLYPH_CHEVRON   128
%define GLYPH_MIDDOT    129

%define XHEIGHT         500
%define CAPHEIGHT       700
%define ASCENDER        740
%define DESCENDER       -210

; How far a quarter arc's handles reach, in thousandths of the radius. A
; circle is 552. Longer handles square the bowls off.
%define ARC_HANDLE      585

; Sets q_x0, q_y0 ... q_x3, q_y3 to quarter %1's control points on the unit
; square, times 1000: quarter 0 runs east to north, 1 north to west, and so on.
%macro QUARTER 1
    %assign q_i ((%1) + 16) % 4
    %if q_i == 0
        %assign q_x0 1000
        %assign q_y0 0
        %assign q_x1 1000
        %assign q_y1 ARC_HANDLE
        %assign q_x2 ARC_HANDLE
        %assign q_y2 1000
        %assign q_x3 0
        %assign q_y3 1000
    %elif q_i == 1
        %assign q_x0 0
        %assign q_y0 1000
        %assign q_x1 -ARC_HANDLE
        %assign q_y1 1000
        %assign q_x2 -1000
        %assign q_y2 ARC_HANDLE
        %assign q_x3 -1000
        %assign q_y3 0
    %elif q_i == 2
        %assign q_x0 -1000
        %assign q_y0 0
        %assign q_x1 -1000
        %assign q_y1 -ARC_HANDLE
        %assign q_x2 -ARC_HANDLE
        %assign q_y2 -1000
        %assign q_x3 0
        %assign q_y3 -1000
    %else
        %assign q_x0 0
        %assign q_y0 -1000
        %assign q_x1 ARC_HANDLE
        %assign q_y1 -1000
        %assign q_x2 1000
        %assign q_y2 -ARC_HANDLE
        %assign q_x3 1000
        %assign q_y3 0
    %endif
%endmacro

%assign glyph_next GLYPH_FIRST

%macro GLYPH 2
    %if %1 != glyph_next
        %error "glyphs must be defined in order"
    %endif
    dw GO_END
glyph_ %+ glyph_next:
    dw %2
    %assign glyph_next glyph_next + 1
%endmacro

%macro L 4
    dw GO_LINE, %1, %2, %3, %4
%endmacro

%macro C 8
    dw GO_CUBIC, %1, %2, %3, %4, %5, %6, %7, %8
%endmacro

; Each 45 degree step is half of a quarter's cubic, split at its middle.
; Points are in thousandths here, then scaled by the radii.
%macro ARC 6
    %assign arc_a %5
    %rep %6 - %5
        QUARTER (arc_a + 16) >> 1
        %if ((arc_a + 16) & 1) == 0
            %assign h_x0 8 * q_x0
            %assign h_y0 8 * q_y0
            %assign h_x1 4 * (q_x0 + q_x1)
            %assign h_y1 4 * (q_y0 + q_y1)
            %assign h_x2 2 * (q_x0 + 2 * q_x1 + q_x2)
            %assign h_y2 2 * (q_y0 + 2 * q_y1 + q_y2)
            %assign h_x3 q_x0 + 3 * q_x1 + 3 * q_x2 + q_x3
            %assign h_y3 q_y0 + 3 * q_y1 + 3 * q_y2 + q_y3
        %else
            %assign h_x0 q_x0 + 3 * q_x1 + 3 * q_x2 + q_x3
            %assign h_y0 q_y0 + 3 * q_y1 + 3 * q_y2 + q_y3
            %assign h_x1 2 * (q_x1 + 2 * q_x2 + q_x3)
            %assign h_y1 2 * (q_y1 + 2 * q_y2 + q_y3)
            %assign h_x2 4 * (q_x2 + q_x3)
            %assign h_y2 4 * (q_y2 + q_y3)
            %assign h_x3 8 * q_x3
            %assign h_y3 8 * q_y3
        %endif
        C %1 + (%3 * h_x0) // 8000, %2 + (%4 * h_y0) // 8000, %1 + (%3 * h_x1) // 8000, %2 + (%4 * h_y1) // 8000, %1 + (%3 * h_x2) // 8000, %2 + (%4 * h_y2) // 8000, %1 + (%3 * h_x3) // 8000, %2 + (%4 * h_y3) // 8000
        %assign arc_a arc_a + 1
    %endrep
%endmacro

%macro E 4
    ARC %1, %2, %3, %4, 0, 8
%endmacro

section .rodata
align 2
font_glyphs:

GLYPH 32, 250                           ; space
GLYPH 33, 190                           ; !
    L 95, 700, 95, 200
    L 95, 0, 95, 1
GLYPH 34, 290                           ; "
    L 85, 700, 85, 530
    L 205, 700, 205, 530
GLYPH 35, 580                           ; #
    L 220, 680, 165, 20
    L 425, 680, 370, 20
    L 70, 455, 515, 455
    L 55, 245, 500, 245
GLYPH 36, 590                           ; $
    ARC 295, 530, 190, 170, 1, 6
    ARC 295, 180, 205, 180, 5, 10
    L 295, 780, 295, -80
GLYPH 37, 720                           ; %
    E 175, 545, 105, 150
    E 545, 155, 105, 150
    L 570, 700, 150, 0
GLYPH 38, 650                           ; &
    ARC 265, 570, 120, 125, -1, 5
    L 180, 482, 600, 0
    C 350, 482, 50, 290, 125, -10, 335, 0
    L 335, 0, 565, 250
GLYPH 39, 170                           ; '
    L 85, 700, 85, 530
GLYPH 40, 300                           ; (
    C 250, 760, 80, 560, 80, 80, 250, -120
GLYPH 41, 300                           ; )
    C 50, 760, 220, 560, 220, 80, 50, -120
GLYPH 42, 480                           ; *
    L 240, 700, 240, 440
    L 120, 640, 360, 500
    L 360, 640, 120, 500
GLYPH 43, 560                           ; +
    L 280, 90, 280, 490
    L 80, 290, 480, 290
GLYPH 44, 200                           ; ,
    L 105, 40, 60, -120
GLYPH 45, 400                           ; -
    L 75, 280, 325, 280
GLYPH 46, 190                           ; .
    L 95, 0, 95, 1
GLYPH 47, 400                           ; /
    L 50, -80, 350, 740
GLYPH 48, 590                           ; 0
    E 295, 350, 210, 360
GLYPH 49, 590                           ; 1
    L 335, 0, 335, 700
    L 335, 700, 145, 570
GLYPH 50, 590                           ; 2
    ARC 295, 495, 200, 205, 0, 3
    C 495, 495, 495, 385, 400, 300, 90, 0
    L 90, 0, 510, 0
GLYPH 51, 590                           ; 3
    ARC 285, 530, 185, 170, -2, 3
    ARC 290, 180, 205, 180, -3, 2
GLYPH 52, 590                           ; 4
    L 410, 0, 410, 700
    L 410, 700, 65, 210
    L 65, 210, 530, 210
GLYPH 53, 590                           ; 5
    L 475, 700, 150, 700
    L 150, 700, 130, 385
    ARC 300, 220, 205, 220, -3, 3
GLYPH 54, 590                           ; 6
    E 295, 220, 205, 220
    C 90, 220, 90, 560, 230, 700, 430, 695
GLYPH 55, 590                           ; 7
    L 75, 700, 515, 700
    L 515, 700, 195, 0
GLYPH 56, 590                           ; 8
    E 295, 535, 175, 165
    E 295, 185, 205, 185
GLYPH 57, 590                           ; 9
    E 295, 480, 205, 220
    C 500, 480, 500, 140, 360, 0, 160, 5
GLYPH 58, 190                           ; :
    L 95, 0, 95, 1
    L 95, 480, 95, 481
GLYPH 59, 200                           ; ;
    L 105, 40, 60, -120
    L 105, 480, 105, 481
GLYPH 60, 560                           ; <
    L 480, 540, 80, 290
    L 80, 290, 480, 40
GLYPH 61, 560                           ; =
    L 80, 385, 480, 385
    L 80, 195, 480, 195
GLYPH 62, 560                           ; >
    L 80, 540, 480, 290
    L 480, 290, 80, 40
GLYPH 63, 510                           ; ?
    ARC 260, 525, 175, 175, -2, 4
    L 260, 350, 260, 200
    L 260, 0, 260, 1
GLYPH 64, 820                           ; @
    E 395, 300, 120, 140
    L 515, 440, 515, 200
    C 515, 200, 515, 110, 660, 120, 710, 300
    ARC 395, 300, 315, 335, 0, 7
GLYPH 65, 660                           ; A
    L 35, 0, 330, 700
    L 330, 700, 625, 0
    L 128, 220, 532, 220
GLYPH 66, 620                           ; B
    L 85, 0, 85, 700
    L 85, 700, 330, 700
    ARC 330, 528, 155, 172, 6, 10
    L 85, 356, 345, 356
    ARC 345, 178, 185, 178, 6, 10
    L 85, 0, 345, 0
GLYPH 67, 700                           ; C
    ARC 380, 350, 300, 360, 1, 7
GLYPH 68, 690                           ; D
    L 85, 0, 85, 700
    L 85, 700, 300, 700
    ARC 300, 350, 310, 350, 6, 10
    L 85, 0, 300, 0
GLYPH 69, 580                           ; E
    L 85, 0, 85, 700
    L 85, 700, 505, 700
    L 85, 355, 465, 355
    L 85, 0, 510, 0
GLYPH 70, 560                           ; F
    L 85, 0, 85, 700
    L 85, 700, 500, 700
    L 85, 355, 460, 355
GLYPH 71, 740                           ; G
    ARC 380, 350, 300, 360, 1, 8
    L 680, 350, 680, 60
    L 680, 330, 455, 330
GLYPH 72, 690                           ; H
    L 85, 0, 85, 700
    L 605, 0, 605, 700
    L 85, 355, 605, 355
GLYPH 73, 180                           ; I
    L 90, 0, 90, 700
GLYPH 74, 520                           ; J
    L 425, 700, 425, 220
    ARC 235, 220, 190, 230, 5, 8
GLYPH 75, 630                           ; K
    L 85, 0, 85, 700
    L 575, 700, 85, 230
    L 255, 393, 605, 0
GLYPH 76, 525                           ; L
    L 85, 700, 85, 0
    L 85, 0, 495, 0
GLYPH 77, 820                           ; M
    L 85, 0, 85, 700
    L 85, 700, 410, 90
    L 410, 90, 735, 700
    L 735, 700, 735, 0
GLYPH 78, 695                           ; N
    L 85, 0, 85, 700
    L 85, 700, 610, 0
    L 610, 0, 610, 700
GLYPH 79, 760                           ; O
    E 380, 350, 310, 360
GLYPH 80, 600                           ; P
    L 85, 0, 85, 700
    L 85, 700, 330, 700
    ARC 330, 500, 185, 200, 6, 10
    L 85, 300, 330, 300
GLYPH 81, 760                           ; Q
    E 380, 350, 310, 360
    L 450, 160, 660, -40
GLYPH 82, 625                           ; R
    L 85, 0, 85, 700
    L 85, 700, 330, 700
    ARC 330, 505, 180, 195, 6, 10
    L 85, 310, 330, 310
    L 315, 310, 565, 0
GLYPH 83, 640                           ; S
    ARC 320, 530, 210, 170, 1, 6
    ARC 320, 180, 225, 180, 5, 10
GLYPH 84, 600                           ; T
    L 30, 700, 570, 700
    L 300, 700, 300, 0
GLYPH 85, 685                           ; U
    L 85, 700, 85, 270
    ARC 342, 270, 257, 280, 4, 8
    L 599, 270, 599, 700
GLYPH 86, 660                           ; V
    L 30, 700, 330, 0
    L 330, 0, 630, 700
GLYPH 87, 920                           ; W
    L 30, 700, 235, 0
    L 235, 0, 460, 700
    L 460, 700, 685, 0
    L 685, 0, 890, 700
GLYPH 88, 640                           ; X
    L 50, 700, 590, 0
    L 590, 700, 50, 0
GLYPH 89, 640                           ; Y
    L 35, 700, 320, 340
    L 605, 700, 320, 340
    L 320, 340, 320, 0
GLYPH 90, 620                           ; Z
    L 65, 700, 555, 700
    L 555, 700, 60, 0
    L 60, 0, 565, 0
GLYPH 91, 290                           ; [
    L 210, 750, 105, 750
    L 105, 750, 105, -110
    L 105, -110, 210, -110
GLYPH 92, 400                           ; backslash
    L 50, 740, 350, -80
GLYPH 93, 290                           ; ]
    L 80, 750, 185, 750
    L 185, 750, 185, -110
    L 185, -110, 80, -110
GLYPH 94, 560                           ; ^
    L 105, 400, 280, 700
    L 280, 700, 455, 400
GLYPH 95, 500                           ; _
    L 20, -100, 480, -100
GLYPH 96, 300                           ; `
    L 105, 720, 190, 610
GLYPH 97, 545                           ; a
    L 455, 0, 455, 330
    ARC 270, 330, 185, 175, 0, 3
    L 455, 285, 262, 285
    ARC 262, 140, 193, 145, 2, 8
GLYPH 98, 575                           ; b
    E 290, 250, 205, 260
    L 85, 740, 85, 0
GLYPH 99, 520                           ; c
    ARC 285, 250, 205, 260, 1, 7
GLYPH 100, 575                          ; d
    E 285, 250, 205, 260
    L 490, 740, 490, 0
GLYPH 101, 550                          ; e
    L 80, 250, 485, 250
    ARC 282, 250, 203, 260, 0, 7
GLYPH 102, 335                          ; f
    L 145, 0, 145, 590
    ARC 295, 590, 150, 150, 2, 4
    L 295, 740, 330, 740
    L 40, 500, 305, 500
GLYPH 103, 575                          ; g
    E 285, 255, 205, 255
    L 490, 500, 490, -45
    ARC 285, -45, 205, 165, 5, 8
GLYPH 104, 565                          ; h
    L 85, 740, 85, 0
    ARC 282, 315, 197, 185, 0, 4
    L 479, 315, 479, 0
GLYPH 105, 180                          ; i
    L 90, 500, 90, 0
    L 90, 690, 90, 691
GLYPH 106, 190                          ; j
    L 100, 500, 100, -95
    ARC -5, -95, 105, 115, 6, 8
    L 100, 690, 100, 691
GLYPH 107, 505                          ; k
    L 85, 740, 85, 0
    L 440, 500, 85, 160
    L 225, 294, 470, 0
GLYPH 108, 180                          ; l
    L 90, 740, 90, 0
GLYPH 109, 840                          ; m
    L 85, 500, 85, 0
    ARC 250, 335, 165, 165, 0, 4
    L 415, 335, 415, 0
    ARC 580, 335, 165, 165, 0, 4
    L 745, 335, 745, 0
GLYPH 110, 565                          ; n
    L 85, 500, 85, 0
    ARC 282, 315, 197, 185, 0, 4
    L 479, 315, 479, 0
GLYPH 111, 560                          ; o
    E 280, 250, 205, 260
GLYPH 112, 575                          ; p
    E 290, 250, 205, 260
    L 85, 500, 85, -210
GLYPH 113, 575                          ; q
    E 285, 250, 205, 260
    L 490, 500, 490, -210
GLYPH 114, 365                          ; r
    L 85, 500, 85, 0
    ARC 255, 320, 170, 180, 2, 4
    L 255, 500, 335, 500
GLYPH 115, 505                          ; s
    ARC 252, 380, 165, 130, 1, 6
    ARC 255, 125, 180, 125, 5, 10
GLYPH 116, 350                          ; t
    L 150, 650, 150, 115
    ARC 265, 115, 115, 125, 4, 6
    L 265, -10, 325, -10
    L 40, 500, 320, 500
GLYPH 117, 565                          ; u
    L 85, 500, 85, 185
    ARC 282, 185, 197, 195, 4, 8
    L 479, 500, 479, 0
GLYPH 118, 515                          ; v
    L 30, 500, 257, 0
    L 257, 0, 485, 500
GLYPH 119, 760                          ; w
    L 25, 500, 192, 0
    L 192, 0, 380, 500
    L 380, 500, 568, 0
    L 568, 0, 735, 500
GLYPH 120, 500                          ; x
    L 50, 500, 450, 0
    L 450, 500, 50, 0
GLYPH 121, 515                          ; y
    L 30, 500, 260, 15
    L 490, 500, 145, -210
GLYPH 122, 490                          ; z
    L 60, 500, 435, 500
    L 435, 500, 55, 0
    L 55, 0, 445, 0
GLYPH 123, 340                          ; {
    C 300, 750, 160, 750, 200, 330, 90, 320
    C 90, 320, 200, 310, 160, -110, 300, -110
GLYPH 124, 200                          ; |
    L 100, 760, 100, -160
GLYPH 125, 340                          ; }
    C 40, 750, 180, 750, 140, 330, 250, 320
    C 250, 320, 140, 310, 180, -110, 40, -110
GLYPH 126, 560                          ; ~
    C 80, 260, 180, 390, 380, 170, 480, 300
GLYPH 127, 600                          ; ellipsis
    L 95, 0, 95, 1
    L 300, 0, 300, 1
    L 505, 0, 505, 1
GLYPH 128, 360                          ; single right angle quote, for breadcrumbs
    L 105, 450, 255, 250
    L 255, 250, 105, 50
GLYPH 129, 190                          ; middle dot
    L 95, 300, 95, 301
    dw GO_END

%if glyph_next != GLYPH_FIRST + GLYPH_COUNT
    %error "the font is missing glyphs"
%endif

align 8
glyph_table:
%assign glyph_i GLYPH_FIRST
%rep GLYPH_COUNT
    dq glyph_ %+ glyph_i
    %assign glyph_i glyph_i + 1
%endrep
