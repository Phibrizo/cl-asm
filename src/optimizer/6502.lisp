; -*- coding: utf-8 -*-
(defpackage #:cl-asm/optimizer.6502
  (:use #:cl)
  (:export #:*rules-6502*))

;;; src/optimizer/6502.lisp
;;;
;;; Règles d'optimisation peephole pour le MOS 6502 et le MOS 6510.
;;;
;;; Règle A — JMP supprimé quand il saute au label immédiatement suivant :
;;;   [JMP target] [label target] → [label target]
;;;
;;; Règle B — Tail call : JSR foo / RTS → JMP foo
;;;   [JSR target] [RTS] → [JMP target]
;;;   Condition : aucun label entre JSR et RTS (sinon RTS est atteignable
;;;   par d'autres chemins et le remplacement changerait la sémantique).

(in-package #:cl-asm/optimizer.6502)


;;; --------------------------------------------------------------------------
;;;  Règle A : JMP → label suivant (saut superflu)
;;; --------------------------------------------------------------------------

(defun %rule-jmp-next-label (nodes)
  "Supprime JMP target quand target: est le nœud IR immédiatement suivant.
   Retourne (values (list label-node) 2) si la règle s'applique, sinon NIL."
  (let ((node (first nodes))
        (next (second nodes)))
    (when (and node next
               (typep node 'cl-asm/ir:ir-instruction)
               (string= (cl-asm/ir:ir-instruction-mnemonic node) "JMP")
               (typep next 'cl-asm/ir:ir-label))
      (let ((operand (first (cl-asm/ir:ir-instruction-operands node))))
        (when (and operand
                   (eq (cl-asm/ir:ir-operand-kind operand) :direct)
                   (null (cl-asm/ir:ir-operand-index-reg operand))
                   (stringp (cl-asm/ir:ir-operand-value operand))
                   (string= (cl-asm/ir:ir-operand-value operand)
                            (cl-asm/ir:ir-label-name next)))
          (values (list next) 2))))))


;;; --------------------------------------------------------------------------
;;;  Règle B : tail-call JSR foo / RTS → JMP foo
;;; --------------------------------------------------------------------------

(defun %rule-jsr-rts-jmp (nodes)
  "Remplace JSR target / RTS par JMP target (tail-call optimization).
   La règle ne s'applique pas s'il existe un label entre JSR et RTS
   (un tel label signifie que RTS est atteignable par d'autres chemins).
   Retourne (values (list jmp-node) 2) ou NIL."
  (let ((node (first nodes))
        (next (second nodes)))
    (when (and node next
               (typep node 'cl-asm/ir:ir-instruction)
               (string= (cl-asm/ir:ir-instruction-mnemonic node) "JSR")
               (typep next 'cl-asm/ir:ir-instruction)
               (string= (cl-asm/ir:ir-instruction-mnemonic next) "RTS"))
      (let* ((operand (first (cl-asm/ir:ir-instruction-operands node)))
             (jmp (cl-asm/ir:make-ir-instruction
                   :mnemonic "JMP"
                   :operands (list operand)
                   :size     nil
                   :loc      (cl-asm/ir:ir-instruction-loc node))))
        (values (list jmp) 2)))))


;;; --------------------------------------------------------------------------
;;;  Liste des règles et enregistrement
;;; --------------------------------------------------------------------------

(defparameter *rules-6502*
  (list #'%rule-jmp-next-label
        #'%rule-jsr-rts-jmp)
  "Règles peephole pour le MOS 6502 (et le MOS 6510).")

(cl-asm/optimizer:register-peephole-optimizer
 :6502 *rules-6502*
 "MOS 6502 — règles A (JMP→label suivant) et B (JSR/RTS→JMP)")

(cl-asm/optimizer:register-peephole-optimizer
 :6510 *rules-6502*
 "MOS 6510 / C64 — mêmes règles que le 6502")
