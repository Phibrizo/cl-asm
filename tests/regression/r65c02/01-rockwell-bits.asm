; tests/regression/r65c02/01-rockwell-bits.asm
; Instructions Rockwell 65C02 : RMB, SMB, BBR, BBS

        .org $0801

; RMB — Reset Memory Bit
        rmb0 $10
        rmb1 $10
        rmb2 $10
        rmb3 $10
        rmb4 $10
        rmb5 $10
        rmb6 $10
        rmb7 $10

; SMB — Set Memory Bit
        smb0 $20
        smb1 $20
        smb2 $20
        smb3 $20
        smb4 $20
        smb5 $20
        smb6 $20
        smb7 $20

; BBR — Branch on Bit Reset
        rmb0 $10
        bbr0 $10, skip0
        nop
skip0:  nop
        bbr7 $10, skip7
        nop
skip7:  nop

; BBS — Branch on Bit Set
        smb3 $20
        bbs3 $20, skip3
        nop
skip3:  nop
        bbs5 $20, skip5
        nop
skip5:  nop

        rts
