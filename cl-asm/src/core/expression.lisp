; -*- coding: utf-8 -*-
(defpackage #:cl-asm/expression
  (:use #:cl)
  (:export
   #:eval-expr #:eval-expr/integer #:eval-expr/byte
   #:eval-expr/sbyte #:eval-expr/word #:eval-expr/dword
   #:make-env #:env-symbol-table #:env-source-loc #:env-pc
   #:constant-expr-p
   #:expression-error #:division-by-zero-error
   #:unknown-operator-error #:wrong-arity-error
   #:expr-error-operator #:expr-error-expected #:expr-error-got))
(in-package #:cl-asm/expression)

;;; ==========================================================================
;;;  cl-asm / expression.lisp
;;;
;;;  Évaluateur d'expressions arithmétiques pour l'assembleur.
;;;
;;;  Les expressions sont représentées comme des arbres préfixés (listes Lisp)
;;;  construits par le parser. Exemples de formes valides :
;;;
;;;    42                        ; littéral entier
;;;    "LABEL"                   ; référence a un symbole
;;;    (:+ "BASE" 16)            ; BASE + 16
;;;    (:- (:* 3 "COUNT") 1)     ; 3*COUNT - 1
;;;    (:lo "VEC")               ; octet bas de VEC
;;;    (:hi "VEC")               ; octet haut de VEC
;;;    (:bank "VEC")             ; octet de banque (bits 16-23, 45GS02)
;;;    (:>> "VAL" 2)             ; VAL >> 2
;;;    (:& "FLAGS" #xFF)         ; FLAGS & 0xFF
;;;    (:bitor "A" "B")             ; A | B
;;;    (:^ "X" #x80)             ; X ^ 0x80  (XOR)
;;;    (:~ "MASK")               ; ~MASK  (NOT bit-à-bit)
;;;    (:neg "X")                ; -X  (négation arithmétique)
;;;    (:defined "SYM")          ; 1 si SYM est défini, 0 sinon
;;;    (:current-pc)             ; valeur courante du PC ($*)
;;;
;;;  Toutes les opérations sont en arithmétique entière non bornée.
;;;  Les résultats sont tronqués selon le contexte d'utilisation
;;;  (l'encodeur d'instruction est responsable de la vérification de plage).
;;;
;;;  Interface publique :
;;;    (eval-expr expr env)  → (values valeur resolvedp)
;;;
;;;  ENV est une plist :
;;;    (:symbol-table ST :source-loc LOC :pc ADDR)
;;; ==========================================================================


;;; --------------------------------------------------------------------------
;;;  Conditions
;;; --------------------------------------------------------------------------

(define-condition expression-error (cl-asm/ir:asm-error) ()
  (:documentation "Erreur lors de l'évaluation d'une expression."))

(define-condition division-by-zero-error (expression-error) ()
  (:report (lambda (c s)
             (format s "Division par zéro dans une expression assembleur.~@[~% → ~A~]"
                     (cl-asm/ir:asm-error-source-loc c)))))

(define-condition unknown-operator-error (expression-error)
  ((operator :initarg :operator :reader expr-error-operator))
  (:report (lambda (c s)
             (format s "Opérateur d'expression inconnu : ~S~@[~% → ~A~]"
                     (expr-error-operator c)
                     (cl-asm/ir:asm-error-source-loc c)))))

(define-condition wrong-arity-error (expression-error)
  ((operator :initarg :operator :reader expr-error-operator)
   (expected :initarg :expected :reader expr-error-expected)
   (got      :initarg :got      :reader expr-error-got))
  (:report (lambda (c s)
             (format s "Opérateur ~S attend ~A argument(s), reçu ~A.~@[~% → ~A~]"
                     (expr-error-operator c)
                     (expr-error-expected c)
                     (expr-error-got      c)
                     (cl-asm/ir:asm-error-source-loc c)))))


;;; --------------------------------------------------------------------------
;;;  Helpers internes
;;; --------------------------------------------------------------------------

(defun env-symbol-table (env)
  (getf env :symbol-table))

(defun env-source-loc (env)
  (getf env :source-loc))

(defun env-pc (env)
  (getf env :pc 0))

(defun check-arity (op args expected-count)
  "Vérifie que ARGS contient exactement EXPECTED-COUNT éléments."
  (unless (= (length args) expected-count)
    (error 'wrong-arity-error
           :operator op
           :expected expected-count
           :got      (length args)
           :message  (format nil "Opérateur ~S : arité incorrecte" op))))

(defun check-arity-min (op args min-count)
  "Vérifie que ARGS contient au moins MIN-COUNT éléments."
  (when (< (length args) min-count)
    (error 'wrong-arity-error
           :operator op
           :expected (format nil "≥~D" min-count)
           :got      (length args)
           :message  (format nil "Opérateur ~S : pas assez d'arguments" op))))

(defmacro with-resolved-args ((args-var env resolved-var all-resolved-var) &body body)
  "Évalue chaque argument dans ARGS-VAR avec ENV.
   RESOLVED-VAR est lié a la liste des valeurs (ou :unresolved).
   ALL-RESOLVED-VAR est T si tous les arguments ont pu être résolus.
   Si un argument n'est pas résolu et qu'on est en pass 2, on propage l'erreur
   naturellement (resolve-symbol aura déjà signalé)."
  (let ((vals-sym (gensym "VALS-"))
        (ok-sym   (gensym "OK-"))
        (a-sym    (gensym "A-"))
        (v-sym    (gensym "V-"))
        (r-sym    (gensym "R-")))
    `(let* ((,vals-sym
              (mapcar (lambda (,a-sym)
                        (multiple-value-bind (,v-sym ,r-sym)
                            (eval-expr ,a-sym ,env)
                          (cons ,v-sym ,r-sym)))
                      ,args-var))
            (,ok-sym  (every #'cdr ,vals-sym))
            (,resolved-var (mapcar #'car ,vals-sym))
            (,all-resolved-var ,ok-sym))
       ,@body)))


;;; --------------------------------------------------------------------------
;;;  Évaluateur principal
;;; --------------------------------------------------------------------------

;;; eval-expr et eval-compound se rappellent mutuellement.
;;; On déclare eval-compound en avance pour supprimer le style-warning.
(declaim (ftype (function (t t) (values t t)) eval-compound))

(defun eval-expr (expr env)
  "Évalue EXPR dans l'environnement ENV.
   Retourne (values VALEUR RESOLVEDP).
   RESOLVEDP = NIL signifie forward-ref non encore disponible (pass 1).
   En pass 2, toute référence indéfinie déclenche une condition."
  (cond

    ;; --- Littéral entier ---
    ((integerp expr)
     (values expr t))

    ;; --- Littéral caractère → code ASCII ---
    ((characterp expr)
     (values (char-code expr) t))

    ;; --- Référence a un symbole (string) ---
    ((stringp expr)
     (let ((st (env-symbol-table env)))
       (if st
           (cl-asm/symbol-table:resolve-symbol
            st expr :source-loc (env-source-loc env))
           ;; Pas de table fournie → non résolu silencieusement
           (values :unresolved nil))))

    ;; --- PC courant ---
    ((eq expr :*)
     (values (env-pc env) t))

    ;; --- Nœud d'expression composée (liste préfixée) ---
    ((listp expr)
     (eval-compound expr env))

    (t
     (error 'expression-error
            :message    (format nil "Forme d'expression invalide : ~S" expr)
            :source-loc (env-source-loc env)))))


(defun eval-compound (expr env)
  "Évalue un nœud composé (OP ARG…)."
  (unless (and (listp expr) (keywordp (first expr)))
    (error 'expression-error
           :message    (format nil "Nœud composé invalide : ~S" expr)
           :source-loc (env-source-loc env)))
  (let ((op   (first  expr))
        (args (rest   expr)))
    (case op

      ;; ----------------------------------------------------------------
      ;;  Arithmétique binaire
      ;; ----------------------------------------------------------------

      (:+
       (check-arity-min op args 1)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (apply #'+ vals) t)
             (values :unresolved nil))))

      (:-
       (check-arity-min op args 1)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (if (= 1 (length vals))
                         (- (first vals))      ; unaire : (:- x) = -x
                         (apply #'- vals))     ; binaire : (:- a b) = a-b
                     t)
             (values :unresolved nil))))

      (:*
       (check-arity-min op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (apply #'* vals) t)
             (values :unresolved nil))))

      (:/
       (check-arity op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (let ((divisor (second vals)))
               (when (zerop divisor)
                 (error 'division-by-zero-error
                        :message    "Division par zéro"
                        :source-loc (env-source-loc env)))
               (values (truncate (first vals) divisor) t))
             (values :unresolved nil))))

      (:mod
       (check-arity op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (let ((divisor (second vals)))
               (when (zerop divisor)
                 (error 'division-by-zero-error
                        :message    "Modulo par zéro"
                        :source-loc (env-source-loc env)))
               (values (mod (first vals) divisor) t))
             (values :unresolved nil))))

      ;; ----------------------------------------------------------------
      ;;  Opérateurs bit-à-bit
      ;; ----------------------------------------------------------------

      (:&
       (check-arity-min op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (apply #'logand vals) t)
             (values :unresolved nil))))

      (:bitor
       (check-arity-min op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (apply #'logior vals) t)
             (values :unresolved nil))))

      (:^
       (check-arity-min op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (apply #'logxor vals) t)
             (values :unresolved nil))))

      (:~
       (check-arity op args 1)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (lognot (first vals)) t)
             (values :unresolved nil))))

      ;; ----------------------------------------------------------------
      ;;  Décalages
      ;; ----------------------------------------------------------------

      (:>>
       (check-arity op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (ash (first vals) (- (second vals))) t)
             (values :unresolved nil))))

      (:<<
       (check-arity op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (ash (first vals) (second vals)) t)
             (values :unresolved nil))))

      ;; ----------------------------------------------------------------
      ;;  Extraction d'octets (très utilisé en assembleur 8/16-bit)
      ;; ----------------------------------------------------------------

      ;; Octet bas (bits 0-7)  - synonymes < et :lo
      (:lo
       (check-arity op args 1)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (ldb (byte 8 0) (first vals)) t)
             (values :unresolved nil))))

      ;; Octet haut (bits 8-15)  - synonymes > et :hi
      (:hi
       (check-arity op args 1)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (ldb (byte 8 8) (first vals)) t)
             (values :unresolved nil))))

      ;; Octet de banque (bits 16-23) - 45GS02 / 65816
      (:bank
       (check-arity op args 1)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (ldb (byte 8 16) (first vals)) t)
             (values :unresolved nil))))

      ;; Octet le plus haut (bits 24-31) - 65816 / futur
      (:highest
       (check-arity op args 1)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (ldb (byte 8 24) (first vals)) t)
             (values :unresolved nil))))

      ;; Mot bas (bits 0-15)
      (:word
       (check-arity op args 1)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (ldb (byte 16 0) (first vals)) t)
             (values :unresolved nil))))

      ;; ----------------------------------------------------------------
      ;;  Opérateurs de comparaison (retournent 0 ou 1, utiles dans .if)
      ;; ----------------------------------------------------------------

      (:=
       (check-arity op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (if (= (first vals) (second vals)) 1 0) t)
             (values :unresolved nil))))

      (:/=
       (check-arity op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (if (/= (first vals) (second vals)) 1 0) t)
             (values :unresolved nil))))

      (:<
       (check-arity op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (if (< (first vals) (second vals)) 1 0) t)
             (values :unresolved nil))))

      (:<=
       (check-arity op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (if (<= (first vals) (second vals)) 1 0) t)
             (values :unresolved nil))))

      (:>
       (check-arity op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (if (> (first vals) (second vals)) 1 0) t)
             (values :unresolved nil))))

      (:>=
       (check-arity op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (if (>= (first vals) (second vals)) 1 0) t)
             (values :unresolved nil))))

      ;; ----------------------------------------------------------------
      ;;  Opérateurs logiques (sur des valeurs booléennes 0/1)
      ;; ----------------------------------------------------------------

      (:and
       (check-arity op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (if (and (not (zerop (first vals)))
                              (not (zerop (second vals)))) 1 0) t)
             (values :unresolved nil))))

      (:or
       (check-arity op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (if (or (not (zerop (first vals)))
                             (not (zerop (second vals)))) 1 0) t)
             (values :unresolved nil))))

      (:not
       (check-arity op args 1)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (if (zerop (first vals)) 1 0) t)
             (values :unresolved nil))))

      ;; ----------------------------------------------------------------
      ;;  Opérateurs spéciaux
      ;; ----------------------------------------------------------------

      ;; Négation arithmétique unaire (alias de (:- x))
      (:neg
       (check-arity op args 1)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (- (first vals)) t)
             (values :unresolved nil))))

      ;; PC courant (forme alternative a :*)
      (:current-pc
       (check-arity op args 0)
       (values (env-pc env) t))

      ;; Test de définition d'un symbole (utile pour .ifdef)
      (:defined
       (check-arity op args 1)
       (let ((sym (first args)))
         (unless (stringp sym)
           (error 'expression-error
                  :message    (format nil ":defined attend un nom de symbole (string), reçu ~S" sym)
                  :source-loc (env-source-loc env)))
         (let ((st (env-symbol-table env)))
           (if st
               (values (if (cl-asm/symbol-table:symbol-defined-p st sym) 1 0) t)
               (values 0 t)))))

      ;; Expression conditionnelle ternaire : (:if TEST THEN ELSE)
      (:if
       (check-arity op args 3)
       (multiple-value-bind (test-val test-ok)
           (eval-expr (first args) env)
         (if (not test-ok)
             (values :unresolved nil)
             (eval-expr (if (not (zerop test-val))
                            (second args)
                            (third  args))
                        env))))

      ;; Valeur absolue
      (:abs
       (check-arity op args 1)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (abs (first vals)) t)
             (values :unresolved nil))))

      ;; Min / Max
      (:min
       (check-arity-min op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (apply #'min vals) t)
             (values :unresolved nil))))

      (:max
       (check-arity-min op args 2)
       (with-resolved-args (args env vals all-ok)
         (if all-ok
             (values (apply #'max vals) t)
             (values :unresolved nil))))

      ;; ----------------------------------------------------------------
      ;;  Opérateur inconnu
      ;; ----------------------------------------------------------------
      (otherwise
       (error 'unknown-operator-error
              :operator   op
              :message    (format nil "Opérateur d'expression inconnu : ~S" op)
              :source-loc (env-source-loc env))))))


;;; --------------------------------------------------------------------------
;;;  Helpers publics
;;; --------------------------------------------------------------------------

(defun eval-expr/integer (expr env &key (bits 16) (signed nil))
  "Évalue EXPR et vérifie que le résultat tient dans BITS bits.
   Retourne (values ENTIER RESOLVEDP).
   Si RESOLVEDP est NIL (forward-ref en pass 1), retourne (values 0 NIL)
   sans vérifier la plage - la vérification est faite en pass 2."
  (multiple-value-bind (val resolvedp)
      (eval-expr expr env)
    (if (not resolvedp)
        (values 0 nil)
        (let* ((lo (if signed (- (expt 2 (1- bits))) 0))
               (hi (if signed (1- (expt 2 (1- bits))) (1- (expt 2 bits)))))
          (unless (<= lo val hi)
            (error 'cl-asm/ir:asm-range-error
                   :value   val
                   :bits    bits
                   :message (format nil "Valeur ~D hors plage [~D, ~D] (~D bits~A)"
                                    val lo hi bits (if signed " signé" ""))
                   :source-loc (env-source-loc env)))
          (values val t)))))

(defun eval-expr/byte (expr env)
  "Évalue EXPR et vérifie qu'elle tient dans un octet non signé [0, 255]."
  (eval-expr/integer expr env :bits 8 :signed nil))

(defun eval-expr/sbyte (expr env)
  "Évalue EXPR et vérifie qu'elle tient dans un octet signé [-128, 127]."
  (eval-expr/integer expr env :bits 8 :signed t))

(defun eval-expr/word (expr env)
  "Évalue EXPR et vérifie qu'elle tient dans un mot 16 bits [0, 65535]."
  (eval-expr/integer expr env :bits 16 :signed nil))

(defun eval-expr/dword (expr env)
  "Évalue EXPR et vérifie qu'elle tient dans 32 bits [0, 4294967295]."
  (eval-expr/integer expr env :bits 32 :signed nil))

(defun make-env (&key symbol-table source-loc (pc 0))
  "Construit un environnement d'évaluation."
  (list :symbol-table symbol-table
        :source-loc   source-loc
        :pc           pc))

(defun constant-expr-p (expr)
  "Vrai si EXPR peut être déterminée sans table de symboles
   (aucune référence a des labels)."
  (cond
    ((integerp   expr) t)
    ((characterp expr) t)
    ((eq expr :*)      nil)   ; dépend du PC
    ((stringp    expr) nil)   ; référence a un label
    ((listp      expr)
     (let ((op   (first expr))
           (args (rest  expr)))
       (case op
         ((:defined :current-pc) nil)
         (otherwise (every #'constant-expr-p args)))))
    (t nil)))
