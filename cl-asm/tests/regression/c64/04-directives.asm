; tests/regression/c64/04-directives.asm
; Directives : constantes, .byte, .word, .text, .fill, expressions

        .org $0801

; Constantes
ROWS    = 25
COLS    = 40
SCREEN  = $0400
COLOR   = $D800
BASE    = $C000

        ; .byte - valeurs diverses
        .byte $00
        .byte $FF, $FE, $FD
        .byte 0, 127, 255
        .byte 'A', 'Z'

        ; .word (little-endian)
        .word $0000
        .word $FFFF
        .word $0801
        .word SCREEN

        ; .text
        .text "HELLO"
        .text "WORLD"

        ; .fill
        .fill 4, $00
        .fill 8, $FF

        ; Expressions dans les operandes
        lda #<SCREEN        ; octet bas
        ldx #>SCREEN        ; octet haut
        lda #ROWS
        lda #COLS
