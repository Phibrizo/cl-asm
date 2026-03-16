; tests/regression/c64/02-addressing.asm
; Tous les modes d'adressage 6502

        .org $0801

        ; Immédiat
        lda #$FF
        ldx #$00
        ldy #$7F
        cmp #$80
        and #$0F
        ora #$F0
        eor #$AA
        adc #$01
        sbc #$01

        ; Zero-page
        lda $10
        sta $20
        ldx $30
        stx $40
        ldy $50
        sty $60
        inc $70
        dec $80
        asl $90
        lsr $A0
        rol $B0
        ror $C0

        ; Zero-page,X
        lda $10,X
        sta $20,X
        ldy $30,X
        sty $40,X
        inc $50,X
        dec $60,X

        ; Zero-page,Y
        ldx $10,Y
        stx $20,Y

        ; Absolu
        lda $1234
        sta $5678
        ldx $ABCD
        stx $EF01
        ldy $2345
        sty $6789
        inc $ABCE
        dec $ABCF

        ; Absolu,X
        lda $1234,X
        sta $5678,X
        ldy $9ABC,X

        ; Absolu,Y
        lda $1234,Y
        sta $5678,Y
        ldx $9ABC,Y

        ; (Indirect,X)
        lda ($10,X)
        sta ($20,X)

        ; (Indirect),Y
        lda ($10),Y
        sta ($20),Y

        ; Indirect (JMP seulement)
        jmp ($FFFC)
