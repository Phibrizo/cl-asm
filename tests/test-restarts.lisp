; -*- coding: utf-8 -*-
;;; tests/test-restarts.lisp
;;;
;;; Tests unitaires pour le système de conditions/restarts d'assemblage.
;;; Couvre : use-value, use-zero, skip-instruction, clamp-value,
;;;          macros with-asm-use-zero et with-asm-skip-errors,
;;;          comportement sans handler (erreur propagée normalement).

(defpackage #:cl-asm/test.restarts
  (:use #:cl)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.restarts)

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

;;; Helpers

(defun asm (src &key origin)
  (cl-asm/backend.6502:assemble-string src :origin (or origin #x0200)))

(defun bytes (&rest args) (coerce args '(vector (unsigned-byte 8))))

(defun signals-p (condition-type thunk)
  "Vrai si THUNK signale une condition de type CONDITION-TYPE."
  (handler-case (progn (funcall thunk) nil)
    (condition (c) (typep c condition-type))))


;;; --------------------------------------------------------------------------
;;;  Sans handler : erreur propagée normalement (comportement inchangé)
;;; --------------------------------------------------------------------------

(deftest test-no-handler-propagates
  (check "label indéfini sans handler → asm-undefined-label"
    (signals-p 'cl-asm/ir:asm-undefined-label
               (lambda () (asm "LDA unknown"))))
  (check "mnémonique inconnu sans handler → asm-unknown-mnemonic"
    (signals-p 'cl-asm/ir:asm-unknown-mnemonic
               (lambda () (asm "BADMNEM"))))
  (check "branche hors portée sans handler → asm-range-error"
    (signals-p 'cl-asm/ir:asm-range-error
               (lambda ()
                 (asm ".org $0200
BNE far
.fill 200
far: NOP")))))


;;; --------------------------------------------------------------------------
;;;  use-zero : label indéfini résolu à 0
;;; --------------------------------------------------------------------------

(deftest test-use-zero
  ;; LDA unknown → valeur 0 → zero-page → LDA $00 ($A5 $00)
  ;; (0 ≤ $FF, le backend choisit le mode zero-page)
  (check "use-zero : LDA label_inconnu → LDA zp $00"
    (equalp
     (handler-bind
       ((cl-asm/ir:asm-undefined-label
         (lambda (c) (declare (ignore c))
           (invoke-restart 'cl-asm/restarts:use-zero))))
       (asm "LDA unknown
RTS"))
     (bytes #xA5 #x00 #x60)))

  ;; with-asm-use-zero macro
  (check "with-asm-use-zero : résout automatiquement à 0"
    (equalp
     (cl-asm/restarts:with-asm-use-zero
       (asm "LDA unknown
RTS"))
     (bytes #xA5 #x00 #x60))))


;;; --------------------------------------------------------------------------
;;;  use-value : label indéfini résolu à une valeur fournie
;;; --------------------------------------------------------------------------

(deftest test-use-value
  ;; LDA unknown → use-value #x0400 → LDA abs $0400 ($AD $00 $04)
  (check "use-value : LDA label_inconnu → LDA abs $0400"
    (equalp
     (handler-bind
       ((cl-asm/ir:asm-undefined-label
         (lambda (c) (declare (ignore c))
           (invoke-restart 'cl-asm/restarts:use-value #x0400))))
       (asm "LDA unknown
RTS"))
     (bytes #xAD #x00 #x04 #x60)))

  ;; use-value avec un label zero-page ($10)
  (check "use-value : LDA label_inconnu → LDA zp $10"
    (equalp
     (handler-bind
       ((cl-asm/ir:asm-undefined-label
         (lambda (c) (declare (ignore c))
           (invoke-restart 'cl-asm/restarts:use-value #x10))))
       (asm "LDA unknown
RTS"))
     (bytes #xA5 #x10 #x60)))

  ;; JMP n'a que le mode absolu : use-value avec adresse > $FF
  (check "use-value : JMP label_inconnu → JMP abs $0400"
    (equalp
     (handler-bind
       ((cl-asm/ir:asm-undefined-label
         (lambda (c) (declare (ignore c))
           (invoke-restart 'cl-asm/restarts:use-value #x0400))))
       (asm "JMP unknown"))
     (bytes #x4C #x00 #x04)))

  ;; Plusieurs labels inconnus — handler appelé une fois par label (pass 2)
  (let ((count 0))
    (handler-bind
      ((cl-asm/ir:asm-undefined-label
        (lambda (c) (declare (ignore c))
          (incf count)
          (invoke-restart 'cl-asm/restarts:use-zero))))
      (asm "LDA alpha
STA beta
RTS"))
    (check "use-value : handler appelé une fois par label inconnu (pass 2)"
      (= count 2))))


;;; --------------------------------------------------------------------------
;;;  skip-instruction : mnémonique inconnu ignoré
;;; --------------------------------------------------------------------------

(deftest test-skip-instruction-unknown-mnemonic
  ;; BADMNEM ignoré → seul LDA #1 et RTS assemblés
  (check "skip-instruction : BADMNEM ignoré, code court"
    (equalp
     (handler-bind
       ((cl-asm/ir:asm-unknown-mnemonic
         (lambda (c) (declare (ignore c))
           (invoke-restart 'cl-asm/restarts:skip-instruction))))
       (asm "BADMNEM
LDA #$01
RTS"))
     (bytes #xA9 #x01 #x60)))

  ;; Deux mnémoniques inconnus ignorés
  (check "skip-instruction : deux mnémoniques inconnus ignorés"
    (equalp
     (handler-bind
       ((cl-asm/ir:asm-unknown-mnemonic
         (lambda (c) (declare (ignore c))
           (invoke-restart 'cl-asm/restarts:skip-instruction))))
       (asm "FOO
BAR
NOP"))
     (bytes #xEA)))

  ;; with-asm-skip-errors macro
  (check "with-asm-skip-errors : BADMNEM ignoré"
    (equalp
     (cl-asm/restarts:with-asm-skip-errors
       (asm "BADMNEM
RTS"))
     (bytes #x60))))


;;; --------------------------------------------------------------------------
;;;  clamp-value : branche hors portée tronquée
;;; --------------------------------------------------------------------------

(deftest test-clamp-value-range-error
  ;; BNE vers une cible trop loin → branche tronquée à +127
  (let ((result
         (handler-bind
           ((cl-asm/ir:asm-range-error
             (lambda (c) (declare (ignore c))
               (invoke-restart 'cl-asm/restarts:clamp-value))))
           (asm ".org $0200
BNE far
.fill 200
far: NOP"))))
    (check "clamp-value : branche hors portée tronquée à +127"
      ;; BNE = $D0, offset clampé à $7F (+127)
      (and (= (aref result 0) #xD0)
           (= (aref result 1) #x7F))))

  ;; use-value : fournir manuellement l'offset
  (let ((result
         (handler-bind
           ((cl-asm/ir:asm-range-error
             (lambda (c) (declare (ignore c))
               (invoke-restart 'cl-asm/restarts:use-value #x10))))
           (asm ".org $0200
BNE far
.fill 200
far: NOP"))))
    (check "use-value sur range-error : offset forcé à $10"
      (and (= (aref result 0) #xD0)
           (= (aref result 1) #x10)))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~%=== Conditions / Restarts ===~%")
  (test-no-handler-propagates)
  (test-use-zero)
  (test-use-value)
  (test-skip-instruction-unknown-mnemonic)
  (test-clamp-value-range-error)
  (format t "~%  restarts : ~D OK, ~D KO~%~%" *pass* *fail*))
