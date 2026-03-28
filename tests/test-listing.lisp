; -*- coding: utf-8 -*-
;;; tests/test-listing.lisp
;;;
;;; Tests unitaires pour l'émetteur de listing (src/emit/output.lisp).
;;; Couvre : correction de la taille des instructions (bugfix),
;;;          cycles CPU 6502 / 6510 / 65C02, listing sans cible.

(defpackage #:cl-asm/test.listing
  (:use #:cl)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.listing)

(defvar *pass* 0)
(defvar *fail* 0)
(defvar *failures* '())

(defmacro check (desc expr)
  `(if ,expr
       (progn (incf *pass*)
              (format t "  OK  ~A~%" ,desc))
       (progn (incf *fail*)
              (push ,desc *failures*)
              (format t "  KO  ~A~%" ,desc))))

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&--- ~A ---~%" ',name)
     ,@body))

(defun count-occurrences (sub str)
  "Nombre d'occurrences non-chevauchantes de SUB dans STR."
  (let ((len (length sub))
        (n 0)
        (pos 0))
    (loop
      (let ((found (search sub str :start2 pos)))
        (unless found (return n))
        (incf n)
        (setf pos (+ found len))))))

;;; Helpers : assemblage + listing pour 6502 et 65C02

(defun listing-6502 (src &key (origin #x0200))
  (let* ((prog  (cl-asm/parser:parse-string src))
         (bytes (cl-asm/backend.6502:assemble prog :origin origin)))
    (with-output-to-string (s)
      (cl-asm/emit:emit-listing prog bytes s :origin origin :target :6502))))

(defun listing-65c02 (src &key (origin #x0200))
  (let* ((prog  (cl-asm/parser:parse-string src))
         (bytes (cl-asm/backend.65c02:assemble-65c02 prog :origin origin)))
    (with-output-to-string (s)
      (cl-asm/emit:emit-listing prog bytes s :origin origin :target :65c02))))

(defun listing-no-target (src &key (origin #x0200))
  (let* ((prog  (cl-asm/parser:parse-string src))
         (bytes (cl-asm/backend.6502:assemble prog :origin origin)))
    (with-output-to-string (s)
      (cl-asm/emit:emit-listing prog bytes s :origin origin))))


;;; --------------------------------------------------------------------------
;;;  Bugfix : taille des instructions — PC correctement avancé
;;; --------------------------------------------------------------------------

(deftest test/listing-pc-correct
  ;; LDA #$42  = A9 42     (2 octets) → $0200
  ;; STA $D020 = 8D 20 D0  (3 octets) → $0202
  ;; RTS       = 60         (1 octet)  → $0205
  (let ((lst (listing-6502 "LDA #$42
STA $D020
RTS")))
    (check "listing/pc — LDA à $0200" (search "0200" lst))
    (check "listing/pc — STA à $0202" (search "0202" lst))
    (check "listing/pc — RTS à $0205" (search "0205" lst))))

(deftest test/listing-hex-bytes
  (let ((lst (listing-6502 "LDA #$42
STA $D020")))
    (check "listing/hex — A9 42 pour LDA #$42"   (search "A9 42" lst))
    (check "listing/hex — 8D 20 D0 pour STA abs" (search "8D 20 D0" lst))))

(deftest test/listing-labels
  ;; Le parser uppercaseant les labels, la sortie contient "MAIN:" et non "main:"
  (let ((lst (listing-6502 ".org $0300
main:
  LDA #$00
  RTS" :origin #x0300)))
    (check "listing/labels — label MAIN:" (search "MAIN:" lst))
    (check "listing/labels — adresse $0300" (search "0300" lst))))


;;; --------------------------------------------------------------------------
;;;  Cycles 6502
;;; --------------------------------------------------------------------------

(deftest test/cycles-6502-fixed
  (let ((lst (listing-6502 "LDA #$42")))   ; A9 → 2cy fixe
    (check "cycles/6502 — LDA # = 2cy" (search "2cy" lst)))
  (let ((lst (listing-6502 "STA $D020")))  ; 8D → 4cy fixe
    (check "cycles/6502 — STA abs = 4cy" (search "4cy" lst)))
  (let ((lst (listing-6502 "RTS")))        ; 60 → 6cy fixe
    (check "cycles/6502 — RTS = 6cy" (search "6cy" lst)))
  (let ((lst (listing-6502 "JSR $0300")))  ; 20 → 6cy fixe
    (check "cycles/6502 — JSR = 6cy" (search "6cy" lst))))

(deftest test/cycles-6502-page-crossing
  ;; LDA abs,X ($BD) = 4cy+ (page-crossing penalty)
  (let ((lst (listing-6502 "LDA $0300,X")))
    (check "cycles/6502 — LDA abs,X = 4cy+" (search "4cy+" lst)))
  ;; LDA (zp),Y ($B1) = 5cy+
  (let ((lst (listing-6502 "LDA ($10),Y")))
    (check "cycles/6502 — LDA (zp),Y = 5cy+" (search "5cy+" lst))))

(deftest test/cycles-6502-branch
  ;; BNE ($D0) = 2cy* (branche : +1 prise, +2 prise+page)
  (let ((lst (listing-6502 "loop:
  BNE loop")))
    (check "cycles/6502 — BNE = 2cy*" (search "2cy*" lst)))
  ;; BEQ ($F0) idem
  (let ((lst (listing-6502 "loop:
  BEQ loop")))
    (check "cycles/6502 — BEQ = 2cy*" (search "2cy*" lst))))

(deftest test/cycles-6502-sta-no-penalty
  ;; STA abs,Y ($99) = toujours 5cy (pas de penalty pour les stores)
  (let ((lst (listing-6502 "STA $0300,Y")))
    (check "cycles/6502 — STA abs,Y = 5cy"    (search "5cy" lst))
    (check "cycles/6502 — STA abs,Y sans 5cy+" (not (search "5cy+" lst))))
  ;; STA abs,X ($9D) = toujours 5cy
  (let ((lst (listing-6502 "STA $0300,X")))
    (check "cycles/6502 — STA abs,X = 5cy"    (search "5cy" lst))
    (check "cycles/6502 — STA abs,X sans 5cy+" (not (search "5cy+" lst)))))

(deftest test/cycles-6502-multi-instr
  ;; Plusieurs instructions : vérifier que tous les cycles apparaissent
  (let ((lst (listing-6502 "LDA #$00
STA $D020
RTS")))
    (check "cycles/6502 — multi : 2cy présent" (search "2cy" lst))
    (check "cycles/6502 — multi : 4cy présent" (search "4cy" lst))
    (check "cycles/6502 — multi : 6cy présent" (search "6cy" lst))
    ;; Trois lignes d'instruction → trois mentions de cy
    (check "cycles/6502 — multi : 3 occurrences cy"
           (>= (count-occurrences "cy" lst) 3))))

(deftest test/cycles-6510-same-as-6502
  ;; 6510 utilise la même table que 6502
  (let* ((prog  (cl-asm/parser:parse-string "LDA #$00
STA $D020"))
         (bytes (cl-asm/backend.6510:assemble-6510 prog :origin #x0200))
         (lst   (with-output-to-string (s)
                  (cl-asm/emit:emit-listing prog bytes s
                                           :origin #x0200
                                           :target :6510))))
    (check "cycles/6510 — LDA # = 2cy" (search "2cy" lst))
    (check "cycles/6510 — STA abs = 4cy" (search "4cy" lst))))


;;; --------------------------------------------------------------------------
;;;  Cycles 65C02 / Commander X16
;;; --------------------------------------------------------------------------

(deftest test/cycles-65c02-new-opcodes
  ;; PHY ($5A) = 3cy, PLY ($7A) = 4cy — opcodes absents du 6502
  (let ((lst (listing-65c02 "PHY
PLY")))
    (check "cycles/65c02 — PHY = 3cy" (search "3cy" lst))
    (check "cycles/65c02 — PLY = 4cy" (search "4cy" lst)))
  ;; PHX ($DA) = 3cy, PLX ($FA) = 4cy
  (let ((lst (listing-65c02 "PHX
PLX")))
    (check "cycles/65c02 — PHX = 3cy" (search "3cy" lst))
    (check "cycles/65c02 — PLX = 4cy" (search "4cy" lst))))

(deftest test/cycles-65c02-bra
  ;; BRA ($80) = 2cy* comme les Bcc
  (let ((lst (listing-65c02 "loop:
  BRA loop")))
    (check "cycles/65c02 — BRA = 2cy*" (search "2cy*" lst))))

(deftest test/cycles-65c02-jmp-indirect
  ;; JMP ($6C) = 6cy sur 65C02 (bug page-crossing corrigé), 5cy sur 6502
  (let ((lst-65c02 (listing-65c02 "JMP ($0300)"))
        (lst-6502  (listing-6502  "JMP ($0300)")))
    (check "cycles/65c02 — JMP (ind) = 6cy" (search "6cy" lst-65c02))
    (check "cycles/6502  — JMP (ind) = 5cy" (search "5cy" lst-6502))))


;;; --------------------------------------------------------------------------
;;;  Listing sans cible (compatibilité ascendante)
;;; --------------------------------------------------------------------------

(deftest test/listing-no-target
  ;; Sans target : pas de cycles, pas de correction de taille (comportement préservé)
  (let ((lst (listing-no-target "LDA #$42
STA $D020
RTS")))
    (check "listing/no-target — mnémoniques présents" (search "LDA" lst))
    (check "listing/no-target — STA présent"          (search "STA" lst))
    (check "listing/no-target — RTS présent"          (search "RTS" lst))
    (check "listing/no-target — pas de colonne cy"    (not (search "cy" lst)))
    ;; $0200 (adresse initiale) doit apparaître
    (check "listing/no-target — $0200 présent"        (search "0200" lst))))

(deftest test/listing-write-file
  ;; write-listing produit un fichier valide
  (let* ((prog  (cl-asm/parser:parse-string "LDA #$00
RTS"))
         (bytes (cl-asm/backend.6502:assemble prog :origin #x0200))
         (path  (uiop:with-temporary-file (:pathname p :keep t) p)))
    (cl-asm/emit:write-listing prog bytes path :origin #x0200 :target :6502)
    (let ((content (uiop:read-file-string path)))
      (check "listing/write-file — fichier non vide" (plusp (length content)))
      (check "listing/write-file — contient LDA"     (search "LDA" content))
      (check "listing/write-file — contient 2cy"     (search "2cy" content)))
    (ignore-errors (delete-file path))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== listing ===~%")
  (test/listing-pc-correct)
  (test/listing-hex-bytes)
  (test/listing-labels)
  (test/cycles-6502-fixed)
  (test/cycles-6502-page-crossing)
  (test/cycles-6502-branch)
  (test/cycles-6502-sta-no-penalty)
  (test/cycles-6502-multi-instr)
  (test/cycles-6510-same-as-6502)
  (test/cycles-65c02-new-opcodes)
  (test/cycles-65c02-bra)
  (test/cycles-65c02-jmp-indirect)
  (test/listing-no-target)
  (test/listing-write-file)
  (format t "  listing : ~D OK, ~D KO~%" *pass* *fail*))
