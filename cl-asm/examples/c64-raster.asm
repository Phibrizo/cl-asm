; -*- coding: utf-8 -*-
; target: 6502
; examples/c64-raster.asm
;
; Raster bar pour Commodore 64
; Affiche un arc-en-ciel de couleurs sur la bordure en synchronisant
; sur le faisceau electron (raster) via une interruption VIC-II.
;
; Assemblage depuis le REPL :
;   (let ((b (cl-asm/backend.6502:assemble-file
;              "examples/c64-raster.asm" :origin #x0801)))
;     (cl-asm/emit:write-prg b "examples/c64-raster.prg"
;                             :load-address #x0801))
;
; Chargement sur C64 / VICE :
;   LOAD "C64-RASTER.PRG",8,1 : RUN
;   x64 examples/c64-raster.prg

; --------------------------------------------------------------------------
;  Constantes materielles C64
; --------------------------------------------------------------------------

BORDER_COLOR  = $D020       ; couleur de bordure
BG_COLOR      = $D021       ; couleur de fond
RASTER_LINE   = $D012       ; ligne raster courante (bits 0-7)
CONTROL_REG   = $D011       ; controle VIC-II (bit 7 = bit 8 du raster)
IRQ_STATUS    = $D019       ; status IRQ VIC-II
IRQ_ENABLE    = $D01A       ; activation IRQ VIC-II
CIA1_ICR      = $DC0D       ; CIA1 interrupt control register
IRQ_VECTOR    = $0314       ; vecteur IRQ noyau C64

; Palette C64
BLACK         = 0
WHITE         = 1
RED           = 2
CYAN          = 3
PURPLE        = 4
GREEN         = 5
BLUE          = 6
YELLOW        = 7
ORANGE        = 8
LIGHT_RED     = 10
LIGHT_BLUE    = 14

; Parametres du raster bar
RASTER_START  = 50          ; premiere ligne du bar

; --------------------------------------------------------------------------
;  Options de compilation
; --------------------------------------------------------------------------

DEBUG         = 0           ; 1 = affiche compteur IRQ en haut a gauche

; --------------------------------------------------------------------------
;  Stub BASIC : 10 SYS 2064
; --------------------------------------------------------------------------

        .org $0801

        .byte $0B, $08              ; pointeur ligne suivante
        .byte $0A, $00              ; numero de ligne : 10
        .byte $9E                   ; token SYS
        .byte $32, $30, $36, $34   ; "2064" en ASCII
        .byte $00                   ; fin de ligne
        .byte $00, $00              ; fin du programme BASIC

; $0810 = 2064 : point d'entree

; --------------------------------------------------------------------------
;  Macros
; --------------------------------------------------------------------------

; WAIT_RASTER line : boucle jusqu'a ce que le raster atteigne LINE
.macro WAIT_RASTER line
__wait:
        lda RASTER_LINE
        cmp #line
        bne __wait
.endmacro

; SET_BORDER col : change la couleur de bordure
.macro SET_BORDER col
        lda #col
        sta BORDER_COLOR
.endmacro

; --------------------------------------------------------------------------
;  Programme principal
; --------------------------------------------------------------------------

main:
        sei                         ; couper les interruptions

        ; Desactiver les IRQ CIA (timers) pour eviter les conflits
        lda #$7F
        sta CIA1_ICR

        ; Installer notre gestionnaire d'IRQ
        lda #<raster_irq
        sta IRQ_VECTOR
        lda #>raster_irq
        sta IRQ_VECTOR + 1

        ; Programmer le VIC-II : IRQ a la ligne RASTER_START
        lda #RASTER_START
        sta RASTER_LINE
        lda CONTROL_REG
        and #$7F                    ; bit 7 = 0 (bit 8 du raster = 0)
        sta CONTROL_REG

        ; Activer l'IRQ raster
        lda #$01
        sta IRQ_ENABLE

        ; Fond noir
        lda #BLACK
        sta BG_COLOR

.if DEBUG
        ; Initialiser le compteur d'IRQ visible
        lda #$30                    ; caractere '0'
        sta $0400
.endif

        cli                         ; reactiver les interruptions

; Boucle principale
loop:
        jmp loop


; --------------------------------------------------------------------------
;  Routine d'interruption raster
; --------------------------------------------------------------------------

raster_irq:
        pha                         ; sauvegarder A, X, Y
        txa
        pha
        tya
        pha

        ; Acquitter l'IRQ VIC-II
        lda #$01
        sta IRQ_STATUS

        ; Bandes de couleur - une macro par bande
        SET_BORDER YELLOW
        WAIT_RASTER 58
        SET_BORDER ORANGE
        WAIT_RASTER 66
        SET_BORDER LIGHT_RED
        WAIT_RASTER 74
        SET_BORDER RED
        WAIT_RASTER 82
        SET_BORDER PURPLE
        WAIT_RASTER 90
        SET_BORDER BLUE
        WAIT_RASTER 98
        SET_BORDER CYAN
        WAIT_RASTER 106
        SET_BORDER GREEN

        ; Fin du bar
        WAIT_RASTER 114
        SET_BORDER BLACK

.if DEBUG
        inc $0400
.endif

        ; Reprogrammer l'IRQ pour la prochaine frame
        lda #RASTER_START
        sta RASTER_LINE

        pla                         ; restaurer Y, X, A
        tay
        pla
        tax
        pla
        rti
