; -*- coding: utf-8 -*-
; target: x16
; examples/x16-debug.asm
;
; Programme de diagnostic X16 : s'arrete proprement avec BRK
; pour lancer le moniteur et inspecter l'etat du CPU.
;
; Assemblage :
;   ./cl-asm examples/x16-debug.asm
;
; Utilisation :
;   LOAD "X16-DEBUG.PRG"
;   RUN
;
; Attendu : le moniteur s'ouvre avec PC pointe apres le BRK.
; On peut alors inspecter A, X, Y, SP, et les registres VERA.
;
; Si le moniteur ne s'ouvre PAS, le programme plante avant BRK
; -> le probleme est dans le stub BASIC ou l'adresse SYS.
;
; Progression :
;   LDA #$11 -> A=$11 avant d'ecrire dans VERA
;   LDA #$22 -> A=$22 apres avoir ecrit dans VERA
;   BRK      -> moniteur
; En inspectant A dans le moniteur on sait jusqu'ou on est arrive.

VERA_ADDR_LO   = $9F20
VERA_ADDR_HI   = $9F21
VERA_ADDR_BANK = $9F22
VERA_DATA0     = $9F23

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
        ; Marqueur 1 : on est arrive ici si A=$11 dans le moniteur
        lda #$11

        ; Etape 1 : configurer VERA
        lda #$00
        sta VERA_ADDR_LO
        sta VERA_ADDR_HI
        lda #$10                    ; stride=1
        sta VERA_ADDR_BANK

        ; Marqueur 2 : VERA configure, A=$22
        lda #$22

        ; Etape 2 : ecrire un seul caractere 'H' + couleur
        lda #'H'
        sta VERA_DATA0
        lda #$61
        sta VERA_DATA0

        ; Marqueur 3 : ecriture VERA OK, A=$33
        lda #$33

        ; Arreter proprement -> moniteur
        brk
