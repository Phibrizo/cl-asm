; -*- coding: utf-8 -*-
; include-utils.asm — Sous-routines partagées (inclus via .include)
;
; Ce fichier est conçu pour être inclus dans un programme principal :
;   .include "include-utils.asm"
;
; Constantes et sous-routines exportées :
;   BORDER_COLOR ($D020) — registre couleur du bord C64
;   BG_COLOR     ($D021) — registre couleur du fond C64
;   SCREEN       ($0400) — adresse de la mémoire vidéo C64
;
;   clear_screen   — remplit l'écran avec l'espace PETSCII ($20)
;   set_border     — couleur du bord = A, fond = X


; --- Constantes ---
BORDER_COLOR = $D020
BG_COLOR     = $D021
SCREEN       = $0400
SPACE_CHAR   = $20          ; espace PETSCII

; --- clear_screen : remplit les 1000 caractères de l'écran avec ' '
; Entrée  : rien
; Modifie : A, X
clear_screen:
        LDA #SPACE_CHAR
        LDX #$00
.loop:
        STA SCREEN,X
        STA SCREEN+$100,X
        STA SCREEN+$200,X
        STA SCREEN+$300,X
        INX
        BNE .loop           ; 256 × 4 colonnes = 1000 octets (+ 24 surplus)
        RTS

; --- set_border : couleur bord/fond
; Entrée  : A = couleur bord (0-15), X = couleur fond (0-15)
; Modifie : rien
set_border:
        STA BORDER_COLOR
        STX BG_COLOR
        RTS
