; tests/regression/x16/02-branches.asm
; Branches 6502 + BRA inconditionnelle (65C02)

        .org $0801

        ; Branches forward classiques
        bcc fwd_bcc
        bcs fwd_bcs
        beq fwd_beq
        bne fwd_bne
        bmi fwd_bmi
        bpl fwd_bpl
        bvc fwd_bvc
        bvs fwd_bvs

fwd_bcc: nop
fwd_bcs: nop
fwd_beq: nop
fwd_bne: nop
fwd_bmi: nop
fwd_bpl: nop
fwd_bvc: nop
fwd_bvs: nop

        ; BRA — branche inconditionnelle
        bra fwd_bra
        nop
fwd_bra: nop

        ; Boucle arrière avec BNE
loop:
        dex
        bne loop

        ; Boucle arrière avec BRA
loop2:
        dey
        bra loop2

        rts
