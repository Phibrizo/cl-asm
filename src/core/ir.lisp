; -*- coding: utf-8 -*-
(defpackage #:cl-asm/ir
  (:use #:cl)
  (:export
   #:source-loc #:make-source-loc
   #:source-loc-file #:source-loc-line #:source-loc-column
   #:source-loc->string
   #:asm-error #:asm-error-message #:asm-error-source-loc
   #:asm-syntax-error
   #:asm-undefined-label #:asm-error-label
   #:asm-range-error #:asm-error-value #:asm-error-bits
   #:asm-unknown-mnemonic #:asm-error-mnemonic
   #:ir-operand #:make-ir-operand #:ir-operand-p
   #:ir-operand-kind #:ir-operand-value #:ir-operand-index-reg
   #:ir-operand-size-hint #:ir-operand-loc
   #:make-imm #:make-dir #:make-ind #:make-ind-x #:make-ind-y #:make-reg
   #:ir-label #:make-ir-label #:ir-label-p
   #:ir-label-name #:ir-label-kind #:ir-label-number #:ir-label-loc
   #:ir-instruction #:make-ir-instruction #:ir-instruction-p
   #:ir-instruction-mnemonic #:ir-instruction-operands #:ir-instruction-size
   #:ir-instruction-loc
   #:ir-directive #:make-ir-directive #:ir-directive-p
   #:ir-directive-name #:ir-directive-args #:ir-directive-loc
   #:ir-relocation #:make-ir-relocation
   #:ir-relocation-offset #:ir-relocation-symbol
   #:ir-relocation-type #:ir-relocation-addend
   #:ir-section #:make-ir-section #:ir-section-p
   #:ir-section-name #:ir-section-origin #:ir-section-nodes #:ir-section-binary
   #:section-append
   #:ir-program #:make-ir-program #:ir-program-p
   #:ir-program-sections #:ir-program-entry-point
   #:program-find-section #:program-find-or-create-section))

;;; Pre-declaration du package cl-asm/symbol-table pour casser la
;;; dependance circulaire : expression.lisp appelle resolve-symbol et
;;; symbol-defined-p, mais symbol-table.lisp depend d'expression.lisp.
;;; On cree le package minimal ici ; symbol-table.lisp l'etendera.
;;; Le eval-when garantit que le package existe au compile-time.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package '#:cl-asm/symbol-table)
    (make-package '#:cl-asm/symbol-table :use '(#:cl))
    (export (intern "RESOLVE-SYMBOL"   '#:cl-asm/symbol-table)
            '#:cl-asm/symbol-table)
    (export (intern "SYMBOL-DEFINED-P" '#:cl-asm/symbol-table)
            '#:cl-asm/symbol-table)))

;;; Declaim forward pour supprimer les style-warnings de SBCL dans
;;; expression.lisp qui appelle ces fonctions avant qu'elles soient definies.
(declaim (ftype (function (t string &key (:source-loc t)) (values t t))
                cl-asm/symbol-table:resolve-symbol))
(declaim (ftype (function (t string) t)
                cl-asm/symbol-table:symbol-defined-p))

;;; src/core/ir.lisp
;;;
;;; Représentation intermédiaire (IR) de cl-asm.
;;;
;;; L'IR est le format pivot entre les frontends (parsers) et les backends
;;; (encodeurs). Elle est agnostique de l'architecture cible.
;;;
;;; Structure d'un programme assemblé :
;;;
;;;   IR-PROGRAM
;;;     └── sections : liste de IR-SECTION
;;;           └── nodes : liste de nœuds IR (dans l'ordre source)
;;;                 ├── IR-LABEL       ; définition de label
;;;                 ├── IR-INSTRUCTION ; instruction machine
;;;                 └── IR-DIRECTIVE   ; directive assembleur
;;;
;;; Les opérandes sont des IR-OPERAND, dont la valeur est soit un
;;; littéral entier, soit une référence à un symbole (string), soit
;;; un arbre d'expression (liste préfixée pour cl-asm/expression).


(in-package #:cl-asm/ir)


;;; --------------------------------------------------------------------------
;;;  Localisation source
;;; --------------------------------------------------------------------------

(defstruct source-loc
  "Position dans le fichier source."
  (file   nil :type (or string null))
  (line   0   :type fixnum)
  (column 0   :type fixnum))

(defun source-loc->string (loc)
  "Représentation lisible d'une source-loc."
  (if loc
      (format nil "~@[~A:~]~D:~D"
              (source-loc-file   loc)
              (source-loc-line   loc)
              (source-loc-column loc))
      "<inconnu>"))


;;; --------------------------------------------------------------------------
;;;  Conditions
;;; --------------------------------------------------------------------------

(define-condition asm-error (error)
  ((message    :initarg :message    :reader asm-error-message)
   (source-loc :initarg :source-loc :reader asm-error-source-loc
               :initform nil))
  (:report (lambda (c s)
             (let ((loc (asm-error-source-loc c)))
               (if loc
                   (format s "~A: ~A"
                           (source-loc->string loc)
                           (asm-error-message c))
                   (format s "~A" (asm-error-message c)))))))

(define-condition asm-syntax-error    (asm-error) ())
(define-condition asm-undefined-label (asm-error)
  ((label :initarg :label :reader asm-error-label)))
(define-condition asm-range-error     (asm-error)
  ((value :initarg :value :reader asm-error-value)
   (bits  :initarg :bits  :reader asm-error-bits)))
(define-condition asm-unknown-mnemonic (asm-error)
  ((mnemonic :initarg :mnemonic :reader asm-error-mnemonic)))


;;; --------------------------------------------------------------------------
;;;  Opérandes
;;; --------------------------------------------------------------------------

;;; Kinds d'opérande
;;;
;;;   :immediate       #valeur      — valeur immédiate
;;;   :direct          adresse      — adresse directe (zero-page ou absolue)
;;;   :indirect        (adresse)    — adresse indirecte parenthèses
;;;   :indirect-x      (addr,X)     — indirection indexée X pre
;;;   :indirect-y      (addr),Y/Z   — indirection indexée post (Y ou Z selon index-reg)
;;;   :indirect-sp-y   (addr,SP),Y  — pile 45GS02
;;;   :indirect-32     [addr]       — indirection 32 bits 45GS02
;;;   :indirect-32-z   [addr],Z     — indirection 32 bits post-indexée Z 45GS02
;;;   :register        A X Y Z B   — registre seul (pour imp/acc)
;;;   :string          "..."        — pour directives .byte "hello"

(defstruct ir-operand
  "Un opérande d'instruction ou argument de directive."
  (kind      :direct)
  ;; Valeur : entier, string (nom de label), ou arbre d'expression
  (value     nil)
  ;; Indice de registre secondaire pour les modes indexés
  ;; :x :y :z :b :sp ou nil
  (index-reg nil)
  ;; Hint de taille forcée : nil | :byte | :word | :dword
  (size-hint nil)
  ;; Localisation source
  (loc       nil))

(defun make-imm (value &key loc size-hint)
  "Construit un opérande immédiat."
  (make-ir-operand :kind :immediate :value value
                   :loc loc :size-hint size-hint))

(defun make-dir (value &key loc size-hint)
  "Construit un opérande direct (adresse)."
  (make-ir-operand :kind :direct :value value
                   :loc loc :size-hint size-hint))

(defun make-ind (value &key loc)
  "Construit un opérande indirect."
  (make-ir-operand :kind :indirect :value value :loc loc))

(defun make-ind-x (value &key loc)
  "Construit un opérande indirect pre-indexé X."
  (make-ir-operand :kind :indirect-x :value value :index-reg :x :loc loc))

(defun make-ind-y (value &key loc)
  "Construit un opérande indirect post-indexé Y."
  (make-ir-operand :kind :indirect-y :value value :index-reg :y :loc loc))

(defun make-reg (reg &key loc)
  "Construit un opérande registre."
  (make-ir-operand :kind :register :value reg :loc loc))


;;; --------------------------------------------------------------------------
;;;  Nœuds IR
;;; --------------------------------------------------------------------------

;;; --- Label -----------------------------------------------------------------

(defstruct ir-label
  "Définition d'un label."
  (name     ""    :type string)
  ;; :local (label normal), :global (ca65 ::), :numeric (1: 2:...)
  (kind     :local)
  ;; Numéro pour les labels numériques
  (number   nil)
  (loc      nil))

;;; --- Instruction -----------------------------------------------------------

(defstruct ir-instruction
  "Une instruction machine."
  ;; Mnémonique en majuscules, ex. "LDA" "STA" "LDZ" "MOVE"
  (mnemonic  ""  :type string)
  ;; Liste de IR-OPERAND (0 à 2 selon l'architecture)
  (operands  nil :type list)
  ;; Hint de taille pour M68K : nil | :byte | :word | :long
  ;; NIL pour toutes les architectures autres que M68K (champ ignoré)
  (size      nil)
  (loc       nil))

;;; --- Directive -------------------------------------------------------------

;;; Directives supportées :
;;;
;;;   .org      ADDR           — définit l'adresse courante
;;;   .equ      NOM = EXPR     — définit une constante
;;;   .byte     EXPR [,...]    — émet des octets
;;;   .word     EXPR [,...]    — émet des mots 16 bits
;;;   .dword    EXPR [,...]    — émet des mots 32 bits (45GS02)
;;;   .text     "STRING"       — émet une chaîne ASCII (sans octet nul)
;;;   .asciiz   "STRING"       — émet une chaîne ASCII + octet nul final
;;;   .pascalstr "STRING"      — émet un octet de longueur + chaîne
;;;   .fill     N [, VAL]      — émet N octets de valeur VAL (défaut 0)
;;;   .align    N [, VAL]      — aligne sur N octets
;;;   .padto    ADDR [, VAL]   — remplit jusqu'à ADDR avec VAL (défaut 0)
;;;   .assertpc ADDR           — erreur si PC ≠ ADDR
;;;   .section  NAME           — change de section
;;;   .global   NOM            — exporte un label
;;;   .extern   NOM            — importe un label externe
;;;   .include  "FILE"         — inclut un fichier source
;;;   .if / .else / .endif     — assemblage conditionnel
;;;   .macro / .endmacro       — définition de macro textuelle

(defstruct ir-directive
  "Une directive assembleur."
  ;; Keyword identifiant la directive : :org :byte :word :equ ...
  (name  :byte)
  ;; Arguments (liste hétérogène selon la directive)
  (args  nil   :type list)
  (loc   nil))

;;; --- Relocation ------------------------------------------------------------

(defstruct ir-relocation
  "Une relocation : référence à un symbole non encore connu."
  ;; Offset dans le binaire de la section
  (offset  0     :type (unsigned-byte 32))
  ;; Nom du symbole à résoudre
  (symbol  ""    :type string)
  ;; Type : :abs8 :abs16 :abs32 :rel8 :rel16
  (type    :abs16)
  ;; Valeur à additionner au symbole résolu
  (addend  0     :type fixnum))


;;; --------------------------------------------------------------------------
;;;  Section
;;; --------------------------------------------------------------------------

(defstruct ir-section
  "Une section du programme (text, data, bss...)."
  ;; Nom de la section : :text :data :bss ou un keyword custom
  (name    :text  :type keyword)
  ;; Adresse d'origine (fixée par .org ou nil = déterminée à l'édition de liens)
  (origin  nil)
  ;; Liste ordonnée de nœuds IR
  (nodes   nil    :type list)
  ;; Données binaires émises (remplies par le backend en pass 2)
  (binary  nil))

(defun section-append (section node)
  "Ajoute NODE en fin de SECTION."
  (setf (ir-section-nodes section)
        (nconc (ir-section-nodes section) (list node))))


;;; --------------------------------------------------------------------------
;;;  Programme
;;; --------------------------------------------------------------------------

(defstruct ir-program
  "Le programme complet après parsing."
  ;; Liste ordonnée de IR-SECTION
  (sections     nil  :type list)
  ;; Point d'entrée (label string ou nil)
  (entry-point  nil))

(defun program-find-section (program name)
  "Retourne la section NAME ou NIL."
  (find name (ir-program-sections program)
        :key #'ir-section-name :test #'eq))

(defun program-find-or-create-section (program name)
  "Retourne la section NAME, la crée si elle n'existe pas."
  (or (program-find-section program name)
      (let ((s (make-ir-section :name name)))
        (setf (ir-program-sections program)
              (nconc (ir-program-sections program) (list s)))
        s)))
