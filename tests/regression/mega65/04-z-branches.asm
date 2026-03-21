; tests/regression/mega65/04-z-branches.asm
; Registre Z en contexte de boucles et branches

        .org $2001

; Constantes
COUNT   = 16
SCREEN  = $0800

; ---------- Boucle décroissante avec DEZ ----------

count_down:
        ldz #COUNT
loop1:
        dez
        bne loop1           ; BNE teste Z register (flag Z)

; ---------- Boucle croissante avec INZ ----------

count_up:
        ldz #$00
loop2:
        inz
        cpx #COUNT          ; X inchangé, on utilise BNE sur Z flag
        tza
        cmp #COUNT
        bne loop2

; ---------- Transfert A/Z dans une boucle ----------

xfer_loop:
        ldx #$08
        ldz #$00
xloop:
        tza
        sta SCREEN,X        ; stocker Z dans écran
        inz
        dex
        bne xloop

; ---------- Fin : transfert Z → A ----------

        ldz #$05
        dez
        tza

        rts
