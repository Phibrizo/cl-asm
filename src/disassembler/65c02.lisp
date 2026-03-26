; -*- coding: utf-8 -*-
;;; src/disassembler/65c02.lisp
;;;
;;; Désassembleur WDC 65C02 — Commander X16.
;;;
;;; API publique :
;;;   (disasm-one mem addr) → (values mnemonic operand-string size)
;;;   (disasm mem addr &key count) → liste de (addr hex mnemonic operand)
;;;   (disasm-string mem addr &key count stream) → string
;;;   (print-disasm mem addr &key count stream)
;;;
;;; Extensions par rapport au 6502 :
;;;   Nouveaux modes : :zero-page-indirect ($nn)  — LDA ($nn), STA ($nn)…
;;;                    :indirect-absolute-x ($nnnn,X) — JMP ($nnnn,X)
;;;   Nouvelles instructions : BRA, STZ, TRB, TSB,
;;;                            PHX/PLX/PHY/PLY, INC A, DEC A,
;;;                            BIT #imm / BIT zp,X / BIT abs,X,
;;;                            LDA/STA/ADC/SBC/AND/ORA/EOR/CMP ($nn)

(defpackage #:cl-asm/disassembler.65c02
  (:use #:cl)
  (:import-from #:cl-asm/disassemblers #:register-disassembler)
  (:export
   #:disasm-one
   #:disasm
   #:disasm-string
   #:print-disasm
   #:*opcode-table-65c02*))

(in-package #:cl-asm/disassembler.65c02)


;;; --------------------------------------------------------------------------
;;;  Lecture mémoire
;;; --------------------------------------------------------------------------

(declaim (inline mem-byte))
(defun mem-byte (mem addr)
  (aref mem (logand addr #xFFFF)))


;;; --------------------------------------------------------------------------
;;;  Table des opcodes 65C02
;;;
;;;  On part de la table 6502 et on ajoute/remplace les opcodes 65C02.
;;; --------------------------------------------------------------------------

(defparameter *opcode-table-65c02*
  (let ((tbl (copy-seq cl-asm/disassembler.6502:*opcode-table*)))
    (dolist (e '(
      ;; BRA — branche inconditionnelle
      (#x80 "BRA" :relative)
      ;; STZ — store zero
      (#x64 "STZ" :zero-page)
      (#x74 "STZ" :zero-page-x)
      (#x9C "STZ" :absolute)
      (#x9E "STZ" :absolute-x)
      ;; TRB / TSB
      (#x14 "TRB" :zero-page)
      (#x1C "TRB" :absolute)
      (#x04 "TSB" :zero-page)
      (#x0C "TSB" :absolute)
      ;; PHX / PLX / PHY / PLY
      (#xDA "PHX" :implied)
      (#xFA "PLX" :implied)
      (#x5A "PHY" :implied)
      (#x7A "PLY" :implied)
      ;; INC A / DEC A
      (#x1A "INC" :accumulator)
      (#x3A "DEC" :accumulator)
      ;; LDA/STA/ADC/SBC/AND/ORA/EOR/CMP ($nn) — zero-page-indirect
      (#xB2 "LDA" :zero-page-indirect)
      (#x92 "STA" :zero-page-indirect)
      (#x72 "ADC" :zero-page-indirect)
      (#xF2 "SBC" :zero-page-indirect)
      (#x32 "AND" :zero-page-indirect)
      (#x12 "ORA" :zero-page-indirect)
      (#x52 "EOR" :zero-page-indirect)
      (#xD2 "CMP" :zero-page-indirect)
      ;; JMP ($addr,X) — indirect-absolute-x
      (#x7C "JMP" :indirect-absolute-x)
      ;; BIT : modes supplémentaires
      (#x89 "BIT" :immediate)
      (#x34 "BIT" :zero-page-x)
      (#x3C "BIT" :absolute-x)))
    (destructuring-bind (op mn mode) e
      (setf (aref tbl op) (cons mn mode))))
    tbl)
  "Vecteur de 256 entrées (mnemonic . mode) pour le 65C02.")


;;; --------------------------------------------------------------------------
;;;  Taille des instructions
;;; --------------------------------------------------------------------------

(defun mode-size (mode)
  "Taille totale de l'instruction (opcode + opérande) en octets."
  (case mode
    ((:implied :accumulator)                                        1)
    ((:immediate :zero-page :zero-page-x :zero-page-y
      :indirect-x :indirect-y :zero-page-indirect :relative)       2)
    ((:absolute :absolute-x :absolute-y :indirect
      :indirect-absolute-x)                                        3)
    (t 1)))


;;; --------------------------------------------------------------------------
;;;  Formatage des opérandes
;;; --------------------------------------------------------------------------

(defun format-operand (mode b1 b2 addr)
  "Formate l'opérande selon MODE."
  (ecase mode
    (:implied              "")
    (:accumulator          "A")
    (:immediate            (format nil "#$~2,'0X" b1))
    (:zero-page            (format nil "$~2,'0X" b1))
    (:zero-page-x          (format nil "$~2,'0X,X" b1))
    (:zero-page-y          (format nil "$~2,'0X,Y" b1))
    (:zero-page-indirect   (format nil "($~2,'0X)" b1))
    (:absolute             (format nil "$~4,'0X" (+ b1 (ash b2 8))))
    (:absolute-x           (format nil "$~4,'0X,X" (+ b1 (ash b2 8))))
    (:absolute-y           (format nil "$~4,'0X,Y" (+ b1 (ash b2 8))))
    (:indirect             (format nil "($~4,'0X)" (+ b1 (ash b2 8))))
    (:indirect-x           (format nil "($~2,'0X,X)" b1))
    (:indirect-y           (format nil "($~2,'0X),Y" b1))
    (:indirect-absolute-x  (format nil "($~4,'0X,X)" (+ b1 (ash b2 8))))
    (:relative
     (let* ((off    (if (logbitp 7 b1) (- b1 256) b1))
            (target (logand (+ addr 2 off) #xFFFF)))
       (format nil "$~4,'0X" target)))))


;;; --------------------------------------------------------------------------
;;;  Désassemblage unitaire
;;; --------------------------------------------------------------------------

(defun disasm-one (mem addr)
  "Désassemble l'instruction à ADDR dans MEM.
Retourne (values mnemonic operand-string size).
Pour un opcode illégal : (values \"???\" \"\" 1)."
  (let* ((opcode (mem-byte mem addr))
         (entry  (aref *opcode-table-65c02* opcode)))
    (if (null entry)
        (values "???" "" 1)
        (let* ((mn   (car entry))
               (mode (cdr entry))
               (size (mode-size mode))
               (b1   (if (> size 1) (mem-byte mem (logand (+ addr 1) #xFFFF)) 0))
               (b2   (if (> size 2) (mem-byte mem (logand (+ addr 2) #xFFFF)) 0))
               (op   (format-operand mode b1 b2 addr)))
          (values mn op size)))))


;;; --------------------------------------------------------------------------
;;;  Désassemblage de séquences
;;; --------------------------------------------------------------------------

(defun disasm (mem addr &key (count 10))
  "Désassemble COUNT instructions consécutives depuis ADDR."
  (let ((result '())
        (pc addr))
    (dotimes (_ count)
      (multiple-value-bind (mn op size) (disasm-one mem pc)
        (let ((hex (with-output-to-string (s)
                     (dotimes (i size)
                       (when (> i 0) (write-char #\Space s))
                       (format s "~2,'0X" (mem-byte mem (logand (+ pc i) #xFFFF)))))))
          (push (list pc hex mn op) result))
        (setf pc (logand (+ pc size) #xFFFF))))
    (nreverse result)))

(defun disasm-string (mem addr &key (count 10) stream)
  "Désassemble COUNT instructions et retourne une string formatée.
Format : \"$0200  A9 05     LDA #$05\""
  (let ((lines (disasm mem addr :count count)))
    (with-output-to-string (s)
      (dolist (line lines)
        (destructuring-bind (pc hex mn op) line
          (format s "$~4,'0X  ~8A  ~A~@[ ~A~]~%" pc hex mn (if (string= op "") nil op))))
      (when stream
        (write-string (get-output-stream-string s) stream)))))

(defun print-disasm (mem addr &key (count 10) (stream *standard-output*))
  "Désassemble COUNT instructions et affiche sur STREAM."
  (dolist (line (disasm mem addr :count count))
    (destructuring-bind (pc hex mn op) line
      (format stream "$~4,'0X  ~8A  ~A~@[ ~A~]~%" pc hex mn (if (string= op "") nil op)))))


;;; --------------------------------------------------------------------------
;;;  Enregistrement dans le registre
;;; --------------------------------------------------------------------------

(register-disassembler
 :65c02
 '("65c02" "x16" "commander-x16")
 "CL-ASM/DISASSEMBLER.65C02" "DISASM-ONE"
 "WDC 65C02 / Commander X16")
