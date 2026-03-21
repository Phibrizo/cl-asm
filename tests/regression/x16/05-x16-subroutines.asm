; tests/regression/x16/05-x16-subroutines.asm
; Sous-routines, boucles imbriquées, modes d'adressage 65C02

; Constantes
VERA_ADDR_L = $9F20
VERA_ADDR_M = $9F21
VERA_ADDR_H = $9F22
VERA_DATA0  = $9F23
ZP_PTR      = $02           ; pointeur zero-page

        .org $0801

; Stub BASIC : 10 SYS 2061
        .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00

; ---------- Programme principal ----------

main:
        jsr init_vera
        jsr fill_screen
        jsr write_msg
        rts

; ---------- Initialiser VERA ----------

init_vera:
        stz VERA_ADDR_L
        stz VERA_ADDR_M
        lda #$11            ; stride 1, bank 0
        sta VERA_ADDR_H
        rts

; ---------- Remplir écran (space) ----------

fill_screen:
        phx
        phy
        ldy #$00
outer:
        ldx #$00
inner:
        lda #$20            ; espace
        sta VERA_DATA0
        inx
        cpx #80
        bne inner
        iny
        cpy #60
        bne outer
        ply
        plx
        rts

; ---------- Écrire message via pointeur ZP ----------

MSGLEN  = 5
msg:
        .text "HELLO"

write_msg:
        ; configurer VERA pour position (0,0)
        stz VERA_ADDR_L
        stz VERA_ADDR_M
        lda #$11
        sta VERA_ADDR_H

        ; écrire via indirect zero-page
        lda #<msg
        sta ZP_PTR
        lda #>msg
        sta ZP_PTR+1

        ldy #$00
wloop:
        lda (ZP_PTR),Y
        sta VERA_DATA0
        iny
        cpy #MSGLEN
        bne wloop
        rts
