; -*- coding: utf-8 -*-
; include-main.asm — Exemple d'utilisation de .include (C64 / MOS 6502)
;
; Démontre l'inclusion d'un fichier source externe via la directive .include.
; Les sous-routines et constantes de include-utils.asm sont disponibles
; immédiatement après le .include, comme si elles étaient écrites inline.
;
; Assemblage :
;   ./cl-asm examples/include-main.asm -o /tmp/include-main.prg
;   x64sc /tmp/include-main.prg   (ou VICE via drag & drop)


        .org $0801

; --- Stub BASIC : 10 SYS 2064 ---
        .byte $0B, $08          ; pointeur ligne suivante
        .byte $0A, $00          ; numéro de ligne 10
        .byte $9E               ; token SYS
        .byte $32, $30, $36, $34  ; "2064" (= $0810 en ASCII)
        .byte $00, $00, $00     ; fin du programme BASIC

; --- Inclusion des utilitaires partagés ---
;     Constantes et sous-routines disponibles dès ici :
;       BORDER_COLOR, BG_COLOR, SCREEN, SPACE_CHAR
;       clear_screen, set_border
        .include "include-utils.asm"

; --- Programme principal ---
start:
        ; Effacer l'écran
        JSR clear_screen

        ; Bord bleu clair (14), fond noir (0)
        LDA #14
        LDX #0
        JSR set_border

        ; Écrire 'H' 'I' '!' sur l'écran (codes PETSCII)
        LDA #$08                ; 'H' en PETSCII
        STA SCREEN
        LDA #$09                ; 'I'
        STA SCREEN+1
        LDA #$1B                ; '!'
        STA SCREEN+2

        RTS
