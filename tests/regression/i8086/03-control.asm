; tests/regression/i8086/03-control.asm
; Intel 8086 : sauts, appels, pile, instructions implicites

        .org $0100

        ; --- PUSH / POP reg16 ---
        PUSH AX
        PUSH BX
        PUSH CX
        PUSH DX
        PUSH SP
        PUSH BP
        PUSH SI
        PUSH DI
        POP  AX
        POP  BX
        POP  CX
        POP  DX
        POP  SP
        POP  BP
        POP  SI
        POP  DI

        ; --- PUSH / POP segments ---
        PUSH ES
        PUSH CS
        PUSH SS
        PUSH DS
        POP  ES
        POP  SS
        POP  DS

        ; --- PUSH / POP mémoire ---
        PUSH WORD PTR [BX]
        PUSH WORD PTR [SI]
        POP  WORD PTR [DI]
        POP  WORD PTR [BX+SI]

        ; --- CALL near / RET ---
        CALL subroutine
        CALL near_call
near_call:
        CALL subroutine
        RET

        ; --- Sauts conditionnels — tous les Jcc (rel8, vers label fwd) ---
        JO   lbl_jo
lbl_jo:
        JNO  lbl_jno
lbl_jno:
        JB   lbl_jb
lbl_jb:
        JNB  lbl_jnb
lbl_jnb:
        JZ   lbl_jz
lbl_jz:
        JNZ  lbl_jnz
lbl_jnz:
        JBE  lbl_jbe
lbl_jbe:
        JA   lbl_ja
lbl_ja:
        JS   lbl_js
lbl_js:
        JNS  lbl_jns
lbl_jns:
        JP   lbl_jp
lbl_jp:
        JNP  lbl_jnp
lbl_jnp:
        JL   lbl_jl
lbl_jl:
        JGE  lbl_jge
lbl_jge:
        JLE  lbl_jle
lbl_jle:
        JG   lbl_jg
lbl_jg:
        JCXZ lbl_jcxz
lbl_jcxz:

        ; --- Saut en arrière ---
back:
        NOP
        JMP SHORT back

        ; --- LOOP ---
        MOV CX, $0003
loop_start:
        DEC AX
        LOOP loop_start

        ; --- Instructions implicites 1 octet ---
        NOP
        HLT
        CLC
        STC
        CMC
        CLI
        STI
        CLD
        STD
        CBW
        CWD
        XLAT
        PUSHF
        POPF
        LAHF
        SAHF
        AAA
        AAS
        DAA
        DAS

subroutine:
        RET
