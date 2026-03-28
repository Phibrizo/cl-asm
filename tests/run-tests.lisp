; -*- coding: utf-8 -*-
;;; tests/run-tests.lisp
;;;
;;; Lanceur global : exécute toutes les suites de tests et affiche
;;; un bilan consolidé.

(defpackage #:cl-asm/test
  (:use #:cl)
  (:export #:run-all-tests))

(in-package #:cl-asm/test)

;;; --------------------------------------------------------------------------
;;; i18n minimal — détection de LANG sans dépendance externe
;;; --------------------------------------------------------------------------

(defun %getenv (name)
  #+sbcl  (sb-ext:posix-getenv name)
  #+clisp (ext:getenv name)
  #+ecl   (si:getenv name)
  #-(or sbcl clisp ecl) nil)

(defparameter *test-lang*
  (let ((lang (or (%getenv "LANG") (%getenv "LANGUAGE") "")))
    (if (and (>= (length lang) 2)
             (string= (subseq lang 0 2) "fr"))
        :fr :en)))

(defun %msg (fr en)
  (if (eq *test-lang* :fr) fr en))

;;; --------------------------------------------------------------------------

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
    (run-suite cl-asm/test.6510)
    (run-suite cl-asm/test.65c02)
    (run-suite cl-asm/test.r65c02)
    (run-suite cl-asm/test.45gs02)
    (run-suite cl-asm/test.65816)
    (run-suite cl-asm/test.z80)
    (run-suite cl-asm/test.m68k-parser)
    (run-suite cl-asm/test.m68k)

    ;; --- Intel 8080 ---
    (run-suite cl-asm/test.i8080)

    ;; --- Intel 8086 ---
    (run-suite cl-asm/test.i8086)

    ;; --- Simulateur ---
    (run-suite cl-asm/test.sim-6502)
    (run-suite cl-asm/test.sim-programs)

    ;; --- Outils ---
    (run-suite cl-asm/test.acme2clasm)

    ;; --- Désassembleur ---
    (run-suite cl-asm/test.disasm-6502)
    (run-suite cl-asm/test.disasm-45gs02)
    (run-suite cl-asm/test.disasm-65c02)

    ;; --- Débogueur ---
    (run-suite cl-asm/test.debugger-6502)

    ;; --- Linker ---
    (run-suite cl-asm/test.linker-6502)

    ;; --- Optimiseur ---
    (run-suite cl-asm/test.optimizer)

    ;; --- Conditions/Restarts ---
    (run-suite cl-asm/test.restarts)

    ;; --- Listing ---
    (run-suite cl-asm/test.listing)

    ;; --- Emetteurs ---
    (run-suite cl-asm/test.emitters)

    ;; --- Bilan global ---
    (format t "~%")
    (format t "--- ~A ---~%" (%msg "Core" "Core"))
    (format t "=== symbol-table : ~3D OK, ~D KO~%"
            cl-asm/test.symbol-table:*pass*
            cl-asm/test.symbol-table:*fail*)
    (format t "=== expression   : ~3D OK, ~D KO~%"
            cl-asm/test.expression:*pass*
            cl-asm/test.expression:*fail*)
    (format t "--- ~A ---~%" (%msg "Frontend" "Frontend"))
    (format t "=== lexer        : ~3D OK, ~D KO~%"
            cl-asm/test.lexer:*pass*
            cl-asm/test.lexer:*fail*)
    (format t "=== parser       : ~3D OK, ~D KO~%"
            cl-asm/test.parser:*pass*
            cl-asm/test.parser:*fail*)
    (format t "=== macros       : ~3D OK, ~D KO~%"
            cl-asm/test.macros:*pass*
            cl-asm/test.macros:*fail*)
    (format t "=== ~A : ~3D OK, ~D KO~%"
            (%msg "conditionnel" "conditional ")
            cl-asm/test.conditional:*pass*
            cl-asm/test.conditional:*fail*)
    (format t "=== lasm         : ~3D OK, ~D KO~%"
            cl-asm/test.lasm:*pass*
            cl-asm/test.lasm:*fail*)
    (format t "--- ~A ---~%" (%msg "Backends" "Backends"))
    (format t "=== 6502         : ~3D OK, ~D KO~%"
            cl-asm/test.6502:*pass*
            cl-asm/test.6502:*fail*)
    (format t "=== 6510 (c64)   : ~3D OK, ~D KO~%"
            cl-asm/test.6510:*pass*
            cl-asm/test.6510:*fail*)
    (format t "=== 65c02        : ~3D OK, ~D KO~%"
            cl-asm/test.65c02:*pass*
            cl-asm/test.65c02:*fail*)
    (format t "=== r65c02       : ~3D OK, ~D KO~%"
            cl-asm/test.r65c02:*pass*
            cl-asm/test.r65c02:*fail*)
    (format t "=== 45gs02       : ~3D OK, ~D KO~%"
            cl-asm/test.45gs02:*pass*
            cl-asm/test.45gs02:*fail*)
    (format t "=== 65816        : ~3D OK, ~D KO~%"
            cl-asm/test.65816:*pass*
            cl-asm/test.65816:*fail*)
    (format t "=== z80          : ~3D OK, ~D KO~%"
            cl-asm/test.z80:*pass*
            cl-asm/test.z80:*fail*)
    (format t "--- ~A ---~%" (%msg "Parsers architectures" "Architecture parsers"))
    (format t "=== m68k-parser  : ~3D OK, ~D KO~%"
            cl-asm/test.m68k-parser:*pass*
            cl-asm/test.m68k-parser:*fail*)
    (format t "=== m68k         : ~3D OK, ~D KO~%"
            cl-asm/test.m68k:*pass*
            cl-asm/test.m68k:*fail*)
    (format t "--- ~A ---~%" (%msg "Intel 8080" "Intel 8080"))
    (format t "=== i8080        : ~3D OK, ~D KO~%"
            cl-asm/test.i8080:*pass*
            cl-asm/test.i8080:*fail*)
    (format t "--- ~A ---~%" (%msg "Intel 8086" "Intel 8086"))
    (format t "=== i8086        : ~3D OK, ~D KO~%"
            cl-asm/test.i8086:*pass*
            cl-asm/test.i8086:*fail*)
    (format t "--- ~A ---~%" (%msg "Simulateur" "Simulator"))
    (format t "=== sim-6502     : ~3D OK, ~D KO~%"
            cl-asm/test.sim-6502:*pass*
            cl-asm/test.sim-6502:*fail*)
    (format t "=== sim-programs : ~3D OK, ~D KO~%"
            cl-asm/test.sim-programs:*pass*
            cl-asm/test.sim-programs:*fail*)
    (format t "--- ~A ---~%" (%msg "Outils" "Tools"))
    (format t "=== acme2clasm   : ~3D OK, ~D KO~%"
            cl-asm/test.acme2clasm:*pass*
            cl-asm/test.acme2clasm:*fail*)
    (format t "--- ~A ---~%" (%msg "Désassembleur" "Disassembler"))
    (format t "=== disasm-6502  : ~3D OK, ~D KO~%"
            cl-asm/test.disasm-6502:*pass*
            cl-asm/test.disasm-6502:*fail*)
    (format t "=== disasm-45gs02: ~3D OK, ~D KO~%"
            cl-asm/test.disasm-45gs02:*pass*
            cl-asm/test.disasm-45gs02:*fail*)
    (format t "=== disasm-65c02 : ~3D OK, ~D KO~%"
            cl-asm/test.disasm-65c02:*pass*
            cl-asm/test.disasm-65c02:*fail*)
    (format t "--- ~A ---~%" (%msg "Débogueur" "Debugger"))
    (format t "=== debugger-6502: ~3D OK, ~D KO~%"
            cl-asm/test.debugger-6502:*pass*
            cl-asm/test.debugger-6502:*fail*)
    (format t "--- ~A ---~%" (%msg "Linker" "Linker"))
    (format t "=== linker-6502  : ~3D OK, ~D KO~%"
            cl-asm/test.linker-6502:*pass*
            cl-asm/test.linker-6502:*fail*)
    (format t "--- ~A ---~%" (%msg "Optimiseur" "Optimizer"))
    (format t "=== optimizer    : ~3D OK, ~D KO~%"
            cl-asm/test.optimizer:*pass*
            cl-asm/test.optimizer:*fail*)
    (format t "--- ~A ---~%" (%msg "Conditions/Restarts" "Conditions/Restarts"))
    (format t "=== restarts     : ~3D OK, ~D KO~%"
            cl-asm/test.restarts:*pass*
            cl-asm/test.restarts:*fail*)
    (format t "--- ~A ---~%" (%msg "Listing" "Listing"))
    (format t "=== listing      : ~3D OK, ~D KO~%"
            cl-asm/test.listing:*pass*
            cl-asm/test.listing:*fail*)
    (format t "--- ~A ---~%" (%msg "Emetteurs" "Emitters"))
    (format t "=== emitters     : ~3D OK, ~D KO~%"
            cl-asm/test.emitters:*pass*
            cl-asm/test.emitters:*fail*)
    (format t "-------------------------------~%")
    (format t (%msg "=== TOTAL        : ~3D OK, ~D KO sur ~D tests~%"
                    "=== TOTAL        : ~3D OK, ~D KO out of ~D tests~%")
            total-pass total-fail (+ total-pass total-fail))
    (when total-failures
      (format t "~%~A :~%" (%msg "Echecs" "Failures"))
      (dolist (f (reverse total-failures))
        (format t "  - ~A~%" f)))
    (finish-output)
    (zerop total-fail)))
