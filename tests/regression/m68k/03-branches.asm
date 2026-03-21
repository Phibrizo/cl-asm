; tests/regression/m68k/03-branches.asm
; Motorola 68000 : branchements et sauts

        .org $0000

        ; Bcc — branches conditionnelles (suffix .W pour forcer word form)
        CMP.W   #1, D0
        BEQ.W   fwd_beq
        BGT.W   fwd_bgt
        BLT.W   fwd_blt
        BNE.W   fwd_bne
        BGE.W   fwd_bge
        BLE.W   fwd_ble
        BCC.W   fwd_bcc
        BCS.W   fwd_bcs
        BMI.W   fwd_bmi
        BPL.W   fwd_bpl

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
        BRA.W   bra_target
        NOP
bra_target: NOP

        ; DBcc — boucle décrémentale
        MOVE.W  #9, D0
loop:
        SUBQ.W  #1, D0
        DBRA    D0, loop

        ; JSR/RTS
        JSR     my_sub
        NOP
        BRA.W   done

my_sub:
        MOVE.W  #$42, D0
        RTS

        ; LEA
        LEA     $1234, A0
        LEA     $10(A0), A1

done:
        RTS
