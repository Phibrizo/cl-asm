; -*- coding: utf-8 -*-
;;; src/frontend/lasm.lisp
;;;
;;; Frontend .lasm : les fichiers source sont du Common Lisp valide
;;; qui s'execute dans un contexte ou les mnemoniques sont des fonctions.
;;;
;;; Convention de nommage et modes d'adressage :
;;;
;;;   Sans keyword — mode deduit de la valeur :
;;;     (lda #x10)        → LDA $10   (zero-page, valeur ≤ 255)
;;;     (lda #x1234)      → LDA $1234 (absolu, valeur > 255)
;;;     (lda 'screen)     → LDA SCREEN (symbole, résolu à l'assemblage)
;;;
;;;   Avec keyword — mode explicite :
;;;     (lda :imm #xFF)   → LDA #$FF  (immediat)
;;;     (lda :imm 'cols)  → LDA #COLS (immediat symbolique)
;;;     (lda :x   #x10)   → LDA $10,X (indexé X)
;;;     (lda :y   #x1234) → LDA $1234,Y (indexé Y)
;;;     (lda :ind #xFFFC) → JMP ($FFFC) (indirect)
;;;     (lda :ix  #x00)   → LDA ($00,X) (indirect pre-indexé X)
;;;     (lda :iy  #xB0)   → LDA ($B0),Y (indirect post-indexé Y)
;;;     (lda :iz  #xB0)   → LDA ($B0),Z (45GS02 indirect post-indexé Z)
;;;     (lda :abs #x10)   → LDA $0010  (force le mode absolu)
;;;     (lda :zp  #x10)   → LDA $10    (force le mode zero-page)
;;;
;;;   Instructions implicites / accumulateur :
;;;     (nop)             → NOP
;;;     (rts)             → RTS
;;;     (lsr :a)          → LSR A
;;;
;;;   Directives :
;;;     (org #x0801)
;;;     (label 'start)    → emplace le label START ici
;;;     (db #x01 #x02)    → .byte
;;;     (dw #x1234)       → .word (little-endian)
;;;     (fill 10 #x00)    → .fill
;;;     (section :data)
;;;     (equ 'cols 40)    → COLS = 40
;;;
;;;   Lisp natif disponible :
;;;     let, dotimes, loop, defun, defmacro, if, cond, etc.
;;;     Toute la puissance de Common Lisp est accessible.


(defpackage #:cl-asm/lasm
  (:use #:cl)
  ;; Ces noms conflictent avec des symboles CL standards.
  ;; :shadow cree des copies locales qui masquent la version CL.
  ;; Dans le corps de ce fichier, cl:and, cl:bit etc. restent
  ;; accessibles avec leur prefixe explicite si necessaire.
  (:shadow #:fill #:bit #:sec #:and #:map)
  (:export
   #:load-lasm
   #:load-lasm-string
   #:lasm-program
   #:assemble-lasm
   #:assemble-lasm-string
   #:defstruct-asm
   #:defenum
   #:include-binary
   #:petscii
   #:assert-size
   #:sine-table
   #:cosine-table
   #:linear-ramp
   ;; Helpers Intel 8080
   #:i8080r
   #:i8080rp
   #:i8080))

(in-package #:cl-asm/lasm)


;;; --------------------------------------------------------------------------
;;;  Contexte d'assemblage .lasm
;;; --------------------------------------------------------------------------

(defstruct lasm-context
  "Etat courant pendant l'execution d'un fichier .lasm."
  ;; Programme IR en cours de construction
  (program  nil)
  ;; Section courante
  (section  nil)
  ;; Table des symboles
  (symtable nil)
  ;; Compteur de labels anonymes
  (label-counter 0 :type fixnum))

(defvar *ctx* nil
  "Contexte .lasm courant (lie dynamiquement pendant load-lasm).")


;;; --------------------------------------------------------------------------
;;;  Helpers internes
;;; --------------------------------------------------------------------------

(defun current-section ()
  (lasm-context-section *ctx*))

(defun emit (node)
  "Ajoute NODE a la section courante."
  (cl-asm/ir:section-append (current-section) node))

(defun sym->string (sym)
  "Convertit un symbole ou une string en string majuscules."
  (etypecase sym
    (symbol (string-upcase (symbol-name sym)))
    (string (string-upcase sym))))

(defun make-expr (val)
  "Convertit une valeur Lisp en expression IR.
   Entier → entier. Symbole/string → nom de label."
  (etypecase val
    (integer val)
    (symbol  (sym->string val))
    (string  (string-upcase val))
    (list    val)))   ; expression deja sous forme d'arbre prefixe

(defun resolve-mode-and-operand (keyword val)
  "Construit un IR-OPERAND depuis un keyword de mode et une valeur."
  (let ((expr (make-expr val)))
    (ecase keyword
      (:imm
       (cl-asm/ir:make-ir-operand :kind :immediate :value expr))
      (:a
       (cl-asm/ir:make-ir-operand :kind :register  :value "A"))
      (:x
       (cl-asm/ir:make-ir-operand :kind :direct    :value expr
                                   :index-reg :x))
      (:y
       (cl-asm/ir:make-ir-operand :kind :direct    :value expr
                                   :index-reg :y))
      (:z
       (cl-asm/ir:make-ir-operand :kind :direct    :value expr
                                   :index-reg :z))
      (:ind
       (cl-asm/ir:make-ir-operand :kind :indirect  :value expr))
      (:ix
       (cl-asm/ir:make-ir-operand :kind :indirect-x :value expr
                                   :index-reg :x))
      (:iy
       (cl-asm/ir:make-ir-operand :kind :indirect-y :value expr
                                   :index-reg :y))
      (:iz
       (cl-asm/ir:make-ir-operand :kind :indirect-y :value expr
                                   :index-reg :z))
      (:abs
       (cl-asm/ir:make-ir-operand :kind :direct    :value expr
                                   :size-hint :word))
      (:zp
       (cl-asm/ir:make-ir-operand :kind :direct    :value expr
                                   :size-hint :byte)))))

(defun auto-operand (val)
  "Deduit le mode d'adressage depuis la valeur seule (sans keyword).
   Entier ≤ 255 → zero-page. Entier > 255 → absolu.
   Symbole/string → absolu (resolu a l'assemblage)."
  (let ((expr (make-expr val)))
    (cond
      ((cl:and (integerp val) (<= 0 val 255))
       (cl-asm/ir:make-ir-operand :kind :direct :value expr))
      ((integerp val)
       (cl-asm/ir:make-ir-operand :kind :direct :value expr
                                   :size-hint :word))
      (t
       ;; Symbole ou expression → absolu par defaut
       (cl-asm/ir:make-ir-operand :kind :direct :value expr)))))

(defun make-instr (mnemonic &optional keyword val)
  "Construit et emet une IR-INSTRUCTION.
   Formes possibles :
     (make-instr \"NOP\")               → implied
     (make-instr \"LSR\" :a nil)        → accumulator
     (make-instr \"LDA\" :imm #xFF)     → immediat
     (make-instr \"LDA\" nil #x10)      → auto-deduit
     (make-instr \"LDA\" :x #x10)       → indexe X"
  (let ((operand
          (cond
            ;; Pas d'operande → implied
            ((cl:and (null keyword) (null val))
             nil)
            ;; Keyword :a → accumulateur
            ((eq keyword :a)
             (cl-asm/ir:make-ir-operand :kind :register :value "A"))
            ;; Keyword explicite
            (keyword
             (resolve-mode-and-operand keyword val))
            ;; Pas de keyword → deduction automatique
            (val
             (auto-operand val))
            (t nil))))
    (emit (cl-asm/ir:make-ir-instruction
           :mnemonic (string-upcase mnemonic)
           :operands (if operand (list operand) nil)))))


;;; --------------------------------------------------------------------------
;;;  Directives
;;; --------------------------------------------------------------------------

(defun org (address)
  "Definit l'adresse d'origine."
  (emit (cl-asm/ir:make-ir-directive
         :name :org :args (list address))))

(defun label (name)
  "Emplace un label a la position courante."
  (emit (cl-asm/ir:make-ir-label
         :name (sym->string name)
         :kind :local)))

(defun global-label (name)
  "Emplace un label global a la position courante."
  (emit (cl-asm/ir:make-ir-label
         :name (sym->string name)
         :kind :global)))

(defun equ (name value)
  "Definit une constante : (equ 'cols 40) → COLS = 40"
  (emit (cl-asm/ir:make-ir-directive
         :name :equ
         :args (list (sym->string name) value))))

(defun db (&rest values)
  "Emet des octets : (db #x01 #x02 #x03)"
  (emit (cl-asm/ir:make-ir-directive
         :name :byte :args values)))

(defun dw (&rest values)
  "Emet des mots 16 bits (little-endian) : (dw #x1234)"
  (emit (cl-asm/ir:make-ir-directive
         :name :word :args values)))

(defun dd (&rest values)
  "Emet des mots 32 bits (little-endian) : (dd #x12345678)"
  (emit (cl-asm/ir:make-ir-directive
         :name :dword :args values)))

(defun text (string)
  "Emet une chaine ASCII : (text \"HELLO\")"
  (emit (cl-asm/ir:make-ir-directive
         :name :text :args (list string))))

(defun fill (count &optional (value 0))
  "Emet COUNT octets de valeur VALUE : (fill 10 #x00)"
  (emit (cl-asm/ir:make-ir-directive
         :name :fill :args (list count value))))

(defun align (boundary &optional (value 0))
  "Aligne sur BOUNDARY octets."
  (emit (cl-asm/ir:make-ir-directive
         :name :align :args (list boundary value))))

(defun pad-to (address &optional fill-value)
  "Remplit depuis le PC courant jusqu'a ADDRESS avec FILL-VALUE (defaut $00).
   Ex : (pad-to #xBFFF) ou (pad-to #xBFFF #xFF)"
  (emit (cl-asm/ir:make-ir-directive
         :name :padto
         :args (if fill-value (list address fill-value) (list address)))))

(defun assert-pc (address)
  "Erreur si le PC courant n'est pas exactement ADDRESS.
   Ex : (assert-pc #x0900)"
  (emit (cl-asm/ir:make-ir-directive
         :name :assertpc :args (list address))))

(defun ascii-z (str)
  "Emet STR en ASCII suivi d'un octet nul : (ascii-z \"HELLO\")"
  (emit (cl-asm/ir:make-ir-directive
         :name :asciiz :args (list str))))

(defun pascal-str (str)
  "Emet un octet de longueur suivi de STR : (pascal-str \"HELLO\")"
  (emit (cl-asm/ir:make-ir-directive
         :name :pascalstr :args (list str))))

(defun petscii (str)
  "Emet STR avec conversion ASCII→PETSCII : (petscii \"Hello\")
   a-z → A-Z PETSCII, A-Z → shifted PETSCII (comme ACME !PET)."
  (emit (cl-asm/ir:make-ir-directive
         :name :pet :args (list str))))

(defun include-binary (filename &optional offset count)
  "Inclut un fichier binaire comme données brutes.
   OFFSET (défaut 0) : octet de départ dans le fichier.
   COUNT  (défaut nil) : nombre d'octets à émettre (nil = tout le reste).
   Ex: (include-binary \"sprite.bin\")
       (include-binary \"sheet.bin\" 64 16)"
  (emit (cl-asm/ir:make-ir-directive
         :name :incbin
         :args (cl:append (list filename)
                          (when offset (list offset))
                          (when count  (list count))))))

(defmacro defenum (name &rest values)
  "Définit un enum avec constantes auto-numérotées à partir de 0.
   Chaque valeur est un keyword.
   Ex: (defenum color :black :white :red)
   → COLOR.BLACK=0, COLOR.WHITE=1, COLOR.RED=2, COLOR.COUNT=3"
  (let* ((ename (string-upcase (string name)))
         (alist (loop for v in values
                      for i from 0
                      collect (cons (string-upcase (string v)) i))))
    `(emit (cl-asm/ir:make-ir-directive
            :name :defenum
            :args (list ,ename ',alist)))))

;;; --------------------------------------------------------------------------
;;;  Tables mathématiques
;;; --------------------------------------------------------------------------

(defun sine-table (label n amplitude offset)
  "Emet N octets : sin(i*2π/N)*amplitude + offset, pour i de 0 à N-1.
   Place un label si fourni.
   Ex: (sine-table 'sin-tbl 256 127 128)"
  (when label (label label))
  (let ((bytes (loop for i from 0 below n
                     collect (logand (round (+ offset
                                               (* amplitude (sin (* i 2 pi (/ 1 n))))))
                                     #xFF))))
    (emit (cl-asm/ir:make-ir-directive :name :byte :args bytes))))

(defun cosine-table (label n amplitude offset)
  "Emet N octets : cos(i*2π/N)*amplitude + offset, pour i de 0 à N-1.
   Ex: (cosine-table 'cos-tbl 256 127 128)"
  (when label (label label))
  (let ((bytes (loop for i from 0 below n
                     collect (logand (round (+ offset
                                               (* amplitude (cos (* i 2 pi (/ 1 n))))))
                                     #xFF))))
    (emit (cl-asm/ir:make-ir-directive :name :byte :args bytes))))

(defun linear-ramp (label from to n)
  "Emet N octets : rampe linéaire de FROM à TO en N pas.
   Ex: (linear-ramp 'ramp 0 255 256)"
  (when label (label label))
  (let ((bytes (loop for i from 0 below n
                     collect (logand (round (+ from (* (- to from) (/ i (max 1 (1- n))))))
                                     #xFF))))
    (emit (cl-asm/ir:make-ir-directive :name :byte :args bytes))))


(defmacro assert-size (expected-n &rest body)
  "Vérifie que le bloc émet exactement EXPECTED-N octets.
   Génère un label caché, exécute BODY, puis vérifie la taille.
   Ex: (assert-size 2 (lda :imm 0) (rts))"
  (let ((lbl (symbol-name (gensym "__ASSERTSZ"))))
    `(progn
       (emit (cl-asm/ir:make-ir-label :name ,lbl :kind :local))
       ,@body
       (emit (cl-asm/ir:make-ir-directive
              :name :assertsize
              :args (list ,expected-n ,lbl))))))

(defmacro defstruct-asm (name &rest fields)
  "Définit une structure avec calcul automatique des offsets de champs.
   Chaque champ est soit un keyword (taille 1 octet) soit (keyword taille).
   Ex: (defstruct-asm player :x :y (:hp 2) :state)
   → PLAYER.X=0, PLAYER.Y=1, PLAYER.HP=2, PLAYER.STATE=4, PLAYER.SIZE=5"
  (let* ((sname (string-upcase (string name)))
         (parsed-fields
           (mapcar (lambda (f)
                     (if (consp f)
                         (cons (string-upcase (string (car f))) (cadr f))
                         (cons (string-upcase (string f)) 1)))
                   fields)))
    `(emit (cl-asm/ir:make-ir-directive
            :name :defstruct
            :args (list ,sname ',parsed-fields)))))

(defun section (name)
  "Change de section."
  (let* ((kw   (if (keywordp name) name
                   (intern (string-upcase (symbol-name name)) :keyword)))
         (sect (cl-asm/ir:program-find-or-create-section
                (lasm-context-program *ctx*) kw)))
    (setf (lasm-context-section *ctx*) sect)
    (emit (cl-asm/ir:make-ir-directive
           :name :section :args (list kw)))))

(defun genlabel ()
  "Genere un label unique anonyme."
  (let ((n (incf (lasm-context-label-counter *ctx*))))
    (intern (format nil "__LASM_~D" n) :keyword)))


;;; --------------------------------------------------------------------------
;;;  Macros d'aide pour les structures de controle courantes
;;; --------------------------------------------------------------------------

(defmacro with-label (name &body body)
  "Place NAME comme label, execute BODY, puis continue."
  `(progn (label ,name) ,@body))

(defmacro lasm-if (cond-fn true-label false-label &body body)
  "Structure if/else en assembleur.
   COND-FN est une fonction qui emet la branche conditionnelle
   vers TRUE-LABEL si la condition est fausse.
   Usage :
     (lasm-if (lambda (l) (beq l)) 'done 'skip
       (lda :imm 0))"
  (declare (ignore true-label false-label))
  `(let ((end-label (genlabel)))
     (funcall ,cond-fn end-label)
     ,@body
     (label end-label)))


;;; --------------------------------------------------------------------------
;;;  Instructions 6502 — une fonction par mnemonique
;;; --------------------------------------------------------------------------
;;;
;;; Signature generale : (MN [keyword] [valeur])
;;;   Sans argument       → implied     : (nop) (rts) (clc)
;;;   keyword :a          → accumulateur: (lsr :a) (asl :a)
;;;   keyword :imm val    → immediat    : (lda :imm #xFF)
;;;   keyword :x/:y val   → indexe      : (lda :x #x1234)
;;;   keyword :ix/:iy val → indirect    : (lda :ix #x00)
;;;   keyword :ind val    → indirect    : (jmp :ind #xFFFC)
;;;   valeur seul         → auto        : (lda #x10) (lda #x1234)

(macrolet ((def-implied (name mn)
             `(defun ,name () (make-instr ,mn)))
           (def-instr (name mn)
             `(defun ,name (&optional keyword val)
                (if (cl:and keyword (not (keywordp keyword)))
                    ;; (lda #x10) — premier arg est la valeur, pas un keyword
                    (make-instr ,mn nil keyword)
                    (make-instr ,mn keyword val)))))

  ;; Instructions implied
  (def-implied nop  "NOP")
  (def-implied rts  "RTS")
  (def-implied rti  "RTI")
  (def-implied brk  "BRK")
  (def-implied clc  "CLC")
  (def-implied sec  "SEC")
  (def-implied cli  "CLI")
  (def-implied sei  "SEI")
  (def-implied cld  "CLD")
  (def-implied sed  "SED")
  (def-implied clv  "CLV")
  (def-implied tax  "TAX")
  (def-implied tay  "TAY")
  (def-implied txa  "TXA")
  (def-implied tya  "TYA")
  (def-implied tsx  "TSX")
  (def-implied txs  "TXS")
  (def-implied pha  "PHA")
  (def-implied pla  "PLA")
  (def-implied php  "PHP")
  (def-implied plp  "PLP")
  (def-implied inx  "INX")
  (def-implied iny  "INY")
  (def-implied dex  "DEX")
  (def-implied dey  "DEY")
  ;; Instructions avec operande
  (def-instr lda  "LDA")
  (def-instr ldx  "LDX")
  (def-instr ldy  "LDY")
  (def-instr sta  "STA")
  (def-instr stx  "STX")
  (def-instr sty  "STY")
  (def-instr adc  "ADC")
  (def-instr sbc  "SBC")
  (def-instr cmp  "CMP")
  (def-instr cpx  "CPX")
  (def-instr cpy  "CPY")
  (def-instr and  "AND")
  (def-instr ora  "ORA")
  (def-instr eor  "EOR")
  (def-instr bit  "BIT")
  (def-instr inc  "INC")
  (def-instr dec  "DEC")
  (def-instr asl  "ASL")
  (def-instr lsr  "LSR")
  (def-instr rol  "ROL")
  (def-instr ror  "ROR")
  (def-instr jmp  "JMP")
  (def-instr jsr  "JSR")
  ;; Branches (valeur = label cible)
  (def-instr bcc  "BCC")
  (def-instr bcs  "BCS")
  (def-instr beq  "BEQ")
  (def-instr bne  "BNE")
  (def-instr bmi  "BMI")
  (def-instr bpl  "BPL")
  (def-instr bvc  "BVC")
  (def-instr bvs  "BVS"))


;;; --------------------------------------------------------------------------
;;;  Instructions 45GS02 supplementaires
;;; --------------------------------------------------------------------------

(macrolet ((def-implied (name mn)
             `(defun ,name () (make-instr ,mn)))
           (def-instr (name mn)
             `(defun ,name (&optional keyword val)
                (if (cl:and keyword (not (keywordp keyword)))
                    (make-instr ,mn nil keyword)
                    (make-instr ,mn keyword val)))))

  ;; Registre Z
  (def-implied inz  "INZ")
  (def-implied dez  "DEZ")
  (def-implied phz  "PHZ")
  (def-implied plz  "PLZ")
  (def-implied taz  "TAZ")
  (def-implied tza  "TZA")
  (def-instr  ldz  "LDZ")
  (def-instr  stz  "STZ")
  ;; Registre B
  (def-implied tab  "TAB")
  (def-implied tba  "TBA")
  (def-implied tsy  "TSY")
  (def-implied tys  "TYS")
  ;; Instructions speciales
  (def-implied map  "MAP")
  (def-implied eom  "EOM")
  (def-implied neg  "NEG")
  (def-instr  asr  "ASR")
  (def-instr  inw  "INW")
  (def-instr  dew  "DEW")
  ;; Registre Q
  (def-instr  ldq  "LDQ")
  (def-instr  stq  "STQ")
  (def-instr  adcq "ADCQ")
  (def-instr  sbcq "SBCQ")
  (def-instr  andq "ANDQ")
  (def-instr  oraq "ORAQ")
  (def-instr  eorq "EORQ")
  (def-instr  aslq "ASLQ")
  (def-instr  lsrq "LSRQ")
  (def-instr  rolq "ROLQ")
  (def-instr  rorq "RORQ")
  (def-instr  asrq "ASRQ")
  (def-instr  bitq "BITQ")
  (def-instr  cmpq "CMPQ")
  ;; Branches longues 16 bits
  (def-instr  lbcc "LBCC")
  (def-instr  lbcs "LBCS")
  (def-instr  lbeq "LBEQ")
  (def-instr  lbne "LBNE")
  (def-instr  lbmi "LBMI")
  (def-instr  lbpl "LBPL")
  (def-instr  lbvc "LBVC")
  (def-instr  lbvs "LBVS"))


;;; --------------------------------------------------------------------------
;;;  Instructions 65C02 supplementaires
;;; --------------------------------------------------------------------------

(macrolet ((def-implied (name mn)
             `(defun ,name () (make-instr ,mn)))
           (def-instr (name mn)
             `(defun ,name (&optional keyword val)
                (if (cl:and keyword (not (keywordp keyword)))
                    (make-instr ,mn nil keyword)
                    (make-instr ,mn keyword val)))))
  (def-instr bra  "BRA")
  (def-instr trb  "TRB")
  (def-instr tsb  "TSB")
  (def-implied phx "PHX")
  (def-implied phy "PHY")
  (def-implied plx "PLX")
  (def-implied ply "PLY"))


;;; --------------------------------------------------------------------------
;;;  Instructions R65C02 supplementaires (Rockwell bit manipulation)
;;; --------------------------------------------------------------------------
;;;
;;;  rmb0..rmb7 zp  — Reset Memory Bit n, Zero Page
;;;  smb0..smb7 zp  — Set Memory Bit n, Zero Page
;;;  bbr0..bbr7 zp, rel — Branch on Bit Reset
;;;  bbs0..bbs7 zp, rel — Branch on Bit Set
;;;
;;;  Les instructions bbr/bbs prennent deux operandes (zp + branche).
;;;  On les encode comme deux operandes dans l'IR.

(macrolet ((def-bit-zp (prefix)
             `(progn
                ,@(loop for n from 0 to 7
                        collect
                        `(defun ,(intern (format nil "~A~D" prefix n))
                             (zp-addr)
                           (emit (cl-asm/ir:make-ir-instruction
                                  :mnemonic ,(format nil "~A~D" prefix n)
                                  :operands (list (auto-operand zp-addr))))))))
           (def-bit-branch (prefix)
             `(progn
                ,@(loop for n from 0 to 7
                        collect
                        `(defun ,(intern (format nil "~A~D" prefix n))
                             (zp-addr branch-target)
                           (emit (cl-asm/ir:make-ir-instruction
                                  :mnemonic ,(format nil "~A~D" prefix n)
                                  :operands (list (auto-operand zp-addr)
                                                  (auto-operand branch-target)))))))))
  (def-bit-zp    "RMB")
  (def-bit-zp    "SMB")
  (def-bit-branch "BBR")
  (def-bit-branch "BBS"))


;;; --------------------------------------------------------------------------
;;;  Instructions 65816 supplementaires
;;; --------------------------------------------------------------------------

(macrolet ((def-implied (name mn)
             `(defun ,name () (make-instr ,mn)))
           (def-instr (name mn)
             `(defun ,name (&optional keyword val)
                (if (cl:and keyword (not (keywordp keyword)))
                    (make-instr ,mn nil keyword)
                    (make-instr ,mn keyword val)))))
  ;; Implied
  (def-implied xba  "XBA")
  (def-implied xce  "XCE")
  (def-implied wai  "WAI")
  (def-implied stp  "STP")
  (def-implied rtl  "RTL")
  (def-implied tcd  "TCD")
  (def-implied tcs  "TCS")
  (def-implied tdc  "TDC")
  (def-implied tsc  "TSC")
  (def-implied txy  "TXY")
  (def-implied tyx  "TYX")
  (def-implied phb  "PHB")
  (def-implied plb  "PLB")
  (def-implied phd  "PHD")
  (def-implied pld  "PLD")
  (def-implied phk  "PHK")
  ;; Avec operande
  (def-instr jsl  "JSL")
  (def-instr jml  "JML")
  (def-instr brl  "BRL")
  (def-instr pea  "PEA")
  (def-instr pei  "PEI")
  (def-instr per  "PER")
  (def-instr sep  "SEP")
  (def-instr rep  "REP")
  (def-instr cop  "COP"))

(defun mvn (src-bank dst-bank)
  "MVN src, dst — block move negative (65816)."
  (emit (cl-asm/ir:make-ir-instruction
         :mnemonic "MVN"
         :operands (list (auto-operand src-bank)
                         (auto-operand dst-bank)))))

(defun mvp (src-bank dst-bank)
  "MVP src, dst — block move positive (65816)."
  (emit (cl-asm/ir:make-ir-instruction
         :mnemonic "MVP"
         :operands (list (auto-operand src-bank)
                         (auto-operand dst-bank)))))


;;; --------------------------------------------------------------------------
;;;  Helpers Z80 et emission generique
;;; --------------------------------------------------------------------------
;;;
;;;  L'IR Z80 encode les registres comme :direct "A", :direct "HL", etc.
;;;  (chaines, pas des keywords).
;;;
;;;  Fonctions helper :
;;;    (z80r "HL")          — operande registre direct
;;;    (z80ind "HL")        — operande indirect (HL)
;;;    (z80ind "IX" 5)      — operande indirect avec deplacement (IX+5)
;;;    (zi "LD" op1 op2)    — emission d'une instruction Z80 generique
;;;
;;;  Exemple :
;;;    (zi "LD" (z80r "A") (z80r "B"))       ; LD A, B
;;;    (zi "LD" (z80r "HL") (make-imm 100))  ; LD HL, 100
;;;    (zi "PUSH" (z80r "HL"))               ; PUSH HL
;;;    (zi "JP" (make-dir 'start))           ; JP start

(defun z80r (name)
  "Operande registre Z80 : (z80r \"HL\") → :direct \"HL\""
  (cl-asm/ir:make-ir-operand :kind :direct
                              :value (string-upcase (string name))))

(defun z80ind (name &optional displacement)
  "Operande indirect Z80 : (z80ind \"HL\") → :indirect \"HL\"
   Avec deplacement : (z80ind \"IX\" 5) → :indirect (:+ \"IX\" 5)"
  (cl-asm/ir:make-ir-operand
   :kind :indirect
   :value (if displacement
              (list :+ (string-upcase (string name)) displacement)
              (string-upcase (string name)))))

(defun zi (mnemonic &rest operands)
  "Emet une instruction Z80 generique avec des operandes IR arbitraires.
   Ex : (zi \"LD\" (z80r \"A\") (z80r \"B\"))"
  (emit (cl-asm/ir:make-ir-instruction
         :mnemonic (string-upcase (string mnemonic))
         :operands operands)))


;;; --------------------------------------------------------------------------
;;;  Helpers Intel 8080 et emission generique
;;; --------------------------------------------------------------------------
;;;
;;;  L'IR 8080 encode les registres comme :direct "A", :direct "B", etc.
;;;  Les paires sont :direct "B" (= BC), :direct "D" (= DE), :direct "H" (= HL),
;;;  :direct "SP", :direct "PSW".
;;;
;;;  Fonctions helper :
;;;    (i8080r "A")          — operande registre 8 bits (B C D E H L M A)
;;;    (i8080rp "H")         — operande paire de registres (B D H SP PSW)
;;;    (i8080 "MOV" op1 op2) — emission d'une instruction 8080 generique
;;;
;;;  Exemple :
;;;    (i8080 "MOV" (i8080r "A") (i8080r "B"))       ; MOV A, B
;;;    (i8080 "MVI" (i8080r "A") (make-imm 42))       ; MVI A, 42
;;;    (i8080 "LXI" (i8080rp "H") (make-imm #x1234))  ; LXI H, $1234
;;;    (i8080 "JMP" (make-dir 'start))                ; JMP start

(defun i8080r (name)
  "Operande registre 8 bits Intel 8080 : (i8080r \"A\") → :direct \"A\""
  (cl-asm/ir:make-ir-operand :kind :direct
                              :value (string-upcase (string name))))

(defun i8080rp (name)
  "Operande paire de registres Intel 8080 : (i8080rp \"H\") → :direct \"H\""
  (cl-asm/ir:make-ir-operand :kind :direct
                              :value (string-upcase (string name))))

(defun i8080 (mnemonic &rest operands)
  "Emet une instruction Intel 8080 generique avec des operandes IR arbitraires.
   Ex : (i8080 \"MOV\" (i8080r \"A\") (i8080r \"B\"))"
  (emit (cl-asm/ir:make-ir-instruction
         :mnemonic (string-upcase (string mnemonic))
         :operands operands)))


;;; --------------------------------------------------------------------------
;;;  Helpers M68K et emission generique
;;; --------------------------------------------------------------------------
;;;
;;;  L'IR M68K encode les registres comme :direct "D0".."D7" et "A0".."A7".
;;;
;;;  Fonctions helper :
;;;    (dn 0)         — registre de donnees D0
;;;    (an 0)         — registre d'adresse A0
;;;    (ind-an 0)     — indirect (A0)
;;;    (post-an 0)    — post-increment (A0)+
;;;    (pre-an 0)     — pre-decrement -(A0)
;;;    (m68k-imm val) — immediat #val
;;;    (mi mnem size op...) — emission d'une instruction M68K
;;;
;;;  Exemple :
;;;    (mi "MOVE" :word (dn 0) (dn 1))   ; MOVE.W D0, D1
;;;    (mi "ADD"  :long (dn 0) (dn 1))   ; ADD.L  D0, D1
;;;    (mi "CLR"  :byte (dn 3))          ; CLR.B  D3
;;;    (mi "NOP")                         ; NOP

(defun dn (n)
  "Registre de donnees M68K Dn : (dn 0) → D0"
  (cl-asm/ir:make-ir-operand :kind :direct
                              :value (format nil "D~D" n)))

(defun an (n)
  "Registre d'adresse M68K An : (an 1) → A1"
  (cl-asm/ir:make-ir-operand :kind :direct
                              :value (format nil "A~D" n)))

(defun ind-an (n)
  "Indirect M68K (An) : (ind-an 0) → (A0)"
  (cl-asm/ir:make-ir-operand :kind :indirect
                              :value (format nil "A~D" n)))

(defun post-an (n)
  "Post-increment M68K (An)+ : (post-an 0) → (A0)+"
  (cl-asm/ir:make-ir-operand :kind :post-increment
                              :value (format nil "A~D" n)))

(defun pre-an (n)
  "Pre-decrement M68K -(An) : (pre-an 0) → -(A0)"
  (cl-asm/ir:make-ir-operand :kind :pre-decrement
                              :value (format nil "A~D" n)))

(defun m68k-imm (val)
  "Immediat M68K : (m68k-imm 42) → #42"
  (cl-asm/ir:make-ir-operand :kind :immediate :value val))

(defun mi (mnemonic &optional size &rest operands)
  "Emet une instruction M68K avec taille optionnelle.
   SIZE : nil | :byte | :word | :long
   Ex : (mi \"MOVE\" :word (dn 0) (dn 1))  ; MOVE.W D0, D1
        (mi \"NOP\")                         ; NOP"
  ;; Si size n'est pas un keyword de taille, c'est un operande
  (if (cl:and size (not (member size '(:byte :word :long))))
      (emit (cl-asm/ir:make-ir-instruction
             :mnemonic (string-upcase (string mnemonic))
             :size nil
             :operands (cons size operands)))
      (emit (cl-asm/ir:make-ir-instruction
             :mnemonic (string-upcase (string mnemonic))
             :size size
             :operands operands))))


;;; --------------------------------------------------------------------------
;;;  Point d'entree
;;; --------------------------------------------------------------------------

(defun target (keyword)
  "Directive de cible — information pour le script cl-asm en ligne de commande.
   Sans effet a l'execution : la cible est deja determinee par le script shell
   avant le chargement du fichier. Presente uniquement pour eviter une erreur
   si le fichier .lasm est charge directement dans un REPL."
  (declare (ignore keyword))
  nil)

(defun make-fresh-lasm-context ()
  "Cree un contexte .lasm vierge."
  (let* ((prog (cl-asm/ir:make-ir-program))
         (sect (cl-asm/ir:program-find-or-create-section prog :text)))
    (make-lasm-context
     :program       prog
     :section       sect
     :symtable      (cl-asm/symbol-table:make-symbol-table)
     :label-counter 0)))

(defun load-lasm-string (source)
  "Execute SOURCE (string) comme code .lasm dans le contexte d'assemblage.
   Retourne un IR-PROGRAM."
  (let* ((*ctx* (make-fresh-lasm-context))
         (*package* (find-package '#:cl-asm/lasm)))
    (with-input-from-string (s source)
      (loop for form = (read s nil s)
            until (eq form s)
            do (eval form)))
    (lasm-context-program *ctx*)))

(defun load-lasm (path)
  "Charge et execute le fichier .lasm a PATH.
   Retourne un IR-PROGRAM."
  (let* ((*ctx* (make-fresh-lasm-context))
         (*package* (find-package '#:cl-asm/lasm)))
    (load path)
    (lasm-context-program *ctx*)))

(defun lasm-program ()
  "Retourne le IR-PROGRAM du contexte courant (depuis un fichier .lasm)."
  (lasm-context-program *ctx*))

(defun %assemble-program (program origin target)
  "Assemble PROGRAM avec le backend TARGET depuis ORIGIN.
   Centralise le dispatch pour assemble-lasm-string et assemble-lasm."
  (ecase target
    (:6502
     (cl-asm/backend.6502:assemble program :origin origin))
    ((:45gs02 :mega65)
     (cl-asm/backend.45gs02:assemble-45gs02 program :origin origin))
    ((:65c02 :x16 :commander-x16)
     (cl-asm/backend.65c02:assemble-65c02 program :origin origin))
    (:r65c02
     (cl-asm/backend.r65c02:assemble-r65c02 program :origin origin))
    ((:65816 :snes :apple2gs)
     (cl-asm/backend.65816:assemble-65816 program :origin origin))
    ((:z80 :zx80 :zx81 :spectrum :msx :cpc)
     (cl-asm/backend.z80:assemble-z80 program :origin origin))
    ((:m68k :68000 :amiga :atari :mac68k)
     (cl-asm/backend.m68k:assemble-m68k program :origin origin))
    ((:i8080 :8080 :cpm :altair :intel8080)
     (cl-asm/backend.i8080:assemble-i8080 program :origin origin))))

(defun assemble-lasm-string (source &key (origin #x0801) (target :6502))
  "Raccourci : charge SOURCE en .lasm, assemble, retourne les octets.
   TARGET : :6502 (defaut), :45gs02/:mega65, :65c02/:x16, :r65c02,
            :65816/:snes/:apple2gs, :z80/:spectrum/:msx/:cpc, :m68k/:amiga
   Note : pour Z80 et M68K, utiliser :origin 0 (defaut 6502 = #x0801)."
  (%assemble-program (load-lasm-string source) origin target))

(defun assemble-lasm (path &key (origin #x0801) (target :6502))
  "Raccourci : charge PATH en .lasm, assemble, retourne les octets.
   TARGET : voir assemble-lasm-string."
  (%assemble-program (load-lasm path) origin target))
