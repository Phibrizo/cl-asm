; tests/regression/c64/03-branches.asm
; Branches conditionnelles et labels

        .org $0801

        ; Branches forward
        bcc fwd_bcc
        bcs fwd_bcs
        beq fwd_beq
        bne fwd_bne
        bmi fwd_bmi
        bpl fwd_bpl
        bvc fwd_bvc
        bvs fwd_bvs

fwd_bcc:
        nop
fwd_bcs:
        nop
fwd_beq:
        nop
fwd_bne:
        nop
fwd_bmi:
        nop
fwd_bpl:
        nop
fwd_bvc:
        nop
fwd_bvs:
        nop

        ; Branche backward
loop:
        dex
        bne loop

        ; Sous-routine
        jsr sub
        rts

sub:
        lda #$00
        rts
