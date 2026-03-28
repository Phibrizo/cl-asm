; -*- coding: utf-8 -*-
(defpackage #:cl-asm/profiler.6502
  (:use #:cl)
  (:import-from #:cl-asm/simulator.6502
                #:cpu-pc #:cpu-a #:cpu-x #:cpu-y #:cpu-sp #:cpu-p
                #:cpu-mem #:cpu-cycles
                #:step-cpu
                #:cpu-break #:cpu-illegal-opcode
                #:cpu-step-limit #:cpu-watchpoint)
  (:import-from #:cl-asm/disassembler.6502
                #:disasm-one)
  (:export
   ;; Profiler
   #:profiler
   #:make-profiler
   #:profiler-hit-count
   #:profiler-cycle-count
   #:profiler-total-hits
   #:profiler-total-cycles
   #:profiler-reset
   #:profile-step
   #:run-with-profiler
   #:print-profile
   ;; Tracer
   #:tracer
   #:make-tracer
   #:tracer-reset
   #:tracer-count
   #:tracer-total
   #:tracer-max-size
   #:trace-step
   #:run-with-tracer
   #:print-trace
   #:tracer-entries-in-order
   ;; Entrée de trace
   #:trace-entry
   #:trace-entry-pc
   #:trace-entry-a
   #:trace-entry-x
   #:trace-entry-y
   #:trace-entry-sp
   #:trace-entry-flags
   #:trace-entry-delta-cy
   #:trace-entry-mnemonic
   #:trace-entry-operand))

;;; src/profiler/6502.lisp
;;;
;;; Profiler et tracer pour le simulateur MOS 6502.
;;;
;;; Profiler :
;;;   Collecte le nombre d'exécutions et les cycles cumulés par adresse.
;;;   Rapport trié par cycles ou hits, avec colonne % et désassemblage.
;;;
;;; Tracer :
;;;   Tampon circulaire d'entrées d'exécution (snapshot registres avant
;;;   chaque instruction + cycles consommés + mnémonique).
;;;   Taille configurable ; les plus anciennes entrées sont écrasées quand
;;;   le tampon est plein.
;;;
;;; Usage typique :
;;;
;;;   ;; Profiler
;;;   (let* ((cpu (make-cpu))
;;;          (prof (make-profiler)))
;;;     (load-program cpu bytes :origin #x0200)
;;;     (reset-cpu cpu :origin #x0200)
;;;     (run-with-profiler cpu prof)
;;;     (print-profile prof cpu))
;;;
;;;   ;; Tracer
;;;   (let* ((cpu (make-cpu))
;;;          (tr  (make-tracer :max-size 200)))
;;;     (load-program cpu bytes :origin #x0200)
;;;     (reset-cpu cpu :origin #x0200)
;;;     (run-with-tracer cpu tr)
;;;     (print-trace tr))

(in-package #:cl-asm/profiler.6502)

;;; --------------------------------------------------------------------------
;;;  Profiler
;;; --------------------------------------------------------------------------

(defstruct (profiler (:constructor %make-profiler))
  "Collecteur de statistiques par adresse (hits + cycles).
   HIT-COUNT   : vecteur 65536 fixnums — nombre d'exécutions par adresse.
   CYCLE-COUNT : vecteur 65536 fixnums — cycles cumulés par adresse.
   TOTAL-HITS, TOTAL-CYCLES : totaux globaux (mis à jour incrémentalement)."
  (hit-count    nil :type (simple-array fixnum (65536)))
  (cycle-count  nil :type (simple-array fixnum (65536)))
  (total-hits   0   :type fixnum)
  (total-cycles 0   :type fixnum))

(defun make-profiler ()
  "Crée un profiler vide (tous les compteurs à zéro)."
  (%make-profiler
   :hit-count   (make-array 65536 :element-type 'fixnum :initial-element 0)
   :cycle-count (make-array 65536 :element-type 'fixnum :initial-element 0)))

(defun profiler-reset (profiler)
  "Remet tous les compteurs à zéro."
  (fill (profiler-hit-count   profiler) 0)
  (fill (profiler-cycle-count profiler) 0)
  (setf (profiler-total-hits   profiler) 0
        (profiler-total-cycles profiler) 0)
  profiler)

(defun profile-step (cpu profiler)
  "Exécute une instruction et enregistre les statistiques dans PROFILER.
   Propage les conditions de STEP-CPU (cpu-break, cpu-illegal-opcode, etc.).
   Garantit l'enregistrement même si une condition est signalée (via handler-bind)."
  (let* ((pc       (cpu-pc cpu))
         (cy       (cpu-cycles cpu))
         (recorded nil))
    (flet ((do-record ()
             (unless recorded
               (setf recorded t)
               (let ((delta (max 0 (- (cpu-cycles cpu) cy))))
                 (incf (aref (profiler-hit-count   profiler) pc))
                 (incf (aref (profiler-cycle-count profiler) pc) delta)
                 (incf (profiler-total-hits   profiler))
                 (incf (profiler-total-cycles profiler) delta)))))
      (handler-bind
          ((cpu-break          (lambda (c) (declare (ignore c)) (do-record)))
           (cpu-illegal-opcode (lambda (c) (declare (ignore c)) (do-record))))
        (step-cpu cpu))
      (do-record)
      cpu)))

(defun run-with-profiler (cpu profiler &key (max-steps 1000000))
  "Exécute le CPU en profilant chaque instruction jusqu'à BRK ou MAX-STEPS.
   Retourne (values cpu stop-reason) :
     :brk        — BRK rencontré
     :step-limit — MAX-STEPS atteint sans BRK
     :illegal    — opcode illégal
     :watchpoint — watchpoint déclenché"
  (handler-case
      (loop repeat max-steps
            do (profile-step cpu profiler)
            finally (signal 'cpu-step-limit :cpu cpu :steps max-steps))
    (cpu-break          () (values cpu :brk))
    (cpu-illegal-opcode () (values cpu :illegal))
    (cpu-step-limit     () (values cpu :step-limit))
    (cpu-watchpoint     () (values cpu :watchpoint))))

(defun print-profile (profiler cpu
                      &key (top 20) (sort-by :cycles) (stream t))
  "Affiche le rapport de profilage.
   TOP     : nombre de lignes à afficher (défaut 20).
   SORT-BY : :cycles (défaut) ou :hits.
   CPU     : nécessaire pour le désassemblage.
   STREAM  : destination de sortie (défaut *standard-output*)."
  (let ((hc  (profiler-hit-count   profiler))
        (cc  (profiler-cycle-count profiler))
        (mem (cpu-mem cpu))
        (total-cy   (profiler-total-cycles profiler))
        (total-hits (profiler-total-hits   profiler)))
    ;; Collecter les adresses actives
    (let ((active '()))
      (loop for addr from 0 to 65535
            when (> (aref hc addr) 0)
            do (push (list addr (aref hc addr) (aref cc addr)) active))
      ;; Trier
      (let* ((key  (if (eq sort-by :hits) #'second #'third))
             (sorted (sort active #'> :key key))
             (shown  (min top (length sorted))))
        ;; En-tête
        (format stream "~&PROFIL 6502 — top ~D par ~A~%"
                shown (if (eq sort-by :hits) "hits" "cycles"))
        (format stream "Total : ~D cycles, ~D instructions~%~%"
                total-cy total-hits)
        (format stream "  ADDR   HITS   CYCLES    %CY  INSTR~%")
        (format stream "  ----   ----   ------   ----  -----~%")
        ;; Lignes
        (loop for (addr h cy) in (subseq sorted 0 shown)
              do (multiple-value-bind (mn op)
                     (disasm-one mem addr)
                   (format stream "  $~4,'0X  ~5D  ~7D  ~5,1F%  ~A~@[ ~A~]~%"
                           addr h cy
                           (if (zerop total-cy) 0.0d0
                               (* 100.0d0 (/ cy total-cy)))
                           mn op)))))))

;;; --------------------------------------------------------------------------
;;;  Tracer — tampon circulaire d'exécution
;;; --------------------------------------------------------------------------

(defstruct trace-entry
  "Snapshot de l'état CPU avant exécution d'une instruction.
   DELTA-CY : cycles consommés par cette instruction."
  (pc       0   :type (unsigned-byte 16))
  (a        0   :type (unsigned-byte 8))
  (x        0   :type (unsigned-byte 8))
  (y        0   :type (unsigned-byte 8))
  (sp       0   :type (unsigned-byte 8))
  (flags    0   :type (unsigned-byte 8))
  (delta-cy 0   :type fixnum)
  (mnemonic ""  :type string)
  (operand  nil))           ; string ou NIL

(defstruct (tracer (:constructor %make-tracer))
  "Tampon circulaire d'entrées de trace.
   ENTRIES   : vecteur de taille MAX-SIZE (circulaire).
   WRITE-POS : prochain index d'écriture (modulo MAX-SIZE).
   TOTAL     : nombre total d'entrées écrites depuis la création ou le dernier reset."
  entries
  (max-size  1000 :type (integer 1 *))
  (write-pos 0    :type fixnum)
  (total     0    :type fixnum))

(defun make-tracer (&key (max-size 1000))
  "Crée un tracer avec un tampon circulaire de MAX-SIZE entrées."
  (%make-tracer :entries   (make-array max-size :initial-element nil)
                :max-size  max-size))

(defun tracer-count (tracer)
  "Nombre d'entrées actuellement disponibles (min(total, max-size))."
  (min (tracer-total tracer) (tracer-max-size tracer)))

(defun tracer-reset (tracer)
  "Vide le tampon du tracer."
  (fill (tracer-entries tracer) nil)
  (setf (tracer-write-pos tracer) 0
        (tracer-total     tracer) 0)
  tracer)

(defun %tracer-push (tracer entry)
  "Insère une entrée dans le tampon circulaire."
  (setf (aref (tracer-entries tracer)
              (mod (tracer-write-pos tracer) (tracer-max-size tracer)))
        entry)
  (incf (tracer-write-pos tracer))
  (incf (tracer-total     tracer)))

(defun tracer-entries-in-order (tracer &optional (last most-positive-fixnum))
  "Retourne un vecteur des LAST dernières entrées dans l'ordre chronologique.
   Si LAST >= count, retourne toutes les entrées disponibles."
  (let* ((count    (min (tracer-total tracer) (tracer-max-size tracer)))
         (n        (min count last))
         (buf      (tracer-entries tracer))
         (max-size (tracer-max-size tracer))
         ;; Index du plus ancien dans le tampon circulaire
         (oldest   (if (< (tracer-total tracer) max-size)
                       0
                       (mod (tracer-write-pos tracer) max-size)))
         (skip     (- count n))
         (result   (make-array n)))
    (loop for i from 0 below n
          for j = (mod (+ oldest skip i) max-size)
          do (setf (aref result i) (aref buf j)))
    result))

(defun trace-step (cpu tracer)
  "Exécute une instruction, snapshote l'état CPU avant exécution et enregistre.
   Propage les conditions de STEP-CPU.
   Garantit l'enregistrement même si une condition est signalée."
  (let* ((pc       (cpu-pc cpu))
         (a        (cpu-a  cpu))
         (x        (cpu-x  cpu))
         (y        (cpu-y  cpu))
         (sp       (cpu-sp cpu))
         (p        (cpu-p  cpu))
         (cy       (cpu-cycles cpu))
         (recorded nil))
    (multiple-value-bind (mn op)
        (disasm-one (cpu-mem cpu) pc)
      (flet ((do-record ()
               (unless recorded
                 (setf recorded t)
                 (%tracer-push tracer
                               (make-trace-entry
                                :pc pc :a a :x x :y y :sp sp :flags p
                                :delta-cy (max 0 (- (cpu-cycles cpu) cy))
                                :mnemonic mn :operand op)))))
        (handler-bind
            ((cpu-break          (lambda (c) (declare (ignore c)) (do-record)))
             (cpu-illegal-opcode (lambda (c) (declare (ignore c)) (do-record))))
          (step-cpu cpu))
        (do-record)
        cpu))))

(defun run-with-tracer (cpu tracer &key (max-steps 1000000))
  "Exécute le CPU en traçant chaque instruction jusqu'à BRK ou MAX-STEPS.
   Retourne (values cpu stop-reason) :
     :brk        — BRK rencontré
     :step-limit — MAX-STEPS atteint sans BRK
     :illegal    — opcode illégal
     :watchpoint — watchpoint déclenché"
  (handler-case
      (loop repeat max-steps
            do (trace-step cpu tracer)
            finally (signal 'cpu-step-limit :cpu cpu :steps max-steps))
    (cpu-break          () (values cpu :brk))
    (cpu-illegal-opcode () (values cpu :illegal))
    (cpu-step-limit     () (values cpu :step-limit))
    (cpu-watchpoint     () (values cpu :watchpoint))))

(defun print-trace (tracer &key (last 50) (stream t))
  "Affiche les LAST dernières entrées du tracer dans l'ordre chronologique.
   STREAM : destination de sortie (défaut *standard-output*)."
  (let* ((entries (tracer-entries-in-order tracer last))
         (n       (length entries))
         (offset  (- (min (tracer-total tracer) (tracer-max-size tracer)) n)))
    (format stream "~&TRACE 6502 — ~D instruction~:P (~D total)~%~%"
            n (tracer-total tracer))
    (format stream "  ~5@A  ~6@A   A  X  Y  SP    P  ΔCY  INSTR~%" "#" "ADDR")
    (loop for i from 0 below n
          for e = (aref entries i)
          do (format stream "  ~5D  $~4,'0X  ~2,'0X ~2,'0X ~2,'0X  ~2,'0X  ~2,'0X  ~3D  ~A~@[ ~A~]~%"
                     (+ offset i 1)
                     (trace-entry-pc e)
                     (trace-entry-a  e)
                     (trace-entry-x  e)
                     (trace-entry-y  e)
                     (trace-entry-sp e)
                     (trace-entry-flags e)
                     (trace-entry-delta-cy e)
                     (trace-entry-mnemonic e)
                     (trace-entry-operand  e)))))
