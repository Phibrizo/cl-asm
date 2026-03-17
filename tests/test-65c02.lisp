; -*- coding: utf-8 -*-
;;; tests/test-65c02.lisp

(defpackage #:cl-asm/test.65c02
  (:use #:cl)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.65c02)

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

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&~%[~A]~%" ',name)
     ,@body))

(defun asm (source &key (origin #x0801))
  (cl-asm/backend.65c02:assemble-string-65c02 source :origin origin))

(defun bytes= (vec &rest expected)
  (and (= (length vec) (length expected))
       (every #'= vec expected)))


;;; --------------------------------------------------------------------------
;;;  Tests : compatibilite 6502 (les instructions de base doivent fonctionner)
;;; --------------------------------------------------------------------------

(deftest test/6502-compat-nop
  (check "NOP = $EA" (bytes= (asm "NOP") #xEA))
  (check "RTS = $60" (bytes= (asm "RTS") #x60))
  (check "CLC = $18" (bytes= (asm "CLC") #x18)))

(deftest test/6502-compat-lda
  (check "LDA #$FF = A9 FF" (bytes= (asm "LDA #$FF") #xA9 #xFF))
  (check "LDA $10 = A5 10"  (bytes= (asm "LDA $10")  #xA5 #x10))
  (check "LDA $1234 = AD 34 12" (bytes= (asm "LDA $1234") #xAD #x34 #x12)))


;;; --------------------------------------------------------------------------
;;;  Tests : nouvelles instructions 65C02
;;; --------------------------------------------------------------------------

(deftest test/bra
  ;; BRA : branche inconditionnelle relative, opcode $80
  (let* ((src ".org $1000
               BRA target
               NOP
               target:
               RTS")
         (bytes (asm src :origin #x1000)))
    (check "BRA opcode = $80" (= #x80 (aref bytes 0)))
    (check "BRA offset = 1"   (= 1    (aref bytes 1)))  ; saute le NOP
    (check "NOP apres BRA"    (= #xEA (aref bytes 2)))
    (check "RTS a target"     (= #x60 (aref bytes 3)))))

(deftest test/stz
  (check "STZ zp = 64 10"       (bytes= (asm "STZ $10")      #x64 #x10))
  (check "STZ zp,X = 74 10"     (bytes= (asm "STZ $10,X")    #x74 #x10))
  (check "STZ abs = 9C 34 12"   (bytes= (asm "STZ $1234")    #x9C #x34 #x12))
  (check "STZ abs,X = 9E 34 12" (bytes= (asm "STZ $1234,X")  #x9E #x34 #x12)))

(deftest test/trb-tsb
  (check "TRB zp = 14 10"  (bytes= (asm "TRB $10")    #x14 #x10))
  (check "TRB abs = 1C"    (bytes= (asm "TRB $1234")   #x1C #x34 #x12))
  (check "TSB zp = 04 10"  (bytes= (asm "TSB $10")     #x04 #x10))
  (check "TSB abs = 0C"    (bytes= (asm "TSB $1234")   #x0C #x34 #x12)))

(deftest test/push-pull-xy
  (check "PHX = $DA" (bytes= (asm "PHX") #xDA))
  (check "PLX = $FA" (bytes= (asm "PLX") #xFA))
  (check "PHY = $5A" (bytes= (asm "PHY") #x5A))
  (check "PLY = $7A" (bytes= (asm "PLY") #x7A)))

(deftest test/inc-dec-accumulator
  (check "INC A = $1A" (bytes= (asm "INC A") #x1A))
  (check "DEC A = $3A" (bytes= (asm "DEC A") #x3A)))

(deftest test/zero-page-indirect
  ;; LDA ($nn) sans index — nouveau mode 65C02
  (check "LDA (zp) = B2 10"   (bytes= (asm "LDA ($10)")    #xB2 #x10))
  (check "STA (zp) = 92 20"   (bytes= (asm "STA ($20)")    #x92 #x20))
  (check "ADC (zp) = 72 30"   (bytes= (asm "ADC ($30)")    #x72 #x30))
  (check "AND (zp) = 32 40"   (bytes= (asm "AND ($40)")    #x32 #x40))
  (check "ORA (zp) = 12 50"   (bytes= (asm "ORA ($50)")    #x12 #x50))
  (check "EOR (zp) = 52 60"   (bytes= (asm "EOR ($60)")    #x52 #x60))
  (check "CMP (zp) = D2 70"   (bytes= (asm "CMP ($70)")    #xD2 #x70))
  (check "SBC (zp) = F2 80"   (bytes= (asm "SBC ($80)")    #xF2 #x80)))

(deftest test/bit-extended
  ;; BIT avec modes nouveaux sur 65C02
  (check "BIT #imm = 89 FF"    (bytes= (asm "BIT #$FF")    #x89 #xFF))
  (check "BIT zp,X = 34 10"    (bytes= (asm "BIT $10,X")   #x34 #x10))
  (check "BIT abs,X = 3C 34 12" (bytes= (asm "BIT $1234,X") #x3C #x34 #x12)))

(deftest test/jmp-indirect-x
  ;; JMP ($addr,X) — indirect indexe X
  (check "JMP (abs,X) = 7C 34 12"
         (bytes= (asm "JMP ($1234,X)") #x7C #x34 #x12)))


;;; --------------------------------------------------------------------------
;;;  Tests : programme X16 complet
;;; --------------------------------------------------------------------------

(deftest test/x16-hello
  ;; Programme minimaliste X16 : quelques instructions 65C02
  (let* ((src ".org $0801
               ; Stub BASIC
               .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$34,$00,$00,$00
               ; Code
               start:
               STZ $9F20        ; VERA addr lo = 0
               STZ $9F21        ; VERA addr hi = 0
               STZ $9F22        ; VERA addr bank = 0
               LDA #$80
               STA $9F22        ; activer auto-increment
               LDA #$48         ; 'H'
               STA $9F23        ; ecrire dans VERA data
               BRA start        ; boucle (test BRA)
               RTS")
         (bytes (asm src :origin #x0801)))
    (check "au moins 20 octets"  (>= (length bytes) 20))
    (check "stub BASIC debut"    (= #x0B (aref bytes 0)))
    ;; STZ $9F20 = 9C 20 9F
    (check "STZ $9F20 = 9C"      (= #x9C (aref bytes 12)))
    (check "STZ addr lo = $20"   (= #x20 (aref bytes 13)))
    (check "STZ addr hi = $9F"   (= #x9F (aref bytes 14)))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests cl-asm/65c02 ===~%")
  (test/6502-compat-nop)
  (test/6502-compat-lda)
  (test/bra)
  (test/stz)
  (test/trb-tsb)
  (test/push-pull-xy)
  (test/inc-dec-accumulator)
  (test/zero-page-indirect)
  (test/bit-extended)
  (test/jmp-indirect-x)
  (test/x16-hello)
  (when *failures*
    (format t "~&Echecs 65c02 :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
