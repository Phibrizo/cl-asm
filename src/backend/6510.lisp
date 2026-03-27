; -*- coding: utf-8 -*-
(defpackage #:cl-asm/backend.6510
  (:use #:cl)
  (:export
   #:assemble-6510 #:assemble-string-6510 #:assemble-file-6510
   #:*instructions-6510*))
;;; src/backend/6510.lisp
;;;
;;; Backend MOS 6510 — Commodore 64 / C128 / SX-64.
;;;
;;; Le 6510 est le processeur du C64 : un 6502 avec un port I/O intégré
;;; en $0000/$0001 et le même jeu d'opcodes non-documentés.
;;;
;;; Ce backend étend le 6502 avec les opcodes illégaux STABLES, c'est-à-dire
;;; ceux dont le comportement est déterministe sur toutes les révisions de puce
;;; et qui sont largement utilisés dans les démos et jeux C64 :
;;;
;;;   LAX  — Load A et X simultanément (6 modes)
;;;   SAX  — Store A AND X              (4 modes)
;;;   SLO  — ASL mémoire puis ORA A     (7 modes, alias ASO)
;;;   RLA  — ROL mémoire puis AND A     (7 modes)
;;;   SRE  — LSR mémoire puis EOR A     (7 modes, alias LSE)
;;;   RRA  — ROR mémoire puis ADC A     (7 modes)
;;;   DCP  — DEC mémoire puis CMP A     (7 modes, alias DCM)
;;;   ISC  — INC mémoire puis SBC A     (7 modes, alias ISB/INS)
;;;   ALR  — AND #imm puis LSR A        (1 mode,  alias ASR)
;;;   ANC  — AND #imm, bit 7 → C       (1 mode)
;;;   ARR  — AND #imm puis ROR A        (1 mode,  flags complexes)
;;;   AXS  — A AND X − #imm → X        (1 mode,  alias SBX)
;;;   LAS  — (abs,Y) AND SP → A/X/SP   (1 mode)
;;;   KIL  — gèle le CPU               (implied, opcode $02)
;;;
;;; Opcodes exclus (comportement instable selon la révision) :
;;;   XAA/ANE, AHX/SHA, TAS/SHS, SHY, SHX
;;;
;;; Référence : VICE vice.sourceforge.io/viceman.pdf, section « Undocumented »


(in-package #:cl-asm/backend.6510)


;;; --------------------------------------------------------------------------
;;;  Table des instructions 6510
;;; --------------------------------------------------------------------------

(defun build-6510-table ()
  "Construit la table d'instructions 6510 complète (6502 + illégaux stables)."
  (let ((tbl (make-hash-table :test #'equal)))

    ;; Copier toutes les instructions 6502
    (maphash (lambda (k v)
               (setf (gethash k tbl) (copy-list v)))
             cl-asm/backend.6502:*instructions*)

    (flet ((add (mn &rest clauses)
             (setf (gethash mn tbl) clauses)))

      ;; ----------------------------------------------------------------
      ;; LAX — Load A and X : LDA + TAX en une instruction
      ;; ----------------------------------------------------------------
      (add "LAX"
           '(:mode :zero-page   :opcode #xA7 :bytes 2)
           '(:mode :zero-page-y :opcode #xB7 :bytes 2)
           '(:mode :absolute    :opcode #xAF :bytes 3)
           '(:mode :absolute-y  :opcode #xBF :bytes 3)
           '(:mode :indirect-x  :opcode #xA3 :bytes 2)
           '(:mode :indirect-y  :opcode #xB3 :bytes 2))

      ;; ----------------------------------------------------------------
      ;; SAX — Store A AND X : écrit (A AND X) en mémoire, sans affecter A/X
      ;; ----------------------------------------------------------------
      (add "SAX"
           '(:mode :zero-page   :opcode #x87 :bytes 2)
           '(:mode :zero-page-y :opcode #x97 :bytes 2)
           '(:mode :absolute    :opcode #x8F :bytes 3)
           '(:mode :indirect-x  :opcode #x83 :bytes 2))

      ;; ----------------------------------------------------------------
      ;; SLO — ASL mémoire, puis ORA A avec le résultat (alias ASO)
      ;; ----------------------------------------------------------------
      (add "SLO"
           '(:mode :zero-page   :opcode #x07 :bytes 2)
           '(:mode :zero-page-x :opcode #x17 :bytes 2)
           '(:mode :absolute    :opcode #x0F :bytes 3)
           '(:mode :absolute-x  :opcode #x1F :bytes 3)
           '(:mode :absolute-y  :opcode #x1B :bytes 3)
           '(:mode :indirect-x  :opcode #x03 :bytes 2)
           '(:mode :indirect-y  :opcode #x13 :bytes 2))

      ;; ----------------------------------------------------------------
      ;; RLA — ROL mémoire, puis AND A avec le résultat
      ;; ----------------------------------------------------------------
      (add "RLA"
           '(:mode :zero-page   :opcode #x27 :bytes 2)
           '(:mode :zero-page-x :opcode #x37 :bytes 2)
           '(:mode :absolute    :opcode #x2F :bytes 3)
           '(:mode :absolute-x  :opcode #x3F :bytes 3)
           '(:mode :absolute-y  :opcode #x3B :bytes 3)
           '(:mode :indirect-x  :opcode #x23 :bytes 2)
           '(:mode :indirect-y  :opcode #x33 :bytes 2))

      ;; ----------------------------------------------------------------
      ;; SRE — LSR mémoire, puis EOR A avec le résultat (alias LSE)
      ;; ----------------------------------------------------------------
      (add "SRE"
           '(:mode :zero-page   :opcode #x47 :bytes 2)
           '(:mode :zero-page-x :opcode #x57 :bytes 2)
           '(:mode :absolute    :opcode #x4F :bytes 3)
           '(:mode :absolute-x  :opcode #x5F :bytes 3)
           '(:mode :absolute-y  :opcode #x5B :bytes 3)
           '(:mode :indirect-x  :opcode #x43 :bytes 2)
           '(:mode :indirect-y  :opcode #x53 :bytes 2))

      ;; ----------------------------------------------------------------
      ;; RRA — ROR mémoire, puis ADC A avec le résultat
      ;; ----------------------------------------------------------------
      (add "RRA"
           '(:mode :zero-page   :opcode #x67 :bytes 2)
           '(:mode :zero-page-x :opcode #x77 :bytes 2)
           '(:mode :absolute    :opcode #x6F :bytes 3)
           '(:mode :absolute-x  :opcode #x7F :bytes 3)
           '(:mode :absolute-y  :opcode #x7B :bytes 3)
           '(:mode :indirect-x  :opcode #x63 :bytes 2)
           '(:mode :indirect-y  :opcode #x73 :bytes 2))

      ;; ----------------------------------------------------------------
      ;; DCP — DEC mémoire, puis CMP A avec le résultat (alias DCM)
      ;; ----------------------------------------------------------------
      (add "DCP"
           '(:mode :zero-page   :opcode #xC7 :bytes 2)
           '(:mode :zero-page-x :opcode #xD7 :bytes 2)
           '(:mode :absolute    :opcode #xCF :bytes 3)
           '(:mode :absolute-x  :opcode #xDF :bytes 3)
           '(:mode :absolute-y  :opcode #xDB :bytes 3)
           '(:mode :indirect-x  :opcode #xC3 :bytes 2)
           '(:mode :indirect-y  :opcode #xD3 :bytes 2))

      ;; ----------------------------------------------------------------
      ;; ISC — INC mémoire, puis SBC A avec le résultat (alias ISB/INS)
      ;; ----------------------------------------------------------------
      (add "ISC"
           '(:mode :zero-page   :opcode #xE7 :bytes 2)
           '(:mode :zero-page-x :opcode #xF7 :bytes 2)
           '(:mode :absolute    :opcode #xEF :bytes 3)
           '(:mode :absolute-x  :opcode #xFF :bytes 3)
           '(:mode :absolute-y  :opcode #xFB :bytes 3)
           '(:mode :indirect-x  :opcode #xE3 :bytes 2)
           '(:mode :indirect-y  :opcode #xF3 :bytes 2))

      ;; ----------------------------------------------------------------
      ;; ALR — AND #imm puis LSR A (alias ASR)
      ;; ----------------------------------------------------------------
      (add "ALR"
           '(:mode :immediate :opcode #x4B :bytes 2))

      ;; ----------------------------------------------------------------
      ;; ANC — AND #imm, bit 7 copié dans C (comme BIT sans mémoire)
      ;; ----------------------------------------------------------------
      (add "ANC"
           '(:mode :immediate :opcode #x0B :bytes 2))

      ;; ----------------------------------------------------------------
      ;; ARR — AND #imm puis ROR A (flags C et V non-standard)
      ;; ----------------------------------------------------------------
      (add "ARR"
           '(:mode :immediate :opcode #x6B :bytes 2))

      ;; ----------------------------------------------------------------
      ;; AXS — (A AND X) − #imm → X, flags NZC mis à jour (alias SBX)
      ;; ----------------------------------------------------------------
      (add "AXS"
           '(:mode :immediate :opcode #xCB :bytes 2))

      ;; ----------------------------------------------------------------
      ;; LAS — (abs,Y) AND SP → A, X et SP simultanément
      ;; ----------------------------------------------------------------
      (add "LAS"
           '(:mode :absolute-y :opcode #xBB :bytes 3))

      ;; ----------------------------------------------------------------
      ;; KIL — gèle le CPU (JAM / HLT) ; opcode $02 comme canonique
      ;; ----------------------------------------------------------------
      (add "KIL"
           '(:mode :implied :opcode #x02 :bytes 1)))

    tbl))

(defparameter *instructions-6510*
  (build-6510-table)
  "Table des instructions 6510 (6502 + opcodes illégaux stables).")


;;; --------------------------------------------------------------------------
;;;  Encodage d'une instruction 6510
;;; --------------------------------------------------------------------------

(defun encode-instruction-6510 (instr symtable pc pass)
  "Encode INSTR pour le 6510.
   Délègue à encode-instruction du 6502 avec la table 6510."
  (cl-asm/backend.6502:encode-instruction
   instr symtable pc pass
   :table *instructions-6510*
   :resolve-fn #'cl-asm/backend.6502:resolve-mode))


;;; --------------------------------------------------------------------------
;;;  Passes d'assemblage
;;; --------------------------------------------------------------------------

(defun pass-1-6510 (sections symtable origin)
  (let ((pc origin))
    (dolist (section sections)
      (when (cl-asm/ir:ir-section-origin section)
        (setf pc (cl-asm/ir:ir-section-origin section)))
      (dolist (node (cl-asm/ir:ir-section-nodes section))
        (typecase node
          (cl-asm/ir:ir-label
           (setf (cl-asm/symbol-table:st-current-pc symtable) pc)
           (cl-asm/symbol-table:define-label
            symtable
            (cl-asm/ir:ir-label-name node)
            :source-loc (cl-asm/ir:ir-label-loc node)))
          (cl-asm/ir:ir-instruction
           (multiple-value-bind (_ nbytes)
               (encode-instruction-6510 node symtable pc 1)
             (declare (ignore _))
             (incf pc nbytes)))
          (cl-asm/ir:ir-directive
           (setf pc (cl-asm/backend.6502:process-directive-pass1
                     node symtable pc))))))))

(defun pass-2-6510 (sections symtable origin &key debug-map)
  (let ((result (make-array 0 :element-type '(unsigned-byte 8)
                              :adjustable t :fill-pointer 0))
        (pc origin))
    (dolist (section sections)
      (when (cl-asm/ir:ir-section-origin section)
        (setf pc (cl-asm/ir:ir-section-origin section)))
      (dolist (node (cl-asm/ir:ir-section-nodes section))
        (typecase node
          (cl-asm/ir:ir-label
           (setf (cl-asm/symbol-table:st-current-pc symtable) pc)
           (cl-asm/symbol-table:define-label
            symtable
            (cl-asm/ir:ir-label-name node)
            :source-loc (cl-asm/ir:ir-label-loc node)))
          (cl-asm/ir:ir-instruction
           (multiple-value-bind (bytes nbytes)
               (encode-instruction-6510 node symtable pc 2)
             (when (and debug-map (cl-asm/ir:ir-instruction-loc node))
               (cl-asm/debug-map:debug-map-set
                debug-map pc (cl-asm/ir:ir-instruction-loc node)))
             (dolist (b bytes) (vector-push-extend b result))
             (incf pc nbytes)))
          (cl-asm/ir:ir-directive
           (setf pc (cl-asm/backend.6502:process-directive-pass2
                     node symtable pc result))))))
    result))


;;; --------------------------------------------------------------------------
;;;  Points d'entrée publics
;;; --------------------------------------------------------------------------

(defun assemble-6510 (program &key (origin #x0801) (section :text) debug-map optimize)
  "Assemble PROGRAM pour le MOS 6510 / Commodore 64.
   Retourne un vecteur d'octets.
   OPTIMIZE : si non-NIL, applique l'optimiseur peephole avant la passe 1."
  (let* ((symtable (cl-asm/symbol-table:make-symbol-table))
         (sections (let ((main (cl-asm/ir:program-find-section
                                program section))
                         (rest (remove-if
                                (lambda (s)
                                  (eq (cl-asm/ir:ir-section-name s) section))
                                (cl-asm/ir:ir-program-sections program))))
                     (if main (cons main rest) rest))))
    (when optimize
      (setf sections (cl-asm/optimizer:optimize-sections sections :6510)))
    (setf (cl-asm/symbol-table:st-current-pc symtable) origin)
    (pass-1-6510 sections symtable origin)
    (cl-asm/symbol-table:begin-pass-2 symtable)
    (setf (cl-asm/symbol-table:st-current-pc symtable) origin)
    (pass-2-6510 sections symtable origin :debug-map debug-map)))

(defun assemble-string-6510 (source &key (origin #x0801) optimize)
  "Raccourci : parse SOURCE puis assemble pour le 6510."
  (let ((program (cl-asm/parser:parse-string source)))
    (assemble-6510 program :origin origin :optimize optimize)))

(defun assemble-file-6510 (path &key (origin #x0801) debug-map optimize)
  "Raccourci : lit, parse et assemble le fichier à PATH pour le 6510."
  (let ((program (cl-asm/parser:parse-file path)))
    (assemble-6510 program :origin origin :debug-map debug-map :optimize optimize)))

(cl-asm/backends:register-backend
 :6510
 '("6510" "mos6510" "c64")
 "CL-ASM/BACKEND.6510" "ASSEMBLE-FILE-6510"
 "MOS 6510 / Commodore 64"
 "MOS 6510 / Commodore 64")

(cl-asm/linker:register-linker-backend
 :6510
 '("6510" "mos6510" "c64")
 (lambda (sections symtable origin) (pass-1-6510 sections symtable origin))
 (lambda (sections symtable origin) (pass-2-6510 sections symtable origin))
 "MOS 6510 / Commodore 64")
