; tests/regression/m68k/04-alu-imm-alias.asm
; Motorola 68000 : AND/OR/EOR #imm comme alias de ANDI/ORI/EORI

        .org $0000

        ; AND #imm — alias ANDI
        AND.W   #$FF, D0
        AND.W   #$FF00, D1
        AND.L   #$1234, D2

        ; OR #imm — alias ORI
        OR.W    #$0F, D0
        OR.L    #$FFFF, D1

        ; EOR #imm — alias EORI
        EOR.W   #$0F0F, D0
        EOR.L   #$12345678, D1

        NOP
        RTS
