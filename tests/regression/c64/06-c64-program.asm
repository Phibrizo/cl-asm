; tests/regression/c64/06-c64-program.asm
; Programme C64 complet avec stub BASIC : efface l'ecran et change les couleurs

; Constantes C64
SCREEN  = $0400
COLOR   = $D800
BORDER  = $D020
BGCOL   = $D021

        .org $0801

; Stub BASIC : 10 SYS 2061
        .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00

main:
        ; Bordure et fond noirs
        lda #$00
        sta BORDER
        sta BGCOL

        ; Effacer l'ecran avec des espaces
        lda #$20
        ldx #$00
clear:
        sta SCREEN,X
        sta SCREEN+$100,X
        sta SCREEN+$200,X
        sta SCREEN+$2E8,X
        inx
        bne clear

        ; Couleur blanche pour tout le texte
        lda #$01
        ldx #$00
color_lp:
        sta COLOR,X
        sta COLOR+$100,X
        sta COLOR+$200,X
        sta COLOR+$2E8,X
        inx
        bne color_lp

        ; Ecrire "HELLO" en haut a gauche
        lda #$08            ; H
        sta SCREEN
        lda #$05            ; E
        sta SCREEN+1
        lda #$0C            ; L
        sta SCREEN+2
        lda #$0C            ; L
        sta SCREEN+3
        lda #$0F            ; O
        sta SCREEN+4

        rts
