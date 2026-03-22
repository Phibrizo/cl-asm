; tests/regression/i8080/02-alu.asm
; Intel 8080 : opérations ALU (registre et immédiat)

        .org $0100

        ; --- ADD r (1 octet) ---
        ADD A
        ADD B
        ADD C
        ADD D
        ADD E
        ADD H
        ADD L
        ADD M

        ; --- ADC r (1 octet) ---
        ADC A
        ADC B
        ADC C
        ADC D
        ADC E
        ADC H
        ADC L
        ADC M

        ; --- SUB r (1 octet) ---
        SUB A
        SUB B
        SUB C
        SUB D
        SUB E
        SUB H
        SUB L
        SUB M

        ; --- SBB r (1 octet) ---
        SBB A
        SBB B
        SBB C
        SBB D
        SBB E
        SBB H
        SBB L
        SBB M

        ; --- ANA r (1 octet) ---
        ANA A
        ANA B
        ANA C
        ANA D
        ANA E
        ANA H
        ANA L
        ANA M

        ; --- XRA r (1 octet) ---
        XRA A
        XRA B
        XRA C
        XRA D
        XRA E
        XRA H
        XRA L
        XRA M

        ; --- ORA r (1 octet) ---
        ORA A
        ORA B
        ORA C
        ORA D
        ORA E
        ORA H
        ORA L
        ORA M

        ; --- CMP r (1 octet) ---
        CMP A
        CMP B
        CMP C
        CMP D
        CMP E
        CMP H
        CMP L
        CMP M

        ; --- ALU immédiat (2 octets chacun) ---
        ADI $00
        ADI $FF
        ADI $42
        ACI $01
        ACI $80
        SUI $10
        SUI $FF
        SBI $05
        SBI $00
        ANI $0F
        ANI $F0
        ANI $FF
        XRI $AA
        XRI $55
        XRI $00
        ORI $01
        ORI $80
        ORI $FF
        CPI $00
        CPI $42
        CPI $FF

        ; --- Rotations / opérations accumulateur (1 octet) ---
        RLC
        RRC
        RAL
        RAR
        DAA
        CMA
        STC
        CMC

        RET
