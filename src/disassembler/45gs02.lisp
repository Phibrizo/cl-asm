; -*- coding: utf-8 -*-
;;; src/disassembler/45gs02.lisp
;;;
;;; Désassembleur Mega65 (45GS02) — superset du MOS 6502.
;;;
;;; API publique (identique au désassembleur 6502) :
;;;   (disasm-one mem addr) → (values mnemonic operand-string size)
;;;   (disasm mem addr &key count) → liste de (addr hex mnemonic operand)
;;;   (disasm-string mem addr &key count stream) → string
;;;   (print-disasm mem addr &key count stream)
;;;
;;; Gestion des préfixes :
;;;   $EA <opcode>           — indirect-32       : LDA [$zp]
;;;   $42 <branch-opcode>    — branche longue    : LBCC/LBCS/LBEQ/LBNE/…
;;;   $42 $42 <opcode>       — registre Q 32 bits: LDQ/STQ/ADCQ/…
;;;   $42 $42 $EA <opcode>   — Q indirect-32     : LDQ [$zp] / STQ [$zp]
;;;
;;; Ambiguïtés de décodage :
;;;   $42 seul (sans opcode connu en second byte) → NEG A (1 octet)
;;;   $EA seul (sans opcode indirect-y connu)     → EOM  (1 octet, comme NOP)

(defpackage #:cl-asm/disassembler.45gs02
  (:use #:cl)
  (:import-from #:cl-asm/disassemblers #:register-disassembler)
  (:export
   #:disasm-one
   #:disasm
   #:disasm-string
   #:print-disasm
   #:*opcode-table-45gs02*))

(in-package #:cl-asm/disassembler.45gs02)


;;; --------------------------------------------------------------------------
;;;  Lecture mémoire
;;; --------------------------------------------------------------------------

(declaim (inline mem-byte))
(defun mem-byte (mem addr)
  (aref mem (logand addr #xFFFF)))


;;; --------------------------------------------------------------------------
;;;  Table de base 45GS02 (non-préfixée)
;;;
;;;  On part de la table 6502 et on ajoute/remplace les opcodes 45GS02 purs.
;;; --------------------------------------------------------------------------

(defparameter *opcode-table-45gs02*
  (let ((tbl (copy-seq cl-asm/disassembler.6502:*opcode-table*)))
    (dolist (e '(
      ;; NEG A — $42 est aussi un préfixe, géré par le dispatcher
      (#x42 "NEG" :accumulator)
      ;; ASR
      (#x43 "ASR" :accumulator)
      (#x44 "ASR" :zero-page)
      (#x54 "ASR" :zero-page-x)
      ;; Registre Z
      (#xA3 "LDZ" :immediate)
      (#xAB "LDZ" :absolute)
      (#xBB "LDZ" :absolute-x)
      ;; STZ sur 45GS02 stocke le registre Z (différent du STZ 65C02 qui stocke 0)
      (#x84 "STZ" :zero-page)      ; override STY zp
      (#x94 "STZ" :zero-page-x)    ; override STY zp,x
      (#x9C "STZ" :absolute)
      (#x9E "STZ" :absolute-x)
      (#x1B "INZ" :implied)
      (#x3B "DEZ" :implied)
      (#xDB "PHZ" :implied)
      (#xFB "PLZ" :implied)
      (#x4B "TAZ" :implied)
      (#x6B "TZA" :implied)
      (#xCB "TBA" :implied)
      (#x5B "TAB" :implied)
      ;; Instructions mémoire 16 bits
      (#xE3 "INW" :zero-page)
      (#xC3 "DEW" :zero-page)
      (#xEB "ROW" :absolute)
      ;; Divers
      (#x5C "MAP" :implied)
      (#xEA "EOM" :implied)        ; override NOP ; aussi préfixe $EA pour indirect-32
      (#x0B "TSY" :implied)
      (#x2B "TYS" :implied)))
    (destructuring-bind (op mn mode) e
      (setf (aref tbl op) (cons mn mode))))
    tbl)
  "Table des opcodes 45GS02 non-préfixés (256 entrées, NIL = illégal).")


;;; --------------------------------------------------------------------------
;;;  Tables de préfixes
;;; --------------------------------------------------------------------------

(defparameter *prefix-ea-table*
  ;; $EA <opcode> → instruction en mode indirect-32 (LDA [$zp] etc.)
  ;; L'opcode après $EA est l'opcode indirect-y de l'instruction concernée.
  (let ((tbl (make-array 256 :initial-element nil)))
    (dolist (e '((#xB1 "LDA") (#x91 "STA") (#x71 "ADC") (#xF1 "SBC")
                 (#xD1 "CMP") (#x31 "AND") (#x11 "ORA") (#x51 "EOR")))
      (destructuring-bind (op mn) e
        (setf (aref tbl op) mn)))
    tbl)
  "Table : opcode → mnémonique pour le mode indirect-32 ($EA <op> zp).")

(defparameter *prefix-42-table*
  ;; $42 <opcode> → branche longue 16 bits (LBCC, LBCS, …)
  (let ((tbl (make-array 256 :initial-element nil)))
    (dolist (e '((#x90 "LBCC") (#xB0 "LBCS") (#xF0 "LBEQ") (#xD0 "LBNE")
                 (#x30 "LBMI") (#x10 "LBPL") (#x50 "LBVC") (#x70 "LBVS")))
      (destructuring-bind (op mn) e
        (setf (aref tbl op) mn)))
    tbl)
  "Table : opcode → mnémonique pour les branches longues ($42 <op> lo hi).")

(defparameter *prefix-42-42-table*
  ;; $42 $42 <opcode> → instruction Q 32 bits
  ;; Chaque entrée : (mnémonique . mode)
  (let ((tbl (make-array 256 :initial-element nil)))
    (dolist (e '(
      (#xB2 "LDQ"  :indirect-z)  (#xA5 "LDQ"  :zero-page)  (#xAD "LDQ"  :absolute)
      (#x92 "STQ"  :indirect-z)  (#x85 "STQ"  :zero-page)  (#x8D "STQ"  :absolute)
      (#x72 "ADCQ" :indirect-z)  (#x65 "ADCQ" :zero-page)
      (#xF2 "SBCQ" :indirect-z)  (#xE5 "SBCQ" :zero-page)
      (#x32 "ANDQ" :indirect-z)  (#x25 "ANDQ" :zero-page)
      (#x12 "ORAQ" :indirect-z)  (#x05 "ORAQ" :zero-page)
      (#x52 "EORQ" :indirect-z)  (#x45 "EORQ" :zero-page)
      (#x0A "ASLQ" :accumulator) (#x06 "ASLQ" :zero-page)
      (#x4A "LSRQ" :accumulator) (#x46 "LSRQ" :zero-page)
      (#x2A "ROLQ" :accumulator) (#x26 "ROLQ" :zero-page)
      (#x6A "RORQ" :accumulator) (#x66 "RORQ" :zero-page)
      (#x43 "ASRQ" :accumulator) (#x44 "ASRQ" :zero-page)
      (#x24 "BITQ" :zero-page)
      (#xD2 "CMPQ" :indirect-z)  (#xC5 "CMPQ" :zero-page)))
    (destructuring-bind (op mn mode) e
      (setf (aref tbl op) (cons mn mode))))
    tbl)
  "Table : opcode → (mnémonique . mode) pour les instructions Q ($42 $42 <op>).")

(defparameter *prefix-42-42-ea-table*
  ;; $42 $42 $EA <opcode> → instruction Q en mode indirect-32
  (let ((tbl (make-array 256 :initial-element nil)))
    (dolist (e '((#xB2 "LDQ") (#x92 "STQ")))
      (destructuring-bind (op mn) e
        (setf (aref tbl op) mn)))
    tbl)
  "Table : opcode → mnémonique pour Q indirect-32 ($42 $42 $EA <op> zp).")


;;; --------------------------------------------------------------------------
;;;  Taille des modes (octets opérande — sans l'opcode ni les préfixes)
;;; --------------------------------------------------------------------------

(defun operand-size (mode)
  "Nombre d'octets d'opérande après l'opcode (sans les préfixes)."
  (case mode
    ((:implied :accumulator)                                     0)
    ((:immediate :zero-page :zero-page-x :zero-page-y :zero-page-z
      :indirect-x :indirect-y :indirect-z :relative)            1)
    ((:absolute :absolute-x :absolute-y :absolute-z :indirect)  2)
    (t 0)))

(defun mode-size (mode)
  "Taille totale de l'instruction (opcode+opérande, sans préfixes)."
  (1+ (operand-size mode)))


;;; --------------------------------------------------------------------------
;;;  Formatage des opérandes
;;; --------------------------------------------------------------------------

(defun format-operand-45 (mode b1 b2 &optional (addr 0))
  "Formate l'opérande selon MODE.
B1 = premier octet après l'opcode, B2 = second (0 si absent).
ADDR = adresse de l'instruction complète (pour les branches relatives)."
  (ecase mode
    (:implied      "")
    (:accumulator  "A")
    (:immediate    (format nil "#$~2,'0X" b1))
    (:zero-page    (format nil "$~2,'0X" b1))
    (:zero-page-x  (format nil "$~2,'0X,X" b1))
    (:zero-page-y  (format nil "$~2,'0X,Y" b1))
    (:zero-page-z  (format nil "$~2,'0X,Z" b1))
    (:absolute     (format nil "$~4,'0X" (+ b1 (ash b2 8))))
    (:absolute-x   (format nil "$~4,'0X,X" (+ b1 (ash b2 8))))
    (:absolute-y   (format nil "$~4,'0X,Y" (+ b1 (ash b2 8))))
    (:absolute-z   (format nil "$~4,'0X,Z" (+ b1 (ash b2 8))))
    (:indirect     (format nil "($~4,'0X)" (+ b1 (ash b2 8))))
    (:indirect-x   (format nil "($~2,'0X,X)" b1))
    (:indirect-y   (format nil "($~2,'0X),Y" b1))
    (:indirect-z   (format nil "($~2,'0X),Z" b1))
    (:relative
     (let* ((off    (if (logbitp 7 b1) (- b1 256) b1))
            (target (logand (+ addr 2 off) #xFFFF)))
       (format nil "$~4,'0X" target)))))


;;; --------------------------------------------------------------------------
;;;  Désassemblage unitaire
;;; --------------------------------------------------------------------------

(defun disasm-one (mem addr)
  "Désassemble l'instruction à ADDR dans MEM (vecteur d'octets).
Retourne (values mnemonic operand-string size).
Gère les préfixes $EA, $42, $42 $42, $42 $42 $EA.
Pour un opcode illégal ou non reconnu : (values \"???\" \"\" 1)."
  (let* ((b0 (mem-byte mem addr)))
    (cond

      ;; ------------------------------------------------------------------
      ;;  Préfixe $42 : long branch OU préfixe Q ($42 $42)
      ;; ------------------------------------------------------------------
      ((= b0 #x42)
       (let* ((b1 (mem-byte mem (logand (+ addr 1) #xFFFF))))
         (cond

           ;; $42 $42 — préfixe instructions Q
           ((= b1 #x42)
            (let* ((b2 (mem-byte mem (logand (+ addr 2) #xFFFF))))
              (cond

                ;; $42 $42 $EA — Q indirect-32 : LDQ [$zp] / STQ [$zp]
                ((= b2 #xEA)
                 (let* ((b3    (mem-byte mem (logand (+ addr 3) #xFFFF)))
                        (entry (aref *prefix-42-42-ea-table* b3)))
                   (if entry
                       (let* ((b4 (mem-byte mem (logand (+ addr 4) #xFFFF)))
                              (op (format nil "[$~2,'0X]" b4)))
                         ;; taille : $42 $42 $EA opcode zp = 5 octets
                         (values entry op 5))
                       (values "???" "" 1))))

                ;; $42 $42 <opcode> — instruction Q normale
                (t
                 (let ((entry (aref *prefix-42-42-table* b2)))
                   (if entry
                       (let* ((mn      (car entry))
                              (mode    (cdr entry))
                              (op-sz   (operand-size mode))
                              (b3      (if (> op-sz 0)
                                           (mem-byte mem (logand (+ addr 3) #xFFFF)) 0))
                              (b4      (if (> op-sz 1)
                                           (mem-byte mem (logand (+ addr 4) #xFFFF)) 0))
                              (op      (format-operand-45 mode b3 b4))
                              ;; taille : 2 (préfixes) + 1 (opcode) + opérandes
                              (total   (+ 3 op-sz)))
                         (values mn op total))
                       (values "???" "" 1)))))))

           ;; $42 <branch-opcode> — branche longue 16 bits
           ((aref *prefix-42-table* b1)
            (let* ((mn  (aref *prefix-42-table* b1))
                   (b2  (mem-byte mem (logand (+ addr 2) #xFFFF)))
                   (b3  (mem-byte mem (logand (+ addr 3) #xFFFF)))
                   (off (let ((o (+ b2 (ash b3 8))))
                          (if (>= o 32768) (- o 65536) o)))
                   ;; l'offset est relatif à PC+4 (instruction suivante)
                   (target (logand (+ addr 4 off) #xFFFF))
                   (op    (format nil "$~4,'0X" target)))
              ;; taille : $42 + opcode-branche + lo + hi = 4 octets
              (values mn op 4)))

           ;; $42 seul (second byte non reconnu) — NEG A (1 octet)
           (t
            (values "NEG" "A" 1)))))

      ;; ------------------------------------------------------------------
      ;;  Préfixe $EA : indirect-32 OU EOM
      ;; ------------------------------------------------------------------
      ((= b0 #xEA)
       (let* ((b1    (mem-byte mem (logand (+ addr 1) #xFFFF)))
              (entry (aref *prefix-ea-table* b1)))
         (if entry
             ;; $EA <indirect-y-opcode> zp → LDA/STA/… [$zp]
             (let* ((b2 (mem-byte mem (logand (+ addr 2) #xFFFF)))
                    (op (format nil "[$~2,'0X]" b2)))
               ;; taille : $EA + opcode + zp = 3 octets
               (values entry op 3))
             ;; second byte non reconnu → EOM (1 octet, comme NOP)
             (values "EOM" "" 1))))

      ;; ------------------------------------------------------------------
      ;;  Opcodes non-préfixés (table 45GS02 de base)
      ;; ------------------------------------------------------------------
      (t
       (let ((entry (aref *opcode-table-45gs02* b0)))
         (if (null entry)
             (values "???" "" 1)
             (let* ((mn   (car entry))
                    (mode (cdr entry))
                    (size (mode-size mode))
                    (b1   (if (> size 1)
                               (mem-byte mem (logand (+ addr 1) #xFFFF)) 0))
                    (b2   (if (> size 2)
                               (mem-byte mem (logand (+ addr 2) #xFFFF)) 0))
                    (op   (format-operand-45 mode b1 b2 addr)))
               (values mn op size))))))))


;;; --------------------------------------------------------------------------
;;;  Désassemblage de séquences
;;; --------------------------------------------------------------------------

(defun disasm (mem addr &key (count 10))
  "Désassemble COUNT instructions consécutives depuis ADDR.
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
Format : \"$2001  42 42 A5 20  LDQ $20\""
  (let ((lines (disasm mem addr :count count)))
    (with-output-to-string (s)
      (dolist (line lines)
        (destructuring-bind (pc hex mn op) line
          (format s "$~4,'0X  ~12A  ~A~@[ ~A~]~%" pc hex mn (if (string= op "") nil op))))
      (when stream
        (write-string (get-output-stream-string s) stream)))))

(defun print-disasm (mem addr &key (count 10) (stream *standard-output*))
  "Désassemble COUNT instructions et affiche sur STREAM."
  (dolist (line (disasm mem addr :count count))
    (destructuring-bind (pc hex mn op) line
      (format stream "$~4,'0X  ~12A  ~A~@[ ~A~]~%" pc hex mn (if (string= op "") nil op)))))


;;; --------------------------------------------------------------------------
;;;  Enregistrement dans le registre des désassembleurs
;;; --------------------------------------------------------------------------

(register-disassembler
 :45gs02
 '("45gs02" "mega65")
 "CL-ASM/DISASSEMBLER.45GS02" "DISASM-ONE"
 "Mega65 (45GS02)")
