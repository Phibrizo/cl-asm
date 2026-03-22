; tests/regression/i8080/01-mov-mvi.asm
; Intel 8080 : MOV, MVI, LXI, INR, DCR, INX, DCX, DAD

        .org $0100

        ; --- MOV r, r' (1 octet chacun) ---
        MOV A, A
        MOV A, B
        MOV A, C
        MOV A, D
        MOV A, E
        MOV A, H
        MOV A, L
        MOV B, A
        MOV B, C
        MOV C, D
        MOV D, E
        MOV E, H
        MOV H, L
        MOV L, A

        ; --- MOV avec M (indirect HL) ---
        MOV A, M
        MOV M, A
        MOV B, M
        MOV M, B
        MOV H, M
        MOV M, L

        ; --- MVI r, n (2 octets chacun) ---
        MVI A, $00
        MVI A, $FF
        MVI A, $42
        MVI B, $01
        MVI C, $02
        MVI D, $03
        MVI E, $04
        MVI H, $10
        MVI L, $20
        MVI M, $55

        ; --- LXI rp, nn (3 octets chacun) ---
        LXI B, $0000
        LXI B, $1234
        LXI D, $5678
        LXI H, $ABCD
        LXI H, $0000
        LXI SP, $FFFF
        LXI SP, $F000

        ; --- INR r (1 octet) ---
        INR A
        INR B
        INR C
        INR D
        INR E
        INR H
        INR L
        INR M

        ; --- DCR r (1 octet) ---
        DCR A
        DCR B
        DCR C
        DCR D
        DCR E
        DCR H
        DCR L
        DCR M

        ; --- INX rp (1 octet) ---
        INX B
        INX D
        INX H
        INX SP

        ; --- DCX rp (1 octet) ---
        DCX B
        DCX D
        DCX H
        DCX SP

        ; --- DAD rp (1 octet) ---
        DAD B
        DAD D
        DAD H
        DAD SP

        RET
