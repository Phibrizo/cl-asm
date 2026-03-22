; tests/regression/i8080/04-control.asm
; Intel 8080 : sauts, appels, retours, pile, RST, divers

        .org $0100

        ; --- JMP inconditionnel (3 octets) ---
        JMP skip_jmp
skip_jmp:

        ; --- Sauts conditionnels (3 octets chacun) ---
        JNZ skip_jnz
skip_jnz:
        JZ  skip_jz
skip_jz:
        JNC skip_jnc
skip_jnc:
        JC  skip_jc
skip_jc:
        JPO skip_jpo
skip_jpo:
        JPE skip_jpe
skip_jpe:
        JP  skip_jp
skip_jp:
        JM  skip_jm
skip_jm:

        ; --- CALL / RET (3 octets / 1 octet) ---
        CALL sub1
        RET

        ; --- Appels conditionnels (3 octets chacun) ---
        CNZ sub1
        CZ  sub1
        CNC sub1
        CC  sub1
        CPO sub1
        CPE sub1
        CP  sub1
        CM  sub1

        ; --- Retours conditionnels (1 octet chacun) ---
        RNZ
        RZ
        RNC
        RC
        RPO
        RPE
        RP
        RM

        ; --- PUSH / POP (1 octet chacun) ---
        PUSH B
        PUSH D
        PUSH H
        PUSH PSW
        POP  B
        POP  D
        POP  H
        POP  PSW

        ; --- RST n (1 octet chacun, n=0..7) ---
        RST 0
        RST 1
        RST 2
        RST 3
        RST 4
        RST 5
        RST 6
        RST 7

        ; --- Instructions diverses (1 octet) ---
        NOP
        HLT
        DI
        EI
        XCHG
        XTHL
        PCHL
        SPHL

sub1:
        RET
