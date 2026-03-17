; -*- coding: utf-8 -*-
;;; bootstrap.lisp
;;;
;;; Chargement manuel de cl-asm sans ASDF.
;;; Les packages sont declarers dans chaque fichier source.
;;; Ce fichier charge les fichiers dans le bon ordre.
;;;
;;; Usage :
;;;   sbcl --load bootstrap.lisp
;;;   (cl-asm/backend.6502:assemble-string "NOP")

(load "src/core/version.lisp")
(load "src/core/ir.lisp")
(load "src/core/expression.lisp")
(load "src/core/symbol-table.lisp")
(load "src/frontend/classic-lexer.lisp")
(load "src/frontend/classic-parser.lisp")
(load "src/backend/6502.lisp")
(load "src/backend/45gs02.lisp")
(load "src/emit/output.lisp")
(load "src/backend/65c02.lisp")
(load "src/frontend/lasm.lisp")
