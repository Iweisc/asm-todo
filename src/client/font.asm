; The font: every glyph is a few pen strokes along its centerline, in font
; units (1000 per em, y up, baseline at 0, x-height 500, caps 700). text.asm
; rasterizes them with a round pen at whatever size and weight it needs, so
; one drawing covers every text style.
;
;   GLYPH code, advance     starts a glyph. Codes must come in order.
;   L x0, y0, x1, y1        a straight stroke
;   C x0, y0, ... x3, y3    a cubic Bezier stroke
;   ARC cx, cy, rx, ry, from, to
;                           an elliptical arc, counterclockwise, with angles in
;                           steps of 45 degrees (0 east, 2 north, 4 west, 6 south)
;   E cx, cy, rx, ry        a whole ellipse

%define GO_END          0
%define GO_LINE         1
%define GO_CUBIC        2
%define GLYPH_FIRST     32
%define GLYPH_COUNT     98              ; ASCII, then the three below
%define GLYPH_ELLIPSIS  127
%define GLYPH_CHEVRON   128
%define GLYPH_MIDDOT    129

; Sets trig_c and trig_s to 1000 * cos and sin of %1 * 45 degrees.
%macro TRIG 1
    %assign trig_i ((%1) + 16) % 8
    %if trig_i == 0
        %assign trig_c 1000
        %assign trig_s 0
    %elif trig_i == 1
        %assign trig_c 707
        %assign trig_s 707
    %elif trig_i == 2
        %assign trig_c 0
        %assign trig_s 1000
    %elif trig_i == 3
        %assign trig_c -707
        %assign trig_s 707
    %elif trig_i == 4
        %assign trig_c -1000
        %assign trig_s 0
    %elif trig_i == 5
        %assign trig_c -707
        %assign trig_s -707
    %elif trig_i == 6
        %assign trig_c 0
        %assign trig_s -1000
    %else
        %assign trig_c 707
        %assign trig_s -707
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

; Each 45 degree step becomes one cubic. 265 / 1000 is 4/3 * tan(45 / 4).
%macro ARC 6
    %assign arc_a %5
    %rep %6 - %5
        TRIG arc_a
        %assign arc_x0 %1 + (%3 * trig_c) // 1000
        %assign arc_y0 %2 + (%4 * trig_s) // 1000
        %assign arc_tx0 -(%3 * trig_s) // 1000
        %assign arc_ty0 (%4 * trig_c) // 1000
        TRIG arc_a + 1
        %assign arc_x3 %1 + (%3 * trig_c) // 1000
        %assign arc_y3 %2 + (%4 * trig_s) // 1000
        %assign arc_tx3 -(%3 * trig_s) // 1000
        %assign arc_ty3 (%4 * trig_c) // 1000
        C arc_x0, arc_y0, arc_x0 + (arc_tx0 * 265) // 1000, arc_y0 + (arc_ty0 * 265) // 1000, arc_x3 - (arc_tx3 * 265) // 1000, arc_y3 - (arc_ty3 * 265) // 1000, arc_x3, arc_y3
        %assign arc_a arc_a + 1
    %endrep
%endmacro

%macro E 4
    ARC %1, %2, %3, %4, 0, 8
%endmacro

section .rodata
align 2
font_glyphs:

GLYPH 32, 260                           ; space
GLYPH 33, 180                           ; !
    L 90, 700, 90, 190
    L 90, 0, 90, 1
GLYPH 34, 280                           ; "
    L 80, 700, 80, 520
    L 200, 700, 200, 520
GLYPH 35, 560                           ; #
    L 210, 660, 150, 40
    L 420, 660, 360, 40
    L 70, 440, 500, 440
    L 50, 250, 480, 250
GLYPH 36, 600                           ; $
    ARC 300, 527, 195, 173, 1, 6
    ARC 300, 177, 205, 177, 5, 10
    L 300, 770, 300, -70
GLYPH 37, 700                           ; %
    E 170, 560, 110, 140
    E 530, 140, 110, 140
    L 560, 700, 140, 0
GLYPH 38, 640                           ; &
    ARC 255, 575, 125, 125, -1, 5
    L 167, 487, 590, 0
    C 343, 487, 40, 280, 120, -10, 330, 0
    L 330, 0, 560, 260
GLYPH 39, 160                           ; '
    L 80, 700, 80, 520
GLYPH 40, 300                           ; (
    ARC 330, 320, 230, 460, 3, 5
GLYPH 41, 300                           ; )
    ARC -30, 320, 230, 460, -1, 1
GLYPH 42, 500                           ; *
    L 250, 700, 250, 420
    L 130, 640, 370, 480
    L 370, 640, 130, 480
GLYPH 43, 560                           ; +
    L 280, 100, 280, 500
    L 80, 300, 480, 300
GLYPH 44, 190                           ; ,
    L 95, 40, 55, -110
GLYPH 45, 400                           ; -
    L 70, 280, 330, 280
GLYPH 46, 180                           ; .
    L 90, 0, 90, 1
GLYPH 47, 400                           ; /
    L 40, -80, 360, 740
GLYPH 48, 580                           ; 0
    E 290, 350, 210, 358
GLYPH 49, 580                           ; 1
    L 320, 0, 320, 700
    L 320, 700, 150, 580
GLYPH 50, 580                           ; 2
    ARC 290, 490, 200, 210, -1, 4
    L 431, 342, 90, 0
    L 90, 0, 500, 0
GLYPH 51, 580                           ; 3
    ARC 280, 530, 190, 170, -2, 3
    ARC 285, 180, 205, 180, -3, 2
GLYPH 52, 580                           ; 4
    L 400, 0, 400, 700
    L 400, 700, 60, 200
    L 60, 200, 520, 200
GLYPH 53, 580                           ; 5
    L 470, 700, 150, 700
    L 150, 700, 135, 390
    ARC 300, 215, 205, 215, -3, 3
GLYPH 54, 580                           ; 6
    E 290, 215, 205, 215
    C 85, 215, 85, 560, 220, 700, 420, 690
GLYPH 55, 580                           ; 7
    L 70, 700, 510, 700
    L 510, 700, 190, 0
GLYPH 56, 580                           ; 8
    E 290, 535, 175, 165
    E 290, 185, 205, 185
GLYPH 57, 580                           ; 9
    E 290, 485, 205, 215
    C 495, 485, 495, 140, 360, 0, 160, 10
GLYPH 58, 180                           ; :
    L 90, 0, 90, 1
    L 90, 480, 90, 481
GLYPH 59, 190                           ; ;
    L 95, 40, 55, -110
    L 95, 480, 95, 481
GLYPH 60, 560                           ; <
    L 480, 560, 80, 300
    L 80, 300, 480, 40
GLYPH 61, 560                           ; =
    L 80, 390, 480, 390
    L 80, 210, 480, 210
GLYPH 62, 560                           ; >
    L 80, 560, 480, 300
    L 480, 300, 80, 40
GLYPH 63, 500                           ; ?
    ARC 260, 520, 170, 180, -2, 4
    L 260, 340, 260, 200
    L 260, 0, 260, 1
GLYPH 64, 800                           ; @
    E 390, 300, 115, 135
    L 505, 430, 505, 210
    C 505, 210, 505, 120, 650, 130, 700, 300
    ARC 390, 300, 310, 330, 0, 7
GLYPH 65, 660                           ; A
    L 40, 0, 330, 700
    L 330, 700, 620, 0
    L 140, 240, 520, 240
GLYPH 66, 610                           ; B
    L 90, 0, 90, 700
    L 90, 700, 330, 700
    ARC 330, 527, 160, 173, 6, 10
    L 90, 354, 345, 354
    ARC 345, 177, 185, 177, 6, 10
    L 90, 0, 345, 0
GLYPH 67, 700                           ; C
    ARC 380, 350, 300, 358, 1, 7
GLYPH 68, 680                           ; D
    L 90, 0, 90, 700
    L 90, 700, 300, 700
    ARC 300, 350, 300, 350, 6, 10
    L 90, 0, 300, 0
GLYPH 69, 580                           ; E
    L 90, 0, 90, 700
    L 90, 700, 500, 700
    L 90, 355, 460, 355
    L 90, 0, 510, 0
GLYPH 70, 550                           ; F
    L 90, 0, 90, 700
    L 90, 700, 500, 700
    L 90, 355, 450, 355
GLYPH 71, 740                           ; G
    ARC 380, 350, 300, 358, 1, 8
    L 680, 350, 450, 350
GLYPH 72, 680                           ; H
    L 90, 0, 90, 700
    L 590, 0, 590, 700
    L 90, 355, 590, 355
GLYPH 73, 180                           ; I
    L 90, 0, 90, 700
GLYPH 74, 520                           ; J
    L 420, 700, 420, 190
    ARC 230, 190, 190, 190, 5, 8
GLYPH 75, 620                           ; K
    L 90, 0, 90, 700
    L 560, 700, 90, 240
    L 270, 420, 590, 0
GLYPH 76, 520                           ; L
    L 90, 700, 90, 0
    L 90, 0, 480, 0
GLYPH 77, 800                           ; M
    L 90, 0, 90, 700
    L 90, 700, 400, 120
    L 400, 120, 710, 700
    L 710, 700, 710, 0
GLYPH 78, 680                           ; N
    L 90, 0, 90, 700
    L 90, 700, 590, 0
    L 590, 0, 590, 700
GLYPH 79, 760                           ; O
    E 380, 350, 310, 358
GLYPH 80, 600                           ; P
    L 90, 0, 90, 700
    L 90, 700, 330, 700
    ARC 330, 505, 175, 195, 6, 10
    L 90, 310, 330, 310
GLYPH 81, 760                           ; Q
    E 380, 350, 310, 358
    L 450, 170, 650, -30
GLYPH 82, 620                           ; R
    L 90, 0, 90, 700
    L 90, 700, 330, 700
    ARC 330, 505, 175, 195, 6, 10
    L 90, 310, 330, 310
    L 300, 310, 560, 0
GLYPH 83, 640                           ; S
    ARC 320, 527, 215, 173, 1, 6
    ARC 320, 177, 225, 177, 5, 10
GLYPH 84, 600                           ; T
    L 30, 700, 570, 700
    L 300, 700, 300, 0
GLYPH 85, 680                           ; U
    L 90, 700, 90, 260
    ARC 340, 260, 250, 260, 4, 8
    L 590, 260, 590, 700
GLYPH 86, 660                           ; V
    L 30, 700, 330, 0
    L 330, 0, 630, 700
GLYPH 87, 910                           ; W
    L 30, 700, 230, 0
    L 230, 0, 455, 700
    L 455, 700, 680, 0
    L 680, 0, 880, 700
GLYPH 88, 630                           ; X
    L 50, 700, 580, 0
    L 580, 700, 50, 0
GLYPH 89, 640                           ; Y
    L 40, 700, 320, 360
    L 600, 700, 320, 360
    L 320, 360, 320, 0
GLYPH 90, 620                           ; Z
    L 60, 700, 560, 700
    L 560, 700, 60, 0
    L 60, 0, 570, 0
GLYPH 91, 280                           ; [
    L 200, 740, 100, 740
    L 100, 740, 100, -100
    L 100, -100, 200, -100
GLYPH 92, 400                           ; backslash
    L 40, 740, 360, -80
GLYPH 93, 280                           ; ]
    L 80, 740, 180, 740
    L 180, 740, 180, -100
    L 180, -100, 80, -100
GLYPH 94, 560                           ; ^
    L 100, 400, 280, 700
    L 280, 700, 460, 400
GLYPH 95, 500                           ; _
    L 0, -90, 500, -90
GLYPH 96, 300                           ; `
    L 100, 720, 180, 620
GLYPH 97, 560                           ; a
    E 265, 250, 205, 258
    L 470, 500, 470, 0
GLYPH 98, 560                           ; b
    E 295, 250, 205, 258
    L 90, 740, 90, 0
GLYPH 99, 510                           ; c
    ARC 270, 250, 205, 258, 1, 7
GLYPH 100, 560                          ; d
    E 265, 250, 205, 258
    L 470, 740, 470, 0
GLYPH 101, 545                          ; e
    L 65, 250, 475, 250
    ARC 270, 250, 205, 258, 0, 7
GLYPH 102, 340                          ; f
    L 145, 0, 145, 590
    ARC 295, 590, 150, 150, 1, 4
    L 50, 500, 290, 500
GLYPH 103, 560                          ; g
    E 265, 250, 205, 258
    L 470, 500, 470, -60
    ARC 265, -60, 205, 150, 5, 8
GLYPH 104, 560                          ; h
    L 90, 740, 90, 0
    ARC 280, 310, 190, 190, 0, 4
    L 470, 310, 470, 0
GLYPH 105, 180                          ; i
    L 90, 500, 90, 0
    L 90, 690, 90, 691
GLYPH 106, 200                          ; j
    L 110, 500, 110, -80
    ARC 0, -80, 110, 120, 5, 8
    L 110, 690, 110, 691
GLYPH 107, 480                          ; k
    L 90, 740, 90, 0
    L 430, 500, 90, 180
    L 210, 290, 450, 0
GLYPH 108, 180                          ; l
    L 90, 740, 90, 0
GLYPH 109, 760                          ; m
    L 90, 500, 90, 0
    ARC 235, 330, 145, 170, 0, 4
    L 380, 330, 380, 0
    ARC 525, 330, 145, 170, 0, 4
    L 670, 330, 670, 0
GLYPH 110, 560                          ; n
    L 90, 500, 90, 0
    ARC 280, 310, 190, 190, 0, 4
    L 470, 310, 470, 0
GLYPH 111, 540                          ; o
    E 270, 250, 210, 258
GLYPH 112, 560                          ; p
    E 295, 250, 205, 258
    L 90, 500, 90, -210
GLYPH 113, 560                          ; q
    E 265, 250, 205, 258
    L 470, 500, 470, -210
GLYPH 114, 390                          ; r
    L 90, 500, 90, 0
    ARC 260, 320, 170, 180, 1, 4
GLYPH 115, 505                          ; s
    ARC 255, 375, 170, 125, 1, 6
    ARC 255, 125, 175, 125, 5, 10
GLYPH 116, 390                          ; t
    L 170, 690, 170, 90
    ARC 290, 90, 120, 90, 4, 7
    L 50, 500, 330, 500
GLYPH 117, 560                          ; u
    L 90, 500, 90, 190
    ARC 280, 190, 190, 190, 4, 8
    L 470, 500, 470, 0
GLYPH 118, 520                          ; v
    L 50, 500, 260, 0
    L 260, 0, 470, 500
GLYPH 119, 730                          ; w
    L 45, 500, 205, 0
    L 205, 0, 365, 500
    L 365, 500, 525, 0
    L 525, 0, 685, 500
GLYPH 120, 520                          ; x
    L 70, 500, 450, 0
    L 450, 500, 70, 0
GLYPH 121, 530                          ; y
    L 50, 500, 265, 20
    L 480, 500, 160, -210
GLYPH 122, 520                          ; z
    L 70, 500, 450, 500
    L 450, 500, 70, 0
    L 70, 0, 460, 0
GLYPH 123, 340                          ; {
    C 300, 740, 160, 740, 200, 330, 90, 320
    C 90, 320, 200, 310, 160, -100, 300, -100
GLYPH 124, 200                          ; |
    L 100, 760, 100, -160
GLYPH 125, 340                          ; }
    C 40, 740, 180, 740, 140, 330, 250, 320
    C 250, 320, 140, 310, 180, -100, 40, -100
GLYPH 126, 560                          ; ~
    C 80, 270, 180, 400, 380, 180, 480, 310
GLYPH 127, 600                          ; ellipsis
    L 90, 0, 90, 1
    L 300, 0, 300, 1
    L 510, 0, 510, 1
GLYPH 128, 360                          ; single right angle quote, for breadcrumbs
    L 100, 450, 260, 250
    L 260, 250, 100, 50
GLYPH 129, 180                          ; middle dot
    L 90, 300, 90, 301
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
