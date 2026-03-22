; -*- coding: utf-8 -*-
;;;; src/backend/i8080.lisp
;;;;
;;;; Backend Intel 8080 pour cl-asm.
;;;; Supporte le jeu d'instructions Intel 8080 (Altair, CP/M…).
;;;;
;;;; Encodage :
;;;;   Registres 8 bits : B=0 C=1 D=2 E=3 H=4 L=5 M=6 A=7
;;;;   Paires rp         : B(C)=0 D(E)=1 H(L)=2 SP=3
;;;;   Paires push/pop   : B(C)=0 D(E)=1 H(L)=2 PSW=3
;;;;
;;;;   MOV d,s = $40|(d<<3)|s    (1 octet)
;;;;   ALU  r  = base|r          (1 octet, base: ADD=$80 ADC=$88 … CMP=$B8)
;;;;   IMM n   = opcode n        (2 octets : MVI, ADI-CPI, IN, OUT)
;;;;   RP  nn  = opcode lo hi    (3 octets : LXI, LDA, STA, LHLD, SHLD, JMP, CALL, Jcc, Ccc)

(defpackage #:cl-asm/backend.i8080
  (:use #:cl)
  (:export
   #:assemble-i8080
   #:assemble-string-i8080
   #:assemble-file-i8080))

(in-package #:cl-asm/backend.i8080)

;;; Déclarations forward
(declaim (ftype (function (t t t t t) t) i8080-directive-pass1))
(declaim (ftype (function (t t t t t) t) i8080-directive-pass2))


;;; --------------------------------------------------------------------------
;;;  Utilitaires
;;; --------------------------------------------------------------------------

(defun ascii-to-petscii (code)
  "Convertit un code ASCII en PETSCII (comme ACME !PET)."
  (cond
    ((and (>= code #x61) (<= code #x7A)) (- code #x20))
    ((and (>= code #x41) (<= code #x5A)) (+ code #x80))
    (t code)))


;;; --------------------------------------------------------------------------
;;;  Tables de registres
;;; --------------------------------------------------------------------------

(defun i8080-reg8-code (s)
  "Code 3 bits du registre 8 bits (B=0 C=1 D=2 E=3 H=4 L=5 M=6 A=7).
   Retourne NIL si S n'est pas un registre 8 bits valide."
  (position (string-upcase s)
            #("B" "C" "D" "E" "H" "L" "M" "A") :test #'string=))

(defun i8080-regpair-code (s)
  "Code 2 bits de la paire de registres (B=0 D=1 H=2 SP=3). NIL si inconnu."
  (let ((u (string-upcase s)))
    (cond
      ((or (string= u "B") (string= u "BC")) 0)
      ((or (string= u "D") (string= u "DE")) 1)
      ((or (string= u "H") (string= u "HL")) 2)
      ((string= u "SP") 3)
      (t nil))))

(defun i8080-regpair-push-code (s)
  "Code 2 bits pour PUSH/POP (B=0 D=1 H=2 PSW=3). NIL si inconnu."
  (let ((u (string-upcase s)))
    (cond
      ((or (string= u "B") (string= u "BC")) 0)
      ((or (string= u "D") (string= u "DE")) 1)
      ((or (string= u "H") (string= u "HL")) 2)
      ((string= u "PSW") 3)
      (t nil))))


;;; --------------------------------------------------------------------------
;;;  Helpers sur les opérandes IR
;;; --------------------------------------------------------------------------

(defun op-kind (op) (cl-asm/ir:ir-operand-kind op))
(defun op-val  (op) (cl-asm/ir:ir-operand-value op))

(defun op-is-named-str (op name)
  "Vrai si l'opérande est :direct avec la chaîne NAME (insensible à la casse)."
  (and (eq (op-kind op) :direct)
       (stringp (op-val op))
       (string= (string-upcase (op-val op)) (string-upcase name))))

(defun op-is-reg8-p (op)
  "Vrai si l'opérande est un registre 8 bits valide (B C D E H L M A)."
  (and (eq (op-kind op) :direct)
       (stringp (op-val op))
       (i8080-reg8-code (op-val op))
       t))

(defun op-reg8-code (op) (i8080-reg8-code (op-val op)))

(defun op-is-imm-p (op)
  "Vrai si l'opérande est une valeur immédiate (nombre, expr ou #n)."
  (or (eq (op-kind op) :immediate)
      (and (eq (op-kind op) :direct)
           (not (stringp (op-val op))))))


;;; --------------------------------------------------------------------------
;;;  Évaluation des expressions
;;; --------------------------------------------------------------------------

(defun i8080-eval-expr (expr env)
  "Évalue EXPR dans ENV. Retourne (values val resolved-p)."
  (cl-asm/expression:eval-expr expr env))

(defun i8080-eval (expr env)
  "Évalue EXPR dans ENV et retourne la valeur. Erreur si non résolue."
  (multiple-value-bind (val ok)
      (i8080-eval-expr expr env)
    (if ok val (error "Expression 8080 non résolue : ~S" expr))))


;;; --------------------------------------------------------------------------
;;;  Encodage bas niveau
;;; --------------------------------------------------------------------------

(defun i8080-byte (val)    (logand val #xFF))
(defun i8080-word-lo (val) (logand val #xFF))
(defun i8080-word-hi (val) (logand (ash val -8) #xFF))


;;; --------------------------------------------------------------------------
;;;  Encodeur principal
;;; --------------------------------------------------------------------------

(defun encode-i8080 (mnem-up ops env pc)
  "Encode une instruction Intel 8080. Retourne une liste d'octets."
  (declare (ignore pc))
  (let ((op1 (first ops))
        (op2 (second ops)))
    (flet ((e1 () (i8080-eval (op-val op1) env))
           (e2 () (i8080-eval (op-val op2) env))
           (rp1 ()
             (and op1 (stringp (op-val op1))
                  (i8080-regpair-code (op-val op1)))))
      (cond

        ;; ----------------------------------------------------------------
        ;; Implied (1 octet)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "NOP")  '(#x00))
        ((string= mnem-up "RLC")  '(#x07))
        ((string= mnem-up "RRC")  '(#x0F))
        ((string= mnem-up "RAL")  '(#x17))
        ((string= mnem-up "RAR")  '(#x1F))
        ((string= mnem-up "DAA")  '(#x27))
        ((string= mnem-up "CMA")  '(#x2F))
        ((string= mnem-up "STC")  '(#x37))
        ((string= mnem-up "CMC")  '(#x3F))
        ((string= mnem-up "HLT")  '(#x76))
        ((string= mnem-up "RET")  '(#xC9))
        ((string= mnem-up "PCHL") '(#xE9))
        ((string= mnem-up "XTHL") '(#xE3))
        ((string= mnem-up "XCHG") '(#xEB))
        ((string= mnem-up "SPHL") '(#xF9))
        ((string= mnem-up "DI")   '(#xF3))
        ((string= mnem-up "EI")   '(#xFB))

        ;; Retours conditionnels (aucun opérande)
        ((string= mnem-up "RNZ") '(#xC0))
        ((string= mnem-up "RZ")  '(#xC8))
        ((string= mnem-up "RNC") '(#xD0))
        ((string= mnem-up "RC")  '(#xD8))
        ((string= mnem-up "RPO") '(#xE0))
        ((string= mnem-up "RPE") '(#xE8))
        ((string= mnem-up "RP")  '(#xF0))
        ((string= mnem-up "RM")  '(#xF8))

        ;; ----------------------------------------------------------------
        ;; MOV d, s  (1 octet)   $40|(d<<3)|s
        ;; ----------------------------------------------------------------
        ((string= mnem-up "MOV")
         (unless (and op1 op2 (op-is-reg8-p op1) (op-is-reg8-p op2))
           (error "MOV: deux registres 8 bits attendus"))
         (let ((d (op-reg8-code op1))
               (s (op-reg8-code op2)))
           (when (and (= d 6) (= s 6))
             (error "MOV M,M invalide (= HLT)"))
           (list (logior #x40 (ash d 3) s))))

        ;; ----------------------------------------------------------------
        ;; INR r / DCR r  (1 octet)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "INR")
         (unless (and op1 (op-is-reg8-p op1))
           (error "INR: registre 8 bits attendu"))
         (list (logior #x04 (ash (op-reg8-code op1) 3))))

        ((string= mnem-up "DCR")
         (unless (and op1 (op-is-reg8-p op1))
           (error "DCR: registre 8 bits attendu"))
         (list (logior #x05 (ash (op-reg8-code op1) 3))))

        ;; ----------------------------------------------------------------
        ;; INX rp / DCX rp / DAD rp  (1 octet)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "INX")
         (let ((rp (rp1)))
           (unless rp (error "INX: paire de registres attendue"))
           (list (logior #x03 (ash rp 4)))))

        ((string= mnem-up "DCX")
         (let ((rp (rp1)))
           (unless rp (error "DCX: paire de registres attendue"))
           (list (logior #x0B (ash rp 4)))))

        ((string= mnem-up "DAD")
         (let ((rp (rp1)))
           (unless rp (error "DAD: paire de registres attendue"))
           (list (logior #x09 (ash rp 4)))))

        ;; ----------------------------------------------------------------
        ;; STAX rp / LDAX rp  (1 octet, B ou D seulement)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "STAX")
         (let ((rp (rp1)))
           (case rp
             (0 '(#x02))
             (1 '(#x12))
             (t (error "STAX: B ou D attendu")))))

        ((string= mnem-up "LDAX")
         (let ((rp (rp1)))
           (case rp
             (0 '(#x0A))
             (1 '(#x1A))
             (t (error "LDAX: B ou D attendu")))))

        ;; ----------------------------------------------------------------
        ;; ALU r   (1 octet)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "ADD")
         (unless (and op1 (op-is-reg8-p op1))
           (error "ADD: registre 8 bits attendu"))
         (list (logior #x80 (op-reg8-code op1))))

        ((string= mnem-up "ADC")
         (unless (and op1 (op-is-reg8-p op1))
           (error "ADC: registre 8 bits attendu"))
         (list (logior #x88 (op-reg8-code op1))))

        ((string= mnem-up "SUB")
         (unless (and op1 (op-is-reg8-p op1))
           (error "SUB: registre 8 bits attendu"))
         (list (logior #x90 (op-reg8-code op1))))

        ((string= mnem-up "SBB")
         (unless (and op1 (op-is-reg8-p op1))
           (error "SBB: registre 8 bits attendu"))
         (list (logior #x98 (op-reg8-code op1))))

        ((string= mnem-up "ANA")
         (unless (and op1 (op-is-reg8-p op1))
           (error "ANA: registre 8 bits attendu"))
         (list (logior #xA0 (op-reg8-code op1))))

        ((string= mnem-up "XRA")
         (unless (and op1 (op-is-reg8-p op1))
           (error "XRA: registre 8 bits attendu"))
         (list (logior #xA8 (op-reg8-code op1))))

        ((string= mnem-up "ORA")
         (unless (and op1 (op-is-reg8-p op1))
           (error "ORA: registre 8 bits attendu"))
         (list (logior #xB0 (op-reg8-code op1))))

        ((string= mnem-up "CMP")
         (unless (and op1 (op-is-reg8-p op1))
           (error "CMP: registre 8 bits attendu"))
         (list (logior #xB8 (op-reg8-code op1))))

        ;; ----------------------------------------------------------------
        ;; PUSH rp / POP rp  (1 octet, PSW autorisé)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "PUSH")
         (let ((rp (and op1 (stringp (op-val op1))
                        (i8080-regpair-push-code (op-val op1)))))
           (unless rp (error "PUSH: B D H PSW attendu"))
           (list (logior #xC5 (ash rp 4)))))

        ((string= mnem-up "POP")
         (let ((rp (and op1 (stringp (op-val op1))
                        (i8080-regpair-push-code (op-val op1)))))
           (unless rp (error "POP: B D H PSW attendu"))
           (list (logior #xC1 (ash rp 4)))))

        ;; ----------------------------------------------------------------
        ;; RST n   (1 octet, n = 0..7)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "RST")
         (let ((n (e1)))
           (unless (<= 0 n 7)
             (error "RST ~D invalide (0–7 attendu)" n))
           (list (logior #xC7 (ash n 3)))))

        ;; ----------------------------------------------------------------
        ;; MVI r, n   (2 octets)   ($06|(r<<3)) n
        ;; ----------------------------------------------------------------
        ((string= mnem-up "MVI")
         (unless (and op1 op2 (op-is-reg8-p op1) (op-is-imm-p op2))
           (error "MVI: registre et valeur immédiate attendus"))
         (list (logior #x06 (ash (op-reg8-code op1) 3))
               (i8080-byte (e2))))

        ;; ----------------------------------------------------------------
        ;; ALU immédiat  (2 octets)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "ADI") (list #xC6 (i8080-byte (e1))))
        ((string= mnem-up "ACI") (list #xCE (i8080-byte (e1))))
        ((string= mnem-up "SUI") (list #xD6 (i8080-byte (e1))))
        ((string= mnem-up "SBI") (list #xDE (i8080-byte (e1))))
        ((string= mnem-up "ANI") (list #xE6 (i8080-byte (e1))))
        ((string= mnem-up "XRI") (list #xEE (i8080-byte (e1))))
        ((string= mnem-up "ORI") (list #xF6 (i8080-byte (e1))))
        ((string= mnem-up "CPI") (list #xFE (i8080-byte (e1))))

        ;; ----------------------------------------------------------------
        ;; IN / OUT port   (2 octets)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "IN")  (list #xDB (i8080-byte (e1))))
        ((string= mnem-up "OUT") (list #xD3 (i8080-byte (e1))))

        ;; ----------------------------------------------------------------
        ;; LXI rp, nn   (3 octets)   ($01|(rp<<4)) lo hi
        ;; ----------------------------------------------------------------
        ((string= mnem-up "LXI")
         (unless (and op1 op2 (stringp (op-val op1)) (op-is-imm-p op2))
           (error "LXI: paire de registres et adresse attendues"))
         (let ((rp (i8080-regpair-code (op-val op1))))
           (unless rp (error "LXI: B D H SP attendu"))
           (let ((n (e2)))
             (list (logior #x01 (ash rp 4)) (i8080-word-lo n) (i8080-word-hi n)))))

        ;; ----------------------------------------------------------------
        ;; LDA / STA / LHLD / SHLD nn   (3 octets)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "LDA")
         (let ((n (e1)))
           (list #x3A (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "STA")
         (let ((n (e1)))
           (list #x32 (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "LHLD")
         (let ((n (e1)))
           (list #x2A (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "SHLD")
         (let ((n (e1)))
           (list #x22 (i8080-word-lo n) (i8080-word-hi n))))

        ;; ----------------------------------------------------------------
        ;; JMP nn   (3 octets)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "JMP")
         (let ((n (e1)))
           (list #xC3 (i8080-word-lo n) (i8080-word-hi n))))

        ;; ----------------------------------------------------------------
        ;; CALL nn   (3 octets)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "CALL")
         (let ((n (e1)))
           (list #xCD (i8080-word-lo n) (i8080-word-hi n))))

        ;; ----------------------------------------------------------------
        ;; Sauts conditionnels   (3 octets)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "JNZ")
         (let ((n (e1))) (list #xC2 (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "JZ")
         (let ((n (e1))) (list #xCA (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "JNC")
         (let ((n (e1))) (list #xD2 (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "JC")
         (let ((n (e1))) (list #xDA (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "JPO")
         (let ((n (e1))) (list #xE2 (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "JPE")
         (let ((n (e1))) (list #xEA (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "JP")
         (let ((n (e1))) (list #xF2 (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "JM")
         (let ((n (e1))) (list #xFA (i8080-word-lo n) (i8080-word-hi n))))

        ;; ----------------------------------------------------------------
        ;; Appels conditionnels   (3 octets)
        ;; ----------------------------------------------------------------
        ((string= mnem-up "CNZ")
         (let ((n (e1))) (list #xC4 (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "CZ")
         (let ((n (e1))) (list #xCC (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "CNC")
         (let ((n (e1))) (list #xD4 (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "CC")
         (let ((n (e1))) (list #xDC (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "CPO")
         (let ((n (e1))) (list #xE4 (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "CPE")
         (let ((n (e1))) (list #xEC (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "CP")
         (let ((n (e1))) (list #xF4 (i8080-word-lo n) (i8080-word-hi n))))
        ((string= mnem-up "CM")
         (let ((n (e1))) (list #xFC (i8080-word-lo n) (i8080-word-hi n))))

        (t (error "Mnémonique 8080 inconnu : ~A" mnem-up))))))

;;; Correction : LXI utilisait nn1 (basé sur op1) pour op2.
;;; On redéfinit la clause LXI proprement via un patch — voir ci-dessus,
;;; la clause LXI a été réécrite pour utiliser e2 directement.
;;; (Le flet nn1 n'est plus utilisé mais reste déclaré — sans impact.)


;;; --------------------------------------------------------------------------
;;;  Estimation de taille (passe 1)
;;; --------------------------------------------------------------------------

(defun i8080-instr-size (mnem-up)
  "Estime la taille en octets d'une instruction Intel 8080."
  (cond
    ;; 3 octets : adresse 16 bits
    ((member mnem-up
             '("LXI" "LDA" "STA" "LHLD" "SHLD"
               "JMP" "CALL"
               "JNZ" "JZ" "JNC" "JC" "JPO" "JPE" "JP" "JM"
               "CNZ" "CZ"  "CNC" "CC"  "CPO" "CPE" "CP" "CM")
             :test #'string=) 3)
    ;; 2 octets : immédiat 8 bits
    ((member mnem-up
             '("MVI" "ADI" "ACI" "SUI" "SBI" "ANI" "XRI" "ORI" "CPI"
               "IN" "OUT")
             :test #'string=) 2)
    ;; 1 octet : tout le reste
    (t 1)))


;;; --------------------------------------------------------------------------
;;;  Assemblage deux passes
;;; --------------------------------------------------------------------------

(defun pass-1-i8080 (program symtable &key (origin 0))
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
             (setf pc (i8080-directive-pass1
                       (cl-asm/ir:ir-directive-name node)
                       (cl-asm/ir:ir-directive-args node)
                       env pc symtable))))
          (cl-asm/ir:ir-instruction
           (let ((mnem (string-upcase
                        (cl-asm/ir:ir-instruction-mnemonic node))))
             (incf pc (i8080-instr-size mnem)))))))
    pc))

(defun i8080-directive-pass1 (name args env pc symtable)
  "Traite une directive en passe 1. Retourne le nouveau PC."
  (case name
    (:org
     (multiple-value-bind (val ok)
         (i8080-eval-expr (first args) env)
       (if ok val pc)))
    (:equ
     (let ((sym-name (first args))
           (expr     (second args)))
       (multiple-value-bind (val ok)
           (i8080-eval-expr expr env)
         (when ok
           (cl-asm/symbol-table:define-constant symtable sym-name val)))
       pc))
    ((:byte :pet)
     (+ pc (reduce #'+ args
                   :key (lambda (a) (if (stringp a) (length a) 1))
                   :initial-value 0)))
    (:word  (+ pc (* 2 (length args))))
    (:dword (+ pc (* 4 (length args))))
    (:asciiz    (+ pc (if (stringp (first args)) (length (first args)) 0) 1))
    (:pascalstr (+ pc (if (stringp (first args)) (length (first args)) 0) 1))
    (:fill
     (multiple-value-bind (n ok)
         (i8080-eval-expr (first args) env)
       (if ok (+ pc n) pc)))
    (:padto
     (multiple-value-bind (target ok)
         (i8080-eval-expr (first args) env)
       (if ok
           (if (> pc target)
               (error 'cl-asm/ir:asm-error
                      :message (format nil ".padto $~X : PC courant ($~X) dépasse la cible"
                                       target pc))
               target)
           pc)))
    (:incbin
     (let* ((filename  (first args))
            (offset    (if (second args)
                           (multiple-value-bind (v ok)
                               (i8080-eval-expr (second args) env)
                             (if ok v 0))
                           0))
            (count-arg (when (third args)
                         (multiple-value-bind (v ok)
                             (i8080-eval-expr (third args) env)
                           (when ok v)))))
       (handler-case
           (let* ((fsize (with-open-file (s filename :element-type '(unsigned-byte 8))
                           (file-length s)))
                  (avail (max 0 (- fsize offset)))
                  (n     (if count-arg (min count-arg avail) avail)))
             (+ pc n))
         (file-error ()
           (error 'cl-asm/ir:asm-error
                  :message (format nil ".incbin : fichier introuvable \"~A\"" filename))))))
    (:assertpc   pc)   ; vérifié en passe 2 uniquement
    (:assertsize pc)   ; vérifié en passe 2 uniquement
    (:defstruct
     (let* ((struct-name (first args))
            (fields      (second args))
            (offset      0))
       (dolist (field fields)
         (cl-asm/symbol-table:define-constant
          symtable
          (format nil "~A.~A" struct-name (car field))
          offset)
         (incf offset (cdr field)))
       (cl-asm/symbol-table:define-constant
        symtable
        (format nil "~A.SIZE" struct-name)
        offset))
     pc)
    (:defenum
     (let ((enum-name (first args))
           (values    (second args)))
       (dolist (entry values)
         (cl-asm/symbol-table:define-constant
          symtable
          (format nil "~A.~A" enum-name (car entry))
          (cdr entry)))
       (cl-asm/symbol-table:define-constant
        symtable
        (format nil "~A.COUNT" enum-name)
        (length values)))
     pc)
    (otherwise pc)))

(defun pass-2-i8080 (program symtable &key (origin 0))
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
             (setf pc (i8080-directive-pass2
                       (cl-asm/ir:ir-directive-name node)
                       (cl-asm/ir:ir-directive-args node)
                       env pc result))))
          (cl-asm/ir:ir-instruction
           (let* ((mnem  (string-upcase
                          (cl-asm/ir:ir-instruction-mnemonic node)))
                  (ops   (cl-asm/ir:ir-instruction-operands node))
                  (env   (cl-asm/expression:make-env
                          :symbol-table symtable :pc pc))
                  (bytes (encode-i8080 mnem ops env pc)))
             (dolist (b bytes) (vector-push-extend b result))
             (incf pc (length bytes))))
          (cl-asm/ir:ir-label nil))))
    result))

(defun i8080-directive-pass2 (name args env pc result)
  "Traite une directive en passe 2."
  (case name
    (:org
     (multiple-value-bind (val ok)
         (i8080-eval-expr (first args) env)
       (if ok val pc)))
    (:equ      pc)
    (:defstruct pc)
    (:defenum   pc)
    (:incbin
     (let* ((filename  (first args))
            (offset    (if (second args)
                           (multiple-value-bind (v ok)
                               (i8080-eval-expr (second args) env)
                             (if ok v 0))
                           0))
            (count-arg (when (third args)
                         (multiple-value-bind (v ok)
                             (i8080-eval-expr (third args) env)
                           (when ok v)))))
       (handler-case
           (with-open-file (s filename :element-type '(unsigned-byte 8))
             (let* ((fsize (file-length s))
                    (avail (max 0 (- fsize offset)))
                    (n     (if count-arg (min count-arg avail) avail)))
               (when (> offset 0) (file-position s offset))
               (dotimes (_ n)
                 (let ((b (read-byte s nil nil)))
                   (when b
                     (vector-push-extend b result)
                     (incf pc))))))
         (file-error ()
           (error 'cl-asm/ir:asm-error
                  :message (format nil ".incbin : fichier introuvable \"~A\"" filename)))))
     pc)
    (:section pc)
    (:global  pc)
    (:extern  pc)
    (:byte
     (dolist (arg args)
       (if (stringp arg)
           (loop for c across arg
                 do (vector-push-extend (char-code c) result)
                    (incf pc))
           (multiple-value-bind (val ok)
               (i8080-eval-expr arg env)
             (vector-push-extend (logand (if ok val 0) #xFF) result)
             (incf pc))))
     pc)
    (:pet
     (dolist (arg args)
       (if (stringp arg)
           (loop for c across arg
                 do (vector-push-extend (ascii-to-petscii (char-code c)) result)
                    (incf pc))
           (multiple-value-bind (val ok)
               (i8080-eval-expr arg env)
             (vector-push-extend (logand (if ok val 0) #xFF) result)
             (incf pc))))
     pc)
    (:word
     (dolist (arg args)
       (multiple-value-bind (val ok)
           (i8080-eval-expr arg env)
         (let ((w (if ok val 0)))
           (vector-push-extend (logand w #xFF) result)
           (vector-push-extend (logand (ash w -8) #xFF) result)
           (incf pc 2))))
     pc)
    (:dword
     (dolist (arg args)
       (multiple-value-bind (val ok)
           (i8080-eval-expr arg env)
         (let ((d (if ok val 0)))
           (dotimes (i 4)
             (vector-push-extend (logand (ash d (* -8 i)) #xFF) result))
           (incf pc 4))))
     pc)
    (:fill
     (multiple-value-bind (count ok-n)
         (i8080-eval-expr (first args) env)
       (let ((fill-val (if (second args)
                           (multiple-value-bind (v ok)
                               (i8080-eval-expr (second args) env)
                             (if ok (logand v #xFF) 0))
                           0)))
         (when ok-n
           (dotimes (_ count)
             (vector-push-extend fill-val result)
             (incf pc)))))
     pc)
    (:asciiz
     (let ((str (first args)))
       (when (stringp str)
         (loop for c across str
               do (vector-push-extend (char-code c) result)
                  (incf pc)))
       (vector-push-extend 0 result)
       (incf pc))
     pc)
    (:pascalstr
     (let ((str (first args)))
       (let ((len (if (stringp str) (length str) 0)))
         (vector-push-extend (logand len #xFF) result)
         (incf pc)
         (when (stringp str)
           (loop for c across str
                 do (vector-push-extend (char-code c) result)
                    (incf pc)))))
     pc)
    (:padto
     (multiple-value-bind (target ok)
         (i8080-eval-expr (first args) env)
       (when ok
         (when (> pc target)
           (error 'cl-asm/ir:asm-error
                  :message (format nil ".padto $~X : PC courant ($~X) dépasse la cible"
                                   target pc)))
         (let ((fill-val (if (second args)
                             (multiple-value-bind (v fok)
                                 (i8080-eval-expr (second args) env)
                               (if fok (logand v #xFF) 0))
                             0)))
           (dotimes (_ (- target pc))
             (vector-push-extend fill-val result)
             (incf pc)))))
     pc)
    (:assertpc
     (multiple-value-bind (target ok)
         (i8080-eval-expr (first args) env)
       (when ok
         (unless (= pc target)
           (error 'cl-asm/ir:asm-error
                  :message (format nil ".assertpc $~X : PC courant est $~X"
                                   target pc)))))
     pc)
    (:assertsize
     (let ((expected (first args))
           (lbl      (second args)))
       (multiple-value-bind (start-pc ok)
           (i8080-eval-expr lbl env)
         (when ok
           (let ((actual (- pc start-pc)))
             (unless (= actual expected)
               (error 'cl-asm/ir:asm-error
                      :message (format nil "(assert-size ~D) : bloc émet ~D octet~:P (attendu ~D)"
                                       expected actual expected)))))))
     pc)
    (otherwise pc)))


;;; --------------------------------------------------------------------------
;;;  API publique
;;; --------------------------------------------------------------------------

(defun assemble-i8080 (program &key (origin 0))
  "Assemble un IR-PROGRAM Intel 8080. Retourne un vecteur d'octets."
  (let ((sym (cl-asm/symbol-table:make-symbol-table)))
    (pass-1-i8080 program sym :origin origin)
    (cl-asm/symbol-table:begin-pass-2 sym)
    (pass-2-i8080 program sym :origin origin)))

(defun assemble-string-i8080 (source &key (origin 0))
  "Assemble une chaîne source Intel 8080. Retourne un vecteur d'octets."
  (let* ((cl-asm/parser:*i8080-mode* t)
         (prog (cl-asm/parser:parse-string source)))
    (assemble-i8080 prog :origin origin)))

(defun assemble-file-i8080 (path &key (origin 0))
  "Assemble le fichier PATH Intel 8080. Retourne un vecteur d'octets."
  (let* ((cl-asm/parser:*i8080-mode* t)
         (prog (cl-asm/parser:parse-file path)))
    (assemble-i8080 prog :origin origin)))


;;; --------------------------------------------------------------------------
;;;  Enregistrement du backend
;;; --------------------------------------------------------------------------

(cl-asm/backends:register-backend
 :i8080
 '("i8080" "8080" "cpm" "altair" "intel8080")
 'cl-asm/backend.i8080
 'assemble-file-i8080
 "Intel 8080 (CP/M, Altair)"
 "Intel 8080 (CP/M, Altair)")
