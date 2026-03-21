; tests/regression/65816/03-long-addressing.asm
; WDC 65816 : adressage 24 bits, JSL/JML, MVN/MVP

        .org $8000

        ; JSL/RTL — sous-routine longue
        jsl sub_long
        nop

        ; JML — saut long
        jml long_target

long_target:
        ; Adressage direct long
        .al
        lda $7E0000         ; banque $7E, adresse $0000
        sta $7E0002
        .as

        ; MVN/MVP — block move
        ; MVN dst_bank, src_bank
        mvn $7E, $7F
        mvp $7E, $7F

        ; PEA — push effective address (immédiat)
        pea #$1234

        rts

sub_long:
        lda #$42
        rtl
