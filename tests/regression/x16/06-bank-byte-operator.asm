; tests/regression/x16/06-bank-byte-operator.asm
; Opérateur ^ (bank byte, bits 16-23) — syntaxe ca65
; Ce fichier ne s'assemblait pas avant l'ajout du support de ^.

        .org $0801

; Stub BASIC : 10 SYS 2061
        .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00

; Constantes avec adresses sur 24 bits (Commander X16)
VERA_ADDR_L = $9F20
VERA_ADDR_M = $9F21
VERA_ADDR_H = $9F22
VERA_DATA0  = $9F23

; Une adresse dans la banque 1 VRAM ($1F000)
VRAM_TILE   = $1F000

main:
        ; Octet bas de VRAM_TILE → octet lo
        lda #<VRAM_TILE         ; $00
        sta VERA_ADDR_L
        ; Octet haut de VRAM_TILE → octet hi
        lda #>VRAM_TILE         ; $F0
        sta VERA_ADDR_M
        ; Octet banque de VRAM_TILE → opérateur ^ (bits 16-23)
        lda #^VRAM_TILE         ; $01
        sta VERA_ADDR_H
        rts
