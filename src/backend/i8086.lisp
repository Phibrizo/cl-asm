; -*- coding: utf-8 -*-
;;;; src/backend/i8086.lisp
;;;;
;;;; Backend Intel 8086 pour cl-asm.
;;;; Cibles : IBM PC, MS-DOS, CP/M-86, systèmes embarqués 8086/8088.
;;;;
;;;; Encodage little-endian, instructions de longueur variable (1-6 octets).
;;;; Noyau de l'encodage : le byte ModRM + déplacements optionnels.
;;;;
;;;; Table des codes registres 8086 :
;;;;   16-bit : AX=0 CX=1 DX=2 BX=3 SP=4 BP=5 SI=6 DI=7
;;;;    8-bit : AL=0 CL=1 DL=2 BL=3 AH=4 CH=5 DH=6 BH=7
;;;;   segment: ES=0 CS=1 SS=2 DS=3
;;;;
;;;; Byte ModRM : [mod:2][reg:3][rm:3]
;;;;   mod=00 : mémoire sans déplacement (sauf rm=110 = addr directe)
;;;;   mod=01 : mémoire + disp8  (non utilisé en v1, toujours disp16)
;;;;   mod=10 : mémoire + disp16
;;;;   mod=11 : registre direct
;;;;
;;;; Modes d'adressage mémoire (rm quand mod≠11) :
;;;;   000=[BX+SI] 001=[BX+DI] 010=[BP+SI] 011=[BP+DI]
;;;;   100=[SI]    101=[DI]    110=[BP]    111=[BX]
;;;;   mod=00, rm=110 → adresse directe 16-bit

(defpackage #:cl-asm/backend.i8086
  (:use #:cl)
  (:export
   #:assemble-i8086
   #:assemble-string-i8086
   #:assemble-file-i8086))

(in-package #:cl-asm/backend.i8086)

;;; Déclarations forward
(declaim (ftype (function (t t t t t) t) i8086-directive-pass1))
(declaim (ftype (function (t t t t t) t) i8086-directive-pass2))


;;; --------------------------------------------------------------------------
;;;  Utilitaires bas niveau
;;; --------------------------------------------------------------------------

(defun x86-lo (val) (logand val #xFF))
(defun x86-hi (val) (logand (ash val -8) #xFF))
(defun x86-modrm (mod reg rm) (logior (ash mod 6) (ash reg 3) rm))

(defun x86-s8-p (val) (and (>= val -128) (<= val 127)))
(defun x86-u16 (val) (logand val #xFFFF))

(defun x86-eval (expr env)
  "Évalue EXPR dans ENV. Retourne (values val resolved-p)."
  (cl-asm/expression:eval-expr expr env))

(defun x86-eval! (expr env)
  "Évalue EXPR dans ENV. Erreur si non résolu."
  (multiple-value-bind (val ok)
      (x86-eval expr env)
    (if ok val (error "Expression 8086 non résolue en passe 2 : ~S" expr))))

(defun x86-eval0 (expr env)
  "Évalue EXPR dans ENV. Retourne 0 si non résolu (usage passe 1)."
  (multiple-value-bind (val ok) (x86-eval expr env)
    (if ok val 0)))


;;; --------------------------------------------------------------------------
;;;  Tables de registres
;;; --------------------------------------------------------------------------

;;; Ordre canonique 8086 (code = position dans le vecteur)
(defparameter *reg16-names*
  #("AX" "CX" "DX" "BX" "SP" "BP" "SI" "DI"))

(defparameter *reg8-names*
  #("AL" "CL" "DL" "BL" "AH" "CH" "DH" "BH"))

(defparameter *sreg-names*
  #("ES" "CS" "SS" "DS"))

(defun x86-reg16-code (name)
  "Code 3 bits du registre 16 bits (AX=0..DI=7). NIL si inconnu."
  (position (string-upcase name) *reg16-names* :test #'string=))

(defun x86-reg8-code (name)
  "Code 3 bits du registre 8 bits (AL=0..BH=7). NIL si inconnu."
  (position (string-upcase name) *reg8-names* :test #'string=))

(defun x86-sreg-code (name)
  "Code 2 bits du registre de segment (ES=0..DS=3). NIL si inconnu."
  (position (string-upcase name) *sreg-names* :test #'string=))

(defun x86-reg16-p (name)
  (and (x86-reg16-code (string-upcase name)) t))

(defun x86-reg8-p (name)
  (and (x86-reg8-code (string-upcase name)) t))

(defun x86-sreg-p (name)
  (and (x86-sreg-code (string-upcase name)) t))


;;; --------------------------------------------------------------------------
;;;  Helpers opérandes IR
;;; --------------------------------------------------------------------------

(defun op-kind (op) (cl-asm/ir:ir-operand-kind op))
(defun op-val  (op) (cl-asm/ir:ir-operand-value op))

(defun op-is-reg16-p (op)
  (and (eq (op-kind op) :direct) (stringp (op-val op))
       (x86-reg16-p (op-val op))))

(defun op-is-reg8-p (op)
  (and (eq (op-kind op) :direct) (stringp (op-val op))
       (x86-reg8-p (op-val op))))

(defun op-is-sreg-p (op)
  (and (eq (op-kind op) :direct) (stringp (op-val op))
       (x86-sreg-p (op-val op))))

(defun op-is-mem-p (op)
  (eq (op-kind op) :indirect))

(defun op-is-imm-p (op)
  (eq (op-kind op) :immediate))

(defun op-is-reg-p (op)
  (or (op-is-reg16-p op) (op-is-reg8-p op) (op-is-sreg-p op)))

(defun op-reg16 (op) (x86-reg16-code (op-val op)))
(defun op-reg8  (op) (x86-reg8-code  (op-val op)))
(defun op-sreg  (op) (x86-sreg-code  (op-val op)))

(defun op-reg-name (op) (string-upcase (op-val op)))

(defun op-is-ax-p (op)
  (and (op-is-reg16-p op) (string= (op-reg-name op) "AX")))

(defun op-is-al-p (op)
  (and (op-is-reg8-p op) (string= (op-reg-name op) "AL")))

(defun op-is-cl-p (op)
  (and (op-is-reg8-p op) (string= (op-reg-name op) "CL")))

(defun op-mem-size (op)
  "Taille explicite d'un opérande mémoire : :byte, :word, ou nil."
  (when (op-is-mem-p op)
    (first (op-val op))))

(defun op-mem-base (op)  (second (op-val op)))
(defun op-mem-index (op) (third  (op-val op)))
(defun op-mem-disp (op)  (fourth (op-val op)))


;;; --------------------------------------------------------------------------
;;;  Déduction de taille (word/byte) depuis les opérandes
;;; --------------------------------------------------------------------------

(defun i8086-op-size (op)
  "Retourne :word, :byte, ou nil selon le type d'opérande."
  (cond
    ((op-is-reg16-p op) :word)
    ((op-is-reg8-p  op) :byte)
    ((op-is-mem-p   op) (op-mem-size op))
    (t nil)))

(defun i8086-infer-size (op1 op2 &optional default)
  "Déduit la taille :word ou :byte depuis op1 et op2.
   Utilise DEFAULT si les deux sont ambigus."
  (let ((s1 (i8086-op-size op1))
        (s2 (i8086-op-size op2)))
    (cond
      ((and s1 s2 (not (eq s1 s2)))
       (error "Tailles incompatibles dans l'instruction 8086"))
      (s1 s1)
      (s2 s2)
      (default default)
      (t :word))))

(defun i8086-size-w (sz)
  "Bit w : 1 si word, 0 si byte."
  (if (eq sz :word) 1 0))


;;; --------------------------------------------------------------------------
;;;  Encodage mémoire (ModRM + déplacement)
;;; --------------------------------------------------------------------------

(defun x86-rm-code (base index)
  "Code rm 3 bits pour mode adressage mémoire 16-bit 8086.
   Combinaisons valides : BX+SI=0, BX+DI=1, BP+SI=2, BP+DI=3,
   SI=4, DI=5, BP=6, BX=7, nil+nil=6 (adresse directe)."
  (let ((b (and base (string-upcase base)))
        (i (and index (string-upcase index))))
    (cond
      ((and (equal b "BX") (equal i "SI")) 0)
      ((and (equal b "BX") (equal i "DI")) 1)
      ((and (equal b "BP") (equal i "SI")) 2)
      ((and (equal b "BP") (equal i "DI")) 3)
      ((and (equal b "SI") (null i))       4)
      ((and (equal b "DI") (null i))       5)
      ((and (equal b "BP") (null i))       6)
      ((and (equal b "BX") (null i))       7)
      ((and (null b) (null i))             6)   ; adresse directe
      (t (error "Mode adressage 8086 invalide : base=~A index=~A" base index)))))

(defun x86-mem-byte-count (base index disp-expr)
  "Nombre d'octets pour le couple (modrm + déplacement) en passe 1.
   Toujours disp16 quand il y a un déplacement (cohérence entre passes)."
  (if (and (null base) (null index))
      3                            ; adresse directe : modrm + disp16
    (let* ((bp-alone (and (equal (and base (string-upcase base)) "BP") (null index)))
           (need-disp (or (not (eql disp-expr 0)) bp-alone)))
      (if need-disp 3 1))))       ; modrm+disp16 ou modrm seul

(defun x86-encode-mem (reg-field op env)
  "Encode un opérande mémoire op (kind=:indirect).
   reg-field : code 3 bits placé dans le champ reg du ModRM.
   Retourne une liste d'octets (modrm + déplacement éventuel).
   Stratégie : toujours disp16 quand déplacement ≠ 0 (cohérence passes)."
  (let ((base  (op-mem-base op))
        (index (op-mem-index op))
        (disp  (op-mem-disp op)))
    (if (and (null base) (null index))
        ;; Adresse directe : mod=00, rm=110, disp16
        (let ((addr (x86-eval! disp env)))
          (list (x86-modrm 0 reg-field 6)
                (x86-lo addr) (x86-hi addr)))
      (let* ((rm        (x86-rm-code base index))
             (bp-alone  (and (equal (and base (string-upcase base)) "BP") (null index)))
             (need-disp (or (not (eql disp 0)) bp-alone)))
        (if (not need-disp)
            ;; mod=00 : pas de déplacement
            (list (x86-modrm 0 reg-field rm))
          ;; mod=10 : déplacement 16 bits (toujours, pour cohérence)
          (let ((d (x86-eval! disp env)))
            (list (x86-modrm 2 reg-field rm)
                  (x86-lo d) (x86-hi d))))))))

(defun x86-encode-reg (reg-field rm-reg)
  "Encode reg-reg : mod=11, reg=reg-field, rm=rm-reg → 1 octet ModRM."
  (list (x86-modrm 3 reg-field rm-reg)))


;;; --------------------------------------------------------------------------
;;;  Estimation de taille (passe 1)
;;; --------------------------------------------------------------------------

(defun x86-op-modrm-bytes (op)
  "Nombre d'octets pour le ModRM + déplacement d'un opérande en passe 1."
  (if (op-is-mem-p op)
      (x86-mem-byte-count (op-mem-base op) (op-mem-index op) (op-mem-disp op))
    1))  ; registre : 1 octet modrm

(defun i8086-estimate-size (mnem ops)
  "Estime la taille en octets d'une instruction 8086 pour la passe 1."
  (let ((op1 (first ops))
        (op2 (second ops)))
    (cond
      ;; Instructions 1 octet sans opérande
      ((member mnem
               '("NOP" "HLT" "CLC" "STC" "CMC" "CLD" "STD" "CLI" "STI"
                 "CBW" "CWD" "XLAT" "LAHF" "SAHF" "PUSHF" "POPF"
                 "MOVSB" "MOVSW" "CMPSB" "CMPSW"
                 "STOSB" "STOSW" "LODSB" "LODSW" "SCASB" "SCASW"
                 "IRET" "INTO" "WAIT"
                 "DAA" "DAS" "AAA" "AAS"
                 "REP" "REPE" "REPZ" "REPNE" "REPNZ" "LOCK")
               :test #'string=) 1)
      ;; AAM / AAD : 2 octets (opcode + #x0A implicite)
      ((member mnem '("AAM" "AAD") :test #'string=) 2)
      ;; INTO : 1 octet
      ((string= mnem "INTO") 1)
      ;; RET / RETF : 1 ou 3 octets selon présence imm16
      ((or (string= mnem "RET") (string= mnem "RETF"))
       (if op1 3 1))
      ;; INT 3 : 1 octet ; INT n : 2 octets
      ((string= mnem "INT")
       (if (and op1 (op-is-imm-p op1)) 2 1))
      ;; Jcc : toujours 2 octets (rel8 uniquement en 8086)
      ((member mnem
               '("JO" "JNO" "JB" "JNB" "JE" "JNE" "JBE" "JNBE"
                 "JS" "JNS" "JP" "JNP" "JL" "JNL" "JLE" "JNLE"
                 "JC" "JNC" "JZ" "JNZ" "JA" "JNA" "JAE" "JNAE"
                 "JPE" "JPO" "JG" "JNG" "JGE" "JNGE" "JCXZ")
               :test #'string=) 2)
      ;; LOOP : 2 octets (rel8)
      ((member mnem '("LOOP" "LOOPZ" "LOOPE" "LOOPNZ" "LOOPNE") :test #'string=) 2)
      ;; JMP : SHORT=2, indirect=1+modrm, near=3 (défaut)
      ((string= mnem "JMP")
       (cond
         ((null op1) 1)
         ((eq (op-kind op1) :short-rel) 2)
         ((op-is-mem-p op1) (+ 1 (x86-op-modrm-bytes op1)))
         ((op-is-reg16-p op1) 2)        ; JMP r16 : opcode + modrm
         (t 3)))                         ; near
      ;; CALL : indirect=1+modrm, near=3
      ((string= mnem "CALL")
       (cond
         ((null op1) 1)
         ((op-is-mem-p op1) (+ 1 (x86-op-modrm-bytes op1)))
         ((op-is-reg16-p op1) 2)
         (t 3)))
      ;; PUSH registre/segment : 1 octet ; PUSH mémoire : 1+modrm
      ((string= mnem "PUSH")
       (cond
         ((null op1) 1)
         ((op-is-reg16-p op1) 1)
         ((op-is-sreg-p op1) 1)
         ((op-is-mem-p op1) (+ 1 (x86-op-modrm-bytes op1)))
         (t 1)))
      ;; POP registre/segment : 1 octet ; POP mémoire : 1+modrm
      ((string= mnem "POP")
       (cond
         ((null op1) 1)
         ((op-is-reg16-p op1) 1)
         ((op-is-sreg-p op1) 1)
         ((op-is-mem-p op1) (+ 1 (x86-op-modrm-bytes op1)))
         (t 1)))
      ;; INC/DEC registre 16-bit : 1 ; registre 8-bit : 2 ; mémoire : 1+modrm
      ((member mnem '("INC" "DEC") :test #'string=)
       (cond
         ((op-is-reg16-p op1) 1)
         ((op-is-reg8-p  op1) 2)
         ((op-is-mem-p   op1) (+ 1 (x86-op-modrm-bytes op1)))
         (t 2)))
      ;; NEG/NOT/MUL/DIV/IMUL/IDIV : 1 opcode + modrm
      ((member mnem '("NEG" "NOT" "MUL" "DIV" "IMUL" "IDIV") :test #'string=)
       (+ 1 (x86-op-modrm-bytes op1)))
      ;; Shifts (ROL/ROR/RCL/RCR/SHL/SAL/SHR/SAR) : 1 opcode + modrm
      ((member mnem '("ROL" "ROR" "RCL" "RCR" "SHL" "SAL" "SHR" "SAR") :test #'string=)
       (+ 1 (x86-op-modrm-bytes op1)))
      ;; LEA / LDS / LES : 1 opcode + modrm-mémoire
      ((member mnem '("LEA" "LDS" "LES") :test #'string=)
       (+ 1 (x86-op-modrm-bytes op2)))
      ;; XCHG reg16, AX ou AX, reg16 : 1 octet
      ;; XCHG mémoire : 1+modrm
      ((string= mnem "XCHG")
       (cond
         ((and (op-is-reg16-p op1) (op-is-reg16-p op2)) 2) ; reg-reg : modrm
         ((op-is-mem-p op1) (+ 1 (x86-op-modrm-bytes op1)))
         ((op-is-mem-p op2) (+ 1 (x86-op-modrm-bytes op2)))
         (t 2)))
      ;; IN / OUT : 1 ou 2 octets selon port
      ((string= mnem "IN")
       (if (op-is-reg16-p op2) 1 2))     ; DX=1, imm8=2
      ((string= mnem "OUT")
       (if (op-is-reg16-p op1) 1 2))     ; DX=1, imm8=2
      ;; MOV : variable selon formes
      ((string= mnem "MOV")
       (cond
         ;; MOV reg16, imm16 : 3 octets (#xB8+reg + imm16)
         ((and (op-is-reg16-p op1) (op-is-imm-p op2)) 3)
         ;; MOV reg8, imm8 : 2 octets
         ((and (op-is-reg8-p op1) (op-is-imm-p op2)) 2)
         ;; MOV reg, reg : 2 octets
         ((and (op-is-reg-p op1) (op-is-reg-p op2)) 2)
         ;; MOV reg, mem ou mem, reg : 1+modrm
         ((op-is-mem-p op1)
          (let ((mc (x86-op-modrm-bytes op1)))
            (if (op-is-imm-p op2)
                (+ 1 mc (if (eq (op-mem-size op1) :byte) 1 2)) ; + imm
              (+ 1 mc))))
         ((op-is-mem-p op2) (+ 1 (x86-op-modrm-bytes op2)))
         (t 4)))
      ;; ADD/ADC/SUB/SBB/AND/OR/XOR/CMP : variable
      ((member mnem '("ADD" "ADC" "SUB" "SBB" "AND" "OR" "XOR" "CMP") :test #'string=)
       (cond
         ;; AX/AL, imm → forme courte accumulateur
         ((and (or (op-is-ax-p op1) (op-is-al-p op1)) (op-is-imm-p op2))
          (if (op-is-ax-p op1) 3 2))
         ;; reg, imm : 1 opcode + modrm + imm
         ((and (op-is-reg-p op1) (op-is-imm-p op2))
          (+ 2 (if (eq (i8086-op-size op1) :word) 2 1)))
         ;; reg, reg/mem ou mem, reg : 1+modrm
         ((or (op-is-mem-p op1) (op-is-mem-p op2))
          (+ 1 (x86-op-modrm-bytes (if (op-is-mem-p op1) op1 op2))))
         (t 2)))
      ;; Défaut
      (t 2))))


;;; --------------------------------------------------------------------------
;;;  Encodage des instructions (passe 2)
;;; --------------------------------------------------------------------------

(defun x86-rel8 (target pc-after)
  "Calcule un déplacement relatif 8 bits signé. Erreur si hors portée."
  (let ((rel (- target pc-after)))
    (unless (x86-s8-p rel)
      (error "Déplacement relatif trop grand pour rel8 : ~D (cible $~X, PC=$~X)"
             rel target (- pc-after 2)))
    (logand rel #xFF)))

(defun x86-rel16 (target pc-after)
  "Calcule un déplacement relatif 16 bits signé."
  (let ((rel (logand (- target pc-after) #xFFFF)))
    (list (x86-lo rel) (x86-hi rel))))

(defun encode-alu-reg-imm (opcode-base op-code op1 op2 env)
  "Encode OP r/m, imm.
   opcode-base=#x80/#x81, op-code=sous-opcode (0..7).
   Retourne une liste d'octets."
  (let* ((sz  (i8086-op-size op1))
         (imm (x86-eval! (op-val op2) env))
         (modrm-bytes (if (op-is-reg-p op1)
                          (x86-encode-reg op-code (if (eq sz :word)
                                                      (op-reg16 op1) (op-reg8 op1)))
                        (x86-encode-mem op-code op1 env))))
    (if (eq sz :word)
        (list* (if (eq opcode-base :auto)
                   (if (x86-s8-p imm) #x83 #x81) #x81)
               (append modrm-bytes (list (x86-lo imm) (x86-hi imm))))
      (list* #x80 (append modrm-bytes (list (logand imm #xFF)))))))

(defun encode-alu (op-code op1 op2 env pc)
  "Encode une instruction ALU (ADD/ADC/SUB/SBB/AND/OR/XOR/CMP).
   op-code : 0=ADD 1=OR 2=ADC 3=SBB 4=AND 5=SUB 6=XOR 7=CMP"
  (declare (ignore pc))
  (let ((base (* op-code 8)))
    (cond
      ;; AX, imm16 → forme courte accumulateur
      ((and (op-is-ax-p op1) (op-is-imm-p op2))
       (let ((imm (x86-eval! (op-val op2) env)))
         (list (+ base 5) (x86-lo imm) (x86-hi imm))))
      ;; AL, imm8 → forme courte accumulateur
      ((and (op-is-al-p op1) (op-is-imm-p op2))
       (let ((imm (x86-eval! (op-val op2) env)))
         (list (+ base 4) (logand imm #xFF))))
      ;; reg16, imm → #x81 + modrm + imm16
      ((and (op-is-reg16-p op1) (op-is-imm-p op2))
       (let ((imm (x86-eval! (op-val op2) env)))
         (list* #x81 (append (x86-encode-reg op-code (op-reg16 op1))
                             (list (x86-lo imm) (x86-hi imm))))))
      ;; reg8, imm → #x80 + modrm + imm8
      ((and (op-is-reg8-p op1) (op-is-imm-p op2))
       (let ((imm (x86-eval! (op-val op2) env)))
         (list* #x80 (append (x86-encode-reg op-code (op-reg8 op1))
                             (list (logand imm #xFF))))))
      ;; mem, imm → #x80/#x81 + mem-modrm + imm
      ((and (op-is-mem-p op1) (op-is-imm-p op2))
       (let* ((sz  (or (op-mem-size op1) :word))
              (imm (x86-eval! (op-val op2) env))
              (mb  (x86-encode-mem op-code op1 env)))
         (if (eq sz :word)
             (list* #x81 (append mb (list (x86-lo imm) (x86-hi imm))))
           (list* #x80 (append mb (list (logand imm #xFF)))))))
      ;; reg16, r/m16 (d=1 : dst=reg, src=rm)
      ((and (op-is-reg16-p op1) (or (op-is-reg16-p op2) (op-is-mem-p op2)))
       (let ((mb (if (op-is-mem-p op2)
                     (x86-encode-mem (op-reg16 op1) op2 env)
                   (x86-encode-reg  (op-reg16 op1) (op-reg16 op2)))))
         (list* (+ base 3) mb)))
      ;; r/m16, reg16 (d=0 : dst=rm, src=reg)
      ((and (op-is-reg16-p op2) (or (op-is-reg16-p op1) (op-is-mem-p op1)))
       (let ((mb (if (op-is-mem-p op1)
                     (x86-encode-mem (op-reg16 op2) op1 env)
                   (x86-encode-reg  (op-reg16 op2) (op-reg16 op1)))))
         (list* (+ base 1) mb)))
      ;; reg8, r/m8
      ((and (op-is-reg8-p op1) (or (op-is-reg8-p op2) (op-is-mem-p op2)))
       (let ((mb (if (op-is-mem-p op2)
                     (x86-encode-mem (op-reg8 op1) op2 env)
                   (x86-encode-reg  (op-reg8 op1) (op-reg8 op2)))))
         (list* (+ base 2) mb)))
      ;; r/m8, reg8
      ((and (op-is-reg8-p op2) (or (op-is-reg8-p op1) (op-is-mem-p op1)))
       (let ((mb (if (op-is-mem-p op1)
                     (x86-encode-mem (op-reg8 op2) op1 env)
                   (x86-encode-reg  (op-reg8 op2) (op-reg8 op1)))))
         (list* (+ base 0) mb)))
      (t (error "Encodage ALU 8086 impossible : op1=~S op2=~S" op1 op2)))))

(defun encode-shift (shift-op op1 op2 env)
  "Encode une instruction de décalage/rotation.
   shift-op : ROL=0 ROR=1 RCL=2 RCR=3 SHL/SAL=4 SHR=5 SAR=7.
   op2 doit être 1 (immédiat) ou CL."
  (let* ((sz (or (i8086-op-size op1) :word))
         (w  (i8086-size-w sz))
         (modrm-bytes (if (op-is-reg-p op1)
                          (if (eq sz :word)
                              (x86-encode-reg shift-op (op-reg16 op1))
                            (x86-encode-reg shift-op (op-reg8  op1)))
                        (x86-encode-mem shift-op op1 env))))
    (cond
      ;; count = CL
      ((op-is-cl-p op2)
       (list* (+ #xD2 w) modrm-bytes))
      ;; count = 1 (immédiat)
      ((and (op-is-imm-p op2)
            (let ((v (x86-eval0 (op-val op2) env))) (= v 1)))
       (list* (+ #xD0 w) modrm-bytes))
      ;; count implicite (opérande absent → count=1)
      ((null op2)
       (list* (+ #xD0 w) modrm-bytes))
      (t (error "Le 8086 n'accepte que 1 ou CL comme count pour les shifts")))))

(defun encode-unary-f6 (sub-op op1 env)
  "Encode NEG/NOT/MUL/DIV/IMUL/IDIV : #xF6/#xF7 + ModRM /sub-op."
  (let* ((sz (or (i8086-op-size op1) :word))
         (w  (i8086-size-w sz))
         (mb (if (op-is-reg-p op1)
                 (if (eq sz :word)
                     (x86-encode-reg sub-op (op-reg16 op1))
                   (x86-encode-reg sub-op (op-reg8  op1)))
               (x86-encode-mem sub-op op1 env))))
    (list* (+ #xF6 w) mb)))

(defun encode-i8086 (mnem ops env pc)
  "Encode une instruction 8086. Retourne une liste d'octets."
  (let ((op1 (first ops))
        (op2 (second ops))
        (mnem-up (string-upcase mnem)))
    (cond

      ;; ----------------------------------------------------------------
      ;;  NOP / HLT / drapeaux / préfixes / chaînes
      ;; ----------------------------------------------------------------

      ((string= mnem-up "NOP")   '(#x90))
      ((string= mnem-up "HLT")   '(#xF4))
      ((string= mnem-up "CLC")   '(#xF8))
      ((string= mnem-up "STC")   '(#xF9))
      ((string= mnem-up "CMC")   '(#xF5))
      ((string= mnem-up "CLD")   '(#xFC))
      ((string= mnem-up "STD")   '(#xFD))
      ((string= mnem-up "CLI")   '(#xFA))
      ((string= mnem-up "STI")   '(#xFB))
      ((string= mnem-up "CBW")   '(#x98))
      ((string= mnem-up "CWD")   '(#x99))
      ((string= mnem-up "XLAT")  '(#xD7))
      ((string= mnem-up "LAHF")  '(#x9F))
      ((string= mnem-up "SAHF")  '(#x9E))
      ((string= mnem-up "PUSHF") '(#x9C))
      ((string= mnem-up "POPF")  '(#x9D))
      ((string= mnem-up "WAIT")  '(#x9B))
      ((string= mnem-up "DAA")   '(#x27))
      ((string= mnem-up "DAS")   '(#x2F))
      ((string= mnem-up "AAA")   '(#x37))
      ((string= mnem-up "AAS")   '(#x3F))
      ((string= mnem-up "AAM")   '(#xD4 #x0A))
      ((string= mnem-up "AAD")   '(#xD5 #x0A))

      ;; Préfixes répétition / verrou
      ((string= mnem-up "REP")   '(#xF3))
      ((string= mnem-up "REPE")  '(#xF3))
      ((string= mnem-up "REPZ")  '(#xF3))
      ((string= mnem-up "REPNE") '(#xF2))
      ((string= mnem-up "REPNZ") '(#xF2))
      ((string= mnem-up "LOCK")  '(#xF0))

      ;; Opérations chaînes
      ((string= mnem-up "MOVSB") '(#xA4))
      ((string= mnem-up "MOVSW") '(#xA5))
      ((string= mnem-up "CMPSB") '(#xA6))
      ((string= mnem-up "CMPSW") '(#xA7))
      ((string= mnem-up "STOSB") '(#xAA))
      ((string= mnem-up "STOSW") '(#xAB))
      ((string= mnem-up "LODSB") '(#xAC))
      ((string= mnem-up "LODSW") '(#xAD))
      ((string= mnem-up "SCASB") '(#xAE))
      ((string= mnem-up "SCASW") '(#xAF))

      ;; ----------------------------------------------------------------
      ;;  MOV
      ;; ----------------------------------------------------------------

      ((string= mnem-up "MOV")
       (cond
         ;; MOV reg16, imm16 : #xB8+reg, lo, hi
         ((and (op-is-reg16-p op1) (op-is-imm-p op2))
          (let ((imm (x86-eval! (op-val op2) env)))
            (list (+ #xB8 (op-reg16 op1))
                  (x86-lo imm) (x86-hi imm))))
         ;; MOV reg8, imm8 : #xB0+reg, imm
         ((and (op-is-reg8-p op1) (op-is-imm-p op2))
          (let ((imm (x86-eval! (op-val op2) env)))
            (list (+ #xB0 (op-reg8 op1)) (logand imm #xFF))))
         ;; MOV mem, imm : #xC6/#xC7 + modrm + imm
         ((and (op-is-mem-p op1) (op-is-imm-p op2))
          (let* ((sz  (or (op-mem-size op1) :word))
                 (imm (x86-eval! (op-val op2) env))
                 (mb  (x86-encode-mem 0 op1 env)))
            (if (eq sz :word)
                (list* #xC7 (append mb (list (x86-lo imm) (x86-hi imm))))
              (list* #xC6 (append mb (list (logand imm #xFF)))))))
         ;; MOV reg16, sreg : #x8C + modrm(11, sreg, r16)
         ((and (op-is-reg16-p op1) (op-is-sreg-p op2))
          (list #x8C (x86-modrm 3 (op-sreg op2) (op-reg16 op1))))
         ;; MOV sreg, r/m16 : #x8E + modrm
         ((and (op-is-sreg-p op1) (or (op-is-reg16-p op2) (op-is-mem-p op2)))
          (let ((mb (if (op-is-mem-p op2)
                        (x86-encode-mem (op-sreg op1) op2 env)
                      (x86-encode-reg  (op-sreg op1) (op-reg16 op2)))))
            (list* #x8E mb)))
         ;; MOV r16, r/m16 (d=1 : reg=dst) : #x8B + modrm
         ((and (op-is-reg16-p op1) (or (op-is-reg16-p op2) (op-is-mem-p op2)))
          (let ((mb (if (op-is-mem-p op2)
                        (x86-encode-mem (op-reg16 op1) op2 env)
                      (x86-encode-reg  (op-reg16 op1) (op-reg16 op2)))))
            (list* #x8B mb)))
         ;; MOV r/m16, r16 (d=0 : reg=src) : #x89 + modrm
         ((and (op-is-reg16-p op2) (op-is-mem-p op1))
          (list* #x89 (x86-encode-mem (op-reg16 op2) op1 env)))
         ;; MOV r8, r/m8 : #x8A + modrm
         ((and (op-is-reg8-p op1) (or (op-is-reg8-p op2) (op-is-mem-p op2)))
          (let ((mb (if (op-is-mem-p op2)
                        (x86-encode-mem (op-reg8 op1) op2 env)
                      (x86-encode-reg  (op-reg8 op1) (op-reg8 op2)))))
            (list* #x8A mb)))
         ;; MOV r/m8, r8 : #x88 + modrm
         ((and (op-is-reg8-p op2) (op-is-mem-p op1))
          (list* #x88 (x86-encode-mem (op-reg8 op2) op1 env)))
         (t (error "MOV 8086 : combinaison d'opérandes non supportée : ~S ~S" op1 op2))))

      ;; ----------------------------------------------------------------
      ;;  XCHG
      ;; ----------------------------------------------------------------

      ((string= mnem-up "XCHG")
       (cond
         ;; XCHG AX, reg16 ou reg16, AX : #x90+reg
         ((and (op-is-ax-p op1) (op-is-reg16-p op2))
          (list (+ #x90 (op-reg16 op2))))
         ((and (op-is-reg16-p op1) (op-is-ax-p op2))
          (list (+ #x90 (op-reg16 op1))))
         ;; XCHG r/m16, r16 : #x87 + modrm
         ((and (op-is-reg16-p op2) (or (op-is-reg16-p op1) (op-is-mem-p op1)))
          (let ((mb (if (op-is-mem-p op1)
                        (x86-encode-mem (op-reg16 op2) op1 env)
                      (x86-encode-reg  (op-reg16 op2) (op-reg16 op1)))))
            (list* #x87 mb)))
         ;; XCHG r/m8, r8 : #x86 + modrm
         ((and (op-is-reg8-p op2) (or (op-is-reg8-p op1) (op-is-mem-p op1)))
          (let ((mb (if (op-is-mem-p op1)
                        (x86-encode-mem (op-reg8 op2) op1 env)
                      (x86-encode-reg  (op-reg8 op2) (op-reg8 op1)))))
            (list* #x86 mb)))
         (t (error "XCHG 8086 : opérandes invalides"))))

      ;; ----------------------------------------------------------------
      ;;  LEA / LDS / LES
      ;; ----------------------------------------------------------------

      ((string= mnem-up "LEA")
       (unless (op-is-reg16-p op1)
         (error "LEA : destination doit être un registre 16 bits"))
       (list* #x8D (x86-encode-mem (op-reg16 op1) op2 env)))

      ((string= mnem-up "LDS")
       (unless (op-is-reg16-p op1)
         (error "LDS : destination doit être un registre 16 bits"))
       (list* #xC5 (x86-encode-mem (op-reg16 op1) op2 env)))

      ((string= mnem-up "LES")
       (unless (op-is-reg16-p op1)
         (error "LES : destination doit être un registre 16 bits"))
       (list* #xC4 (x86-encode-mem (op-reg16 op1) op2 env)))

      ;; ----------------------------------------------------------------
      ;;  ALU : ADD ADC SUB SBB AND OR XOR CMP
      ;; ----------------------------------------------------------------

      ((string= mnem-up "ADD") (encode-alu 0 op1 op2 env pc))
      ((string= mnem-up "OR")  (encode-alu 1 op1 op2 env pc))
      ((string= mnem-up "ADC") (encode-alu 2 op1 op2 env pc))
      ((string= mnem-up "SBB") (encode-alu 3 op1 op2 env pc))
      ((string= mnem-up "AND") (encode-alu 4 op1 op2 env pc))
      ((string= mnem-up "SUB") (encode-alu 5 op1 op2 env pc))
      ((string= mnem-up "XOR") (encode-alu 6 op1 op2 env pc))
      ((string= mnem-up "CMP") (encode-alu 7 op1 op2 env pc))

      ;; ----------------------------------------------------------------
      ;;  INC / DEC
      ;; ----------------------------------------------------------------

      ((string= mnem-up "INC")
       (cond
         ((op-is-reg16-p op1) (list (+ #x40 (op-reg16 op1))))
         ((op-is-reg8-p  op1) (list* #xFE (x86-encode-reg 0 (op-reg8 op1))))
         ((op-is-mem-p   op1)
          (let* ((sz (or (op-mem-size op1) :word))
                 (w  (i8086-size-w sz)))
            (list* (+ #xFE w) (x86-encode-mem 0 op1 env))))
         (t (error "INC : opérande invalide"))))

      ((string= mnem-up "DEC")
       (cond
         ((op-is-reg16-p op1) (list (+ #x48 (op-reg16 op1))))
         ((op-is-reg8-p  op1) (list* #xFE (x86-encode-reg 1 (op-reg8 op1))))
         ((op-is-mem-p   op1)
          (let* ((sz (or (op-mem-size op1) :word))
                 (w  (i8086-size-w sz)))
            (list* (+ #xFE w) (x86-encode-mem 1 op1 env))))
         (t (error "DEC : opérande invalide"))))

      ;; ----------------------------------------------------------------
      ;;  NEG / NOT / MUL / DIV / IMUL / IDIV
      ;; ----------------------------------------------------------------

      ((string= mnem-up "NEG")  (encode-unary-f6 3 op1 env))
      ((string= mnem-up "NOT")  (encode-unary-f6 2 op1 env))
      ((string= mnem-up "MUL")  (encode-unary-f6 4 op1 env))
      ((string= mnem-up "IMUL") (encode-unary-f6 5 op1 env))
      ((string= mnem-up "DIV")  (encode-unary-f6 6 op1 env))
      ((string= mnem-up "IDIV") (encode-unary-f6 7 op1 env))

      ;; ----------------------------------------------------------------
      ;;  Shifts et rotations
      ;; ----------------------------------------------------------------

      ((string= mnem-up "ROL") (encode-shift 0 op1 op2 env))
      ((string= mnem-up "ROR") (encode-shift 1 op1 op2 env))
      ((string= mnem-up "RCL") (encode-shift 2 op1 op2 env))
      ((string= mnem-up "RCR") (encode-shift 3 op1 op2 env))
      ((or (string= mnem-up "SHL") (string= mnem-up "SAL"))
       (encode-shift 4 op1 op2 env))
      ((string= mnem-up "SHR") (encode-shift 5 op1 op2 env))
      ((string= mnem-up "SAR") (encode-shift 7 op1 op2 env))

      ;; ----------------------------------------------------------------
      ;;  PUSH / POP
      ;; ----------------------------------------------------------------

      ((string= mnem-up "PUSH")
       (cond
         ((op-is-reg16-p op1) (list (+ #x50 (op-reg16 op1))))
         ((op-is-sreg-p op1)
          (case (op-sreg op1)
            (0 '(#x06))   ; ES
            (1 '(#x0E))   ; CS
            (2 '(#x16))   ; SS
            (3 '(#x1E))   ; DS
            (t (error "PUSH sreg inconnu"))))
         ((op-is-mem-p op1)
          (list* #xFF (x86-encode-mem 6 op1 env)))
         (t (error "PUSH : opérande invalide"))))

      ((string= mnem-up "POP")
       (cond
         ((op-is-reg16-p op1) (list (+ #x58 (op-reg16 op1))))
         ((op-is-sreg-p op1)
          (case (op-sreg op1)
            (0 '(#x07))   ; ES
            (2 '(#x17))   ; SS
            (3 '(#x1F))   ; DS
            (t (error "POP CS est invalide"))))
         ((op-is-mem-p op1)
          (list* #x8F (x86-encode-mem 0 op1 env)))
         (t (error "POP : opérande invalide"))))

      ;; ----------------------------------------------------------------
      ;;  Sauts conditionnels (Jcc) — rel8 uniquement en 8086
      ;; ----------------------------------------------------------------

      ;; Table opcode Jcc : JO=70 JNO=71 JB/JC/JNAE=72 JNB/JNC/JAE=73
      ;;   JZ/JE=74 JNZ/JNE=75 JBE/JNA=76 JNBE/JA=77
      ;;   JS=78 JNS=79 JP/JPE=7A JNP/JPO=7B JL/JNGE=7C JNL/JGE=7D
      ;;   JLE/JNG=7E JNLE/JG=7F

      ((member mnem-up '("JO")                      :test #'string=)
       (list #x70 (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JNO")                     :test #'string=)
       (list #x71 (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JB" "JC" "JNAE")          :test #'string=)
       (list #x72 (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JNB" "JNC" "JAE")         :test #'string=)
       (list #x73 (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JZ" "JE")                 :test #'string=)
       (list #x74 (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JNZ" "JNE")               :test #'string=)
       (list #x75 (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JBE" "JNA")               :test #'string=)
       (list #x76 (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JNBE" "JA")               :test #'string=)
       (list #x77 (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JS")                      :test #'string=)
       (list #x78 (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JNS")                     :test #'string=)
       (list #x79 (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JP" "JPE")                :test #'string=)
       (list #x7A (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JNP" "JPO")               :test #'string=)
       (list #x7B (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JL" "JNGE")               :test #'string=)
       (list #x7C (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JNL" "JGE")               :test #'string=)
       (list #x7D (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JLE" "JNG")               :test #'string=)
       (list #x7E (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("JNLE" "JG")               :test #'string=)
       (list #x7F (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))

      ;; ----------------------------------------------------------------
      ;;  JCXZ / LOOP
      ;; ----------------------------------------------------------------

      ((string= mnem-up "JCXZ")
       (list #xE3 (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("LOOP") :test #'string=)
       (list #xE2 (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("LOOPZ" "LOOPE") :test #'string=)
       (list #xE1 (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
      ((member mnem-up '("LOOPNZ" "LOOPNE") :test #'string=)
       (list #xE0 (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))

      ;; ----------------------------------------------------------------
      ;;  JMP
      ;; ----------------------------------------------------------------

      ((string= mnem-up "JMP")
       (cond
         ;; JMP SHORT label → rel8
         ((eq (op-kind op1) :short-rel)
          (list #xEB (x86-rel8 (x86-eval! (op-val op1) env) (+ pc 2))))
         ;; JMP r16 → #xFF /4
         ((op-is-reg16-p op1)
          (list* #xFF (x86-encode-reg 4 (op-reg16 op1))))
         ;; JMP [mem] → #xFF /4
         ((op-is-mem-p op1)
          (list* #xFF (x86-encode-mem 4 op1 env)))
         ;; JMP near imm/label → rel16
         (t
          (let* ((target (x86-eval! (op-val op1) env))
                 (rel    (x86-rel16 target (+ pc 3))))
            (list* #xE9 rel)))))

      ;; ----------------------------------------------------------------
      ;;  CALL
      ;; ----------------------------------------------------------------

      ((string= mnem-up "CALL")
       (cond
         ;; CALL r16 → #xFF /2
         ((op-is-reg16-p op1)
          (list* #xFF (x86-encode-reg 2 (op-reg16 op1))))
         ;; CALL [mem] → #xFF /2
         ((op-is-mem-p op1)
          (list* #xFF (x86-encode-mem 2 op1 env)))
         ;; CALL near imm/label → rel16
         (t
          (let* ((target (x86-eval! (op-val op1) env))
                 (rel    (x86-rel16 target (+ pc 3))))
            (list* #xE8 rel)))))

      ;; ----------------------------------------------------------------
      ;;  RET / RETF / IRET / INTO
      ;; ----------------------------------------------------------------

      ((string= mnem-up "RET")
       (if op1
           (let ((n (x86-eval! (op-val op1) env)))
             (list #xC2 (x86-lo n) (x86-hi n)))
         '(#xC3)))

      ((string= mnem-up "RETF")
       (if op1
           (let ((n (x86-eval! (op-val op1) env)))
             (list #xCA (x86-lo n) (x86-hi n)))
         '(#xCB)))

      ((string= mnem-up "IRET")  '(#xCF))
      ((string= mnem-up "INTO")  '(#xCE))

      ;; ----------------------------------------------------------------
      ;;  INT
      ;; ----------------------------------------------------------------

      ((string= mnem-up "INT")
       (let ((n (x86-eval! (op-val op1) env)))
         (if (= n 3)
             '(#xCC)
           (list #xCD (logand n #xFF)))))

      ;; ----------------------------------------------------------------
      ;;  IN / OUT
      ;; ----------------------------------------------------------------

      ((string= mnem-up "IN")
       ;; IN AL/AX, imm8 ou IN AL/AX, DX
       (let ((w (if (op-is-ax-p op1) 1 0)))
         (if (op-is-reg16-p op2)   ; DX
             (list (+ #xEC w))
           (list (+ #xE4 w) (logand (x86-eval! (op-val op2) env) #xFF)))))

      ((string= mnem-up "OUT")
       ;; OUT imm8, AL/AX ou OUT DX, AL/AX
       (let ((w (if (op-is-ax-p op2) 1 0)))
         (if (op-is-reg16-p op1)   ; DX
             (list (+ #xEE w))
           (list (+ #xE6 w) (logand (x86-eval! (op-val op1) env) #xFF)))))

      ;; ----------------------------------------------------------------
      ;;  Mnémonique inconnu
      ;; ----------------------------------------------------------------

      (t (error "Mnémonique 8086 inconnu : ~A" mnem-up)))))


;;; --------------------------------------------------------------------------
;;;  Directives (passe 1)
;;; --------------------------------------------------------------------------

(defun i8086-eval-expr (expr env)
  (cl-asm/expression:eval-expr expr env))

(defun i8086-string-is-literal-p (arg symtable)
  (and (stringp arg)
       (or (null symtable)
           (not (cl-asm/symbol-table:symbol-defined-p symtable arg)))))

(defun i8086-directive-pass1 (name args env pc symtable)
  "Traite une directive en passe 1. Retourne le nouveau PC."
  (case name
    (:org
     (multiple-value-bind (val ok) (i8086-eval-expr (first args) env)
       (if ok val pc)))
    (:equ
     (multiple-value-bind (val ok) (i8086-eval-expr (second args) env)
       (when ok
         (cl-asm/symbol-table:define-constant symtable (first args) val)))
     pc)
    ((:byte :pet)
     (+ pc (reduce #'+ args
                   :key (lambda (a) (if (stringp a) (length a) 1))
                   :initial-value 0)))
    (:word  (+ pc (* 2 (length args))))
    (:dword (+ pc (* 4 (length args))))
    (:asciiz    (+ pc (if (stringp (first args)) (length (first args)) 0) 1))
    (:pascalstr (+ pc (if (stringp (first args)) (length (first args)) 0) 1))
    (:fill
     (multiple-value-bind (n ok) (i8086-eval-expr (first args) env)
       (if ok (+ pc n) pc)))
    (:padto
     (multiple-value-bind (target ok) (i8086-eval-expr (first args) env)
       (if ok (max pc target) pc)))
    (:incbin
     (let* ((filename (first args))
            (offset   (if (second args)
                          (multiple-value-bind (v ok)
                              (i8086-eval-expr (second args) env)
                            (if ok v 0))
                        0))
            (count-arg (when (third args)
                         (multiple-value-bind (v ok)
                             (i8086-eval-expr (third args) env)
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
    (:assertpc pc)
    (:assertsize pc)
    (:defstruct
     (let* ((struct-name (first args))
            (fields      (second args))
            (offset      0))
       (dolist (field fields)
         (cl-asm/symbol-table:define-constant
          symtable (format nil "~A.~A" struct-name (car field)) offset)
         (incf offset (cdr field)))
       (cl-asm/symbol-table:define-constant
        symtable (format nil "~A.SIZE" struct-name) offset))
     pc)
    (:defenum
     (let ((enum-name (first args))
           (values    (second args)))
       (dolist (entry values)
         (cl-asm/symbol-table:define-constant
          symtable (format nil "~A.~A" enum-name (car entry)) (cdr entry)))
       (cl-asm/symbol-table:define-constant
        symtable (format nil "~A.COUNT" enum-name) (length values)))
     pc)
    (otherwise pc)))


;;; --------------------------------------------------------------------------
;;;  Directives (passe 2)
;;; --------------------------------------------------------------------------

(defun i8086-directive-pass2 (name args env pc result)
  "Traite une directive en passe 2. Retourne le nouveau PC."
  (case name
    (:org
     (multiple-value-bind (val ok) (i8086-eval-expr (first args) env)
       (if ok val pc)))
    (:equ pc)
    (:defstruct pc)
    (:defenum pc)
    ((:byte :pet)
     (dolist (arg args)
       (if (i8086-string-is-literal-p arg (cl-asm/expression:env-symbol-table env))
           (loop for c across arg
                 do (vector-push-extend (char-code c) result) (incf pc))
         (multiple-value-bind (val ok) (i8086-eval-expr arg env)
           (vector-push-extend (logand (if ok val 0) #xFF) result)
           (incf pc))))
     pc)
    (:word
     (dolist (arg args)
       (if (i8086-string-is-literal-p arg (cl-asm/expression:env-symbol-table env))
           (loop for c across arg
                 do (vector-push-extend (char-code c) result)
                    (vector-push-extend 0 result)
                    (incf pc 2))
         (multiple-value-bind (val ok) (i8086-eval-expr arg env)
           (let ((v (if ok val 0)))
             (vector-push-extend (x86-lo v) result)
             (vector-push-extend (x86-hi v) result)
             (incf pc 2)))))
     pc)
    (:dword
     (dolist (arg args)
       (multiple-value-bind (val ok) (i8086-eval-expr arg env)
         (let ((v (if ok val 0)))
           (vector-push-extend (x86-lo v)            result)
           (vector-push-extend (x86-hi v)            result)
           (vector-push-extend (logand (ash v -16) #xFF) result)
           (vector-push-extend (logand (ash v -24) #xFF) result)
           (incf pc 4))))
     pc)
    (:asciiz
     (let ((s (first args)))
       (when (stringp s)
         (loop for c across s
               do (vector-push-extend (char-code c) result) (incf pc)))
       (vector-push-extend 0 result)
       (incf pc))
     pc)
    (:pascalstr
     (let ((s (first args)))
       (when (stringp s)
         (vector-push-extend (length s) result)
         (incf pc)
         (loop for c across s
               do (vector-push-extend (char-code c) result) (incf pc))))
     pc)
    (:fill
     (multiple-value-bind (n ok) (i8086-eval-expr (first args) env)
       (when ok
         (let ((fill-val (if (second args)
                             (multiple-value-bind (v fok)
                                 (i8086-eval-expr (second args) env)
                               (if fok (logand v #xFF) 0))
                           0)))
           (dotimes (i n)
             (vector-push-extend fill-val result)
             (incf pc)))))
     pc)
    (:padto
     (multiple-value-bind (target ok) (i8086-eval-expr (first args) env)
       (when ok
         (when (> pc target)
           (error 'cl-asm/ir:asm-error
                  :message (format nil ".padto $~X : PC courant ($~X) dépasse la cible"
                                   target pc)))
         (let ((fill-val (if (second args)
                             (multiple-value-bind (v fok)
                                 (i8086-eval-expr (second args) env)
                               (if fok (logand v #xFF) 0))
                           0)))
           (dotimes (i (- target pc))
             (vector-push-extend fill-val result)
             (incf pc)))))
     pc)
    (:incbin
     (let* ((filename  (first args))
            (offset    (if (second args)
                           (multiple-value-bind (v ok)
                               (i8086-eval-expr (second args) env)
                             (if ok v 0))
                         0))
            (count-arg (when (third args)
                         (multiple-value-bind (v ok)
                             (i8086-eval-expr (third args) env)
                           (when ok v)))))
       (handler-case
           (with-open-file (s filename :element-type '(unsigned-byte 8))
             (let* ((fsize (file-length s))
                    (avail (max 0 (- fsize offset)))
                    (n     (if count-arg (min count-arg avail) avail)))
               (when (> offset 0) (file-position s offset))
               (dotimes (_ n)
                 (let ((b (read-byte s nil nil)))
                   (when b (vector-push-extend b result) (incf pc))))))
         (file-error ()
           (error 'cl-asm/ir:asm-error
                  :message (format nil ".incbin : fichier introuvable \"~A\"" filename)))))
     pc)
    (:assertpc
     (multiple-value-bind (target ok) (i8086-eval-expr (first args) env)
       (when ok
         (unless (= pc target)
           (error 'cl-asm/ir:asm-error
                  :message (format nil ".assertpc $~X : PC courant est $~X" target pc)))))
     pc)
    (:assertsize
     (let ((expected (first args)) (lbl (second args)))
       (multiple-value-bind (start-pc ok) (i8086-eval-expr lbl env)
         (when ok
           (let ((actual (- pc start-pc)))
             (unless (= actual expected)
               (error 'cl-asm/ir:asm-error
                      :message (format nil "(assert-size ~D) : bloc émet ~D octet~:P"
                                       expected actual)))))))
     pc)
    (otherwise pc)))


;;; --------------------------------------------------------------------------
;;;  Assemblage deux passes
;;; --------------------------------------------------------------------------

(defun pass-1-i8086 (program symtable &key (origin 0))
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
             (setf pc (i8086-directive-pass1
                       (cl-asm/ir:ir-directive-name node)
                       (cl-asm/ir:ir-directive-args node)
                       env pc symtable))))
          (cl-asm/ir:ir-instruction
           (let ((mnem (string-upcase (cl-asm/ir:ir-instruction-mnemonic node)))
                 (ops  (cl-asm/ir:ir-instruction-operands node)))
             (incf pc (i8086-estimate-size mnem ops)))))))
    pc))

(defun pass-2-i8086 (program symtable &key (origin 0))
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
             (setf pc (i8086-directive-pass2
                       (cl-asm/ir:ir-directive-name node)
                       (cl-asm/ir:ir-directive-args node)
                       env pc result))))
          (cl-asm/ir:ir-instruction
           (let* ((mnem  (cl-asm/ir:ir-instruction-mnemonic node))
                  (ops   (cl-asm/ir:ir-instruction-operands node))
                  (env   (cl-asm/expression:make-env
                          :symbol-table symtable :pc pc))
                  (bytes (encode-i8086 mnem ops env pc)))
             (dolist (b bytes) (vector-push-extend b result))
             (incf pc (length bytes))))
          (cl-asm/ir:ir-label nil))))
    result))


;;; --------------------------------------------------------------------------
;;;  API publique
;;; --------------------------------------------------------------------------

(defun assemble-i8086 (program &key (origin 0))
  "Assemble un IR-PROGRAM Intel 8086. Retourne un vecteur d'octets."
  (let ((sym (cl-asm/symbol-table:make-symbol-table)))
    (pass-1-i8086 program sym :origin origin)
    (cl-asm/symbol-table:begin-pass-2 sym)
    (pass-2-i8086 program sym :origin origin)))

(defun assemble-string-i8086 (source &key (origin 0))
  "Assemble une chaîne source Intel 8086. Retourne un vecteur d'octets."
  (let* ((cl-asm/parser:*i8086-mode* t)
         (cl-asm/lexer:*star-comment-col1* t)
         (prog (cl-asm/parser:parse-string source)))
    (assemble-i8086 prog :origin origin)))

(defun assemble-file-i8086 (path &key (origin 0))
  "Assemble le fichier PATH Intel 8086. Retourne un vecteur d'octets."
  (let* ((cl-asm/parser:*i8086-mode* t)
         (cl-asm/lexer:*star-comment-col1* t)
         (prog (cl-asm/parser:parse-file path)))
    (assemble-i8086 prog :origin origin)))


;;; --------------------------------------------------------------------------
;;;  Enregistrement du backend
;;; --------------------------------------------------------------------------

(cl-asm/backends:register-backend
 :i8086
 '("8086" "i8086" "8088" "i8088" "ibmpc" "msdos" "x86-16")
 'cl-asm/backend.i8086
 'assemble-file-i8086
 "Intel 8086/8088 — IBM PC, MS-DOS, CP/M-86"
 "Intel 8086/8088 — IBM PC, MS-DOS, CP/M-86")
