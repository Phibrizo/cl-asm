; tests/regression/mega65/01-z-register.asm
; Instructions spécifiques 45GS02 : registre Z

        .org $2001

        ; LDZ — charger le registre Z
        ldz #$00
        ldz #$FF
        ldz $1234
        ldz $1234,X

        ; INZ/DEZ — incrémenter/décrémenter Z
        inz
        dez

        ; TAZ/TZA — transferts A↔Z
        lda #$42
        taz
        tza

        rts
