; tests/regression/z80/01-ld-registers.asm
; Zilog Z80 : LD registre→registre et LD registre,immédiat

        .org $8000

        ; LD reg, reg
        LD A, B
        LD A, C
        LD A, D
        LD A, E
        LD A, H
        LD A, L
        LD A, A
        LD B, C
        LD H, L
        LD D, E

        ; LD reg, imm8
        LD A, $42
        LD B, 0
        LD C, 255
        LD D, $FF
        LD E, $00
        LD H, $10
        LD L, $20

        ; LD reg16, imm16
        LD BC, $1234
        LD DE, $5678
        LD HL, $ABCD
        LD SP, $FFFE

        ; LD indirect
        LD A, (HL)
        LD (HL), A
        LD B, (HL)
        LD (HL), B
        LD (HL), $10

        ; LD A, (BC)/(DE)
        LD A, (BC)
        LD A, (DE)
        LD (BC), A
        LD (DE), A

        ; LD A, (nn) / LD (nn), A
        LD A, ($FF00)
        LD ($FF00), A

        RET
