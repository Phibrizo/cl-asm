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
;;;  Test : anonymous labels, scoped @labels, .res, forward-ref immediate
;;; --------------------------------------------------------------------------

(deftest test/anon-scoped-labels
  ;; Programme avec :, :-, @labels scopés, .res, .byte "str", forward-ref imm
  (let* ((src ".org $0801
               .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00
               main:
               ldx #5
               :
               dex
               bne :-
               ldx #<data
               ldy #>data
               jsr routine1
               jsr routine2
               rts
               routine1:
               ldy #3
               @loop:
               dey
               bne @loop
               rts
               routine2:
               ldy #2
               @loop:
               dey
               bne @loop
               rts
               buffer: .res 4
               data: .byte \"Hi\",0")
         (bytes (asm src :origin #x0801)))
    ;; Taille brute (sans header PRG) : 47 octets
    (check "taille totale 47"          (= (length bytes) 47))
    ;; BASIC stub
    (check "stub[0] = $0B"             (= #x0B (aref bytes 0)))
    ;; ldx #5 : après stub (offset 12-13)
    (check "ldx #5 opcode A2"          (= #xA2 (aref bytes 12)))
    (check "ldx #5 operande 05"        (= #x05 (aref bytes 13)))
    ;; dex : offset 14 (anonymous label ici)
    (check "dex = CA"                  (= #xCA (aref bytes 14)))
    ;; bne :- : offset 15-16, offset rel = $FD (-3)
    (check "bne opcode D0"             (= #xD0 (aref bytes 15)))
    (check "bne :- offset = FD"        (= #xFD (aref bytes 16)))
    ;; ldx #<data : forward-ref immédiat, data=$082D → low=$2D
    (check "ldx #<data opcode A2"      (= #xA2 (aref bytes 17)))
    (check "ldx #<data = $2D"          (= #x2D (aref bytes 18)))
    ;; ldy #>data : forward-ref immédiat → high=$08
    (check "ldy #>data opcode A0"      (= #xA0 (aref bytes 19)))
    (check "ldy #>data = $08"          (= #x08 (aref bytes 20)))
    ;; routine1 : ldy #3, @loop dey, bne -3, rts (offset 28-33)
    (check "routine1 ldy #3 opcode"    (= #xA0 (aref bytes 28)))
    (check "routine1 ldy #3 = 03"      (= #x03 (aref bytes 29)))
    (check "routine1 @loop dey = 88"   (= #x88 (aref bytes 30)))
    (check "routine1 bne D0"           (= #xD0 (aref bytes 31)))
    (check "routine1 bne offset FD"    (= #xFD (aref bytes 32)))
    (check "routine1 rts = 60"         (= #x60 (aref bytes 33)))
    ;; routine2 : ldy #2, @loop dey, bne -3, rts (offset 34-39)
    (check "routine2 ldy #2 opcode"    (= #xA0 (aref bytes 34)))
    (check "routine2 ldy #2 = 02"      (= #x02 (aref bytes 35)))
    (check "routine2 @loop dey = 88"   (= #x88 (aref bytes 36)))
    (check "routine2 bne D0"           (= #xD0 (aref bytes 37)))
    (check "routine2 bne offset FD"    (= #xFD (aref bytes 38)))
    (check "routine2 rts = 60"         (= #x60 (aref bytes 39)))
    ;; buffer .res 4 → 4 zéros (offset 40-43)
    (check ".res 4 → zero[0]"          (= #x00 (aref bytes 40)))
    (check ".res 4 → zero[3]"          (= #x00 (aref bytes 43)))
    ;; data .byte "Hi",0 → 48 69 00 (offset 44-46)
    (check ".byte H = $48"             (= #x48 (aref bytes 44)))
    (check ".byte i = $69"             (= #x69 (aref bytes 45)))
    (check ".byte nul = $00"           (= #x00 (aref bytes 46)))))


;;; --------------------------------------------------------------------------
;;;  Test : syntaxe ACME (!to ignoré, !cpu ignoré, *=addr, !BYTE, !PET)
;;; --------------------------------------------------------------------------

(deftest test/acme-syntax
  (let* ((src "!to \"out.prg\",cbm
               !cpu 65c02
               *=$0801
               !BYTE $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00
               start:
               LDA #$00
               STA $9F20
               RTS
               raw_data:
               !BYTE $61,$62,$63,0
               pet_lower:
               !PET \"abc\",13,0
               pet_upper:
               !PET \"ABC\",0")
         (bytes (asm src :origin #x0801)))
    ;; Taille totale : 31 octets bruts
    (check "taille totale 31"          (= (length bytes) 31))
    ;; *=$0801 → .org reconnu, stub BASIC en tête
    (check "stub[0] = $0B"             (= #x0B (aref bytes 0)))
    ;; LDA #$00 à l'offset 12
    (check "LDA #$00 opcode"           (= #xA9 (aref bytes 12)))
    (check "LDA #$00 operande"         (= #x00 (aref bytes 13)))
    ;; !BYTE $61,$62,$63,0 → valeurs brutes (offset 18-21)
    (check "!BYTE $61 = 61"            (= #x61 (aref bytes 18)))
    (check "!BYTE $62 = 62"            (= #x62 (aref bytes 19)))
    (check "!BYTE $63 = 63"            (= #x63 (aref bytes 20)))
    (check "!BYTE 0   = 00"            (= #x00 (aref bytes 21)))
    ;; !PET "abc",13,0 → PETSCII : a→$41 b→$42 c→$43 CR $0D null (offset 22-26)
    (check "!PET a → $41 (PETSCII A)"  (= #x41 (aref bytes 22)))
    (check "!PET b → $42 (PETSCII B)"  (= #x42 (aref bytes 23)))
    (check "!PET c → $43 (PETSCII C)"  (= #x43 (aref bytes 24)))
    (check "!PET 13 → $0D (CR)"        (= #x0D (aref bytes 25)))
    (check "!PET 0  → $00"             (= #x00 (aref bytes 26)))
    ;; !PET "ABC",0 → PETSCII shifted : A→$C1 B→$C2 C→$C3 (offset 27-30)
    (check "!PET A → $C1 (shifted)"    (= #xC1 (aref bytes 27)))
    (check "!PET B → $C2 (shifted)"    (= #xC2 (aref bytes 28)))
    (check "!PET C → $C3 (shifted)"    (= #xC3 (aref bytes 29)))
    (check "!PET 0 → $00"              (= #x00 (aref bytes 30)))))


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
  (test/anon-scoped-labels)
  (test/acme-syntax)
  (when *failures*
    (format t "~&Echecs 65c02 :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
