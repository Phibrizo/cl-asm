; tests/regression/m68k/03-branches.asm
; Motorola 68000 : branchements et sauts

        .org $0000

        ; Bcc — branches conditionnelles
        CMP.W   #0, D0
        BEQ     fwd_beq
        BGT     fwd_bgt
        BLT     fwd_blt
        BNE     fwd_bne
        BGE     fwd_bge
        BLE     fwd_ble
        BCC     fwd_bcc
        BCS     fwd_bcs
        BMI     fwd_bmi
        BPL     fwd_bpl

fwd_beq: NOP
fwd_bgt: NOP
fwd_blt: NOP
fwd_bne: NOP
fwd_bge: NOP
fwd_ble: NOP
fwd_bcc: NOP
fwd_bcs: NOP
fwd_bmi: NOP
fwd_bpl: NOP

        ; BRA — branche inconditionnelle
        BRA     bra_target
        NOP
bra_target: NOP

        ; DBcc — boucle décrémentale
        MOVE.W  #9, D0
loop:
        SUBQ.W  #1, D0
        DBRA    D0, loop

        ; JSR/RTS
        JSR     sub
        NOP
        BRA     end

sub:
        MOVE.W  #$42, D0
        RTS

        ; LEA
        LEA     $1234, A0
        LEA     $10(A0), A1

end:
        RTS
