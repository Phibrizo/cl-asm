; -*- coding: utf-8 -*-
;;; bootstrap.lisp
;;;
;;; Chargement manuel de cl-asm sans ASDF.
;;; Les packages sont déclarés dans chaque fichier source.
;;; Ce fichier charge les fichiers dans le bon ordre de dépendances.
;;;
;;; Usage :
;;;   sbcl --load bootstrap.lisp
;;;   (cl-asm/backend.6502:assemble-string "NOP")
;;;   (cl-asm/simulator.6502:make-cpu)

(load "src/core/version.lisp")
(load "src/core/backends.lisp")
(load "src/core/ir.lisp")
(load "src/core/expression.lisp")
(load "src/core/symbol-table.lisp")
(load "src/frontend/classic-lexer.lisp")
(load "src/frontend/classic-parser.lisp")
(load "src/backend/6502.lisp")
(load "src/backend/45gs02.lisp")
(load "src/emit/output.lisp")
(load "src/backend/65c02.lisp")
(load "src/backend/r65c02.lisp")
(load "src/backend/65816.lisp")
(load "src/backend/z80.lisp")
(load "src/backend/m68k.lisp")
(load "src/backend/i8080.lisp")
(load "src/frontend/lasm.lisp")
(load "src/simulator/6502.lisp")
