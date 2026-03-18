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
   #:assemble-lasm-string))

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

(defun assemble-lasm-string (source &key (origin #x0801)
                                         (target :6502))
  "Raccourci : charge SOURCE en .lasm, assemble, retourne les octets.
   TARGET : :6502 (defaut) ou :45gs02"
  (let ((program (load-lasm-string source)))
    (ecase target
      (:6502
       (cl-asm/backend.6502:assemble program :origin origin))
      (:45gs02
       (cl-asm/backend.45gs02:assemble-45gs02 program :origin origin)))))

(defun assemble-lasm (path &key (origin #x0801) (target :6502))
  "Raccourci : charge PATH en .lasm, assemble, retourne les octets."
  (let ((program (load-lasm path)))
    (ecase target
      (:6502
       (cl-asm/backend.6502:assemble program :origin origin))
      (:45gs02
       (cl-asm/backend.45gs02:assemble-45gs02 program :origin origin)))))
