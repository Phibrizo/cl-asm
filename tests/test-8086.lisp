; -*- coding: utf-8 -*-
;;; tests/test-8086.lisp
;;;
;;; Tests unitaires pour le backend Intel 8086.

(defpackage #:cl-asm/test.i8086
  (:use #:cl #:cl-asm/backend.i8086)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.i8086)


;;; --------------------------------------------------------------------------
;;;  Infra de test (identique aux autres suites)
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
                (format t "~&  KO  ~A (erreur NON déclenchée)~%" ,description)))))

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&~%[~A]~%" ',name)
     ,@body))

(defun asm (src &key (origin 0))
  "Assemble une chaîne source Intel 8086."
  (assemble-string-i8086 src :origin origin))

(defun bytes= (result &rest expected)
  "Compare le résultat avec la séquence d'octets attendus."
  (and (= (length result) (length expected))
       (every #'= result expected)))


;;; --------------------------------------------------------------------------
;;;  Tests : instructions sans opérandes (1 octet)
;;; --------------------------------------------------------------------------

(deftest test/implied
  (check "NOP → #x90"    (bytes= (asm "NOP")   #x90))
  (check "HLT → #xF4"    (bytes= (asm "HLT")   #xF4))
  (check "CLC → #xF8"    (bytes= (asm "CLC")   #xF8))
  (check "STC → #xF9"    (bytes= (asm "STC")   #xF9))
  (check "CMC → #xF5"    (bytes= (asm "CMC")   #xF5))
  (check "CLD → #xFC"    (bytes= (asm "CLD")   #xFC))
  (check "STD → #xFD"    (bytes= (asm "STD")   #xFD))
  (check "CLI → #xFA"    (bytes= (asm "CLI")   #xFA))
  (check "STI → #xFB"    (bytes= (asm "STI")   #xFB))
  (check "CBW → #x98"    (bytes= (asm "CBW")   #x98))
  (check "CWD → #x99"    (bytes= (asm "CWD")   #x99))
  (check "XLAT → #xD7"   (bytes= (asm "XLAT")  #xD7))
  (check "LAHF → #x9F"   (bytes= (asm "LAHF")  #x9F))
  (check "SAHF → #x9E"   (bytes= (asm "SAHF")  #x9E))
  (check "PUSHF → #x9C"  (bytes= (asm "PUSHF") #x9C))
  (check "POPF → #x9D"   (bytes= (asm "POPF")  #x9D))
  (check "DAA → #x27"    (bytes= (asm "DAA")   #x27))
  (check "DAS → #x2F"    (bytes= (asm "DAS")   #x2F))
  (check "AAA → #x37"    (bytes= (asm "AAA")   #x37))
  (check "AAS → #x3F"    (bytes= (asm "AAS")   #x3F))
  (check "AAM → #xD4 #x0A" (bytes= (asm "AAM") #xD4 #x0A))
  (check "AAD → #xD5 #x0A" (bytes= (asm "AAD") #xD5 #x0A))
  (check "IRET → #xCF"   (bytes= (asm "IRET")  #xCF))
  (check "INTO → #xCE"   (bytes= (asm "INTO")  #xCE))
  (check "MOVSB → #xA4"  (bytes= (asm "MOVSB") #xA4))
  (check "MOVSW → #xA5"  (bytes= (asm "MOVSW") #xA5))
  (check "CMPSB → #xA6"  (bytes= (asm "CMPSB") #xA6))
  (check "CMPSW → #xA7"  (bytes= (asm "CMPSW") #xA7))
  (check "STOSB → #xAA"  (bytes= (asm "STOSB") #xAA))
  (check "STOSW → #xAB"  (bytes= (asm "STOSW") #xAB))
  (check "LODSB → #xAC"  (bytes= (asm "LODSB") #xAC))
  (check "LODSW → #xAD"  (bytes= (asm "LODSW") #xAD))
  (check "SCASB → #xAE"  (bytes= (asm "SCASB") #xAE))
  (check "SCASW → #xAF"  (bytes= (asm "SCASW") #xAF))
  (check "REP → #xF3"    (bytes= (asm "REP")   #xF3))
  (check "REPNE → #xF2"  (bytes= (asm "REPNE") #xF2))
  (check "LOCK → #xF0"   (bytes= (asm "LOCK")  #xF0))
  (check "REP MOVSB → séquence 2 octets"
         (bytes= (asm "REP
MOVSB") #xF3 #xA4)))


;;; --------------------------------------------------------------------------
;;;  Tests : MOV
;;; --------------------------------------------------------------------------

(deftest test/mov-reg-imm
  ;; MOV r16, imm16 : #xB8+reg, lo, hi
  (check "MOV AX, 0"      (bytes= (asm "MOV AX, 0")      #xB8 #x00 #x00))
  (check "MOV AX, $1234"  (bytes= (asm "MOV AX, $1234")  #xB8 #x34 #x12))
  (check "MOV BX, $5678"  (bytes= (asm "MOV BX, $5678")  #xBB #x78 #x56))
  (check "MOV CX, $FFFF"  (bytes= (asm "MOV CX, $FFFF")  #xB9 #xFF #xFF))
  (check "MOV DX, 100"    (bytes= (asm "MOV DX, 100")    #xBA #x64 #x00))
  (check "MOV SI, $0100"  (bytes= (asm "MOV SI, $0100")  #xBE #x00 #x01))
  (check "MOV DI, $0200"  (bytes= (asm "MOV DI, $0200")  #xBF #x00 #x02))
  (check "MOV SP, $FFFE"  (bytes= (asm "MOV SP, $FFFE")  #xBC #xFE #xFF))
  (check "MOV BP, $0000"  (bytes= (asm "MOV BP, $0000")  #xBD #x00 #x00))
  ;; MOV r8, imm8 : #xB0+reg, imm
  (check "MOV AL, $42"    (bytes= (asm "MOV AL, $42")    #xB0 #x42))
  (check "MOV AH, $FF"    (bytes= (asm "MOV AH, $FF")    #xB4 #xFF))
  (check "MOV CL, 10"     (bytes= (asm "MOV CL, 10")     #xB1 #x0A))
  (check "MOV BL, $00"    (bytes= (asm "MOV BL, $00")    #xB3 #x00)))

(deftest test/mov-reg-reg
  ;; MOV r16, r16 : #x8B + ModRM(11, dst, src)
  (check "MOV AX, BX"     (bytes= (asm "MOV AX, BX")   #x8B #xC3))
  (check "MOV BX, AX"     (bytes= (asm "MOV BX, AX")   #x8B #xD8))
  (check "MOV CX, DX"     (bytes= (asm "MOV CX, DX")   #x8B #xCA))
  (check "MOV SI, DI"     (bytes= (asm "MOV SI, DI")   #x8B #xF7))
  ;; MOV r8, r8 : #x8A + ModRM(11, dst, src)
  (check "MOV AL, BL"     (bytes= (asm "MOV AL, BL")   #x8A #xC3))
  (check "MOV AH, CL"     (bytes= (asm "MOV AH, CL")   #x8A #xE1)))

(deftest test/mov-reg-mem
  ;; MOV r16, [BX] : #x8B + ModRM(00, reg, 7)
  (check "MOV AX, [BX]"   (bytes= (asm "MOV AX, [BX]")  #x8B #x07))
  (check "MOV BX, [SI]"   (bytes= (asm "MOV BX, [SI]")  #x8B #x1C))
  (check "MOV CX, [DI]"   (bytes= (asm "MOV CX, [DI]")  #x8B #x0D))
  ;; MOV r16, [BX+disp16]
  (check "MOV AX, [BX+5]" (bytes= (asm "MOV AX, [BX+5]")
                                   #x8B #x87 #x05 #x00))
  ;; MOV r16, [BX+SI]
  (check "MOV AX, [BX+SI]" (bytes= (asm "MOV AX, [BX+SI]") #x8B #x00))
  ;; MOV r16, [direct]
  (check "MOV AX, [$1234]" (bytes= (asm "MOV AX, [$1234]")
                                    #x8B #x06 #x34 #x12))
  ;; MOV r8, [BX]
  (check "MOV AL, [BX]"   (bytes= (asm "MOV AL, [BX]")  #x8A #x07)))

(deftest test/mov-mem-reg
  ;; MOV [BX], r16 : #x89 + ModRM
  (check "MOV [BX], AX"    (bytes= (asm "MOV [BX], AX")   #x89 #x07))
  (check "MOV [SI], DX"    (bytes= (asm "MOV [SI], DX")   #x89 #x14))
  (check "MOV [BX+SI], AX" (bytes= (asm "MOV [BX+SI], AX") #x89 #x00))
  ;; MOV [BX], r8 : #x88 + ModRM
  (check "MOV [BX], AL"    (bytes= (asm "MOV [BX], AL")   #x88 #x07))
  ;; MOV [BX+disp], r16
  (check "MOV [BX+$10], CX" (bytes= (asm "MOV [BX+$10], CX")
                                     #x89 #x8F #x10 #x00)))

(deftest test/mov-mem-imm
  ;; MOV WORD PTR [BX], imm16 : #xC7 + ModRM(00,0,7) + imm16
  (check "MOV WORD PTR [BX], $1234"
         (bytes= (asm "MOV WORD PTR [BX], $1234")
                 #xC7 #x07 #x34 #x12))
  ;; MOV BYTE PTR [BX], imm8 : #xC6 + ModRM + imm8
  (check "MOV BYTE PTR [BX], $42"
         (bytes= (asm "MOV BYTE PTR [BX], $42")
                 #xC6 #x07 #x42)))

(deftest test/mov-sreg
  ;; MOV r16, sreg : #x8C + ModRM(11, sreg, r16)
  (check "MOV AX, DS"  (bytes= (asm "MOV AX, DS")   #x8C #xD8))
  (check "MOV BX, CS"  (bytes= (asm "MOV BX, CS")   #x8C #xCB))
  ;; MOV sreg, r16 : #x8E + ModRM(11, sreg, r16)
  (check "MOV DS, AX"  (bytes= (asm "MOV DS, AX")   #x8E #xD8))
  (check "MOV ES, BX"  (bytes= (asm "MOV ES, BX")   #x8E #xC3)))


;;; --------------------------------------------------------------------------
;;;  Tests : ALU (ADD / SUB / AND / OR / XOR / CMP)
;;; --------------------------------------------------------------------------

(deftest test/alu-reg-imm
  ;; Forme courte accumulateur
  (check "ADD AX, 5"     (bytes= (asm "ADD AX, 5")      #x05 #x05 #x00))
  (check "SUB AX, $100"  (bytes= (asm "SUB AX, $100")   #x2D #x00 #x01))
  (check "AND AX, $FF00" (bytes= (asm "AND AX, $FF00")  #x25 #x00 #xFF))
  (check "OR AX, 1"      (bytes= (asm "OR AX, 1")       #x0D #x01 #x00))
  (check "XOR AX, $FFFF" (bytes= (asm "XOR AX, $FFFF")  #x35 #xFF #xFF))
  (check "CMP AX, 0"     (bytes= (asm "CMP AX, 0")      #x3D #x00 #x00))
  (check "ADD AL, 10"    (bytes= (asm "ADD AL, 10")      #x04 #x0A))
  (check "SUB AL, $FF"   (bytes= (asm "SUB AL, $FF")     #x2C #xFF))
  (check "CMP AL, $42"   (bytes= (asm "CMP AL, $42")     #x3C #x42))
  ;; Forme générale reg16, imm16 : #x81 + ModRM
  (check "ADD BX, $1234" (bytes= (asm "ADD BX, $1234")
                                  #x81 #xC3 #x34 #x12))
  (check "CMP CX, $0001" (bytes= (asm "CMP CX, $0001")
                                  #x81 #xF9 #x01 #x00))
  ;; Forme reg8, imm8 : #x80 + ModRM
  (check "ADD BL, $42"   (bytes= (asm "ADD BL, $42")     #x80 #xC3 #x42))
  (check "CMP AL, 5"     (bytes= (asm "CMP AL, 5")       #x3C #x05)))

(deftest test/alu-reg-reg
  ;; ADD r16, r/m16 (d=1) : #x03 + ModRM(11, dst, src)
  (check "ADD AX, BX"  (bytes= (asm "ADD AX, BX")  #x03 #xC3))
  (check "SUB CX, DX"  (bytes= (asm "SUB CX, DX")  #x2B #xCA))
  (check "AND SI, DI"  (bytes= (asm "AND SI, DI")  #x23 #xF7))
  (check "XOR AX, AX"  (bytes= (asm "XOR AX, AX")  #x33 #xC0))
  ;; ADD r8, r8
  (check "ADD AL, BL"  (bytes= (asm "ADD AL, BL")  #x02 #xC3))
  (check "CMP AH, CH"  (bytes= (asm "CMP AH, CH")  #x3A #xE5)))

(deftest test/alu-mem
  ;; ADD [BX], AX : #x01 + ModRM
  (check "ADD [BX], AX"  (bytes= (asm "ADD [BX], AX")  #x01 #x07))
  (check "SUB [SI], DX"  (bytes= (asm "SUB [SI], DX")  #x29 #x14))
  ;; ADD AX, [BX] : #x03 + ModRM
  (check "ADD AX, [BX]"  (bytes= (asm "ADD AX, [BX]")  #x03 #x07))
  (check "CMP BX, [SI]"  (bytes= (asm "CMP BX, [SI]")  #x3B #x1C)))

(deftest test/adc-sbb
  (check "ADC AX, BX"  (bytes= (asm "ADC AX, BX")  #x13 #xC3))
  (check "SBB AX, CX"  (bytes= (asm "SBB AX, CX")  #x1B #xC1))
  (check "ADC AL, 5"   (bytes= (asm "ADC AL, 5")    #x14 #x05))
  (check "SBB AL, 1"   (bytes= (asm "SBB AL, 1")    #x1C #x01)))


;;; --------------------------------------------------------------------------
;;;  Tests : INC / DEC
;;; --------------------------------------------------------------------------

(deftest test/inc-dec
  ;; INC r16 : #x40+reg
  (check "INC AX"  (bytes= (asm "INC AX")  #x40))
  (check "INC BX"  (bytes= (asm "INC BX")  #x43))
  (check "INC CX"  (bytes= (asm "INC CX")  #x41))
  (check "INC DX"  (bytes= (asm "INC DX")  #x42))
  (check "INC SI"  (bytes= (asm "INC SI")  #x46))
  (check "INC DI"  (bytes= (asm "INC DI")  #x47))
  ;; DEC r16 : #x48+reg
  (check "DEC AX"  (bytes= (asm "DEC AX")  #x48))
  (check "DEC BX"  (bytes= (asm "DEC BX")  #x4B))
  (check "DEC SP"  (bytes= (asm "DEC SP")  #x4C))
  ;; INC r8 : #xFE + ModRM(11,0,reg)
  (check "INC AL"  (bytes= (asm "INC AL")  #xFE #xC0))
  (check "INC CL"  (bytes= (asm "INC CL")  #xFE #xC1))
  (check "INC BH"  (bytes= (asm "INC BH")  #xFE #xC7))
  ;; DEC r8 : #xFE + ModRM(11,1,reg)
  (check "DEC AL"  (bytes= (asm "DEC AL")  #xFE #xC8))
  (check "DEC BL"  (bytes= (asm "DEC BL")  #xFE #xCB))
  ;; INC [BX] : #xFF + ModRM(00,0,7)
  (check "INC WORD PTR [BX]"
         (bytes= (asm "INC WORD PTR [BX]")  #xFF #x07))
  (check "DEC BYTE PTR [SI]"
         (bytes= (asm "DEC BYTE PTR [SI]")  #xFE #x0C)))


;;; --------------------------------------------------------------------------
;;;  Tests : NEG / NOT / MUL / DIV
;;; --------------------------------------------------------------------------

(deftest test/unary
  (check "NEG AX"   (bytes= (asm "NEG AX")   #xF7 #xD8))
  (check "NOT AX"   (bytes= (asm "NOT AX")   #xF7 #xD0))
  (check "MUL BX"   (bytes= (asm "MUL BX")   #xF7 #xE3))
  (check "IMUL CX"  (bytes= (asm "IMUL CX")  #xF7 #xE9))
  (check "DIV DX"   (bytes= (asm "DIV DX")   #xF7 #xF2))
  (check "IDIV SI"  (bytes= (asm "IDIV SI")  #xF7 #xFE))
  (check "NEG AL"   (bytes= (asm "NEG AL")   #xF6 #xD8))
  (check "MUL BL"   (bytes= (asm "MUL BL")   #xF6 #xE3))
  (check "NOT WORD PTR [BX]"
         (bytes= (asm "NOT WORD PTR [BX]")   #xF7 #x17)))


;;; --------------------------------------------------------------------------
;;;  Tests : PUSH / POP
;;; --------------------------------------------------------------------------

(deftest test/push-pop
  ;; PUSH r16 : #x50+reg
  (check "PUSH AX"  (bytes= (asm "PUSH AX")  #x50))
  (check "PUSH BX"  (bytes= (asm "PUSH BX")  #x53))
  (check "PUSH CX"  (bytes= (asm "PUSH CX")  #x51))
  (check "PUSH BP"  (bytes= (asm "PUSH BP")  #x55))
  ;; POP r16 : #x58+reg
  (check "POP AX"   (bytes= (asm "POP AX")   #x58))
  (check "POP BX"   (bytes= (asm "POP BX")   #x5B))
  (check "POP SI"   (bytes= (asm "POP SI")   #x5E))
  ;; PUSH segment
  (check "PUSH ES"  (bytes= (asm "PUSH ES")  #x06))
  (check "PUSH CS"  (bytes= (asm "PUSH CS")  #x0E))
  (check "PUSH SS"  (bytes= (asm "PUSH SS")  #x16))
  (check "PUSH DS"  (bytes= (asm "PUSH DS")  #x1E))
  ;; POP segment
  (check "POP ES"   (bytes= (asm "POP ES")   #x07))
  (check "POP SS"   (bytes= (asm "POP SS")   #x17))
  (check "POP DS"   (bytes= (asm "POP DS")   #x1F))
  ;; PUSH/POP mémoire
  (check "PUSH WORD PTR [BX]"
         (bytes= (asm "PUSH WORD PTR [BX]")  #xFF #x37))
  (check "POP WORD PTR [SI]"
         (bytes= (asm "POP WORD PTR [SI]")   #x8F #x04)))


;;; --------------------------------------------------------------------------
;;;  Tests : XCHG
;;; --------------------------------------------------------------------------

(deftest test/xchg
  ;; XCHG AX, r16 : #x90+reg
  (check "XCHG AX, AX"  (bytes= (asm "XCHG AX, AX")  #x90))  ; = NOP
  (check "XCHG AX, BX"  (bytes= (asm "XCHG AX, BX")  #x93))
  (check "XCHG AX, CX"  (bytes= (asm "XCHG AX, CX")  #x91))
  (check "XCHG AX, DX"  (bytes= (asm "XCHG AX, DX")  #x92))
  (check "XCHG BX, AX"  (bytes= (asm "XCHG BX, AX")  #x93))
  ;; XCHG r16, r16 (non-AX) : #x87 + ModRM
  (check "XCHG BX, CX"  (bytes= (asm "XCHG BX, CX")  #x87 #xCB))
  ;; XCHG r8, r8 : #x86 + ModRM
  (check "XCHG AL, BL"  (bytes= (asm "XCHG AL, BL")  #x86 #xD8)))


;;; --------------------------------------------------------------------------
;;;  Tests : LEA
;;; --------------------------------------------------------------------------

(deftest test/lea
  (check "LEA AX, [BX]"     (bytes= (asm "LEA AX, [BX]")     #x8D #x07))
  (check "LEA BX, [SI+$10]" (bytes= (asm "LEA BX, [SI+$10]") #x8D #x9C #x10 #x00))
  (check "LEA SI, [BX+DI]"  (bytes= (asm "LEA SI, [BX+DI]")  #x8D #x31)))


;;; --------------------------------------------------------------------------
;;;  Tests : Shifts et rotations
;;; --------------------------------------------------------------------------

(deftest test/shifts
  ;; SHL/SHR/SAR/ROL/ROR/RCL/RCR reg16, 1
  (check "SHL AX, 1"   (bytes= (asm "SHL AX, 1")  #xD1 #xE0))
  (check "SHR AX, 1"   (bytes= (asm "SHR AX, 1")  #xD1 #xE8))
  (check "SAR AX, 1"   (bytes= (asm "SAR AX, 1")  #xD1 #xF8))
  (check "ROL BX, 1"   (bytes= (asm "ROL BX, 1")  #xD1 #xC3))
  (check "ROR CX, 1"   (bytes= (asm "ROR CX, 1")  #xD1 #xC9))
  (check "RCL DX, 1"   (bytes= (asm "RCL DX, 1")  #xD1 #xD2))
  (check "RCR SI, 1"   (bytes= (asm "RCR SI, 1")  #xD1 #xDE))
  ;; Shifts reg8, 1
  (check "SHL AL, 1"   (bytes= (asm "SHL AL, 1")  #xD0 #xE0))
  (check "SHR BL, 1"   (bytes= (asm "SHR BL, 1")  #xD0 #xEB))
  (check "SAR CL, 1"   (bytes= (asm "SAR CL, 1")  #xD0 #xF9))
  ;; Shifts reg16, CL
  (check "SHL AX, CL"  (bytes= (asm "SHL AX, CL") #xD3 #xE0))
  (check "SHR BX, CL"  (bytes= (asm "SHR BX, CL") #xD3 #xEB))
  (check "ROL CX, CL"  (bytes= (asm "ROL CX, CL") #xD3 #xC1))
  ;; Shifts reg8, CL
  (check "SHL AL, CL"  (bytes= (asm "SHL AL, CL") #xD2 #xE0))
  ;; Shifts mémoire
  (check "SHL WORD PTR [BX], 1"
         (bytes= (asm "SHL WORD PTR [BX], 1") #xD1 #x27))
  (check "SHR WORD PTR [BX+SI], CL"
         (bytes= (asm "SHR WORD PTR [BX+SI], CL") #xD3 #x28)))


;;; --------------------------------------------------------------------------
;;;  Tests : Sauts conditionnels (Jcc)
;;; --------------------------------------------------------------------------

(deftest test/jcc
  ;; Tous depuis origin=0, cible=$10 → offset = $10 - 2 = $0E
  (check "JZ $10"    (bytes= (asm "JZ $10")    #x74 #x0E))
  (check "JNZ $10"   (bytes= (asm "JNZ $10")   #x75 #x0E))
  (check "JE $10"    (bytes= (asm "JE $10")    #x74 #x0E))
  (check "JNE $10"   (bytes= (asm "JNE $10")   #x75 #x0E))
  (check "JB $10"    (bytes= (asm "JB $10")    #x72 #x0E))
  (check "JNB $10"   (bytes= (asm "JNB $10")   #x73 #x0E))
  (check "JC $10"    (bytes= (asm "JC $10")    #x72 #x0E))
  (check "JNC $10"   (bytes= (asm "JNC $10")   #x73 #x0E))
  (check "JBE $10"   (bytes= (asm "JBE $10")   #x76 #x0E))
  (check "JA $10"    (bytes= (asm "JA $10")    #x77 #x0E))
  (check "JS $10"    (bytes= (asm "JS $10")    #x78 #x0E))
  (check "JNS $10"   (bytes= (asm "JNS $10")   #x79 #x0E))
  (check "JP $10"    (bytes= (asm "JP $10")    #x7A #x0E))
  (check "JNP $10"   (bytes= (asm "JNP $10")   #x7B #x0E))
  (check "JL $10"    (bytes= (asm "JL $10")    #x7C #x0E))
  (check "JNL $10"   (bytes= (asm "JNL $10")   #x7D #x0E))
  (check "JLE $10"   (bytes= (asm "JLE $10")   #x7E #x0E))
  (check "JG $10"    (bytes= (asm "JG $10")    #x7F #x0E))
  (check "JO $10"    (bytes= (asm "JO $10")    #x70 #x0E))
  (check "JNO $10"   (bytes= (asm "JNO $10")   #x71 #x0E))
  (check "JCXZ $10"  (bytes= (asm "JCXZ $10")  #xE3 #x0E))
  ;; Déplacement négatif
  (check "JZ $00 depuis $10"
         (bytes= (asm "JZ $00" :origin #x10) #x74 #xEE)))


;;; --------------------------------------------------------------------------
;;;  Tests : LOOP
;;; --------------------------------------------------------------------------

(deftest test/loop
  (check "LOOP $10"    (bytes= (asm "LOOP $10")    #xE2 #x0E))
  (check "LOOPZ $10"   (bytes= (asm "LOOPZ $10")   #xE1 #x0E))
  (check "LOOPNZ $10"  (bytes= (asm "LOOPNZ $10")  #xE0 #x0E)))


;;; --------------------------------------------------------------------------
;;;  Tests : JMP
;;; --------------------------------------------------------------------------

(deftest test/jmp
  ;; JMP SHORT : #xEB + rel8
  (check "JMP SHORT $10"
         (bytes= (asm "JMP SHORT $10") #xEB #x0E))
  ;; JMP near (défaut) : #xE9 + rel16
  ;; Cible $0100, PC initial 0 → instr=3 octets, PC-after=3, rel=0xFD
  (check "JMP $0100 depuis 0"
         (bytes= (asm "JMP $0100") #xE9 #xFD #x00))
  ;; JMP r16 : #xFF + ModRM(11,4,reg)
  (check "JMP AX"     (bytes= (asm "JMP AX")  #xFF #xE0))
  (check "JMP BX"     (bytes= (asm "JMP BX")  #xFF #xE3))
  ;; JMP [BX] : #xFF + ModRM(00,4,7)
  (check "JMP [BX]"   (bytes= (asm "JMP [BX]") #xFF #x27))
  ;; JMP avec label
  (check "JMP avec label forward"
         (bytes= (asm "JMP target
NOP
target:
NOP") #xE9 #x01 #x00 #x90 #x90)))


;;; --------------------------------------------------------------------------
;;;  Tests : CALL / RET
;;; --------------------------------------------------------------------------

(deftest test/call-ret
  ;; CALL near : #xE8 + rel16
  (check "CALL $0100 depuis 0"
         (bytes= (asm "CALL $0100") #xE8 #xFD #x00))
  ;; CALL r16 : #xFF + ModRM(11,2,reg)
  (check "CALL AX"    (bytes= (asm "CALL AX")   #xFF #xD0))
  (check "CALL BX"    (bytes= (asm "CALL BX")   #xFF #xD3))
  ;; CALL [BX] : #xFF + ModRM(00,2,7)
  (check "CALL [BX]"  (bytes= (asm "CALL [BX]") #xFF #x17))
  ;; RET
  (check "RET"         (bytes= (asm "RET")       #xC3))
  (check "RETF"        (bytes= (asm "RETF")      #xCB))
  (check "RET $0004"   (bytes= (asm "RET $0004") #xC2 #x04 #x00))
  (check "RETF $0002"  (bytes= (asm "RETF $0002") #xCA #x02 #x00)))


;;; --------------------------------------------------------------------------
;;;  Tests : INT
;;; --------------------------------------------------------------------------

(deftest test/int
  (check "INT 3"    (bytes= (asm "INT 3")    #xCC))
  (check "INT $21"  (bytes= (asm "INT $21")  #xCD #x21))
  (check "INT $10"  (bytes= (asm "INT $10")  #xCD #x10))
  (check "INT $80"  (bytes= (asm "INT $80")  #xCD #x80)))


;;; --------------------------------------------------------------------------
;;;  Tests : IN / OUT
;;; --------------------------------------------------------------------------

(deftest test/in-out
  (check "IN AL, $60"   (bytes= (asm "IN AL, $60")   #xE4 #x60))
  (check "IN AX, $60"   (bytes= (asm "IN AX, $60")   #xE5 #x60))
  (check "IN AL, DX"    (bytes= (asm "IN AL, DX")    #xEC))
  (check "IN AX, DX"    (bytes= (asm "IN AX, DX")    #xED))
  (check "OUT $60, AL"  (bytes= (asm "OUT $60, AL")  #xE6 #x60))
  (check "OUT $60, AX"  (bytes= (asm "OUT $60, AX")  #xE7 #x60))
  (check "OUT DX, AL"   (bytes= (asm "OUT DX, AL")   #xEE))
  (check "OUT DX, AX"   (bytes= (asm "OUT DX, AX")   #xEF)))


;;; --------------------------------------------------------------------------
;;;  Tests : Modes d'adressage mémoire
;;; --------------------------------------------------------------------------

(deftest test/addressing-modes
  ;; mod=00 : [reg] sans déplacement
  (check "[BX]   rm=7 mod=00" (bytes= (asm "MOV AX, [BX]")   #x8B #x07))
  (check "[SI]   rm=4 mod=00" (bytes= (asm "MOV AX, [SI]")   #x8B #x04))
  (check "[DI]   rm=5 mod=00" (bytes= (asm "MOV AX, [DI]")   #x8B #x05))
  (check "[BX+SI] rm=0 mod=00" (bytes= (asm "MOV AX, [BX+SI]") #x8B #x00))
  (check "[BX+DI] rm=1 mod=00" (bytes= (asm "MOV AX, [BX+DI]") #x8B #x01))
  (check "[BP+SI] rm=2 mod=00" (bytes= (asm "MOV AX, [BP+SI]") #x8B #x02))
  (check "[BP+DI] rm=3 mod=00" (bytes= (asm "MOV AX, [BP+DI]") #x8B #x03))
  ;; [BP] seul → doit utiliser mod=10 disp=0 (mod=00 rm=6 = adresse directe)
  (check "[BP] = mod=10 disp16=0"
         (bytes= (asm "MOV AX, [BP]")  #x8B #x86 #x00 #x00))
  ;; Adresse directe [imm16]
  (check "[$1234] adresse directe"
         (bytes= (asm "MOV AX, [$1234]") #x8B #x06 #x34 #x12))
  ;; mod=10 : [reg+disp16]
  (check "[BX+$100] mod=10"
         (bytes= (asm "MOV AX, [BX+$100]") #x8B #x87 #x00 #x01))
  (check "[BP+$50] mod=10"
         (bytes= (asm "MOV AX, [BP+$50]") #x8B #x86 #x50 #x00)))


;;; --------------------------------------------------------------------------
;;;  Tests : Labels et sauts
;;; --------------------------------------------------------------------------

(deftest test/labels
  ;; Saut en avant
  (check "JNE forward label"
         (let ((bytes (asm "
start:
  MOV AX, 0
  CMP AX, BX
  JNE done
  INC AX
done:
  RET")))
           ;; MOV AX,0=3 CMP AX,BX=2 JNE=2 INC AX=1 RET=1 = 9 octets
           (= (length bytes) 9)))
  ;; LOOP avec label
  (check "LOOP backward label"
         (let ((bytes (asm "
  MOV CX, 10
loop:
  DEC AX
  LOOP loop")))
           ;; MOV CX,10=3 DEC AX=1 LOOP=2 = 6 octets
           (and (= (length bytes) 6)
                ;; offset LOOP = $05 - $06 = $FF = -1 → #xFF
                (= (aref bytes 5) #xFD)))))  ; rel = -(3) = -3 → #xFD


;;; --------------------------------------------------------------------------
;;;  Tests : directives de données
;;; --------------------------------------------------------------------------

(deftest test/directives
  (check ".org change l'adresse"
         (let ((bytes (asm ".org $100
MOV AX, 0")))
           (bytes= bytes #xB8 #x00 #x00)))
  (check ".byte émet des octets"
         (bytes= (asm ".byte $42, $FF, 0")  #x42 #xFF #x00))
  (check ".word émet des mots LE"
         (bytes= (asm ".word $1234, $5678") #x34 #x12 #x78 #x56)))


;;; --------------------------------------------------------------------------
;;;  Lanceur de la suite
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&~%=== Tests Intel 8086 ===~%")
  (test/implied)
  (test/mov-reg-imm)
  (test/mov-reg-reg)
  (test/mov-reg-mem)
  (test/mov-mem-reg)
  (test/mov-mem-imm)
  (test/mov-sreg)
  (test/alu-reg-imm)
  (test/alu-reg-reg)
  (test/alu-mem)
  (test/adc-sbb)
  (test/inc-dec)
  (test/unary)
  (test/push-pop)
  (test/xchg)
  (test/lea)
  (test/shifts)
  (test/jcc)
  (test/loop)
  (test/jmp)
  (test/call-ret)
  (test/int)
  (test/in-out)
  (test/addressing-modes)
  (test/labels)
  (test/directives)
  (format t "~&~%=== 8086 : ~D OK, ~D KO ===~%"
          *pass* *fail*))
