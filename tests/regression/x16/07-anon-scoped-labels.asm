; tests/regression/x16/07-anon-scoped-labels.asm
; Anonymous labels (:), scoped @labels, .res, forward-ref immediate (ca65)
; Ce fichier ne s'assemblait pas avant l'implémentation de ces fonctionnalités.

        .org $0801

; Stub BASIC : 10 SYS 2061
        .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00

; --- Test anonymous labels : boucle comptée ---
main:
        ldx #5
:                       ; anonymous label (= ici : dex)
        dex
        bne :-          ; branche au : précédent

; --- Test forward-ref en mode immédiat ---
; ldx/ldy avec forward-ref : doit estimer 2 octets en passe 1
        ldx #<data      ; octet bas de l'adresse de data
        ldy #>data      ; octet haut

; --- Appels sous-routines avec @labels scoped ---
        jsr routine1
        jsr routine2

        rts

; --- routine1 avec @loop local ---
routine1:
        ldy #3
@loop:
        dey
        bne @loop       ; @loop scopé à routine1
        rts

; --- routine2 avec @loop local (différent de routine1/@loop) ---
routine2:
        ldy #2
@loop:
        dey
        bne @loop       ; @loop scopé à routine2
        rts

; --- Test .res (réserve N octets) ---
buffer: .res 4

; --- Test .byte avec string inline et forward-ref ---
data:   .byte "Hi",0
