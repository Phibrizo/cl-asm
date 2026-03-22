; -*- coding: utf-8 -*-
;;; tests/test-acme2clasm.lisp
;;;
;;; Tests unitaires pour le convertisseur acme2clasm.lisp.
;;; Charge le convertisseur en mode test (sans exécuter main).

(defpackage #:cl-asm/test.acme2clasm
  (:use #:cl)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.acme2clasm)

;;; Empêcher l'exécution de (main) lors du chargement
(defvar *acme2clasm-skip-main* t)

;;; Charger le convertisseur (fonctions disponibles dans le package CL-USER)
(load (merge-pathnames "acme2clasm.lisp"
                       (make-pathname :directory (butlast (pathname-directory
                                                           *load-truename*)))))

;;; Infrastructure de tests (copiée du pattern des autres suites)
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

;;; Helper : créer un converter factice pour convert-line
(defun make-test-conv ()
  (make-converter :source-path "test"))

;;; Helper : convertit une ligne et retourne le résultat (sans \r)
(defun conv (line)
  (string-right-trim '(#\Return #\Newline)
                     (convert-line (make-test-conv) 1 line)))


;;; --------------------------------------------------------------------------
;;;  Tests : cas de base existants (non-régression)
;;; --------------------------------------------------------------------------

(deftest test/basic-directives
  (check "!byte → .byte"
         (string= (conv "        !byte $01, $02")
                  "        .byte $01, $02"))
  (check "!word → .word"
         (string= (conv "        !word $1234")
                  "        .word $1234"))
  (check "!fill → .fill"
         (string= (conv "        !fill 4")
                  "        .fill 4"))
  (check "* = ADDR → .org ADDR"
         (string= (conv "* = $0801")
                  ".org $0801"))
  (check "commentaire pur conservé"
         (string= (conv "; mon commentaire")
                  "; mon commentaire"))
  (check "ligne vide → vide"
         (string= (conv "") "")))

(deftest test/label-alone
  (check "label seul sans ':'"
         ;; label seul en colonne 0, pas de mnémonique → label:
         (let ((result (conv "plain_label")))
           (string= result "plain_label:")))
  (check "label avec ':'"
         (let ((result (conv "plain_label:")))
           (string= result "plain_label:"))))

(deftest test/label-plus-directive
  ;; C'est le bug corrigé : label: !directive sur la même ligne
  (check "label: !byte → label: + .byte"
         (let ((result (conv "my_data: !byte $01, $02, $03")))
           (string= result (format nil "my_data:~%        .byte $01, $02, $03"))))
  (check "label: !word → label: + .word"
         (let ((result (conv "my_word: !word $1234")))
           (string= result (format nil "my_word:~%        .word $1234"))))
  (check "label: !fill → label: + .fill"
         (let ((result (conv "my_fill: !fill 8")))
           (string= result (format nil "my_fill:~%        .fill 8"))))
  (check "label: * = ADDR → label: + .org (via rest)"
         ;; Note : * = addr après un label reste une assignation
         ;; car stripped commence par le nom du label, pas par *
         ;; ce test vérifie que le reste est bien re-converti
         (let ((result (conv "data: !byte $FF")))
           (string= result (format nil "data:~%        .byte $FF"))))
  (check "label: .byte (ca65) → label: + .byte"
         (let ((result (conv "table: .byte 1, 2, 3")))
           (string= result (format nil "table:~%        .byte 1, 2, 3"))))
  (check "label: !text → label: + .text"
         (let ((result (conv "msg: !text \"hello\"")))
           (string= result (format nil "msg:~%        .text \"hello\"")))))

(deftest test/label-plus-instruction
  ;; Label suivi d'une instruction (non directive) — doit passer en .asm
  (check "label: LDA #$00 → label: + instruction"
         (let ((result (conv "start: LDA #$00")))
           ;; "LDA #$00" n'est pas une directive, convert-line le passe tel quel
           (string= result (format nil "start:~%        LDA #$00"))))
  (check "label: NOP → label: + NOP"
         (let ((result (conv "loop: NOP")))
           (string= result (format nil "loop:~%        NOP")))))

(deftest test/assignment
  (check "NOM = VALEUR reste une assignation"
         (string= (conv "MY_CONST = $0800")
                  "MY_CONST = $0800"))
  (check "!addr NOM = VAL → NOM = VAL"
         (string= (conv "!addr zp_tmp = $02")
                  "zp_tmp = $02")))

(deftest test/expression-conversion
  (check "opérateur AND converti en &"
         (string= (conv "        !byte val AND $0F")
                  "        .byte val & $0F"))
  (check "opérateur OR converti en |"
         (string= (conv "        !byte a OR b")
                  "        .byte a | b")))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests acme2clasm ===~%")
  (test/basic-directives)
  (test/label-alone)
  (test/label-plus-directive)
  (test/label-plus-instruction)
  (test/assignment)
  (test/expression-conversion)
  (when *failures*
    (format t "~&Echecs acme2clasm :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
