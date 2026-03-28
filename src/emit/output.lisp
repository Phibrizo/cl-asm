; -*- coding: utf-8 -*-
(defpackage #:cl-asm/emit
  (:use #:cl)
  (:import-from #:cl-asm/disassemblers
                #:find-disassembler-by-keyword
                #:disassembler-package
                #:disassembler-function)
  (:import-from #:cl-asm/emitters
                #:register-emitter)
  (:export
   #:emit-bin #:write-bin
   #:emit-prg #:write-prg
   #:emit-listing #:write-listing
   #:*cycles-6502*
   #:*cycles-65c02*))
;;; src/emit/output.lisp
;;;
;;; Emetteurs de fichiers de sortie.
;;;
;;; Trois formats :
;;;   BIN  — binaire brut, pas de header
;;;   PRG  — format C64 : 2 octets header little-endian + binaire
;;;   LST  — listing annoté : adresse | hex | source [| cycles]
;;;
;;; Cycles CPU :
;;;   *cycles-6502*  — MOS 6502 / MOS 6510 (151 opcodes officiels)
;;;   *cycles-65c02* — WDC 65C02 / Commander X16 / 45GS02 (hérite du 6502)
;;;
;;;   Chaque entrée du vecteur : (base-cycles . extra-flag) ou NIL (opcode illégal)
;;;   extra-flag : 0 = fixe
;;;                1 = +1 cycle si page-crossing
;;;                2 = branche : +1 si prise, +2 si prise + page-crossing
;;;
;;; Listing avec cycles : passer :target (:6502 :6510 :65c02 :r65c02 :45gs02)
;;;   à emit-listing / write-listing.


(in-package #:cl-asm/emit)

(declaim (ftype (function (t) t) format-operand format-expr directive-size))
(declaim (ftype (function (t t t) t) format-directive-listing))


;;; --------------------------------------------------------------------------
;;;  BIN — binaire brut
;;; --------------------------------------------------------------------------

(defun emit-bin (bytes stream)
  "Ecrit le vecteur BYTES dans STREAM (flux binaire)."
  (write-sequence bytes stream))

(defun write-bin (bytes path)
  "Ecrit le vecteur BYTES dans le fichier a PATH."
  (with-open-file (s path
                     :direction :output
                     :element-type '(unsigned-byte 8)
                     :if-exists :supersede)
    (emit-bin bytes s))
  path)


;;; --------------------------------------------------------------------------
;;;  PRG — format C64
;;; --------------------------------------------------------------------------

(defun emit-prg (bytes stream &key (load-address #x0801))
  "Ecrit un fichier PRG C64 dans STREAM.
   Format : 2 octets little-endian (adresse de chargement) + binaire."
  (write-byte (logand load-address #xFF) stream)
  (write-byte (logand (ash load-address -8) #xFF) stream)
  (emit-bin bytes stream))

(defun write-prg (bytes path &key (load-address #x0801))
  "Ecrit un fichier PRG C64 dans le fichier a PATH."
  (with-open-file (s path
                     :direction :output
                     :element-type '(unsigned-byte 8)
                     :if-exists :supersede)
    (emit-prg bytes s :load-address load-address))
  path)


;;; --------------------------------------------------------------------------
;;;  Tables de cycles CPU
;;; --------------------------------------------------------------------------

(defparameter *cycles-6502*
  (let ((tbl (make-array 256 :initial-element nil)))
    (dolist (e '(
      ;; (opcode base-cycles extra-flag)
      ;; extra-flag : 0=fixe  1=+1 page-crossing  2=branche (+1 prise, +2 prise+page)
      (#x00  7 0)   ; BRK
      (#x01  6 0)   ; ORA (zp,X)
      (#x05  3 0)   ; ORA zp
      (#x06  5 0)   ; ASL zp
      (#x08  3 0)   ; PHP
      (#x09  2 0)   ; ORA #
      (#x0A  2 0)   ; ASL A
      (#x0D  4 0)   ; ORA abs
      (#x0E  6 0)   ; ASL abs
      (#x10  2 2)   ; BPL rel
      (#x11  5 1)   ; ORA (zp),Y
      (#x15  4 0)   ; ORA zp,X
      (#x16  6 0)   ; ASL zp,X
      (#x18  2 0)   ; CLC
      (#x19  4 1)   ; ORA abs,Y
      (#x1D  4 1)   ; ORA abs,X
      (#x1E  7 0)   ; ASL abs,X
      (#x20  6 0)   ; JSR abs
      (#x21  6 0)   ; AND (zp,X)
      (#x24  3 0)   ; BIT zp
      (#x25  3 0)   ; AND zp
      (#x26  5 0)   ; ROL zp
      (#x28  4 0)   ; PLP
      (#x29  2 0)   ; AND #
      (#x2A  2 0)   ; ROL A
      (#x2C  4 0)   ; BIT abs
      (#x2D  4 0)   ; AND abs
      (#x2E  6 0)   ; ROL abs
      (#x30  2 2)   ; BMI rel
      (#x31  5 1)   ; AND (zp),Y
      (#x35  4 0)   ; AND zp,X
      (#x36  6 0)   ; ROL zp,X
      (#x38  2 0)   ; SEC
      (#x39  4 1)   ; AND abs,Y
      (#x3D  4 1)   ; AND abs,X
      (#x3E  7 0)   ; ROL abs,X
      (#x40  6 0)   ; RTI
      (#x41  6 0)   ; EOR (zp,X)
      (#x45  3 0)   ; EOR zp
      (#x46  5 0)   ; LSR zp
      (#x48  3 0)   ; PHA
      (#x49  2 0)   ; EOR #
      (#x4A  2 0)   ; LSR A
      (#x4C  3 0)   ; JMP abs
      (#x4D  4 0)   ; EOR abs
      (#x4E  6 0)   ; LSR abs
      (#x50  2 2)   ; BVC rel
      (#x51  5 1)   ; EOR (zp),Y
      (#x55  4 0)   ; EOR zp,X
      (#x56  6 0)   ; LSR zp,X
      (#x58  2 0)   ; CLI
      (#x59  4 1)   ; EOR abs,Y
      (#x5D  4 1)   ; EOR abs,X
      (#x5E  7 0)   ; LSR abs,X
      (#x60  6 0)   ; RTS
      (#x61  6 0)   ; ADC (zp,X)
      (#x65  3 0)   ; ADC zp
      (#x66  5 0)   ; ROR zp
      (#x68  4 0)   ; PLA
      (#x69  2 0)   ; ADC #
      (#x6A  2 0)   ; ROR A
      (#x6C  5 0)   ; JMP (ind)  — bug page-crossing 6502, mais taille fixe 5cy
      (#x6D  4 0)   ; ADC abs
      (#x6E  6 0)   ; ROR abs
      (#x70  2 2)   ; BVS rel
      (#x71  5 1)   ; ADC (zp),Y
      (#x75  4 0)   ; ADC zp,X
      (#x76  6 0)   ; ROR zp,X
      (#x78  2 0)   ; SEI
      (#x79  4 1)   ; ADC abs,Y
      (#x7D  4 1)   ; ADC abs,X
      (#x7E  7 0)   ; ROR abs,X
      (#x81  6 0)   ; STA (zp,X)
      (#x84  3 0)   ; STY zp
      (#x85  3 0)   ; STA zp
      (#x86  3 0)   ; STX zp
      (#x88  2 0)   ; DEY
      (#x8A  2 0)   ; TXA
      (#x8C  4 0)   ; STY abs
      (#x8D  4 0)   ; STA abs
      (#x8E  4 0)   ; STX abs
      (#x90  2 2)   ; BCC rel
      (#x91  6 0)   ; STA (zp),Y  — toujours 6cy (pas de page-crossing penalty)
      (#x94  4 0)   ; STY zp,X
      (#x95  4 0)   ; STA zp,X
      (#x96  4 0)   ; STX zp,Y
      (#x98  2 0)   ; TYA
      (#x99  5 0)   ; STA abs,Y   — toujours 5cy (pas de page-crossing penalty)
      (#x9A  2 0)   ; TXS
      (#x9D  5 0)   ; STA abs,X   — toujours 5cy (pas de page-crossing penalty)
      (#xA0  2 0)   ; LDY #
      (#xA1  6 0)   ; LDA (zp,X)
      (#xA2  2 0)   ; LDX #
      (#xA4  3 0)   ; LDY zp
      (#xA5  3 0)   ; LDA zp
      (#xA6  3 0)   ; LDX zp
      (#xA8  2 0)   ; TAY
      (#xA9  2 0)   ; LDA #
      (#xAA  2 0)   ; TAX
      (#xAC  4 0)   ; LDY abs
      (#xAD  4 0)   ; LDA abs
      (#xAE  4 0)   ; LDX abs
      (#xB0  2 2)   ; BCS rel
      (#xB1  5 1)   ; LDA (zp),Y
      (#xB4  4 0)   ; LDY zp,X
      (#xB5  4 0)   ; LDA zp,X
      (#xB6  4 0)   ; LDX zp,Y
      (#xB8  2 0)   ; CLV
      (#xB9  4 1)   ; LDA abs,Y
      (#xBA  2 0)   ; TSX
      (#xBC  4 1)   ; LDY abs,X
      (#xBD  4 1)   ; LDA abs,X
      (#xBE  4 1)   ; LDX abs,Y
      (#xC0  2 0)   ; CPY #
      (#xC1  6 0)   ; CMP (zp,X)
      (#xC4  3 0)   ; CPY zp
      (#xC5  3 0)   ; CMP zp
      (#xC6  5 0)   ; DEC zp
      (#xC8  2 0)   ; INY
      (#xC9  2 0)   ; CMP #
      (#xCA  2 0)   ; DEX
      (#xCC  4 0)   ; CPY abs
      (#xCD  4 0)   ; CMP abs
      (#xCE  6 0)   ; DEC abs
      (#xD0  2 2)   ; BNE rel
      (#xD1  5 1)   ; CMP (zp),Y
      (#xD5  4 0)   ; CMP zp,X
      (#xD6  6 0)   ; DEC zp,X
      (#xD8  2 0)   ; CLD
      (#xD9  4 1)   ; CMP abs,Y
      (#xDD  4 1)   ; CMP abs,X
      (#xDE  7 0)   ; DEC abs,X
      (#xE0  2 0)   ; CPX #
      (#xE1  6 0)   ; SBC (zp,X)
      (#xE4  3 0)   ; CPX zp
      (#xE5  3 0)   ; SBC zp
      (#xE6  5 0)   ; INC zp
      (#xE8  2 0)   ; INX
      (#xE9  2 0)   ; SBC #
      (#xEA  2 0)   ; NOP
      (#xEC  4 0)   ; CPX abs
      (#xED  4 0)   ; SBC abs
      (#xEE  6 0)   ; INC abs
      (#xF0  2 2)   ; BEQ rel
      (#xF1  5 1)   ; SBC (zp),Y
      (#xF5  4 0)   ; SBC zp,X
      (#xF6  6 0)   ; INC zp,X
      (#xF8  2 0)   ; SED
      (#xF9  4 1)   ; SBC abs,Y
      (#xFD  4 1)   ; SBC abs,X
      (#xFE  7 0)   ; INC abs,X
    ))
      (destructuring-bind (op cy ex) e
        (setf (aref tbl op) (cons cy ex))))
    tbl)
  "Table des cycles MOS 6502 (151 opcodes officiels).
   Même table utilisée pour le MOS 6510 (C64).
   Chaque entrée : (base-cycles . extra-flag)  ou  NIL si opcode illégal.
   extra-flag : 0=fixe  1=+1 page-crossing  2=branche")

(defparameter *cycles-65c02*
  (let ((tbl (copy-seq *cycles-6502*)))
    (dolist (e '(
      ;; Nouveaux opcodes WDC 65C02 / Commander X16
      (#x04  5 0)   ; TSB zp
      (#x0C  6 0)   ; TSB abs
      (#x12  5 0)   ; ORA (zp)
      (#x14  5 0)   ; TRB zp
      (#x1A  2 0)   ; INC A
      (#x1C  6 0)   ; TRB abs
      (#x32  5 0)   ; AND (zp)
      (#x34  4 0)   ; BIT zp,X
      (#x3A  2 0)   ; DEC A
      (#x3C  4 1)   ; BIT abs,X
      (#x52  5 0)   ; EOR (zp)
      (#x5A  3 0)   ; PHY
      (#x64  3 0)   ; STZ zp
      (#x6C  6 0)   ; JMP (ind) — 6cy sur 65C02 (bug page-crossing corrigé)
      (#x72  5 0)   ; ADC (zp)
      (#x74  4 0)   ; STZ zp,X
      (#x7A  4 0)   ; PLY
      (#x7C  6 0)   ; JMP (abs,X)
      (#x80  2 2)   ; BRA rel
      (#x89  2 0)   ; BIT #
      (#x92  5 0)   ; STA (zp)
      (#x9C  4 0)   ; STZ abs
      (#x9E  5 0)   ; STZ abs,X
      (#xB2  5 0)   ; LDA (zp)
      (#xD2  5 0)   ; CMP (zp)
      (#xDA  3 0)   ; PHX
      (#xF2  5 0)   ; SBC (zp)
      (#xFA  4 0)   ; PLX
    ))
      (destructuring-bind (op cy ex) e
        (setf (aref tbl op) (cons cy ex))))
    tbl)
  "Table des cycles WDC 65C02 / Commander X16 / 45GS02 (approximatif).
   Hérite de *cycles-6502* avec ajouts et corrections.
   JMP ($nn) passe de 5cy à 6cy (bug page-crossing corrigé sur 65C02).")


;;; --------------------------------------------------------------------------
;;;  LST — listing annoté
;;; --------------------------------------------------------------------------

(defun find-cycle-table (target)
  "Retourne la table de cycles pour TARGET, ou NIL si non disponible."
  (case target
    ((:6502 :6510)             *cycles-6502*)
    ((:65c02 :r65c02 :45gs02)  *cycles-65c02*)
    (otherwise nil)))

(defun %find-disasm-entry (target)
  "Trouve l'entrée désassembleur pour TARGET.
   Applique des fallbacks pour les variantes sans désassembleur propre :
     :6510   → :6502
     :r65c02 → :65c02"
  (when target
    (or (find-disassembler-by-keyword target)
        (case target
          (:6510   (find-disassembler-by-keyword :6502))
          (:r65c02 (find-disassembler-by-keyword :65c02))))))

(defun %disasm-size (disasm-entry bytes pos)
  "Retourne la taille de l'instruction à POS dans BYTES via le désassembleur.
   Retourne 1 si le désassembleur n'est pas disponible ou si POS est hors limites."
  (if (and disasm-entry bytes (< pos (length bytes)))
      (let* ((pkg (find-package (disassembler-package disasm-entry)))
             (fn  (when pkg
                    (find-symbol (disassembler-function disasm-entry) pkg))))
        (if fn
            (or (nth-value 2 (funcall fn bytes pos)) 1)
            1))
      1))

(defun format-cycles (entry)
  "Formate les cycles pour le listing. ENTRY = (base-cycles . extra-flag)."
  (let ((base  (car entry))
        (extra (cdr entry)))
    (ecase extra
      (0 (format nil "~Dcy"  base))
      (1 (format nil "~Dcy+" base))   ; +1 si page-crossing
      (2 (format nil "~Dcy*" base)))));; branche : +1 prise, +2 prise+page

(defun emit-listing (program bytes stream &key (origin #x0801) target)
  "Génère un listing annoté dans STREAM (flux texte).
   TARGET (optionnel) : mot-clé backend (:6502 :6510 :65c02 :r65c02 :45gs02).
                        Active l'affichage des cycles CPU et corrige les tailles.
   Format de chaque ligne :
     ADDR  XX XX XX   MNEMONIC OPERANDE          Ncy[+/*]
   Exemples :
     0801  A9 00      LDA #$00                   2cy
     0803  8D 20 D0   STA $D020                  4cy
     0806  BD 00 02   LDA $0200,X                4cy+
     0809  D0 05      BNE $0810                  2cy*"
  (let* ((pc           origin)
         (byte-pos     0)
         (sections     (cl-asm/ir:ir-program-sections program))
         (disasm-entry (%find-disasm-entry target))
         (cycle-table  (find-cycle-table target)))
    (dolist (section sections)
      (when (cl-asm/ir:ir-section-origin section)
        (setf pc (cl-asm/ir:ir-section-origin section)))
      (dolist (node (cl-asm/ir:ir-section-nodes section))
        (typecase node
          (cl-asm/ir:ir-label
           (format stream "~4,'0X~20T~A:~%"
                   pc
                   (cl-asm/ir:ir-label-name node)))
          (cl-asm/ir:ir-instruction
           (let* ((mn   (cl-asm/ir:ir-instruction-mnemonic node))
                  (ops  (cl-asm/ir:ir-instruction-operands  node))
                  (sz   (%disasm-size disasm-entry bytes byte-pos))
                  (cyc  (when (and cycle-table
                                   bytes
                                   (< byte-pos (length bytes)))
                          (aref cycle-table (aref bytes byte-pos)))))
             ;; Adresse
             (format stream "~4,'0X  " pc)
             ;; Bytes hex (taille réelle via désassembleur)
             (let ((hex-str
                     (with-output-to-string (hs)
                       (loop for i from 0 below sz
                             while (< (+ byte-pos i) (length bytes))
                             do (format hs "~2,'0X " (aref bytes (+ byte-pos i)))))))
               (format stream "~12A" hex-str))
             ;; Mnémonique et opérande
             (format stream " ~A" mn)
             (when ops
               (format stream " ~A" (format-operand (first ops))))
             ;; Cycles (si table disponible pour cette cible)
             (when cyc
               (format stream "~40T~A" (format-cycles cyc)))
             (format stream "~%")
             ;; Avancer PC et position dans le binaire
             (incf pc       sz)
             (incf byte-pos sz)))
          (cl-asm/ir:ir-directive
           (format-directive-listing node stream pc)
           (let ((sz (directive-size node)))
             (incf pc       sz)
             (incf byte-pos sz))))))))

(defun format-operand (operand)
  "Formate un operande pour le listing."
  (let ((kind  (cl-asm/ir:ir-operand-kind     operand))
        (val   (cl-asm/ir:ir-operand-value     operand))
        (ireg  (cl-asm/ir:ir-operand-index-reg operand)))
    (ecase kind
      (:register   (format nil "~A" val))
      (:immediate  (format nil "#~A" (format-expr val)))
      (:direct
       (if ireg
           (format nil "~A,~A" (format-expr val) (string-upcase (symbol-name ireg)))
           (format nil "~A" (format-expr val))))
      (:indirect
       (format nil "(~A)" (format-expr val)))
      (:indirect-x
       (format nil "(~A,~A)" (format-expr val)
               (string-upcase (symbol-name ireg))))
      (:indirect-y
       (format nil "(~A),~A" (format-expr val)
               (string-upcase (symbol-name ireg)))))))

(defun format-expr (expr)
  "Formate une expression pour le listing."
  (cond
    ((integerp expr)
     (if (<= 0 expr 255)
         (format nil "$~2,'0X" expr)
         (format nil "$~4,'0X" expr)))
    ((stringp expr) expr)
    ((eq expr :*) "*")
    ((listp expr)
     (format nil "~A" expr))
    (t (format nil "~A" expr))))

(defun format-directive-listing (directive stream pc)
  "Formate une directive pour le listing."
  (let ((name (cl-asm/ir:ir-directive-name directive))
        (args (cl-asm/ir:ir-directive-args  directive)))
    (case name
      (:org
       (format stream "~4,'0X~20T.ORG $~4,'0X~%" pc (first args)))
      (:equ
       (format stream "~4,'0X~20T~A = ~A~%" pc (first args) (second args)))
      (:defenum
       (let ((enum-name (first args))
             (values    (second args)))
         (format stream "~4,'0X~20T.DEFENUM ~A~%" pc enum-name)
         (dolist (entry values)
           (format stream "~20T  ~A.~A = ~D~%"
                   enum-name (car entry) (cdr entry)))
         (format stream "~20T  ~A.COUNT = ~D~%" enum-name (length values))))
      (:incbin
       (let* ((filename  (first args))
              (offset    (or (second args) 0))
              (count-arg (third args))
              (n (handler-case
                     (with-open-file (s filename :element-type '(unsigned-byte 8))
                       (let* ((fsize (file-length s))
                              (avail (max 0 (- fsize offset))))
                         (if count-arg (min count-arg avail) avail)))
                   (file-error () 0))))
         (format stream "~4,'0X~20T.INCBIN ~S~44T; ~D byte~:P~%" pc filename n)))
      (:defstruct
       (let* ((struct-name (first args))
              (fields      (second args))
              (offset      0))
         (format stream "~4,'0X~20T.DEFSTRUCT ~A~%" pc struct-name)
         (dolist (field fields)
           (format stream "~20T  ~A.~A = ~D~%"
                   struct-name (car field) offset)
           (incf offset (cdr field)))
         (format stream "~20T  ~A.SIZE = ~D~%" struct-name offset)))
      (:pet
       (format stream "~4,'0X~20T.PETSCII ~{~S~^, ~}~%" pc args))
      (:assertsize
       (format stream "~4,'0X~20T; assert-size ~D~%" pc (first args)))
      (:byte
       (format stream "~4,'0X~20T.BYTE ~{$~2,'0X~^, ~}~%" pc args))
      (:word
       (format stream "~4,'0X~20T.WORD ~{$~4,'0X~^, ~}~%" pc args))
      (otherwise
       (format stream "~4,'0X~20T.~A ~{~A~^, ~}~%"
               pc (string-upcase (symbol-name name)) args)))))

(defun directive-size (directive)
  "Retourne la taille en octets d'une directive."
  (let ((name (cl-asm/ir:ir-directive-name directive))
        (args (cl-asm/ir:ir-directive-args  directive)))
    (case name
      ((:byte :pet)
       (reduce #'+ args
               :key (lambda (a) (if (stringp a) (length a) 1))
               :initial-value 0))
      (:word  (* 2 (length args)))
      (:dword (* 4 (length args)))
      (:incbin
       (handler-case
           (let* ((filename  (first args))
                  (offset    (or (second args) 0))
                  (count-arg (third args)))
             (with-open-file (s filename :element-type '(unsigned-byte 8))
               (let* ((fsize (file-length s))
                      (avail (max 0 (- fsize offset))))
                 (if count-arg (min count-arg avail) avail))))
         (file-error () 0)))
      (:text  (reduce #'+ args
                      :key (lambda (a) (if (stringp a) (length a) 1))
                      :initial-value 0))
      (otherwise 0))))

(defun write-listing (program bytes path &key (origin #x0801) target)
  "Ecrit un listing annoté dans le fichier a PATH.
   TARGET (optionnel) : active les cycles CPU (:6502 :6510 :65c02 :r65c02 :45gs02)."
  (with-open-file (s path
                     :direction :output
                     :if-exists :supersede)
    (emit-listing program bytes s :origin origin :target target))
  path)


;;; --------------------------------------------------------------------------
;;;  Enregistrement dans le registre des émetteurs
;;; --------------------------------------------------------------------------

(cl-asm/emitters:register-emitter
  :bin
  '("bin" "raw" "binary")
  "bin"
  (lambda (bytes path &key origin) (declare (ignore origin)) (write-bin bytes path))
  "Binaire brut (pas de header)"
  "Raw binary (no header)")

(cl-asm/emitters:register-emitter
  :prg
  '("prg" "c64")
  "prg"
  (lambda (bytes path &key (origin #x0801)) (write-prg bytes path :load-address origin))
  "PRG C64 (2 octets adresse de chargement + binaire)"
  "Commodore 64 PRG (2-byte load address + binary)")
