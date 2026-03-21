; -*- coding: utf-8 -*-
;;;; src/backend/m68k.lisp
;;;;
;;;; Backend M68K pour cl-asm.
;;;; Supporte le jeu d'instructions Motorola 68000 (Amiga, Atari ST, Mac 68k…).
;;;;
;;;; Encodage big-endian 16 bits (mots).
;;;; EA field = (mode<<3)|reg, 6 bits.
;;;; MOVE : dst EA inversé (reg bits 11-9, mode bits 8-6).

(defpackage #:cl-asm/backend.m68k
  (:use #:cl)
  (:export
   #:assemble-m68k
   #:assemble-string-m68k
   #:assemble-file-m68k))

(in-package #:cl-asm/backend.m68k)

;;; Déclarations forward
(declaim (ftype (function (t t t t t) t) m68k-directive-pass1))
(declaim (ftype (function (t t t t t) t) m68k-directive-pass2))
(declaim (ftype (function (t t) t) m68k-ea-mode-reg))
(declaim (ftype (function (t t t) t) m68k-ea-extension-words))


;;; --------------------------------------------------------------------------
;;;  Helpers sur les opérandes IR
;;; --------------------------------------------------------------------------

(defun op-kind (op) (cl-asm/ir:ir-operand-kind op))
(defun op-val  (op) (cl-asm/ir:ir-operand-value op))

(defun op-str= (op name)
  "Vrai si l'opérande est :direct avec la chaîne NAME (insensible à la casse)."
  (and (eq (op-kind op) :direct)
       (stringp (op-val op))
       (string= (string-upcase (op-val op)) (string-upcase name))))


;;; --------------------------------------------------------------------------
;;;  Tables de registres
;;; --------------------------------------------------------------------------

(defparameter *data-regs* #("D0" "D1" "D2" "D3" "D4" "D5" "D6" "D7"))
(defparameter *addr-regs* #("A0" "A1" "A2" "A3" "A4" "A5" "A6" "A7"))

(defun m68k-data-reg-num (name)
  "Retourne le numéro 0-7 d'un registre de données, NIL si inconnu."
  (let ((up (string-upcase name)))
    (or (position up *data-regs* :test #'string=)
        ;; SP n'est pas un registre de données
        nil)))

(defun m68k-addr-reg-num (name)
  "Retourne le numéro 0-7 d'un registre d'adresse, NIL si inconnu."
  (let ((up (string-upcase name)))
    (or (position up *addr-regs* :test #'string=)
        (when (string= up "SP") 7)
        nil)))

(defun m68k-is-data-reg (name)
  (and (stringp name) (m68k-data-reg-num name) t))

(defun m68k-is-addr-reg (name)
  (and (stringp name) (m68k-addr-reg-num name) t))

;;; Teste si un opérande :direct est un registre de données
(defun op-is-dn-p (op)
  (and (eq (op-kind op) :direct)
       (stringp (op-val op))
       (m68k-is-data-reg (op-val op))))

;;; Teste si un opérande :direct est un registre d'adresse
(defun op-is-an-p (op)
  (and (eq (op-kind op) :direct)
       (stringp (op-val op))
       (m68k-is-addr-reg (op-val op))))

(defun op-is-reg-p (op)
  (or (op-is-dn-p op) (op-is-an-p op)))

;;; Registre de données sous forme de numéro
(defun op-dn-num (op) (m68k-data-reg-num (op-val op)))
(defun op-an-num (op) (m68k-addr-reg-num (op-val op)))


;;; --------------------------------------------------------------------------
;;;  Évaluation des expressions
;;; --------------------------------------------------------------------------

(defun m68k-eval (expr env)
  "Évalue EXPR dans ENV. Retourne (values val resolved-p)."
  (cl-asm/expression:eval-expr expr env))

(defun m68k-eval! (expr env)
  "Évalue EXPR dans ENV. Erreur si non résolu."
  (multiple-value-bind (val ok)
      (m68k-eval expr env)
    (if ok val (error "Expression M68K non résolue : ~S" expr))))


;;; --------------------------------------------------------------------------
;;;  Encodage bas niveau (big-endian)
;;; --------------------------------------------------------------------------

(defun words->bytes (words)
  "Convertit une liste de mots 16 bits en liste d'octets (big-endian)."
  (loop for w in words
        collect (logand (ash w -8) #xFF)
        collect (logand w #xFF)))

(defun m68k-byte (val) (logand val #xFF))
(defun m68k-word (val) (logand val #xFFFF))

(defun m68k-s8 (val)
  "Tronque à 8 bits signé → représentation unsigned."
  (logand (if (< val 0) (+ val 256) val) #xFF))

(defun m68k-s16 (val)
  "Tronque à 16 bits signé → représentation unsigned."
  (logand (if (< val 0) (+ val 65536) val) #xFFFF))

(defun m68k-size-code (size)
  "Code de taille standard : .B→0, .W→1, .L→2."
  (ecase size
    (:byte 0)
    (:word 1)
    (:long 2)))

(defun m68k-move-size-code (size)
  "Code de taille pour MOVE : .B→1, .L→2, .W→3."
  (ecase size
    (:byte 1)
    (:long 2)
    (:word 3)))

(defun m68k-branch-size (size)
  "Retourne la taille en octets d'une branche : :byte→2, sinon 4."
  (if (eq size :byte) 2 4))


;;; --------------------------------------------------------------------------
;;;  EA encoding
;;; --------------------------------------------------------------------------
;;;
;;;  EA field = (mode<<3)|reg  (6 bits dans le mot d'instruction)
;;;
;;;  Mode 0 : Dn         — :direct "D0".."D7"
;;;  Mode 1 : An         — :direct "A0".."A7"/"SP"
;;;  Mode 2 : (An)       — :indirect "A0".."A7"
;;;  Mode 3 : (An)+      — :post-increment "A0".."A7"
;;;  Mode 4 : -(An)      — :pre-decrement "A0".."A7"
;;;  Mode 5 : d(An)      — :indirect (:disp "An" d)
;;;  Mode 6 : d(An,Xi.s) — :indirect (:indexed "An" "Xi" size d)
;;;  Mode 7 reg 0 : abs.W  — :direct val ≤ $7FFF
;;;  Mode 7 reg 1 : abs.L  — :direct val (grands)
;;;  Mode 7 reg 2 : d(PC)  — :indirect (:disp :pc d)
;;;  Mode 7 reg 3 : d(PC,Xi.s) — :indirect (:indexed :pc "Xi" size d)
;;;  Mode 7 reg 4 : #imm  — :immediate val

(defun m68k-ea-mode-reg (op env)
  "Retourne (values mode reg) pour l'opérande OP.
   Évalue les expressions numériques via ENV (pour abs.W vs abs.L)."
  (let ((kind (op-kind op))
        (val  (op-val op)))
    (cond
      ;; Mode 0 : Dn
      ((and (eq kind :direct) (stringp val) (m68k-is-data-reg val))
       (values 0 (m68k-data-reg-num val)))
      ;; Mode 1 : An
      ((and (eq kind :direct) (stringp val) (m68k-is-addr-reg val))
       (values 1 (m68k-addr-reg-num val)))
      ;; Mode 2 : (An)
      ((and (eq kind :indirect) (stringp val) (m68k-is-addr-reg val))
       (values 2 (m68k-addr-reg-num val)))
      ;; Mode 3 : (An)+
      ((eq kind :post-increment)
       (values 3 (m68k-addr-reg-num val)))
      ;; Mode 4 : -(An)
      ((eq kind :pre-decrement)
       (values 4 (m68k-addr-reg-num val)))
      ;; Mode 5 : d(An)
      ((and (eq kind :indirect) (listp val) (eq (first val) :disp)
            (stringp (second val)))
       (values 5 (m68k-addr-reg-num (second val))))
      ;; Mode 6 : d(An,Xi.s)
      ((and (eq kind :indirect) (listp val) (eq (first val) :indexed)
            (stringp (second val)))
       (values 6 (m68k-addr-reg-num (second val))))
      ;; Mode 5 : d(PC)
      ((and (eq kind :indirect) (listp val) (eq (first val) :disp)
            (eq (second val) :pc))
       (values 7 2))
      ;; Mode 6 : d(PC,Xi.s)
      ((and (eq kind :indirect) (listp val) (eq (first val) :indexed)
            (eq (second val) :pc))
       (values 7 3))
      ;; Mode 7 reg 4 : #imm
      ((eq kind :immediate)
       (values 7 4))
      ;; Mode 7 reg 0/1 : abs.W ou abs.L (valeur numérique directe)
      ((and (eq kind :direct) (not (stringp val)))
       (multiple-value-bind (addr ok)
           (m68k-eval val env)
         (if (and ok (<= -32768 addr 32767))
             (values 7 0)   ; abs.W
             (values 7 1)))) ; abs.L ou non résolu → abs.L par défaut
      ;; Symbole non résolu → abs.L
      ((and (eq kind :direct) (stringp val))
       ;; Non un registre connu → adresse absolue symbolique
       (multiple-value-bind (addr ok)
           (m68k-eval val env)
         (if (and ok (<= -32768 addr 32767))
             (values 7 0)
             (values 7 1))))
      (t (error "Opérande M68K invalide : ~S ~S" kind val)))))

(defun m68k-xi-word (xi-name xi-size)
  "Construit le mot d'extension indexé : bit15=0 (Dn) ou 1 (An),
   bits14-12=reg, bit11=0, bits9-8=taille (0=.W, 1=.L), bits7-0=disp (0)."
  (let* ((up (string-upcase xi-name))
         (dn (m68k-data-reg-num up))
         (an (m68k-addr-reg-num up))
         (da-bit (if dn 0 1))
         (reg    (or dn an 0))
         (sz-bit (if (eq xi-size :long) 1 0)))
    (logior (ash da-bit 15)
            (ash reg 12)
            (ash sz-bit 11))))

(defun m68k-ea-extension-words (op env pc)
  "Retourne la liste de mots 16 bits d'extension pour l'EA de OP."
  (let ((kind (op-kind op))
        (val  (op-val op)))
    (cond
      ;; Mode 5 : d(An) → 1 mot extension = disp signé 16 bits
      ((and (eq kind :indirect) (listp val) (eq (first val) :disp)
            (stringp (second val)))
       (let ((d (m68k-eval! (third val) env)))
         (list (m68k-s16 d))))
      ;; Mode 6 : d(An,Xi.s) → 1 mot extension briefword
      ((and (eq kind :indirect) (listp val) (eq (first val) :indexed)
            (stringp (second val)))
       (destructuring-bind (_ an xi-name xi-size disp) val
         (declare (ignore _ an))
         (let ((d  (m68k-eval! disp env))
               (xw (m68k-xi-word xi-name xi-size)))
           (list (logior xw (m68k-s8 d))))))
      ;; d(PC) → déplacement relatif au PC (PC = adresse du mot d'extension)
      ((and (eq kind :indirect) (listp val) (eq (first val) :disp)
            (eq (second val) :pc))
       (let* ((target (m68k-eval! (third val) env))
              ;; Le mot d'extension est après le mot d'instruction (PC+2)
              (disp   (- target (+ pc 2))))
         (list (m68k-s16 disp))))
      ;; d(PC,Xi.s)
      ((and (eq kind :indirect) (listp val) (eq (first val) :indexed)
            (eq (second val) :pc))
       (destructuring-bind (_ _pc xi-name xi-size disp) val
         (declare (ignore _ _pc))
         (let ((d  (m68k-eval! disp env))
               (xw (m68k-xi-word xi-name xi-size)))
           (list (logior xw (m68k-s8 d))))))
      ;; abs.W → 1 mot
      ;; abs.L → 2 mots  (géré dans m68k-ea-words-for-op)
      (t nil))))

(defun m68k-ea-imm-words (op env size)
  "Retourne les mots immédiats pour mode 7/4 (#imm) selon la taille."
  (let ((v (m68k-eval! (op-val op) env)))
    (ecase size
      (:byte (list (m68k-byte v)))      ; 1 mot, octet dans low byte
      (:word (list (m68k-s16 v)))      ; 1 mot
      (:long (list (logand (ash v -16) #xFFFF)
                   (logand v #xFFFF))))))

(defun m68k-ea-abs-words (op env)
  "Retourne les mots pour une EA absolue (mode 7/0 ou 7/1)."
  (multiple-value-bind (mode reg)
      (m68k-ea-mode-reg op env)
    (declare (ignore mode))
    (let ((v (multiple-value-bind (addr ok)
                 (m68k-eval (op-val op) env)
               (if ok addr 0))))
      (if (= reg 0)
          ;; abs.W
          (list (m68k-s16 v))
          ;; abs.L
          (list (logand (ash v -16) #xFFFF)
                (logand v #xFFFF))))))

(defun m68k-ea-words-for-op (op env size pc)
  "Retourne la liste complète de mots d'extension pour OP."
  (let ((kind (op-kind op))
        (val  (op-val op)))
    (cond
      ((eq kind :immediate)
       (m68k-ea-imm-words op env size))
      ((and (eq kind :direct) (not (stringp val)))
       (m68k-ea-abs-words op env))
      ((and (eq kind :direct) (stringp val)
            (not (m68k-is-data-reg val))
            (not (m68k-is-addr-reg val)))
       ;; Symbole absolu
       (m68k-ea-abs-words op env))
      (t
       (m68k-ea-extension-words op env pc)))))

(defun m68k-ea-field (op env)
  "Retourne le champ EA (6 bits) pour OP : (mode<<3)|reg."
  (multiple-value-bind (mode reg)
      (m68k-ea-mode-reg op env)
    (logior (ash mode 3) reg)))


;;; --------------------------------------------------------------------------
;;;  Estimation de taille (passe 1)
;;; --------------------------------------------------------------------------

(defun m68k-ea-words-count (op &optional size)
  "Estime le nombre de mots d'extension pour une EA (sans évaluation).
   SIZE (:byte/:word/:long) affine l'estimation pour les immédiats."
  (let ((kind (op-kind op))
        (val  (op-val op)))
    (cond
      ;; Registres Dn/An, (An), (An)+, -(An) : 0
      ((and (eq kind :direct) (stringp val)
            (or (m68k-is-data-reg val) (m68k-is-addr-reg val))) 0)
      ((eq kind :indirect)
       (cond
         ((stringp val) 0)                    ; (An)
         ((and (listp val) (eq (first val) :disp)) 1)    ; d(An) ou d(PC)
         ((and (listp val) (eq (first val) :indexed)) 1) ; d(An,Xi)
         (t 0)))
      ((eq kind :post-increment) 0)
      ((eq kind :pre-decrement)  0)
      ((eq kind :immediate)
       ;; .B et .W → 1 mot ; .L → 2 mots ; sans info → pessimiste 2 mots
       (if (eq size :long) 2 (if size 1 2)))
      ;; abs numérique : évaluer si possible (constante littérale) pour choisir
      ;; abs.W (1 mot, addr ≤ 32767) ou abs.L (2 mots).
      ((and (eq kind :direct) (not (stringp val)))
       (multiple-value-bind (addr ok)
           (m68k-eval val nil)
         (if (and ok (<= -32768 addr 32767)) 1 2)))
      ;; symbole → abs.W (1 mot) : pour les programmes à origine ≤ $7FFF,
      ;; l'adresse résolue tient dans 16 bits, ce qui correspond à ce que
      ;; l'encodeur fait en passe 2 (abs.W si addr ≤ 32767).
      (t 1))))

(defun m68k-estimate-size (mnem size ops)
  "Estime la taille en octets d'une instruction M68K."
  (let ((op1 (first ops))
        (op2 (second ops)))
    (cond
      ;; Instructions 1 mot (pas d'extensions)
      ((member mnem '("NOP" "RTS" "RTR" "RTE" "TRAPV" "RESET" "ILLEGAL"
                      "STOP" "EXT" "EXTB" "SWAP" "UNLK")
               :test #'string=)
       2)
      ;; MOVEQ : toujours 1 mot
      ((string= mnem "MOVEQ") 2)
      ;; LINK : 1 mot + 1 mot déplacement
      ((string= mnem "LINK") 4)
      ;; TRAP : 1 mot
      ((string= mnem "TRAP") 2)
      ;; Branches
      ((member mnem '("BRA" "BSR" "BEQ" "BNE" "BLT" "BGT" "BLE" "BGE"
                      "BCC" "BCS" "BMI" "BPL" "BVC" "BVS" "BHI" "BLS"
                      "BNOT")
               :test #'string=)
       (m68k-branch-size size))
      ;; DBcc : 1 mot + 1 mot déplacement
      ((member mnem '("DBF" "DBRA" "DBEQ" "DBNE" "DBLT" "DBGT" "DBLE"
                      "DBGE" "DBCC" "DBCS" "DBMI" "DBPL" "DBVC" "DBVS"
                      "DBHI" "DBLS")
               :test #'string=)
       4)
      ;; Scc (S<cond>) : 1 mot + EA extensions
      ((and (>= (length mnem) 2) (char= (char mnem 0) #\S)
            (member (subseq mnem 1)
                    '("T" "F" "HI" "LS" "CC" "CS" "NE" "EQ"
                      "VC" "VS" "PL" "MI" "GE" "LT" "GT" "LE")
                    :test #'string=))
       (+ 2 (* 2 (if op1 (m68k-ea-words-count op1) 0))))
      ;; JMP / JSR : 1 mot + EA
      ((member mnem '("JMP" "JSR") :test #'string=)
       (+ 2 (* 2 (if op1 (m68k-ea-words-count op1) 0))))
      ;; LEA / PEA
      ((string= mnem "LEA") (+ 2 (* 2 (if op1 (m68k-ea-words-count op1) 0))))
      ((string= mnem "PEA") (+ 2 (* 2 (if op1 (m68k-ea-words-count op1) 0))))
      ;; EXG : 1 mot
      ((string= mnem "EXG") 2)
      ;; CHK : 1 mot + EA src
      ((string= mnem "CHK") (+ 2 (* 2 (if op1 (m68k-ea-words-count op1) 0))))
      ;; TAS : 1 mot + EA
      ((string= mnem "TAS") (+ 2 (* 2 (if op1 (m68k-ea-words-count op1) 0))))
      ;; MOVEM : 1 mot + 1 mot masque + EA
      ((string= mnem "MOVEM")
       (+ 4 (* 2 (if op2 (m68k-ea-words-count op2)
                     (if op1 (m68k-ea-words-count op1) 0)))))
      ;; MOVE / MOVEA : 1 mot + extensions src + extensions dst
      ((member mnem '("MOVE" "MOVEA") :test #'string=)
       (+ 2 (* 2 (+ (if op1 (m68k-ea-words-count op1 size) 0)
                    (if op2 (m68k-ea-words-count op2) 0)))))
      ;; ADDI/SUBI/ANDI/ORI/EORI/CMPI : 1 mot + imm words + EA
      ((member mnem '("ADDI" "SUBI" "ANDI" "ORI" "EORI" "CMPI")
               :test #'string=)
       (let ((imm-words (ecase (or size :word)
                          (:byte 1) (:word 1) (:long 2))))
         (+ 2 (* 2 imm-words)
            (* 2 (if op2 (m68k-ea-words-count op2) 0)))))
      ;; ADDQ/SUBQ : 1 mot + EA
      ((member mnem '("ADDQ" "SUBQ") :test #'string=)
       (+ 2 (* 2 (if op2 (m68k-ea-words-count op2) 0))))
      ;; MULU/MULS/DIVU/DIVS : 1 mot + EA source
      ((member mnem '("MULU" "MULS" "DIVU" "DIVS") :test #'string=)
       (+ 2 (* 2 (if op1 (m68k-ea-words-count op1 :word) 0))))
      ;; BTST/BCHG/BCLR/BSET : variable
      ((member mnem '("BTST" "BCHG" "BCLR" "BSET") :test #'string=)
       (if (and op1 (op-is-dn-p op1))
           ;; Dn,ea  : 1 mot + EA
           (+ 2 (* 2 (if op2 (m68k-ea-words-count op2) 0)))
           ;; #n,ea  : 1 mot + 1 mot imm + EA
           (+ 4 (* 2 (if op2 (m68k-ea-words-count op2) 0)))))
      ;; CLR/NEG/NEGX/NOT/TST : 1 mot + EA
      ((member mnem '("CLR" "NEG" "NEGX" "NOT" "TST") :test #'string=)
       (+ 2 (* 2 (if op1 (m68k-ea-words-count op1) 0))))
      ;; ABCD/SBCD/NBCD : 1 mot
      ((member mnem '("ABCD" "SBCD" "NBCD") :test #'string=) 2)
      ;; Shifts/rotations registre : 1 mot ; mémoire : 1 mot + EA
      ((member mnem '("ASL" "ASR" "LSL" "LSR" "ROL" "ROR" "ROXL" "ROXR")
               :test #'string=)
       (if (or (null op2)
               (and op2 (op-is-dn-p op2)))
           2
           (+ 2 (* 2 (if op1 (m68k-ea-words-count op1) 0)))))
      ;; ADD/SUB/AND/OR/EOR/CMP + variantes A/X
      (t
       (+ 2 (* 2 (+ (if op1 (m68k-ea-words-count op1 size) 0)
                    (if op2 (m68k-ea-words-count op2 size) 0))))))))


;;; --------------------------------------------------------------------------
;;;  Encodeurs spécialisés
;;; --------------------------------------------------------------------------

(defun encode-move (size op1 op2 env pc)
  "Encode MOVE.B/W/L op1, op2."
  (multiple-value-bind (src-mode src-reg)
      (m68k-ea-mode-reg op1 env)
    (multiple-value-bind (dst-mode dst-reg)
        (m68k-ea-mode-reg op2 env)
      (let* ((sc  (m68k-move-size-code (or size :word)))
             ;; Mot d'instruction : bits15-12=taille, 11-9=dst_reg, 8-6=dst_mode,
             ;; 5-3=src_mode, 2-0=src_reg
             (word (logior (ash sc 12)
                           (ash dst-reg 9)
                           (ash dst-mode 6)
                           (ash src-mode 3)
                           src-reg))
             (ext-src (m68k-ea-words-for-op op1 env size pc))
             ;; PC avance après mot d'instruction + mots src
             (pc2  (+ pc 2 (* 2 (length ext-src))))
             (ext-dst (m68k-ea-words-for-op op2 env size pc2)))
        (words->bytes (list* word (append ext-src ext-dst)))))))

(defun encode-movea (size op1 op2 env pc)
  "Encode MOVEA.W/L op1, An."
  (multiple-value-bind (src-mode src-reg)
      (m68k-ea-mode-reg op1 env)
    (let* ((sc    (if (eq size :long) 2 3)) ; .L→2, .W→3
           (an    (op-an-num op2))
           (word  (logior (ash sc 12)
                          (ash an 9)
                          (ash 1 6)          ; dst mode 1 = An
                          (ash src-mode 3)
                          src-reg))
           (ext   (m68k-ea-words-for-op op1 env size pc)))
      (words->bytes (list* word ext)))))

(defun encode-moveq (op1 op2 env)
  "Encode MOVEQ #n, Dn."
  (let ((n  (m68k-eval! (op-val op1) env))
        (dn (op-dn-num op2)))
    (words->bytes (list (logior #x7000 (ash dn 9) (m68k-byte n))))))

(defun m68k-alu-op-code (mnem)
  "Nibble haut (bits 15-12) de l'opération ALU."
  (cond
    ((string= mnem "OR")  8)   ; 1000 = $8
    ((string= mnem "SUB") 9)   ; 1001 = $9
    ((string= mnem "AND") 12)  ; 1100 = $C
    ((string= mnem "ADD") 13)  ; 1101 = $D
    ((string= mnem "EOR") 11)  ; 1011 = $B
    ((string= mnem "CMP") 11)  ; 1011 = $B
    (t nil)))

(defun encode-alu-dn (mnem size op1 op2 env pc)
  "Encode ADD/SUB/AND/OR/EOR/CMP <ea>,Dn ou Dn,<ea>."
  ;; EOR : toujours Dn,<EA> (dir=1), pas de forme EA→Dn
  ;; CMP : toujours <EA>,Dn (dir=0), pas de forme Dn→EA
  ;; ADD/SUB/AND/OR : dir déduit des opérandes
  (let ((op-code (or (m68k-alu-op-code mnem)
                     (error "Opération ALU inconnue : ~A" mnem))))
    (cond
      ;; EOR toujours Dn→<EA> (dir=1) : op1=Dn source, op2=EA destination
      ((string= mnem "EOR")
       (let* ((sc   (m68k-size-code (or size :word)))
              (dn   (op-dn-num op1))
              (ea   (m68k-ea-field op2 env))
              (word (logior (ash op-code 12) (ash dn 9) (ash 1 8) (ash sc 6) ea))
              (ext  (m68k-ea-words-for-op op2 env size pc)))
         (words->bytes (list* word ext))))
      ;; CMP toujours <EA>→Dn (dir=0) : op1=EA source, op2=Dn destination
      ((string= mnem "CMP")
       (let* ((sc   (m68k-size-code (or size :word)))
              (dn   (op-dn-num op2))
              (ea   (m68k-ea-field op1 env))
              (word (logior (ash op-code 12) (ash dn 9) (ash sc 6) ea))
              (ext  (m68k-ea-words-for-op op1 env size pc)))
         (words->bytes (list* word ext))))
      ;; <ea>, Dn (op2 = Dn) — dir=0
      ((op-is-dn-p op2)
       (let* ((sc   (m68k-size-code (or size :word)))
              (dn   (op-dn-num op2))
              (ea   (m68k-ea-field op1 env))
              (word (logior (ash op-code 12) (ash dn 9) (ash sc 6) ea))
              (ext  (m68k-ea-words-for-op op1 env size pc)))
         (words->bytes (list* word ext))))
      ;; Dn, <ea> (op1 = Dn) — dir=1
      ((op-is-dn-p op1)
       (let* ((sc   (m68k-size-code (or size :word)))
              (dn   (op-dn-num op1))
              (ea   (m68k-ea-field op2 env))
              (word (logior (ash op-code 12) (ash dn 9) (ash 1 8) (ash sc 6) ea))
              (ext  (m68k-ea-words-for-op op2 env size pc)))
         (words->bytes (list* word ext))))
      (t (error "~A : forme non reconnue ~S ~S" mnem (op-val op1) (op-val op2))))))

(defun encode-adda-suba (mnem size op1 op2 env pc)
  "Encode ADDA/SUBA <ea>, An."
  (let* ((base   (if (string= mnem "ADDA") #xD000 #x9000))
         (an     (op-an-num op2))
         (sc-bit (if (eq size :long) 1 0))
         (ea     (m68k-ea-field op1 env))
         (word   (logior base (ash an 9) (ash sc-bit 8) (ash 3 6) ea))
         (ext    (m68k-ea-words-for-op op1 env size pc)))
    (words->bytes (list* word ext))))

(defun encode-cmpa (size op1 op2 env pc)
  "Encode CMPA <ea>, An."
  (let* ((an     (op-an-num op2))
         (sc-bit (if (eq size :long) 1 0))
         (ea     (m68k-ea-field op1 env))
         (word   (logior #xB000 (ash an 9) (ash sc-bit 8) (ash 3 6) ea))
         (ext    (m68k-ea-words-for-op op1 env size pc)))
    (words->bytes (list* word ext))))

(defun encode-imm-op (mnem size op1 op2 env pc)
  "Encode ADDI/SUBI/ANDI/ORI/EORI/CMPI #n, <ea>."
  (let* ((base  (cond ((string= mnem "ADDI") #x0600)
                      ((string= mnem "SUBI") #x0400)
                      ((string= mnem "ANDI") #x0200)
                      ((string= mnem "ORI")  #x0000)
                      ((string= mnem "EORI") #x0A00)
                      ((string= mnem "CMPI") #x0C00)
                      (t (error "encode-imm-op: mnémonique inconnu ~A" mnem))))
         (sc    (m68k-size-code (or size :word)))
         (ea    (m68k-ea-field op2 env))
         (word  (logior base (ash sc 6) ea))
         (imm   (m68k-ea-imm-words op1 env (or size :word)))
         (ext   (m68k-ea-words-for-op op2 env size (+ pc 2 (* 2 (length imm))))))
    (words->bytes (list* word (append imm ext)))))

(defun encode-addq-subq (mnem size op1 op2 env pc)
  "Encode ADDQ/SUBQ #n, <ea>."
  (let* ((base (if (string= mnem "ADDQ") #x5000 #x5100))
         (n    (logand (m68k-eval! (op-val op1) env) 7))
         (sc   (m68k-size-code (or size :word)))
         (ea   (m68k-ea-field op2 env))
         (word (logior base (ash n 9) (ash sc 6) ea))
         (ext  (m68k-ea-words-for-op op2 env size pc)))
    (words->bytes (list* word ext))))

(defun m68k-shift-op-code (mnem)
  (cond
    ((string= mnem "ASL")  0) ((string= mnem "ASR")  0)
    ((string= mnem "LSL")  1) ((string= mnem "LSR")  1)
    ((string= mnem "ROXL") 2) ((string= mnem "ROXR") 2)
    ((string= mnem "ROL")  3) ((string= mnem "ROR")  3)
    (t 0)))

(defun m68k-shift-dir (mnem)
  "1=gauche, 0=droite."
  (if (member mnem '("ASL" "LSL" "ROXL" "ROL") :test #'string=) 1 0))

(defun encode-shift (mnem size op1 op2 env pc)
  "Encode ASL/ASR/LSL/LSR/ROL/ROR/ROXL/ROXR."
  (let ((op-code (m68k-shift-op-code mnem))
        (dir     (m68k-shift-dir mnem)))
    (cond
      ;; Décalage mémoire (1 opérande) : base $E0C0 + op_code<<9 + dir<<8 + EA
      ((null op2)
       (let* ((ea   (m68k-ea-field op1 env))
              (word (logior #xE0C0 (ash op-code 9) (ash dir 8) ea))
              (ext  (m68k-ea-words-for-op op1 env size pc)))
         (words->bytes (list* word ext))))
      ;; Registre par registre : ASL Dm, Dn
      ;; format : 1110 cnt d sz 1 type Dn  (bit5=1 = count in register)
      ((op-is-dn-p op1)
       (let* ((sc   (m68k-size-code (or size :word)))
              (dn   (op-dn-num op2))
              (cnt  (op-dn-num op1))
              (word (logior #xE000 (ash cnt 9) (ash dir 8) (ash sc 6)
                            (ash 1 5) (ash op-code 3) dn)))
         (words->bytes (list word))))
      ;; Décalage immédiat : ASL #n, Dn
      ;; format : 1110 nnn d sz 0 type Dn  (bit5=0 = immediate count)
      (t
       (let* ((sc   (m68k-size-code (or size :word)))
              (n    (logand (m68k-eval! (op-val op1) env) 7))
              (dn   (op-dn-num op2))
              (word (logior #xE000 (ash n 9) (ash dir 8) (ash sc 6)
                            (ash op-code 3) dn)))
         (words->bytes (list word)))))))

(defun m68k-bit-op-code (mnem)
  (cond
    ((string= mnem "BTST") 0) ((string= mnem "BCHG") 1)
    ((string= mnem "BCLR") 2) ((string= mnem "BSET") 3)
    (t 0)))

(defun encode-bit-op (mnem op1 op2 env pc)
  "Encode BTST/BCHG/BCLR/BSET."
  (let ((op-code (m68k-bit-op-code mnem)))
    (if (op-is-dn-p op1)
        ;; Dn, <ea>
        (let* ((dn   (op-dn-num op1))
               (ea   (m68k-ea-field op2 env))
               (word (logior #x0100 (ash dn 9) (ash op-code 6) ea))
               (ext  (m68k-ea-words-for-op op2 env nil pc)))
          (words->bytes (list* word ext)))
        ;; #n, <ea>
        (let* ((n    (logand (m68k-eval! (op-val op1) env) #xFF))
               (ea   (m68k-ea-field op2 env))
               (word (logior #x0800 (ash op-code 6) ea))
               (ext  (m68k-ea-words-for-op op2 env nil (+ pc 4))))
          (words->bytes (list* word n ext))))))

(defun m68k-branch-code (mnem)
  "Condition code 4 bits pour les branches."
  (cond
    ((string= mnem "BRA") #x0) ((string= mnem "BSR") #x1)
    ((string= mnem "BHI") #x2) ((string= mnem "BLS") #x3)
    ((string= mnem "BCC") #x4) ((string= mnem "BCS") #x5)
    ((string= mnem "BNE") #x6) ((string= mnem "BEQ") #x7)
    ((string= mnem "BVC") #x8) ((string= mnem "BVS") #x9)
    ((string= mnem "BPL") #xA) ((string= mnem "BMI") #xB)
    ((string= mnem "BGE") #xC) ((string= mnem "BLT") #xD)
    ((string= mnem "BGT") #xE) ((string= mnem "BLE") #xF)
    ((string= mnem "BNOT") #x6)  ; alias BNE
    (t #x0)))

(defun encode-branch (mnem size op1 env pc)
  "Encode Bcc/BRA/BSR."
  (let* ((cond-code (m68k-branch-code mnem))
         (target    (m68k-eval! (op-val op1) env))
         (base-word (logior #x6000 (ash cond-code 8))))
    (if (eq size :byte)
        ;; Branche courte : déplacement dans le byte bas du mot d'instruction
        (let ((d (- target (+ pc 2))))
          (unless (<= -128 d 127)
            (error "Branche ~A hors portée courte : ~D" mnem d))
          (words->bytes (list (logior base-word (m68k-s8 d)))))
        ;; Branche longue (.W par défaut) : mot d'instruction + mot déplacement
        (let ((d (- target (+ pc 2))))
          (unless (<= -32768 d 32767)
            (error "Branche ~A hors portée : ~D" mnem d))
          (words->bytes (list base-word (m68k-s16 d)))))))

(defun m68k-dbcc-code (mnem)
  (cond
    ((or (string= mnem "DBF") (string= mnem "DBRA")) #x1)
    ((string= mnem "DBHI") #x2) ((string= mnem "DBLS") #x3)
    ((string= mnem "DBCC") #x4) ((string= mnem "DBCS") #x5)
    ((string= mnem "DBNE") #x6) ((string= mnem "DBEQ") #x7)
    ((string= mnem "DBVC") #x8) ((string= mnem "DBVS") #x9)
    ((string= mnem "DBPL") #xA) ((string= mnem "DBMI") #xB)
    ((string= mnem "DBGE") #xC) ((string= mnem "DBLT") #xD)
    ((string= mnem "DBGT") #xE) ((string= mnem "DBLE") #xF)
    (t #x1)))

(defun encode-dbcc (mnem op1 op2 env pc)
  "Encode DBcc Dn, label."
  (let* ((cc   (m68k-dbcc-code mnem))
         (dn   (op-dn-num op1))
         (word (logior #x50C8 (ash cc 8) dn))
         (tgt  (m68k-eval! (op-val op2) env))
         (d    (- tgt (+ pc 2))))
    (words->bytes (list word (m68k-s16 d)))))

(defun m68k-scc-code (mnem)
  (let ((suffix (subseq mnem 1)))
    (cond
      ((string= suffix "T")  #x0) ((string= suffix "F")  #x1)
      ((string= suffix "HI") #x2) ((string= suffix "LS") #x3)
      ((string= suffix "CC") #x4) ((string= suffix "CS") #x5)
      ((string= suffix "NE") #x6) ((string= suffix "EQ") #x7)
      ((string= suffix "VC") #x8) ((string= suffix "VS") #x9)
      ((string= suffix "PL") #xA) ((string= suffix "MI") #xB)
      ((string= suffix "GE") #xC) ((string= suffix "LT") #xD)
      ((string= suffix "GT") #xE) ((string= suffix "LE") #xF)
      (t #x0))))

(defun encode-scc (mnem op1 env pc)
  "Encode S<cc> <ea>."
  (let* ((cc   (m68k-scc-code mnem))
         (ea   (m68k-ea-field op1 env))
         (word (logior #x50C0 (ash cc 8) ea))
         (ext  (m68k-ea-words-for-op op1 env :byte pc)))
    (words->bytes (list* word ext))))

(defun encode-jmp-jsr (mnem op1 env pc)
  "Encode JMP/JSR <ea>."
  (let* ((base (if (string= mnem "JMP") #x4EC0 #x4E80))
         (ea   (m68k-ea-field op1 env))
         (word (logior base ea))
         (ext  (m68k-ea-words-for-op op1 env nil pc)))
    (words->bytes (list* word ext))))

(defun encode-lea (op1 op2 env pc)
  "Encode LEA <ea>, An."
  (let* ((ea   (m68k-ea-field op1 env))
         (an   (op-an-num op2))
         (word (logior #x41C0 (ash an 9) ea))
         (ext  (m68k-ea-words-for-op op1 env nil pc)))
    (words->bytes (list* word ext))))

(defun encode-pea (op1 env pc)
  "Encode PEA <ea>."
  (let* ((ea   (m68k-ea-field op1 env))
         (word (logior #x4840 ea))
         (ext  (m68k-ea-words-for-op op1 env nil pc)))
    (words->bytes (list* word ext))))

(defun encode-muldiv (mnem size op1 op2 env pc)
  "Encode MULU/MULS/DIVU/DIVS <ea>, Dn."
  (let* ((base (cond ((string= mnem "MULU") #xC0C0)
                     ((string= mnem "MULS") #xC1C0)
                     ((string= mnem "DIVU") #x80C0)
                     ((string= mnem "DIVS") #x81C0)
                     (t (error "encode-muldiv: mnémonique inconnu ~A" mnem))))
         (dn   (op-dn-num op2))
         (ea   (m68k-ea-field op1 env))
         (word (logior base (ash dn 9) ea))
         (ext  (m68k-ea-words-for-op op1 env (or size :word) pc)))
    (words->bytes (list* word ext))))

(defun encode-movem (size op1 op2 env pc)
  "Encode MOVEM reglist, <ea> ou MOVEM <ea>, reglist."
  ;; Deux formes :
  ;;  MOVEM reglist, <ea>  (store) : op1=:immediate (masque), op2=<ea>
  ;;  MOVEM <ea>, reglist  (load)  : op1=<ea>, op2=:immediate (masque)
  (let* ((storing (eq (op-kind op1) :immediate))
         (ea-op   (if storing op2 op1))
         (mask-op (if storing op1 op2))
         (mask    (m68k-eval! (op-val mask-op) env))
         (ea      (m68k-ea-field ea-op env))
         (dir-bit (if storing 0 1))
         (sc-bit  (if (eq size :long) 1 0))
         (word    (logior #x4880 (ash dir-bit 10) (ash sc-bit 6) ea))
         (ext     (m68k-ea-words-for-op ea-op env size (+ pc 4))))
    (words->bytes (list* word (list (logand mask #xFFFF)) ext))))

(defun encode-ext (mnem op1 size)
  "Encode EXT/EXTB Dn. EXT.W=$4880, EXT.L=$48C0, EXTB.L=$49C0."
  (let* ((dn   (op-dn-num op1))
         (word (cond ((string= mnem "EXTB")  (logior #x49C0 dn))
                     ((eq size :long)         (logior #x48C0 dn))
                     (t                       (logior #x4880 dn)))))
    (words->bytes (list word))))

(defun encode-swap (op1)
  "Encode SWAP Dn."
  (words->bytes (list (logior #x4840 (op-dn-num op1)))))

(defun encode-exg (op1 op2)
  "Encode EXG Rn, Rn."
  (let* ((r1   (if (op-is-dn-p op1) (op-dn-num op1) (op-an-num op1)))
         (r2   (if (op-is-dn-p op2) (op-dn-num op2) (op-an-num op2)))
         (mode (cond
                 ((and (op-is-dn-p op1) (op-is-dn-p op2)) #x08) ; Dx,Dy
                 ((and (op-is-an-p op1) (op-is-an-p op2)) #x09) ; Ax,Ay
                 (t #x11)))                                       ; Dx,Ay ou Ay,Dx
         (word (logior #xC100 (ash r1 9) (ash mode 3) r2)))
    (words->bytes (list word))))

(defun encode-clr-neg-etc (mnem size op1 env pc)
  "Encode CLR/NEG/NEGX/NOT/TST <ea>."
  (let* ((base (cond ((string= mnem "CLR")  #x4200)
                     ((string= mnem "NEG")  #x4400)
                     ((string= mnem "NEGX") #x4000)
                     ((string= mnem "NOT")  #x4600)
                     ((string= mnem "TST")  #x4A00)
                     (t (error "encode-clr-neg-etc: mnémonique inconnu ~A" mnem))))
         (sc   (m68k-size-code (or size :word)))
         (ea   (m68k-ea-field op1 env))
         (word (logior base (ash sc 6) ea))
         (ext  (m68k-ea-words-for-op op1 env size pc)))
    (words->bytes (list* word ext))))

(defun encode-abcd-sbcd (mnem op1 op2)
  "Encode ABCD/SBCD Ry,Rx — op1=source(Ry), op2=destination(Rx)."
  ;; Format : 1100 Rx 1 00000 rm 0 Ry
  (let* ((base (if (string= mnem "ABCD") #xC100 #x8100))
         (rm   (if (eq (op-kind op1) :pre-decrement) 1 0))
         ;; Rx = destination = op2 ; Ry = source = op1
         (rx   (if (eq rm 1)
                   (m68k-addr-reg-num (op-val op2))
                   (op-dn-num op2)))
         (ry   (if (eq rm 1)
                   (m68k-addr-reg-num (op-val op1))
                   (op-dn-num op1)))
         (word (logior base (ash rx 9) (ash rm 3) ry)))
    (words->bytes (list word))))

(defun encode-nbcd (op1 env pc)
  "Encode NBCD <ea>."
  (let* ((ea   (m68k-ea-field op1 env))
         (word (logior #x4800 ea))
         (ext  (m68k-ea-words-for-op op1 env :byte pc)))
    (words->bytes (list* word ext))))

(defun encode-tas (op1 env pc)
  "Encode TAS <ea>."
  (let* ((ea   (m68k-ea-field op1 env))
         (word (logior #x4AC0 ea))
         (ext  (m68k-ea-words-for-op op1 env :byte pc)))
    (words->bytes (list* word ext))))

(defun encode-chk (size op1 op2 env pc)
  "Encode CHK <ea>, Dn."
  (let* ((sc-bit (if (eq size :long) 1 0))
         (dn     (op-dn-num op2))
         (ea     (m68k-ea-field op1 env))
         (word   (logior #x4000 (ash dn 9) (ash (if (zerop sc-bit) 6 4) 7) ea))
         (ext    (m68k-ea-words-for-op op1 env size pc)))
    (words->bytes (list* word ext))))

(defun encode-link (op1 op2 env)
  "Encode LINK An, #d."
  (let* ((an   (op-an-num op1))
         (d    (m68k-eval! (op-val op2) env))
         (word (logior #x4E50 an)))
    (words->bytes (list word (m68k-s16 d)))))

(defun encode-unlk (op1)
  "Encode UNLK An."
  (words->bytes (list (logior #x4E58 (op-an-num op1)))))

(defun encode-trap (op1 env)
  "Encode TRAP #n."
  (let ((n (logand (m68k-eval! (op-val op1) env) #xF)))
    (words->bytes (list (logior #x4E40 n)))))


;;; --------------------------------------------------------------------------
;;;  Encodeur principal
;;; --------------------------------------------------------------------------

(defun encode-m68k (mnem size ops env pc)
  "Encode une instruction M68K. Retourne une liste d'octets."
  (let ((op1 (first ops))
        (op2 (second ops)))
    (cond

      ;; --- Implied ---
      ((string= mnem "NOP")     (list #x4E #x71))
      ((string= mnem "RTS")     (list #x4E #x75))
      ((string= mnem "RTR")     (list #x4E #x77))
      ((string= mnem "RTE")     (list #x4E #x73))
      ((string= mnem "TRAPV")   (list #x4E #x76))
      ((string= mnem "RESET")   (list #x4E #x70))
      ((string= mnem "ILLEGAL") (list #x4A #xFC))
      ((string= mnem "STOP")
       ;; STOP #n
       (let ((n (m68k-eval! (op-val op1) env)))
         (words->bytes (list #x4E72 (m68k-s16 n)))))

      ;; --- MOVE ---
      ((string= mnem "MOVE")
       (if (op-is-an-p op2)
           (encode-movea size op1 op2 env pc)
           (encode-move size op1 op2 env pc)))
      ((string= mnem "MOVEA")  (encode-movea size op1 op2 env pc))
      ((string= mnem "MOVEQ")  (encode-moveq op1 op2 env))
      ((string= mnem "MOVEM")  (encode-movem size op1 op2 env pc))

      ;; --- ADD ---
      ((string= mnem "ADD")
       (if (op-is-an-p op2)
           (encode-adda-suba "ADDA" size op1 op2 env pc)
           (encode-alu-dn mnem size op1 op2 env pc)))
      ((string= mnem "ADDA")  (encode-adda-suba "ADDA" size op1 op2 env pc))
      ((string= mnem "ADDI")  (encode-imm-op mnem size op1 op2 env pc))
      ((string= mnem "ADDQ")  (encode-addq-subq mnem size op1 op2 env pc))
      ((string= mnem "ADDX")
       ;; ADDX Dy,Dx ou ADDX -(Ay),-(Ax)
       (let* ((rm   (if (eq (op-kind op1) :pre-decrement) 1 0))
              (ry   (if (eq rm 1) (m68k-addr-reg-num (op-val op1))
                        (op-dn-num op1)))
              (rx   (if (eq rm 1) (m68k-addr-reg-num (op-val op2))
                        (op-dn-num op2)))
              (sc   (m68k-size-code (or size :word)))
              (word (logior #xD100 (ash rx 9) (ash sc 6) (ash rm 3) ry)))
         (words->bytes (list word))))

      ;; --- SUB ---
      ((string= mnem "SUB")
       (if (op-is-an-p op2)
           (encode-adda-suba "SUBA" size op1 op2 env pc)
           (encode-alu-dn mnem size op1 op2 env pc)))
      ((string= mnem "SUBA")  (encode-adda-suba "SUBA" size op1 op2 env pc))
      ((string= mnem "SUBI")  (encode-imm-op mnem size op1 op2 env pc))
      ((string= mnem "SUBQ")  (encode-addq-subq mnem size op1 op2 env pc))
      ((string= mnem "SUBX")
       (let* ((rm   (if (eq (op-kind op1) :pre-decrement) 1 0))
              (ry   (if (eq rm 1) (m68k-addr-reg-num (op-val op1))
                        (op-dn-num op1)))
              (rx   (if (eq rm 1) (m68k-addr-reg-num (op-val op2))
                        (op-dn-num op2)))
              (sc   (m68k-size-code (or size :word)))
              (word (logior #x9100 (ash rx 9) (ash sc 6) (ash rm 3) ry)))
         (words->bytes (list word))))

      ;; --- AND / OR / EOR ---
      ;; AND/OR acceptent EA=immédiat directement (opcode $C/$8 avec mode 7/4).
      ;; EOR n'a pas de forme <ea>→Dn : EOR #imm est un alias pour EORI.
      ((string= mnem "AND")  (encode-alu-dn mnem size op1 op2 env pc))
      ((string= mnem "ANDI") (encode-imm-op mnem size op1 op2 env pc))
      ((string= mnem "OR")   (encode-alu-dn mnem size op1 op2 env pc))
      ((string= mnem "ORI")  (encode-imm-op mnem size op1 op2 env pc))
      ((string= mnem "EOR")  (if (eq (op-kind op1) :immediate)
                                 (encode-imm-op "EORI" size op1 op2 env pc)
                                 (encode-alu-dn mnem size op1 op2 env pc)))
      ((string= mnem "EORI") (encode-imm-op mnem size op1 op2 env pc))

      ;; --- CMP ---
      ((string= mnem "CMP")
       (if (op-is-an-p op2)
           (encode-cmpa size op1 op2 env pc)
           (encode-alu-dn mnem size op1 op2 env pc)))
      ((string= mnem "CMPA")  (encode-cmpa size op1 op2 env pc))
      ((string= mnem "CMPI")  (encode-imm-op mnem size op1 op2 env pc))
      ((string= mnem "CMPM")
       ;; CMPM (Ay)+, (Ax)+
       (let* ((ay   (m68k-addr-reg-num (op-val op1)))
              (ax   (m68k-addr-reg-num (op-val op2)))
              (sc   (m68k-size-code (or size :word)))
              (word (logior #xB108 (ash ax 9) (ash sc 6) ay)))
         (words->bytes (list word))))

      ;; --- MUL / DIV ---
      ((string= mnem "MULU") (encode-muldiv mnem size op1 op2 env pc))
      ((string= mnem "MULS") (encode-muldiv mnem size op1 op2 env pc))
      ((string= mnem "DIVU") (encode-muldiv mnem size op1 op2 env pc))
      ((string= mnem "DIVS") (encode-muldiv mnem size op1 op2 env pc))

      ;; --- Bit ops ---
      ((member mnem '("BTST" "BCHG" "BCLR" "BSET") :test #'string=)
       (encode-bit-op mnem op1 op2 env pc))

      ;; --- Shifts / Rotations ---
      ((member mnem '("ASL" "ASR" "LSL" "LSR" "ROL" "ROR" "ROXL" "ROXR")
               :test #'string=)
       (encode-shift mnem size op1 op2 env pc))

      ;; --- Branches ---
      ((member mnem '("BRA" "BSR" "BEQ" "BNE" "BLT" "BGT" "BLE" "BGE"
                      "BCC" "BCS" "BMI" "BPL" "BVC" "BVS" "BHI" "BLS"
                      "BNOT")
               :test #'string=)
       (encode-branch mnem size op1 env pc))

      ;; --- DBcc ---
      ((member mnem '("DBF" "DBRA" "DBEQ" "DBNE" "DBLT" "DBGT" "DBLE"
                      "DBGE" "DBCC" "DBCS" "DBMI" "DBPL" "DBVC" "DBVS"
                      "DBHI" "DBLS")
               :test #'string=)
       (encode-dbcc mnem op1 op2 env pc))

      ;; --- Scc ---
      ((and (>= (length mnem) 2) (char= (char mnem 0) #\S)
            (member (subseq mnem 1)
                    '("T" "F" "HI" "LS" "CC" "CS" "NE" "EQ"
                      "VC" "VS" "PL" "MI" "GE" "LT" "GT" "LE")
                    :test #'string=))
       (encode-scc mnem op1 env pc))

      ;; --- JMP / JSR ---
      ((string= mnem "JMP") (encode-jmp-jsr mnem op1 env pc))
      ((string= mnem "JSR") (encode-jmp-jsr mnem op1 env pc))

      ;; --- LEA / PEA ---
      ((string= mnem "LEA") (encode-lea op1 op2 env pc))
      ((string= mnem "PEA") (encode-pea op1 env pc))

      ;; --- MOVE à SR/CCR ---

      ;; --- Unary ---
      ((string= mnem "CLR")  (encode-clr-neg-etc mnem size op1 env pc))
      ((string= mnem "NEG")  (encode-clr-neg-etc mnem size op1 env pc))
      ((string= mnem "NEGX") (encode-clr-neg-etc mnem size op1 env pc))
      ((string= mnem "NOT")  (encode-clr-neg-etc mnem size op1 env pc))
      ((string= mnem "TST")  (encode-clr-neg-etc mnem size op1 env pc))
      ((string= mnem "EXT")  (encode-ext mnem op1 size))
      ((string= mnem "EXTB") (encode-ext mnem op1 size))
      ((string= mnem "SWAP") (encode-swap op1))
      ((string= mnem "TAS")  (encode-tas op1 env pc))
      ((string= mnem "NBCD") (encode-nbcd op1 env pc))

      ;; --- BCD ---
      ((string= mnem "ABCD") (encode-abcd-sbcd mnem op1 op2))
      ((string= mnem "SBCD") (encode-abcd-sbcd mnem op1 op2))

      ;; --- EXG ---
      ((string= mnem "EXG") (encode-exg op1 op2))

      ;; --- CHK ---
      ((string= mnem "CHK") (encode-chk size op1 op2 env pc))

      ;; --- LINK / UNLK ---
      ((string= mnem "LINK")  (encode-link op1 op2 env))
      ((string= mnem "UNLK")  (encode-unlk op1))

      ;; --- TRAP ---
      ((string= mnem "TRAP") (encode-trap op1 env))

      ;; --- DC / DS / ORG (directives traitées ailleurs) ---
      (t (error "Mnémonique M68K inconnu : ~A" mnem)))))


;;; --------------------------------------------------------------------------
;;;  Assemblage deux passes
;;; --------------------------------------------------------------------------

(defun m68k-eval-expr (expr env)
  (cl-asm/expression:eval-expr expr env))

(defun m68k-directive-pass1 (name args env pc symtable)
  "Traite une directive en passe 1. Retourne le nouveau PC."
  (case name
    (:org
     (multiple-value-bind (val ok)
         (m68k-eval-expr (first args) env)
       (if ok val pc)))
    (:equ
     (let ((sym-name (first args))
           (expr     (second args)))
       (multiple-value-bind (val ok)
           (m68k-eval-expr expr env)
         (when ok
           (cl-asm/symbol-table:define-constant symtable sym-name val)))
       pc))
    (:byte  (+ pc (length args)))
    (:word  (+ pc (* 2 (length args))))
    (:long  (+ pc (* 4 (length args))))
    (:dword (+ pc (* 4 (length args))))
    (:fill
     (multiple-value-bind (n ok)
         (m68k-eval-expr (first args) env)
       (if ok (+ pc n) pc)))
    (otherwise pc)))

(defun pass-1-m68k (program symtable &key (origin 0))
  "Passe 1 : enregistre les labels, estime les tailles."
  (let ((pc origin))
    (dolist (section (cl-asm/ir:ir-program-sections program))
      (dolist (node (cl-asm/ir:ir-section-nodes section))
        (typecase node
          (cl-asm/ir:ir-label
           (setf (cl-asm/symbol-table:st-current-pc symtable) pc)
           (cl-asm/symbol-table:define-label
            symtable
            (cl-asm/ir:ir-label-name node)
            :source-loc (cl-asm/ir:ir-label-loc node)))
          (cl-asm/ir:ir-directive
           (let ((env (cl-asm/expression:make-env
                       :symbol-table symtable :pc pc)))
             (setf pc (m68k-directive-pass1
                       (cl-asm/ir:ir-directive-name node)
                       (cl-asm/ir:ir-directive-args node)
                       env pc symtable))))
          (cl-asm/ir:ir-instruction
           (let* ((mnem (string-upcase
                         (cl-asm/ir:ir-instruction-mnemonic node)))
                  (sz   (cl-asm/ir:ir-instruction-size node))
                  (ops  (cl-asm/ir:ir-instruction-operands node)))
             (incf pc (m68k-estimate-size mnem sz ops)))))))
    pc))

(defun m68k-directive-pass2 (name args env pc result)
  "Traite une directive en passe 2."
  (case name
    (:org
     (multiple-value-bind (val ok)
         (m68k-eval-expr (first args) env)
       (if ok val pc)))
    (:equ pc)
    (:section pc)
    (:global  pc)
    (:extern  pc)
    (:byte
     (dolist (arg args)
       (multiple-value-bind (val ok)
           (m68k-eval-expr arg env)
         (vector-push-extend (logand (if ok val 0) #xFF) result)
         (incf pc)))
     pc)
    (:word
     (dolist (arg args)
       (multiple-value-bind (val ok)
           (m68k-eval-expr arg env)
         (let ((w (if ok val 0)))
           ;; big-endian
           (vector-push-extend (logand (ash w -8) #xFF) result)
           (vector-push-extend (logand w #xFF) result)
           (incf pc 2))))
     pc)
    ((:long :dword)
     (dolist (arg args)
       (multiple-value-bind (val ok)
           (m68k-eval-expr arg env)
         (let ((d (if ok val 0)))
           (vector-push-extend (logand (ash d -24) #xFF) result)
           (vector-push-extend (logand (ash d -16) #xFF) result)
           (vector-push-extend (logand (ash d  -8) #xFF) result)
           (vector-push-extend (logand d #xFF) result)
           (incf pc 4))))
     pc)
    (:fill
     (multiple-value-bind (count ok-n)
         (m68k-eval-expr (first args) env)
       (let ((fill-val (if (second args)
                           (multiple-value-bind (v ok)
                               (m68k-eval-expr (second args) env)
                             (if ok (logand v #xFF) 0))
                           0)))
         (when ok-n
           (dotimes (_ count)
             (vector-push-extend fill-val result)
             (incf pc)))))
     pc)
    (otherwise pc)))

(defun pass-2-m68k (program symtable &key (origin 0))
  "Passe 2 : encode toutes les instructions."
  (let ((result (make-array 0 :element-type '(unsigned-byte 8)
                              :adjustable t :fill-pointer 0))
        (pc origin))
    (dolist (section (cl-asm/ir:ir-program-sections program))
      (dolist (node (cl-asm/ir:ir-section-nodes section))
        (typecase node
          (cl-asm/ir:ir-directive
           (let ((env (cl-asm/expression:make-env
                       :symbol-table symtable :pc pc)))
             (setf pc (m68k-directive-pass2
                       (cl-asm/ir:ir-directive-name node)
                       (cl-asm/ir:ir-directive-args node)
                       env pc result))))
          (cl-asm/ir:ir-instruction
           (let* ((mnem (string-upcase
                         (cl-asm/ir:ir-instruction-mnemonic node)))
                  (sz   (cl-asm/ir:ir-instruction-size node))
                  (ops  (cl-asm/ir:ir-instruction-operands node))
                  (env  (cl-asm/expression:make-env
                         :symbol-table symtable :pc pc))
                  (bytes (encode-m68k mnem sz ops env pc)))
             (dolist (b bytes) (vector-push-extend b result))
             (incf pc (length bytes))))
          (cl-asm/ir:ir-label nil))))
    result))


;;; --------------------------------------------------------------------------
;;;  API publique
;;; --------------------------------------------------------------------------

(defun assemble-m68k (program &key (origin 0))
  "Assemble un IR-PROGRAM M68K. Retourne un vecteur d'octets."
  (let ((sym (cl-asm/symbol-table:make-symbol-table)))
    (pass-1-m68k program sym :origin origin)
    (cl-asm/symbol-table:begin-pass-2 sym)
    (pass-2-m68k program sym :origin origin)))

(defun assemble-string-m68k (source &key (origin 0))
  "Assemble une chaîne source M68K. Retourne un vecteur d'octets."
  (let* ((cl-asm/parser:*m68k-mode* t)
         (prog (cl-asm/parser:parse-string source)))
    (assemble-m68k prog :origin origin)))

(defun assemble-file-m68k (path &key (origin 0))
  "Assemble le fichier PATH M68K. Retourne un vecteur d'octets."
  (let* ((cl-asm/parser:*m68k-mode* t)
         (prog (cl-asm/parser:parse-file path)))
    (assemble-m68k prog :origin origin)))


;;; --------------------------------------------------------------------------
;;;  Enregistrement du backend
;;; --------------------------------------------------------------------------

(cl-asm/backends:register-backend
 :m68k
 '("m68k" "68000" "68k" "amiga" "atari" "mac68k" "atarist")
 'cl-asm/backend.m68k
 'assemble-file-m68k
 "M68K (Motorola 68000 — Amiga, Atari ST, Mac 68k)"
 "M68K (Motorola 68000 — Amiga, Atari ST, Mac 68k)")
