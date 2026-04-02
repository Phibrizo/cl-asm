; -*- coding: utf-8 -*-
(defpackage #:cl-asm/dead-code.m68k
  (:use #:cl))

;;; src/dead-code/m68k.lisp
;;;
;;; Tables de mnémoniques pour le détecteur de code mort — Motorola 68000.
;;;
;;; Sur le 68000, les conditions sont encodées dans le mnémonique (BEQ, BNE…),
;;; pas dans les opérandes. Les seules ambiguïtés sont JMP et JSR qui peuvent
;;; être directs (label) ou indirects (registre/mémoire).
;;;
;;; Pour JMP/JSR :
;;;   - Opérande direct (string label) → cible connue → :jump / :call
;;;   - Opérande indirect (registre, indirect) → cible inconnue
;;;     → JMP indirect : :return (pas de fall-through, cible inconnue)
;;;     → JSR indirect : :call   (fall-through toujours atteint)
;;;
;;; DBcc (DBEQ, DBNE…) sont des instructions de boucle avec fall-through
;;; ou saut conditionnel → :branch.
;;;
;;; Pas de classify-fn nécessaire : BRA (inconditionnel) est dans
;;; jump-mnemonics, tous les Bcc sont dans branch-mnemonics.

(in-package #:cl-asm/dead-code.m68k)


;;; --------------------------------------------------------------------------
;;;  Tables M68K
;;; --------------------------------------------------------------------------

;;; Branches conditionnelles (fall-through + cible)
(defparameter *branches-m68k*
  '("BEQ" "BNE" "BCC" "BCS" "BHI" "BLS" "BGE" "BLT" "BGT" "BLE"
    "BPL" "BMI" "BVC" "BVS"
    ;; DBcc : boucle décrément — fall-through si compteur épuisé, saut sinon
    "DBEQ" "DBNE" "DBCC" "DBCS" "DBHI" "DBLS" "DBGE" "DBLT" "DBGT" "DBLE"
    "DBPL" "DBMI" "DBVC" "DBVS" "DBT" "DBF" "DBRA"))

;;; Sauts inconditionnels (cible seulement)
;;; JMP indirect (JMP (A0) etc.) → %operand->label retourne NIL → aucun successeur
(defparameter *jumps-m68k*
  '("BRA" "JMP"))

;;; Appels (fall-through + cible si directe)
;;; JSR indirect → fall-through atteint, cible inconnue (pas de problème)
(defparameter *calls-m68k*
  '("BSR" "JSR"))

;;; Instructions terminales
(defparameter *returns-m68k*
  '("RTS" "RTR" "RTE"))


;;; --------------------------------------------------------------------------
;;;  Enregistrement
;;; --------------------------------------------------------------------------

(cl-asm/dead-code:register-dead-code-analyzer
 :m68k
 :branch-mnemonics *branches-m68k*
 :jump-mnemonics   *jumps-m68k*
 :call-mnemonics   *calls-m68k*
 :return-mnemonics *returns-m68k*
 :description      "Motorola 68000 / Amiga / Atari ST")
