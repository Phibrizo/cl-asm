; tests/regression/c64/01-basic.asm
; Instructions de base 6502 : implied, accumulator, immediate

        .org $0801

        ; Implied
        nop
        clc
        sec
        cli
        sei
        clv
        cld
        sed
        tax
        txa
        tay
        tya
        tsx
        txs
        pha
        pla
        php
        plp
        inx
        dex
        iny
        dey
        rts
        rti
        brk

        ; Accumulator
        asl A
        lsr A
        rol A
        ror A
