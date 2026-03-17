; -*- coding: utf-8 -*-
(defpackage #:cl-asm/backend.65c02
  (:use #:cl)
  (:export
   #:assemble-65c02 #:assemble-string-65c02 #:assemble-file-65c02
   #:*instructions-65c02*
   #:resolve-mode-65c02))
;;; src/backend/65c02.lisp
;;;
;;; Backend d'assemblage pour le processeur WDC 65C02.
;;; Cible principale : Commander X16.
;;;
;;; Le 65C02 est un superset du 6502 original. Ce backend etend le
;;; backend 6502 avec :
;;;
;;;   1. Nouvelles instructions
;;;      BRA rel         branche inconditionnelle relative (-128..+127)
;;;      STZ addr        store zero (zp, zp,X, abs, abs,X)
;;;      TRB addr        test and reset bits (zp, abs)
;;;      TSB addr        test and set bits  (zp, abs)
;;;      PHX / PLX       push/pull X
;;;      PHY / PLY       push/pull Y
;;;      INC A           increment accumulateur
;;;      DEC A           decrement accumulateur
;;;
;;;   2. Nouveau mode d'adressage
;;;      :zero-page-indirect   LDA ($nn)   indirect sans index (zp seulement)
;;;
;;;   3. Modes etendus pour instructions existantes
;;;      ADC/SBC/AND/ORA/EOR/CMP/LDA/STA supportent ($nn) indirect zp
;;;      JMP ($addr,X)  indirect indexe X


(in-package #:cl-asm/backend.65c02)

(declaim (ftype (function (t t t) t)
                process-directive-pass1-65c02 eval-operand-value-65c02))
(declaim (ftype (function (t t t t) t) process-directive-pass2-65c02))


;;; --------------------------------------------------------------------------
;;;  Table des instructions 65C02
;;; --------------------------------------------------------------------------

(defun build-65c02-table ()
  "Construit la table d'instructions 65C02 complete."
  (let ((tbl (make-hash-table :test #'equal)))

    ;; Copier toutes les instructions 6502
    (maphash (lambda (k v)
               (setf (gethash k tbl) (copy-list v)))
             cl-asm/backend.6502:*instructions*)

    (flet ((add (mn &rest clauses)
             "Ajoute ou remplace les clauses de MN dans la table."
             (setf (gethash mn tbl) clauses))
           (add-mode (mn &rest new-clauses)
             "Ajoute des modes supplementaires a un mnemonique existant."
             (let ((existing (gethash mn tbl)))
               (setf (gethash mn tbl)
                     (append existing new-clauses)))))

      ;; ------------------------------------------------------------------
      ;; BRA — branche inconditionnelle relative
      ;; ------------------------------------------------------------------
      (add "BRA"
           '(:mode :relative :opcode #x80 :bytes 2))

      ;; ------------------------------------------------------------------
      ;; STZ — store zero
      ;; ------------------------------------------------------------------
      (add "STZ"
           '(:mode :zero-page   :opcode #x64 :bytes 2)
           '(:mode :zero-page-x :opcode #x74 :bytes 2)
           '(:mode :absolute    :opcode #x9C :bytes 3)
           '(:mode :absolute-x  :opcode #x9E :bytes 3))

      ;; ------------------------------------------------------------------
      ;; TRB / TSB — test and reset/set bits
      ;; ------------------------------------------------------------------
      (add "TRB"
           '(:mode :zero-page :opcode #x14 :bytes 2)
           '(:mode :absolute  :opcode #x1C :bytes 3))

      (add "TSB"
           '(:mode :zero-page :opcode #x04 :bytes 2)
           '(:mode :absolute  :opcode #x0C :bytes 3))

      ;; ------------------------------------------------------------------
      ;; PHX / PLX / PHY / PLY — push/pull X et Y
      ;; ------------------------------------------------------------------
      (add "PHX" '(:mode :implied :opcode #xDA :bytes 1))
      (add "PLX" '(:mode :implied :opcode #xFA :bytes 1))
      (add "PHY" '(:mode :implied :opcode #x5A :bytes 1))
      (add "PLY" '(:mode :implied :opcode #x7A :bytes 1))

      ;; ------------------------------------------------------------------
      ;; INC A / DEC A — increment/decrement accumulateur
      ;; ------------------------------------------------------------------
      (add-mode "INC"
                '(:mode :accumulator :opcode #x1A :bytes 1))
      (add-mode "DEC"
                '(:mode :accumulator :opcode #x3A :bytes 1))

      ;; ------------------------------------------------------------------
      ;; Mode :zero-page-indirect — ($nn) sans index
      ;; Ajoute ce mode pour les instructions ALU et memoire
      ;; ------------------------------------------------------------------
      (dolist (pair '(("LDA" . #xB2) ("STA" . #x92)
                      ("ADC" . #x72) ("SBC" . #xF2)
                      ("AND" . #x32) ("ORA" . #x12)
                      ("EOR" . #x52) ("CMP" . #xD2)))
        (add-mode (car pair)
                  `(:mode :zero-page-indirect :opcode ,(cdr pair) :bytes 2)))

      ;; ------------------------------------------------------------------
      ;; JMP ($addr,X) — indirect indexe X absolu (nouveaute 65C02)
      ;; Mode distinct de :indirect-x (ZP) pour encoder sur 3 octets
      ;; ------------------------------------------------------------------
      (add-mode "JMP"
                '(:mode :indirect-absolute-x :opcode #x7C :bytes 3))

      ;; ------------------------------------------------------------------
      ;; BIT avec modes immediat et indexe (nouveautes 65C02)
      ;; ------------------------------------------------------------------
      (add-mode "BIT"
                '(:mode :immediate   :opcode #x89 :bytes 2)
                '(:mode :zero-page-x :opcode #x34 :bytes 2)
                '(:mode :absolute-x  :opcode #x3C :bytes 3)))

    tbl))

(defparameter *instructions-65c02*
  (build-65c02-table)
  "Table des instructions 65C02 (6502 + extensions WDC).")


;;; --------------------------------------------------------------------------
;;;  Resolution du mode :zero-page-indirect
;;; --------------------------------------------------------------------------

(defun resolve-mode-65c02 (operand addr-value)
  "Resout le mode d'adressage 65C02 pour OPERAND avec la valeur ADDR-VALUE.
   Etend resolve-mode du 6502 avec le mode :zero-page-indirect."
  (when (null operand)
    (return-from resolve-mode-65c02 :implied))
  (let ((kind      (cl-asm/ir:ir-operand-kind operand))
        (index-reg (cl-asm/ir:ir-operand-index-reg operand))
        (size-hint (cl-asm/ir:ir-operand-size-hint operand)))
    (cond
      ;; (:indirect val,X) avec valeur > 255 -> :indirect-absolute-x
      ;; (JMP ($1234,X) du 65C02 — 3 octets)
      ((cl:and (eq kind :indirect-x)
               (integerp addr-value)
               (> addr-value 255))
       :indirect-absolute-x)
      ;; (:indirect val) sans index et valeur ZP -> :zero-page-indirect
      ((cl:and (eq kind :indirect)
               (null index-reg)
               (or (null size-hint)
                   (eq size-hint :byte))
               (integerp addr-value)
               (<= 0 addr-value 255))
       :zero-page-indirect)
      ;; Deleguer au resolver 6502 pour les autres modes
      (t
       (cl-asm/backend.6502:resolve-mode operand addr-value)))))


;;; --------------------------------------------------------------------------
;;;  Encodage d'une instruction 65C02
;;; --------------------------------------------------------------------------

(defun lookup-65c02 (mnemonic)
  "Cherche MNEMONIC dans la table 65C02."
  (gethash (string-upcase mnemonic) *instructions-65c02*))

(defun find-clause-65c02 (clauses mode)
  "Cherche la clause correspondant au MODE dans CLAUSES."
  (find mode clauses :key (lambda (c) (getf c :mode))))

(defun encode-instruction-65c02 (instr symtable pc pass)
  "Encode INSTR pour le 65C02.
   Delègue a encode-instruction du 6502 avec la table et le resolver 65C02."
  (cl-asm/backend.6502:encode-instruction
   instr symtable pc pass
   :table      *instructions-65c02*
   :resolve-fn #'resolve-mode-65c02))


;;; --------------------------------------------------------------------------
;;;  Passes d'assemblage
;;; --------------------------------------------------------------------------

(defun process-directive-pass1-65c02 (node symtable pc)
  (cl-asm/backend.6502:process-directive-pass1 node symtable pc))

(defun process-directive-pass2-65c02 (node symtable pc result)
  (cl-asm/backend.6502:process-directive-pass2 node symtable pc result))

(defun pass-1-65c02 (sections symtable origin)
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
               (encode-instruction-65c02 node symtable pc 1)
             (declare (ignore _))
             (incf pc nbytes)))
          (cl-asm/ir:ir-directive
           (setf pc (process-directive-pass1-65c02
                     node symtable pc))))))))

(defun pass-2-65c02 (sections symtable origin)
  (let ((pc origin)
        (result (make-array 0 :element-type '(unsigned-byte 8)
                              :adjustable t :fill-pointer 0)))
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
               (encode-instruction-65c02 node symtable pc 2)
             (dolist (b bytes) (vector-push-extend b result))
             (incf pc nbytes)))
          (cl-asm/ir:ir-directive
           (setf pc (process-directive-pass2-65c02
                     node symtable pc result))))))
    result))


;;; --------------------------------------------------------------------------
;;;  Points d'entree publics
;;; --------------------------------------------------------------------------

(defun assemble-65c02 (program &key (origin #x0801) (section :text))
  "Assemble PROGRAM pour le 65C02 / Commander X16.
   Retourne un vecteur d'octets."
  (let* ((symtable (cl-asm/symbol-table:make-symbol-table))
         (sections (let ((main (cl-asm/ir:program-find-section
                                program section))
                         (rest (remove-if
                                (lambda (s)
                                  (eq (cl-asm/ir:ir-section-name s) section))
                                (cl-asm/ir:ir-program-sections program))))
                     (if main (cons main rest) rest))))
    (setf (cl-asm/symbol-table:st-current-pc symtable) origin)
    (pass-1-65c02 sections symtable origin)
    (cl-asm/symbol-table:begin-pass-2 symtable)
    (setf (cl-asm/symbol-table:st-current-pc symtable) origin)
    (pass-2-65c02 sections symtable origin)))

(defun assemble-string-65c02 (source &key (origin #x0801))
  "Raccourci : parse SOURCE puis assemble pour le 65C02."
  (let ((program (cl-asm/parser:parse-string source)))
    (assemble-65c02 program :origin origin)))

(defun assemble-file-65c02 (path &key (origin #x0801))
  "Raccourci : lit, parse et assemble le fichier a PATH pour le 65C02."
  (let ((program (cl-asm/parser:parse-file path)))
    (assemble-65c02 program :origin origin)))
