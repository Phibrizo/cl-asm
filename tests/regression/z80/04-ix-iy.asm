; tests/regression/z80/04-ix-iy.asm
; Zilog Z80 : registres d'index IX et IY

        .org $8000

        ; LD IX/IY
        LD IX, $1234
        LD IY, $5678

        ; LD reg, (IX+d) / LD reg, (IY+d)
        LD A, (IX+0)
        LD A, (IX+$10)
        LD B, (IX+1)
        LD H, (IY+2)
        LD L, (IY+$7F)

        ; LD (IX+d), reg
        LD (IX+0), A
        LD (IX+$10), B
        LD (IY+0), H

        ; LD (IX+d), n
        LD (IX+0), $42
        LD (IY+$10), $42

        ; ADD/ADC avec IX
        ADD A, (IX+0)
        ADD A, (IY+$10)
        SUB (IX+0)

        ; INC/DEC (IX+d)
        INC (IX+0)
        DEC (IY+$10)

        ; ADD IX/IY (HL non supporté avec IY — utiliser IY lui-même)
        ADD IX, BC
        ADD IX, DE
        ADD IY, BC
        ADD IY, IY

        RET
