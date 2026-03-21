; tests/regression/mega65/05-mega65-full.asm
; Programme Mega65 complet : directives, sous-routines, Z-register, 65C02

; Constantes Mega65
SCREEN  = $0800
COLOR   = $D800
BORDER  = $D020
BGCOL   = $D021
COUNT   = 40

        .org $2001

; Stub BASIC : 10 SYS 8205
        .byte $0B,$20,$0A,$00,$9E,$38,$32,$30,$35,$00,$00,$00

; Données
msg:
        .text "MEGA65"
msglen = 6
pad:
        .fill 4, $00

; ---------- Programme principal ----------

main:
        jsr init_screen
        jsr write_msg
        jsr z_counter
        rts

; ---------- Initialiser écran ----------

init_screen:
        lda #$00
        sta BORDER
        sta BGCOL

        ; Effacer avec Z comme compteur externe
        ldz #$00
        lda #$20
clear:
        sta SCREEN,X
        inz
        tza
        tax
        cmp #COUNT
        bne clear
        rts

; ---------- Écrire message ----------

write_msg:
        ldx #$00
wloop:
        lda msg,X
        sta SCREEN,X
        inx
        cpx #msglen
        bne wloop
        rts

; ---------- Compteur Z avec STZ ----------

z_counter:
        stz BORDER          ; STZ 65C02
        ldz #$10
zloop:
        tza
        sta COLOR
        dez
        bne zloop

        ; Transfert final
        tza
        pha
        pla
        rts
