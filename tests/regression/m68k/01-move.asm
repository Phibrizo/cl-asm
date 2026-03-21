; tests/regression/m68k/01-move.asm
; Motorola 68000 : instructions MOVE

        .org $0000

        ; MOVE registre → registre
        MOVE.W  D0, D1
        MOVE.L  D0, D1
        MOVE.B  D0, D1
        MOVE.W  D7, D0
        MOVE.L  A0, D0

        ; MOVEQ
        MOVEQ   #0, D0
        MOVEQ   #1, D1
        MOVEQ   #127, D7
        MOVEQ   #-1, D0

        ; MOVEA
        MOVEA.L D0, A0
        MOVEA.W D0, A1
        MOVEA.L A0, A1

        ; MOVE immédiat → registre
        MOVE.W  #$1234, D0
        MOVE.L  #$12345678, D1
        MOVE.B  #$FF, D3

        ; MOVE indirect
        MOVE.W  (A0), D0
        MOVE.W  D0, (A0)
        MOVE.W  (A0)+, D0
        MOVE.W  -(A0), D0
        MOVE.W  #$1234, (A0)
        MOVE.W  (A0)+, -(A1)

        ; MOVE déplacement
        MOVE.W  $10(A0), D0
        MOVE.W  D0, $10(A0)

        NOP
        RTS
