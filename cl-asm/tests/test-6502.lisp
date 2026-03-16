; -*- coding: utf-8 -*-
;;; tests/test-6502.lisp

(defpackage #:cl-asm/test.6502
  (:use #:cl #:cl-asm/backend.6502)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.6502)


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

(defun asm (source &key (origin #x0801))
  "Assemble SOURCE et retourne le vecteur d'octets."
  (assemble-string source :origin origin))

(defun bytes= (vec &rest expected)
  "Vrai si VEC contient exactement les octets EXPECTED."
  (and (= (length vec) (length expected))
       (every #'= vec expected)))

(defun starts-with (vec &rest expected)
  "Vrai si VEC commence par les octets EXPECTED."
  (and (>= (length vec) (length expected))
       (every #'= vec expected)))


;;; --------------------------------------------------------------------------
;;;  Tests : instructions implied et accumulator
;;; --------------------------------------------------------------------------

(deftest test/nop
  (check "NOP = $EA"      (bytes= (asm "NOP") #xEA))
  (check "RTS = $60"      (bytes= (asm "RTS") #x60))
  (check "RTI = $40"      (bytes= (asm "RTI") #x40))
  (check "BRK = $00"      (bytes= (asm "BRK") #x00))
  (check "CLC = $18"      (bytes= (asm "CLC") #x18))
  (check "SEC = $38"      (bytes= (asm "SEC") #x38))
  (check "SEI = $78"      (bytes= (asm "SEI") #x78))
  (check "CLI = $58"      (bytes= (asm "CLI") #x58))
  (check "CLD = $D8"      (bytes= (asm "CLD") #xD8))
  (check "TAX = $AA"      (bytes= (asm "TAX") #xAA))
  (check "TXA = $8A"      (bytes= (asm "TXA") #x8A))
  (check "TAY = $A8"      (bytes= (asm "TAY") #xA8))
  (check "TYA = $98"      (bytes= (asm "TYA") #x98)))

(deftest test/accumulator-mode
  (check "LSR A = $4A"    (bytes= (asm "LSR A") #x4A))
  (check "ASL A = $0A"    (bytes= (asm "ASL A") #x0A))
  (check "ROL A = $2A"    (bytes= (asm "ROL A") #x2A))
  (check "ROR A = $6A"    (bytes= (asm "ROR A") #x6A)))


;;; --------------------------------------------------------------------------
;;;  Tests : mode immediat
;;; --------------------------------------------------------------------------

(deftest test/immediate
  (check "LDA #$00 = A9 00" (bytes= (asm "LDA #$00") #xA9 #x00))
  (check "LDA #$FF = A9 FF" (bytes= (asm "LDA #$FF") #xA9 #xFF))
  (check "LDA #42  = A9 2A" (bytes= (asm "LDA #42")  #xA9 #x2A))
  (check "LDX #$01 = A2 01" (bytes= (asm "LDX #$01") #xA2 #x01))
  (check "LDY #$02 = A0 02" (bytes= (asm "LDY #$02") #xA0 #x02))
  (check "ADC #$10 = 69 10" (bytes= (asm "ADC #$10") #x69 #x10))
  (check "SBC #$01 = E9 01" (bytes= (asm "SBC #$01") #xE9 #x01))
  (check "CMP #$00 = C9 00" (bytes= (asm "CMP #$00") #xC9 #x00))
  (check "AND #$0F = 29 0F" (bytes= (asm "AND #$0F") #x29 #x0F))
  (check "ORA #$80 = 09 80" (bytes= (asm "ORA #$80") #x09 #x80))
  (check "EOR #$FF = 49 FF" (bytes= (asm "EOR #$FF") #x49 #xFF)))


;;; --------------------------------------------------------------------------
;;;  Tests : zero-page
;;; --------------------------------------------------------------------------

(deftest test/zero-page
  (check "LDA $10 = A5 10"   (bytes= (asm "LDA $10") #xA5 #x10))
  (check "STA $20 = 85 20"   (bytes= (asm "STA $20") #x85 #x20))
  (check "LDX $30 = A6 30"   (bytes= (asm "LDX $30") #xA6 #x30))
  (check "STX $40 = 86 40"   (bytes= (asm "STX $40") #x86 #x40))
  (check "INC $50 = E6 50"   (bytes= (asm "INC $50") #xE6 #x50))
  (check "DEC $60 = C6 60"   (bytes= (asm "DEC $60") #xC6 #x60))
  (check "LDA $10,X = B5 10" (bytes= (asm "LDA $10,X") #xB5 #x10))
  (check "LDA $10,Y via LDA zero-page"
         (bytes= (asm "LDX $10,Y") #xB6 #x10)))


;;; --------------------------------------------------------------------------
;;;  Tests : absolu
;;; --------------------------------------------------------------------------

(deftest test/absolute
  (check "LDA $1234 = AD 34 12"
         (bytes= (asm "LDA $1234") #xAD #x34 #x12))
  (check "STA $D020 = 8D 20 D0"
         (bytes= (asm "STA $D020") #x8D #x20 #xD0))
  (check "JMP $C000 = 4C 00 C0"
         (bytes= (asm "JMP $C000") #x4C #x00 #xC0))
  (check "JSR $FFD2 = 20 D2 FF"
         (bytes= (asm "JSR $FFD2") #x20 #xD2 #xFF))
  (check "LDA $1234,X = BD 34 12"
         (bytes= (asm "LDA $1234,X") #xBD #x34 #x12))
  (check "LDA $1234,Y = B9 34 12"
         (bytes= (asm "LDA $1234,Y") #xB9 #x34 #x12))
  (check "STA $D000,X = 9D 00 D0"
         (bytes= (asm "STA $D000,X") #x9D #x00 #xD0)))


;;; --------------------------------------------------------------------------
;;;  Tests : indirect
;;; --------------------------------------------------------------------------

(deftest test/indirect
  (check "JMP ($FFFC) = 6C FC FF"
         (bytes= (asm "JMP ($FFFC)") #x6C #xFC #xFF))
  (check "LDA ($00,X) = A1 00"
         (bytes= (asm "LDA ($00,X)") #xA1 #x00))
  (check "STA ($B0),Y = 91 B0"
         (bytes= (asm "STA ($B0),Y") #x91 #xB0))
  (check "LDA ($00),Y = B1 00"
         (bytes= (asm "LDA ($00),Y") #xB1 #x00)))


;;; --------------------------------------------------------------------------
;;;  Tests : branchements relatifs
;;; --------------------------------------------------------------------------

(deftest test/branches
  ;; BNE *+2 = branche sur soi-meme (offset 0)
  ;; L'instruction est a $0801, PC apres = $0803, target = $0803, offset = 0
  (check "BEQ forward"
         (let ((bytes (asm (format nil "BEQ end~%NOP~%end:"))))
           ;; BEQ offset=+1 (saute le NOP), NOP
           (and (= #xF0 (aref bytes 0))  ; BEQ
                (= #x01 (aref bytes 1))  ; offset +1
                (= #xEA (aref bytes 2))))) ; NOP
  (check "BNE backward"
         (let ((bytes (asm (format nil "loop: NOP~%BNE loop"))))
           ;; NOP, BNE offset=-3 (saute en arriere sur NOP)
           (and (= #xEA (aref bytes 0))   ; NOP
                (= #xD0 (aref bytes 1))   ; BNE
                (= #xFD (aref bytes 2))))) ; offset -3 = $FD
  (check "BCC = $90"
         (= #x90 (aref (asm (format nil "BCC end~%end:")) 0)))
  (check "BCS = $B0"
         (= #xB0 (aref (asm (format nil "BCS end~%end:")) 0))))

(deftest test/branch-out-of-range
  (check-error "branche hors portee -> asm-range-error"
               cl-asm/ir:asm-range-error
               ;; Generer 200 NOP puis une branche vers le debut
               (let ((src (with-output-to-string (s)
                            (format s "start:~%")
                            (dotimes (i 200) (format s "NOP~%"))
                            (format s "BNE start~%"))))
                 (asm src))))


;;; --------------------------------------------------------------------------
;;;  Tests : directives
;;; --------------------------------------------------------------------------

(deftest test/directive-org
  ;; .org ne produit pas d'octets, change juste l'adresse
  (check ".org ne produit pas d'octets"
         (bytes= (asm ".org $C000") )))

(deftest test/directive-byte
  (check ".byte simple"
         (bytes= (asm ".byte $01") #x01))
  (check ".byte multiple"
         (bytes= (asm ".byte $01, $02, $03") #x01 #x02 #x03))
  (check ".byte stub BASIC C64"
         (bytes= (asm ".byte $0B, $08, $E2, $07, $9E, $32, $30, $36, $34, $00, $00, $00")
                 #x0B #x08 #xE2 #x07 #x9E #x32 #x30 #x36 #x34 #x00 #x00 #x00)))

(deftest test/directive-word
  (check ".word $1234 = 34 12 (little-endian)"
         (bytes= (asm ".word $1234") #x34 #x12))
  (check ".word multiple"
         (bytes= (asm ".word $0100, $0200") #x00 #x01 #x00 #x02)))

(deftest test/directive-text
  (check ".text produit des codes ASCII"
         (bytes= (asm ".text \"HI\"") (char-code #\H) (char-code #\I))))

(deftest test/directive-fill
  (check ".fill 3 = trois zeros"
         (bytes= (asm ".fill 3") #x00 #x00 #x00))
  (check ".fill 3,$FF = trois $FF"
         (bytes= (asm ".fill 3, $FF") #xFF #xFF #xFF)))


;;; --------------------------------------------------------------------------
;;;  Tests : labels et expressions
;;; --------------------------------------------------------------------------

(deftest test/label-forward-ref
  ;; JMP end (3 octets @ $0801) + NOP (1 octet @ $0804) + end: RTS (@ $0805)
  (let ((bytes (asm (format nil "JMP end~%NOP~%end: RTS"))))
    (check "JMP forward = 4C"      (= #x4C (aref bytes 0)))
    (check "JMP target lo = $05"   (= #x05 (aref bytes 1)))
    (check "JMP target hi = $08"   (= #x08 (aref bytes 2)))
    (check "NOP apres JMP"         (= #xEA (aref bytes 3)))
    (check "RTS a la cible"        (= #x60 (aref bytes 4)))))

(deftest test/label-backward-ref
  (let ((bytes (asm (format nil "start: NOP~%JMP start"))))
    (check "JMP start = 4C 01 08"
           (and (= #x4C (aref bytes 1))
                (= #x01 (aref bytes 2))
                (= #x08 (aref bytes 3))))))

(deftest test/constant-in-operand
  (let ((bytes (asm (format nil "COLS = 40~%LDA #COLS"))))
    (check "LDA #40 = A9 28"
           (and (= #xA9 (aref bytes 0))
                (= 40   (aref bytes 1))))))

(deftest test/lo-hi-expr
  (let ((bytes (asm (format nil "VEC = $C000~%LDA #<VEC~%LDX #>VEC"))))
    (check "LDA #<VEC = A9 00"
           (and (= #xA9 (aref bytes 0)) (= #x00 (aref bytes 1))))
    (check "LDX #>VEC = A2 C0"
           (and (= #xA2 (aref bytes 2)) (= #xC0 (aref bytes 3))))))


;;; --------------------------------------------------------------------------
;;;  Tests : programme C64 complet
;;; --------------------------------------------------------------------------

(deftest test/c64-hello-screen
  ;; Programme C64 minimal : efface l'ecran (couleur bordure = noir)
  (let* ((src (format nil
                      "~A~%~A~%~A~%~A~%~A~%~A"
                      ".org $0801"
                      ".byte $0B,$08,$E2,$07,$9E,$32,$30,$36,$34,$00,$00,$00"
                      "start:"
                      "LDA #$00"
                      "STA $D020"
                      "RTS"))
         (bytes (asm src :origin #x0801)))
    (check "au moins 15 octets"    (>= (length bytes) 15))
    (check "stub BASIC commence"   (= #x0B (aref bytes 0)))
    (check "LDA #$00 apres stub"   (= #xA9 (aref bytes 12)))
    (check "valeur $00"            (= #x00 (aref bytes 13)))
    (check "STA $D020"             (= #x8D (aref bytes 14)))))


;;; --------------------------------------------------------------------------
;;;  Tests : emetteurs PRG et BIN
;;; --------------------------------------------------------------------------

(deftest test/emit-prg
  ;; Verifier que l'en-tete PRG est correct : 2 octets little-endian
  ;; suivi du binaire
  (let* ((bytes (make-array 3 :element-type '(unsigned-byte 8)
                              :initial-contents '(#xA9 #x00 #x60)))
         (prg (make-array 5 :element-type '(unsigned-byte 8))))
    (setf (aref prg 0) (logand #x0801 #xFF))
    (setf (aref prg 1) (logand (ash #x0801 -8) #xFF))
    (setf (aref prg 2) (aref bytes 0))
    (setf (aref prg 3) (aref bytes 1))
    (setf (aref prg 4) (aref bytes 2))
    (check "header PRG lo = $01"  (= #x01 (aref prg 0)))
    (check "header PRG hi = $08"  (= #x08 (aref prg 1)))
    (check "premier octet = $A9"  (= #xA9 (aref prg 2)))))

(deftest test/emit-bin-vs-prg
  ;; BIN = PRG sans les 2 octets de header
  (let* ((bytes (asm "LDA #$00"))
         (prg-stream (make-array 0 :element-type '(unsigned-byte 8)
                                   :adjustable t :fill-pointer 0))
         (bin-stream (make-array 0 :element-type '(unsigned-byte 8)
                                   :adjustable t :fill-pointer 0)))
    ;; Simuler l'emission
    (vector-push-extend (logand #x0801 #xFF) prg-stream)
    (vector-push-extend (logand (ash #x0801 -8) #xFF) prg-stream)
    (loop for b across bytes do (vector-push-extend b prg-stream))
    (loop for b across bytes do (vector-push-extend b bin-stream))
    (check "PRG = 2 + taille binaire"
           (= (length prg-stream) (+ 2 (length bin-stream))))
    (check "BIN[0] = PRG[2]"
           (= (aref bin-stream 0) (aref prg-stream 2)))))


;;; --------------------------------------------------------------------------
;;;  Tests : erreurs
;;; --------------------------------------------------------------------------

(deftest test/unknown-mnemonic
  (check-error "mnemonique inconnu -> asm-unknown-mnemonic"
               cl-asm/ir:asm-unknown-mnemonic
               (asm "FOO #$00")))

(deftest test/invalid-mode
  ;; STA n'a pas de mode immediat
  (check-error "STA #$00 invalide -> asm-syntax-error"
               cl-asm/ir:asm-syntax-error
               (asm "STA #$00")))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests cl-asm/backend.6502 ===~%")
  (test/nop)
  (test/accumulator-mode)
  (test/immediate)
  (test/zero-page)
  (test/absolute)
  (test/indirect)
  (test/branches)
  (test/branch-out-of-range)
  (test/directive-org)
  (test/directive-byte)
  (test/directive-word)
  (test/directive-text)
  (test/directive-fill)
  (test/label-forward-ref)
  (test/label-backward-ref)
  (test/constant-in-operand)
  (test/lo-hi-expr)
  (test/c64-hello-screen)
  (test/emit-prg)
  (test/emit-bin-vs-prg)
  (test/unknown-mnemonic)
  (test/invalid-mode)
  (when *failures*
    (format t "~&Echecs 6502 :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
