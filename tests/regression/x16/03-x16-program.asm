; tests/regression/x16/03-x16-program.asm
; Programme X16 minimaliste : stub BASIC + quelques instructions 65C02

; Constantes X16
VERA_ADDR_L = $9F20
VERA_ADDR_M = $9F21
VERA_ADDR_H = $9F22
VERA_DATA0  = $9F23

        .org $0801

; Stub BASIC : 10 SYS 2061
        .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00

main:
        ; Réinitialiser VERA addr
        stz VERA_ADDR_L
        stz VERA_ADDR_M
        lda #$11            ; bank 0, incr=1
        sta VERA_ADDR_H

        ; Écrire quelques octets via VERA DATA0
        lda #$20            ; espace
        ldx #$08
write_loop:
        sta VERA_DATA0
        dex
        bne write_loop

        ; Utilisation de PHY/PLY
        ldy #$05
        phy
        ldy #$00
        ply

        ; Incrémente accumulateur
        lda #$00
        inc A
        inc A

        rts
