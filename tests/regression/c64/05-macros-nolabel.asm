; tests/regression/c64/05-macros-nolabel.asm
; Macros textuelles sans labels locaux (compatible ca65 et acme)

        .org $0801

.macro SAVE_AXY
        pha
        txa
        pha
        tya
        pha
.endmacro

.macro RESTORE_AXY
        pla
        tay
        pla
        tax
        pla
.endmacro

.macro SET_BORDER color
        lda #color
        sta $D020
.endmacro

.macro SET_SCREEN color
        lda #color
        sta $D021
.endmacro

        SAVE_AXY
        lda #$01
        RESTORE_AXY

        SET_BORDER 0
        SET_SCREEN 0
        SET_BORDER 1
        SET_SCREEN 6

        rts
