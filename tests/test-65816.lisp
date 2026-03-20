; -*- coding: utf-8 -*-
;;; tests/test-65816.lisp

(defpackage #:cl-asm/test.65816
  (:use #:cl #:cl-asm/backend.65816)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.65816)


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


;;; --------------------------------------------------------------------------
;;;  Helpers
;;; --------------------------------------------------------------------------

(defun asm (source &key (origin #x8000))
  "Assemble SOURCE pour le 65816."
  (assemble-string-65816 source :origin origin))

(defun bytes= (vec &rest expected)
  (and (= (length vec) (length expected))
       (every #'= vec expected)))

(defun starts-with (vec &rest expected)
  (and (>= (length vec) (length expected))
       (every #'= vec expected)))


;;; --------------------------------------------------------------------------
;;;  Compatibilite 6502
;;; --------------------------------------------------------------------------

(deftest test/6502-compat-implied
  (check "NOP = $EA"  (bytes= (asm "NOP") #xEA))
  (check "RTS = $60"  (bytes= (asm "RTS") #x60))
  (check "CLC = $18"  (bytes= (asm "CLC") #x18))
  (check "SEI = $78"  (bytes= (asm "SEI") #x78))
  (check "PHA = $48"  (bytes= (asm "PHA") #x48))
  (check "PLA = $68"  (bytes= (asm "PLA") #x68)))

(deftest test/6502-compat-lda
  (check "LDA #$FF = A9 FF"    (bytes= (asm "LDA #$FF") #xA9 #xFF))
  (check "LDA $10 = A5 10"     (bytes= (asm "LDA $10")  #xA5 #x10))
  (check "LDA $1234 = AD 34 12" (bytes= (asm "LDA $1234") #xAD #x34 #x12))
  (check "STA $D020 = 8D 20 D0" (bytes= (asm "STA $D020") #x8D #x20 #xD0)))

(deftest test/6502-compat-branches
  (check "BNE forward"
         (let ((v (asm ".org $8000
BNE end
NOP
end: RTS")))
           (and (= (aref v 0) #xD0)   ; BNE
                (= (aref v 1) 1)      ; offset +1
                (= (aref v 2) #xEA)   ; NOP
                (= (aref v 3) #x60)))) ; RTS
  (check "BRA = $80"  (starts-with (asm "BRA end
NOP
end: RTS") #x80)))


;;; --------------------------------------------------------------------------
;;;  Nouvelles instructions implied du 65816
;;; --------------------------------------------------------------------------

(deftest test/implied-65816
  (check "PHB = $8B"  (bytes= (asm "PHB") #x8B))
  (check "PLB = $AB"  (bytes= (asm "PLB") #xAB))
  (check "PHD = $0B"  (bytes= (asm "PHD") #x0B))
  (check "PLD = $2B"  (bytes= (asm "PLD") #x2B))
  (check "PHK = $4B"  (bytes= (asm "PHK") #x4B))
  (check "RTL = $6B"  (bytes= (asm "RTL") #x6B))
  (check "WAI = $CB"  (bytes= (asm "WAI") #xCB))
  (check "STP = $DB"  (bytes= (asm "STP") #xDB))
  (check "XBA = $EB"  (bytes= (asm "XBA") #xEB))
  (check "XCE = $FB"  (bytes= (asm "XCE") #xFB))
  (check "TCD = $5B"  (bytes= (asm "TCD") #x5B))
  (check "TCS = $1B"  (bytes= (asm "TCS") #x1B))
  (check "TDC = $7B"  (bytes= (asm "TDC") #x7B))
  (check "TSC = $3B"  (bytes= (asm "TSC") #x3B))
  (check "TXY = $9B"  (bytes= (asm "TXY") #x9B))
  (check "TYX = $BB"  (bytes= (asm "TYX") #xBB)))

(deftest test/65c02-compat-implied
  (check "PHX = $DA"  (bytes= (asm "PHX") #xDA))
  (check "PLX = $FA"  (bytes= (asm "PLX") #xFA))
  (check "PHY = $5A"  (bytes= (asm "PHY") #x5A))
  (check "PLY = $7A"  (bytes= (asm "PLY") #x7A)))


;;; --------------------------------------------------------------------------
;;;  Adressage absolute long (24 bits)
;;; --------------------------------------------------------------------------

(deftest test/absolute-long
  (check "LDA $123456 : 4 octets"
         (= 4 (length (asm "LDA $123456"))))
  (check "LDA $123456 opcode = $AF"
         (= #xAF (aref (asm "LDA $123456") 0)))
  (check "LDA $123456 octet 1 = $56"
         (= #x56 (aref (asm "LDA $123456") 1)))
  (check "LDA $123456 octet 2 = $34"
         (= #x34 (aref (asm "LDA $123456") 2)))
  (check "LDA $123456 octet 3 = $12"
         (= #x12 (aref (asm "LDA $123456") 3)))
  (check "STA $7E0000 : 4 octets"
         (= 4 (length (asm "STA $7E0000"))))
  (check "STA $7E0000 opcode = $8F"
         (= #x8F (aref (asm "STA $7E0000") 0)))
  (check "LDA $123456,X opcode = $BF"
         (= #xBF (aref (asm "LDA $123456,X") 0))))

(deftest test/jsl-jml
  (check "JSL $123456 : 4 octets"
         (= 4 (length (asm "JSL $123456"))))
  (check "JSL $123456 opcode = $22"
         (= #x22 (aref (asm "JSL $123456") 0)))
  (check "JSL $123456 octets addr"
         (bytes= (asm "JSL $123456") #x22 #x56 #x34 #x12))
  (check "JML $123456 opcode = $5C"
         (= #x5C (aref (asm "JML $123456") 0)))
  (check "JML $123456 : 4 octets"
         (= 4 (length (asm "JML $123456")))))


;;; --------------------------------------------------------------------------
;;;  Indirect long
;;; --------------------------------------------------------------------------

(deftest test/dp-indirect-long
  (check "LDA [$10] : 2 octets"
         (= 2 (length (asm "LDA [$10]"))))
  (check "LDA [$10] opcode = $A7"
         (= #xA7 (aref (asm "LDA [$10]") 0)))
  (check "LDA [$10] addr = $10"
         (= #x10 (aref (asm "LDA [$10]") 1)))
  (check "STA [$20] opcode = $87"
         (= #x87 (aref (asm "STA [$20]") 0)))
  (check "ADC [$30] opcode = $67"
         (= #x67 (aref (asm "ADC [$30]") 0))))

(deftest test/jmp-indirect-long
  ;; JMP [$nnnn] — indirect absolu long (3 octets : opcode + adresse 16-bit)
  (check "JMP [$2000] : 3 octets"
         (= 3 (length (asm "JMP [$2000]"))))
  (check "JMP [$2000] opcode = $DC"
         (= #xDC (aref (asm "JMP [$2000]") 0)))
  (check "JMP [$2000] addr lo = $00"
         (= #x00 (aref (asm "JMP [$2000]") 1)))
  (check "JMP [$2000] addr hi = $20"
         (= #x20 (aref (asm "JMP [$2000]") 2))))


;;; --------------------------------------------------------------------------
;;;  Stack relative indirect indexed Y (($nn,S),Y)
;;; --------------------------------------------------------------------------

(deftest test/sr-indirect-y
  ;; ($nn,SP),Y est deja supporte par le parser (kind :indirect-sp-y)
  (check "LDA ($05,SP),Y : 2 octets"
         (= 2 (length (asm "LDA ($05,SP),Y"))))
  (check "LDA ($05,SP),Y opcode = $B3"
         (= #xB3 (aref (asm "LDA ($05,SP),Y") 0)))
  (check "LDA ($05,SP),Y operande = $05"
         (= #x05 (aref (asm "LDA ($05,SP),Y") 1)))
  (check "STA ($02,SP),Y opcode = $93"
         (= #x93 (aref (asm "STA ($02,SP),Y") 0))))


;;; --------------------------------------------------------------------------
;;;  BRL — branche longue
;;; --------------------------------------------------------------------------

(deftest test/brl
  ;; BRL (3) + NOP (1) + RTS (1) = 5 octets au total
  (check "BRL forward : programme = 5 octets"
         (= 5 (length (asm "BRL end
NOP
end: RTS"))))
  (check "BRL forward opcode = $82"
         (= #x82 (aref (asm "BRL end
NOP
end: RTS") 0)))
  (check "BRL forward offset lo = 1"
         (= 1 (aref (asm "BRL end
NOP
end: RTS") 1)))
  (check "BRL forward offset hi = 0"
         (= 0 (aref (asm "BRL end
NOP
end: RTS") 2)))
  (check "BRL hors portee -> asm-range-error"
         (handler-case
             (progn
               (cl-asm/backend.65816:assemble-string-65816
                ".org $8000
BRL end
.fill 33000
end: NOP")
               nil)
           (cl-asm/ir:asm-range-error () t)
           (error () nil))))


;;; --------------------------------------------------------------------------
;;;  REP / SEP
;;; --------------------------------------------------------------------------

(deftest test/rep-sep
  (check "REP #$30 : 2 octets"  (= 2 (length (asm "REP #$30"))))
  (check "REP #$30 opcode = $C2" (= #xC2 (aref (asm "REP #$30") 0)))
  (check "REP #$30 operande = $30" (= #x30 (aref (asm "REP #$30") 1)))
  (check "SEP #$20 opcode = $E2" (= #xE2 (aref (asm "SEP #$20") 0)))
  (check "SEP #$20 operande = $20" (= #x20 (aref (asm "SEP #$20") 1))))


;;; --------------------------------------------------------------------------
;;;  Directives de mode et immediat 16 bits
;;; --------------------------------------------------------------------------

(deftest test/mode-directives-immediate
  ;; 8-bit par defaut
  (check "LDA #$FF 8-bit = 2 octets"
         (= 2 (length (asm "LDA #$FF"))))
  ;; .al → accumulateur 16-bit
  (check "apres .al : LDA #$1234 = 3 octets"
         (= 3 (length (asm ".al
LDA #$1234"))))
  (check "apres .al : LDA #$1234 opcode = $A9"
         (= #xA9 (aref (asm ".al
LDA #$1234") 0)))
  (check "apres .al : LDA #$1234 lo = $34"
         (= #x34 (aref (asm ".al
LDA #$1234") 1)))
  (check "apres .al : LDA #$1234 hi = $12"
         (= #x12 (aref (asm ".al
LDA #$1234") 2)))
  ;; .as → retour en 8-bit
  (check "apres .al .as : LDA #$FF = 2 octets"
         (= 2 (length (asm ".al
.as
LDA #$FF"))))
  ;; .xl → index 16-bit
  (check "apres .xl : LDX #$1234 = 3 octets"
         (= 3 (length (asm ".xl
LDX #$1234"))))
  (check "apres .xl : LDY #$0100 lo = $00"
         (= #x00 (aref (asm ".xl
LDY #$0100") 1)))
  (check "apres .xl : LDY #$0100 hi = $01"
         (= #x01 (aref (asm ".xl
LDY #$0100") 2)))
  ;; .xs → retour index 8-bit
  (check "apres .xl .xs : LDX #$FF = 2 octets"
         (= 2 (length (asm ".xl
.xs
LDX #$FF"))))
  ;; instruction non-M reste 8-bit meme apres .al
  (check "REP reste 8-bit apres .al"
         (= 2 (length (asm ".al
REP #$30")))))


;;; --------------------------------------------------------------------------
;;;  MVN / MVP — block move
;;; --------------------------------------------------------------------------

(deftest test/block-move
  (check "MVN $00,$7E : 3 octets"
         (= 3 (length (asm "MVN $00,$7E"))))
  (check "MVN $00,$7E opcode = $54"
         (= #x54 (aref (asm "MVN $00,$7E") 0)))
  (check "MVN $00,$7E dst = $00"
         (= #x00 (aref (asm "MVN $00,$7E") 1)))
  (check "MVN $00,$7E src = $7E"
         (= #x7E (aref (asm "MVN $00,$7E") 2)))
  (check "MVP $7E,$00 opcode = $44"
         (= #x44 (aref (asm "MVP $7E,$00") 0)))
  (check "MVP $7E,$00 dst = $7E"
         (= #x7E (aref (asm "MVP $7E,$00") 1)))
  (check "MVP $7E,$00 src = $00"
         (= #x00 (aref (asm "MVP $7E,$00") 2))))


;;; --------------------------------------------------------------------------
;;;  PEA
;;; --------------------------------------------------------------------------

(deftest test/pea
  (check "PEA #$1234 : 3 octets"  (= 3 (length (asm "PEA #$1234"))))
  (check "PEA #$1234 opcode = $F4" (= #xF4 (aref (asm "PEA #$1234") 0)))
  (check "PEA #$1234 lo = $34"    (= #x34 (aref (asm "PEA #$1234") 1)))
  (check "PEA #$1234 hi = $12"    (= #x12 (aref (asm "PEA #$1234") 2))))


;;; --------------------------------------------------------------------------
;;;  Forward references
;;; --------------------------------------------------------------------------

(deftest test/forward-ref-65816
  (check "JMP forward = 4C"
         (= #x4C (aref (asm ".org $8000
JMP target
NOP
target: RTS") 0)))
  (check "JMP target hi = $80"
         (= #x80 (aref (asm ".org $8000
JMP target
NOP
target: RTS") 2)))
  (check "JSL forward : programme = 7 octets (JSL4+RTS1+NOP1+RTL1)"
         (= 7 (length (asm ".org $8000
JSL sub
RTS
sub: NOP
RTL"))))
  (check "JSL sub opcode = $22"
         (= #x22 (aref (asm ".org $8000
JSL sub
RTS
sub: NOP
RTL") 0))))


;;; --------------------------------------------------------------------------
;;;  Erreurs
;;; --------------------------------------------------------------------------

(deftest test/errors-65816
  (check-error "mnemonique inconnu -> asm-unknown-mnemonic"
               cl-asm/ir:asm-unknown-mnemonic
               (asm "FOOBAR"))
  (check-error "mode invalide -> asm-syntax-error"
               cl-asm/ir:asm-syntax-error
               (asm "RTL #$00")))  ; RTL n'a pas de mode immediat


;;; --------------------------------------------------------------------------
;;;  Programme SNES minimal
;;; --------------------------------------------------------------------------

(deftest test/snes-minimal
  (let ((v (asm ".org $8000
    CLC
    XCE          ; passe en mode natif 65816
    REP #$30     ; M=0 X=0 (16-bit)
    .al
    .xl
    LDA #$0000
    LDX #$01FF
    TXS          ; init stack
    RTL")))
    (check "programme SNES : au moins 9 octets"
           (>= (length v) 9))
    (check "CLC = $18"   (= #x18 (aref v 0)))
    (check "XCE = $FB"   (= #xFB (aref v 1)))
    (check "REP = $C2"   (= #xC2 (aref v 2)))
    (check "REP #$30"    (= #x30 (aref v 3)))
    (check "LDA #$0000 opcode = $A9" (= #xA9 (aref v 4)))
    (check "LDA #$0000 lo = $00"     (= #x00 (aref v 5)))
    (check "LDA #$0000 hi = $00"     (= #x00 (aref v 6)))))


;;; --------------------------------------------------------------------------
;;;  Orchestration
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests cl-asm/backend.65816 ===~%")
  (test/6502-compat-implied)
  (test/6502-compat-lda)
  (test/6502-compat-branches)
  (test/implied-65816)
  (test/65c02-compat-implied)
  (test/absolute-long)
  (test/jsl-jml)
  (test/dp-indirect-long)
  (test/jmp-indirect-long)
  (test/sr-indirect-y)
  (test/brl)
  (test/rep-sep)
  (test/mode-directives-immediate)
  (test/block-move)
  (test/pea)
  (test/forward-ref-65816)
  (test/errors-65816)
  (test/snes-minimal)
  (zerop *fail*))
