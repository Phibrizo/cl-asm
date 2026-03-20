; -*- coding: utf-8 -*-
(defpackage #:cl-asm/backend.r65c02
  (:use #:cl)
  (:export
   #:assemble-r65c02 #:assemble-string-r65c02 #:assemble-file-r65c02
   #:*instructions-r65c02*))
;;; src/backend/r65c02.lisp
;;;
;;; Backend d'assemblage pour le Rockwell R65C02.
;;;
;;; Le R65C02 est la variante Rockwell du WDC 65C02. Il ajoute 32 instructions
;;; de manipulation de bits et de branchement conditionnel sur bit :
;;;
;;;   RMBn zp        Reset Memory Bit n  ($n7, 2 octets) — n = 0..7
;;;   SMBn zp        Set   Memory Bit n  ($n7, 2 octets, $n7 = n*$10+$87)
;;;   BBRn zp,rel    Branch on Bit Reset ($nF, 3 octets)
;;;   BBSn zp,rel    Branch on Bit Set   ($nF, 3 octets, $nF = n*$10+$8F)
;;;
;;; Opcode mapping :
;;;   RMB0=$07  RMB1=$17  RMB2=$27  RMB3=$37
;;;   RMB4=$47  RMB5=$57  RMB6=$67  RMB7=$77
;;;   SMB0=$87  SMB1=$97  SMB2=$A7  SMB3=$B7
;;;   SMB4=$C7  SMB5=$D7  SMB6=$E7  SMB7=$F7
;;;   BBR0=$0F  BBR1=$1F  BBR2=$2F  BBR3=$3F
;;;   BBR4=$4F  BBR5=$5F  BBR6=$6F  BBR7=$7F
;;;   BBS0=$8F  BBS1=$9F  BBS2=$AF  BBS3=$BF
;;;   BBS4=$CF  BBS5=$DF  BBS6=$EF  BBS7=$FF
;;;
;;; Ce backend hérite de cl-asm/backend.65c02 : il copie sa table
;;; d'instructions et ajoute les 32 instructions Rockwell.
;;;
;;; Les instructions RMBn/SMBn prennent un seul opérande (adresse zero-page).
;;; Les instructions BBRn/BBSn prennent deux opérandes : zp puis offset relatif.
;;; Ces deux opérandes sont séparés par une virgule dans la source.

(in-package #:cl-asm/backend.r65c02)

(declaim (ftype (function (t t t) t) process-directive-pass1-r65c02))
(declaim (ftype (function (t t t t) t) process-directive-pass2-r65c02))


;;; --------------------------------------------------------------------------
;;;  Table des instructions R65C02
;;; --------------------------------------------------------------------------

(defvar *instructions-r65c02* nil
  "Table de hachage mnémonique → liste de clauses pour le R65C02.")

(defun build-r65c02-table ()
  "Construit la table d'instructions R65C02 complète.
   Hérite de la table 65C02 et ajoute les 32 instructions Rockwell."
  (let ((tbl (make-hash-table :test #'equal)))

    ;; Copier toutes les instructions 65C02
    (maphash (lambda (k v)
               (setf (gethash k tbl) (copy-list v)))
             cl-asm/backend.65c02:*instructions-65c02*)

    ;; Ajouter les 32 instructions Rockwell
    ;; RMBn / SMBn : 1 opérande zero-page, 2 octets
    (dotimes (n 8)
      (let ((rmb (format nil "RMB~D" n))
            (smb (format nil "SMB~D" n)))
        (setf (gethash rmb tbl)
              (list (list :mode :zero-page
                          :opcode (+ (* n #x10) #x07)
                          :bytes 2)))
        (setf (gethash smb tbl)
              (list (list :mode :zero-page
                          :opcode (+ (* n #x10) #x87)
                          :bytes 2)))))

    ;; BBRn / BBSn : 2 opérandes (zp + offset relatif), 3 octets
    (dotimes (n 8)
      (let ((bbr (format nil "BBR~D" n))
            (bbs (format nil "BBS~D" n)))
        (setf (gethash bbr tbl)
              (list (list :mode :rockwell-branch
                          :opcode (+ (* n #x10) #x0F)
                          :bytes 3)))
        (setf (gethash bbs tbl)
              (list (list :mode :rockwell-branch
                          :opcode (+ (* n #x10) #x8F)
                          :bytes 3)))))

    tbl))

(setf *instructions-r65c02* (build-r65c02-table))


;;; --------------------------------------------------------------------------
;;;  Encodage des instructions R65C02
;;; --------------------------------------------------------------------------


(defun encode-rockwell-branch (instr symtable pc)
  "Encode une instruction BBRn/BBSn (mode :rockwell-branch).
   Opcode (1) + zp (1) + offset relatif (1) = 3 octets.
   Les deux opérandes sont dans la liste des opérandes de INSTR."
  (let* ((mnemonic  (cl-asm/ir:ir-instruction-mnemonic instr))
         (opcode    (cl-asm/parser:rockwell-opcode mnemonic))
         (operands  (cl-asm/ir:ir-instruction-operands instr))
         (zp-expr   (first operands))
         (rel-expr  (second operands)))
    (unless (and zp-expr rel-expr)
      (error "~A requiert deux opérandes (zp, rel)" mnemonic))
    (let* ((zp-val  (cl-asm/backend.6502:eval-operand-value zp-expr symtable pc))
           (target  (cl-asm/backend.6502:eval-operand-value rel-expr symtable pc))
           (offset  (if (and target (numberp target))
                        (let ((off (- target (+ pc 3))))
                          (when (or (< off -128) (> off 127))
                            (error "BBR/BBS offset hors plage [-128,127] : ~D" off))
                          (if (< off 0) (+ off 256) off))
                        0)))
      (values (list opcode
                    (if (and zp-val (numberp zp-val)) (logand zp-val #xFF) 0)
                    offset)
              3))))

(defun encode-rockwell-zp (instr symtable pc)
  "Encode une instruction RMBn/SMBn (mode :zero-page).
   Opcode (1) + zp (1) = 2 octets."
  (let* ((mnemonic (cl-asm/ir:ir-instruction-mnemonic instr))
         (opcode   (cl-asm/parser:rockwell-opcode mnemonic))
         (operands (cl-asm/ir:ir-instruction-operands instr))
         (zp-expr  (first operands)))
    (unless zp-expr
      (error "~A requiert un opérande (adresse zero-page)" mnemonic))
    (let* ((zp-val (cl-asm/backend.6502:eval-operand-value zp-expr symtable pc))
           (zp     (if (and zp-val (numberp zp-val)) (logand zp-val #xFF) 0)))
      (values (list opcode zp) 2))))

(defun encode-instruction-r65c02 (instr symtable pc pass)
  "Encode INSTR pour le R65C02.
   Gère les instructions Rockwell en direct, délègue les autres au 65C02."
  (let ((mnemonic (cl-asm/ir:ir-instruction-mnemonic instr)))
    (if (cl-asm/parser:rockwell-mnemonic-p mnemonic)
        (let ((prefix (subseq mnemonic 0 3)))
          (cond
            ((or (string= prefix "BBR") (string= prefix "BBS"))
             (encode-rockwell-branch instr symtable pc))
            (t
             (encode-rockwell-zp instr symtable pc))))
        ;; Déléguer au backend 65C02 avec la table R65C02
        (cl-asm/backend.6502:encode-instruction
         instr symtable pc pass
         :table      *instructions-r65c02*
         :resolve-fn #'cl-asm/backend.65c02:resolve-mode-65c02))))


;;; --------------------------------------------------------------------------
;;;  Passes d'assemblage
;;; --------------------------------------------------------------------------

(defun process-directive-pass1-r65c02 (node symtable pc)
  (cl-asm/backend.6502:process-directive-pass1 node symtable pc))

(defun process-directive-pass2-r65c02 (node symtable pc result)
  (cl-asm/backend.6502:process-directive-pass2 node symtable pc result))

(defun pass-1-r65c02 (sections symtable origin)
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
               (encode-instruction-r65c02 node symtable pc 1)
             (declare (ignore _))
             (incf pc nbytes)))
          (cl-asm/ir:ir-directive
           (setf pc (process-directive-pass1-r65c02
                     node symtable pc))))))))

(defun pass-2-r65c02 (sections symtable origin)
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
               (encode-instruction-r65c02 node symtable pc 2)
             (dolist (b bytes) (vector-push-extend b result))
             (incf pc nbytes)))
          (cl-asm/ir:ir-directive
           (setf pc (process-directive-pass2-r65c02
                     node symtable pc result))))))
    result))


;;; --------------------------------------------------------------------------
;;;  Points d'entrée publics
;;; --------------------------------------------------------------------------

(defun assemble-r65c02 (program &key (origin #x0801) (section :text))
  "Assemble PROGRAM pour le Rockwell R65C02.
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
    (pass-1-r65c02 sections symtable origin)
    (cl-asm/symbol-table:begin-pass-2 symtable)
    (setf (cl-asm/symbol-table:st-current-pc symtable) origin)
    (pass-2-r65c02 sections symtable origin)))

(defun assemble-string-r65c02 (source &key (origin #x0801))
  "Raccourci : parse SOURCE puis assemble pour le R65C02."
  (let ((program (cl-asm/parser:parse-string source)))
    (assemble-r65c02 program :origin origin)))

(defun assemble-file-r65c02 (path &key (origin #x0801))
  "Raccourci : lit, parse et assemble le fichier à PATH pour le R65C02."
  (let ((program (cl-asm/parser:parse-file path)))
    (assemble-r65c02 program :origin origin)))

(cl-asm/backends:register-backend
 :r65c02
 '("r65c02" "rockwell")
 "CL-ASM/BACKEND.R65C02" "ASSEMBLE-FILE-R65C02"
 "Rockwell R65C02"
 "Rockwell R65C02")
