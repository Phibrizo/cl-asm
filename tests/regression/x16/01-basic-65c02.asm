; tests/regression/x16/01-basic-65c02.asm
; Instructions spécifiques 65C02 : BRA, STZ, PHX/PLX/PHY/PLY, INC/DEC A, TRB/TSB

        .org $0801

        ; Branche inconditionnelle
        bra skip
        nop
skip:

        ; STZ — store zero
        stz $10
        stz $10,X
        stz $1234
        stz $1234,X

        ; Empile/dépile X et Y
        phx
        plx
        phy
        ply

        ; INC/DEC accumulateur
        inc A
        dec A

        ; TRB/TSB — test and reset/set bits
        trb $10
        trb $1234
        tsb $10
        tsb $1234

        ; Modes zero-page indirect (sans index)
        lda ($10)
        sta ($20)
        adc ($30)
        and ($40)
        ora ($50)
        eor ($60)
        cmp ($70)
        sbc ($80)

        ; BIT étendu
        bit #$FF
        bit $10,X
        bit $1234,X

        ; JMP indirect indexé X
        jmp ($1234,X)

        rts
