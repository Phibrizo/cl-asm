; tests/regression/i8086/04-shifts-misc.asm
; Intel 8086 : décalages, LEA, XCHG, IN/OUT, INT, divers

        .org $0100

        ; --- Décalages / rotations par 1 ---
        SHL AX,  1
        SHR AX,  1
        SAR AX,  1
        ROL AX,  1
        ROR AX,  1
        RCL AX,  1
        RCR AX,  1
        SAL AX,  1

        SHL AL,  1
        SHR BL,  1
        SAR CL,  1
        ROL DL,  1

        SHL WORD PTR [BX], 1
        SHR WORD PTR [SI], 1
        SAR BYTE PTR [DI], 1

        ; --- Décalages / rotations par CL ---
        SHL BX,  CL
        SHR CX,  CL
        SAR DX,  CL
        ROL SI,  CL
        ROR DI,  CL
        RCL BP,  CL
        RCR SP,  CL

        SHL BL,  CL
        SHR CH,  CL

        SHL WORD PTR [BX+SI], CL
        SHR BYTE PTR [BX],    CL

        ; --- XCHG AX, r16 (forme courte #x90+reg) ---
        XCHG AX, AX
        XCHG AX, CX
        XCHG AX, DX
        XCHG AX, BX
        XCHG AX, SP
        XCHG AX, BP
        XCHG AX, SI
        XCHG AX, DI
        XCHG BX, AX
        XCHG DI, AX

        ; --- XCHG [mem], reg ---
        XCHG [BX],    AX
        XCHG [SI],    BX
        XCHG [BX+SI], CX

        ; --- LEA ---
        LEA AX, [BX]
        LEA BX, [SI]
        LEA CX, [DI]
        LEA DX, [BX+SI]
        LEA SI, [BX+DI]
        LEA DI, [BP+SI]
        LEA BP, [BP+DI]

        ; --- LDS / LES ---
        LDS SI, [BX]
        LDS DI, [BX+SI]
        LES AX, [SI]
        LES BX, [BX+DI]

        ; --- IN / OUT port fixe ---
        IN  AL, $21
        IN  AX, $21
        OUT $21, AL
        OUT $21, AX

        ; --- IN / OUT via DX ---
        IN  AL, DX
        IN  AX, DX
        OUT DX, AL
        OUT DX, AX

        ; --- INT ---
        INT $00
        INT $10
        INT $21
        INTO

        ; --- Divers ---
        NOP
        HLT
        WAIT

        RET
