; -*- coding: utf-8 -*-
(defpackage #:cl-asm/dead-code.i8086
  (:use #:cl))

;;; src/dead-code/i8086.lisp
;;;
;;; Tables de mnémoniques pour le détecteur de code mort — Intel 8086/8088.
;;;
;;; Sur le 8086 :
;;;   - Tous les Jcc sont conditionnels (2 lettres après J, ou JCXZ) → :branch
;;;   - LOOP/LOOPE/LOOPNE/LOOPNZ/LOOPZ → :branch (décrément + test)
;;;   - JMP peut être direct (label) ou indirect (reg/mem) :
;;;       JMP label    → :jump (opérande string → cible suivable)
;;;       JMP [BX]     → :jump (opérande non-string → pas de cible, pas de fall-through)
;;;   - CALL peut être direct ou indirect (fall-through toujours atteint) → :call
;;;   - INT n : appel système avec reprise → :normal (fall-through atteint)
;;;   - INTO : conditionnel → :normal
;;;   - HLT, RET, RETF, IRET : terminaux

(in-package #:cl-asm/dead-code.i8086)


;;; --------------------------------------------------------------------------
;;;  Tables i8086
;;; --------------------------------------------------------------------------

;;; Branches conditionnelles (fall-through + cible)
(defparameter *branches-i8086*
  '(;; Jcc standards
    "JE"  "JNE" "JA"  "JB"  "JG"  "JL"  "JGE" "JLE"
    "JAE" "JBE" "JP"  "JNP" "JS"  "JNS" "JO"  "JNO"
    ;; Alias courants
    "JZ"  "JNZ" "JC"  "JNC" "JNA" "JNAE" "JNB" "JNBE"
    "JNG" "JNGE" "JNL" "JNLE" "JPE" "JPO"
    ;; Spéciaux
    "JCXZ"
    ;; Boucles LOOP
    "LOOP" "LOOPE" "LOOPNE" "LOOPNZ" "LOOPZ"))

;;; Sauts inconditionnels
;;; JMPF (far jump) : même logique → cible directe si label
(defparameter *jumps-i8086*
  '("JMP" "JMPF"))

;;; Appels (fall-through toujours atteint)
(defparameter *calls-i8086*
  '("CALL" "CALLF"))

;;; Instructions terminales
(defparameter *returns-i8086*
  '("RET" "RETF" "IRET" "HLT"))


;;; --------------------------------------------------------------------------
;;;  Enregistrement
;;; --------------------------------------------------------------------------

(cl-asm/dead-code:register-dead-code-analyzer
 :i8086
 :branch-mnemonics *branches-i8086*
 :jump-mnemonics   *jumps-i8086*
 :call-mnemonics   *calls-i8086*
 :return-mnemonics *returns-i8086*
 :description      "Intel 8086/8088 / IBM PC / MS-DOS")
