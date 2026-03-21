; -*- coding: utf-8 -*-
(defpackage #:cl-asm/parser
  (:use #:cl)
  (:export
   #:parse-tokens #:parse-string #:parse-file #:parser-error
   ;; Helpers pour le backend Rockwell R65C02
   #:rockwell-mnemonic-p
   #:rockwell-bit-number
   #:rockwell-opcode
   #:rockwell-two-operands-p
   ;; Helpers pour le backend Z80
   #:z80-mnemonic-p
   #:*z80-mode*
   ;; Helpers pour le backend M68K
   #:m68k-mnemonic-p
   #:*m68k-mode*))
;;; src/frontend/classic-parser.lisp
;;;
;;; Parser pour syntaxe assembleur classique (ca65-like).
;;;
;;; Consomme une liste de tokens produits par classic-lexer et construit
;;; un IR-PROGRAM.
;;;
;;; Grammaire informelle :
;;;
;;;   program     ::= line* EOF
;;;   line        ::= (label | instruction | directive | assignment)? NEWLINE
;;;   label       ::= IDENTIFIER ':'  |  IDENTIFIER '::'  |  DIGIT ':'
;;;   instruction ::= IDENTIFIER operand?
;;;   directive   ::= IDENTIFIER arg (',' arg)*
;;;   assignment  ::= IDENTIFIER '=' expr
;;;
;;;   operand     ::= imm | indirect | direct | register
;;;   imm         ::= '#' expr
;;;   indirect    ::= '(' expr ')'
;;;                |  '(' expr ',' reg ')'    ; pre-indexé
;;;                |  '(' expr ')' ',' reg    ; post-indexé
;;;   direct      ::= expr (',y' | ',x' | ',z')?
;;;   register    ::= 'A' | 'X' | 'Y' | 'Z' | 'B' | 'SP'
;;;
;;;   expr        ::= atom (op atom)*   ; voir expression.lisp pour l'arbre
;;;   atom        ::= INTEGER | IDENTIFIER | STRING | '*' | '(' expr ')'
;;;                |  '<' atom | '>' atom | '<<' atom | '>>' atom


(in-package #:cl-asm/parser)

;;; Déclarations forward — toutes les fonctions qui se rappellent mutuellement
;;; doivent être déclarées avant leur première utilisation.
(declaim (ftype (function (t) t)
                parse-expr parse-expr-bitor parse-expr-bitxor
                parse-expr-bitand parse-expr-shift parse-expr-add
                parse-expr-mul parse-expr-unary parse-expr-atom
                parse-operand parse-line skip-to-newline))
(declaim (ftype (function (t t) t) emit-node parse-directive-arg))
(declaim (ftype (function (t t t) t) parse-directive))
(declaim (ftype (function (t string &rest t) t) parser-error))
;; Z80 helpers (définis en fin de fichier)
(declaim (ftype (function (t) t) z80-mnemonic-p parse-z80-operands))
;; M68K helpers (définis en fin de fichier)
(declaim (ftype (function (t) t) m68k-mnemonic-p parse-m68k-operands
                                 m68k-base-mnemonic m68k-size-from-mnemonic))
;; Déclaration anticipée de *m68k-mode* pour éviter les style-warnings SBCL
;; (la variable est référencée dans parse-line avant d'être définie en fin de fichier)
(defvar *m68k-mode* nil)
(declaim (ftype (function (t t list) t) expand-macro))


;;; --------------------------------------------------------------------------
;;;  Définition de macro
;;; --------------------------------------------------------------------------

(defstruct macro-def
  "Une macro définie par .macro/.endmacro."
  ;; Nom de la macro (string, majuscules)
  (name    ""  :type string)
  ;; Liste de noms de paramètres (strings, majuscules)
  (params  nil :type list)
  ;; Corps : liste de listes de tokens (une liste par ligne)
  (body    nil :type list))


;;; --------------------------------------------------------------------------
;;;  Contexte de parsing
;;; --------------------------------------------------------------------------

(defstruct parse-context
  "État courant du parser."
  ;; Liste des tokens restants
  (tokens     nil  :type list)
  ;; Section courante
  (section    nil)
  ;; Programme en cours de construction
  (program    nil)
  ;; Table des symboles (pour les constantes définies pendant le parsing)
  (symtable   nil)
  ;; Table des macros : nom (string) -> macro-def
  (macros     nil)
  ;; Compteur d'invocations de macros (pour les labels uniques)
  (macro-counter 0 :type fixnum))

(defun pc-current (ctx)
  "Token courant."
  (first (parse-context-tokens ctx)))

(defun pc-peek (ctx &optional (n 1))
  "N-ième token suivant (0 = courant)."
  (nth n (parse-context-tokens ctx)))

(defun pc-advance (ctx)
  "Consomme et retourne le token courant."
  (pop (parse-context-tokens ctx)))

(defun pc-loc (ctx)
  "Localisation source du token courant."
  (let ((tok (pc-current ctx)))
    (if tok (cl-asm/lexer:token-loc tok) nil)))

(defun pc-kind (ctx)
  "Kind du token courant."
  (let ((tok (pc-current ctx)))
    (if tok (cl-asm/lexer:token-kind tok) :eof)))

(defun pc-value (ctx)
  "Valeur du token courant."
  (let ((tok (pc-current ctx)))
    (if tok (cl-asm/lexer:token-value tok) nil)))

(defun pc-expect (ctx kind)
  "Consomme un token du type KIND. Signale une erreur sinon."
  (if (eq (pc-kind ctx) kind)
      (pc-advance ctx)
      (parser-error ctx "Attendu ~A, trouvé ~A~@[ (~S)~]"
                   kind (pc-kind ctx) (pc-value ctx))))

(defun pc-skip-newlines (ctx)
  "Saute les tokens :newline."
  (loop while (eq (pc-kind ctx) :newline)
        do (pc-advance ctx)))

(defun parser-error (ctx fmt &rest args)
  "Signale une erreur de syntaxe à la position courante."
  (error 'cl-asm/ir:asm-syntax-error
         :message (apply #'format nil fmt args)
         :source-loc (pc-loc ctx)))


;;; --------------------------------------------------------------------------
;;;  Reconnaissance des registres
;;; --------------------------------------------------------------------------

(defparameter *registers-6502*
  '("A" "X" "Y" "SP")
  "Registres du 6502.")

(defparameter *registers-45gs02*
  '("A" "X" "Y" "Z" "B" "SP")
  "Registres du 45GS02 (superset 6502).")

(defun register-p (name &optional (regs *registers-45gs02*))
  "Vrai si NAME (string) est un nom de registre."
  (member (string-upcase name) regs :test #'string=))

(defun register-keyword (name)
  "Convertit un nom de registre en keyword : \"X\" -> :x"
  (intern (string-upcase name) :keyword))


;;; --------------------------------------------------------------------------
;;;  Parsing des expressions
;;; --------------------------------------------------------------------------
;;;
;;; Les expressions sont construites sous forme d'arbres préfixés
;;; compatibles avec cl-asm/expression:eval-expr.
;;;
;;; Précédence (du moins au plus liant) :
;;;   1. OR bit-à-bit   |
;;;   2. XOR            ^
;;;   3. AND bit-à-bit  &
;;;   4. Décalages      << >>
;;;   5. Addition       + -
;;;   6. Multiplication * / %
;;;   7. Unaires        - ~ < >
;;;   8. Atomes         littéraux, identifiants, (expr)

(defun parse-expr (ctx)
  "Point d'entrée : parse une expression complète."
  (parse-expr-bitor ctx))

(defun parse-expr-bitor (ctx)
  (let ((left (parse-expr-bitxor ctx)))
    (loop while (eq (pc-kind ctx) :pipe)
          do (pc-advance ctx)
             (setf left (list :bitor left (parse-expr-bitxor ctx))))
    ;; = comme operateur de comparaison (apres les operateurs bit-a-bit)
    (when (eq (pc-kind ctx) :equals)
      (pc-advance ctx)
      (setf left (list := left (parse-expr-bitxor ctx))))
    left))

(defun parse-expr-bitxor (ctx)
  (let ((left (parse-expr-bitand ctx)))
    (loop while (eq (pc-kind ctx) :caret)
          do (pc-advance ctx)
             (setf left (list :^ left (parse-expr-bitand ctx))))
    left))

(defun parse-expr-bitand (ctx)
  (let ((left (parse-expr-shift ctx)))
    (loop while (eq (pc-kind ctx) :ampersand)
          do (pc-advance ctx)
             (setf left (list :& left (parse-expr-shift ctx))))
    left))

(defun parse-expr-shift (ctx)
  (let ((left (parse-expr-add ctx)))
    (loop
      (case (pc-kind ctx)
        (:lshift (pc-advance ctx)
                 (setf left (list :<< left (parse-expr-add ctx))))
        (:rshift (pc-advance ctx)
                 (setf left (list :>> left (parse-expr-add ctx))))
        (otherwise (return))))
    left))

(defun parse-expr-add (ctx)
  (let ((left (parse-expr-mul ctx)))
    (loop
      (case (pc-kind ctx)
        (:plus  (pc-advance ctx)
                (setf left (list :+ left (parse-expr-mul ctx))))
        (:minus (pc-advance ctx)
                (setf left (list :- left (parse-expr-mul ctx))))
        (otherwise (return))))
    left))

(defun parse-expr-mul (ctx)
  (let ((left (parse-expr-unary ctx)))
    (loop
      (case (pc-kind ctx)
        (:star    (pc-advance ctx)
                  (setf left (list :* left (parse-expr-unary ctx))))
        (:slash   (pc-advance ctx)
                  (setf left (list :/ left (parse-expr-unary ctx))))
        (:percent (pc-advance ctx)
                  (setf left (list :mod left (parse-expr-unary ctx))))
        (otherwise (return))))
    left))

(defun parse-expr-unary (ctx)
  (case (pc-kind ctx)
    (:minus
     (pc-advance ctx)
     (list :neg (parse-expr-unary ctx)))
    (:tilde
     (pc-advance ctx)
     (list :~ (parse-expr-unary ctx)))
    ;; < = octet bas,  > = octet haut
    (:lt
     (pc-advance ctx)
     (list :lo (parse-expr-unary ctx)))
    (:gt
     (pc-advance ctx)
     (list :hi (parse-expr-unary ctx)))
    (otherwise
     (parse-expr-atom ctx))))

(defun parse-expr-atom (ctx)
  (case (pc-kind ctx)
    ;; Littéral entier
    (:integer
     (prog1 (pc-value ctx) (pc-advance ctx)))
    ;; Chaîne
    (:string
     (prog1 (pc-value ctx) (pc-advance ctx)))
    ;; Identifiant : référence à un symbole
    (:identifier
     (let ((name (pc-value ctx)))
       (pc-advance ctx)
       (string-upcase name)))
    ;; * = PC courant
    (:star
     (pc-advance ctx)
     :*)
    ;; Expression parenthésée
    (:lparen
     (pc-advance ctx)
     (let ((e (parse-expr ctx)))
       (pc-expect ctx :rparen)
       e))
    ;; Tout autre token = erreur
    (t
     (parser-error ctx "Expression attendue, trouve ~A~@[ (~S)~]"
                   (pc-kind ctx) (pc-value ctx)))))


;;; --------------------------------------------------------------------------
;;;  Parsing des opérandes d'instruction
;;; --------------------------------------------------------------------------

(defun parse-operand (ctx)
  "Parse un opérande d'instruction. Retourne un IR-OPERAND ou NIL."
  (let ((loc (pc-loc ctx)))
    (case (pc-kind ctx)

      ;; Immédiat : #expr
      (:hash
       (pc-advance ctx)
       (cl-asm/ir:make-ir-operand
        :kind :immediate
        :value (parse-expr ctx)
        :loc loc))

      ;; Indirect ou indirect indexé : (expr) ou (expr,X) ou (expr),Y/Z
      ;; Aussi : (expr,SP),Y  -- mode pile 45GS02
      (:lparen
       (pc-advance ctx)
       (let ((addr (parse-expr ctx)))
         (cond
           ;; (addr,reg) — pre-indexé ou pile
           ((eq (pc-kind ctx) :comma)
            (pc-advance ctx)
            (let ((reg (string-upcase (or (pc-value ctx) ""))))
              (pc-expect ctx :identifier)
              (pc-expect ctx :rparen)
              ;; (addr,SP),Y — mode pile 45GS02
              (if (and (string= reg "SP") (eq (pc-kind ctx) :comma))
                  (progn
                    (pc-advance ctx)
                    (pc-expect ctx :identifier)  ; consomme Y
                    (cl-asm/ir:make-ir-operand
                     :kind :indirect-sp-y
                     :value addr
                     :index-reg :y
                     :loc loc))
                  ;; (addr,reg) — pre-indexé normal
                  (cl-asm/ir:make-ir-operand
                   :kind :indirect-x
                   :value addr
                   :index-reg (register-keyword reg)
                   :loc loc))))
           ;; (addr) — indirect pur ou post-indexé ,Y ou ,Z
           (t
            (pc-expect ctx :rparen)
            (if (eq (pc-kind ctx) :comma)
                (progn
                  (pc-advance ctx)
                  (let ((reg (string-upcase (or (pc-value ctx) ""))))
                    (pc-expect ctx :identifier)
                    (cl-asm/ir:make-ir-operand
                     :kind :indirect-y
                     :value addr
                     :index-reg (register-keyword reg)
                     :loc loc)))
                (cl-asm/ir:make-ir-operand
                 :kind :indirect
                 :value addr
                 :loc loc))))))

      ;; Indirect 32 bits 45GS02 : [expr] ou [expr],Z
      (:lbracket
       (pc-advance ctx)
       (let ((addr (parse-expr ctx)))
         (pc-expect ctx :rbracket)
         (if (eq (pc-kind ctx) :comma)
             (progn
               (pc-advance ctx)
               (pc-expect ctx :identifier)   ; consomme Z
               (cl-asm/ir:make-ir-operand
                :kind :indirect-32-z
                :value addr
                :index-reg :z
                :loc loc))
             (cl-asm/ir:make-ir-operand
              :kind :indirect-32
              :value addr
              :loc loc))))

      ;; Pas d'opérande (instructions implicites : NOP, RTS, etc.)
      ((:newline :eof :colon)
       nil)

      ;; Identifiant : registre seul (LSR A, INC X...) ou expression directe
      (:identifier
       (let ((name (string-upcase (pc-value ctx))))
         (if (and (register-p name)
                  (member (cl-asm/lexer:token-kind
                           (or (pc-peek ctx 1)
                               (cl-asm/lexer:make-token :kind :eof)))
                          '(:newline :eof :colon)))
             ;; Registre seul → opérande :register (mode accumulateur)
             (progn
               (pc-advance ctx)
               (cl-asm/ir:make-ir-operand
                :kind :register :value name :loc loc))
             ;; Sinon : expression directe (label, constante...)
             (let ((addr (parse-expr ctx)))
               (if (eq (pc-kind ctx) :comma)
                   (progn
                     (pc-advance ctx)
                     (let ((reg (string-upcase (or (pc-value ctx) ""))))
                       (pc-expect ctx :identifier)
                       (cl-asm/ir:make-ir-operand
                        :kind :direct
                        :value addr
                        :index-reg (register-keyword reg)
                        :loc loc)))
                   (cl-asm/ir:make-ir-operand
                    :kind :direct :value addr :loc loc))))))

      ;; Direct ou indexé direct : expr  ou  expr,X  ou  expr,Y
      (otherwise
       (let ((addr (parse-expr ctx))
             (size-hint nil))
         ;; Hint de taille explicite via opérateur de cast (ignoré ici,
         ;; la taille sera déduite par le backend)
         (if (eq (pc-kind ctx) :comma)
             (progn
               (pc-advance ctx)
               (let ((reg (string-upcase (or (pc-value ctx) ""))))
                 (pc-expect ctx :identifier)
                 (cl-asm/ir:make-ir-operand
                  :kind :direct
                  :value addr
                  :index-reg (register-keyword reg)
                  :size-hint size-hint
                  :loc loc)))
             (cl-asm/ir:make-ir-operand
              :kind :direct
              :value addr
              :size-hint size-hint
              :loc loc)))))))


;;; --------------------------------------------------------------------------
;;;  Parsing des directives
;;; --------------------------------------------------------------------------

(defparameter *directive-names*
  '(".org" ".byte" ".word" ".dword" ".text" ".fill" ".align"
    ".equ" ".define" ".section" ".global" ".extern" ".include"
    ".if" ".else" ".endif" ".macro" ".endmacro"
    ;; Directives de mode 65816
    ".al" ".as" ".xl" ".xs")
  "Directives reconnues.")

(defun directive-p (name)
  "Vrai si NAME (string) est une directive."
  (member (string-downcase name) *directive-names* :test #'string=))

(defun directive-keyword (name)
  "Convertit \".byte\" -> :byte etc."
  (intern (string-upcase (subseq name 1)) :keyword))

(defun parse-directive (ctx name loc)
  "Parse les arguments d'une directive et construit un IR-DIRECTIVE."
  (let ((kw (directive-keyword name))
        (args nil))
    (case kw
      ;; .org ADDR
      (:org
       (push (parse-expr ctx) args))
      ;; .equ NOM = EXPR  (forme alternative à NOM = EXPR)
      (:equ
       (let ((sym (pc-value ctx)))
         (pc-expect ctx :identifier)
         (pc-expect ctx :equals)
         (push sym args)
         (push (parse-expr ctx) args)))
      ;; .section NAME — change la section courante du contexte
      (:section
       (let* ((sect-name (intern (string-upcase (pc-value ctx)) :keyword))
              (sect (cl-asm/ir:program-find-or-create-section
                     (parse-context-program ctx) sect-name)))
         (pc-expect ctx :identifier)
         (setf (parse-context-section ctx) sect)
         (push sect-name args)))
      ;; .global / .extern NOM [, NOM...]
      ((:global :extern)
       (push (string-upcase (pc-value ctx)) args)
       (pc-expect ctx :identifier)
       (loop while (eq (pc-kind ctx) :comma)
             do (pc-advance ctx)
                (push (string-upcase (pc-value ctx)) args)
                (pc-expect ctx :identifier)))
      ;; .include "FILE"
      (:include
       (push (pc-value ctx) args)
       (pc-expect ctx :string))
      ;; .byte, .word, .dword, .text, .fill, .align
      ;; liste d'expressions séparées par des virgules
      (otherwise
       (unless (member (pc-kind ctx) '(:newline :eof))
         (push (parse-directive-arg ctx kw) args)
         (loop while (eq (pc-kind ctx) :comma)
               do (pc-advance ctx)
                  (push (parse-directive-arg ctx kw) args)))))
    (cl-asm/ir:make-ir-directive
     :name kw
     :args (nreverse args)
     :loc  loc)))

(defun parse-directive-arg (ctx kw)
  "Parse un argument de directive (expression ou chaîne)."
  (declare (ignore kw))
  (if (eq (pc-kind ctx) :string)
      (prog1 (pc-value ctx) (pc-advance ctx))
      (parse-expr ctx)))


;;; --------------------------------------------------------------------------
;;;  Gestion des macros
;;; --------------------------------------------------------------------------

(defun macro-table (ctx)
  "Retourne la table des macros du contexte, la crée si absente."
  (unless (parse-context-macros ctx)
    (setf (parse-context-macros ctx)
          (make-hash-table :test #'equal)))
  (parse-context-macros ctx))

(defun find-macro (ctx name)
  "Cherche une macro par son nom (insensible à la casse)."
  (let ((tbl (parse-context-macros ctx)))
    (when tbl
      (gethash (string-upcase name) tbl))))

(defun register-macro (ctx mdef)
  "Enregistre une macro dans le contexte."
  (setf (gethash (macro-def-name mdef) (macro-table ctx)) mdef))

(defun next-macro-id (ctx)
  "Retourne un identifiant unique pour l'invocation courante."
  (incf (parse-context-macro-counter ctx)))

(defun parse-macro-def (ctx name loc)
  "Parse le corps d'une définition de macro jusqu'à .endmacro.
   NAME est le nom de la macro, déjà lu.
   Retourne une MACRO-DEF."
  (declare (ignore loc))
  ;; Lire les paramètres sur la même ligne que .macro
  (let ((params nil))
    (loop while (eq (pc-kind ctx) :identifier)
          do (push (string-upcase (pc-value ctx)) params)
             (pc-advance ctx)
             (when (eq (pc-kind ctx) :comma) (pc-advance ctx)))
    (setf params (nreverse params))
    ;; Consommer la fin de ligne
    (case (pc-kind ctx)
      (:newline (pc-advance ctx))
      (:eof nil))
    ;; Lire le corps ligne par ligne jusqu'à .endmacro
    (let ((body nil)
          (current-line nil))
      (loop
        (case (pc-kind ctx)
          (:eof
           (parser-error ctx "Fin de fichier dans la definition de macro ~A"
                         name))
          (:newline
           (when current-line
             (push (nreverse current-line) body)
             (setf current-line nil))
           (pc-advance ctx))
          (otherwise
           ;; Détecter .endmacro
           (if (and (eq (pc-kind ctx) :identifier)
                    (string-equal (pc-value ctx) ".endmacro"))
               (progn
                 (pc-advance ctx)
                 ;; Consommer fin de ligne après .endmacro
                 (when (eq (pc-kind ctx) :newline) (pc-advance ctx))
                 (when current-line
                   (push (nreverse current-line) body))
                 (return))
               (progn
                 (push (pc-current ctx) current-line)
                 (pc-advance ctx))))))
      (make-macro-def :name (string-upcase name)
                      :params params
                      :body (nreverse body)))))

(defun make-unique-token (tok id)
  "Crée un token avec un nom rendu unique par l'ID d'invocation.
   Les labels locaux (__NOM) sont suffixés par __ID — qu'il s'agisse
   d'une référence (:identifier) ou d'une définition (:label-def)."
  (let ((kind (cl-asm/lexer:token-kind tok))
        (v    (cl-asm/lexer:token-value tok)))
    (cond
      ;; :identifier dont le nom commence par __ → rendre unique
      ((and (eq kind :identifier)
            (stringp v)
            (> (length v) 2)
            (string= (subseq v 0 2) "__"))
       (cl-asm/lexer:make-token
        :kind  kind
        :value (format nil "~A__~D" v id)
        :loc   (cl-asm/lexer:token-loc tok)))
      ;; :label-def dont le nom commence par __ → rendre unique
      ((and (eq kind :label-def)
            (stringp v)
            (> (length v) 2)
            (string= (subseq v 0 2) "__"))
       (cl-asm/lexer:make-token
        :kind  kind
        :value (format nil "~A__~D" v id)
        :loc   (cl-asm/lexer:token-loc tok)))
      ;; Autres tokens → inchangés
      (t tok))))

(defun substitute-params (tokens params args id)
  "Substitue les paramètres par les arguments dans une liste de tokens.
   Rend uniques les labels locaux (préfixe __) en ajoutant l'ID."
  (mapcar (lambda (tok)
            (let ((v (cl-asm/lexer:token-value tok)))
              (cond
                ;; Paramètre → remplacer par les tokens de l'argument
                ((and (eq (cl-asm/lexer:token-kind tok) :identifier)
                      (stringp v))
                 (let ((pos (position (string-upcase v) params
                                      :test #'string=)))
                   (if pos
                       ;; On retourne le token de l'argument correspondant
                       ;; (un seul token par paramètre pour l'instant)
                       (nth pos args)
                       (make-unique-token tok id))))
                (t
                 (make-unique-token tok id)))))
          tokens))

(defun expand-macro (ctx mdef args)
  "Expande MDEF avec les ARGS donnés.
   Injecte les tokens résultants en tête du flux de CTX."
  (let* ((id (next-macro-id ctx))
         (params (macro-def-params mdef))
         (expanded-tokens nil))
    ;; Vérifier le nombre d'arguments
    (unless (= (length args) (length params))
      (parser-error ctx
                    "Macro ~A : ~D argument(s) attendu(s), ~D fourni(s)"
                    (macro-def-name mdef)
                    (length params) (length args)))
    ;; Expandre chaque ligne du corps
    (dolist (line (macro-def-body mdef))
      (let ((subst (substitute-params line params args id)))
        (dolist (tok subst)
          (push tok expanded-tokens)))
      ;; Ajouter un :newline entre les lignes
      (push (cl-asm/lexer:make-token :kind :newline :value nil :loc nil)
            expanded-tokens))
    ;; Injecter en tête du flux (dans l'ordre)
    (setf (parse-context-tokens ctx)
          (append (nreverse expanded-tokens)
                  (parse-context-tokens ctx)))))

(defun parse-macro-args (ctx)
  "Parse les arguments d'un appel de macro (liste d'expressions séparées
   par des virgules jusqu'à la fin de ligne).
   Retourne une liste de tokens, un par argument
   (les expressions multi-tokens ne sont pas encore supportées)."
  (let ((args nil))
    (loop while (not (member (pc-kind ctx) '(:newline :eof)))
          do (push (pc-current ctx) args)
             (pc-advance ctx)
             (when (eq (pc-kind ctx) :comma)
               (pc-advance ctx)))
    (nreverse args)))


;;; --------------------------------------------------------------------------
;;;  Assemblage conditionnel  .if / .else / .endif
;;; --------------------------------------------------------------------------
;;;
;;; L'expression du .if est evaluee immediatement au parsing.
;;; Les forward-references ne sont PAS supportees : seuls les symboles
;;; deja definis au moment du .if sont visibles.
;;; Zero = faux, tout autre entier = vrai.
;;;
;;; Imbrication supportee. .else est optionnel.

(defun skip-conditional-block (ctx)
  "Saute les tokens jusqu'au .else ou .endif correspondant,
   en respectant l'imbrication des .if/.endif.
   Retourne :else si on s'est arrete sur .else, :endif sinon."
  (let ((depth 0))
    (loop
      (pc-skip-newlines ctx)
      (when (eq (pc-kind ctx) :eof)
        (parser-error ctx "Fin de fichier dans un bloc .if"))
      (when (eq (pc-kind ctx) :identifier)
        (let ((name (string-downcase (pc-value ctx))))
          (cond
            ;; .if imbriqué : augmenter la profondeur
            ((string= name ".if")
             (incf depth)
             (skip-to-newline ctx))
            ;; .endif au niveau courant → fin
            ((and (string= name ".endif") (= depth 0))
             (pc-advance ctx)
             (skip-to-newline ctx)
             (return :endif))
            ;; .endif imbriqué → diminuer la profondeur
            ((string= name ".endif")
             (decf depth)
             (skip-to-newline ctx))
            ;; .else au niveau courant → fin du bloc faux
            ((and (string= name ".else") (= depth 0))
             (pc-advance ctx)
             (skip-to-newline ctx)
             (return :else))
            ;; Autre token → ignorer jusqu'à la fin de ligne
            (t
             (skip-to-newline ctx)))))
      ;; Token non-identifiant sur cette ligne → sauter
      (unless (eq (pc-kind ctx) :identifier)
        (skip-to-newline ctx)))))

(defun skip-to-newline (ctx)
  "Consomme tous les tokens jusqu'a (inclus) la fin de ligne courante."
  (loop until (member (pc-kind ctx) '(:newline :eof))
        do (pc-advance ctx))
  (when (eq (pc-kind ctx) :newline)
    (pc-advance ctx)))

(defun skip-to-endif (ctx)
  "Saute jusqu'au .endif correspondant (ignore un eventuel .else)."
  (let ((result (skip-conditional-block ctx)))
    ;; Si on s'est arrêté sur .else, continuer jusqu'au .endif
    (when (eq result :else)
      (skip-conditional-block ctx))))

(defun parse-if (ctx loc)
  "Parse et execute un bloc .if/.else/.endif.
   L'expression est evaluee immediatement.
   Retourne T si quelque chose a ete emis, NIL sinon."
  (declare (ignore loc))
  ;; Evaluer l'expression du .if
  (let* ((expr (parse-expr ctx))
         (env  (cl-asm/expression:make-env
                :symbol-table (parse-context-symtable ctx)
                :pc 0))
         (val  (cl-asm/expression:eval-expr expr env))
         (truep (and (integerp val) (/= val 0))))
    ;; Consommer la fin de ligne après .if EXPR
    (case (pc-kind ctx)
      (:newline (pc-advance ctx))
      (:eof nil))
    (cond
      ;; Condition vraie : parser le bloc vrai, sauter le bloc faux
      (truep
       (let ((found-end nil))
         (loop while (not (eq (pc-kind ctx) :eof))
               do (pc-skip-newlines ctx)
                  (when (eq (pc-kind ctx) :eof)
                    (parser-error ctx "Fin de fichier dans un bloc .if"))
                  ;; Detecter .else ou .endif au niveau 0
                  (when (and (eq (pc-kind ctx) :identifier)
                             (string-equal (pc-value ctx) ".else"))
                    ;; Fin du bloc vrai → sauter jusqu'au .endif
                    (pc-advance ctx)
                    (skip-to-endif ctx)
                    (setf found-end t)
                    (return))
                  (when (and (eq (pc-kind ctx) :identifier)
                             (string-equal (pc-value ctx) ".endif"))
                    (pc-advance ctx)
                    (skip-to-newline ctx)
                    (setf found-end t)
                    (return))
                  ;; Parser une ligne normale du bloc vrai
                  (parse-line ctx))
         (unless found-end
           (parser-error ctx "Fin de fichier dans un bloc .if"))))
      ;; Condition fausse : sauter le bloc faux
      (t
       (let ((result (skip-conditional-block ctx)))
         ;; Si on a trouvé un .else, parser son bloc
         (when (eq result :else)
           (let ((found-end nil))
             (loop while (not (eq (pc-kind ctx) :eof))
                   do (pc-skip-newlines ctx)
                      (when (eq (pc-kind ctx) :eof)
                        (parser-error ctx "Fin de fichier dans un bloc .else"))
                      (when (and (eq (pc-kind ctx) :identifier)
                                 (string-equal (pc-value ctx) ".endif"))
                        (pc-advance ctx)
                        (skip-to-newline ctx)
                        (setf found-end t)
                        (return))
                      (parse-line ctx))
             (unless found-end
               (parser-error ctx "Fin de fichier dans un bloc .else")))))))
    t))

(defun parse-line (ctx)
  "Parse une ligne source. Ajoute les noeuds dans la section courante."
  (pc-skip-newlines ctx)
  (when (eq (pc-kind ctx) :eof)
    (return-from parse-line nil))

  (let ((loc (pc-loc ctx)))

    (cond
      ;; Label numérique : 1: 2: ...
      ((eq (pc-kind ctx) :numeric-label-def)
       (let ((num (pc-value ctx)))
         (pc-advance ctx)
         (emit-node ctx
                    (cl-asm/ir:make-ir-label
                     :kind :numeric :number num :name (format nil "~D" num)
                     :loc loc)))
       ;; Suite possible sur la même ligne (ex: 1: NOP)
       (unless (member (pc-kind ctx) '(:newline :eof))
         (parse-line ctx)
         (return-from parse-line t)))

      ;; Identifiant : peut être mnémonique, directive, ou assignation
      ((eq (pc-kind ctx) :identifier)
       (let ((name (pc-value ctx)))
         (pc-advance ctx)
         (cond
           ;; Label résiduel : nom suivi de ':' (sécurité — normalement le
           ;; lexer émet :label-def directement)
           ((eq (pc-kind ctx) :colon)
            (pc-advance ctx)
            (emit-node ctx
                       (cl-asm/ir:make-ir-label
                        :kind :local :name (string-upcase name) :loc loc))
            (unless (member (pc-kind ctx) '(:newline :eof))
              (parse-line ctx)
              (return-from parse-line t)))

           ;; Assignation : NOM = EXPR
           ((eq (pc-kind ctx) :equals)
            (pc-advance ctx)
            (let* ((val-expr (parse-expr ctx))
                   (env      (cl-asm/expression:make-env
                              :symbol-table (parse-context-symtable ctx)
                              :pc 0)))
              ;; Enregistrer dans la symtable pour les .if suivants
              (multiple-value-bind (val ok)
                  (cl-asm/expression:eval-expr val-expr env)
                (when (and ok (parse-context-symtable ctx))
                  (cl-asm/symbol-table:define-constant
                   (parse-context-symtable ctx)
                   (string-upcase name) val)))
              (emit-node ctx
                         (cl-asm/ir:make-ir-directive
                          :name :equ
                          :args (list (string-upcase name) val-expr)
                          :loc loc))))

           ;; Directive : .byte .word .org ... ou .macro / .if
           ((directive-p name)
            (cond
              ;; .macro — définition de macro
              ((string-equal name ".macro")
               (let ((mname (if (eq (pc-kind ctx) :identifier)
                                (prog1 (pc-value ctx) (pc-advance ctx))
                                (parser-error ctx "Nom de macro attendu"))))
                 (register-macro ctx (parse-macro-def ctx mname loc))
                 (return-from parse-line t)))
              ;; .if — assemblage conditionnel
              ((string-equal name ".if")
               (parse-if ctx loc)
               (return-from parse-line t))
              ;; .else / .endif au niveau racine = erreur de syntaxe
              ((string-equal name ".else")
               (parser-error ctx ".else sans .if correspondant"))
              ((string-equal name ".endif")
               (parser-error ctx ".endif sans .if correspondant"))
              ;; Autres directives normales
              (t
               (emit-node ctx (parse-directive ctx name loc)))))

           ;; Appel de macro connue
           ((find-macro ctx name)
            (let* ((mdef (find-macro ctx name))
                   (args (parse-macro-args ctx)))
              (expand-macro ctx mdef args)
              ;; Les tokens expandés sont maintenant en tête du flux —
              ;; on re-parse immédiatement sans émettre de noeud ici.
              (parse-line ctx)
              (return-from parse-line t)))

           ;; Instruction : mnémonique [opérande]
           ;; Cas spécial : BBRn/BBSn = deux opérandes (zp , rel)
           (t
            (let* ((mnem-up   (string-upcase name))
                   (mnem-base (if *m68k-mode* (m68k-base-mnemonic mnem-up) mnem-up))
                   (mnem-size (if *m68k-mode* (m68k-size-from-mnemonic mnem-up) nil))
                   (operands
                    (cond
                      ;; Z80 : opérandes séparées par virgules
                      ((z80-mnemonic-p mnem-up)
                       (parse-z80-operands ctx))
                      ;; M68K : opérandes séparées par virgules, modes d'adressage étendus
                      ((m68k-mnemonic-p mnem-up)
                       (parse-m68k-operands ctx))
                      ;; BBRn/BBSn : zp-expr , rel-expr
                      ;; On parse les deux expressions directement
                      ;; sans passer par parse-operand (qui consommerait
                      ;; la virgule comme indicateur d'indexe)
                      ((and (= (length mnem-up) 4)
                            (member (subseq mnem-up 0 3) '("BBR" "BBS") :test #'string=)
                            (char<= #\0 (char mnem-up 3) #\7))
                       (let* ((loc1   (pc-loc ctx))
                              (zp-val (parse-expr ctx))
                              (zp-op  (cl-asm/ir:make-ir-operand
                                       :kind :direct :value zp-val :loc loc1))
                              (dummy  (when (eq (pc-kind ctx) :comma)
                                        (pc-advance ctx)))
                              (loc2   (pc-loc ctx))
                              (val    (parse-expr ctx))
                              (rel-op (cl-asm/ir:make-ir-operand
                                       :kind :direct :value val :loc loc2)))
                         (declare (ignore dummy))
                         (list zp-op rel-op)))
                      ;; MVN/MVP (65816 block move) : dst-bank , src-bank
                      ((member mnem-up '("MVN" "MVP") :test #'string=)
                       (let* ((loc1    (pc-loc ctx))
                              (dst-val (parse-expr ctx))
                              (dst-op  (cl-asm/ir:make-ir-operand
                                        :kind :direct :value dst-val :loc loc1))
                              (dummy   (when (eq (pc-kind ctx) :comma)
                                         (pc-advance ctx)))
                              (loc2    (pc-loc ctx))
                              (src-val (parse-expr ctx))
                              (src-op  (cl-asm/ir:make-ir-operand
                                        :kind :direct :value src-val :loc loc2)))
                         (declare (ignore dummy))
                         (list dst-op src-op)))
                      (t
                       (let ((operand (parse-operand ctx)))
                         (if operand (list operand) nil))))))
              (emit-node ctx
                         (cl-asm/ir:make-ir-instruction
                          :mnemonic mnem-base
                          :size mnem-size
                          :operands operands
                          :loc loc)))))))

      ;; Token :label-def émis directement par le lexer
      ;; Après le label, une instruction peut suivre sur la même ligne
      ((eq (pc-kind ctx) :label-def)
       (let* ((raw     (pc-value ctx))
              (name    (if (listp raw) (first raw) raw))
              (globalp (and (listp raw) (member :global raw))))
         (pc-advance ctx)
         (emit-node ctx
                    (cl-asm/ir:make-ir-label
                     :kind (if globalp :global :local)
                     :name (string-upcase name)
                     :loc loc)))
       ;; Suite possible sur la même ligne : loop: DEX  ou  main:: NOP
       (unless (member (pc-kind ctx) '(:newline :eof))
         (parse-line ctx)
         (return-from parse-line t)))

      ;; Token inattendu
      (t
       (parser-error ctx "Token inattendu en debut de ligne : ~A~@[ (~S)~]"
                     (pc-kind ctx) (pc-value ctx)))))

  ;; Consomme la fin de ligne
  (case (pc-kind ctx)
    (:newline (pc-advance ctx))
    (:eof     nil)
    (otherwise
     (parser-error ctx "Fin de ligne attendue, trouve ~A" (pc-kind ctx))))

  t)

(defun emit-node (ctx node)
  "Ajoute NODE à la section courante du contexte."
  (cl-asm/ir:section-append (parse-context-section ctx) node))


;;; --------------------------------------------------------------------------
;;;  Point d'entrée
;;; --------------------------------------------------------------------------

(defun parse-tokens (tokens &key (file nil) (section :text))
  "Parse une liste de TOKENS et retourne un IR-PROGRAM.
   FILE   : nom du fichier source (pour les messages d'erreur).
   SECTION : section initiale (défaut :text)."
  (declare (ignore file))
  (let* ((program  (cl-asm/ir:make-ir-program))
         (sect     (cl-asm/ir:program-find-or-create-section program section))
         (symtable (cl-asm/symbol-table:make-symbol-table))
         (ctx      (make-parse-context
                    :tokens        tokens
                    :section       sect
                    :program       program
                    :symtable      symtable
                    :macros        (make-hash-table :test #'equal)
                    :macro-counter 0)))
    (loop while (not (eq (pc-kind ctx) :eof))
          do (parse-line ctx))
    program))

(defun parse-string (source &key (file nil) (section :text))
  "Tokenise puis parse SOURCE. Retourne un IR-PROGRAM."
  (let ((tokens (cl-asm/lexer:tokenize-string source :file file)))
    (parse-tokens tokens :file file :section section)))

(defun parse-file (path &key (section :text))
  "Lit, tokenise et parse le fichier à PATH. Retourne un IR-PROGRAM."
  (let ((tokens (cl-asm/lexer:tokenize-file path)))
    (parse-tokens tokens :file (namestring path) :section section)))


;;; --------------------------------------------------------------------------
;;;  Helpers pour les instructions Rockwell R65C02
;;;  (RMB0..RMB7, SMB0..SMB7, BBR0..BBR7, BBS0..BBS7)
;;; --------------------------------------------------------------------------

(defun rockwell-mnemonic-p (name)
  "Retourne T si NAME est une instruction Rockwell valide.
   Attend une chaîne de 4 caractères : préfixe RMB/SMB/BBR/BBS + chiffre 0-7."
  (and (stringp name)
       (= (length name) 4)
       (let ((prefix (subseq name 0 3))
             (digit  (char name 3)))
         (and (member prefix '("RMB" "SMB" "BBR" "BBS") :test #'string=)
              (char<= #\0 digit #\7)))))

(defun rockwell-bit-number (name)
  "Extrait le numéro de bit (0-7) du nom d'une instruction Rockwell."
  (- (char-code (char name 3)) (char-code #\0)))

(defun rockwell-opcode (name)
  "Calcule l'opcode d'une instruction Rockwell.
   RMBn → n*$10 + $07
   SMBn → n*$10 + $87
   BBRn → n*$10 + $0F
   BBSn → n*$10 + $8F"
  (let ((n      (rockwell-bit-number name))
        (prefix (subseq name 0 3)))
    (cond
      ((string= prefix "RMB") (+ (* n #x10) #x07))
      ((string= prefix "SMB") (+ (* n #x10) #x87))
      ((string= prefix "BBR") (+ (* n #x10) #x0F))
      ((string= prefix "BBS") (+ (* n #x10) #x8F))
      (t (error "Mnémonique Rockwell inconnu : ~A" name)))))

(defun rockwell-two-operands-p (name)
  "Retourne T si NAME prend deux opérandes (BBR/BBS : zero-page + branche)."
  (let ((prefix (subseq name 0 3)))
    (or (string= prefix "BBR") (string= prefix "BBS"))))


;;; --------------------------------------------------------------------------
;;;  Helpers pour les instructions Z80
;;; --------------------------------------------------------------------------

(defvar *z80-mode* nil
  "T si on est en train d'assembler du code Z80.
   Quand NIL, les mnémoniques partagés avec 6502 (INC, DEC, AND…) sont
   traités par le parser 6502 standard.")

(defparameter *z80-mnemonics*
  '("LD" "LDI" "LDIR" "LDD" "LDDR"
    "PUSH" "POP"
    "EX" "EXX"
    "IN" "INI" "INIR" "IND" "INDR"
    "OUT" "OUTI" "OTIR" "OUTD" "OTDR"
    "ADD" "ADC" "SUB" "SBC" "AND" "OR" "XOR" "CP"
    "INC" "DEC"
    "DAA" "CPL" "NEG" "CCF" "SCF" "NOP" "HALT"
    "RLCA" "RLA" "RRCA" "RRA"
    "RLC" "RL" "RRC" "RR" "SLA" "SRA" "SRL" "SLL"
    "RLD" "RRD"
    "BIT" "SET" "RES"
    "JP" "JR" "CALL" "RET" "RETI" "RETN" "DJNZ"
    "RST"
    "IM"
    "CPI" "CPIR" "CPD" "CPDR"
    "DI" "EI")
  "Liste des mnémoniques Z80 (en majuscules).")

(defun z80-mnemonic-p (name)
  "Retourne T si NAME (chaîne majuscules) est un mnémonique Z80 ET que le
   mode Z80 est actif (*z80-mode* = T)."
  (and *z80-mode*
       (member name *z80-mnemonics* :test #'string=)
       t))

(defun z80-comma-is-6502-index-p (tok-after-comma tok-after-that)
  "Retourne T si TOK-AFTER-COMMA est X/Y/Z seul (fin de ligne).
   Distingue 'LDA $10,X' (6502) de 'LD A,B' (Z80).
   Un mnémonique Z80 comme AND peut apparaître dans du code 6502."
  (and tok-after-comma
       (eq (cl-asm/lexer:token-kind tok-after-comma) :identifier)
       (member (string-upcase (cl-asm/lexer:token-value tok-after-comma))
               '("X" "Y" "Z") :test #'string=)
       (or (null tok-after-that)
           (member (cl-asm/lexer:token-kind tok-after-that)
                   '(:newline :eof :comment) :test #'eq))))

(defun parse-z80-operand-raw (ctx)
  "Parse un opérande Z80 : registre, (reg), (IX+d), (nn), #n, ou expr.
   Retourne un IR-OPERAND.
   Ne consomme pas ',X' / ',Y' comme indicateur d'indexe."
  (let ((loc  (pc-loc ctx))
        (kind (pc-kind ctx)))
    (cond
      ;; Indirect : (expr) ou (IX+d) ou (IY+d)
      ((eq kind :lparen)
       (pc-advance ctx)                       ; consomme (
       (let ((inner-loc (pc-loc ctx))
             (val (parse-expr ctx)))          ; expr ou sym (IX, IY, HL, C…)
         ;; Déplacement optionnel : + ou -
         (let ((disp nil))
           (when (member (pc-kind ctx) '(:plus :minus) :test #'eq)
             (let ((sign (if (eq (pc-kind ctx) :plus) 1 -1)))
               (pc-advance ctx)
               (let ((d (parse-expr ctx)))
                 (setf disp (if (= sign 1) d (list '- d))))))
           (unless (eq (pc-kind ctx) :rparen)
             (error "')' attendu dans opérande Z80 (got ~A)" (pc-kind ctx)))
           (pc-advance ctx)                   ; consomme )
           (if disp
               (cl-asm/ir:make-ir-operand
                :kind :indirect :value (list :+ val disp) :loc inner-loc)
               (cl-asm/ir:make-ir-operand
                :kind :indirect :value val :loc inner-loc)))))
      ;; Immédiat # (syntaxe optionnelle)
      ((eq kind :hash)
       (pc-advance ctx)
       (cl-asm/ir:make-ir-operand
        :kind :immediate :value (parse-expr ctx) :loc loc))
      ;; Identificateur, nombre, expression
      (t
       (cl-asm/ir:make-ir-operand
        :kind :direct :value (parse-expr ctx) :loc loc)))))

(defun parse-z80-operands (ctx)
  "Parse 0, 1 ou 2 opérandes Z80 séparés par une virgule.
   Distingue 'ADD A, B' (Z80, 2 opérandes) de 'AND $10,X' (6502 index)."
  (when (member (pc-kind ctx) '(:newline :eof :comment) :test #'eq)
    (return-from parse-z80-operands nil))
  (let ((op1 (parse-z80-operand-raw ctx)))
    (cond
      ;; Virgule présente
      ((eq (pc-kind ctx) :comma)
       (let ((tok-after  (pc-peek ctx 1))
             (tok-after2 (pc-peek ctx 2)))
         (cond
           ;; Virgule 6502-index : ,X  ,Y  ,Z  seul en fin de ligne
           ((z80-comma-is-6502-index-p tok-after tok-after2)
            ;; On ne consomme pas la virgule — le backend 6502 la verra si besoin
            (list op1))
           ;; Virgule Z80 : deuxième opérande
           (t
            (pc-advance ctx)                 ; consomme ,
            (list op1 (parse-z80-operand-raw ctx))))))
      ;; Pas de virgule — opérande unique
      (t (list op1)))))


;;; ==========================================================================
;;;  Mode M68K (Motorola 68000)
;;;
;;;  Activé via *m68k-mode* = T (lié par assemble-string-m68k / assemble-file-m68k).
;;;  Quand NIL, aucun impact sur les autres architectures.
;;;
;;;  Nouveaux kinds d'IR-OPERAND introduits :
;;;    :post-increment  — (An)+,  value = nom registre string ("A0"…"SP")
;;;    :pre-decrement   — -(An),  value = nom registre string
;;;    :indirect  avec value structurée :
;;;      (:disp "An" expr)            — d(An) ou d(PC) (:pc comme symbole)
;;;      (:indexed "An" "Xi" size d)  — d(An,Xi.s) ou d(PC,Xi.s)
;;;    :direct avec value = string registre — Dn / An / SP / PC / SR / CCR
;;; ==========================================================================

(defvar *m68k-mode* nil
  "T si on est en train d'assembler du code M68K (Motorola 68000).
   Quand NIL, aucun mnémonique M68K n'est reconnu — pas d'impact sur
   6502, Z80 ou les autres architectures.")

(defparameter *m68k-base-mnemonics*
  '("MOVE" "MOVEA" "MOVEM" "MOVEP" "MOVEQ"
    "ADD" "ADDA" "ADDI" "ADDQ" "ADDX"
    "SUB" "SUBA" "SUBI" "SUBQ" "SUBX"
    "AND" "ANDI" "OR" "ORI" "EOR" "EORI"
    "CMP" "CMPA" "CMPI" "CMPM"
    "MULU" "MULS" "DIVU" "DIVS"
    "NEG" "NEGX" "NOT" "CLR" "TST" "EXT" "EXTB" "SWAP"
    "ASL" "ASR" "LSL" "LSR" "ROL" "ROR" "ROXL" "ROXR"
    "BTST" "BCHG" "BCLR" "BSET"
    "BRA" "BSR"
    "BEQ" "BNE" "BLT" "BGT" "BLE" "BGE"
    "BCC" "BCS" "BMI" "BPL" "BVC" "BVS" "BHI" "BLS" "BNOT"
    "DBF" "DBRA" "DBEQ" "DBNE" "DBLT" "DBGT" "DBLE" "DBGE"
    "DBCC" "DBCS" "DBMI" "DBPL" "DBVC" "DBVS" "DBHI" "DBLS"
    "SF" "ST" "SEQ" "SNE" "SLT" "SGT" "SLE" "SGE"
    "SCC" "SCS" "SMI" "SPL" "SVC" "SVS" "SHI" "SLS"
    "JMP" "JSR" "RTS" "RTR" "RTE"
    "NOP" "STOP" "RESET" "ILLEGAL"
    "TRAP" "TRAPV" "CHK" "LINK" "UNLK"
    "LEA" "PEA" "TAS"
    "ABCD" "SBCD" "NBCD"
    "EXG"
    "DC" "DS" "ORG")
  "Mnémoniques M68K de base (sans suffixe .B/.W/.L).")

(defun m68k-base-mnemonic (name)
  "Retourne le mnémonique sans suffixe de taille : 'MOVE.B' → 'MOVE'."
  (let ((dot-pos (position #\. name)))
    (if dot-pos (subseq name 0 dot-pos) name)))

(defun m68k-size-from-mnemonic (name)
  "Retourne le hint de taille depuis le suffixe du mnémonique.
   'MOVE.B' → :byte, 'MOVE.W' → :word, 'MOVE.L' → :long, 'BRA.S' → :byte, NIL si absent."
  (let ((dot-pos (position #\. name)))
    (when dot-pos
      (let ((suffix (subseq name (1+ dot-pos))))
        (cond ((string= suffix "B") :byte)
              ((string= suffix "W") :word)
              ((string= suffix "L") :long)
              ((string= suffix "S") :byte)
              (t nil))))))

(defun m68k-mnemonic-p (name)
  "Retourne T si NAME est un mnémonique M68K ET que *m68k-mode* = T.
   Gère les suffixes de taille : 'MOVE.B' est reconnu comme 'MOVE'."
  (and *m68k-mode*
       (member (m68k-base-mnemonic name) *m68k-base-mnemonics* :test #'string=)
       t))

(defparameter *m68k-data-registers*
  '("D0" "D1" "D2" "D3" "D4" "D5" "D6" "D7")
  "Registres de données M68K.")

(defparameter *m68k-addr-registers*
  '("A0" "A1" "A2" "A3" "A4" "A5" "A6" "A7" "SP")
  "Registres d'adresse M68K. SP = A7.")

(defparameter *m68k-special-registers*
  '("PC" "SR" "CCR" "USP")
  "Registres spéciaux M68K.")

(defparameter *m68k-all-registers*
  (append *m68k-data-registers* *m68k-addr-registers* *m68k-special-registers*)
  "Tous les registres M68K.")

(defun m68k-register-p (name)
  "Vrai si NAME (string, déjà en majuscules) est un registre M68K."
  (member name *m68k-all-registers* :test #'string=))

(defun m68k-register-with-size (name)
  "Décompose 'D1.W' en (values \"D1\" :word).
   Sans suffixe, retourne (values NAME NIL)."
  (let ((dot-pos (position #\. name)))
    (if dot-pos
        (let ((reg    (subseq name 0 dot-pos))
              (suffix (subseq name (1+ dot-pos))))
          (values reg
                  (cond ((string= suffix "W") :word)
                        ((string= suffix "L") :long)
                        (t nil))))
        (values name nil))))

(defun parse-m68k-operand (ctx)
  "Parse un opérande M68K. Retourne un IR-OPERAND.

   Modes reconnus :
     #expr           → :immediate
     Dn / An / SR…   → :direct \"Dn\"
     (An)            → :indirect \"An\"
     (An)+           → :post-increment \"An\"
     -(An)           → :pre-decrement \"An\"
     d(An)           → :indirect (:disp \"An\" d)
     d(PC)           → :indirect (:disp :pc d)
     d(An,Xi.s)      → :indirect (:indexed \"An\" \"Xi\" size d)
     d(PC,Xi.s)      → :indirect (:indexed :pc \"Xi\" size d)
     (An,Xi.s)       → :indirect (:indexed \"An\" \"Xi\" size 0)
     expr            → :direct expr  (adresse absolue)"
  (let ((loc (pc-loc ctx)))
    (cond
      ;; #expr — immédiat
      ((eq (pc-kind ctx) :hash)
       (pc-advance ctx)
       (cl-asm/ir:make-ir-operand :kind :immediate :value (parse-expr ctx) :loc loc))

      ;; -(An) — pré-décrémentation
      ((and (eq (pc-kind ctx) :minus)
            (let ((nxt (pc-peek ctx 1)))
              (and nxt (eq (cl-asm/lexer:token-kind nxt) :lparen))))
       (pc-advance ctx)                     ; consomme -
       (pc-advance ctx)                     ; consomme (
       (let ((reg (string-upcase (pc-value ctx))))
         (pc-advance ctx)                   ; consomme nom registre
         (pc-expect ctx :rparen)
         (cl-asm/ir:make-ir-operand :kind :pre-decrement :value reg :loc loc)))

      ;; (expr) — indirect registre, post-incrémentation, ou indexé sans déplacement
      ((eq (pc-kind ctx) :lparen)
       (pc-advance ctx)                     ; consomme (
       (let ((inner (parse-expr ctx)))
         (cond
           ;; (An,Xi.s) — indexé, déplacement implicite 0
           ((eq (pc-kind ctx) :comma)
            (pc-advance ctx)               ; consomme ,
            (multiple-value-bind (xi-reg xi-size)
                (m68k-register-with-size (string-upcase (pc-value ctx)))
              (pc-advance ctx)             ; consomme Xi
              (pc-expect ctx :rparen)
              (cl-asm/ir:make-ir-operand
               :kind :indirect
               :value (list :indexed inner xi-reg xi-size 0)
               :loc loc)))
           ;; (An) ou (An)+
           (t
            (pc-expect ctx :rparen)
            (cond
              ;; (An)+ — post-incrémentation
              ((eq (pc-kind ctx) :plus)
               (pc-advance ctx)           ; consomme +
               (cl-asm/ir:make-ir-operand :kind :post-increment :value inner :loc loc))
              ;; (An) — indirect
              (t
               (cl-asm/ir:make-ir-operand :kind :indirect :value inner :loc loc)))))))

      ;; expr éventuellement suivie de (An) ou (An,Xi) — déplacement
      (t
       (let ((val (parse-expr ctx)))
         (cond
           ;; d(An) ou d(An,Xi.s) ou d(PC) ou d(PC,Xi.s)
           ((eq (pc-kind ctx) :lparen)
            (pc-advance ctx)               ; consomme (
            (let ((base (string-upcase (pc-value ctx))))
              (pc-advance ctx)             ; consomme base (An ou PC)
              (cond
                ;; d(An,Xi.s) ou d(PC,Xi.s)
                ((eq (pc-kind ctx) :comma)
                 (pc-advance ctx)         ; consomme ,
                 (multiple-value-bind (xi-reg xi-size)
                     (m68k-register-with-size (string-upcase (pc-value ctx)))
                   (pc-advance ctx)       ; consomme Xi
                   (pc-expect ctx :rparen)
                   (let ((base-kw (if (string= base "PC") :pc base)))
                     (cl-asm/ir:make-ir-operand
                      :kind :indirect
                      :value (list :indexed base-kw xi-reg xi-size val)
                      :loc loc))))
                ;; d(An) ou d(PC)
                (t
                 (pc-expect ctx :rparen)
                 (let ((base-kw (if (string= base "PC") :pc base)))
                   (cl-asm/ir:make-ir-operand
                    :kind :indirect
                    :value (list :disp base-kw val)
                    :loc loc))))))
           ;; Registre direct ou adresse absolue
           (t
            (cl-asm/ir:make-ir-operand :kind :direct :value val :loc loc))))))))

(defun parse-m68k-operands (ctx)
  "Parse 0, 1 ou 2 opérandes M68K séparés par une virgule."
  (when (member (pc-kind ctx) '(:newline :eof) :test #'eq)
    (return-from parse-m68k-operands nil))
  (let ((op1 (parse-m68k-operand ctx)))
    (if (eq (pc-kind ctx) :comma)
        (progn
          (pc-advance ctx)               ; consomme ,
          (list op1 (parse-m68k-operand ctx)))
        (list op1))))
