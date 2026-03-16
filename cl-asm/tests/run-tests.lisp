; -*- coding: utf-8 -*-
;;; tests/run-tests.lisp
;;;
;;; Lanceur global : exécute toutes les suites de tests et affiche
;;; un bilan consolidé.

(defpackage #:cl-asm/test
  (:use #:cl)
  (:export #:run-all-tests))

(in-package #:cl-asm/test)

(defmacro run-suite (pkg)
  "Lance une suite de tests et accumule les compteurs."
  (let ((run  (intern "RUN-ALL-TESTS" pkg))
        (pass (intern "*PASS*" pkg))
        (fail (intern "*FAIL*" pkg))
        (fail-list (intern "*FAILURES*" pkg)))
    `(progn
       (,run)
       (incf total-pass ,pass)
       (incf total-fail ,fail)
       (setf total-failures (append total-failures ,fail-list)))))

(defun run-all-tests ()
  (let ((total-pass 0)
        (total-fail 0)
        (total-failures '()))

    ;; --- Core ---
    (run-suite cl-asm/test.symbol-table)
    (run-suite cl-asm/test.expression)

    ;; --- Frontend ---
    (run-suite cl-asm/test.lexer)
    (run-suite cl-asm/test.parser)
    (run-suite cl-asm/test.macros)
    (run-suite cl-asm/test.conditional)
    (run-suite cl-asm/test.lasm)

    ;; --- Backends ---
    (run-suite cl-asm/test.6502)
    (run-suite cl-asm/test.65c02)
    (run-suite cl-asm/test.45gs02)

    ;; --- Bilan global ---
    (format t "~%")
    (format t "--- Core ---~%")
    (format t "=== symbol-table : ~3D OK, ~D KO~%"
            cl-asm/test.symbol-table:*pass*
            cl-asm/test.symbol-table:*fail*)
    (format t "=== expression   : ~3D OK, ~D KO~%"
            cl-asm/test.expression:*pass*
            cl-asm/test.expression:*fail*)
    (format t "--- Frontend ---~%")
    (format t "=== lexer        : ~3D OK, ~D KO~%"
            cl-asm/test.lexer:*pass*
            cl-asm/test.lexer:*fail*)
    (format t "=== parser       : ~3D OK, ~D KO~%"
            cl-asm/test.parser:*pass*
            cl-asm/test.parser:*fail*)
    (format t "=== macros       : ~3D OK, ~D KO~%"
            cl-asm/test.macros:*pass*
            cl-asm/test.macros:*fail*)
    (format t "=== conditionnel : ~3D OK, ~D KO~%"
            cl-asm/test.conditional:*pass*
            cl-asm/test.conditional:*fail*)
    (format t "=== lasm         : ~3D OK, ~D KO~%"
            cl-asm/test.lasm:*pass*
            cl-asm/test.lasm:*fail*)
    (format t "--- Backends ---~%")
    (format t "=== 6502         : ~3D OK, ~D KO~%"
            cl-asm/test.6502:*pass*
            cl-asm/test.6502:*fail*)
    (format t "=== 65c02        : ~3D OK, ~D KO~%"
            cl-asm/test.65c02:*pass*
            cl-asm/test.65c02:*fail*)
    (format t "=== 45gs02       : ~3D OK, ~D KO~%"
            cl-asm/test.45gs02:*pass*
            cl-asm/test.45gs02:*fail*)
    (format t "-------------------------------~%")
    (format t "=== TOTAL        : ~3D OK, ~D KO sur ~D tests~%"
            total-pass total-fail (+ total-pass total-fail))
    (when total-failures
      (format t "~%Echecs :~%")
      (dolist (f (reverse total-failures))
        (format t "  - ~A~%" f)))
    (finish-output)
    (zerop total-fail)))
