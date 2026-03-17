; -*- coding: utf-8 -*-
; target: x16
; examples/x16-hello.asm
;
; Hello World pour Commander X16
; Affiche "HELLO, X16!" via CHROUT (ROM KERNAL).
; Illustre les instructions 65C02 : BRA, STZ, PHY/PLY, INC A.
;
; Assemblage : ./cl-asm examples/x16-hello.asm
; Chargement : LOAD "X16-HELLO.PRG" : RUN
; Quitter    : touche STOP/PAUSE

CHROUT  = $FFD2             ; affiche le caractere dans A
STOP    = $FFE1             ; teste si STOP est presse (Z=1 si oui)

; --------------------------------------------------------------------------
;  Constantes
; --------------------------------------------------------------------------

BORDER  = $02               ; code CHROUT pour changer la couleur de bordure

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
        ; Effacer l'ecran (code CHROUT $93)
        lda #$93
        jsr CHROUT

        ; Afficher le message principal
        ldx #$00
write:
        lda msg,X
        beq next
        jsr CHROUT
        inx
        bra write               ; BRA -- instruction 65C02

next:
        ; Nouvelle ligne
        lda #$0D
        jsr CHROUT

        ; Afficher un compteur en utilisant INC A (65C02)
        ; "Compteur : 1 2 3 4 5"
        ldx #$00
write2:
        lda msg2,X
        beq count
        jsr CHROUT
        inx
        bra write2

count:
        ; Afficher 1 a 5 avec INC A (instruction 65C02)
        lda #$00
        inc A                   ; INC A -- instruction 65C02
        inc A
        inc A
        inc A
        inc A                   ; A = 5

        ; Afficher chiffres de A jusqu'a 1
        ldx #5
digit:
        txa
        ora #$30                ; convertir en ASCII
        jsr CHROUT
        lda #' '
        jsr CHROUT
        dex                     ; DEX -- 6502 classique
        bne digit               ; BNE -- 6502 classique

        ; Nouvelle ligne
        lda #$0D
        jsr CHROUT

        ; Utiliser STZ (65C02) pour initialiser une ZP sans toucher $00/$01
        stz $10                 ; STZ zero-page -- instruction 65C02
        stz $11
        stz $12

        ; Message final
        ldx #$00
write3:
        lda msg3,X
        beq wait
        jsr CHROUT
        inx
        bra write3              ; BRA -- instruction 65C02

wait:
        ; Attendre STOP avec PHY/PLY (65C02) comme delai visible
        phy                     ; PHY -- instruction 65C02
        ldy #$FF
delay:
        dey
        bne delay
        ply                     ; PLY -- instruction 65C02

        jsr STOP
        bne wait                ; Z=0 = pas STOP -> reboucler
        rts                     ; Z=1 = STOP -> retour BASIC

; --------------------------------------------------------------------------
;  Messages
; --------------------------------------------------------------------------

msg:
        .text "HELLO, X16!"
        .byte $00

msg2:
        .text "COMPTEUR : "
        .byte $00

msg3:
        .text "65C02 OK - STOP POUR QUITTER"
        .byte $00
