; tests/regression/mega65/02-misc-m65.asm
; Instructions diverses 45GS02 : ASR, MAP, EOM

        .org $2001

        ; ASR — arithmetic shift right (zero-page)
        asr $10
        asr $10,X

        ; MAP/EOM — remapping mémoire Mega65
        map
        eom

        rts
