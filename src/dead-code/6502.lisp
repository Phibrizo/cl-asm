; -*- coding: utf-8 -*-
(defpackage #:cl-asm/dead-code.6502
  (:use #:cl))

;;; src/dead-code/6502.lisp
;;;
;;; Tables de mnémoniques pour le détecteur de code mort — famille 6502.
;;;
;;; Couvre : MOS 6502, MOS 6510 (C64), WDC 65C02, Rockwell 65C02,
;;;           45GS02 (Mega65), WDC 65816 (SNES/Apple IIgs).
;;;
;;; Dans toute la famille 6502, chaque mnémonique est non ambigu :
;;; la classification branche/saut/appel/retour ne dépend pas des opérandes.
;;; Aucun classify-fn ni target-operand-fn n'est nécessaire.

(in-package #:cl-asm/dead-code.6502)


;;; --------------------------------------------------------------------------
;;;  Tables communes à toute la famille 6502
;;; --------------------------------------------------------------------------

(defparameter *branches-6502*
  '("BEQ" "BNE" "BCC" "BCS" "BPL" "BMI" "BVC" "BVS")
  "Branches conditionnelles MOS 6502 (deux successeurs : fall-through + cible).")

(defparameter *jumps-6502*
  '("JMP")
  "Saut inconditionnel 6502. La cible indirecte JMP (addr) est détectée
   via l'opérande non-string et n'est pas suivie (conservatif).")

(defparameter *calls-6502*
  '("JSR")
  "Appels de sous-routine 6502 (deux successeurs : fall-through + cible).")

(defparameter *returns-6502*
  '("RTS" "RTI" "BRK")
  "Instructions terminales 6502 (aucun successeur).
   BRK est traité comme un arrêt ; s'il est utilisé pour des appels système
   (C64 kernal) avec reprise, déclarer le point de reprise comme entry-point.")

;;; --- Enregistrement 6502 ---

(cl-asm/dead-code:register-dead-code-analyzer
 :6502
 :branch-mnemonics *branches-6502*
 :jump-mnemonics   *jumps-6502*
 :call-mnemonics   *calls-6502*
 :return-mnemonics *returns-6502*
 :description      "MOS 6502")

;;; --- 6510 : ajoute KIL (opcode illégal, halt CPU) ---

(cl-asm/dead-code:register-dead-code-analyzer
 :6510
 :branch-mnemonics *branches-6502*
 :jump-mnemonics   *jumps-6502*
 :call-mnemonics   *calls-6502*
 :return-mnemonics (cons "KIL" *returns-6502*)
 :description      "MOS 6510 / Commodore 64")

;;; --- 65C02 : ajoute BRA (branche inconditionnelle = saut court) ---

(defparameter *jumps-65c02*
  (cons "BRA" *jumps-6502*)
  "BRA est inconditionnelle (toujours pris), donc :jump (pas de fall-through).")

(cl-asm/dead-code:register-dead-code-analyzer
 :65c02
 :branch-mnemonics *branches-6502*
 :jump-mnemonics   *jumps-65c02*
 :call-mnemonics   *calls-6502*
 :return-mnemonics *returns-6502*
 :description      "WDC 65C02 / Commander X16")

;;; --- R65C02 : identique au 65C02 (extensions Rockwell = bit ops, pas de CF) ---

(cl-asm/dead-code:register-dead-code-analyzer
 :r65c02
 :branch-mnemonics *branches-6502*
 :jump-mnemonics   *jumps-65c02*
 :call-mnemonics   *calls-6502*
 :return-mnemonics *returns-6502*
 :description      "Rockwell 65C02")

;;; --- 45GS02 : branches longues + branches de boucle ---

(defparameter *branches-45gs02*
  (append *branches-6502*
          '("LBEQ" "LBNE" "LBCC" "LBCS" "LBPL" "LBMI" "LBVC" "LBVS"))
  "Branches conditionnelles 45GS02 : variantes courtes (6502) + longues (Mega65).")

(defparameter *jumps-45gs02*
  ;; BRA (court) et LBRA (long) sont inconditionnelles → pas de fall-through
  (append *jumps-65c02* '("LBRA"))
  "Sauts inconditionnels 45GS02.")

(defparameter *calls-45gs02*
  (append *calls-6502* '("JSQ"))
  "Appels 45GS02 : JSR (normal) + JSQ (appel Q-word).")

(defparameter *returns-45gs02*
  (append *returns-6502* '("RTQ"))
  "Retours 45GS02 : RTS/RTI/BRK (6502) + RTQ (retour Q-word).")

(cl-asm/dead-code:register-dead-code-analyzer
 :45gs02
 :branch-mnemonics *branches-45gs02*
 :jump-mnemonics   *jumps-45gs02*
 :call-mnemonics   *calls-45gs02*
 :return-mnemonics *returns-45gs02*
 :description      "45GS02 / Mega65")

;;; --- 65816 : variantes longues + COP ---

(defparameter *branches-65816*
  *branches-6502*
  "Branches conditionnelles 65816 (identiques au 6502).")

(defparameter *jumps-65816*
  ;; BRA (toujours pris, court), BRL (toujours pris, long), JMP, JML
  '("JMP" "JML" "BRA" "BRL")
  "Sauts inconditionnels 65816.")

(defparameter *calls-65816*
  '("JSR" "JSL")
  "Appels 65816 : JSR (court) + JSL (long, 24 bits).")

(defparameter *returns-65816*
  '("RTS" "RTL" "RTI" "BRK" "COP")
  "Instructions terminales 65816 : retours normaux + interruptions logicielles.")

(cl-asm/dead-code:register-dead-code-analyzer
 :65816
 :branch-mnemonics *branches-65816*
 :jump-mnemonics   *jumps-65816*
 :call-mnemonics   *calls-65816*
 :return-mnemonics *returns-65816*
 :description      "WDC 65816 / SNES / Apple IIgs")
