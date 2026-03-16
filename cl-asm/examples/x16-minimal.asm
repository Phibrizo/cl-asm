; -*- coding: utf-8 -*-
; target: x16
; examples/x16-minimal.asm
;
; Affiche "HELLO X16" via CHROUT (ROM KERNAL, sans acces direct VERA).
; Plus simple et plus fiable que l'acces direct a VERA.
;
; Assemblage : ./cl-asm examples/x16-minimal.asm
; Chargement : LOAD "X16-MINIMAL.PRG" : RUN
; Quitter    : touche STOP/PAUSE

; Vecteurs KERNAL
CHROUT  = $FFD2             ; affiche le caractere dans A
STOP    = $FFE1             ; teste si STOP est presse (Z=1 si oui)

; --------------------------------------------------------------------------
;  Stub BASIC : 10 SYS 2061
; --------------------------------------------------------------------------

        .org $0801

        .byte $0B, $08
        .byte $0A, $00
        .byte $9E
        .byte $32, $30, $36, $31   ; "2061"
        .byte $00
        .byte $00, $00

; --------------------------------------------------------------------------
;  Code a $080D
; --------------------------------------------------------------------------

main:
        ; Afficher "HELLO X16" via CHROUT (ROM KERNAL)
        ; Pas besoin de toucher a VERA ou aux IRQ
        ldx #$00
write:
        lda msg,X
        beq done
        jsr CHROUT              ; afficher le caractere
        inx
        bra write               ; BRA -- instruction 65C02

done:
        ; Nouvelle ligne
        lda #$0D
        jsr CHROUT

        ; Attendre STOP
loop:
        jsr STOP
        bne loop                ; Z=0 = pas STOP -> reboucler
        rts                     ; Z=1 = STOP -> retour BASIC

; --------------------------------------------------------------------------
;  Message
; --------------------------------------------------------------------------

msg:
        .text "HELLO X16"
        .byte $00
