; tests/regression/65816/02-native-16bit.asm
; WDC 65816 : modes 16 bits A et X/Y

        .org $8000

        ; Passer en mode natif (XCE + CLC)
        clc
        xce

        ; A sur 16 bits
        .al
        lda #$1234
        lda #$FFFF
        lda #$0000
        sta $1234
        adc #$0001

        ; Revenir à 8 bits
        .as
        lda #$FF
        sta $10

        ; X/Y sur 16 bits
        .xl
        ldx #$0100
        ldy #$0200
        inx
        iny
        dex
        dey

        ; Revenir à 8 bits
        .xs
        ldx #$01
        ldy #$02

        ; BRL — branche longue (16 bits)
        brl brl_target
        nop
brl_target:
        nop

        rtl
