; tests/regression/m68k/05-motorola-syntax.asm
; Motorola 68000 : syntaxe étendue (EQU, DC.B/W/L, EVEN, * commentaires)
; Ce fichier ne s'assemblait pas avant l'ajout du support de ces fonctionnalités.

        .org $0000

* Constantes via EQU (syntaxe Motorola)
CR      EQU     $0D
LF      EQU     $0A
NULL    EQU     $00
MAXVAL  EQU     255

* Code : quelques instructions utilisant les constantes
        MOVE.W  #MAXVAL, D0     ; référence à EQU dans une instruction
        MOVE.W  #CR, D1         ; référence à EQU
        MOVE.W  #LF, D2
        NOP

* Données : DC.B avec strings et constantes EQU mélangées
MSG:
        DC.B    "Hello World", CR, LF, NULL

        EVEN                    ; alignement sur mot

NUMS:
        DC.W    $1234, $5678

TABLE:
        DC.L    $DEADBEEF

        RTS
