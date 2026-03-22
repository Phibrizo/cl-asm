; tests/regression/i8080/03-memory.asm
; Intel 8080 : LDA/STA/LHLD/SHLD/LDAX/STAX + directives

        .org $0100

        ; --- LDA / STA (3 octets) ---
        LDA $1000
        LDA $FFFF
        LDA $0200
        STA $1000
        STA $FFFF
        STA $0300

        ; --- LHLD / SHLD (3 octets) ---
        LHLD $2000
        LHLD $ABCD
        SHLD $2000
        SHLD $ABCD

        ; --- LDAX / STAX (1 octet, B ou D seulement) ---
        LDAX B
        LDAX D
        STAX B
        STAX D

        ; --- IN / OUT (2 octets) ---
        IN $00
        IN $3C
        IN $FF
        OUT $00
        OUT $01
        OUT $FF

        ; --- Directives de données ---
data_byte:
        .byte $DE
        .byte $AD, $BE, $EF
        .byte $00, $FF, $80, $7F

data_word:
        .word $0000
        .word $1234
        .word $FFFF
        .word $8000

        ; NOP de fin
        NOP
        RET
