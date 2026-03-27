; -*- coding: utf-8 -*-
;;; tests/test-optimizer.lisp
;;;
;;; Tests unitaires pour l'optimiseur peephole de cl-asm.
;;; Couvre : registre, règle A (JMP superflu), règle B (JSR/RTS→JMP),
;;;          règle C (LDA #0/STA→STZ), comportement multi-règles,
;;;          optimize=NIL (pas d'effet), frontières entre architectures.

(defpackage #:cl-asm/test.optimizer
  (:use #:cl)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.optimizer)

(defvar *pass* 0)
(defvar *fail* 0)
(defvar *failures* '())

(defmacro check (desc expr)
  `(if ,expr
       (progn (incf *pass*)
              (format t "  OK  ~A~%" ,desc))
       (progn (incf *fail*)
              (push ,desc *failures*)
              (format t "  KO  ~A~%" ,desc))))

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&--- ~A ---~%" ',name)
     ,@body))

;;; Helpers

(defun asm6502 (src &key optimize)
  (cl-asm/backend.6502:assemble-string src :optimize optimize))

(defun asm6510 (src &key optimize)
  (cl-asm/backend.6510:assemble-string-6510 src :optimize optimize))

(defun asm65c02 (src &key optimize)
  (cl-asm/backend.65c02:assemble-string-65c02 src :optimize optimize))

(defun asm45gs02 (src &key optimize)
  (cl-asm/backend.45gs02:assemble-string-45gs02 src :optimize optimize))

(defun bytes (&rest args) (coerce args '(vector (unsigned-byte 8))))


;;; --------------------------------------------------------------------------
;;;  Registre
;;; --------------------------------------------------------------------------

(deftest test-registry
  ;; Les optimiseurs pour :6502, :6510, :65c02 et :45gs02 sont enregistrés
  (check "find :6502"
    (cl-asm/optimizer:find-peephole-optimizer :6502))
  (check "find :6510"
    (cl-asm/optimizer:find-peephole-optimizer :6510))
  (check "find :65c02"
    (cl-asm/optimizer:find-peephole-optimizer :65c02))
  (check "find :45gs02"
    (cl-asm/optimizer:find-peephole-optimizer :45gs02))
  (check "find inconnue → NIL"
    (null (cl-asm/optimizer:find-peephole-optimizer :z80)))
  (check "all-peephole-optimizers non vide"
    (>= (length (cl-asm/optimizer:all-peephole-optimizers)) 4))
  (check "entrée :6502 est une peephole-entry"
    (cl-asm/optimizer:peephole-entry-p
     (cl-asm/optimizer:find-peephole-optimizer :6502))))


;;; --------------------------------------------------------------------------
;;;  optimize=NIL → aucun effet
;;; --------------------------------------------------------------------------

(deftest test-optimize-nil-no-effect
  ;; Sans :optimize t, le code est assemblé tel quel
  (let ((src ".org $0200
JMP done
done:
RTS"))
    (check "optimize=NIL : JMP non supprimé"
      (equalp (asm6502 src)
              (bytes #x4C #x03 #x02 #x60))))
  (let ((src ".org $0200
LDA #$00
STA $10
RTS"))
    (check "optimize=NIL (65c02) : LDA #0/STA non remplacé"
      (equalp (asm65c02 src)
              (bytes #xA9 #x00 #x85 #x10 #x60)))))


;;; --------------------------------------------------------------------------
;;;  Règle A : JMP → label immédiatement suivant
;;; --------------------------------------------------------------------------

(deftest test-rule-a-jmp-next-label
  ;; JMP done / done: → label seul (JMP éliminé)
  (let ((src ".org $0200
JMP done
done:
LDA #$01
RTS"))
    (check "règle A : JMP éliminé, code plus court"
      (equalp (asm6502 src :optimize t)
              (bytes #xA9 #x01 #x60)))
    ;; Sans optimisation : JMP $0203 puis LDA #1, RTS
    (check "règle A : sans opt, JMP présent"
      (equalp (asm6502 src)
              (bytes #x4C #x03 #x02 #xA9 #x01 #x60))))

  ;; JMP non-adjacent (autre code entre JMP et le label) → pas d'élimination
  (let ((src ".org $0200
JMP far
NOP
far:
RTS"))
    (check "règle A : JMP non-adjacent non éliminé"
      (equalp (asm6502 src :optimize t)
              (bytes #x4C #x04 #x02 #xEA #x60))))

  ;; Règle A sur 6510 aussi
  (let ((src ".org $0200
JMP skip
skip:
LDA #$FF
RTS"))
    (check "règle A sur 6510"
      (equalp (asm6510 src :optimize t)
              (bytes #xA9 #xFF #x60)))))


;;; --------------------------------------------------------------------------
;;;  Règle B : JSR foo / RTS → JMP foo (tail-call)
;;; --------------------------------------------------------------------------

(deftest test-rule-b-jsr-rts-jmp
  ;; JSR helper / RTS → JMP helper
  (let ((src ".org $0200
main:
JSR helper
RTS
helper:
LDA #$42
RTS"))
    ;; Sans opt : JSR($20) $04 $02  RTS($60)  LDA($A9) $42  RTS($60)
    ;; helper: est à $0204
    (check "règle B : sans opt, JSR+RTS présents"
      (equalp (asm6502 src)
              (bytes #x20 #x04 #x02 #x60 #xA9 #x42 #x60)))
    ;; Avec opt : JMP($4C) $03 $02  LDA($A9) $42  RTS($60)
    ;; helper: est maintenant à $0203 (JMP est 3 octets comme JSR)
    (check "règle B : JSR/RTS → JMP"
      (equalp (asm6502 src :optimize t)
              (bytes #x4C #x03 #x02 #xA9 #x42 #x60))))

  ;; Label entre JSR et RTS → pas de remplacement
  (let ((src ".org $0200
JSR foo
bar:
RTS
foo:
NOP
RTS"))
    (check "règle B : label entre JSR et RTS → non optimisé"
      (equalp (asm6502 src :optimize t)
              (asm6502 src))))

  ;; Chaîne de tail-calls : les deux JSR/RTS sont optimisés
  (let ((src ".org $0200
JSR fn1
RTS
fn1:
JSR fn2
RTS
fn2:
NOP
RTS"))
    (let ((opt (asm6502 src :optimize t))
          (raw (asm6502 src)))
      (check "règle B : chaîne de tail-calls réduit le code"
        (< (length opt) (length raw)))))

  ;; Règle B sur 6510
  (let ((src ".org $0200
JSR sub
RTS
sub:
INX
RTS"))
    (check "règle B sur 6510"
      (let ((opt (asm6510 src :optimize t))
            (raw (asm6510 src)))
        (< (length opt) (length raw))))))


;;; --------------------------------------------------------------------------
;;;  Règle C : LDA #$00 / STA → STZ (65C02 / 45GS02 uniquement)
;;; --------------------------------------------------------------------------

(deftest test-rule-c-lda0-sta-stz
  ;; LDA #0 / STA $zp → STZ $zp
  (let ((src ".org $0200
LDA #$00
STA $10
RTS"))
    (check "règle C : LDA #0/STA zp → STZ zp"
      (equalp (asm65c02 src :optimize t)
              (bytes #x64 #x10 #x60)))
    (check "règle C : sans opt, LDA #0 + STA zp"
      (equalp (asm65c02 src)
              (bytes #xA9 #x00 #x85 #x10 #x60))))

  ;; LDA #0 / STA $abs → STZ $abs
  (let ((src ".org $0200
LDA #$00
STA $1234
RTS"))
    (check "règle C : LDA #0/STA abs → STZ abs"
      (equalp (asm65c02 src :optimize t)
              (bytes #x9C #x34 #x12 #x60))))

  ;; LDA #0 / STA $zp,X → STZ $zp,X
  (let ((src ".org $0200
LDA #$00
STA $10,X
RTS"))
    (check "règle C : LDA #0/STA zp,X → STZ zp,X"
      (equalp (asm65c02 src :optimize t)
              (bytes #x74 #x10 #x60))))

  ;; LDA #1 ≠ 0 → pas de remplacement
  (let ((src ".org $0200
LDA #$01
STA $10
RTS"))
    (check "règle C : LDA #1 non remplacé"
      (equalp (asm65c02 src :optimize t)
              (bytes #xA9 #x01 #x85 #x10 #x60))))

  ;; STA ($10),Y (indirect-y) → pas de remplacement
  (let ((src ".org $0200
LDA #$00
STA ($10),Y
RTS"))
    (check "règle C : STA indirect non remplacé"
      (equalp (asm65c02 src :optimize t)
              (bytes #xA9 #x00 #x91 #x10 #x60))))

  ;; Règle C absente sur 45GS02 (STZ y signifie "Store Z register", pas "Store Zero")
  (let ((src ".org $2001
LDA #$00
STA $20
RTS"))
    (check "règle C absente sur 45GS02 : code inchangé"
      (equalp (asm45gs02 src :optimize t)
              (asm45gs02 src))))

  ;; Règle C PAS sur 6502 (STZ n'existe pas)
  (let ((src ".org $0200
LDA #$00
STA $10
RTS"))
    (check "règle C absente sur 6502 : code inchangé"
      (equalp (asm6502 src :optimize t)
              (bytes #xA9 #x00 #x85 #x10 #x60)))))


;;; --------------------------------------------------------------------------
;;;  Tests combinés : plusieurs règles dans un même programme
;;; --------------------------------------------------------------------------

(deftest test-combined-rules
  ;; JMP + JSR/RTS + LDA#0/STA dans un même programme (65C02)
  (let ((src ".org $0200
start:
LDA #$00
STA $FB
JSR print
RTS
JMP end
end:
NOP
RTS
print:
LDA #$01
RTS"))
    (let* ((opt (asm65c02 src :optimize t))
           (raw (asm65c02 src)))
      (check "combiné 65C02 : code plus court avec optimize"
        (< (length opt) (length raw)))))

  ;; Programme minimaliste : une seule règle suffit
  (let ((src ".org $0300
LDA #$00
STA $C0
LDA #$00
STA $C1
RTS"))
    (check "règle C appliquée deux fois"
      (equalp (asm65c02 src :optimize t)
              (bytes #x64 #xC0 #x64 #xC1 #x60)))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~%=== Optimiseur peephole ===~%")
  (test-registry)
  (test-optimize-nil-no-effect)
  (test-rule-a-jmp-next-label)
  (test-rule-b-jsr-rts-jmp)
  (test-rule-c-lda0-sta-stz)
  (test-combined-rules)
  (format t "~%  optimizer : ~D OK, ~D KO~%~%" *pass* *fail*))
