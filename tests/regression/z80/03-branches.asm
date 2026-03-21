; tests/regression/z80/03-branches.asm
; Zilog Z80 : sauts, appels, boucles

        .org $8000

        ; JP absolu
        JP  $9000
        JP  NZ, $9000
        JP  Z,  $9000
        JP  NC, $9000
        JP  C,  $9000

        ; JP (HL)
        JP  (HL)

        ; JR relatif
        JR  fwd_jr
fwd_jr: NOP

        JR  NZ, fwd_nz
        JR  Z,  fwd_z
        JR  NC, fwd_nc
        JR  C,  fwd_c
fwd_nz: NOP
fwd_z:  NOP
fwd_nc: NOP
fwd_c:  NOP

        ; CALL/RET
        CALL $9000
        CALL NZ, $9000
        CALL Z,  $9000

        ; DJNZ — boucle avec compteur B
        LD   B, 10
loop:
        DJNZ loop

        ; RET conditionnel
        RET NZ
        RET Z
        RET NC
        RET C
        RET
