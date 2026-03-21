; tests/regression/x16/04-directives-65c02.asm
; Directives et expressions sur X16/65C02

; Constantes X16
VERA_ADDR_L = $9F20
VERA_ADDR_M = $9F21
VERA_ADDR_H = $9F22
VERA_DATA0  = $9F23
ROWS        = 60
COLS        = 80
VRAM_BASE   = $0000

        .org $0801

        ; .byte
        .byte $00, $FF
        .byte 0, 127, 255
        .byte 'X', '1', '6'

        ; .word
        .word $0000
        .word $FFFF
        .word VERA_ADDR_L
        .word VRAM_BASE

        ; .text
        .text "HELLO X16"

        ; .fill
        .fill 4, $00
        .fill 4, $EA        ; NOP x4

        ; Expressions lo/hi
        lda #<VERA_ADDR_L
        ldx #>VERA_ADDR_L
        lda #ROWS
        lda #COLS
        lda #<(VRAM_BASE + $100)
        lda #>(VRAM_BASE + $100)

        ; Instructions 65C02 avec expressions
        stz VERA_ADDR_L
        stz VERA_ADDR_M
        lda #ROWS - 1
        sta $00

        rts
