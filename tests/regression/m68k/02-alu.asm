; tests/regression/m68k/02-alu.asm
; Motorola 68000 : opérations ALU

        .org $0000

        ; ADD/SUB
        ADD.W   D0, D1
        ADD.L   D0, D1
        ADDI.W  #$10, D0
        ADDI.L  #$100, D1
        ADDQ.W  #1, D0
        ADDQ.L  #4, D1
        SUB.W   D0, D1
        SUBI.W  #$10, D0
        SUBQ.W  #1, D0

        ; AND/OR/EOR
        AND.W   D0, D1
        ANDI.W  #$FF, D0
        OR.W    D0, D1
        ORI.W   #$0F, D0
        EOR.W   D0, D1
        EORI.W  #$0F0F, D0

        ; CMP
        CMP.W   D0, D1
        CMP.W   #$10, D0
        CMP.L   #1, D0

        ; MUL/DIV
        MULU    D0, D1
        MULS    D0, D1
        DIVU    D0, D1
        DIVS    D0, D1

        ; Shifts
        ASL.W   #2, D0
        ASR.W   #2, D0
        LSL.W   #2, D1
        LSR.W   #2, D1
        ROL.W   #2, D0
        ROR.W   #2, D0

        ; NOT/NEG/CLR
        NOT.W   D0
        NEG.W   D0
        CLR.W   D0

        NOP
        RTS
