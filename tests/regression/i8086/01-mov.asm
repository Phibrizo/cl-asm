; tests/regression/i8086/01-mov.asm
; Intel 8086 : MOV — toutes les formes compatibles NASM

        .org $0100

        ; --- MOV reg16, imm16 (#xB8+reg) ---
        MOV AX, $1234
        MOV CX, $5678
        MOV DX, $ABCD
        MOV BX, $0001
        MOV SP, $0200
        MOV BP, $0300
        MOV SI, $0010
        MOV DI, $0020

        ; --- MOV reg8, imm8 (#xB0+reg) ---
        MOV AL, $00
        MOV AL, $FF
        MOV AL, $42
        MOV CL, $08
        MOV DL, $01
        MOV BL, $FE
        MOV AH, $80
        MOV CH, $0F
        MOV DH, $AA
        MOV BH, $55

        ; --- MOV reg16, [mem] — formes mod=00 sans déplacement ---
        MOV AX, [BX]
        MOV AX, [SI]
        MOV AX, [DI]
        MOV AX, [BX+SI]
        MOV AX, [BX+DI]
        MOV AX, [BP+SI]
        MOV AX, [BP+DI]

        MOV CX, [BX]
        MOV DX, [SI]
        MOV BX, [DI]
        MOV SI, [BX+SI]
        MOV DI, [BX+DI]

        ; --- MOV reg8, [mem] ---
        MOV AL, [BX]
        MOV BL, [SI]
        MOV CL, [DI]
        MOV AH, [BX+SI]

        ; --- MOV [mem], reg16 ---
        MOV [BX], AX
        MOV [SI], CX
        MOV [DI], DX
        MOV [BX+SI], BX
        MOV [BX+DI], SP
        MOV [BP+SI], BP
        MOV [BP+DI], SI

        ; --- MOV [mem], reg8 ---
        MOV [BX], AL
        MOV [SI], BL
        MOV [DI], CL
        MOV [BX+SI], AH

        ; --- MOV [mem], imm ---
        MOV WORD PTR [BX],    $1234
        MOV WORD PTR [SI],    $5678
        MOV WORD PTR [BX+SI], $ABCD
        MOV BYTE PTR [BX],    $42
        MOV BYTE PTR [DI],    $FF

        ; --- MOV reg16, sreg ---
        MOV AX, ES
        MOV BX, CS
        MOV CX, SS
        MOV DX, DS

        ; --- MOV sreg, reg16 ---
        MOV ES, AX
        MOV SS, BX
        MOV DS, CX

        RET
