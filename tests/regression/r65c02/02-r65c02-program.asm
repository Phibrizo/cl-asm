; tests/regression/r65c02/02-r65c02-program.asm
; Programme R65C02 : drapeaux en mémoire avec bit ops Rockwell

; Registres fictifs (zero-page)
FLAGS   = $10
STATUS  = $11
RESULT  = $12

        .org $0801

main:
        ; Initialiser FLAGS à $AA
        lda #$AA
        sta FLAGS

        ; Mettre tous les bits de STATUS à zéro
        lda #$00
        sta STATUS

        ; Activer les bits 0, 2, 4, 6 de STATUS
        smb0 STATUS
        smb2 STATUS
        smb4 STATUS
        smb6 STATUS

        ; Lire FLAGS et modifier via bit ops
        rmb1 FLAGS
        rmb3 FLAGS
        smb5 FLAGS

        ; Tester bit 0 de STATUS → doit être set
        bbs0 STATUS, bit0_set
        lda #$00
        bra done
bit0_set:
        lda #$01

done:
        sta RESULT

        ; Tester bit 1 de STATUS → doit être reset
        bbr1 STATUS, bit1_clr
        lda #$FF
        bra end
bit1_clr:
        lda #$00
end:
        rts
