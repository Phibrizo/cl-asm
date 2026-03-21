; -*- coding: utf-8 -*-
;;; tests/test-z80.lisp
;;;
;;; Tests unitaires pour le backend Z80.

(defpackage #:cl-asm/test.z80
  (:use #:cl #:cl-asm/backend.z80)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.z80)


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
  "Assemble une chaîne source Z80 et retourne un vecteur d'octets."
  (assemble-string-z80 src :origin origin))

(defun bytes= (result &rest expected)
  "Compare le résultat avec la séquence d'octets attendus."
  (and (= (length result) (length expected))
       (every #'= result expected)))


;;; --------------------------------------------------------------------------
;;;  1. Instructions sans opérande (implied)
;;; --------------------------------------------------------------------------

(deftest test-z80-implied
  (check "NOP"  (bytes= (asm "NOP")  #x00))
  (check "HALT" (bytes= (asm "HALT") #x76))
  (check "DI"   (bytes= (asm "DI")   #xF3))
  (check "EI"   (bytes= (asm "EI")   #xFB))
  (check "EXX"  (bytes= (asm "EXX")  #xD9))
  (check "DAA"  (bytes= (asm "DAA")  #x27))
  (check "CPL"  (bytes= (asm "CPL")  #x2F))
  (check "CCF"  (bytes= (asm "CCF")  #x3F))
  (check "SCF"  (bytes= (asm "SCF")  #x37))
  (check "RLCA" (bytes= (asm "RLCA") #x07))
  (check "RRCA" (bytes= (asm "RRCA") #x0F))
  (check "RLA"  (bytes= (asm "RLA")  #x17))
  (check "RRA"  (bytes= (asm "RRA")  #x1F))
  (check "NEG"  (bytes= (asm "NEG")  #xED #x44))
  (check "RLD"  (bytes= (asm "RLD")  #xED #x6F))
  (check "RRD"  (bytes= (asm "RRD")  #xED #x67))
  (check "RETN" (bytes= (asm "RETN") #xED #x45))
  (check "RETI" (bytes= (asm "RETI") #xED #x4D)))


;;; --------------------------------------------------------------------------
;;;  2. LD r, r' et LD r, n
;;; --------------------------------------------------------------------------

(deftest test-z80-ld-r-r
  (check "LD A, B"  (bytes= (asm "LD A, B")  #x78))
  (check "LD A, C"  (bytes= (asm "LD A, C")  #x79))
  (check "LD A, D"  (bytes= (asm "LD A, D")  #x7A))
  (check "LD A, E"  (bytes= (asm "LD A, E")  #x7B))
  (check "LD A, H"  (bytes= (asm "LD A, H")  #x7C))
  (check "LD A, L"  (bytes= (asm "LD A, L")  #x7D))
  (check "LD A, A"  (bytes= (asm "LD A, A")  #x7F))
  (check "LD B, C"  (bytes= (asm "LD B, C")  #x41))
  (check "LD H, L"  (bytes= (asm "LD H, L")  #x65))
  (check "LD A, $42" (bytes= (asm "LD A, $42") #x3E #x42))
  (check "LD B, 0"   (bytes= (asm "LD B, 0")   #x06 #x00))
  (check "LD C, 255" (bytes= (asm "LD C, 255") #x0E #xFF)))


;;; --------------------------------------------------------------------------
;;;  3. LD (HL) et (IX+d) / (IY+d)
;;; --------------------------------------------------------------------------

(deftest test-z80-ld-indirect
  (check "LD A, (HL)"    (bytes= (asm "LD A, (HL)")    #x7E))
  (check "LD (HL), A"    (bytes= (asm "LD (HL), A")    #x77))
  (check "LD (HL), $10"  (bytes= (asm "LD (HL), $10")  #x36 #x10))
  (check "LD B, (HL)"    (bytes= (asm "LD B, (HL)")    #x46))
  (check "LD (HL), B"    (bytes= (asm "LD (HL), B")    #x70))
  (check "LD A, (IX+2)"  (bytes= (asm "LD A, (IX+2)")  #xDD #x7E #x02))
  (check "LD A, (IY+5)"  (bytes= (asm "LD A, (IY+5)")  #xFD #x7E #x05))
  (check "LD (IX+3), A"  (bytes= (asm "LD (IX+3), A")  #xDD #x77 #x03))
  (check "LD (IY+0), B"  (bytes= (asm "LD (IY+0), B")  #xFD #x70 #x00))
  (check "LD (IX+1), $FF" (bytes= (asm "LD (IX+1), $FF") #xDD #x36 #x01 #xFF))
  (check "LD (IY+2), $AB" (bytes= (asm "LD (IY+2), $AB") #xFD #x36 #x02 #xAB)))


;;; --------------------------------------------------------------------------
;;;  4. LD rr, nn  et  LD 16-bit divers
;;; --------------------------------------------------------------------------

(deftest test-z80-ld-16bit
  (check "LD BC, $1234" (bytes= (asm "LD BC, $1234") #x01 #x34 #x12))
  (check "LD DE, $5678" (bytes= (asm "LD DE, $5678") #x11 #x78 #x56))
  (check "LD HL, $9ABC" (bytes= (asm "LD HL, $9ABC") #x21 #xBC #x9A))
  (check "LD SP, $FFFE" (bytes= (asm "LD SP, $FFFE") #x31 #xFE #xFF))
  (check "LD IX, $1000" (bytes= (asm "LD IX, $1000") #xDD #x21 #x00 #x10))
  (check "LD IY, $2000" (bytes= (asm "LD IY, $2000") #xFD #x21 #x00 #x20))
  (check "LD SP, HL"    (bytes= (asm "LD SP, HL")    #xF9))
  (check "LD SP, IX"    (bytes= (asm "LD SP, IX")    #xDD #xF9))
  (check "LD SP, IY"    (bytes= (asm "LD SP, IY")    #xFD #xF9))
  (check "LD A, I"      (bytes= (asm "LD A, I")      #xED #x57))
  (check "LD A, R"      (bytes= (asm "LD A, R")      #xED #x5F))
  (check "LD I, A"      (bytes= (asm "LD I, A")      #xED #x47))
  (check "LD R, A"      (bytes= (asm "LD R, A")      #xED #x4F)))


;;; --------------------------------------------------------------------------
;;;  5. LD (nn) — mémoire indirecte
;;; --------------------------------------------------------------------------

(deftest test-z80-ld-mem
  (check "LD A, ($8000)"   (bytes= (asm "LD A, ($8000)")   #x3A #x00 #x80))
  (check "LD ($8000), A"   (bytes= (asm "LD ($8000), A")   #x32 #x00 #x80))
  (check "LD HL, ($4000)"  (bytes= (asm "LD HL, ($4000)")  #x2A #x00 #x40))
  (check "LD ($4000), HL"  (bytes= (asm "LD ($4000), HL")  #x22 #x00 #x40))
  (check "LD BC, ($1000)"  (bytes= (asm "LD BC, ($1000)")  #xED #x4B #x00 #x10))
  (check "LD ($1000), BC"  (bytes= (asm "LD ($1000), BC")  #xED #x43 #x00 #x10))
  (check "LD IX, ($2000)"  (bytes= (asm "LD IX, ($2000)")  #xDD #x2A #x00 #x20))
  (check "LD ($2000), IX"  (bytes= (asm "LD ($2000), IX")  #xDD #x22 #x00 #x20)))


;;; --------------------------------------------------------------------------
;;;  6. PUSH / POP
;;; --------------------------------------------------------------------------

(deftest test-z80-push-pop
  (check "PUSH BC" (bytes= (asm "PUSH BC") #xC5))
  (check "PUSH DE" (bytes= (asm "PUSH DE") #xD5))
  (check "PUSH HL" (bytes= (asm "PUSH HL") #xE5))
  (check "PUSH AF" (bytes= (asm "PUSH AF") #xF5))
  (check "POP  BC" (bytes= (asm "POP BC")  #xC1))
  (check "POP  DE" (bytes= (asm "POP DE")  #xD1))
  (check "POP  HL" (bytes= (asm "POP HL")  #xE1))
  (check "POP  AF" (bytes= (asm "POP AF")  #xF1))
  (check "PUSH IX" (bytes= (asm "PUSH IX") #xDD #xE5))
  (check "PUSH IY" (bytes= (asm "PUSH IY") #xFD #xE5))
  (check "POP  IX" (bytes= (asm "POP IX")  #xDD #xE1))
  (check "POP  IY" (bytes= (asm "POP IY")  #xFD #xE1)))


;;; --------------------------------------------------------------------------
;;;  7. INC / DEC
;;; --------------------------------------------------------------------------

(deftest test-z80-inc-dec
  (check "INC A"    (bytes= (asm "INC A")    #x3C))
  (check "INC B"    (bytes= (asm "INC B")    #x04))
  (check "INC C"    (bytes= (asm "INC C")    #x0C))
  (check "DEC A"    (bytes= (asm "DEC A")    #x3D))
  (check "DEC B"    (bytes= (asm "DEC B")    #x05))
  (check "INC BC"   (bytes= (asm "INC BC")   #x03))
  (check "INC DE"   (bytes= (asm "INC DE")   #x13))
  (check "INC HL"   (bytes= (asm "INC HL")   #x23))
  (check "INC SP"   (bytes= (asm "INC SP")   #x33))
  (check "DEC HL"   (bytes= (asm "DEC HL")   #x2B))
  (check "INC (HL)" (bytes= (asm "INC (HL)") #x34))
  (check "DEC (HL)" (bytes= (asm "DEC (HL)") #x35))
  (check "INC IX"   (bytes= (asm "INC IX")   #xDD #x23))
  (check "DEC IY"   (bytes= (asm "DEC IY")   #xFD #x2B))
  (check "INC (IX+3)" (bytes= (asm "INC (IX+3)") #xDD #x34 #x03))
  (check "DEC (IY+1)" (bytes= (asm "DEC (IY+1)") #xFD #x35 #x01)))


;;; --------------------------------------------------------------------------
;;;  8. ADD / ADC / SUB / SBC
;;; --------------------------------------------------------------------------

(deftest test-z80-alu
  (check "ADD A, B"    (bytes= (asm "ADD A, B")    #x80))
  (check "ADD A, A"    (bytes= (asm "ADD A, A")    #x87))
  (check "ADD A, $05"  (bytes= (asm "ADD A, $05")  #xC6 #x05))
  (check "ADD A, (HL)" (bytes= (asm "ADD A, (HL)") #x86))
  (check "ADD A, (IX+1)" (bytes= (asm "ADD A, (IX+1)") #xDD #x86 #x01))
  (check "ADD HL, BC"  (bytes= (asm "ADD HL, BC")  #x09))
  (check "ADD HL, SP"  (bytes= (asm "ADD HL, SP")  #x39))
  (check "ADC A, C"    (bytes= (asm "ADC A, C")    #x89))
  (check "ADC A, $10"  (bytes= (asm "ADC A, $10")  #xCE #x10))
  (check "ADC HL, DE"  (bytes= (asm "ADC HL, DE")  #xED #x5A))
  (check "SUB B"       (bytes= (asm "SUB B")        #x90))
  (check "SUB $FF"     (bytes= (asm "SUB $FF")      #xD6 #xFF))
  (check "SBC A, E"    (bytes= (asm "SBC A, E")    #x9B))
  (check "SBC HL, BC"  (bytes= (asm "SBC HL, BC")  #xED #x42))
  (check "AND B"       (bytes= (asm "AND B")        #xA0))
  (check "AND $0F"     (bytes= (asm "AND $0F")      #xE6 #x0F))
  (check "OR  C"       (bytes= (asm "OR C")         #xB1))
  (check "XOR A"       (bytes= (asm "XOR A")        #xAF))
  (check "CP  $FF"     (bytes= (asm "CP $FF")       #xFE #xFF))
  (check "CP  D"       (bytes= (asm "CP D")         #xBA)))


;;; --------------------------------------------------------------------------
;;;  9. Rotations CB
;;; --------------------------------------------------------------------------

(deftest test-z80-rotations
  (check "RLC B"     (bytes= (asm "RLC B")     #xCB #x00))
  (check "RRC C"     (bytes= (asm "RRC C")     #xCB #x09))
  (check "RL  D"     (bytes= (asm "RL D")      #xCB #x12))
  (check "RR  E"     (bytes= (asm "RR E")      #xCB #x1B))
  (check "SLA H"     (bytes= (asm "SLA H")     #xCB #x24))
  (check "SRA L"     (bytes= (asm "SRA L")     #xCB #x2D))
  (check "SRL A"     (bytes= (asm "SRL A")     #xCB #x3F))
  (check "RLC (HL)"  (bytes= (asm "RLC (HL)")  #xCB #x06))
  (check "RL  (IX+2)" (bytes= (asm "RL (IX+2)") #xDD #xCB #x02 #x16))
  (check "RR  (IY+5)" (bytes= (asm "RR (IY+5)") #xFD #xCB #x05 #x1E)))


;;; --------------------------------------------------------------------------
;;;  10. BIT / SET / RES
;;; --------------------------------------------------------------------------

(deftest test-z80-bit-ops
  (check "BIT 0, B"    (bytes= (asm "BIT 0, B")    #xCB #x40))
  (check "BIT 7, A"    (bytes= (asm "BIT 7, A")    #xCB #x7F))
  (check "BIT 3, (HL)" (bytes= (asm "BIT 3, (HL)") #xCB #x5E))
  (check "SET 0, B"    (bytes= (asm "SET 0, B")    #xCB #xC0))
  (check "SET 7, A"    (bytes= (asm "SET 7, A")    #xCB #xFF))
  (check "RES 0, B"    (bytes= (asm "RES 0, B")    #xCB #x80))
  (check "RES 7, A"    (bytes= (asm "RES 7, A")    #xCB #xBF))
  (check "BIT 4, (IX+1)" (bytes= (asm "BIT 4, (IX+1)") #xDD #xCB #x01 #x66))
  (check "SET 2, (IY+3)" (bytes= (asm "SET 2, (IY+3)") #xFD #xCB #x03 #xD6))
  (check "RES 5, (IX+0)" (bytes= (asm "RES 5, (IX+0)") #xDD #xCB #x00 #xAE)))


;;; --------------------------------------------------------------------------
;;;  11. JP / JR / CALL / RET / DJNZ
;;; --------------------------------------------------------------------------

(deftest test-z80-jumps
  ;; JP nn
  (check "JP $1234"    (bytes= (asm "JP $1234")    #xC3 #x34 #x12))
  ;; JP cc, nn
  (check "JP NZ, $0100" (bytes= (asm "JP NZ, $0100") #xC2 #x00 #x01))
  (check "JP Z, $0200"  (bytes= (asm "JP Z, $0200")  #xCA #x00 #x02))
  (check "JP NC, $0300" (bytes= (asm "JP NC, $0300") #xD2 #x00 #x03))
  (check "JP C, $0400"  (bytes= (asm "JP C, $0400")  #xDA #x00 #x04))
  (check "JP PO, $0500" (bytes= (asm "JP PO, $0500") #xE2 #x00 #x05))
  (check "JP PE, $0600" (bytes= (asm "JP PE, $0600") #xEA #x00 #x06))
  (check "JP P, $0700"  (bytes= (asm "JP P, $0700")  #xF2 #x00 #x07))
  (check "JP M, $0800"  (bytes= (asm "JP M, $0800")  #xFA #x00 #x08))
  ;; JP (HL)
  (check "JP (HL)"     (bytes= (asm "JP (HL)")     #xE9))
  ;; CALL / RET
  (check "CALL $1234"  (bytes= (asm "CALL $1234")  #xCD #x34 #x12))
  (check "CALL NZ, $5678" (bytes= (asm "CALL NZ, $5678") #xC4 #x78 #x56))
  (check "RET"         (bytes= (asm "RET")         #xC9))
  (check "RET NZ"      (bytes= (asm "RET NZ")      #xC0))
  (check "RET Z"       (bytes= (asm "RET Z")       #xC8))
  ;; JR
  (check "JR $0002"    (bytes= (asm "JR $0002" :origin 0)   #x18 #x00))
  (check "JR NZ, $0002" (bytes= (asm "JR NZ, $0002" :origin 0) #x20 #x00))
  ;; DJNZ
  (check "DJNZ $0002"  (bytes= (asm "DJNZ $0002" :origin 0) #x10 #x00))
  ;; RST
  (check "RST 0"   (bytes= (asm "RST 0")   #xC7))
  (check "RST 8"   (bytes= (asm "RST 8")   #xCF))
  (check "RST 56"  (bytes= (asm "RST 56")  #xFF)))


;;; --------------------------------------------------------------------------
;;;  12. EX / EXX
;;; --------------------------------------------------------------------------

(deftest test-z80-ex
  (check "EX DE, HL"   (bytes= (asm "EX DE, HL")   #xEB))
  (check "EX (SP), HL" (bytes= (asm "EX (SP), HL") #xE3))
  (check "EX (SP), IX" (bytes= (asm "EX (SP), IX") #xDD #xE3))
  (check "EX (SP), IY" (bytes= (asm "EX (SP), IY") #xFD #xE3)))


;;; --------------------------------------------------------------------------
;;;  13. IN / OUT
;;; --------------------------------------------------------------------------

(deftest test-z80-io
  (check "IN A, ($FE)"  (bytes= (asm "IN A, ($FE)")  #xDB #xFE))
  (check "IN B, (C)"    (bytes= (asm "IN B, (C)")    #xED #x40))
  (check "IN A, (C)"    (bytes= (asm "IN A, (C)")    #xED #x78))
  (check "OUT ($FE), A" (bytes= (asm "OUT ($FE), A") #xD3 #xFE))
  (check "OUT (C), B"   (bytes= (asm "OUT (C), B")   #xED #x41))
  (check "OUT (C), A"   (bytes= (asm "OUT (C), A")   #xED #x79)))


;;; --------------------------------------------------------------------------
;;;  14. ADD IX/IY
;;; --------------------------------------------------------------------------

(deftest test-z80-add-index
  (check "ADD IX, BC" (bytes= (asm "ADD IX, BC") #xDD #x09))
  (check "ADD IX, DE" (bytes= (asm "ADD IX, DE") #xDD #x19))
  (check "ADD IX, IX" (bytes= (asm "ADD IX, IX") #xDD #x29))
  (check "ADD IX, SP" (bytes= (asm "ADD IX, SP") #xDD #x39))
  (check "ADD IY, BC" (bytes= (asm "ADD IY, BC") #xFD #x09))
  (check "ADD IY, IY" (bytes= (asm "ADD IY, IY") #xFD #x29)))


;;; --------------------------------------------------------------------------
;;;  15. IM / block moves
;;; --------------------------------------------------------------------------

(deftest test-z80-misc
  (check "IM 0"  (bytes= (asm "IM 0")  #xED #x46))
  (check "IM 1"  (bytes= (asm "IM 1")  #xED #x56))
  (check "IM 2"  (bytes= (asm "IM 2")  #xED #x5E))
  (check "LDI"   (bytes= (asm "LDI")   #xED #xA0))
  (check "LDIR"  (bytes= (asm "LDIR")  #xED #xB0))
  (check "LDD"   (bytes= (asm "LDD")   #xED #xA8))
  (check "LDDR"  (bytes= (asm "LDDR")  #xED #xB8))
  (check "CPI"   (bytes= (asm "CPI")   #xED #xA1))
  (check "CPIR"  (bytes= (asm "CPIR")  #xED #xB1))
  (check "CPD"   (bytes= (asm "CPD")   #xED #xA9))
  (check "CPDR"  (bytes= (asm "CPDR")  #xED #xB9))
  (check "INI"   (bytes= (asm "INI")   #xED #xA2))
  (check "INIR"  (bytes= (asm "INIR")  #xED #xB2))
  (check "OUTI"  (bytes= (asm "OUTI")  #xED #xA3))
  (check "OTIR"  (bytes= (asm "OTIR")  #xED #xB3)))


;;; --------------------------------------------------------------------------
;;;  16. Directives .ORG / .DB / .DW
;;; --------------------------------------------------------------------------

(deftest test-z80-directives
  (check ".BYTE"
    (bytes= (asm ".byte $01, $02, $03") #x01 #x02 #x03))
  (check ".WORD little-endian"
    (bytes= (asm ".word $1234") #x34 #x12))
  (check ".ORG change PC (JR relatif)"
    ;; JR à partir de $0100 vers $0100+2 → offset 0
    (let ((b (asm ".org $0100
JR $0102" :origin #x0100)))
      (and (= (length b) 2)
           (= (aref b 0) #x18)
           (= (aref b 1) #x00)))))


;;; --------------------------------------------------------------------------
;;;  17. Forward references
;;; --------------------------------------------------------------------------

(deftest test-z80-forward-refs
  (check "JP forward label"
    (let ((b (asm "JP target
NOP
target: NOP" :origin 0)))
      ;; JP nn (3) + NOP (1) + NOP (1) = 5 octets
      ;; target = $0004
      (and (= (length b) 5)
           (= (aref b 0) #xC3)
           (= (aref b 1) #x04)
           (= (aref b 2) #x00))))
  (check "JR forward label"
    (let ((b (asm "JR done
NOP
done: NOP" :origin 0)))
      ;; JR (2 octets $0000-$0001) + NOP (1 octet $0002) + done: NOP ($0003)
      ;; offset = 3 - (0+2) = 1 → #x01
      (and (= (length b) 4)
           (= (aref b 0) #x18)
           (= (aref b 1) #x01)))))


;;; --------------------------------------------------------------------------
;;;  18. Programme ZX Spectrum minimal
;;; --------------------------------------------------------------------------

(deftest test-z80-spectrum-minimal
  (check "Programme minimal ZX Spectrum"
    (let ((b (asm "
.org $8000
start:
  LD A, $42
  LD ($5800), A
  HALT
" :origin #x8000)))
      ;; LD A,$42 = 2, LD ($5800),A = 3, HALT = 1 → 6 octets
      (and (= (length b) 6)
           (= (aref b 0) #x3E) (= (aref b 1) #x42)
           (= (aref b 2) #x32) (= (aref b 3) #x00) (= (aref b 4) #x58)
           (= (aref b 5) #x76)))))


;;; --------------------------------------------------------------------------
;;;  19. Erreurs attendues
;;; --------------------------------------------------------------------------

(deftest test-z80-errors
  (check-error "RST valeur invalide" error
    (asm "RST 3"))
  (check-error "JR hors portée" error
    (asm "JR $0200" :origin 0))
  (check-error "IM inconnu" error
    (asm "IM 3")))


;;; --------------------------------------------------------------------------
;;;  Point d'entrée
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~%=== Suite z80 ===~%")
  (test-z80-implied)
  (test-z80-ld-r-r)
  (test-z80-ld-indirect)
  (test-z80-ld-16bit)
  (test-z80-ld-mem)
  (test-z80-push-pop)
  (test-z80-inc-dec)
  (test-z80-alu)
  (test-z80-rotations)
  (test-z80-bit-ops)
  (test-z80-jumps)
  (test-z80-ex)
  (test-z80-io)
  (test-z80-add-index)
  (test-z80-misc)
  (test-z80-directives)
  (test-z80-forward-refs)
  (test-z80-spectrum-minimal)
  (test-z80-errors)
  (format t "~%  z80 : ~D OK, ~D KO~%" *pass* *fail*)
  (values *pass* *fail*))
