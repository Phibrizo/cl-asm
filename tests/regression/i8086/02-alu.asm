; tests/regression/i8086/02-alu.asm
; Intel 8086 : ALU, INC/DEC, unaires, ADC/SBB

        .org $0100

        ; --- ADD AX, imm16 — forme courte accumulateur (#x05) ---
        ADD AX, 5
        ADD AX, $80
        ADD AX, $FF
        ADD AX, $1234
        ADD AX, $FFFF

        ; --- SUB/AND/OR/XOR/CMP AX, imm16 ---
        SUB AX, $0100
        AND AX, $FF00
        OR  AX, $000F
        XOR AX, $FFFF
        CMP AX, $8000

        ; --- ALU AL, imm8 — forme courte accumulateur (#x04, #x2C…) ---
        ADD AL, 5
        ADD AL, $80
        SUB AL, $FF
        AND AL, $0F
        OR  AL, $F0
        XOR AL, $AA
        CMP AL, $42

        ; --- ALU non-AX reg16, imm16 (#x81) ---
        ADD BX, $1234
        SUB CX, $0001
        AND DX, $FF00
        OR  SI, $000F
        XOR DI, $FFFF
        CMP BX, $8000

        ; --- ALU non-AL reg8, imm8 (#x80) ---
        ADD BL, $42
        SUB CL, $01
        AND DL, $0F
        OR  BH, $F0
        CMP CH, $55

        ; --- ADC/SBB AX, imm16 ---
        ADC AX, $0001
        SBB AX, $FFFF

        ; --- ADC/SBB AL, imm8 ---
        ADC AL, $01
        SBB AL, $FF

        ; --- ADC/SBB reg16, imm16 ---
        ADC BX, $1234
        SBB CX, $5678

        ; --- ALU reg16, [mem] (reg ← mem) ---
        ADD AX, [BX]
        SUB AX, [SI]
        AND AX, [DI]
        OR  BX, [BX+SI]
        XOR CX, [BX+DI]
        CMP DX, [BP+SI]

        ; --- ALU [mem], reg16 (mem ← reg) ---
        ADD [BX], AX
        SUB [SI], BX
        AND [DI], CX
        OR  [BX+SI], DX

        ; --- INC / DEC reg16 (forme courte 1 octet) ---
        INC AX
        INC BX
        INC CX
        INC DX
        INC SP
        INC BP
        INC SI
        INC DI
        DEC AX
        DEC BX
        DEC SI
        DEC DI

        ; --- INC / DEC mémoire ---
        INC WORD PTR [BX]
        INC WORD PTR [SI]
        INC BYTE PTR [DI]
        DEC WORD PTR [BX+SI]
        DEC BYTE PTR [BX]

        ; --- NEG / NOT ---
        NEG AX
        NEG BX
        NOT CX
        NOT DX
        NEG WORD PTR [BX]
        NOT BYTE PTR [SI]

        ; --- MUL / DIV / IMUL / IDIV ---
        MUL BX
        MUL WORD PTR [SI]
        DIV CX
        DIV BYTE PTR [BX]
        IMUL DX
        IMUL WORD PTR [DI]
        IDIV BX
        IDIV BYTE PTR [SI]

        RET
