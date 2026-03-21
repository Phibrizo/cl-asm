; tests/regression/mega65/03-mega65-program.asm
; Programme Mega65 : stub BASIC + instructions Z + 65C02

; Constantes Mega65
BORDER  = $D020
BGCOL   = $D021

        .org $2001

; Stub BASIC : 10 SYS 8205
        .byte $0B,$20,$0A,$00,$9E,$38,$32,$30,$35,$00,$00,$00

main:
        ; Initialiser le registre Z à zéro
        ldz #$00

        ; Fond et bordure noirs
        stz BORDER
        stz BGCOL

        ; Boucle avec le registre Z comme compteur
        ldz #$10
count:
        dez
        bne count

        ; Transfert A↔Z
        lda #$42
        taz
        tza

        rts
