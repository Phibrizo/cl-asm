; -*- coding: utf-8 -*-
(defpackage #:cl-asm/dead-code.z80
  (:use #:cl))

;;; src/dead-code/z80.lisp
;;;
;;; Tables de mnémoniques pour le détecteur de code mort — Zilog Z80.
;;;
;;; Le Z80 présente une ambiguïté : JP, JR, CALL et RET peuvent être
;;; conditionnels ou non selon le nombre d'opérandes.
;;;   JR label          → 1 opérande  → saut inconditionnel (:jump)
;;;   JR NZ, label      → 2 opérandes → branche conditionnelle (:branch)
;;;   JP label          → 1 opérande  → saut inconditionnel (:jump)
;;;   JP Z, label       → 2 opérandes → branche conditionnelle (:branch)
;;;   JP (HL)/(IX)/(IY) → indirect    → :return (cible inconnue)
;;;   CALL label        → 1 opérande  → appel (:call)
;;;   CALL Z, label     → 2 opérandes → :branch (peut appeler ou tomber)
;;;   RET               → 0 opérandes → retour (:return)
;;;   RET Z             → 1 opérande  → :normal (fall-through possible)
;;;
;;; classify-fn et target-operand-fn gèrent ces cas.

(in-package #:cl-asm/dead-code.z80)


;;; --------------------------------------------------------------------------
;;;  Classifieur Z80
;;; --------------------------------------------------------------------------

(defun %z80-classify (instr)
  "Classifie une instruction Z80 selon son mnémonique et ses opérandes."
  (let* ((m    (string-upcase (cl-asm/ir:ir-instruction-mnemonic instr)))
         (ops  (cl-asm/ir:ir-instruction-operands instr))
         (nops (length ops)))
    (cond
      ;; Retours inconditionnels et halte
      ((member m '("RETI" "RETN" "HALT") :test #'string=) :return)
      ;; RET seul = retour, RET cond = fall-through possible
      ((string= m "RET")
       (if (zerop nops) :return :normal))
      ;; DJNZ label → branche conditionnelle (loop)
      ((string= m "DJNZ") :branch)
      ;; RST n → appel vers adresse fixe (pas un label, mais fall-through)
      ((string= m "RST") :normal)
      ;; JR label vs JR cond, label
      ((string= m "JR")
       (if (= nops 2) :branch :jump))
      ;; JP (HL)/(IX)/(IY) → indirect (cible inconnue) ; JP cond,nn ; JP nn
      ((string= m "JP")
       (cond
         ;; JP cond, label → 2 opérandes
         ((= nops 2) :branch)
         ;; JP label → 1 opérande direct
         ((and (= nops 1)
               (let ((op (first ops)))
                 (and (cl-asm/ir:ir-operand-p op)
                      (eq  (cl-asm/ir:ir-operand-kind  op) :direct)
                      (stringp (cl-asm/ir:ir-operand-value op)))))
          :jump)
         ;; JP (HL) / JP (IX) / JP (IY) → indirect, pas de fall-through
         (t :return)))
      ;; CALL label vs CALL cond, label
      ((string= m "CALL")
       (if (= nops 2) :branch :call))
      ;; Tout le reste : séquentiel
      (t :normal))))

(defun %z80-target-operand (instr)
  "Retourne l'opérande cible de INSTR.
   Pour les instructions à 2 opérandes Z80 (cond, label), la cible est le
   SECOND opérande. Pour les instructions à 1 opérande, c'est le PREMIER."
  (let ((ops (cl-asm/ir:ir-instruction-operands instr)))
    (case (length ops)
      (2 (second ops))
      (t (first  ops)))))


;;; --------------------------------------------------------------------------
;;;  Enregistrement
;;; --------------------------------------------------------------------------

(cl-asm/dead-code:register-dead-code-analyzer
 :z80
 ;; Les listes ne sont pas utilisées (classify-fn prend le dessus),
 ;; mais on les fournit pour documenter les mnémoniques traités.
 :branch-mnemonics  '("JR" "JP" "CALL" "DJNZ")
 :jump-mnemonics    '("JR" "JP")
 :call-mnemonics    '("CALL")
 :return-mnemonics  '("RET" "RETI" "RETN" "HALT")
 :classify-fn       #'%z80-classify
 :target-operand-fn #'%z80-target-operand
 :description       "Zilog Z80")
