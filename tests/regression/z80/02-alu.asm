; tests/regression/z80/02-alu.asm
; Zilog Z80 : opérations arithmétiques et logiques

        .org $8000

        ; ADD/ADC
        ADD A, B
        ADD A, C
        ADD A, D
        ADD A, H
        ADD A, $10
        ADC A, B
        ADC A, $FF

        ; SUB/SBC
        SUB B
        SUB C
        SUB $10
        SBC A, B
        SBC A, $10

        ; AND/OR/XOR
        AND B
        AND $0F
        OR  C
        OR  $F0
        XOR D
        XOR $FF
        XOR A           ; mettre A à zéro

        ; CP — compare
        CP  B
        CP  $42

        ; INC/DEC registres 8 bits
        INC A
        INC B
        INC C
        DEC A
        DEC B
        DEC H

        ; INC/DEC registres 16 bits
        INC BC
        INC DE
        INC HL
        INC SP
        DEC BC
        DEC HL

        ; ADD HL, rr
        ADD HL, BC
        ADD HL, DE
        ADD HL, HL
        ADD HL, SP

        ; Rotation/décalage
        RLCA
        RRCA
        RLA
        RRA

        ; DAA, CPL, SCF, CCF
        DAA
        CPL
        SCF
        CCF

        RET
