; -*- coding: utf-8 -*-
;;; tests/test-profiler-6502.lisp
;;;
;;; Tests unitaires pour le profiler/tracer 6502.

(defpackage #:cl-asm/test.profiler-6502
  (:use #:cl
        #:cl-asm/simulator.6502
        #:cl-asm/profiler.6502)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.profiler-6502)

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

(defun make-cpu-from-src (src)
  "Assemble SRC (avec .org), charge dans un CPU, positionne PC à $0200."
  (let* ((bytes (cl-asm/backend.6502:assemble-string src))
         (cpu   (make-cpu)))
    (load-program cpu bytes :origin #x0200)
    (reset-cpu cpu :origin #x0200)
    cpu))

;;; --------------------------------------------------------------------------
;;;  Profiler — construction et reset
;;; --------------------------------------------------------------------------

(deftest test-profiler-make
  (let ((p (make-profiler)))
    (check "make-profiler — hit-count est un vecteur 65536"
           (= (length (profiler-hit-count p)) 65536))
    (check "make-profiler — cycle-count est un vecteur 65536"
           (= (length (profiler-cycle-count p)) 65536))
    (check "make-profiler — total-hits = 0"
           (= (profiler-total-hits p) 0))
    (check "make-profiler — total-cycles = 0"
           (= (profiler-total-cycles p) 0))
    (check "make-profiler — hit-count[$0000] = 0"
           (= (aref (profiler-hit-count p) 0) 0))))

(deftest test-profiler-reset
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDA #$FF
    BRK"))
         (p (make-profiler)))
    (run-with-profiler cpu p)
    (check "reset — avant reset, hits > 0"
           (> (profiler-total-hits p) 0))
    (profiler-reset p)
    (check "reset — total-hits = 0 après reset"
           (= (profiler-total-hits p) 0))
    (check "reset — total-cycles = 0 après reset"
           (= (profiler-total-cycles p) 0))
    (check "reset — hit-count[$0200] = 0 après reset"
           (= (aref (profiler-hit-count p) #x0200) 0))))

;;; --------------------------------------------------------------------------
;;;  Profiler — comptage hits
;;; --------------------------------------------------------------------------

(deftest test-profiler-hit-count-single
  ;; LDA #$FF (A9 FF) à $0202, BRK ($00) à $0204
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDA #$FF
    BRK"))
         (p (make-profiler)))
    (run-with-profiler cpu p)
    (check "hit count $0200 = 1 (LDA #$FF)"
           (= (aref (profiler-hit-count p) #x0200) 1))
    (check "hit count $0202 = 1 (BRK)"
           (= (aref (profiler-hit-count p) #x0202) 1))
    (check "total-hits = 2"
           (= (profiler-total-hits p) 2))
    (check "hit count adresse non exécutée = 0"
           (= (aref (profiler-hit-count p) #x0300) 0))))

(deftest test-profiler-hit-count-loop
  ;; Boucle 4 fois :
  ;; $0200  LDX #4  (2 octets) — exécuté 1 fois
  ;; $0202  DEX     (1 octet)  — exécuté 4 fois
  ;; $0203  BNE $0202 (2 oct) — exécuté 4 fois (3 prises + 1 non prise)
  ;; $0205  BRK     (1 octet)  — exécuté 1 fois
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDX #4
loop:
    DEX
    BNE loop
    BRK"))
         (p (make-profiler)))
    (run-with-profiler cpu p)
    (check "LDX #4 — hit 1 fois"
           (= (aref (profiler-hit-count p) #x0200) 1))
    (check "DEX — hit 4 fois"
           (= (aref (profiler-hit-count p) #x0202) 4))
    (check "BNE loop — hit 4 fois"
           (= (aref (profiler-hit-count p) #x0203) 4))
    (check "BRK — hit 1 fois"
           (= (aref (profiler-hit-count p) #x0205) 1))
    (check "total-hits = 10"
           (= (profiler-total-hits p) 10))))

;;; --------------------------------------------------------------------------
;;;  Profiler — comptage cycles
;;; --------------------------------------------------------------------------

(deftest test-profiler-cycle-count
  ;; LDA #$FF = 2 cycles (imm), NOP = 2 cycles, BRK = 7 cycles
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDA #$FF
    NOP
    BRK"))
         (p (make-profiler)))
    (run-with-profiler cpu p)
    (check "cycle-count $0200 (LDA #$FF) = 2"
           (= (aref (profiler-cycle-count p) #x0200) 2))
    (check "cycle-count $0202 (NOP) = 2"
           (= (aref (profiler-cycle-count p) #x0202) 2))
    (check "cycle-count $0203 (BRK) = 7"
           (= (aref (profiler-cycle-count p) #x0203) 7))
    (check "total-cycles = 11 (2+2+7)"
           (= (profiler-total-cycles p) 11))))

(deftest test-profiler-cycle-accumulation
  ;; Boucle LDX #3 / DEX / BNE
  ;; DEX = 2 cycles × 3 = 6 cycles cumulés
  ;; BNE : 2 prises (3cy) + 1 non-prise (2cy) = 8 cycles cumulés
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDX #3
loop:
    DEX
    BNE loop
    BRK"))
         (p (make-profiler)))
    (run-with-profiler cpu p)
    (check "DEX — 3×2 = 6 cycles cumulés"
           (= (aref (profiler-cycle-count p) #x0202) 6))
    (check "BNE — 2 prises (3cy) + 1 non-prise (2cy) = 8 cycles"
           (= (aref (profiler-cycle-count p) #x0203) 8))))

;;; --------------------------------------------------------------------------
;;;  Profiler — accumulation entre plusieurs runs
;;; --------------------------------------------------------------------------

(deftest test-profiler-accumulates
  ;; Deux runs successifs sans reset — compteurs s'accumulent
  (let ((p (make-profiler)))
    (run-with-profiler
     (make-cpu-from-src "
    .org $0200
    NOP
    BRK")
     p)
    (run-with-profiler
     (make-cpu-from-src "
    .org $0200
    NOP
    BRK")
     p)
    (check "accumulation — NOP hit 2 fois (2 runs)"
           (= (aref (profiler-hit-count p) #x0200) 2))
    (check "accumulation — total-hits = 4 (2 runs × 2 instr)"
           (= (profiler-total-hits p) 4))))

;;; --------------------------------------------------------------------------
;;;  Profiler — valeurs de retour de run-with-profiler
;;; --------------------------------------------------------------------------

(deftest test-profiler-run-returns
  (let ((p (make-profiler)))
    ;; :brk sur BRK
    (multiple-value-bind (cpu2 reason)
        (run-with-profiler
         (make-cpu-from-src "
    .org $0200
    NOP
    BRK")
         p)
      (declare (ignore cpu2))
      (check "run-with-profiler — :brk sur BRK"
             (eq reason :brk)))
    ;; :step-limit quand max-steps atteint
    (multiple-value-bind (cpu2 reason)
        (run-with-profiler
         (make-cpu-from-src "
    .org $0200
loop:
    JMP loop")
         p :max-steps 10)
      (declare (ignore cpu2))
      (check "run-with-profiler — :step-limit"
             (eq reason :step-limit)))))

;;; --------------------------------------------------------------------------
;;;  Profiler — print-profile (smoke test)
;;; --------------------------------------------------------------------------

(deftest test-profiler-print
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDA #$42
    NOP
    BRK"))
         (p (make-profiler)))
    (run-with-profiler cpu p)
    ;; Recréer le CPU pour la disassembly (mémoire intacte)
    (let* ((cpu2 (make-cpu-from-src "
    .org $0200
    LDA #$42
    NOP
    BRK"))
           (out (make-string-output-stream)))
      (run-with-profiler cpu2 (make-profiler))  ; juste pour avoir cpu2 chargé
      ;; On utilise cpu pour l'affichage (mémoire chargée)
      (let ((cpu-display (make-cpu-from-src "
    .org $0200
    LDA #$42
    NOP
    BRK")))
        (run-with-profiler cpu-display p)
        (print-profile p cpu-display :stream out :top 5)
        (let ((s (get-output-stream-string out)))
          (check "print-profile — sortie non vide"
                 (> (length s) 0))
          (check "print-profile — contient 'PROFIL'"
                 (not (null (search "PROFIL" s))))
          (check "print-profile — contient '$0200'"
                 (not (null (search "$0200" s))))
          (check "print-profile — contient 'LDA'"
                 (not (null (search "LDA" s)))))))))

;;; --------------------------------------------------------------------------
;;;  Tracer — construction et reset
;;; --------------------------------------------------------------------------

(deftest test-tracer-make
  (let ((tr (make-tracer)))
    (check "make-tracer — count initial = 0"
           (= (tracer-count tr) 0))
    (check "make-tracer — total initial = 0"
           (= (tracer-total tr) 0))
    (check "make-tracer — max-size défaut = 1000"
           (= (tracer-max-size tr) 1000)))
  (let ((tr (make-tracer :max-size 50)))
    (check "make-tracer :max-size 50"
           (= (tracer-max-size tr) 50))))

(deftest test-tracer-reset
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    NOP
    BRK"))
         (tr (make-tracer)))
    (run-with-tracer cpu tr)
    (check "avant reset — count > 0"
           (> (tracer-count tr) 0))
    (tracer-reset tr)
    (check "après reset — count = 0"
           (= (tracer-count tr) 0))
    (check "après reset — total = 0"
           (= (tracer-total tr) 0))))

;;; --------------------------------------------------------------------------
;;;  Tracer — contenu des entrées
;;; --------------------------------------------------------------------------

(deftest test-tracer-single-entry
  ;; LDA #$42 à $0200 : snapshot A=0 AVANT, puis A=$42 APRÈS
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDA #$42
    BRK"))
         (tr (make-tracer)))
    (run-with-tracer cpu tr)
    (let* ((entries (tracer-entries-in-order tr))
           (e0      (aref entries 0)))  ; LDA #$42
      (check "tracer — count = 2 (LDA + BRK)"
             (= (tracer-count tr) 2))
      (check "tracer — e0.pc = $0200"
             (= (trace-entry-pc e0) #x0200))
      (check "tracer — e0.a = 0 (snapshot AVANT exécution)"
             (= (trace-entry-a e0) 0))
      (check "tracer — e0.mnemonic = \"LDA\""
             (string= (trace-entry-mnemonic e0) "LDA"))
      (check "tracer — e0.operand = \"#$42\""
             (string= (trace-entry-operand e0) "#$42"))
      (check "tracer — e0.delta-cy = 2"
             (= (trace-entry-delta-cy e0) 2)))))

(deftest test-tracer-register-snapshots
  ;; Vérifie que les registres sont capturés AVANT exécution
  ;; LDX #$10 : X=0 avant, X=$10 après
  ;; STX $20  : X=$10 avant
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDX #$10
    STX $20
    BRK"))
         (tr (make-tracer)))
    (run-with-tracer cpu tr)
    (let ((entries (tracer-entries-in-order tr)))
      (check "snapshot LDX — X avant = 0"
             (= (trace-entry-x (aref entries 0)) 0))
      (check "snapshot STX — X avant = $10"
             (= (trace-entry-x (aref entries 1)) #x10)))))

(deftest test-tracer-multiple-entries
  ;; 5 LDA + BRK → 6 entrées dans l'ordre
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDA #$01
    LDA #$02
    LDA #$03
    LDA #$04
    LDA #$05
    BRK"))
         (tr (make-tracer)))
    (run-with-tracer cpu tr)
    (check "tracer — 6 entrées (5 LDA + BRK)"
           (= (tracer-count tr) 6))
    (let ((entries (tracer-entries-in-order tr)))
      (check "tracer — ordre chronologique (pc[0] < pc[1])"
             (< (trace-entry-pc (aref entries 0))
                (trace-entry-pc (aref entries 1)))))))

;;; --------------------------------------------------------------------------
;;;  Tracer — tampon circulaire
;;; --------------------------------------------------------------------------

(deftest test-tracer-circular-buffer
  ;; max-size=3, 6 instructions exécutées → seules les 3 dernières
  ;; $0200 LDA #$01 (2 octets)
  ;; $0202 LDA #$02 (2 octets)
  ;; $0204 LDA #$03 (2 octets)
  ;; $0206 LDA #$04 (2 octets)
  ;; $0208 LDA #$05 (2 octets)
  ;; $020A BRK      (1 octet)
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDA #$01
    LDA #$02
    LDA #$03
    LDA #$04
    LDA #$05
    BRK"))
         (tr (make-tracer :max-size 3)))
    (run-with-tracer cpu tr)
    (check "circulaire — count = 3 (max-size)"
           (= (tracer-count tr) 3))
    (check "circulaire — total = 6 (toutes instructions)"
           (= (tracer-total tr) 6))
    (let ((entries (tracer-entries-in-order tr)))
      ;; Les 3 dernières : LDA #$04 ($0206), LDA #$05 ($0208), BRK ($020A)
      (check "circulaire — e[0] = LDA #$04 ($0206)"
             (= (trace-entry-pc (aref entries 0)) #x0206))
      (check "circulaire — e[1] = LDA #$05 ($0208)"
             (= (trace-entry-pc (aref entries 1)) #x0208))
      (check "circulaire — e[2] = BRK ($020A)"
             (= (trace-entry-pc (aref entries 2)) #x020A)))))

(deftest test-tracer-circular-not-full
  ;; max-size=10, 3 instructions → 3 entrées, pas de wrap
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    NOP
    NOP
    BRK"))
         (tr (make-tracer :max-size 10)))
    (run-with-tracer cpu tr)
    (check "circulaire non-plein — count = 3"
           (= (tracer-count tr) 3))
    (check "circulaire non-plein — total = 3"
           (= (tracer-total tr) 3))))

(deftest test-tracer-last-n-entries
  ;; tracer-entries-in-order avec LAST < count
  ;; $0200 LDA #$01, $0202 LDA #$02, $0204 LDA #$03, $0206 LDA #$04, $0208 BRK
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDA #$01
    LDA #$02
    LDA #$03
    LDA #$04
    BRK"))
         (tr (make-tracer :max-size 100)))
    (run-with-tracer cpu tr)
    (let ((last2 (tracer-entries-in-order tr 2)))
      (check "last 2 — longueur = 2"
             (= (length last2) 2))
      ;; Les 2 dernières : LDA #$04 ($0206), BRK ($0208)
      (check "last 2 — e[0] = LDA #$04 ($0206)"
             (= (trace-entry-pc (aref last2 0)) #x0206))
      (check "last 2 — e[1] = BRK ($0208)"
             (= (trace-entry-pc (aref last2 1)) #x0208)))))

;;; --------------------------------------------------------------------------
;;;  Tracer — cycles
;;; --------------------------------------------------------------------------

(deftest test-tracer-cycles
  ;; LDA #$00 = 2cy (imm), STA $10 = 3cy (zp), BRK = 7cy
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDA #$00
    STA $10
    BRK"))
         (tr (make-tracer)))
    (run-with-tracer cpu tr)
    (let ((entries (tracer-entries-in-order tr)))
      (check "tracer cycles — LDA #$00 = 2cy"
             (= (trace-entry-delta-cy (aref entries 0)) 2))
      (check "tracer cycles — STA $10 (zp) = 3cy"
             (= (trace-entry-delta-cy (aref entries 1)) 3))
      (check "tracer cycles — BRK = 7cy"
             (= (trace-entry-delta-cy (aref entries 2)) 7)))))

;;; --------------------------------------------------------------------------
;;;  Tracer — valeurs de retour de run-with-tracer
;;; --------------------------------------------------------------------------

(deftest test-tracer-run-returns
  (let ((tr (make-tracer :max-size 20)))
    ;; :brk sur BRK
    (multiple-value-bind (cpu2 reason)
        (run-with-tracer
         (make-cpu-from-src "
    .org $0200
    NOP
    BRK")
         tr)
      (declare (ignore cpu2))
      (check "run-with-tracer — :brk"
             (eq reason :brk)))
    ;; :step-limit quand max-steps atteint
    (multiple-value-bind (cpu2 reason)
        (run-with-tracer
         (make-cpu-from-src "
    .org $0200
loop:
    JMP loop")
         tr :max-steps 5)
      (declare (ignore cpu2))
      (check "run-with-tracer — :step-limit"
             (eq reason :step-limit))
      (check "run-with-tracer — au moins 5 entrées tracées"
             (>= (tracer-count tr) 5)))))

;;; --------------------------------------------------------------------------
;;;  Tracer — print-trace (smoke test)
;;; --------------------------------------------------------------------------

(deftest test-tracer-print
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDA #$42
    NOP
    BRK"))
         (tr (make-tracer)))
    (run-with-tracer cpu tr)
    (let ((out (make-string-output-stream)))
      (print-trace tr :stream out :last 10)
      (let ((s (get-output-stream-string out)))
        (check "print-trace — sortie non vide"
               (> (length s) 0))
        (check "print-trace — contient 'TRACE'"
               (not (null (search "TRACE" s))))
        (check "print-trace — contient '$0200'"
               (not (null (search "$0200" s))))
        (check "print-trace — contient 'LDA'"
               (not (null (search "LDA" s))))))))

;;; --------------------------------------------------------------------------
;;;  Profiler — profile-step unitaire
;;; --------------------------------------------------------------------------

(deftest test-profile-step-single
  ;; Appel direct à profile-step, une instruction à la fois
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDA #$FF
    BRK"))
         (p (make-profiler)))
    ;; Exécuter LDA #$FF manuellement
    (handler-case
        (profile-step cpu p)
      (cpu-break () nil))
    (check "profile-step — LDA exécutée (hit $0200 = 1)"
           (= (aref (profiler-hit-count p) #x0200) 1))
    (check "profile-step — 2 cycles enregistrés"
           (= (aref (profiler-cycle-count p) #x0200) 2))
    (check "profile-step — total-hits = 1"
           (= (profiler-total-hits p) 1))))

;;; --------------------------------------------------------------------------
;;;  Tracer — trace-step unitaire
;;; --------------------------------------------------------------------------

(deftest test-trace-step-single
  ;; Appel direct à trace-step, une instruction à la fois
  (let* ((cpu (make-cpu-from-src "
    .org $0200
    LDY #$77
    BRK"))
         (tr (make-tracer)))
    (handler-case
        (trace-step cpu tr)
      (cpu-break () nil))
    (check "trace-step — 1 entrée enregistrée"
           (= (tracer-count tr) 1))
    (let ((e (aref (tracer-entries-in-order tr) 0)))
      (check "trace-step — pc = $0200"
             (= (trace-entry-pc e) #x0200))
      (check "trace-step — mnemonic = LDY"
             (string= (trace-entry-mnemonic e) "LDY"))
      (check "trace-step — y AVANT = 0"
             (= (trace-entry-y e) 0)))))

;;; --------------------------------------------------------------------------
;;;  Cohérence profiler/tracer : total-hits = tracer-count sur même programme
;;; --------------------------------------------------------------------------

(deftest test-consistency-hits-trace
  (let* ((cpu-p (make-cpu-from-src "
    .org $0200
    LDA #$01
    LDA #$02
    LDA #$03
    BRK"))
         (cpu-t (make-cpu-from-src "
    .org $0200
    LDA #$01
    LDA #$02
    LDA #$03
    BRK"))
         (p  (make-profiler))
         (tr (make-tracer)))
    (run-with-profiler cpu-p p)
    (run-with-tracer   cpu-t tr)
    (check "cohérence — total-hits = tracer-count = 4"
           (= (profiler-total-hits p) (tracer-count tr)))
    (check "cohérence — valeur = 4 (3 LDA + BRK)"
           (= (profiler-total-hits p) 4))))

;;; --------------------------------------------------------------------------
;;;  Point d'entrée
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Suite : test-profiler-6502 ===~%")
  ;; Profiler
  (test-profiler-make)
  (test-profiler-reset)
  (test-profiler-hit-count-single)
  (test-profiler-hit-count-loop)
  (test-profiler-cycle-count)
  (test-profiler-cycle-accumulation)
  (test-profiler-accumulates)
  (test-profiler-run-returns)
  (test-profiler-print)
  ;; Tracer
  (test-tracer-make)
  (test-tracer-reset)
  (test-tracer-single-entry)
  (test-tracer-register-snapshots)
  (test-tracer-multiple-entries)
  (test-tracer-circular-buffer)
  (test-tracer-circular-not-full)
  (test-tracer-last-n-entries)
  (test-tracer-cycles)
  (test-tracer-run-returns)
  (test-tracer-print)
  ;; Unitaires
  (test-profile-step-single)
  (test-trace-step-single)
  ;; Cohérence
  (test-consistency-hits-trace)
  (format t "~&--- Résultat : ~D OK, ~D KO sur ~D tests ---~%"
          *pass* *fail* (+ *pass* *fail*))
  (when *failures*
    (format t "Échecs :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (values *pass* *fail*))
