; -*- coding: utf-8 -*-
;;;; src/backend/z80.lisp
;;;;
;;;; Backend Z80 pour cl-asm.
;;;; Supporte le jeu d'instructions Zilog Z80 (ZX Spectrum, MSX, CPC…).
;;;;
;;;; Préfixes :
;;;;   $CB — rotations, shifts, BIT/SET/RES
;;;;   $DD — instructions avec IX
;;;;   $ED — instructions étendues (IN, OUT, block moves…)
;;;;   $FD — instructions avec IY
;;;;   $DD $CB / $FD $CB — BIT/SET/RES avec (IX+d) / (IY+d)

(defpackage #:cl-asm/backend.z80
  (:use #:cl)
  (:export
   #:assemble-z80
   #:assemble-string-z80
   #:assemble-file-z80))

(in-package #:cl-asm/backend.z80)

;;; Déclarations forward
(declaim (ftype (function (t t t) t) encode-z80-ld))
(declaim (ftype (function (t t) t) estimate-z80-ld-size))
(declaim (ftype (function (t t t t t) t) z80-directive-pass1))
(declaim (ftype (function (t t t t t) t) z80-directive-pass2))


;;; --------------------------------------------------------------------------
;;;  Tables de registres
;;; --------------------------------------------------------------------------

(defun z80-reg8-code (s)
  "Code binaire 3 bits du registre 8 bits (B=0 C=1 D=2 E=3 H=4 L=5 (HL)=6 A=7).
   Retourne NIL si S n'est pas un registre 8 bits standard."
  (position (string-upcase s)
            #("B" "C" "D" "E" "H" "L" "(HL)" "A") :test #'string=))

(defun z80-reg16-code (s)
  "Code 2 bits du registre 16 bits (BC=0 DE=1 HL=2 SP=3). NIL si inconnu."
  (position (string-upcase s) #("BC" "DE" "HL" "SP") :test #'string=))

(defun z80-reg16af-code (s)
  "Code 2 bits pour PUSH/POP (BC=0 DE=1 HL=2 AF=3). NIL si inconnu."
  (position (string-upcase s) #("BC" "DE" "HL" "AF") :test #'string=))

(defun z80-cond-code (s)
  "Code 3 bits de la condition (NZ=0 Z=1 NC=2 C=3 PO=4 PE=5 P=6 M=7). NIL si inconnu."
  (position (string-upcase s)
            #("NZ" "Z" "NC" "C" "PO" "PE" "P" "M") :test #'string=))

(defun z80-jr-cond-code (s)
  "Code 2 bits pour JR (NZ=0 Z=1 NC=2 C=3). NIL si inconnu."
  (position (string-upcase s) #("NZ" "Z" "NC" "C") :test #'string=))


;;; --------------------------------------------------------------------------
;;;  Helpers sur les opérandes IR
;;; --------------------------------------------------------------------------

;;; Un opérande Z80 peut être :
;;;   (:direct "A")              — registre ou symbole
;;;   (:direct 42)               — valeur numérique
;;;   (:immediate 42)            — valeur immédiate explicite (avec #)
;;;   (:indirect "HL")           — (HL)
;;;   (:indirect (:+ "IX" d))    — (IX+d)
;;;   (:indirect 0x1234)         — (nn) indirect mémoire

(defun op-kind (op) (cl-asm/ir:ir-operand-kind op))
(defun op-val  (op) (cl-asm/ir:ir-operand-value op))

(defun op-is-named-str (op name)
  "Vrai si l'opérande est :direct avec la chaîne NAME (insensible à la casse)."
  (and (eq (op-kind op) :direct)
       (stringp (op-val op))
       (string= (string-upcase (op-val op)) (string-upcase name))))

(defun op-is-reg8-p (op)
  "Vrai si l'opérande est un registre 8 bits simple (pas (HL))."
  (and (eq (op-kind op) :direct)
       (stringp (op-val op))
       (let ((code (z80-reg8-code (op-val op))))
         (and code (not (= code 6))))))   ; code 6 = (HL)

(defun op-is-a-p (op) (op-is-named-str op "A"))

(defun op-reg8-code (op) (z80-reg8-code (op-val op)))

(defun op-is-reg16-p (op)
  (and (eq (op-kind op) :direct)
       (stringp (op-val op))
       (z80-reg16-code (op-val op))
       t))

(defun op-reg16-code (op) (z80-reg16-code (op-val op)))

(defun op-is-hl-indirect-p (op)
  "Vrai si l'opérande est (HL)."
  (or (and (eq (op-kind op) :indirect)
           (stringp (op-val op))
           (string= (string-upcase (op-val op)) "HL"))
      (and (eq (op-kind op) :direct)
           (stringp (op-val op))
           (string= (string-upcase (op-val op)) "(HL)"))))

(defun op-is-ix-indexed-p (op)
  "Vrai si l'opérande est (IX+d)."
  (and (eq (op-kind op) :indirect)
       (listp (op-val op))
       (eq (first (op-val op)) :+)
       (stringp (second (op-val op)))
       (string= (string-upcase (second (op-val op))) "IX")))

(defun op-is-iy-indexed-p (op)
  "Vrai si l'opérande est (IY+d)."
  (and (eq (op-kind op) :indirect)
       (listp (op-val op))
       (eq (first (op-val op)) :+)
       (stringp (second (op-val op)))
       (string= (string-upcase (second (op-val op))) "IY")))

(defun op-is-ix-p (op) (op-is-named-str op "IX"))
(defun op-is-iy-p (op) (op-is-named-str op "IY"))
(defun op-is-sp-p (op) (op-is-named-str op "SP"))
(defun op-is-hl-p (op) (op-is-named-str op "HL"))
(defun op-is-de-p (op) (op-is-named-str op "DE"))
(defun op-is-bc-p (op) (op-is-named-str op "BC"))

(defun op-is-af-p (op) (op-is-named-str op "AF"))
(defun op-is-af2-p (op) (op-is-named-str op "AF'"))

(defun op-is-c-indirect-p (op)
  "Vrai si l'opérande est (C) — port C pour IN/OUT."
  (and (eq (op-kind op) :indirect)
       (stringp (op-val op))
       (string= (string-upcase (op-val op)) "C")))

(defun op-is-sp-indirect-p (op)
  "(SP) pour EX (SP), ..."
  (and (eq (op-kind op) :indirect)
       (stringp (op-val op))
       (string= (string-upcase (op-val op)) "SP")))

(defun op-is-cond-p (op)
  (and (eq (op-kind op) :direct)
       (stringp (op-val op))
       (z80-cond-code (op-val op))
       t))

(defun op-is-jr-cond-p (op)
  (and (eq (op-kind op) :direct)
       (stringp (op-val op))
       (z80-jr-cond-code (op-val op))
       t))

(defun op-is-imm-p (op)
  "Vrai si l'opérande est une valeur immédiate (nombre, expr ou #n)."
  (or (eq (op-kind op) :immediate)
      (and (eq (op-kind op) :direct)
           (not (stringp (op-val op))))))

(defun op-is-mem-indirect-p (op)
  "Vrai si l'opérande est (nn) — adresse mémoire indirecte (pas un registre)."
  (and (eq (op-kind op) :indirect)
       ;; exclure les registres connus
       (not (and (stringp (op-val op))
                 (or (z80-reg16-code (op-val op))
                     (string= (string-upcase (op-val op)) "C")
                     (string= (string-upcase (op-val op)) "SP"))))
       ;; exclure (IX+d) / (IY+d)
       (not (and (listp (op-val op))
                 (eq (first (op-val op)) :+)))))


;;; --------------------------------------------------------------------------
;;;  Évaluation des expressions
;;; --------------------------------------------------------------------------

(defun z80-eval-expr (expr env)
  "Évalue EXPR dans ENV. Retourne (values val resolved-p)."
  (cl-asm/expression:eval-expr expr env))

(defun z80-eval (expr env)
  "Évalue EXPR dans ENV et retourne la valeur. Erreur si non résolue."
  (multiple-value-bind (val ok)
      (z80-eval-expr expr env)
    (if ok val (error "Expression Z80 non résolue : ~S" expr))))

(defun z80-disp-val (op env)
  "Déplacement d'un (IX+d) ou (IY+d). Retourne l'offset évalué."
  (z80-eval (third (op-val op)) env))

(defun z80-imm-val (op env)
  "Valeur numérique d'un opérande immédiat."
  (z80-eval (op-val op) env))


;;; --------------------------------------------------------------------------
;;;  Encodage bas niveau
;;; --------------------------------------------------------------------------

(defun z80-byte (val)  (logand val #xFF))
(defun z80-word-lo (val) (logand val #xFF))
(defun z80-word-hi (val) (logand (ash val -8) #xFF))

(defun z80-signed-byte (val)
  "Tronque à 8 bits signé → représentation unsigned."
  (logand (if (< val 0) (+ val 256) val) #xFF))

(defun z80-rel (target pc)
  "Calcule le déplacement relatif signé 8 bits pour JR/DJNZ.
   Offset = target − (PC + 2)."
  (let ((offset (- target (+ pc 2))))
    (unless (<= -128 offset 127)
      (error "Branche relative hors portée : offset ~D (target=$~X, pc=$~X)"
             offset target pc))
    (z80-signed-byte offset)))


;;; --------------------------------------------------------------------------
;;;  Encodeur principal
;;; --------------------------------------------------------------------------

(defun encode-z80 (mnem-up ops env pc)
  "Encode une instruction Z80. Retourne une liste d'octets."
  (let ((op1 (first ops))
        (op2 (second ops)))
    (flet ((e1  () (z80-eval (op-val op1) env))
           (e2  () (z80-eval (op-val op2) env))
           (d1  () (z80-disp-val op1 env))
           (d2  () (z80-disp-val op2 env)))
      (cond

        ;; ----------------------------------------------------------------
        ;; Implied (1 octet)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "NOP")  '(#x00))
        ((string= mnem-up "HALT") '(#x76))
        ((string= mnem-up "DI")   '(#xF3))
        ((string= mnem-up "EI")   '(#xFB))
        ((string= mnem-up "EXX")  '(#xD9))
        ((string= mnem-up "DAA")  '(#x27))
        ((string= mnem-up "CPL")  '(#x2F))
        ((string= mnem-up "CCF")  '(#x3F))
        ((string= mnem-up "SCF")  '(#x37))
        ((string= mnem-up "RLCA") '(#x07))
        ((string= mnem-up "RRCA") '(#x0F))
        ((string= mnem-up "RLA")  '(#x17))
        ((string= mnem-up "RRA")  '(#x1F))

        ;; ----------------------------------------------------------------
        ;; ED prefix 2 octets
        ;; ----------------------------------------------------------------
        ((string= mnem-up "NEG")  '(#xED #x44))
        ((string= mnem-up "RLD")  '(#xED #x6F))
        ((string= mnem-up "RRD")  '(#xED #x67))
        ((string= mnem-up "RETN") '(#xED #x45))
        ((string= mnem-up "RETI") '(#xED #x4D))

        ;; ----------------------------------------------------------------
        ;; Block operations
        ;; ----------------------------------------------------------------
        ((string= mnem-up "LDI")  '(#xED #xA0))
        ((string= mnem-up "LDIR") '(#xED #xB0))
        ((string= mnem-up "LDD")  '(#xED #xA8))
        ((string= mnem-up "LDDR") '(#xED #xB8))
        ((string= mnem-up "CPI")  '(#xED #xA1))
        ((string= mnem-up "CPIR") '(#xED #xB1))
        ((string= mnem-up "CPD")  '(#xED #xA9))
        ((string= mnem-up "CPDR") '(#xED #xB9))
        ((string= mnem-up "INI")  '(#xED #xA2))
        ((string= mnem-up "INIR") '(#xED #xB2))
        ((string= mnem-up "IND")  '(#xED #xAA))
        ((string= mnem-up "INDR") '(#xED #xBA))
        ((string= mnem-up "OUTI") '(#xED #xA3))
        ((string= mnem-up "OTIR") '(#xED #xB3))
        ((string= mnem-up "OUTD") '(#xED #xAB))
        ((string= mnem-up "OTDR") '(#xED #xBB))

        ;; ----------------------------------------------------------------
        ;; IM 0/1/2
        ;; ----------------------------------------------------------------
        ((string= mnem-up "IM")
         (case (e1)
           (0 '(#xED #x46))
           (1 '(#xED #x56))
           (2 '(#xED #x5E))
           (t (error "IM ~D inconnu" (e1)))))

        ;; ----------------------------------------------------------------
        ;; EX
        ;; ----------------------------------------------------------------
        ((string= mnem-up "EX")
         (cond
           ((and (op-is-de-p op1) (op-is-hl-p op2))   '(#xEB))
           ((and (op-is-af-p op1) (op-is-af2-p op2))  '(#x08))
           ((op-is-sp-indirect-p op1)
            (cond ((op-is-hl-p op2) '(#xE3))
                  ((op-is-ix-p op2) '(#xDD #xE3))
                  ((op-is-iy-p op2) '(#xFD #xE3))
                  (t (error "EX (SP), ? invalide"))))
           (t (error "EX opérandes invalides"))))

        ;; ----------------------------------------------------------------
        ;; PUSH / POP
        ;; ----------------------------------------------------------------
        ((or (string= mnem-up "PUSH") (string= mnem-up "POP"))
         (let ((base (if (string= mnem-up "PUSH") #xC5 #xC1))
               (idx  (if (string= mnem-up "PUSH") #xE5 #xE1)))
           (cond
             ((op-is-ix-p op1) (list #xDD idx))
             ((op-is-iy-p op1) (list #xFD idx))
             ((and (eq (op-kind op1) :direct)
                   (stringp (op-val op1))
                   (z80-reg16af-code (op-val op1)))
              (list (+ base (* (z80-reg16af-code (op-val op1)) 16))))
             (t (error "~A opérande invalide" mnem-up)))))

        ;; ----------------------------------------------------------------
        ;; INC / DEC
        ;; ----------------------------------------------------------------
        ((or (string= mnem-up "INC") (string= mnem-up "DEC"))
         (let ((is-inc (string= mnem-up "INC")))
           (cond
             ((op-is-reg8-p op1)
              (list (+ (if is-inc #x04 #x05) (* (op-reg8-code op1) 8))))
             ((op-is-hl-indirect-p op1)
              (list (if is-inc #x34 #x35)))
             ((op-is-reg16-p op1)
              (list (+ (if is-inc #x03 #x0B) (* (op-reg16-code op1) 16))))
             ((op-is-ix-p op1)  (list #xDD (if is-inc #x23 #x2B)))
             ((op-is-iy-p op1)  (list #xFD (if is-inc #x23 #x2B)))
             ((op-is-ix-indexed-p op1)
              (list #xDD (if is-inc #x34 #x35) (z80-signed-byte (d1))))
             ((op-is-iy-indexed-p op1)
              (list #xFD (if is-inc #x34 #x35) (z80-signed-byte (d1))))
             (t (error "~A opérande invalide" mnem-up)))))

        ;; ----------------------------------------------------------------
        ;; ADD
        ;; ----------------------------------------------------------------
        ((string= mnem-up "ADD")
         (cond
           ((and (op-is-a-p op1) (op-is-reg8-p op2))
            (list (+ #x80 (op-reg8-code op2))))
           ((and (op-is-a-p op1) (op-is-hl-indirect-p op2)) '(#x86))
           ((and (op-is-a-p op1) (op-is-ix-indexed-p op2))
            (list #xDD #x86 (z80-signed-byte (d2))))
           ((and (op-is-a-p op1) (op-is-iy-indexed-p op2))
            (list #xFD #x86 (z80-signed-byte (d2))))
           ((and (op-is-a-p op1) (op-is-imm-p op2))
            (list #xC6 (z80-byte (e2))))
           ((and (op-is-hl-p op1) (op-is-reg16-p op2))
            (list (+ #x09 (* (op-reg16-code op2) 16))))
           ((op-is-ix-p op1)
            (let ((rr (cond ((op-is-bc-p op2) 0) ((op-is-de-p op2) 1)
                            ((op-is-ix-p op2) 2) ((op-is-sp-p op2) 3)
                            (t (error "ADD IX, ? invalide")))))
              (list #xDD (+ #x09 (* rr 16)))))
           ((op-is-iy-p op1)
            (let ((rr (cond ((op-is-bc-p op2) 0) ((op-is-de-p op2) 1)
                            ((op-is-iy-p op2) 2) ((op-is-sp-p op2) 3)
                            (t (error "ADD IY, ? invalide")))))
              (list #xFD (+ #x09 (* rr 16)))))
           (t (error "ADD opérandes invalides"))))

        ;; ----------------------------------------------------------------
        ;; ADC
        ;; ----------------------------------------------------------------
        ((string= mnem-up "ADC")
         (cond
           ((and (op-is-a-p op1) (op-is-reg8-p op2))
            (list (+ #x88 (op-reg8-code op2))))
           ((and (op-is-a-p op1) (op-is-hl-indirect-p op2)) '(#x8E))
           ((and (op-is-a-p op1) (op-is-ix-indexed-p op2))
            (list #xDD #x8E (z80-signed-byte (d2))))
           ((and (op-is-a-p op1) (op-is-iy-indexed-p op2))
            (list #xFD #x8E (z80-signed-byte (d2))))
           ((and (op-is-a-p op1) (op-is-imm-p op2))
            (list #xCE (z80-byte (e2))))
           ((and (op-is-hl-p op1) (op-is-reg16-p op2))
            (list #xED (+ #x4A (* (op-reg16-code op2) 16))))
           (t (error "ADC opérandes invalides"))))

        ;; ----------------------------------------------------------------
        ;; SUB
        ;; ----------------------------------------------------------------
        ((string= mnem-up "SUB")
         (cond
           ((op-is-reg8-p op1)         (list (+ #x90 (op-reg8-code op1))))
           ((op-is-hl-indirect-p op1)  '(#x96))
           ((op-is-ix-indexed-p op1)   (list #xDD #x96 (z80-signed-byte (d1))))
           ((op-is-iy-indexed-p op1)   (list #xFD #x96 (z80-signed-byte (d1))))
           ((op-is-imm-p op1)          (list #xD6 (z80-byte (e1))))
           (t (error "SUB opérande invalide"))))

        ;; ----------------------------------------------------------------
        ;; SBC
        ;; ----------------------------------------------------------------
        ((string= mnem-up "SBC")
         (cond
           ((and (op-is-a-p op1) (op-is-reg8-p op2))
            (list (+ #x98 (op-reg8-code op2))))
           ((and (op-is-a-p op1) (op-is-hl-indirect-p op2)) '(#x9E))
           ((and (op-is-a-p op1) (op-is-ix-indexed-p op2))
            (list #xDD #x9E (z80-signed-byte (d2))))
           ((and (op-is-a-p op1) (op-is-iy-indexed-p op2))
            (list #xFD #x9E (z80-signed-byte (d2))))
           ((and (op-is-a-p op1) (op-is-imm-p op2))
            (list #xDE (z80-byte (e2))))
           ((and (op-is-hl-p op1) (op-is-reg16-p op2))
            (list #xED (+ #x42 (* (op-reg16-code op2) 16))))
           (t (error "SBC opérandes invalides"))))

        ;; ----------------------------------------------------------------
        ;; AND / OR / XOR / CP
        ;; ----------------------------------------------------------------
        ((string= mnem-up "AND")
         (cond
           ((op-is-reg8-p op1)        (list (+ #xA0 (op-reg8-code op1))))
           ((op-is-hl-indirect-p op1) '(#xA6))
           ((op-is-ix-indexed-p op1)  (list #xDD #xA6 (z80-signed-byte (d1))))
           ((op-is-iy-indexed-p op1)  (list #xFD #xA6 (z80-signed-byte (d1))))
           ((op-is-imm-p op1)         (list #xE6 (z80-byte (e1))))
           (t (error "AND opérande invalide"))))

        ((string= mnem-up "OR")
         (cond
           ((op-is-reg8-p op1)        (list (+ #xB0 (op-reg8-code op1))))
           ((op-is-hl-indirect-p op1) '(#xB6))
           ((op-is-ix-indexed-p op1)  (list #xDD #xB6 (z80-signed-byte (d1))))
           ((op-is-iy-indexed-p op1)  (list #xFD #xB6 (z80-signed-byte (d1))))
           ((op-is-imm-p op1)         (list #xF6 (z80-byte (e1))))
           (t (error "OR opérande invalide"))))

        ((string= mnem-up "XOR")
         (cond
           ((op-is-reg8-p op1)        (list (+ #xA8 (op-reg8-code op1))))
           ((op-is-hl-indirect-p op1) '(#xAE))
           ((op-is-ix-indexed-p op1)  (list #xDD #xAE (z80-signed-byte (d1))))
           ((op-is-iy-indexed-p op1)  (list #xFD #xAE (z80-signed-byte (d1))))
           ((op-is-imm-p op1)         (list #xEE (z80-byte (e1))))
           (t (error "XOR opérande invalide"))))

        ((string= mnem-up "CP")
         (cond
           ((op-is-reg8-p op1)        (list (+ #xB8 (op-reg8-code op1))))
           ((op-is-hl-indirect-p op1) '(#xBE))
           ((op-is-ix-indexed-p op1)  (list #xDD #xBE (z80-signed-byte (d1))))
           ((op-is-iy-indexed-p op1)  (list #xFD #xBE (z80-signed-byte (d1))))
           ((op-is-imm-p op1)         (list #xFE (z80-byte (e1))))
           (t (error "CP opérande invalide"))))

        ;; ----------------------------------------------------------------
        ;; RST
        ;; ----------------------------------------------------------------
        ((string= mnem-up "RST")
         (let ((n (e1)))
           (unless (member n '(0 8 16 24 32 40 48 56) :test #'=)
             (error "RST $~X invalide" n))
           (list (+ #xC7 n))))

        ;; ----------------------------------------------------------------
        ;; RET [cond]
        ;; ----------------------------------------------------------------
        ((string= mnem-up "RET")
         (if op1
             (if (op-is-cond-p op1)
                 (list (+ #xC0 (* (z80-cond-code (op-val op1)) 8)))
                 (error "RET condition invalide"))
             '(#xC9)))

        ;; ----------------------------------------------------------------
        ;; DJNZ
        ;; ----------------------------------------------------------------
        ((string= mnem-up "DJNZ")
         (list #x10 (z80-rel (e1) pc)))

        ;; ----------------------------------------------------------------
        ;; JR [cond,] label
        ;; ----------------------------------------------------------------
        ((string= mnem-up "JR")
         (cond
           ((and op2 (op-is-jr-cond-p op1))
            (list (+ #x20 (* (z80-jr-cond-code (op-val op1)) 8))
                  (z80-rel (e2) pc)))
           ((and op1 (not op2))
            (list #x18 (z80-rel (e1) pc)))
           (t (error "JR opérandes invalides"))))

        ;; ----------------------------------------------------------------
        ;; JP [cond,] nn  /  JP (HL)  /  JP (IX)  /  JP (IY)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "JP")
         (cond
           ((and op1 (not op2) (op-is-hl-indirect-p op1))   '(#xE9))
           ((and op1 (not op2) (op-is-named-str op1 "(IX)")) '(#xDD #xE9))
           ((and op1 (not op2) (op-is-named-str op1 "(IY)")) '(#xFD #xE9))
           ((and op2 (op-is-cond-p op1))
            (let ((nn (e2)))
              (list (+ #xC2 (* (z80-cond-code (op-val op1)) 8))
                    (z80-word-lo nn) (z80-word-hi nn))))
           ((and op1 (not op2))
            (let ((nn (e1)))
              (list #xC3 (z80-word-lo nn) (z80-word-hi nn))))
           (t (error "JP opérandes invalides"))))

        ;; ----------------------------------------------------------------
        ;; CALL [cond,] nn
        ;; ----------------------------------------------------------------
        ((string= mnem-up "CALL")
         (cond
           ((and op2 (op-is-cond-p op1))
            (let ((nn (e2)))
              (list (+ #xC4 (* (z80-cond-code (op-val op1)) 8))
                    (z80-word-lo nn) (z80-word-hi nn))))
           ((and op1 (not op2))
            (let ((nn (e1)))
              (list #xCD (z80-word-lo nn) (z80-word-hi nn))))
           (t (error "CALL opérandes invalides"))))

        ;; ----------------------------------------------------------------
        ;; IN  A,(n)  /  IN r,(C)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "IN")
         (cond
           ((and (op-is-a-p op1) (op-is-mem-indirect-p op2))
            (list #xDB (z80-byte (z80-eval (op-val op2) env))))
           ((and (op-is-a-p op1) (op-is-c-indirect-p op2))
            '(#xED #x78))
           ((and (op-is-reg8-p op1) (op-is-c-indirect-p op2))
            (list #xED (+ #x40 (* (op-reg8-code op1) 8))))
           (t (error "IN opérandes invalides"))))

        ;; ----------------------------------------------------------------
        ;; OUT (n),A  /  OUT (C),r
        ;; ----------------------------------------------------------------
        ((string= mnem-up "OUT")
         (cond
           ((and (op-is-mem-indirect-p op1) (op-is-a-p op2))
            (list #xD3 (z80-byte (z80-eval (op-val op1) env))))
           ((and (op-is-c-indirect-p op1) (op-is-reg8-p op2))
            (list #xED (+ #x41 (* (op-reg8-code op2) 8))))
           (t (error "OUT opérandes invalides"))))

        ;; ----------------------------------------------------------------
        ;; BIT / SET / RES  n, r
        ;; ----------------------------------------------------------------
        ((member mnem-up '("BIT" "SET" "RES") :test #'string=)
         (let* ((n    (e1))
                (base (cond ((string= mnem-up "BIT") #x40)
                            ((string= mnem-up "RES") #x80)
                            (t                       #xC0))))
           (unless (<= 0 n 7) (error "~A bit ~D invalide" mnem-up n))
           (cond
             ((op-is-reg8-p op2)
              (list #xCB (+ base (* n 8) (op-reg8-code op2))))
             ((op-is-hl-indirect-p op2)
              (list #xCB (+ base (* n 8) 6)))
             ((op-is-ix-indexed-p op2)
              (list #xDD #xCB (z80-signed-byte (d2)) (+ base (* n 8) 6)))
             ((op-is-iy-indexed-p op2)
              (list #xFD #xCB (z80-signed-byte (d2)) (+ base (* n 8) 6)))
             (t (error "~A opérandes invalides" mnem-up)))))

        ;; ----------------------------------------------------------------
        ;; Rotations / shifts  CB prefix
        ;; Ordre réel des opcodes CB : RLC RRC RL RR SLA SRA SLL SRL
        ;; ----------------------------------------------------------------
        ((member mnem-up '("RLC" "RRC" "RL" "RR" "SLA" "SRA" "SLL" "SRL")
                 :test #'string=)
         (let ((sub-op (position mnem-up
                                 #("RLC" "RRC" "RL" "RR" "SLA" "SRA" "SLL" "SRL")
                                 :test #'string=)))
           (cond
             ((op-is-reg8-p op1)
              (list #xCB (+ (* sub-op 8) (op-reg8-code op1))))
             ((op-is-hl-indirect-p op1)
              (list #xCB (+ (* sub-op 8) 6)))
             ((op-is-ix-indexed-p op1)
              (list #xDD #xCB (z80-signed-byte (d1)) (+ (* sub-op 8) 6)))
             ((op-is-iy-indexed-p op1)
              (list #xFD #xCB (z80-signed-byte (d1)) (+ (* sub-op 8) 6)))
             (t (error "~A opérande invalide" mnem-up)))))

        ;; ----------------------------------------------------------------
        ;; LD
        ;; ----------------------------------------------------------------
        ((string= mnem-up "LD")
         (encode-z80-ld op1 op2 env))

        (t (error "Mnémonique Z80 inconnu : ~A" mnem-up))))))


;;; --------------------------------------------------------------------------
;;;  Encodeur LD
;;; --------------------------------------------------------------------------

(defun encode-z80-ld (op1 op2 env)
  "Encode toutes les formes de LD Z80."
  (flet ((e2  () (z80-eval (op-val op2) env))
         (d1  () (z80-disp-val op1 env))
         (d2  () (z80-disp-val op2 env))
         (mem () (z80-eval (op-val op1) env))
         (mem2 () (z80-eval (op-val op2) env)))
    (cond
      ;; LD r, r'
      ((and (op-is-reg8-p op1) (op-is-reg8-p op2))
       (list (+ #x40 (* (op-reg8-code op1) 8) (op-reg8-code op2))))
      ;; LD r, n
      ((and (op-is-reg8-p op1) (op-is-imm-p op2))
       (list (+ #x06 (* (op-reg8-code op1) 8)) (z80-byte (e2))))
      ;; LD r, (HL)
      ((and (op-is-reg8-p op1) (op-is-hl-indirect-p op2))
       (list (+ #x46 (* (op-reg8-code op1) 8))))
      ;; LD r, (IX+d)
      ((and (op-is-reg8-p op1) (op-is-ix-indexed-p op2))
       (list #xDD (+ #x46 (* (op-reg8-code op1) 8)) (z80-signed-byte (d2))))
      ;; LD r, (IY+d)
      ((and (op-is-reg8-p op1) (op-is-iy-indexed-p op2))
       (list #xFD (+ #x46 (* (op-reg8-code op1) 8)) (z80-signed-byte (d2))))
      ;; LD (HL), r
      ((and (op-is-hl-indirect-p op1) (op-is-reg8-p op2))
       (list (+ #x70 (op-reg8-code op2))))
      ;; LD (HL), n
      ((and (op-is-hl-indirect-p op1) (op-is-imm-p op2))
       (list #x36 (z80-byte (e2))))
      ;; LD (IX+d), r
      ((and (op-is-ix-indexed-p op1) (op-is-reg8-p op2))
       (list #xDD (+ #x70 (op-reg8-code op2)) (z80-signed-byte (d1))))
      ;; LD (IX+d), n
      ((and (op-is-ix-indexed-p op1) (op-is-imm-p op2))
       (list #xDD #x36 (z80-signed-byte (d1)) (z80-byte (e2))))
      ;; LD (IY+d), r
      ((and (op-is-iy-indexed-p op1) (op-is-reg8-p op2))
       (list #xFD (+ #x70 (op-reg8-code op2)) (z80-signed-byte (d1))))
      ;; LD (IY+d), n
      ((and (op-is-iy-indexed-p op1) (op-is-imm-p op2))
       (list #xFD #x36 (z80-signed-byte (d1)) (z80-byte (e2))))
      ;; LD A, (BC)
      ((and (op-is-a-p op1) (eq (op-kind op2) :indirect)
            (stringp (op-val op2))
            (string= (string-upcase (op-val op2)) "BC"))
       '(#x0A))
      ;; LD A, (DE)
      ((and (op-is-a-p op1) (eq (op-kind op2) :indirect)
            (stringp (op-val op2))
            (string= (string-upcase (op-val op2)) "DE"))
       '(#x1A))
      ;; LD A, (nn)
      ((and (op-is-a-p op1) (op-is-mem-indirect-p op2))
       (let ((nn (mem2)))
         (list #x3A (z80-word-lo nn) (z80-word-hi nn))))
      ;; LD (BC), A
      ((and (eq (op-kind op1) :indirect) (stringp (op-val op1))
            (string= (string-upcase (op-val op1)) "BC") (op-is-a-p op2))
       '(#x02))
      ;; LD (DE), A
      ((and (eq (op-kind op1) :indirect) (stringp (op-val op1))
            (string= (string-upcase (op-val op1)) "DE") (op-is-a-p op2))
       '(#x12))
      ;; LD (nn), A
      ((and (op-is-mem-indirect-p op1) (op-is-a-p op2))
       (let ((nn (mem)))
         (list #x32 (z80-word-lo nn) (z80-word-hi nn))))
      ;; LD rr, nn
      ((and (op-is-reg16-p op1) (op-is-imm-p op2))
       (let ((nn (e2)))
         (list (+ #x01 (* (op-reg16-code op1) 16))
               (z80-word-lo nn) (z80-word-hi nn))))
      ;; LD IX, nn
      ((and (op-is-ix-p op1) (op-is-imm-p op2))
       (let ((nn (e2)))
         (list #xDD #x21 (z80-word-lo nn) (z80-word-hi nn))))
      ;; LD IY, nn
      ((and (op-is-iy-p op1) (op-is-imm-p op2))
       (let ((nn (e2)))
         (list #xFD #x21 (z80-word-lo nn) (z80-word-hi nn))))
      ;; LD HL, (nn)
      ((and (op-is-hl-p op1) (op-is-mem-indirect-p op2))
       (let ((nn (mem2)))
         (list #x2A (z80-word-lo nn) (z80-word-hi nn))))
      ;; LD rr, (nn)  ED
      ((and (op-is-reg16-p op1) (op-is-mem-indirect-p op2))
       (let ((nn (mem2)))
         (list #xED (+ #x4B (* (op-reg16-code op1) 16))
               (z80-word-lo nn) (z80-word-hi nn))))
      ;; LD IX, (nn)
      ((and (op-is-ix-p op1) (op-is-mem-indirect-p op2))
       (let ((nn (mem2)))
         (list #xDD #x2A (z80-word-lo nn) (z80-word-hi nn))))
      ;; LD IY, (nn)
      ((and (op-is-iy-p op1) (op-is-mem-indirect-p op2))
       (let ((nn (mem2)))
         (list #xFD #x2A (z80-word-lo nn) (z80-word-hi nn))))
      ;; LD (nn), HL
      ((and (op-is-mem-indirect-p op1) (op-is-hl-p op2))
       (let ((nn (mem)))
         (list #x22 (z80-word-lo nn) (z80-word-hi nn))))
      ;; LD (nn), rr  ED
      ((and (op-is-mem-indirect-p op1) (op-is-reg16-p op2))
       (let ((nn (mem)))
         (list #xED (+ #x43 (* (op-reg16-code op2) 16))
               (z80-word-lo nn) (z80-word-hi nn))))
      ;; LD (nn), IX
      ((and (op-is-mem-indirect-p op1) (op-is-ix-p op2))
       (let ((nn (mem)))
         (list #xDD #x22 (z80-word-lo nn) (z80-word-hi nn))))
      ;; LD (nn), IY
      ((and (op-is-mem-indirect-p op1) (op-is-iy-p op2))
       (let ((nn (mem)))
         (list #xFD #x22 (z80-word-lo nn) (z80-word-hi nn))))
      ;; LD SP, HL/IX/IY
      ((and (op-is-sp-p op1) (op-is-hl-p op2)) '(#xF9))
      ((and (op-is-sp-p op1) (op-is-ix-p op2)) '(#xDD #xF9))
      ((and (op-is-sp-p op1) (op-is-iy-p op2)) '(#xFD #xF9))
      ;; LD A, I/R  et  LD I/R, A
      ((and (op-is-a-p op1) (op-is-named-str op2 "I")) '(#xED #x57))
      ((and (op-is-a-p op1) (op-is-named-str op2 "R")) '(#xED #x5F))
      ((and (op-is-named-str op1 "I") (op-is-a-p op2)) '(#xED #x47))
      ((and (op-is-named-str op1 "R") (op-is-a-p op2)) '(#xED #x4F))
      (t (error "LD opérandes non reconnus : ~S ~S"
                (list (op-kind op1) (op-val op1))
                (list (op-kind op2) (op-val op2)))))))


;;; --------------------------------------------------------------------------
;;;  Estimation de taille (passe 1)
;;; --------------------------------------------------------------------------

(defun estimate-z80-size (mnem-up ops)
  "Estime la taille en octets d'une instruction Z80 (sans résoudre symboles)."
  (let ((op1 (first ops))
        (op2 (second ops)))
    (cond
      ;; 1 octet implied
      ((member mnem-up '("NOP" "HALT" "DI" "EI" "EXX" "DAA" "CPL" "CCF" "SCF"
                         "RLCA" "RRCA" "RLA" "RRA")
               :test #'string=) 1)
      ;; 2 octets ED
      ((member mnem-up '("NEG" "RLD" "RRD" "RETN" "RETI"
                         "LDI" "LDIR" "LDD" "LDDR"
                         "CPI" "CPIR" "CPD" "CPDR"
                         "INI" "INIR" "IND" "INDR"
                         "OUTI" "OTIR" "OUTD" "OTDR" "IM")
               :test #'string=) 2)
      ;; DJNZ, JR : 2 octets
      ((string= mnem-up "DJNZ") 2)
      ((string= mnem-up "JR")   2)
      ;; JP
      ((string= mnem-up "JP")
       (cond ((and op1 (not op2) (op-is-hl-indirect-p op1)) 1)
             ((and op1 (not op2)
                   (or (op-is-named-str op1 "(IX)") (op-is-named-str op1 "(IY)"))) 2)
             (t 3)))
      ;; CALL : 3
      ((string= mnem-up "CALL") 3)
      ;; RET, RST : 1
      ((or (string= mnem-up "RET") (string= mnem-up "RST")) 1)
      ;; EX
      ((string= mnem-up "EX")
       (if (and op1 (or (op-is-ix-p op2) (op-is-iy-p op2))) 2 1))
      ;; PUSH/POP
      ((member mnem-up '("PUSH" "POP") :test #'string=)
       (if (and op1 (or (op-is-ix-p op1) (op-is-iy-p op1))) 2 1))
      ;; INC/DEC
      ((member mnem-up '("INC" "DEC") :test #'string=)
       (cond ((and op1 (or (op-is-ix-indexed-p op1) (op-is-iy-indexed-p op1))) 3)
             ((and op1 (or (op-is-ix-p op1) (op-is-iy-p op1))) 2)
             (t 1)))
      ;; BIT/SET/RES avec (IX+d)/(IY+d) : 4, sinon 2
      ((member mnem-up '("BIT" "SET" "RES") :test #'string=)
       (if (and op2 (or (op-is-ix-indexed-p op2) (op-is-iy-indexed-p op2))) 4 2))
      ;; Rotations/shifts avec (IX+d)/(IY+d) : 4, sinon 2
      ((member mnem-up '("RLC" "RRC" "RL" "RR" "SLA" "SRA" "SLL" "SRL")
               :test #'string=)
       (if (and op1 (or (op-is-ix-indexed-p op1) (op-is-iy-indexed-p op1))) 4 2))
      ;; IN/OUT : 2
      ((member mnem-up '("IN" "OUT") :test #'string=) 2)
      ;; ADD/ADC/SUB/SBC/AND/OR/XOR/CP
      ((member mnem-up '("ADD" "ADC" "SUB" "SBC" "AND" "OR" "XOR" "CP")
               :test #'string=)
       (cond
         ;; ADD/ADC HL,rr → 1; ADC HL,rr (ED) → 2
         ((and op2 (op-is-hl-p op1))
          (if (member mnem-up '("ADC" "SBC") :test #'string=) 2 1))
         ;; ADD IX/IY, rr → 2
         ((and op2 (or (op-is-ix-p op1) (op-is-iy-p op1))) 2)
         ;; avec (IX+d)/(IY+d)
         ((or (and op1 (or (op-is-ix-indexed-p op1) (op-is-iy-indexed-p op1)))
              (and op2 (or (op-is-ix-indexed-p op2) (op-is-iy-indexed-p op2)))) 3)
         ;; immédiat
         ((or (and op1 (op-is-imm-p op1))
              (and op2 (op-is-imm-p op2))) 2)
         (t 1)))
      ;; LD
      ((string= mnem-up "LD") (estimate-z80-ld-size op1 op2))
      (t 1))))

(defun estimate-z80-ld-size (op1 op2)
  "Estime la taille d'un LD."
  (cond
    ;; LD IX/IY, nn ou LD nn, IX/IY → 4
    ((or (op-is-ix-p op1) (op-is-iy-p op1)
         (and op2 (or (op-is-ix-p op2) (op-is-iy-p op2)))) 4)
    ;; (IX+d) / (IY+d) → 3 ou 4
    ((or (op-is-ix-indexed-p op1) (op-is-iy-indexed-p op1)
         (and op2 (or (op-is-ix-indexed-p op2) (op-is-iy-indexed-p op2))))
     (if (and op2 (op-is-imm-p op2)) 4 3))
    ;; LD rr, nn → 3
    ((and (op-is-reg16-p op1) (op-is-imm-p op2)) 3)
    ;; LD (nn), xx ou LD xx, (nn)
    ((or (op-is-mem-indirect-p op1) (and op2 (op-is-mem-indirect-p op2)))
     (cond ((or (op-is-reg16-p op1) (and op2 (op-is-reg16-p op2))) 4)
           (t 3)))
    ;; LD SP, HL/IX/IY → 1 ou 2
    ((op-is-sp-p op1)
     (if (and op2 (or (op-is-ix-p op2) (op-is-iy-p op2))) 2 1))
    ;; LD A,I / LD A,R / LD I,A / LD R,A → 2
    ((or (op-is-named-str op1 "I") (op-is-named-str op1 "R")
         (and op2 (or (op-is-named-str op2 "I") (op-is-named-str op2 "R")))) 2)
    ;; LD r, n → 2
    ((and (op-is-reg8-p op1) (op-is-imm-p op2)) 2)
    ;; LD r, r' ou LD r, (HL) etc → 1
    (t 1)))


;;; --------------------------------------------------------------------------
;;;  Assemblage deux passes
;;; --------------------------------------------------------------------------

(defun pass-1-z80 (program symtable &key (origin 0))
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
             (setf pc (z80-directive-pass1
                       (cl-asm/ir:ir-directive-name node)
                       (cl-asm/ir:ir-directive-args node)
                       env pc symtable))))
          (cl-asm/ir:ir-instruction
           (let* ((mnem (string-upcase
                         (cl-asm/ir:ir-instruction-mnemonic node)))
                  (ops  (cl-asm/ir:ir-instruction-operands node)))
             (incf pc (estimate-z80-size mnem ops)))))))
    pc))

(defun z80-directive-pass1 (name args env pc symtable)
  "Traite une directive en passe 1. Retourne le nouveau PC."
  (case name
    (:org
     (multiple-value-bind (val ok)
         (z80-eval-expr (first args) env)
       (if ok val pc)))
    (:equ
     (let ((sym-name (first args))
           (expr     (second args)))
       (multiple-value-bind (val ok)
           (z80-eval-expr expr env)
         (when ok
           (cl-asm/symbol-table:define-constant symtable sym-name val)))
       pc))
    (:byte  (+ pc (length args)))
    (:word  (+ pc (* 2 (length args))))
    (:dword (+ pc (* 4 (length args))))
    (:fill
     (multiple-value-bind (n ok)
         (z80-eval-expr (first args) env)
       (if ok (+ pc n) pc)))
    (otherwise pc)))

(defun pass-2-z80 (program symtable &key (origin 0))
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
             (setf pc (z80-directive-pass2
                       (cl-asm/ir:ir-directive-name node)
                       (cl-asm/ir:ir-directive-args node)
                       env pc result))))
          (cl-asm/ir:ir-instruction
           (let* ((mnem (string-upcase
                         (cl-asm/ir:ir-instruction-mnemonic node)))
                  (ops  (cl-asm/ir:ir-instruction-operands node))
                  (env  (cl-asm/expression:make-env
                         :symbol-table symtable :pc pc))
                  (bytes (encode-z80 mnem ops env pc)))
             (dolist (b bytes) (vector-push-extend b result))
             (incf pc (length bytes))))
          (cl-asm/ir:ir-label nil))))
    result))

(defun z80-directive-pass2 (name args env pc result)
  "Traite une directive en passe 2."
  (case name
    (:org
     (multiple-value-bind (val ok)
         (z80-eval-expr (first args) env)
       (if ok val pc)))
    (:equ pc)
    (:section pc)
    (:global pc)
    (:extern pc)
    (:byte
     (dolist (arg args)
       (multiple-value-bind (val ok)
           (z80-eval-expr arg env)
         (vector-push-extend (logand (if ok val 0) #xFF) result)
         (incf pc)))
     pc)
    (:word
     (dolist (arg args)
       (multiple-value-bind (val ok)
           (z80-eval-expr arg env)
         (let ((w (if ok val 0)))
           (vector-push-extend (logand w #xFF) result)
           (vector-push-extend (logand (ash w -8) #xFF) result)
           (incf pc 2))))
     pc)
    (:dword
     (dolist (arg args)
       (multiple-value-bind (val ok)
           (z80-eval-expr arg env)
         (let ((d (if ok val 0)))
           (dotimes (i 4)
             (vector-push-extend (logand (ash d (* -8 i)) #xFF) result))
           (incf pc 4))))
     pc)
    (:fill
     (multiple-value-bind (count ok-n)
         (z80-eval-expr (first args) env)
       (let ((fill-val (if (second args)
                           (multiple-value-bind (v ok)
                               (z80-eval-expr (second args) env)
                             (if ok (logand v #xFF) 0))
                           0)))
         (when ok-n
           (dotimes (_ count)
             (vector-push-extend fill-val result)
             (incf pc)))))
     pc)
    (otherwise pc)))


;;; --------------------------------------------------------------------------
;;;  API publique
;;; --------------------------------------------------------------------------

(defun assemble-z80 (program &key (origin 0))
  "Assemble un IR-PROGRAM Z80. Retourne un vecteur d'octets."
  (let ((sym (cl-asm/symbol-table:make-symbol-table)))
    (pass-1-z80 program sym :origin origin)
    (cl-asm/symbol-table:begin-pass-2 sym)
    (pass-2-z80 program sym :origin origin)))

(defun assemble-string-z80 (source &key (origin 0))
  "Assemble une chaîne source Z80. Retourne un vecteur d'octets."
  (let* ((cl-asm/parser:*z80-mode* t)
         (prog (cl-asm/parser:parse-string source)))
    (assemble-z80 prog :origin origin)))

(defun assemble-file-z80 (path &key (origin 0))
  "Assemble le fichier PATH Z80. Retourne un vecteur d'octets."
  (let* ((cl-asm/parser:*z80-mode* t)
         (prog (cl-asm/parser:parse-file path)))
    (assemble-z80 prog :origin origin)))


;;; --------------------------------------------------------------------------
;;;  Enregistrement du backend
;;; --------------------------------------------------------------------------

(cl-asm/backends:register-backend
 :z80
 '("z80" "z80cpu" "zx80" "zx81" "zxspectrum" "spectrum" "cpc" "msx")
 'cl-asm/backend.z80
 'assemble-file-z80
 "Z80 (ZX Spectrum, MSX, CPC, ZX81)"
 "Z80 (ZX Spectrum, MSX, CPC, ZX81)")
