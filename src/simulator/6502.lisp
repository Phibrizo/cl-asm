; -*- coding: utf-8 -*-
;;; src/simulator/6502.lisp
;;;
;;; Simulateur MOS 6502 — Étape 1 : infrastructure + instructions implicites.
;;;
;;; Périmètre :
;;;   - Struct CPU : A X Y PC SP P + mémoire 64 KB
;;;   - make-cpu / reset-cpu / load-program
;;;   - mem-read / mem-write / mem-read16
;;;   - Helpers flags (lecture + écriture)
;;;   - stack-push / stack-pull
;;;   - step-cpu  (NOP BRK + 21 instructions implicites)
;;;   - run-cpu
;;;
;;; Étapes suivantes :
;;;   - Modes d'adressage + load/store (LDA LDX LDY STA STX STY)
;;;   - ALU (ADC SBC AND ORA EOR CMP CPX CPY BIT)
;;;   - Décalages / rotations (ASL LSR ROL ROR INC DEC)
;;;   - Sauts et branches (JMP JSR RTS RTI Bcc)

(defpackage #:cl-asm/simulator.6502
  (:use #:cl)
  (:export
   ;; Construction
   #:make-cpu
   #:reset-cpu
   #:load-program
   ;; Registres (lecture directe via les accesseurs de struct)
   #:cpu-a
   #:cpu-x
   #:cpu-y
   #:cpu-pc
   #:cpu-sp
   #:cpu-p
   #:cpu-mem
   #:cpu-cycles
   ;; Constantes de masque de flags
   #:+flag-c+
   #:+flag-z+
   #:+flag-i+
   #:+flag-d+
   #:+flag-b+
   #:+flag-5+
   #:+flag-v+
   #:+flag-n+
   ;; Flags individuels (lecture)
   #:flag-n
   #:flag-v
   #:flag-b
   #:flag-d
   #:flag-i
   #:flag-z
   #:flag-c
   ;; Écriture de flags
   #:set-flag
   #:update-nz
   ;; Pile
   #:stack-push
   #:stack-pull
   ;; Mémoire
   #:mem-read
   #:mem-write
   #:mem-read16
   ;; Exécution
   #:step-cpu
   #:run-cpu
   ;; Conditions
   #:cpu-break
   #:cpu-break-cpu
   #:cpu-illegal-opcode
   #:cpu-illegal-opcode-cpu
   #:cpu-illegal-opcode-opcode
   #:cpu-step-limit
   #:cpu-step-limit-cpu
   #:cpu-step-limit-steps))

(in-package #:cl-asm/simulator.6502)


;;; --------------------------------------------------------------------------
;;;  Structure CPU
;;; --------------------------------------------------------------------------
;;;
;;;  Registre P (flags) : NV-BDIZC
;;;    bit 7 : N — Negative
;;;    bit 6 : V — Overflow
;;;    bit 5 : - — (toujours 1)
;;;    bit 4 : B — Break
;;;    bit 3 : D — Decimal
;;;    bit 2 : I — Interrupt disable
;;;    bit 1 : Z — Zero
;;;    bit 0 : C — Carry
;;;
;;;  Valeur initiale P = #x24 = %00100100 : bit 5 à 1, I à 1.

(defstruct (cpu (:constructor %make-cpu) (:predicate nil))
  (a      0    :type (unsigned-byte 8))
  (x      0    :type (unsigned-byte 8))
  (y      0    :type (unsigned-byte 8))
  (pc     0    :type (unsigned-byte 16))
  (sp     #xFF :type (unsigned-byte 8))
  (p      #x24 :type (unsigned-byte 8))
  (mem    nil  :type (simple-array (unsigned-byte 8) (65536)))
  (cycles 0    :type fixnum))

(defun make-cpu ()
  "Crée un CPU 6502 avec mémoire 64 KB initialisée à zéro."
  (%make-cpu :mem (make-array 65536
                              :element-type '(unsigned-byte 8)
                              :initial-element 0)))

(defun reset-cpu (cpu &key (origin 0))
  "Remet les registres à leur état initial. Ne touche pas à la mémoire.
   PC est positionné à ORIGIN."
  (setf (cpu-a      cpu) 0
        (cpu-x      cpu) 0
        (cpu-y      cpu) 0
        (cpu-pc     cpu) origin
        (cpu-sp     cpu) #xFF
        (cpu-p      cpu) #x24
        (cpu-cycles cpu) 0)
  cpu)


;;; --------------------------------------------------------------------------
;;;  Mémoire
;;; --------------------------------------------------------------------------

(declaim (inline mem-read mem-write mem-read16))

(defun mem-read (cpu addr)
  "Lit un octet à l'adresse ADDR (modulo 64 KB)."
  (aref (cpu-mem cpu) (logand addr #xFFFF)))

(defun mem-write (cpu addr val)
  "Écrit VAL (8 bits) à l'adresse ADDR (modulo 64 KB)."
  (setf (aref (cpu-mem cpu) (logand addr #xFFFF))
        (logand val #xFF)))

(defun mem-read16 (cpu addr)
  "Lit un mot 16 bits little-endian à ADDR."
  (logior (mem-read cpu addr)
          (ash (mem-read cpu (logand (1+ addr) #xFFFF)) 8)))

(defun load-program (cpu bytes &key (origin 0))
  "Copie le vecteur BYTES dans la mémoire à partir de ORIGIN.
   Positionne PC à ORIGIN. Retourne CPU."
  (loop for i from 0 below (length bytes)
        do (mem-write cpu (+ origin i) (aref bytes i)))
  (setf (cpu-pc cpu) origin)
  cpu)


;;; --------------------------------------------------------------------------
;;;  Conditions
;;; --------------------------------------------------------------------------
;;; Placées ici, après le defstruct, pour que cpu-pc soit déjà connu.

(define-condition cpu-break (condition)
  ((cpu :initarg :cpu :reader cpu-break-cpu))
  (:report (lambda (c s)
             (format s "BRK at PC=$~4,'0X" (cpu-pc (cpu-break-cpu c))))))

(define-condition cpu-illegal-opcode (error)
  ((cpu    :initarg :cpu    :reader cpu-illegal-opcode-cpu)
   (opcode :initarg :opcode :reader cpu-illegal-opcode-opcode))
  (:report (lambda (c s)
             (format s "Illegal opcode $~2,'0X at PC=$~4,'0X"
                     (cpu-illegal-opcode-opcode c)
                     (cpu-pc (cpu-illegal-opcode-cpu c))))))

(define-condition cpu-step-limit (condition)
  ((cpu   :initarg :cpu   :reader cpu-step-limit-cpu)
   (steps :initarg :steps :reader cpu-step-limit-steps))
  (:report (lambda (c s)
             (format s "Step limit ~D reached at PC=$~4,'0X"
                     (cpu-step-limit-steps c)
                     (cpu-pc (cpu-step-limit-cpu c))))))


;;; --------------------------------------------------------------------------
;;;  Flags — constantes de masque
;;; --------------------------------------------------------------------------

(defconstant +flag-c+ #x01)   ; Carry
(defconstant +flag-z+ #x02)   ; Zero
(defconstant +flag-i+ #x04)   ; Interrupt disable
(defconstant +flag-d+ #x08)   ; Decimal
(defconstant +flag-b+ #x10)   ; Break
(defconstant +flag-5+ #x20)   ; (toujours 1)
(defconstant +flag-v+ #x40)   ; Overflow
(defconstant +flag-n+ #x80)   ; Negative


;;; --------------------------------------------------------------------------
;;;  Flags — lecture
;;; --------------------------------------------------------------------------

(declaim (inline flag-c flag-z flag-i flag-d flag-b flag-v flag-n))

(defun flag-c (cpu) (logbitp 0 (cpu-p cpu)))
(defun flag-z (cpu) (logbitp 1 (cpu-p cpu)))
(defun flag-i (cpu) (logbitp 2 (cpu-p cpu)))
(defun flag-d (cpu) (logbitp 3 (cpu-p cpu)))
(defun flag-b (cpu) (logbitp 4 (cpu-p cpu)))
(defun flag-v (cpu) (logbitp 6 (cpu-p cpu)))
(defun flag-n (cpu) (logbitp 7 (cpu-p cpu)))


;;; --------------------------------------------------------------------------
;;;  Flags — écriture
;;; --------------------------------------------------------------------------

(declaim (inline set-flag update-nz))

(defun set-flag (cpu mask set-p)
  "Met ou efface le bit MASK dans P. Conserve toujours bit 5 à 1."
  (setf (cpu-p cpu)
        (logior +flag-5+
                (if set-p
                    (logior  (cpu-p cpu) mask)
                    (logand  (cpu-p cpu) (lognot mask))))))

(defun update-nz (cpu val)
  "Met à jour N et Z d'après VAL (8 bits). Retourne VAL."
  (set-flag cpu +flag-n+ (logbitp 7 val))
  (set-flag cpu +flag-z+ (zerop val))
  val)


;;; --------------------------------------------------------------------------
;;;  Pile (page $01xx)
;;; --------------------------------------------------------------------------

(declaim (inline stack-push stack-pull))

(defun stack-push (cpu val)
  "Empile un octet : écrit à $0100+SP puis décrémente SP."
  (mem-write cpu (logior #x0100 (cpu-sp cpu)) (logand val #xFF))
  (setf (cpu-sp cpu) (logand (1- (cpu-sp cpu)) #xFF)))

(defun stack-pull (cpu)
  "Dépile un octet : incrémente SP puis lit à $0100+SP."
  (setf (cpu-sp cpu) (logand (1+ (cpu-sp cpu)) #xFF))
  (mem-read cpu (logior #x0100 (cpu-sp cpu))))


;;; --------------------------------------------------------------------------
;;;  Fetch — lecture d'opérandes au PC courant
;;; --------------------------------------------------------------------------

(declaim (inline fetch fetch16))

(defun fetch (cpu)
  "Lit l'octet au PC courant et avance PC d'un."
  (let ((b (mem-read cpu (cpu-pc cpu))))
    (setf (cpu-pc cpu) (logand (1+ (cpu-pc cpu)) #xFFFF))
    b))

(defun fetch16 (cpu)
  "Lit un mot 16 bits little-endian au PC courant et avance PC de deux."
  (let ((lo (fetch cpu))
        (hi (fetch cpu)))
    (logior lo (ash hi 8))))


;;; --------------------------------------------------------------------------
;;;  Modes d'adressage — calcul d'adresse effective
;;;
;;;  Les fonctions *-cross renvoient (values addr crossed-p) pour que
;;;  step-cpu puisse appliquer le cycle +1 sur franchissement de page.
;;; --------------------------------------------------------------------------

(declaim (inline addr-zp addr-zpx addr-zpy addr-abs
                 addr-absx* addr-absy* addr-indx addr-indy*))

(defun addr-zp (cpu)
  "Zéro-page : $nn"
  (fetch cpu))

(defun addr-zpx (cpu)
  "Zéro-page indexé X : ($nn + X) mod 256"
  (logand (+ (fetch cpu) (cpu-x cpu)) #xFF))

(defun addr-zpy (cpu)
  "Zéro-page indexé Y : ($nn + Y) mod 256"
  (logand (+ (fetch cpu) (cpu-y cpu)) #xFF))

(defun addr-abs (cpu)
  "Absolu : $nnnn"
  (fetch16 cpu))

(defun addr-absx* (cpu)
  "Absolu indexé X. Retourne (values addr page-crossed-p)."
  (let* ((base (fetch16 cpu))
         (addr (logand (+ base (cpu-x cpu)) #xFFFF)))
    (values addr (/= (logand base #xFF00) (logand addr #xFF00)))))

(defun addr-absy* (cpu)
  "Absolu indexé Y. Retourne (values addr page-crossed-p)."
  (let* ((base (fetch16 cpu))
         (addr (logand (+ base (cpu-y cpu)) #xFFFF)))
    (values addr (/= (logand base #xFF00) (logand addr #xFF00)))))

(defun addr-indx (cpu)
  "Indirect indexé X : ($nn + X) — lit l'adresse en zéro-page."
  (let ((zp (logand (+ (fetch cpu) (cpu-x cpu)) #xFF)))
    (logior (mem-read cpu zp)
            (ash (mem-read cpu (logand (1+ zp) #xFF)) 8))))

(defun addr-indy* (cpu)
  "Indirect indexé Y : ($nn),Y. Retourne (values addr page-crossed-p)."
  (let* ((zp   (fetch cpu))
         (base (logior (mem-read cpu zp)
                       (ash (mem-read cpu (logand (1+ zp) #xFF)) 8)))
         (addr (logand (+ base (cpu-y cpu)) #xFFFF)))
    (values addr (/= (logand base #xFF00) (logand addr #xFF00)))))


;;; --------------------------------------------------------------------------
;;;  Helpers ALU
;;; --------------------------------------------------------------------------

(defun do-adc (cpu val)
  "A ← A + VAL + C. Met à jour N V Z C."
  (let* ((a      (cpu-a cpu))
         (c      (if (flag-c cpu) 1 0))
         (result (+ a val c)))
    (set-flag cpu +flag-c+ (> result #xFF))
    (set-flag cpu +flag-v+
              (not (zerop (logand (lognot (logxor a val))
                                  (logxor a result)
                                  #x80))))
    (setf (cpu-a cpu) (logand result #xFF))
    (update-nz cpu (cpu-a cpu))))

(defun do-sbc (cpu val)
  "A ← A - VAL - (1-C). Implémenté comme ADC avec complément de VAL."
  (do-adc cpu (logxor val #xFF)))

(defun do-and (cpu val)
  "A ← A & VAL. Met à jour N Z."
  (setf (cpu-a cpu) (logand (cpu-a cpu) val))
  (update-nz cpu (cpu-a cpu)))

(defun do-ora (cpu val)
  "A ← A | VAL. Met à jour N Z."
  (setf (cpu-a cpu) (logior (cpu-a cpu) val))
  (update-nz cpu (cpu-a cpu)))

(defun do-eor (cpu val)
  "A ← A ^ VAL. Met à jour N Z."
  (setf (cpu-a cpu) (logxor (cpu-a cpu) val))
  (update-nz cpu (cpu-a cpu)))

(defun do-cmp (cpu reg val)
  "Compare REG avec VAL. Met à jour N Z C (pas V)."
  (let ((result (logand (- reg val) #xFF)))
    (set-flag cpu +flag-c+ (>= reg val))
    (set-flag cpu +flag-n+ (logbitp 7 result))
    (set-flag cpu +flag-z+ (zerop result))))

(defun do-bit (cpu val)
  "BIT : N ← bit7(VAL), V ← bit6(VAL), Z ← (A & VAL) = 0."
  (set-flag cpu +flag-n+ (logbitp 7 val))
  (set-flag cpu +flag-v+ (logbitp 6 val))
  (set-flag cpu +flag-z+ (zerop (logand (cpu-a cpu) val))))




;;; --------------------------------------------------------------------------
;;;  Exécution — step-cpu
;;;
;;;  Étape 1 : instructions implicites uniquement (1 octet, sans opérande).
;;;
;;;  Opcode  Mnémonique  Cycles  Description
;;;  ------  ----------  ------  -----------
;;;  $00     BRK         7       Break — signal cpu-break
;;;  $EA     NOP         2       No operation
;;;  $AA     TAX         2       A → X
;;;  $8A     TXA         2       X → A
;;;  $A8     TAY         2       A → Y
;;;  $98     TYA         2       Y → A
;;;  $BA     TSX         2       SP → X
;;;  $9A     TXS         2       X → SP  (ne met pas à jour N/Z)
;;;  $48     PHA         3       Empile A
;;;  $68     PLA         4       Dépile A
;;;  $08     PHP         3       Empile P (avec B=1)
;;;  $28     PLP         4       Dépile P (bit 5 forcé à 1)
;;;  $E8     INX         2       X++ (modulo 256)
;;;  $C8     INY         2       Y++ (modulo 256)
;;;  $CA     DEX         2       X-- (modulo 256)
;;;  $88     DEY         2       Y-- (modulo 256)
;;;  $18     CLC         2       C ← 0
;;;  $38     SEC         2       C ← 1
;;;  $58     CLI         2       I ← 0
;;;  $78     SEI         2       I ← 1
;;;  $B8     CLV         2       V ← 0
;;;  $D8     CLD         2       D ← 0
;;;  $F8     SED         2       D ← 1
;;; --------------------------------------------------------------------------

(defun step-cpu (cpu)
  "Exécute l'instruction au PC courant. Avance PC et met à jour les cycles.
   Signale CPU-BREAK sur BRK, CPU-ILLEGAL-OPCODE sur opcode inconnu."
  (let ((opcode (mem-read cpu (cpu-pc cpu))))
    (setf (cpu-pc cpu) (logand (1+ (cpu-pc cpu)) #xFFFF))
    (case opcode

      ;; --- NOP ---
      (#xEA
       (incf (cpu-cycles cpu) 2))

      ;; --- BRK ---
      ;; Positionne B, signale la condition (sans empilement IRQ en étape 1)
      (#x00
       (set-flag cpu +flag-b+ t)
       (incf (cpu-cycles cpu) 7)
       (signal 'cpu-break :cpu cpu))

      ;; --- Transferts registres ---
      (#xAA  ; TAX
       (setf (cpu-x cpu) (cpu-a cpu))
       (update-nz cpu (cpu-x cpu))
       (incf (cpu-cycles cpu) 2))

      (#x8A  ; TXA
       (setf (cpu-a cpu) (cpu-x cpu))
       (update-nz cpu (cpu-a cpu))
       (incf (cpu-cycles cpu) 2))

      (#xA8  ; TAY
       (setf (cpu-y cpu) (cpu-a cpu))
       (update-nz cpu (cpu-y cpu))
       (incf (cpu-cycles cpu) 2))

      (#x98  ; TYA
       (setf (cpu-a cpu) (cpu-y cpu))
       (update-nz cpu (cpu-a cpu))
       (incf (cpu-cycles cpu) 2))

      (#xBA  ; TSX
       (setf (cpu-x cpu) (cpu-sp cpu))
       (update-nz cpu (cpu-x cpu))
       (incf (cpu-cycles cpu) 2))

      (#x9A  ; TXS — ne met pas à jour N/Z
       (setf (cpu-sp cpu) (cpu-x cpu))
       (incf (cpu-cycles cpu) 2))

      ;; --- Pile ---
      (#x48  ; PHA
       (stack-push cpu (cpu-a cpu))
       (incf (cpu-cycles cpu) 3))

      (#x68  ; PLA
       (setf (cpu-a cpu) (stack-pull cpu))
       (update-nz cpu (cpu-a cpu))
       (incf (cpu-cycles cpu) 4))

      (#x08  ; PHP — empile P avec bit B forcé à 1
       (stack-push cpu (logior (cpu-p cpu) +flag-b+))
       (incf (cpu-cycles cpu) 3))

      (#x28  ; PLP — dépile P, bit 5 toujours forcé à 1
       (setf (cpu-p cpu) (logior +flag-5+ (stack-pull cpu)))
       (incf (cpu-cycles cpu) 4))

      ;; --- Incréments / décréments ---
      (#xE8  ; INX
       (setf (cpu-x cpu) (logand (1+ (cpu-x cpu)) #xFF))
       (update-nz cpu (cpu-x cpu))
       (incf (cpu-cycles cpu) 2))

      (#xC8  ; INY
       (setf (cpu-y cpu) (logand (1+ (cpu-y cpu)) #xFF))
       (update-nz cpu (cpu-y cpu))
       (incf (cpu-cycles cpu) 2))

      (#xCA  ; DEX
       (setf (cpu-x cpu) (logand (1- (cpu-x cpu)) #xFF))
       (update-nz cpu (cpu-x cpu))
       (incf (cpu-cycles cpu) 2))

      (#x88  ; DEY
       (setf (cpu-y cpu) (logand (1- (cpu-y cpu)) #xFF))
       (update-nz cpu (cpu-y cpu))
       (incf (cpu-cycles cpu) 2))

      ;; --- Flags ---
      (#x18 (set-flag cpu +flag-c+ nil) (incf (cpu-cycles cpu) 2))  ; CLC
      (#x38 (set-flag cpu +flag-c+ t)   (incf (cpu-cycles cpu) 2))  ; SEC
      (#x58 (set-flag cpu +flag-i+ nil) (incf (cpu-cycles cpu) 2))  ; CLI
      (#x78 (set-flag cpu +flag-i+ t)   (incf (cpu-cycles cpu) 2))  ; SEI
      (#xB8 (set-flag cpu +flag-v+ nil) (incf (cpu-cycles cpu) 2))  ; CLV
      (#xD8 (set-flag cpu +flag-d+ nil) (incf (cpu-cycles cpu) 2))  ; CLD
      (#xF8 (set-flag cpu +flag-d+ t)   (incf (cpu-cycles cpu) 2))  ; SED

      ;; --- LDA ---
      (#xA9  ; LDA imm
       (setf (cpu-a cpu) (fetch cpu))
       (update-nz cpu (cpu-a cpu))
       (incf (cpu-cycles cpu) 2))

      (#xA5  ; LDA zp
       (setf (cpu-a cpu) (mem-read cpu (addr-zp cpu)))
       (update-nz cpu (cpu-a cpu))
       (incf (cpu-cycles cpu) 3))

      (#xB5  ; LDA zp,X
       (setf (cpu-a cpu) (mem-read cpu (addr-zpx cpu)))
       (update-nz cpu (cpu-a cpu))
       (incf (cpu-cycles cpu) 4))

      (#xAD  ; LDA abs
       (setf (cpu-a cpu) (mem-read cpu (addr-abs cpu)))
       (update-nz cpu (cpu-a cpu))
       (incf (cpu-cycles cpu) 4))

      (#xBD  ; LDA abs,X
       (multiple-value-bind (addr cross) (addr-absx* cpu)
         (setf (cpu-a cpu) (mem-read cpu addr))
         (update-nz cpu (cpu-a cpu))
         (incf (cpu-cycles cpu) (if cross 5 4))))

      (#xB9  ; LDA abs,Y
       (multiple-value-bind (addr cross) (addr-absy* cpu)
         (setf (cpu-a cpu) (mem-read cpu addr))
         (update-nz cpu (cpu-a cpu))
         (incf (cpu-cycles cpu) (if cross 5 4))))

      (#xA1  ; LDA (ind,X)
       (setf (cpu-a cpu) (mem-read cpu (addr-indx cpu)))
       (update-nz cpu (cpu-a cpu))
       (incf (cpu-cycles cpu) 6))

      (#xB1  ; LDA (ind),Y
       (multiple-value-bind (addr cross) (addr-indy* cpu)
         (setf (cpu-a cpu) (mem-read cpu addr))
         (update-nz cpu (cpu-a cpu))
         (incf (cpu-cycles cpu) (if cross 6 5))))

      ;; --- LDX ---
      (#xA2  ; LDX imm
       (setf (cpu-x cpu) (fetch cpu))
       (update-nz cpu (cpu-x cpu))
       (incf (cpu-cycles cpu) 2))

      (#xA6  ; LDX zp
       (setf (cpu-x cpu) (mem-read cpu (addr-zp cpu)))
       (update-nz cpu (cpu-x cpu))
       (incf (cpu-cycles cpu) 3))

      (#xB6  ; LDX zp,Y
       (setf (cpu-x cpu) (mem-read cpu (addr-zpy cpu)))
       (update-nz cpu (cpu-x cpu))
       (incf (cpu-cycles cpu) 4))

      (#xAE  ; LDX abs
       (setf (cpu-x cpu) (mem-read cpu (addr-abs cpu)))
       (update-nz cpu (cpu-x cpu))
       (incf (cpu-cycles cpu) 4))

      (#xBE  ; LDX abs,Y
       (multiple-value-bind (addr cross) (addr-absy* cpu)
         (setf (cpu-x cpu) (mem-read cpu addr))
         (update-nz cpu (cpu-x cpu))
         (incf (cpu-cycles cpu) (if cross 5 4))))

      ;; --- LDY ---
      (#xA0  ; LDY imm
       (setf (cpu-y cpu) (fetch cpu))
       (update-nz cpu (cpu-y cpu))
       (incf (cpu-cycles cpu) 2))

      (#xA4  ; LDY zp
       (setf (cpu-y cpu) (mem-read cpu (addr-zp cpu)))
       (update-nz cpu (cpu-y cpu))
       (incf (cpu-cycles cpu) 3))

      (#xB4  ; LDY zp,X
       (setf (cpu-y cpu) (mem-read cpu (addr-zpx cpu)))
       (update-nz cpu (cpu-y cpu))
       (incf (cpu-cycles cpu) 4))

      (#xAC  ; LDY abs
       (setf (cpu-y cpu) (mem-read cpu (addr-abs cpu)))
       (update-nz cpu (cpu-y cpu))
       (incf (cpu-cycles cpu) 4))

      (#xBC  ; LDY abs,X
       (multiple-value-bind (addr cross) (addr-absx* cpu)
         (setf (cpu-y cpu) (mem-read cpu addr))
         (update-nz cpu (cpu-y cpu))
         (incf (cpu-cycles cpu) (if cross 5 4))))

      ;; --- STA ---
      (#x85  ; STA zp
       (mem-write cpu (addr-zp cpu) (cpu-a cpu))
       (incf (cpu-cycles cpu) 3))

      (#x95  ; STA zp,X
       (mem-write cpu (addr-zpx cpu) (cpu-a cpu))
       (incf (cpu-cycles cpu) 4))

      (#x8D  ; STA abs
       (mem-write cpu (addr-abs cpu) (cpu-a cpu))
       (incf (cpu-cycles cpu) 4))

      (#x9D  ; STA abs,X  (toujours 5 cycles — pas de bonus page)
       (mem-write cpu (nth-value 0 (addr-absx* cpu)) (cpu-a cpu))
       (incf (cpu-cycles cpu) 5))

      (#x99  ; STA abs,Y  (toujours 5 cycles)
       (mem-write cpu (nth-value 0 (addr-absy* cpu)) (cpu-a cpu))
       (incf (cpu-cycles cpu) 5))

      (#x81  ; STA (ind,X)
       (mem-write cpu (addr-indx cpu) (cpu-a cpu))
       (incf (cpu-cycles cpu) 6))

      (#x91  ; STA (ind),Y  (toujours 6 cycles)
       (mem-write cpu (nth-value 0 (addr-indy* cpu)) (cpu-a cpu))
       (incf (cpu-cycles cpu) 6))

      ;; --- STX ---
      (#x86  ; STX zp
       (mem-write cpu (addr-zp cpu) (cpu-x cpu))
       (incf (cpu-cycles cpu) 3))

      (#x96  ; STX zp,Y
       (mem-write cpu (addr-zpy cpu) (cpu-x cpu))
       (incf (cpu-cycles cpu) 4))

      (#x8E  ; STX abs
       (mem-write cpu (addr-abs cpu) (cpu-x cpu))
       (incf (cpu-cycles cpu) 4))

      ;; --- STY ---
      (#x84  ; STY zp
       (mem-write cpu (addr-zp cpu) (cpu-y cpu))
       (incf (cpu-cycles cpu) 3))

      (#x94  ; STY zp,X
       (mem-write cpu (addr-zpx cpu) (cpu-y cpu))
       (incf (cpu-cycles cpu) 4))

      (#x8C  ; STY abs
       (mem-write cpu (addr-abs cpu) (cpu-y cpu))
       (incf (cpu-cycles cpu) 4))

      ;; --- ADC ---
      (#x69 (do-adc cpu (fetch cpu))                          (incf (cpu-cycles cpu) 2))
      (#x65 (do-adc cpu (mem-read cpu (addr-zp cpu)))         (incf (cpu-cycles cpu) 3))
      (#x75 (do-adc cpu (mem-read cpu (addr-zpx cpu)))        (incf (cpu-cycles cpu) 4))
      (#x6D (do-adc cpu (mem-read cpu (addr-abs cpu)))        (incf (cpu-cycles cpu) 4))
      (#x7D (multiple-value-bind (a cross) (addr-absx* cpu)
              (do-adc cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 5 4))))
      (#x79 (multiple-value-bind (a cross) (addr-absy* cpu)
              (do-adc cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 5 4))))
      (#x61 (do-adc cpu (mem-read cpu (addr-indx cpu)))       (incf (cpu-cycles cpu) 6))
      (#x71 (multiple-value-bind (a cross) (addr-indy* cpu)
              (do-adc cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 6 5))))

      ;; --- SBC ---
      (#xE9 (do-sbc cpu (fetch cpu))                          (incf (cpu-cycles cpu) 2))
      (#xE5 (do-sbc cpu (mem-read cpu (addr-zp cpu)))         (incf (cpu-cycles cpu) 3))
      (#xF5 (do-sbc cpu (mem-read cpu (addr-zpx cpu)))        (incf (cpu-cycles cpu) 4))
      (#xED (do-sbc cpu (mem-read cpu (addr-abs cpu)))        (incf (cpu-cycles cpu) 4))
      (#xFD (multiple-value-bind (a cross) (addr-absx* cpu)
              (do-sbc cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 5 4))))
      (#xF9 (multiple-value-bind (a cross) (addr-absy* cpu)
              (do-sbc cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 5 4))))
      (#xE1 (do-sbc cpu (mem-read cpu (addr-indx cpu)))       (incf (cpu-cycles cpu) 6))
      (#xF1 (multiple-value-bind (a cross) (addr-indy* cpu)
              (do-sbc cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 6 5))))

      ;; --- AND ---
      (#x29 (do-and cpu (fetch cpu))                          (incf (cpu-cycles cpu) 2))
      (#x25 (do-and cpu (mem-read cpu (addr-zp cpu)))         (incf (cpu-cycles cpu) 3))
      (#x35 (do-and cpu (mem-read cpu (addr-zpx cpu)))        (incf (cpu-cycles cpu) 4))
      (#x2D (do-and cpu (mem-read cpu (addr-abs cpu)))        (incf (cpu-cycles cpu) 4))
      (#x3D (multiple-value-bind (a cross) (addr-absx* cpu)
              (do-and cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 5 4))))
      (#x39 (multiple-value-bind (a cross) (addr-absy* cpu)
              (do-and cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 5 4))))
      (#x21 (do-and cpu (mem-read cpu (addr-indx cpu)))       (incf (cpu-cycles cpu) 6))
      (#x31 (multiple-value-bind (a cross) (addr-indy* cpu)
              (do-and cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 6 5))))

      ;; --- ORA ---
      (#x09 (do-ora cpu (fetch cpu))                          (incf (cpu-cycles cpu) 2))
      (#x05 (do-ora cpu (mem-read cpu (addr-zp cpu)))         (incf (cpu-cycles cpu) 3))
      (#x15 (do-ora cpu (mem-read cpu (addr-zpx cpu)))        (incf (cpu-cycles cpu) 4))
      (#x0D (do-ora cpu (mem-read cpu (addr-abs cpu)))        (incf (cpu-cycles cpu) 4))
      (#x1D (multiple-value-bind (a cross) (addr-absx* cpu)
              (do-ora cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 5 4))))
      (#x19 (multiple-value-bind (a cross) (addr-absy* cpu)
              (do-ora cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 5 4))))
      (#x01 (do-ora cpu (mem-read cpu (addr-indx cpu)))       (incf (cpu-cycles cpu) 6))
      (#x11 (multiple-value-bind (a cross) (addr-indy* cpu)
              (do-ora cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 6 5))))

      ;; --- EOR ---
      (#x49 (do-eor cpu (fetch cpu))                          (incf (cpu-cycles cpu) 2))
      (#x45 (do-eor cpu (mem-read cpu (addr-zp cpu)))         (incf (cpu-cycles cpu) 3))
      (#x55 (do-eor cpu (mem-read cpu (addr-zpx cpu)))        (incf (cpu-cycles cpu) 4))
      (#x4D (do-eor cpu (mem-read cpu (addr-abs cpu)))        (incf (cpu-cycles cpu) 4))
      (#x5D (multiple-value-bind (a cross) (addr-absx* cpu)
              (do-eor cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 5 4))))
      (#x59 (multiple-value-bind (a cross) (addr-absy* cpu)
              (do-eor cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 5 4))))
      (#x41 (do-eor cpu (mem-read cpu (addr-indx cpu)))       (incf (cpu-cycles cpu) 6))
      (#x51 (multiple-value-bind (a cross) (addr-indy* cpu)
              (do-eor cpu (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 6 5))))

      ;; --- CMP ---
      (#xC9 (do-cmp cpu (cpu-a cpu) (fetch cpu))                         (incf (cpu-cycles cpu) 2))
      (#xC5 (do-cmp cpu (cpu-a cpu) (mem-read cpu (addr-zp cpu)))        (incf (cpu-cycles cpu) 3))
      (#xD5 (do-cmp cpu (cpu-a cpu) (mem-read cpu (addr-zpx cpu)))       (incf (cpu-cycles cpu) 4))
      (#xCD (do-cmp cpu (cpu-a cpu) (mem-read cpu (addr-abs cpu)))       (incf (cpu-cycles cpu) 4))
      (#xDD (multiple-value-bind (a cross) (addr-absx* cpu)
              (do-cmp cpu (cpu-a cpu) (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 5 4))))
      (#xD9 (multiple-value-bind (a cross) (addr-absy* cpu)
              (do-cmp cpu (cpu-a cpu) (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 5 4))))
      (#xC1 (do-cmp cpu (cpu-a cpu) (mem-read cpu (addr-indx cpu)))      (incf (cpu-cycles cpu) 6))
      (#xD1 (multiple-value-bind (a cross) (addr-indy* cpu)
              (do-cmp cpu (cpu-a cpu) (mem-read cpu a))
              (incf (cpu-cycles cpu) (if cross 6 5))))

      ;; --- CPX ---
      (#xE0 (do-cmp cpu (cpu-x cpu) (fetch cpu))                         (incf (cpu-cycles cpu) 2))
      (#xE4 (do-cmp cpu (cpu-x cpu) (mem-read cpu (addr-zp cpu)))        (incf (cpu-cycles cpu) 3))
      (#xEC (do-cmp cpu (cpu-x cpu) (mem-read cpu (addr-abs cpu)))       (incf (cpu-cycles cpu) 4))

      ;; --- CPY ---
      (#xC0 (do-cmp cpu (cpu-y cpu) (fetch cpu))                         (incf (cpu-cycles cpu) 2))
      (#xC4 (do-cmp cpu (cpu-y cpu) (mem-read cpu (addr-zp cpu)))        (incf (cpu-cycles cpu) 3))
      (#xCC (do-cmp cpu (cpu-y cpu) (mem-read cpu (addr-abs cpu)))       (incf (cpu-cycles cpu) 4))

      ;; --- BIT ---
      (#x24 (do-bit cpu (mem-read cpu (addr-zp cpu)))  (incf (cpu-cycles cpu) 3))
      (#x2C (do-bit cpu (mem-read cpu (addr-abs cpu))) (incf (cpu-cycles cpu) 4))

      ;; --- Opcode inconnu ---
      (t
       (error 'cpu-illegal-opcode :cpu cpu :opcode opcode))))
  cpu)


;;; --------------------------------------------------------------------------
;;;  Exécution — run-cpu
;;; --------------------------------------------------------------------------

(defun run-cpu (cpu &key (max-steps 1000000))
  "Exécute des instructions jusqu'à BRK ou MAX-STEPS.
   Retourne (values cpu stop-reason) :
     :brk        — BRK rencontré
     :step-limit — limite atteinte sans BRK"
  (handler-case
      (loop repeat max-steps
            do (step-cpu cpu)
            finally (signal 'cpu-step-limit :cpu cpu :steps max-steps))
    (cpu-break ()
      (values cpu :brk))
    (cpu-step-limit ()
      (values cpu :step-limit))))
