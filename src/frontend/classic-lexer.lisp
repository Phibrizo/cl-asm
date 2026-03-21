; -*- coding: utf-8 -*-
(defpackage #:cl-asm/lexer
  (:use #:cl)
  (:export
   #:token #:make-token
   #:token-kind #:token-value #:token-loc
   #:token-is #:token-is-one-of
   #:lex-context #:make-lex-context
   #:lexer-error
   #:tokenize #:tokenize-string #:tokenize-file #:tokens->string
   #:*star-comment-col1*))
;;; src/frontend/classic-lexer.lisp
;;;
;;; Lexer pour syntaxes assembleur textuelles (ca65-like, NASM-like).
;;;
;;; Transforme une chaîne ou un flux source en une liste de tokens.
;;; Chaque token est une structure TOKEN avec :
;;;   - kind    : keyword identifiant le type
;;;   - value   : valeur extraite (entier, string, keyword...)
;;;   - loc     : SOURCE-LOC (fichier, ligne, colonne)
;;;
;;; Types de tokens produits :
;;;
;;;   :integer      42  $FF  0xFF  %1010  0b1010
;;;   :char-literal valeur ASCII d'un caractère entre apostrophes : 'A'
;;;   :string       "hello"
;;;   :identifier   nom non réservé (label, constante, variable macro...)
;;;   :mnemonic     LDA STA LDZ... (déterminé par le frontend, pas le lexer)
;;;   :register     A X Y Z B SP (déterminé par le frontend)
;;;   :directive    .byte .word .org .equ .define .include ...
;;;   :label-def    nom: ou nom::  (label suivi de : ou ::)
;;;   :local-label-def  @nom: .nom: (label local)
;;;   :numeric-label-def  1: 2: ... 9:
;;;   :comma        ,
;;;   :colon        :
;;;   :hash         #   (préfixe immédiat)
;;;   :lparen       (
;;;   :rparen       )
;;;   :lbracket     [
;;;   :rbracket     ]
;;;   :plus         +
;;;   :minus        -
;;;   :star         *
;;;   :slash        /
;;;   :percent      %   (début littéral binaire ou modulo selon contexte)
;;;   :ampersand    &
;;;   :pipe         |   (OR bit-à-bit)
;;;   :caret        ^   (XOR)
;;;   :tilde        ~   (NOT)
;;;   :lt           <   (octet bas)
;;;   :gt           >   (octet haut)
;;;   :lshift       <<
;;;   :rshift       >>
;;;   :equals       =
;;;   :newline      fin de ligne logique (séparateur d'instructions)
;;;   :eof          fin de fichier
;;;
;;; Note : le lexer ne distingue pas mnémoniques / registres / identifiants.
;;; C'est le rôle du parser (ou d'une passe de classification) de décider
;;; si "LDA" est un mnémonique ou un identifiant selon le contexte.


(in-package #:cl-asm/lexer)


;;; --------------------------------------------------------------------------
;;;  Structure TOKEN
;;; --------------------------------------------------------------------------

(defstruct token
  "Un token produit par le lexer."
  (kind  :eof  :type keyword)
  (value nil)
  (loc   nil))

(defun token-is (token kind)
  "Vrai si TOKEN est du type KIND."
  (eq (token-kind token) kind))

(defun token-is-one-of (token &rest kinds)
  "Vrai si le type de TOKEN est dans KINDS."
  (member (token-kind token) kinds))


;;; --------------------------------------------------------------------------
;;;  Conditions
;;; --------------------------------------------------------------------------

(defvar *star-comment-col1* nil
  "Quand T, '*' en colonne 1 est traité comme commentaire de fin de ligne
   (syntaxe Motorola 68000 / DevPac / vasm motorola). NIL par défaut.")

(define-condition lexer-error (cl-asm/ir:asm-error) ()
  (:documentation "Erreur de tokenisation."))

(defun lexer-error (loc fmt &rest args)
  (error 'lexer-error
         :message (apply #'format nil fmt args)
         :source-loc loc))


;;; --------------------------------------------------------------------------
;;;  Contexte de lexing
;;; --------------------------------------------------------------------------

(defstruct lex-context
  "État courant du lexer."
  (source  ""  :type string)   ; texte source complet
  (pos     0   :type fixnum)   ; position courante (index dans source)
  (line    1   :type fixnum)   ; numéro de ligne courant
  (col     1   :type fixnum)   ; numéro de colonne courant
  (file    nil)                ; nom du fichier (pour source-loc)
  (tokens  nil :type list))    ; tokens accumulés (dans l'ordre inverse)

(defun lc-current (ctx)
  "Caractère courant, ou NIL en fin de source."
  (let ((pos (lex-context-pos ctx))
        (src (lex-context-source ctx)))
    (when (< pos (length src))
      (char src pos))))

(defun lc-peek (ctx &optional (offset 1))
  "Caractère à OFFSET positions devant la position courante."
  (let ((pos (+ (lex-context-pos ctx) offset))
        (src (lex-context-source ctx)))
    (when (< pos (length src))
      (char src pos))))

(defun lc-advance (ctx)
  "Avance d'un caractère, met à jour ligne/colonne. Retourne le char lu."
  (let ((ch (lc-current ctx)))
    (when ch
      (incf (lex-context-pos ctx))
      (if (char= ch #\Newline)
          (progn
            (incf (lex-context-line ctx))
            (setf (lex-context-col ctx) 1))
          (incf (lex-context-col ctx))))
    ch))

(defun lc-loc (ctx)
  "Source-loc courante."
  (cl-asm/ir:make-source-loc
   :file   (lex-context-file ctx)
   :line   (lex-context-line ctx)
   :column (lex-context-col  ctx)))

(defun lc-emit (ctx kind value loc)
  "Ajoute un token à la liste (en tête — sera inversée à la fin)."
  (push (make-token :kind kind :value value :loc loc)
        (lex-context-tokens ctx)))


;;; --------------------------------------------------------------------------
;;;  Helpers de classification de caractères
;;; --------------------------------------------------------------------------

(defun digit-p (ch &optional (radix 10))
  "Vrai si CH est un chiffre dans la base RADIX."
  (and ch (digit-char-p ch radix)))

(defun alpha-p (ch)
  (and ch (alpha-char-p ch)))

(defun alnum-p (ch)
  (and ch (alphanumericp ch)))

(defun ident-start-p (ch)
  "Caractères valides pour débuter un identifiant."
  (and ch (or (alpha-char-p ch)
              (char= ch #\_)
              (char= ch #\@)
              (char= ch #\.))))

(defun ident-cont-p (ch)
  "Caractères valides pour continuer un identifiant."
  (and ch (or (alphanumericp ch)
              (char= ch #\_)
              (char= ch #\@)
              (char= ch #\.)
              (char= ch #\?))))

(defun whitespace-p (ch)
  (and ch (member ch '(#\Space #\Tab #\Return) :test #'char=)))


;;; --------------------------------------------------------------------------
;;;  Lecture des littéraux numériques
;;; --------------------------------------------------------------------------

(defun read-digits (ctx radix)
  "Lit une séquence de chiffres dans RADIX, retourne la valeur entière."
  (let ((start (lex-context-pos ctx))
        (val 0))
    (loop while (digit-p (lc-current ctx) radix)
          do (setf val (+ (* val radix)
                          (digit-char-p (lc-advance ctx) radix)))
          finally (when (= (lex-context-pos ctx) start)
                    (return nil)))
    val))

(defun lex-number (ctx loc)
  "Lit un littéral numérique depuis la position courante.
   Formats supportés :
     $FF $1234        hexadécimal préfixé par $
     0xFF 0XFF        hexadécimal préfixé par 0x
     %10110011        binaire préfixé par %
     0b10110011 0B..  binaire préfixé par 0b
     42 1000          décimal
   Retourne la valeur entière ou NIL si aucun nombre reconnu."
  (let ((ch (lc-current ctx)))
    (cond
      ;; Hexadécimal : $FF
      ((char= ch #\$)
       (lc-advance ctx)
       (let ((val (read-digits ctx 16)))
         (unless val (lexer-error loc "Chiffre hexadécimal attendu après '$'"))
         val))

      ;; Binaire : %10110011
      ((char= ch #\%)
       (lc-advance ctx)
       (let ((val (read-digits ctx 2)))
         (unless val (lexer-error loc "Chiffre binaire attendu après '%'"))
         val))

      ;; 0x... ou 0b... ou 0 seul
      ((and (char= ch #\0)
            (lc-peek ctx))
       (let ((next (lc-peek ctx)))
         (cond
           ((member next '(#\x #\X) :test #'char=)
            (lc-advance ctx) (lc-advance ctx)   ; consomme 0x
            (let ((val (read-digits ctx 16)))
              (unless val (lexer-error loc "Chiffre hexadécimal attendu après '0x'"))
              val))
           ((member next '(#\b #\B) :test #'char=)
            (lc-advance ctx) (lc-advance ctx)   ; consomme 0b
            (let ((val (read-digits ctx 2)))
              (unless val (lexer-error loc "Chiffre binaire attendu après '0b'"))
              val))
           (t
            (read-digits ctx 10)))))

      ;; Décimal
      ((digit-p ch 10)
       (read-digits ctx 10))

      (t nil))))


;;; --------------------------------------------------------------------------
;;;  Lecture des chaînes et caractères
;;; --------------------------------------------------------------------------

(defun lex-string (ctx loc)
  "Lit une chaîne entre guillemets doubles. Gère les séquences d'échappement."
  (lc-advance ctx)   ; consomme le "
  (let ((buf (make-array 64 :element-type 'character
                            :fill-pointer 0 :adjustable t)))
    (loop
      (let ((ch (lc-current ctx)))
        (cond
          ((null ch)
           (lexer-error loc "Fin de fichier dans une chaîne littérale"))
          ((char= ch #\Newline)
           (lexer-error loc "Fin de ligne dans une chaîne littérale"))
          ((char= ch #\")
           (lc-advance ctx)
           (return (coerce buf 'string)))
          ((char= ch #\\)
           (lc-advance ctx)
           (let ((esc (lc-advance ctx)))
             (vector-push-extend
              (case esc
                (#\n  #\Newline)
                (#\t  #\Tab)
                (#\r  #\Return)
                (#\0  #\Nul)
                (#\\  #\\)
                (#\"  #\")
                (otherwise
                 (lexer-error loc "Séquence d'échappement inconnue : \\~C" esc)))
              buf)))
          (t
           (vector-push-extend (lc-advance ctx) buf)))))))

(defun lex-char-literal (ctx loc)
  "Lit un littéral caractère entre apostrophes : 'A' -> 65."
  (lc-advance ctx)   ; consomme le '
  (let ((ch (lc-advance ctx)))
    (unless ch (lexer-error loc "Fin de fichier dans un littéral caractère"))
    (let ((val (if (char= ch #\\)
                   ;; Séquence d'échappement
                   (let ((esc (lc-advance ctx)))
                     (case esc
                       (#\n 10) (#\t 9) (#\r 13) (#\0 0)
                       (#\\ 92) (#\' 39)
                       (otherwise
                        (lexer-error loc "Séquence d'échappement inconnue : \\~C" esc))))
                   (char-code ch))))
      (let ((close (lc-advance ctx)))
        (unless (and close (char= close #\'))
          (lexer-error loc "Apostrophe fermante attendue")))
      val)))


;;; --------------------------------------------------------------------------
;;;  Lecture des identifiants et labels
;;; --------------------------------------------------------------------------

(defun lex-identifier (ctx)
  "Lit un identifiant ou un label. Retourne (values STRING LABEL-P GLOBAL-P).
   LABEL-P est T si suivi de ':'.
   GLOBAL-P est T si suivi de '::'."
  (let ((buf (make-array 32 :element-type 'character
                            :fill-pointer 0 :adjustable t)))
    (loop while (ident-cont-p (lc-current ctx))
          do (vector-push-extend (lc-advance ctx) buf))
    (let ((name (coerce buf 'string)))
      ;; Tester si c'est une définition de label
      (cond
        ;; '::' = label global (ca65)
        ((and (eql (lc-current ctx) #\:)
              (eql (lc-peek ctx) #\:))
         (lc-advance ctx) (lc-advance ctx)
         (values name :label-global))
        ;; ':' = label local ou normal
        ((eql (lc-current ctx) #\:)
         (lc-advance ctx)
         (values name :label-local))
        ;; identifiant simple
        (t
         (values name :identifier))))))


;;; --------------------------------------------------------------------------
;;;  Lecture des commentaires
;;; --------------------------------------------------------------------------

(defun skip-line-comment (ctx)
  "Saute jusqu'à la fin de ligne (commentaire ; ou //)."
  (loop while (and (lc-current ctx)
                   (not (char= (lc-current ctx) #\Newline)))
        do (lc-advance ctx)))


;;; --------------------------------------------------------------------------
;;;  Tokeniseur principal
;;; --------------------------------------------------------------------------

(defun tokenize (source &key (file nil) (tab-width 8))
  "Tokenise SOURCE (string) et retourne une liste de tokens.
   FILE : nom du fichier source (pour les messages d'erreur).
   TAB-WIDTH : largeur d'une tabulation pour le calcul des colonnes."
  (declare (ignore tab-width))
  (let ((ctx (make-lex-context :source source :file file)))
    (loop
      (let ((ch (lc-current ctx)))

        ;; Fin de fichier
        (when (null ch)
          (lc-emit ctx :eof nil (lc-loc ctx))
          (return))

        (let ((loc (lc-loc ctx)))
          (cond

            ;; Espaces horizontaux — ignorés
            ((whitespace-p ch)
             (lc-advance ctx))

            ;; Caracteres nuls et non-ASCII (codes > 127) — ignores silencieusement.
            ;; Peuvent apparaitre dans les commentaires de fichiers Latin-1
            ;; ou comme artefacts de conversion d'encodage.
            ((or (char= ch #\Nul)
                 (> (char-code ch) 127))
             (lc-advance ctx))

            ;; Fin de ligne — séparateur logique d'instructions
            ((char= ch #\Newline)
             (lc-advance ctx)
             ;; N'émettre :newline que s'il n'y en a pas déjà un en tête
             (unless (and (lex-context-tokens ctx)
                          (token-is (first (lex-context-tokens ctx)) :newline))
               (lc-emit ctx :newline nil loc)))

            ;; Commentaire ; (style ca65/NASM)
            ((char= ch #\;)
             (skip-line-comment ctx))

            ;; Commentaire // (style NASM alternatif)
            ((and (char= ch #\/)
                  (eql (lc-peek ctx) #\/))
             (skip-line-comment ctx))

            ;; Littéral numérique : $ % 0x 0b ou chiffre décimal
            ;; Cas spécial : un chiffre seul suivi de ':' = label numérique (1: 2:...)
            ((or (char= ch #\$)
                 (and (char= ch #\%) (digit-p (lc-peek ctx) 2))
                 (digit-p ch 10))
             (let ((val (lex-number ctx loc)))
               (cond
                 ;; Label numérique : chiffre simple (1-9) suivi de ':'
                 ((and val
                       (< val 10)
                       (eql (lc-current ctx) #\:)
                       (not (eql (lc-peek ctx) #\:)))   ; pas ::
                  (lc-advance ctx)   ; consomme le ':'
                  (lc-emit ctx :numeric-label-def val loc))
                 (val
                  (lc-emit ctx :integer val loc))
                 (t
                  ;; % seul (pas suivi d'un binaire) = opérateur modulo
                  (lc-advance ctx)
                  (lc-emit ctx :percent nil loc)))))

            ;; Littéral caractère 'A'
            ((char= ch #\')
             (lc-emit ctx :integer (lex-char-literal ctx loc) loc))

            ;; Chaîne "..."
            ((char= ch #\")
             (lc-emit ctx :string (lex-string ctx loc) loc))

            ;; Identifiant, directive (.xxx) ou label local (@xxx)
            ((ident-start-p ch)
             (multiple-value-bind (name kind) (lex-identifier ctx)
               (ecase kind
                 (:label-global
                  (lc-emit ctx :label-def name loc)
                  (setf (token-value (first (lex-context-tokens ctx)))
                        (list name :global)))
                 (:label-local
                  (if (and (> (length name) 0)
                           (digit-char-p (char name 0)))
                      ;; Label numérique : 1: 2: ...
                      (lc-emit ctx :numeric-label-def
                               (digit-char-p (char name 0)) loc)
                      ;; Label normal
                      (lc-emit ctx :label-def name loc)))
                 (:identifier
                  (lc-emit ctx :identifier name loc)))))

            ;; Opérateurs et ponctuations
            ((char= ch #\,) (lc-advance ctx) (lc-emit ctx :comma     nil loc))
            ((char= ch #\:) (lc-advance ctx) (lc-emit ctx :colon     nil loc))
            ((char= ch #\#) (lc-advance ctx) (lc-emit ctx :hash      nil loc))
            ((char= ch #\() (lc-advance ctx) (lc-emit ctx :lparen    nil loc))
            ((char= ch #\)) (lc-advance ctx) (lc-emit ctx :rparen    nil loc))
            ((char= ch #\[) (lc-advance ctx) (lc-emit ctx :lbracket  nil loc))
            ((char= ch #\]) (lc-advance ctx) (lc-emit ctx :rbracket  nil loc))
            ((char= ch #\+) (lc-advance ctx) (lc-emit ctx :plus      nil loc))
            ((char= ch #\-) (lc-advance ctx) (lc-emit ctx :minus     nil loc))
            ;; '*' : commentaire col 1 si *star-comment-col1* actif (mode M68K),
            ;; sinon opérateur / référence PC.
            ((char= ch #\*)
             (if (and *star-comment-col1* (= (lex-context-col ctx) 1))
                 (skip-line-comment ctx)
                 (progn (lc-advance ctx) (lc-emit ctx :star nil loc))))
            ((char= ch #\&) (lc-advance ctx) (lc-emit ctx :ampersand nil loc))
            ((char= ch #\^) (lc-advance ctx) (lc-emit ctx :caret     nil loc))
            ((char= ch #\~) (lc-advance ctx) (lc-emit ctx :tilde     nil loc))
            ((char= ch #\=) (lc-advance ctx) (lc-emit ctx :equals    nil loc))
            ((char= ch #\|) (lc-advance ctx) (lc-emit ctx :pipe      nil loc))

            ;; < et << , > et >>
            ((char= ch #\<)
             (lc-advance ctx)
             (if (eql (lc-current ctx) #\<)
                 (progn (lc-advance ctx) (lc-emit ctx :lshift nil loc))
                 (lc-emit ctx :lt nil loc)))

            ((char= ch #\>)
             (lc-advance ctx)
             (if (eql (lc-current ctx) #\>)
                 (progn (lc-advance ctx) (lc-emit ctx :rshift nil loc))
                 (lc-emit ctx :gt nil loc)))

            ;; / et //
            ((char= ch #\/)
             (lc-advance ctx)
             (lc-emit ctx :slash nil loc))

            ;; % seul (modulo, pas binaire — le cas binaire est traité plus haut)
            ((char= ch #\%)
             (lc-advance ctx)
             (lc-emit ctx :percent nil loc))

            ;; Caractère inconnu
            (t
             (lexer-error loc "Caractère inattendu : ~S (code ~D)"
                          ch (char-code ch)))))))

    ;; Retourner les tokens dans l'ordre correct
    (nreverse (lex-context-tokens ctx))))


;;; --------------------------------------------------------------------------
;;;  Utilitaires publics
;;; --------------------------------------------------------------------------

(defun tokenize-string (source &key file)
  "Tokenise SOURCE et retourne la liste de tokens."
  (tokenize source :file file))

(defun tokenize-file (path)
  "Lit et tokenise le fichier à PATH."
  (let ((source (with-open-file (s path :direction :input)
                  (let ((buf (make-string (file-length s))))
                    (read-sequence buf s)
                    buf))))
    (tokenize source :file (namestring path))))

(defun tokens->string (tokens)
  "Représentation lisible d'une liste de tokens (debug)."
  (with-output-to-string (s)
    (dolist (tok tokens)
      (format s "~A~@[:~A~]~%"
              (token-kind tok)
              (token-value tok)))))
