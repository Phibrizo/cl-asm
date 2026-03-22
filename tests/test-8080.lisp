; -*- coding: utf-8 -*-
;;; tests/test-8080.lisp
;;;
;;; Tests unitaires pour le backend Intel 8080.

(defpackage #:cl-asm/test.i8080
  (:use #:cl #:cl-asm/backend.i8080)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.i8080)


;;; --------------------------------------------------------------------------
;;;  Infra de test
;;; --------------------------------------------------------------------------

(defvar *pass* 0)
(defvar *fail* 0)
(defvar *failures* '())

(defmacro check (description form)
  `(let ((result (handler-case ,form
                   (error (e)
                     (format t "~&  ERREUR inattendue dans [~A] : ~A~%"
                             ,description e)
                     nil))))
     (if result
         (progn (incf *pass*) (format t "~&  OK  ~A~%" ,description))
         (progn (incf *fail*)
                (push ,description *failures*)
                (format t "~&  KO  ~A~%" ,description)))))

(defmacro check-error (description condition-type form)
  `(let ((fired nil))
     (handler-case ,form
       (,condition-type () (setf fired t))
       (error (e)
         (format t "~&  ERREUR inattendue dans [~A] : ~A~%" ,description e)))
     (if fired
         (progn (incf *pass*)
                (format t "~&  OK  ~A (erreur attendue)~%" ,description))
         (progn (incf *fail*)
                (push ,description *failures*)
                (format t "~&  KO  ~A (erreur NON declenchee)~%" ,description)))))

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&~%[~A]~%" ',name)
     ,@body))

(defun asm (src &key (origin 0))
  "Assemble une chaîne source Intel 8080 et retourne un vecteur d'octets."
  (assemble-string-i8080 src :origin origin))

(defun bytes= (result &rest expected)
  "Compare le résultat avec la séquence d'octets attendus."
  (and (= (length result) (length expected))
       (every #'= result expected)))


;;; --------------------------------------------------------------------------
;;;  Tests : instructions implied / 1 octet
;;; --------------------------------------------------------------------------

(deftest test/implied
  (check "NOP"  (bytes= (asm "NOP")  #x00))
  (check "HLT"  (bytes= (asm "HLT")  #x76))
  (check "RET"  (bytes= (asm "RET")  #xC9))
  (check "DI"   (bytes= (asm "DI")   #xF3))
  (check "EI"   (bytes= (asm "EI")   #xFB))
  (check "PCHL" (bytes= (asm "PCHL") #xE9))
  (check "SPHL" (bytes= (asm "SPHL") #xF9))
  (check "XCHG" (bytes= (asm "XCHG") #xEB))
  (check "XTHL" (bytes= (asm "XTHL") #xE3))
  (check "RLC"  (bytes= (asm "RLC")  #x07))
  (check "RRC"  (bytes= (asm "RRC")  #x0F))
  (check "RAL"  (bytes= (asm "RAL")  #x17))
  (check "RAR"  (bytes= (asm "RAR")  #x1F))
  (check "DAA"  (bytes= (asm "DAA")  #x27))
  (check "CMA"  (bytes= (asm "CMA")  #x2F))
  (check "STC"  (bytes= (asm "STC")  #x37))
  (check "CMC"  (bytes= (asm "CMC")  #x3F)))

;;; --------------------------------------------------------------------------
;;;  Tests : retours conditionnels
;;; --------------------------------------------------------------------------

(deftest test/conditional-returns
  (check "RNZ" (bytes= (asm "RNZ") #xC0))
  (check "RZ"  (bytes= (asm "RZ")  #xC8))
  (check "RNC" (bytes= (asm "RNC") #xD0))
  (check "RC"  (bytes= (asm "RC")  #xD8))
  (check "RPO" (bytes= (asm "RPO") #xE0))
  (check "RPE" (bytes= (asm "RPE") #xE8))
  (check "RP"  (bytes= (asm "RP")  #xF0))
  (check "RM"  (bytes= (asm "RM")  #xF8)))

;;; --------------------------------------------------------------------------
;;;  Tests : MOV
;;; --------------------------------------------------------------------------

(deftest test/mov
  ;; MOV d,s = $40 | (d<<3) | s
  (check "MOV A,A" (bytes= (asm "MOV A,A") #x7F))  ; 64+(7*8)+7 = 127
  (check "MOV A,B" (bytes= (asm "MOV A,B") #x78))  ; 64+(7*8)+0 = 120
  (check "MOV A,C" (bytes= (asm "MOV A,C") #x79))
  (check "MOV B,A" (bytes= (asm "MOV B,A") #x47))  ; 64+(0*8)+7 = 71
  (check "MOV B,B" (bytes= (asm "MOV B,B") #x40))
  (check "MOV H,L" (bytes= (asm "MOV H,L") #x65))  ; 64+(4*8)+5 = 101
  (check "MOV M,A" (bytes= (asm "MOV M,A") #x77))  ; 64+(6*8)+7 = 119
  (check "MOV A,M" (bytes= (asm "MOV A,M") #x7E))  ; 64+(7*8)+6 = 126
  (check "MOV D,E" (bytes= (asm "MOV D,E") #x53)))  ; 64+(2*8)+3 = 83

;;; --------------------------------------------------------------------------
;;;  Tests : MVI
;;; --------------------------------------------------------------------------

(deftest test/mvi
  ;; MVI r,n = ($06|(r<<3)) n
  (check "MVI B,$12" (bytes= (asm "MVI B,$12") #x06 #x12))
  (check "MVI C,$34" (bytes= (asm "MVI C,$34") #x0E #x34))
  (check "MVI D,$56" (bytes= (asm "MVI D,$56") #x16 #x56))
  (check "MVI E,$78" (bytes= (asm "MVI E,$78") #x1E #x78))
  (check "MVI H,$9A" (bytes= (asm "MVI H,$9A") #x26 #x9A))
  (check "MVI L,$BC" (bytes= (asm "MVI L,$BC") #x2E #xBC))
  (check "MVI M,$FF" (bytes= (asm "MVI M,$FF") #x36 #xFF))
  (check "MVI A,$42" (bytes= (asm "MVI A,$42") #x3E #x42)))

;;; --------------------------------------------------------------------------
;;;  Tests : LXI
;;; --------------------------------------------------------------------------

(deftest test/lxi
  ;; LXI rp,nn = ($01|(rp<<4)) lo hi
  (check "LXI B,$1234" (bytes= (asm "LXI B,$1234") #x01 #x34 #x12))
  (check "LXI D,$ABCD" (bytes= (asm "LXI D,$ABCD") #x11 #xCD #xAB))
  (check "LXI H,$0000" (bytes= (asm "LXI H,$0000") #x21 #x00 #x00))
  (check "LXI SP,$FFFF" (bytes= (asm "LXI SP,$FFFF") #x31 #xFF #xFF)))

;;; --------------------------------------------------------------------------
;;;  Tests : INR / DCR
;;; --------------------------------------------------------------------------

(deftest test/inr-dcr
  ;; INR r = $04 | (r<<3)
  (check "INR B" (bytes= (asm "INR B") #x04))
  (check "INR C" (bytes= (asm "INR C") #x0C))
  (check "INR D" (bytes= (asm "INR D") #x14))
  (check "INR E" (bytes= (asm "INR E") #x1C))
  (check "INR H" (bytes= (asm "INR H") #x24))
  (check "INR L" (bytes= (asm "INR L") #x2C))
  (check "INR M" (bytes= (asm "INR M") #x34))
  (check "INR A" (bytes= (asm "INR A") #x3C))
  ;; DCR r = $05 | (r<<3)
  (check "DCR B" (bytes= (asm "DCR B") #x05))
  (check "DCR A" (bytes= (asm "DCR A") #x3D))
  (check "DCR M" (bytes= (asm "DCR M") #x35)))

;;; --------------------------------------------------------------------------
;;;  Tests : INX / DCX / DAD
;;; --------------------------------------------------------------------------

(deftest test/inx-dcx-dad
  ;; INX rp = $03 | (rp<<4)
  (check "INX B"  (bytes= (asm "INX B")  #x03))
  (check "INX D"  (bytes= (asm "INX D")  #x13))
  (check "INX H"  (bytes= (asm "INX H")  #x23))
  (check "INX SP" (bytes= (asm "INX SP") #x33))
  ;; DCX rp = $0B | (rp<<4)
  (check "DCX B"  (bytes= (asm "DCX B")  #x0B))
  (check "DCX D"  (bytes= (asm "DCX D")  #x1B))
  (check "DCX H"  (bytes= (asm "DCX H")  #x2B))
  (check "DCX SP" (bytes= (asm "DCX SP") #x3B))
  ;; DAD rp = $09 | (rp<<4)
  (check "DAD B"  (bytes= (asm "DAD B")  #x09))
  (check "DAD D"  (bytes= (asm "DAD D")  #x19))
  (check "DAD H"  (bytes= (asm "DAD H")  #x29))
  (check "DAD SP" (bytes= (asm "DAD SP") #x39)))

;;; --------------------------------------------------------------------------
;;;  Tests : LDAX / STAX
;;; --------------------------------------------------------------------------

(deftest test/ldax-stax
  (check "STAX B" (bytes= (asm "STAX B") #x02))
  (check "STAX D" (bytes= (asm "STAX D") #x12))
  (check "LDAX B" (bytes= (asm "LDAX B") #x0A))
  (check "LDAX D" (bytes= (asm "LDAX D") #x1A)))

;;; --------------------------------------------------------------------------
;;;  Tests : LDA / STA / LHLD / SHLD
;;; --------------------------------------------------------------------------

(deftest test/lda-sta-lhld-shld
  (check "LDA $1234"  (bytes= (asm "LDA $1234")  #x3A #x34 #x12))
  (check "STA $5678"  (bytes= (asm "STA $5678")  #x32 #x78 #x56))
  (check "LHLD $1000" (bytes= (asm "LHLD $1000") #x2A #x00 #x10))
  (check "SHLD $2000" (bytes= (asm "SHLD $2000") #x22 #x00 #x20)))

;;; --------------------------------------------------------------------------
;;;  Tests : ALU registre
;;; --------------------------------------------------------------------------

(deftest test/alu-reg
  ;; ADD r = $80 | r
  (check "ADD B" (bytes= (asm "ADD B") #x80))
  (check "ADD A" (bytes= (asm "ADD A") #x87))
  (check "ADD M" (bytes= (asm "ADD M") #x86))
  ;; ADC r = $88 | r
  (check "ADC B" (bytes= (asm "ADC B") #x88))
  (check "ADC A" (bytes= (asm "ADC A") #x8F))
  ;; SUB r = $90 | r
  (check "SUB B" (bytes= (asm "SUB B") #x90))
  (check "SUB A" (bytes= (asm "SUB A") #x97))
  ;; SBB r = $98 | r
  (check "SBB B" (bytes= (asm "SBB B") #x98))
  (check "SBB C" (bytes= (asm "SBB C") #x99))
  ;; ANA r = $A0 | r
  (check "ANA B" (bytes= (asm "ANA B") #xA0))
  (check "ANA A" (bytes= (asm "ANA A") #xA7))
  ;; XRA r = $A8 | r
  (check "XRA B" (bytes= (asm "XRA B") #xA8))
  (check "XRA A" (bytes= (asm "XRA A") #xAF))
  ;; ORA r = $B0 | r
  (check "ORA B" (bytes= (asm "ORA B") #xB0))
  (check "ORA M" (bytes= (asm "ORA M") #xB6))
  ;; CMP r = $B8 | r
  (check "CMP B" (bytes= (asm "CMP B") #xB8))
  (check "CMP A" (bytes= (asm "CMP A") #xBF)))

;;; --------------------------------------------------------------------------
;;;  Tests : ALU immédiat
;;; --------------------------------------------------------------------------

(deftest test/alu-imm
  (check "ADI $10" (bytes= (asm "ADI $10") #xC6 #x10))
  (check "ACI $20" (bytes= (asm "ACI $20") #xCE #x20))
  (check "SUI $30" (bytes= (asm "SUI $30") #xD6 #x30))
  (check "SBI $40" (bytes= (asm "SBI $40") #xDE #x40))
  (check "ANI $F0" (bytes= (asm "ANI $F0") #xE6 #xF0))
  (check "XRI $0F" (bytes= (asm "XRI $0F") #xEE #x0F))
  (check "ORI $FF" (bytes= (asm "ORI $FF") #xF6 #xFF))
  (check "CPI $42" (bytes= (asm "CPI $42") #xFE #x42)))

;;; --------------------------------------------------------------------------
;;;  Tests : JMP et sauts conditionnels
;;; --------------------------------------------------------------------------

(deftest test/jumps
  (check "JMP $1234" (bytes= (asm "JMP $1234") #xC3 #x34 #x12))
  (check "JNZ $0100" (bytes= (asm "JNZ $0100") #xC2 #x00 #x01))
  (check "JZ  $0200" (bytes= (asm "JZ  $0200") #xCA #x00 #x02))
  (check "JNC $0300" (bytes= (asm "JNC $0300") #xD2 #x00 #x03))
  (check "JC  $0400" (bytes= (asm "JC  $0400") #xDA #x00 #x04))
  (check "JPO $0500" (bytes= (asm "JPO $0500") #xE2 #x00 #x05))
  (check "JPE $0600" (bytes= (asm "JPE $0600") #xEA #x00 #x06))
  (check "JP  $0700" (bytes= (asm "JP  $0700") #xF2 #x00 #x07))
  (check "JM  $0800" (bytes= (asm "JM  $0800") #xFA #x00 #x08)))

;;; --------------------------------------------------------------------------
;;;  Tests : CALL et appels conditionnels
;;; --------------------------------------------------------------------------

(deftest test/calls
  (check "CALL $ABCD" (bytes= (asm "CALL $ABCD") #xCD #xCD #xAB))
  (check "CNZ $0100"  (bytes= (asm "CNZ $0100")  #xC4 #x00 #x01))
  (check "CZ  $0200"  (bytes= (asm "CZ  $0200")  #xCC #x00 #x02))
  (check "CNC $0300"  (bytes= (asm "CNC $0300")  #xD4 #x00 #x03))
  (check "CC  $0400"  (bytes= (asm "CC  $0400")  #xDC #x00 #x04))
  (check "CPO $0500"  (bytes= (asm "CPO $0500")  #xE4 #x00 #x05))
  (check "CPE $0600"  (bytes= (asm "CPE $0600")  #xEC #x00 #x06))
  (check "CP  $0700"  (bytes= (asm "CP  $0700")  #xF4 #x00 #x07))
  (check "CM  $0800"  (bytes= (asm "CM  $0800")  #xFC #x00 #x08)))

;;; --------------------------------------------------------------------------
;;;  Tests : PUSH / POP
;;; --------------------------------------------------------------------------

(deftest test/push-pop
  ;; PUSH rp = $C5 | (rp<<4)
  (check "PUSH B"   (bytes= (asm "PUSH B")   #xC5))
  (check "PUSH D"   (bytes= (asm "PUSH D")   #xD5))
  (check "PUSH H"   (bytes= (asm "PUSH H")   #xE5))
  (check "PUSH PSW" (bytes= (asm "PUSH PSW") #xF5))
  ;; POP rp = $C1 | (rp<<4)
  (check "POP B"    (bytes= (asm "POP B")    #xC1))
  (check "POP D"    (bytes= (asm "POP D")    #xD1))
  (check "POP H"    (bytes= (asm "POP H")    #xE1))
  (check "POP PSW"  (bytes= (asm "POP PSW")  #xF1)))

;;; --------------------------------------------------------------------------
;;;  Tests : IN / OUT / RST
;;; --------------------------------------------------------------------------

(deftest test/in-out-rst
  (check "IN $3C"  (bytes= (asm "IN $3C")  #xDB #x3C))
  (check "OUT $01" (bytes= (asm "OUT $01") #xD3 #x01))
  ;; RST n = $C7 | (n<<3)
  (check "RST 0" (bytes= (asm "RST 0") #xC7))
  (check "RST 1" (bytes= (asm "RST 1") #xCF))
  (check "RST 2" (bytes= (asm "RST 2") #xD7))
  (check "RST 3" (bytes= (asm "RST 3") #xDF))
  (check "RST 4" (bytes= (asm "RST 4") #xE7))
  (check "RST 5" (bytes= (asm "RST 5") #xEF))
  (check "RST 6" (bytes= (asm "RST 6") #xF7))
  (check "RST 7" (bytes= (asm "RST 7") #xFF)))

;;; --------------------------------------------------------------------------
;;;  Tests : directives
;;; --------------------------------------------------------------------------

(deftest test/directives
  (check ".org"
         (bytes= (asm ".org $0100
                        NOP")
                 #x00))
  (check ".byte"
         (bytes= (asm ".byte $DE, $AD, $BE, $EF")
                 #xDE #xAD #xBE #xEF))
  (check ".word"
         (bytes= (asm ".word $1234")
                 #x34 #x12))
  (check ".fill"
         (bytes= (asm ".fill 3, $AA")
                 #xAA #xAA #xAA))
  (check ".equ"
         (bytes= (asm "PORT = $3C
                        IN PORT")
                 #xDB #x3C)))

;;; --------------------------------------------------------------------------
;;;  Tests : programme complet (boucle CP/M)
;;; --------------------------------------------------------------------------

(deftest test/program
  ;; Petit programme 8080 : MVI C,9  MVI D,lo  MVI E,hi  CALL 5  RET
  (check "programme boucle"
         (let ((code (asm ".org $0100
                           main:
                             MVI B,$00
                           loop:
                             MOV A,B
                             INR B
                             CPI $0A
                             JNZ loop
                             RET"
                          :origin #x0100)))
           (and
            ;; MVI B,$00 = $06 $00
            (= (aref code 0) #x06)
            (= (aref code 1) #x00)
            ;; MOV A,B = $78
            (= (aref code 2) #x78)
            ;; INR B = $04
            (= (aref code 3) #x04)
            ;; CPI $0A = $FE $0A
            (= (aref code 4) #xFE)
            (= (aref code 5) #x0A)
            ;; JNZ loop ($0102) = $C2 $02 $01
            (= (aref code 6) #xC2)
            (= (aref code 7) #x02)
            (= (aref code 8) #x01)
            ;; RET = $C9
            (= (aref code 9) #xC9)))))

;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~%=== Tests Intel 8080 ===~%")
  (test/implied)
  (test/conditional-returns)
  (test/mov)
  (test/mvi)
  (test/lxi)
  (test/inr-dcr)
  (test/inx-dcx-dad)
  (test/ldax-stax)
  (test/lda-sta-lhld-shld)
  (test/alu-reg)
  (test/alu-imm)
  (test/jumps)
  (test/calls)
  (test/push-pop)
  (test/in-out-rst)
  (test/directives)
  (test/program)
  (format t "~%8080 : ~D OK, ~D KO~%" *pass* *fail*))
