; -*- coding: utf-8 -*-
;;; tests/test-dead-code.lisp
;;;
;;; Tests unitaires pour le détecteur de code mort de cl-asm.
;;; Couvre : registre, analyse 6502/Z80/M68K, labels morts/vivants,
;;;          points d'entrée explicites, sauts indirects (conservatif),
;;;          intégration avec assemble-string.

(defpackage #:cl-asm/test.dead-code
  (:use #:cl)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.dead-code)

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


;;; --------------------------------------------------------------------------
;;;  Helpers
;;; --------------------------------------------------------------------------

(defun dead-labels (src &key (target :6502) entry-points z80-mode)
  "Retourne la liste des noms de labels morts dans SRC assemblé pour TARGET.
   Z80-MODE : si non-NIL, active le mode Z80 du parser."
  (let* ((prog (if z80-mode
                   (let ((cl-asm/parser:*z80-mode* t))
                     (cl-asm/parser:parse-string src))
                   (cl-asm/parser:parse-string src)))
         (sections (cl-asm/ir:ir-program-sections prog))
         (warnings (cl-asm/dead-code:analyze-dead-code sections target
                                                        :entry-points entry-points)))
    (mapcar #'cl-asm/dead-code:dead-code-warning-label warnings)))

(defun dead-count (src &key (target :6502) entry-points z80-mode)
  "Retourne le nombre de labels morts."
  (length (dead-labels src :target target :entry-points entry-points :z80-mode z80-mode)))

(defun dead-p (label src &key (target :6502) entry-points z80-mode)
  "Vrai si LABEL est signalé comme mort."
  (member label (dead-labels src :target target :entry-points entry-points :z80-mode z80-mode)
          :test #'string=))

(defun alive-p (label src &key (target :6502) entry-points z80-mode)
  "Vrai si LABEL n'est PAS signalé comme mort."
  (not (dead-p label src :target target :entry-points entry-points :z80-mode z80-mode)))


;;; --------------------------------------------------------------------------
;;;  Registre
;;; --------------------------------------------------------------------------

(deftest test-registry
  (check "find :6502 enregistré"
    (cl-asm/dead-code:find-dead-code-analyzer :6502))
  (check "find :6510 enregistré"
    (cl-asm/dead-code:find-dead-code-analyzer :6510))
  (check "find :65c02 enregistré"
    (cl-asm/dead-code:find-dead-code-analyzer :65c02))
  (check "find :r65c02 enregistré"
    (cl-asm/dead-code:find-dead-code-analyzer :r65c02))
  (check "find :45gs02 enregistré"
    (cl-asm/dead-code:find-dead-code-analyzer :45gs02))
  (check "find :65816 enregistré"
    (cl-asm/dead-code:find-dead-code-analyzer :65816))
  (check "find :z80 enregistré"
    (cl-asm/dead-code:find-dead-code-analyzer :z80))
  (check "find :m68k enregistré"
    (cl-asm/dead-code:find-dead-code-analyzer :m68k))
  (check "find :i8080 enregistré"
    (cl-asm/dead-code:find-dead-code-analyzer :i8080))
  (check "find :i8086 enregistré"
    (cl-asm/dead-code:find-dead-code-analyzer :i8086))
  (check "architecture inconnue → NIL (pas d'erreur)"
    (null (cl-asm/dead-code:find-dead-code-analyzer :arm64)))
  (check "all-dead-code-analyzers contient ≥10 entrées"
    (>= (length (cl-asm/dead-code:all-dead-code-analyzers)) 10))
  (check "entrée :6502 est une dead-code-entry"
    (cl-asm/dead-code:dead-code-entry-p
     (cl-asm/dead-code:find-dead-code-analyzer :6502))))


;;; --------------------------------------------------------------------------
;;;  Cas simple : aucun code mort
;;; --------------------------------------------------------------------------

(deftest test-no-dead-code
  ;; Programme linéaire sans branche : tous les labels sont atteints
  (let ((src ".org $0200
start:
LDA #$01
STA $10
RTS"))
    (check "programme linéaire : start vivant"
      (alive-p "start" src))
    (check "programme linéaire : 0 labels morts"
      (zerop (dead-count src))))

  ;; Label atteint via JSR
  (let ((src ".org $0200
main:
JSR helper
RTS
helper:
LDA #$42
RTS"))
    (check "helper atteint via JSR"
      (alive-p "helper" src))
    (check "main vivant (point d'entrée)"
      (alive-p "main" src)))

  ;; Label atteint via branche conditionnelle (fall-through)
  (let ((src ".org $0200
main:
LDA #$00
BEQ skip
STA $10
skip:
RTS"))
    (check "skip vivant via fall-through BEQ"
      (alive-p "skip" src)))

  ;; Label atteint via branche conditionnelle (cible)
  (let ((src ".org $0200
main:
LDA $10
BNE done
INC $10
done:
RTS"))
    (check "done vivant via cible BNE"
      (alive-p "done" src))))


;;; --------------------------------------------------------------------------
;;;  Code mort : labels jamais atteints
;;; --------------------------------------------------------------------------

(deftest test-dead-labels
  ;; Fonction définie mais jamais appelée
  (let ((src ".org $0200
main:
LDA #$01
RTS
unused:
LDA #$FF
RTS"))
    (check "unused signalé comme mort"
      (dead-p "UNUSED" src))
    (check "main vivant"
      (alive-p "MAIN" src)))

  ;; Deux fonctions mortes
  (let ((src ".org $0200
main:
RTS
dead1:
NOP
RTS
dead2:
NOP
RTS"))
    (check "dead1 signalé"
      (dead-p "DEAD1" src))
    (check "dead2 signalé"
      (dead-p "DEAD2" src))
    (check "2 labels morts"
      (= 2 (dead-count src))))

  ;; Code après JMP inconditionnel (non atteint par fall-through)
  (let ((src ".org $0200
main:
JMP done
unreachable:
NOP
done:
RTS"))
    (check "unreachable mort (après JMP)"
      (dead-p "UNREACHABLE" src))
    (check "done vivant (cible de JMP)"
      (alive-p "DONE" src)))

  ;; Code après RTS
  (let ((src ".org $0200
main:
LDA #$01
RTS
after_rts:
NOP"))
    (check "after_rts mort (après RTS)"
      (dead-p "AFTER_RTS" src))))


;;; --------------------------------------------------------------------------
;;;  Points d'entrée explicites
;;; --------------------------------------------------------------------------

(deftest test-entry-points
  ;; NMI handler déclaré explicitement
  ;; Sans entry-points, le défaut est position 0 (.org) → NMI → RTI (terminal).
  ;; MAIN et IRQ ne sont donc pas atteints.
  (let ((src ".org $C000
nmi:
RTI
main:
LDA #$01
RTS
irq:
RTI"))
    (check "irq mort sans entry-point explicite"
      (dead-p "IRQ" src))
    (check "main mort sans entry-point explicite"
      (dead-p "MAIN" src))
    ;; Avec déclaration de tous les handlers
    (check "nmi vivant avec entry-point"
      (alive-p "NMI" src :entry-points '("nmi" "main" "irq")))
    (check "irq vivant avec entry-point"
      (alive-p "IRQ" src :entry-points '("nmi" "main" "irq"))))

  ;; Entry-point inexistant → ignoré silencieusement
  (let ((src ".org $0200
main:
RTS"))
    (check "entry-point inconnu ignoré sans erreur"
      (zerop (dead-count src :entry-points '("MAIN" "nonexistent"))))))


;;; --------------------------------------------------------------------------
;;;  Sauts indirects (conservatif — pas de faux positifs sur les cibles)
;;; --------------------------------------------------------------------------

(deftest test-indirect-jumps
  ;; JMP ($FFFC) : indirect → pas de fall-through, cible inconnue
  ;; Le code après JMP indirect est mort (correct)
  (let ((src ".org $0200
main:
JMP ($FFFC)
after_indirect:
NOP
RTS"))
    (check "after_indirect mort après JMP indirect"
      (dead-p "AFTER_INDIRECT" src)))

  ;; Le code AVANT le JMP indirect est vivant
  (let ((src ".org $0200
main:
LDA #$01
JMP ($FFFC)
dead_after:
NOP"))
    (check "main vivant avant JMP indirect"
      (alive-p "MAIN" src))))


;;; --------------------------------------------------------------------------
;;;  Architecture inconnue → liste vide (pas d'erreur)
;;; --------------------------------------------------------------------------

(deftest test-unknown-target
  (let ((src ".org $0200
main:
RTS"))
    (check "target inconnu → analyse retourne NIL"
      (null (dead-labels src :target :arm64)))))


;;; --------------------------------------------------------------------------
;;;  Intégration avec assemble-string (backend 6502)
;;; --------------------------------------------------------------------------

(deftest test-assemble-integration
  ;; Sans detect-dead-code : deuxième valeur absente (NIL)
  (multiple-value-bind (bytes warnings)
      (cl-asm/backend.6502:assemble-string ".org $0200
main:
RTS")
    (check "assemble sans detect-dead-code : bytes non nuls"
      (and bytes (> (length bytes) 0)))
    (check "assemble sans detect-dead-code : warnings NIL"
      (null warnings)))

  ;; Avec detect-dead-code : bytes + liste de warnings
  (multiple-value-bind (bytes warnings)
      (cl-asm/backend.6502:assemble-string
       ".org $0200
main:
LDA #$01
RTS
dead_fn:
NOP
RTS"
       :detect-dead-code t)
    (check "assemble avec detect-dead-code : bytes présents"
      (and bytes (> (length bytes) 0)))
    (check "assemble avec detect-dead-code : dead_fn signalé"
      (member "DEAD_FN" warnings
              :key #'cl-asm/dead-code:dead-code-warning-label
              :test #'string=)))

  ;; Code sans mort + detect-dead-code → liste vide (pas NIL)
  (multiple-value-bind (bytes warnings)
      (cl-asm/backend.6502:assemble-string
       ".org $0200
main:
JSR helper
RTS
helper:
NOP
RTS"
       :detect-dead-code t)
    (declare (ignore bytes))
    (check "aucun mort → warnings vide"
      (null warnings)))

  ;; dead-code-entry-points
  (multiple-value-bind (bytes warnings)
      (cl-asm/backend.6502:assemble-string
       ".org $C000
nmi:
RTI
main:
RTS"
       :detect-dead-code t
       :dead-code-entry-points '("nmi" "main"))
    (declare (ignore bytes))
    (check "nmi vivant avec entry-points"
      (null (member "nmi" warnings
                    :key #'cl-asm/dead-code:dead-code-warning-label
                    :test #'string=)))))


;;; --------------------------------------------------------------------------
;;;  Z80 : branche conditionnelle vs saut inconditionnel
;;; --------------------------------------------------------------------------

(deftest test-z80-control-flow
  ;; JR label (inconditionnel) → DEAD_Z80 non atteignable par fall-through
  (let ((src ".org $0000
main:
JR done
dead_z80:
NOP
done:
RET"))
    (check "Z80 JR inconditionnel : dead_z80 mort"
      (dead-p "DEAD_Z80" src :target :z80 :z80-mode t))
    (check "Z80 JR inconditionnel : done vivant"
      (alive-p "DONE" src :target :z80 :z80-mode t)))

  ;; JR NZ, label (conditionnel) → fall-through ET cible vivants
  (let ((src ".org $0000
main:
JR NZ, target
fallthrough:
RET
target:
RET"))
    (check "Z80 JR NZ : fallthrough vivant"
      (alive-p "FALLTHROUGH" src :target :z80 :z80-mode t))
    (check "Z80 JR NZ : target vivant"
      (alive-p "TARGET" src :target :z80 :z80-mode t)))

  ;; CALL nn → fall-through atteint, cible atteinte
  (let ((src ".org $0000
main:
CALL sub
after_call:
RET
sub:
INC A
RET"))
    (check "Z80 CALL : after_call vivant"
      (alive-p "AFTER_CALL" src :target :z80 :z80-mode t))
    (check "Z80 CALL : sub vivant"
      (alive-p "SUB" src :target :z80 :z80-mode t))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~%=== Détecteur de code mort ===~%")
  (test-registry)
  (test-no-dead-code)
  (test-dead-labels)
  (test-entry-points)
  (test-indirect-jumps)
  (test-unknown-target)
  (test-assemble-integration)
  (test-z80-control-flow)
  (format t "~%  dead-code : ~D OK, ~D KO~%~%" *pass* *fail*))
