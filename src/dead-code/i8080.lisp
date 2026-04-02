; -*- coding: utf-8 -*-
(defpackage #:cl-asm/dead-code.i8080
  (:use #:cl))

;;; src/dead-code/i8080.lisp
;;;
;;; Tables de mnémoniques pour le détecteur de code mort — Intel 8080.
;;;
;;; Le 8080 code les conditions dans le mnémonique (JC/JNC/JZ/JNZ…),
;;; pas dans les opérandes. Chaque mnémonique est donc non ambigu.
;;;
;;; Cas particuliers :
;;;   - Retours conditionnels (RC/RNC/RZ/RNZ/RP/RM/RPE/RPO) : la fonction
;;;     peut retourner ou tomber au suivant → traités comme :normal.
;;;   - Appels conditionnels (CC/CNC/CZ/CNZ/CP/CM/CPE/CPO) : peuvent appeler
;;;     ou tomber → traités comme :branch (fall-through + cible).
;;;   - RST n : appel vers $0/$8/$10/…/$38 (adresse fixe, pas un label).
;;;     → :normal (fall-through et retour possible, cible non suivable).
;;;   - HLT : terminal.

(in-package #:cl-asm/dead-code.i8080)


;;; --------------------------------------------------------------------------
;;;  Tables i8080
;;; --------------------------------------------------------------------------

;;; Branches conditionnelles (fall-through + cible)
;;;   Jumps conditionnels + Appels conditionnels (traités pareil : 2 successeurs)
(defparameter *branches-i8080*
  '(;; Jumps conditionnels
    "JC" "JNC" "JZ" "JNZ" "JP" "JM" "JPE" "JPO"
    ;; Appels conditionnels
    "CC" "CNC" "CZ" "CNZ" "CP" "CM" "CPE" "CPO"))

;;; Sauts inconditionnels
(defparameter *jumps-i8080*
  '("JMP"))

;;; Appels inconditionnels
(defparameter *calls-i8080*
  '("CALL"))

;;; Instructions terminales
;;;   Les retours conditionnels NE sont PAS ici (ils ont un fall-through).
(defparameter *returns-i8080*
  '("RET" "HLT"))


;;; --------------------------------------------------------------------------
;;;  Enregistrement
;;; --------------------------------------------------------------------------

(cl-asm/dead-code:register-dead-code-analyzer
 :i8080
 :branch-mnemonics *branches-i8080*
 :jump-mnemonics   *jumps-i8080*
 :call-mnemonics   *calls-i8080*
 :return-mnemonics *returns-i8080*
 :description      "Intel 8080 / CP/M / Altair")
