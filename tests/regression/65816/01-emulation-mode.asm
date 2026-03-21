; tests/regression/65816/01-emulation-mode.asm
; WDC 65816 en mode émulation : instructions 6502/65C02 de base

        .org $8000

        ; Mode émulation : A, X, Y sur 8 bits

        ; Instructions 6502 standard
        lda #$FF
        ldx #$00
        ldy #$7F
        sta $10
        stx $20
        sty $30
        tax
        tay
        txa
        tya
        inx
        iny
        dex
        dey
        nop
        clc
        sec
        sei
        cli

        ; Instructions 65C02
        stz $10
        phx
        plx
        phy
        ply

        ; Branches
        bcc fwd
        bne fwd
fwd:    nop

        ; Spécifiques 65816 (mode émulation)
        phb
        plb
        phd
        pld
        phk

        rts
