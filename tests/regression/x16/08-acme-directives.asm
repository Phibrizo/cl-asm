; tests/regression/x16/08-acme-directives.asm
; Syntaxe ACME : !to (ignoré), !cpu (ignoré), *=addr (org), !BYTE, !PET
; Ce fichier ne s'assemblait pas avant l'ajout du support de la syntaxe ACME.

!to "test.prg",cbm          ; ignoré par cl-asm (nom de sortie ACME)
!cpu 65c02                  ; ignoré par cl-asm (cible fixée en ligne de commande)

*=$0801                     ; ACME style org (équivalent à .org $0801)

; Stub BASIC : 10 SYS 2061
!BYTE $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00

start:
        LDA #$00
        STA $9F20
        RTS

; !BYTE : données brutes (valeurs numériques)
raw_data:
        !BYTE $61,$62,$63,0  ; 'a','b','c' ASCII brut, 0

; !PET : conversion PETSCII, minuscules → majuscules PETSCII (code - $20)
pet_lower:
        !PET "abc",13,0      ; a→$41 b→$42 c→$43 CR null

; !PET : majuscules → PETSCII shifted (+$80)
pet_upper:
        !PET "ABC",0         ; A→$C1 B→$C2 C→$C3 null
