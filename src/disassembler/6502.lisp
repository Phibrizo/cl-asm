; -*- coding: utf-8 -*-
;;; src/disassembler/6502.lisp
;;;
;;; Désassembleur MOS 6502 — jeu d'instructions officiel complet (151 opcodes).
;;;
;;; API publique :
;;;   (disasm-one mem addr)
;;;     → (values mnemonic operand-string size)
;;;     Désassemble l'instruction à ADDR dans MEM.
;;;     MEM : vecteur (simple-array (unsigned-byte 8) (*)) ou tout tableau
;;;     Retourne "???" pour un opcode illégal (size=1).
;;;
;;;   (disasm mem addr &key count)
;;;     → liste de (addr hex-string mnemonic operand-string)
;;;     Désassemble COUNT instructions consécutives depuis ADDR.
;;;
;;;   (disasm-string mem addr &key count stream)
;;;     → string (ou écrit sur STREAM)
;;;     Format : "$0200  A9 05     LDA #$05"

(defpackage #:cl-asm/disassembler.6502
  (:use #:cl)
  (:import-from #:cl-asm/disassemblers #:register-disassembler)
  (:export
   ;; Désassemblage unitaire
   #:disasm-one
   ;; Désassemblage de séquences
   #:disasm
   #:disasm-string
   #:print-disasm
   ;; Table des opcodes (utile pour les outils)
   #:*opcode-table*))

(in-package #:cl-asm/disassembler.6502)


;;; --------------------------------------------------------------------------
;;;  Taille des modes d'adressage
;;; --------------------------------------------------------------------------

(defun mode-size (mode)
  "Nombre d'octets de l'instruction (opcode inclus) pour un mode donné."
  (case mode
    ((:implied :accumulator)                                      1)
    ((:immediate :zero-page :zero-page-x :zero-page-y
      :indirect-x :indirect-y :relative)                         2)
    ((:absolute :absolute-x :absolute-y :indirect)               3)
    (t 1)))


;;; --------------------------------------------------------------------------
;;;  Table des opcodes
;;;  Chaque entrée : (mnemonic . mode)  ou  NIL pour un opcode illégal.
;;; --------------------------------------------------------------------------

(defparameter *opcode-table*
  (let ((tbl (make-array 256 :initial-element nil)))
    (dolist (e '(
      ;; opcode  mnemonic   mode
      (#x00 "BRK" :implied)
      (#x01 "ORA" :indirect-x)
      (#x05 "ORA" :zero-page)
      (#x06 "ASL" :zero-page)
      (#x08 "PHP" :implied)
      (#x09 "ORA" :immediate)
      (#x0A "ASL" :accumulator)
      (#x0D "ORA" :absolute)
      (#x0E "ASL" :absolute)
      (#x10 "BPL" :relative)
      (#x11 "ORA" :indirect-y)
      (#x15 "ORA" :zero-page-x)
      (#x16 "ASL" :zero-page-x)
      (#x18 "CLC" :implied)
      (#x19 "ORA" :absolute-y)
      (#x1D "ORA" :absolute-x)
      (#x1E "ASL" :absolute-x)
      (#x20 "JSR" :absolute)
      (#x21 "AND" :indirect-x)
      (#x24 "BIT" :zero-page)
      (#x25 "AND" :zero-page)
      (#x26 "ROL" :zero-page)
      (#x28 "PLP" :implied)
      (#x29 "AND" :immediate)
      (#x2A "ROL" :accumulator)
      (#x2C "BIT" :absolute)
      (#x2D "AND" :absolute)
      (#x2E "ROL" :absolute)
      (#x30 "BMI" :relative)
      (#x31 "AND" :indirect-y)
      (#x35 "AND" :zero-page-x)
      (#x36 "ROL" :zero-page-x)
      (#x38 "SEC" :implied)
      (#x39 "AND" :absolute-y)
      (#x3D "AND" :absolute-x)
      (#x3E "ROL" :absolute-x)
      (#x40 "RTI" :implied)
      (#x41 "EOR" :indirect-x)
      (#x45 "EOR" :zero-page)
      (#x46 "LSR" :zero-page)
      (#x48 "PHA" :implied)
      (#x49 "EOR" :immediate)
      (#x4A "LSR" :accumulator)
      (#x4C "JMP" :absolute)
      (#x4D "EOR" :absolute)
      (#x4E "LSR" :absolute)
      (#x50 "BVC" :relative)
      (#x51 "EOR" :indirect-y)
      (#x55 "EOR" :zero-page-x)
      (#x56 "LSR" :zero-page-x)
      (#x58 "CLI" :implied)
      (#x59 "EOR" :absolute-y)
      (#x5D "EOR" :absolute-x)
      (#x5E "LSR" :absolute-x)
      (#x60 "RTS" :implied)
      (#x61 "ADC" :indirect-x)
      (#x65 "ADC" :zero-page)
      (#x66 "ROR" :zero-page)
      (#x68 "PLA" :implied)
      (#x69 "ADC" :immediate)
      (#x6A "ROR" :accumulator)
      (#x6C "JMP" :indirect)
      (#x6D "ADC" :absolute)
      (#x6E "ROR" :absolute)
      (#x70 "BVS" :relative)
      (#x71 "ADC" :indirect-y)
      (#x75 "ADC" :zero-page-x)
      (#x76 "ROR" :zero-page-x)
      (#x78 "SEI" :implied)
      (#x79 "ADC" :absolute-y)
      (#x7D "ADC" :absolute-x)
      (#x7E "ROR" :absolute-x)
      (#x81 "STA" :indirect-x)
      (#x84 "STY" :zero-page)
      (#x85 "STA" :zero-page)
      (#x86 "STX" :zero-page)
      (#x88 "DEY" :implied)
      (#x8A "TXA" :implied)
      (#x8C "STY" :absolute)
      (#x8D "STA" :absolute)
      (#x8E "STX" :absolute)
      (#x90 "BCC" :relative)
      (#x91 "STA" :indirect-y)
      (#x94 "STY" :zero-page-x)
      (#x95 "STA" :zero-page-x)
      (#x96 "STX" :zero-page-y)
      (#x98 "TYA" :implied)
      (#x99 "STA" :absolute-y)
      (#x9A "TXS" :implied)
      (#x9D "STA" :absolute-x)
      (#xA0 "LDY" :immediate)
      (#xA1 "LDA" :indirect-x)
      (#xA2 "LDX" :immediate)
      (#xA4 "LDY" :zero-page)
      (#xA5 "LDA" :zero-page)
      (#xA6 "LDX" :zero-page)
      (#xA8 "TAY" :implied)
      (#xA9 "LDA" :immediate)
      (#xAA "TAX" :implied)
      (#xAC "LDY" :absolute)
      (#xAD "LDA" :absolute)
      (#xAE "LDX" :absolute)
      (#xB0 "BCS" :relative)
      (#xB1 "LDA" :indirect-y)
      (#xB4 "LDY" :zero-page-x)
      (#xB5 "LDA" :zero-page-x)
      (#xB6 "LDX" :zero-page-y)
      (#xB8 "CLV" :implied)
      (#xB9 "LDA" :absolute-y)
      (#xBA "TSX" :implied)
      (#xBC "LDY" :absolute-x)
      (#xBD "LDA" :absolute-x)
      (#xBE "LDX" :absolute-y)
      (#xC0 "CPY" :immediate)
      (#xC1 "CMP" :indirect-x)
      (#xC4 "CPY" :zero-page)
      (#xC5 "CMP" :zero-page)
      (#xC6 "DEC" :zero-page)
      (#xC8 "INY" :implied)
      (#xC9 "CMP" :immediate)
      (#xCA "DEX" :implied)
      (#xCC "CPY" :absolute)
      (#xCD "CMP" :absolute)
      (#xCE "DEC" :absolute)
      (#xD0 "BNE" :relative)
      (#xD1 "CMP" :indirect-y)
      (#xD5 "CMP" :zero-page-x)
      (#xD6 "DEC" :zero-page-x)
      (#xD8 "CLD" :implied)
      (#xD9 "CMP" :absolute-y)
      (#xDD "CMP" :absolute-x)
      (#xDE "DEC" :absolute-x)
      (#xE0 "CPX" :immediate)
      (#xE1 "SBC" :indirect-x)
      (#xE4 "CPX" :zero-page)
      (#xE5 "SBC" :zero-page)
      (#xE6 "INC" :zero-page)
      (#xE8 "INX" :implied)
      (#xE9 "SBC" :immediate)
      (#xEA "NOP" :implied)
      (#xEC "CPX" :absolute)
      (#xED "SBC" :absolute)
      (#xEE "INC" :absolute)
      (#xF0 "BEQ" :relative)
      (#xF1 "SBC" :indirect-y)
      (#xF5 "SBC" :zero-page-x)
      (#xF6 "INC" :zero-page-x)
      (#xF8 "SED" :implied)
      (#xF9 "SBC" :absolute-y)
      (#xFD "SBC" :absolute-x)
      (#xFE "INC" :absolute-x)))
      (destructuring-bind (op mn mode) e
        (setf (aref tbl op) (cons mn mode))))
    tbl)
  "Vecteur de 256 entrées (mnemonic . mode) ou NIL pour les opcodes illégaux.")


;;; --------------------------------------------------------------------------
;;;  Lecture mémoire
;;; --------------------------------------------------------------------------

(declaim (inline mem-byte))
(defun mem-byte (mem addr)
  "Lit un octet à ADDR dans MEM (vecteur ou tableau)."
  (aref mem (logand addr #xFFFF)))

(defun mem-word-le (mem addr)
  "Lit un mot 16 bits little-endian à ADDR."
  (+ (mem-byte mem addr)
     (ash (mem-byte mem (logand (1+ addr) #xFFFF)) 8)))


;;; --------------------------------------------------------------------------
;;;  Formatage de l'opérande
;;; --------------------------------------------------------------------------

(defun format-operand (mode b1 b2 addr)
  "Formate l'opérande selon le MODE.
B1 = premier octet après l'opcode, B2 = second (0 si absent).
ADDR = adresse de l'instruction (pour les branches relatives)."
  (ecase mode
    (:implied      "")
    (:accumulator  "A")
    (:immediate    (format nil "#$~2,'0X" b1))
    (:zero-page    (format nil "$~2,'0X" b1))
    (:zero-page-x  (format nil "$~2,'0X,X" b1))
    (:zero-page-y  (format nil "$~2,'0X,Y" b1))
    (:absolute     (format nil "$~4,'0X" (+ b1 (ash b2 8))))
    (:absolute-x   (format nil "$~4,'0X,X" (+ b1 (ash b2 8))))
    (:absolute-y   (format nil "$~4,'0X,Y" (+ b1 (ash b2 8))))
    (:indirect     (format nil "($~4,'0X)" (+ b1 (ash b2 8))))
    (:indirect-x   (format nil "($~2,'0X,X)" b1))
    (:indirect-y   (format nil "($~2,'0X),Y" b1))
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
         (entry  (aref *opcode-table* opcode)))
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
  "Désassemble COUNT instructions consécutives depuis ADDR dans MEM.
Retourne une liste de (addr hex-bytes mnemonic operand-string)."
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
Si STREAM est fourni, écrit directement dessus.
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

(register-disassembler
 :6502
 '("6502" "mos6502")
 "CL-ASM/DISASSEMBLER.6502" "DISASM-ONE"
 "MOS 6502")
