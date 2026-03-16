; -*- coding: utf-8 -*-
;;; tests/test-lasm.lisp

(defpackage #:cl-asm/test.lasm
  (:use #:cl #:cl-asm/lasm)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.lasm)


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

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&~%[~A]~%" ',name)
     ,@body))

(defun asm (source &key (origin #x0801))
  (assemble-lasm-string source :origin origin))

(defun bytes= (vec &rest expected)
  (and (= (length vec) (length expected))
       (every #'= vec expected)))


;;; --------------------------------------------------------------------------
;;;  Tests : instructions implied
;;; --------------------------------------------------------------------------

(deftest test/implied
  (check "NOP = EA"  (bytes= (asm "(nop)") #xEA))
  (check "RTS = 60"  (bytes= (asm "(rts)") #x60))
  (check "CLC = 18"  (bytes= (asm "(clc)") #x18))
  (check "SEI = 78"  (bytes= (asm "(sei)") #x78))
  (check "TAX = AA"  (bytes= (asm "(tax)") #xAA))
  (check "PHA = 48"  (bytes= (asm "(pha)") #x48)))

(deftest test/accumulator
  (check "LSR :a = 4A" (bytes= (asm "(lsr :a)") #x4A))
  (check "ASL :a = 0A" (bytes= (asm "(asl :a)") #x0A))
  (check "ROL :a = 2A" (bytes= (asm "(rol :a)") #x2A))
  (check "ROR :a = 6A" (bytes= (asm "(ror :a)") #x6A)))


;;; --------------------------------------------------------------------------
;;;  Tests : mode immediat
;;; --------------------------------------------------------------------------

(deftest test/immediate
  (check "LDA :imm #xFF = A9 FF"
         (bytes= (asm "(lda :imm #xFF)") #xA9 #xFF))
  (check "LDA :imm 0 = A9 00"
         (bytes= (asm "(lda :imm 0)") #xA9 #x00))
  (check "LDX :imm 1 = A2 01"
         (bytes= (asm "(ldx :imm 1)") #xA2 #x01))
  (check "ADC :imm #x10 = 69 10"
         (bytes= (asm "(adc :imm #x10)") #x69 #x10)))


;;; --------------------------------------------------------------------------
;;;  Tests : deduction automatique du mode
;;; --------------------------------------------------------------------------

(deftest test/auto-mode
  ;; Entier ≤ 255 → zero-page
  (check "LDA #x10 = A5 10 (zp auto)"
         (bytes= (asm "(lda #x10)") #xA5 #x10))
  ;; Entier > 255 → absolu
  (check "LDA #x1234 = AD 34 12 (abs auto)"
         (bytes= (asm "(lda #x1234)") #xAD #x34 #x12))
  (check "STA #xD020 = 8D 20 D0"
         (bytes= (asm "(sta #xD020)") #x8D #x20 #xD0)))


;;; --------------------------------------------------------------------------
;;;  Tests : mode force
;;; --------------------------------------------------------------------------

(deftest test/forced-mode
  ;; :abs force le mode absolu meme pour une valeur ≤ 255
  (check "LDA :abs #x10 = AD 10 00 (absolu force)"
         (bytes= (asm "(lda :abs #x10)") #xAD #x10 #x00))
  ;; :zp force le mode zero-page
  (check "LDA :zp #x10 = A5 10 (zp force)"
         (bytes= (asm "(lda :zp #x10)") #xA5 #x10)))


;;; --------------------------------------------------------------------------
;;;  Tests : modes indexes
;;; --------------------------------------------------------------------------

(deftest test/indexed
  (check "LDA :x #x10 = B5 10 (zp,X)"
         (bytes= (asm "(lda :x #x10)") #xB5 #x10))
  (check "LDA :x #x1234 = BD 34 12 (abs,X)"
         (bytes= (asm "(lda :x #x1234)") #xBD #x34 #x12))
  (check "LDA :y #x1234 = B9 34 12 (abs,Y)"
         (bytes= (asm "(lda :y #x1234)") #xB9 #x34 #x12))
  (check "STA :x #xD000 = 9D 00 D0"
         (bytes= (asm "(sta :x #xD000)") #x9D #x00 #xD0)))


;;; --------------------------------------------------------------------------
;;;  Tests : modes indirects
;;; --------------------------------------------------------------------------

(deftest test/indirect
  (check "JMP :ind #xFFFC = 6C FC FF"
         (bytes= (asm "(jmp :ind #xFFFC)") #x6C #xFC #xFF))
  (check "LDA :ix #x00 = A1 00"
         (bytes= (asm "(lda :ix #x00)") #xA1 #x00))
  (check "STA :iy #xB0 = 91 B0"
         (bytes= (asm "(sta :iy #xB0)") #x91 #xB0)))


;;; --------------------------------------------------------------------------
;;;  Tests : directives
;;; --------------------------------------------------------------------------

(deftest test/directives
  (check "org ne produit pas d'octets"
         (= 0 (length (asm "(org #xC000)"))))
  (check "db = octets bruts"
         (bytes= (asm "(db #x01 #x02 #x03)") #x01 #x02 #x03))
  (check "dw = little-endian"
         (bytes= (asm "(dw #x1234)") #x34 #x12))
  (check "fill = remplissage"
         (bytes= (asm "(fill 3 #xFF)") #xFF #xFF #xFF))
  (check "text = ASCII"
         (bytes= (asm "(text \"HI\")") (char-code #\H) (char-code #\I))))


;;; --------------------------------------------------------------------------
;;;  Tests : labels et symboles
;;; --------------------------------------------------------------------------

(deftest test/labels-forward
  ;; Label forward-ref : JMP suivi du label
  (let* ((src "(jmp 'end) (nop) (label 'end) (rts)")
         (bytes (asm src)))
    (check "JMP = 4C"    (= #x4C (aref bytes 0)))
    (check "target = $05" (= #x05 (aref bytes 1)))  ; $0801+3+1=$0805
    (check "NOP apres"   (= #xEA (aref bytes 3)))
    (check "RTS a end"   (= #x60 (aref bytes 4)))))

(deftest test/labels-backward
  (let* ((src "(label 'start) (nop) (jmp 'start)")
         (bytes (asm src)))
    (check "NOP = EA"        (= #xEA (aref bytes 0)))
    (check "JMP start = 4C"  (= #x4C (aref bytes 1)))
    (check "lo = $01"        (= #x01 (aref bytes 2)))
    (check "hi = $08"        (= #x08 (aref bytes 3)))))

(deftest test/equ-symbole
  (let* ((src "(equ 'cols 40) (lda :imm 'cols)")
         (bytes (asm src)))
    (check "LDA #40 = A9 28"
           (and (= #xA9 (aref bytes 0))
                (= 40   (aref bytes 1))))))


;;; --------------------------------------------------------------------------
;;;  Tests : puissance de Lisp
;;; --------------------------------------------------------------------------

(deftest test/lisp-dotimes
  ;; Générer 3 NOP avec dotimes
  (let ((bytes (asm "(dotimes (i 3) (nop))")))
    (check "3 NOP = EA EA EA"
           (bytes= bytes #xEA #xEA #xEA))))

(deftest test/lisp-let
  ;; Constante locale Lisp
  (let* ((src "(let ((couleur #x00))
                 (lda :imm couleur)
                 (sta #xD020))")
         (bytes (asm src)))
    (check "LDA #$00" (= #x00 (aref bytes 1)))
    (check "STA $D020" (= #x8D (aref bytes 2)))))

(deftest test/lisp-defun
  ;; Definir une fonction Lisp qui emet du code
  (let* ((src "(defun set-border (col)
                 (lda :imm col)
                 (sta #xD020))
               (set-border 0)
               (set-border 1)")
         (bytes (asm src)))
    ;; Deux fois LDA + STA = 2 x 5 = 10 octets
    (check "10 octets"   (= 10 (length bytes)))
    (check "LDA #$00"    (= #x00 (aref bytes 1)))
    (check "LDA #$01"    (= #x01 (aref bytes 6)))))

(deftest test/lisp-loop
  ;; Boucle loop pour remplir un tableau
  (let* ((src "(org #x0801)
               (loop for i from 0 to 3
                     do (lda :imm i)
                        (sta (+ #xD800 i)))")
         (bytes (asm src)))
    ;; 4 x (LDA #imm + STA abs) = 4 x 5 = 20 octets
    (check "20 octets"   (= 20 (length bytes)))
    (check "LDA #0"      (= #x00 (aref bytes 1)))
    (check "STA $D800"   (= #x8D (aref bytes 2)))
    (check "LDA #3"      (= #x03 (aref bytes 16)))))


;;; --------------------------------------------------------------------------
;;;  Tests : programme C64 complet
;;; --------------------------------------------------------------------------

(deftest test/c64-hello
  (let* ((src
           "(org #x0801)
            (db #x0B #x08 #xE2 #x07 #x9E
                #x32 #x30 #x36 #x34 #x00 #x00 #x00)
            (label 'start)
            (lda :imm 0)
            (sta #xD020)
            (rts)")
         (bytes (asm src)))
    (check "au moins 15 octets"  (>= (length bytes) 15))
    (check "stub BASIC = $0B"    (= #x0B (aref bytes 0)))
    (check "LDA #$00 = A9"       (= #xA9 (aref bytes 12)))
    (check "STA $D020 = 8D"      (= #x8D (aref bytes 14)))))


;;; --------------------------------------------------------------------------
;;;  Tests : 45GS02
;;; --------------------------------------------------------------------------

(deftest test/45gs02-basic
  (let* ((src "(ldz :imm 0) (taz) (inz) (rts)")
         (bytes (assemble-lasm-string src :target :45gs02 :origin #x2001)))
    (check "LDZ #0 = A3 00" (and (= #xA3 (aref bytes 0))
                                  (= #x00 (aref bytes 1))))
    (check "TAZ = 4B"        (= #x4B (aref bytes 2)))
    (check "INZ = 1B"        (= #x1B (aref bytes 3)))
    (check "RTS = 60"        (= #x60 (aref bytes 4)))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests cl-asm/lasm ===~%")
  (test/implied)
  (test/accumulator)
  (test/immediate)
  (test/auto-mode)
  (test/forced-mode)
  (test/indexed)
  (test/indirect)
  (test/directives)
  (test/labels-forward)
  (test/labels-backward)
  (test/equ-symbole)
  (test/lisp-dotimes)
  (test/lisp-let)
  (test/lisp-defun)
  (test/lisp-loop)
  (test/c64-hello)
  (test/45gs02-basic)
  (when *failures*
    (format t "~&Echecs lasm :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
