; -*- coding: utf-8 -*-
(defpackage #:cl-asm/optimizer.65c02
  (:use #:cl))

;;; src/optimizer/65c02.lisp
;;;
;;; Règles d'optimisation peephole pour le WDC 65C02 et le 45GS02.
;;;
;;; Contient les règles A et B du 6502 (via cl-asm/optimizer.6502:*rules-6502*)
;;; plus la règle spécifique au 65C02 :
;;;
;;; Règle C — LDA #$00 / STA addr → STZ addr
;;;   [LDA #0] [STA :direct addr] → [STZ :direct addr]
;;;   Modes couverts :
;;;     LDA #$00 / STA $zp       → STZ $zp       (opcode $64)
;;;     LDA #$00 / STA $zp,X     → STZ $zp,X     (opcode $74)
;;;     LDA #$00 / STA $abs      → STZ $abs       (opcode $9C)
;;;     LDA #$00 / STA $abs,X    → STZ $abs,X     (opcode $9E)
;;;
;;;   La règle ne s'applique PAS pour :
;;;     LDA #val (val ≠ 0)
;;;     STA avec mode indirect, indirect-x, indirect-y

(in-package #:cl-asm/optimizer.65c02)


;;; --------------------------------------------------------------------------
;;;  Règle C : LDA #$00 / STA addr → STZ addr
;;; --------------------------------------------------------------------------

(defun %rule-lda0-sta-stz (nodes)
  "Remplace LDA #$00 / STA addr par STZ addr (économie de 2 octets).
   S'applique uniquement si STA est en mode :direct avec index nil ou :x.
   Retourne (values (list stz-node) 2) ou NIL."
  (let ((node (first nodes))
        (next (second nodes)))
    (when (and node next
               (typep node 'cl-asm/ir:ir-instruction)
               (string= (cl-asm/ir:ir-instruction-mnemonic node) "LDA")
               (typep next 'cl-asm/ir:ir-instruction)
               (string= (cl-asm/ir:ir-instruction-mnemonic next) "STA"))
      (let ((lda-op (first (cl-asm/ir:ir-instruction-operands node)))
            (sta-op (first (cl-asm/ir:ir-instruction-operands next))))
        (when (and lda-op sta-op
                   ;; LDA #$00 : mode immédiat, valeur littérale 0
                   (eq  (cl-asm/ir:ir-operand-kind  lda-op) :immediate)
                   (eql (cl-asm/ir:ir-operand-value lda-op) 0)
                   ;; STA : mode direct, indexé X ou sans indexage
                   (eq  (cl-asm/ir:ir-operand-kind      sta-op) :direct)
                   (member (cl-asm/ir:ir-operand-index-reg sta-op) '(nil :x)))
          (let* ((stz-op (cl-asm/ir:make-ir-operand
                          :kind      (cl-asm/ir:ir-operand-kind      sta-op)
                          :value     (cl-asm/ir:ir-operand-value     sta-op)
                          :index-reg (cl-asm/ir:ir-operand-index-reg sta-op)
                          :size-hint (cl-asm/ir:ir-operand-size-hint sta-op)
                          :loc       (cl-asm/ir:ir-operand-loc       sta-op)))
                 (stz (cl-asm/ir:make-ir-instruction
                       :mnemonic "STZ"
                       :operands (list stz-op)
                       :size     nil
                       :loc      (cl-asm/ir:ir-instruction-loc node))))
            (values (list stz) 2)))))))


;;; --------------------------------------------------------------------------
;;;  Liste des règles et enregistrement
;;; --------------------------------------------------------------------------

;;; Les règles 65C02 = règle C + règles A/B du 6502
(defparameter *rules-65c02*
  (cons #'%rule-lda0-sta-stz
        cl-asm/optimizer.6502:*rules-6502*)
  "Règles peephole pour le WDC 65C02 :
   règle C (LDA #0/STA→STZ) + règles A/B du 6502.")

;;; Note : la règle C ne s'applique PAS au 45GS02 car STZ y signifie
;;; "Store Z register" (opcode $84 zp, différent du STZ 65C02 $64 qui store zéro).
;;; Le 45GS02 bénéficie uniquement des règles A et B.

(cl-asm/optimizer:register-peephole-optimizer
 :65c02 *rules-65c02*
 "WDC 65C02 — règles A+B (6502) et C (LDA #0/STA→STZ)")

(cl-asm/optimizer:register-peephole-optimizer
 :45gs02 cl-asm/optimizer.6502:*rules-6502*
 "Mega65 (45GS02) — règles A+B seulement (STZ ≠ Store Zero sur 45GS02)")
