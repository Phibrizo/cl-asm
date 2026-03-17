; -*- coding: utf-8 -*-
;;; tests/test-expression.lisp
;;;
;;; Tests unitaires pour cl-asm/expression.
;;; Chargement :
;;;   sbcl --load bootstrap.lisp \
;;;        --load src/core/expression.lisp \
;;;        --load src/core/symbol-table.lisp \
;;;        --load tests/test-expression.lisp \
;;;        --eval "(cl-asm/test.expression:run-all-tests)" --quit

(defpackage #:cl-asm/test.expression
  (:use #:cl #:cl-asm/expression)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.expression)


;;; --------------------------------------------------------------------------
;;;  Infra de test (méme style que test-symbol-table)
;;; --------------------------------------------------------------------------

(defvar *pass* 0)
(defvar *fail* 0)
(defvar *failures* '())

(defmacro check (description form)
  `(let ((result (handler-case ,form
                   (error (e)
                     (format t "~&  ERREUR inattendue dans é~Aé : ~A~%" ,description e)
                     nil))))
     (if result
         (progn (incf *pass*) (format t "~&  OK  ~A~%" ,description))
         (progn (incf *fail*)
                (push ,description *failures*)
                (format t "~&  KO  ~A~%" ,description)))))

(defmacro check-error (description condition-type form)
  `(let ((fired nil))
     (handler-case ,form
       (,condition-type () (setf fired t))
       (error (e)
         (format t "~&  ERREUR inattendue dans é~Aé : ~A~%" ,description e)))
     (if fired
         (progn (incf *pass*) (format t "~&  OK  ~A (erreur attendue)~%" ,description))
         (progn (incf *fail*)
                (push ,description *failures*)
                (format t "~&  KO  ~A (erreur NON déclenchée)~%" ,description)))))

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&~%[~A]~%" ',name)
     ,@body))


;;; --------------------------------------------------------------------------
;;;  Helpers
;;; --------------------------------------------------------------------------

(defun ev (expr &key st (pc 0))
  "éévalue EXPR, retourne la valeur (ou :unresolved)."
  (multiple-value-bind (val resolvedp)
      (eval-expr expr (make-env :symbol-table st :pc pc))
    (if resolvedp val :unresolved)))

(defun evp (expr &key st (pc 0))
  "retourne resolvedp."
  (nth-value 1 (eval-expr expr (make-env :symbol-table st :pc pc))))

(defun make-st-with (&rest name-value-pairs)
  "Crée une table de symboles avec des constantes pré-définies.
   Appel : (make-st-with \"A\" 1 \"B\" 2)"
  (let ((st (cl-asm/symbol-table:make-symbol-table)))
    (loop :for (name val) :on name-value-pairs :by #'cddr
          :do (cl-asm/symbol-table:define-constant st name val))
    st))


;;; --------------------------------------------------------------------------
;;;  Tests : literaux
;;; --------------------------------------------------------------------------

(deftest test/literal-integer
  (check "entier positif"     (= 42    (ev 42)))
  (check "zéro"               (= 0     (ev 0)))
  (check "entier negatif"     (= -1    (ev -1)))
  (check "grand entier"       (= #xFFFF (ev #xFFFF)))
  (check "resolvedp = t"      (evp 42)))

(deftest test/literal-character
  (check "char A = 65"  (= 65  (ev #\A)))
  (check "char NUL = 0" (= 0   (ev #\Nul)))
  (check "char espace"  (= 32  (ev #\Space))))

(deftest test/current-pc
  (check "PC via :*"          (= #x0810 (ev :* :pc #x0810)))
  (check "PC via :current-pc" (= #x1000 (ev '(:current-pc) :pc #x1000)))
  (check "PC = 0 par défaut"  (= 0      (ev :*))))


;;; --------------------------------------------------------------------------
;;;  Tests : références à des symboles
;;; --------------------------------------------------------------------------

(deftest test/symbol-ref-resolved
  (let ((st (make-st-with "BASE" #x8000 "COLS" 40)))
    (check "BASE résolu"  (= #x8000 (ev "BASE" :st st)))
    (check "COLS résolu"  (= 40     (ev "COLS" :st st)))))

(deftest test/symbol-ref-unresolved-pass1
  ;; Sans table, les symboles restent non résolus silencieusement
  (check "symbole sans table → :unresolved"
         (eq :unresolved (ev "GHOST")))
  (check "resolvedp = nil sans table"
         (not (evp "GHOST"))))

(deftest test/symbol-ref-undefined-pass2
  ;; En pass 2, un symbole inconnu doit déclencher une erreur
  (let ((st (cl-asm/symbol-table:make-symbol-table)))
    (setf (cl-asm/symbol-table:st-current-pass st) 2)
    (check-error "symbole indéfini en pass 2 → asm-undefined-label"
                 cl-asm/ir:asm-undefined-label
                 (ev "NOPE" :st st))))


;;; --------------------------------------------------------------------------
;;;  Tests : arithmétique binaire
;;; --------------------------------------------------------------------------

(deftest test/addition
  (check "2 + 3 = 5"             (= 5    (ev '(:+ 2 3))))
  (check "BASE + 16"             (= #x8010 (ev `(:+ #x8000 16))))
  (check "addition multiple"     (= 10   (ev '(:+ 1 2 3 4))))
  (check "addition avec symbole" (= #x8010
                                   (ev '(:+ "BASE" 16)
                                       :st (make-st-with "BASE" #x8000)))))

(deftest test/soustraction
  (check "5 - 3 = 2"          (= 2   (ev '(:- 5 3))))
  (check "unaire : (:- 7) = -7" (= -7 (ev '(:- 7))))
  (check "chaéne : 10 - 3 - 2" (= 5  (ev '(:- 10 3 2)))))

(deftest test/multiplication
  (check "3 * 4 = 12"         (= 12  (ev '(:* 3 4))))
  (check "multiple : 2*3*4"   (= 24  (ev '(:* 2 3 4)))))

(deftest test/division
  (check "10 / 3 = 3 (tronqué)" (= 3  (ev '(:/ 10 3))))
  (check "12 / 4 = 3"           (= 3  (ev '(:/ 12 4))))
  (check "-7 / 2 = -3"          (= -3 (ev '(:/ -7 2)))))

(deftest test/division-by-zero
  (check-error "division par zéro → division-by-zéro-error"
               division-by-zero-error
               (ev '(:/ 10 0)))
  (check-error "modulo par zéro → division-by-zéro-error"
               division-by-zero-error
               (ev '(:mod 10 0))))

(deftest test/modulo
  (check "10 mod 3 = 1" (= 1 (ev '(:mod 10 3))))
  (check "8 mod 4 = 0"  (= 0 (ev '(:mod 8 4)))))


;;; --------------------------------------------------------------------------
;;;  Tests : opérateurs bit-à-bit
;;; --------------------------------------------------------------------------

(deftest test/bitwise-and
  (check "#xFF & #x0F = #x0F" (= #x0F (ev '(:& #xFF #x0F))))
  (check "#xAA & #x55 = 0"    (= 0    (ev '(:& #xAA #x55)))))

(deftest test/bitwise-or
  (check "#xF0 | #x0F = #xFF" (= #xFF (ev '(:bitor #xF0 #x0F))))
  (check "0 | 0 = 0"          (= 0    (ev '(:bitor 0 0)))))

(deftest test/bitwise-xor
  (check "#xFF ^ #xFF = 0"    (= 0    (ev '(:^ #xFF #xFF))))
  (check "#xAA ^ #x55 = #xFF" (= #xFF (ev '(:^ #xAA #x55)))))

(deftest test/bitwise-not
  ;; lognot en CL = complément à 2 sur entier non borné → résultat negatif
  (check "~0 = -1"    (= -1  (ev '(:~ 0))))
  (check "~(-1) = 0"  (= 0   (ev '(:~ -1))))
  ;; En pratique on applique ensuite un masque
  (check "(~#x00) & #xFF = #xFF"
         (= #xFF (ev '(:& (:~ 0) #xFF)))))


;;; --------------------------------------------------------------------------
;;;  Tests : décalages
;;; --------------------------------------------------------------------------

(deftest test/shift-right
  (check "8 >> 1 = 4"   (= 4   (ev '(:>> 8 1))))
  (check "256 >> 4 = 16" (= 16  (ev '(:>> 256 4))))
  (check "1 >> 0 = 1"   (= 1   (ev '(:>> 1 0)))))

(deftest test/shift-left
  (check "1 << 8 = 256" (= 256 (ev '(:<< 1 8))))
  (check "3 << 2 = 12"  (= 12  (ev '(:<< 3 2)))))


;;; --------------------------------------------------------------------------
;;;  Tests : extraction d'octets (céur de l'assembleur 8-bit)
;;; --------------------------------------------------------------------------

(deftest test/lo-hi
  (check ":lo de #x1234 = #x34" (= #x34 (ev '(:lo #x1234))))
  (check ":hi de #x1234 = #x12" (= #x12 (ev '(:hi #x1234))))
  (check ":lo de 0 = 0"         (= 0    (ev '(:lo 0))))
  (check ":hi de #x00FF = 0"    (= 0    (ev '(:hi #x00FF))))
  (check ":hi de #xFF00 = #xFF" (= #xFF (ev '(:hi #xFF00)))))

(deftest test/bank
  (check ":bank de #x123456 = #x12" (= #x12 (ev '(:bank #x123456))))
  (check ":bank de #x001234 = 0"    (= 0    (ev '(:bank #x001234)))))

(deftest test/word
  (check ":word de #x12345678 = #x5678" (= #x5678 (ev '(:word #x12345678))))
  (check ":word de #xFFFF     = #xFFFF" (= #xFFFF  (ev '(:word #xFFFF)))))

(deftest test/lo-hi-with-symbol
  (let ((st (make-st-with "VEC" #xC000)))
    (check ":lo de VEC = 0"    (= 0    (ev '(:lo "VEC") :st st)))
    (check ":hi de VEC = #xC0" (= #xC0 (ev '(:hi "VEC") :st st)))))


;;; --------------------------------------------------------------------------
;;;  Tests : comparaisons
;;; --------------------------------------------------------------------------

(deftest test/comparisons
  (check "1 = 1 → 1"   (= 1 (ev '(:= 1 1))))
  (check "1 = 2 → 0"   (= 0 (ev '(:= 1 2))))
  (check "1 /= 2 → 1"  (= 1 (ev '(:/= 1 2))))
  (check "2 > 1 → 1"   (= 1 (ev '(:> 2 1))))
  (check "1 > 2 → 0"   (= 0 (ev '(:> 1 2))))
  (check "1 < 2 → 1"   (= 1 (ev '(:< 1 2))))
  (check "2 <= 2 → 1"  (= 1 (ev '(:<= 2 2))))
  (check "3 ≥ 2 → 1"  (= 1 (ev '(:>= 3 2)))))


;;; --------------------------------------------------------------------------
;;;  Tests : opérateurs logiques
;;; --------------------------------------------------------------------------

(deftest test/logical
  (check "1 and 1 → 1" (= 1 (ev '(:and 1 1))))
  (check "1 and 0 → 0" (= 0 (ev '(:and 1 0))))
  (check "0 or  1 → 1" (= 1 (ev '(:or  0 1))))
  (check "0 or  0 → 0" (= 0 (ev '(:or  0 0))))
  (check "not 0 → 1"   (= 1 (ev '(:not 0))))
  (check "not 1 → 0"   (= 0 (ev '(:not 1))))
  (check "not 42 → 0"  (= 0 (ev '(:not 42)))))


;;; --------------------------------------------------------------------------
;;;  Tests : opérateurs spéciaux
;;; --------------------------------------------------------------------------

(deftest test/neg
  (check "neg 5 = -5"   (= -5  (ev '(:neg 5))))
  (check "neg -3 = 3"   (= 3   (ev '(:neg -3))))
  (check "neg 0 = 0"    (= 0   (ev '(:neg 0)))))

(deftest test/abs
  (check "abs  5 = 5"  (= 5 (ev '(:abs  5))))
  (check "abs -5 = 5"  (= 5 (ev '(:abs -5))))
  (check "abs  0 = 0"  (= 0 (ev '(:abs  0)))))

(deftest test/min-max
  (check "min 3 7 = 3"     (= 3 (ev '(:min 3 7))))
  (check "min 7 3 = 3"     (= 3 (ev '(:min 7 3))))
  (check "max 3 7 = 7"     (= 7 (ev '(:max 3 7))))
  (check "max 3 7 2 9 = 9" (= 9 (ev '(:max 3 7 2 9)))))

(deftest test/defined
  (let ((st (make-st-with "EXISTS" 1)))
    (check ":defined symbole existant → 1"
           (= 1 (ev '(:defined "EXISTS") :st st)))
    (check ":defined symbole absent → 0"
           (= 0 (ev '(:defined "NOPE") :st st)))))

(deftest test/if-expr
  (check "(:if 1 42 99) = 42"  (= 42 (ev '(:if 1 42 99))))
  (check "(:if 0 42 99) = 99"  (= 99 (ev '(:if 0 42 99))))
  (check "(:if (:> 3 2) 10 20) = 10"
         (= 10 (ev '(:if (:> 3 2) 10 20))))
  (check "(:if (:= 1 2) 10 20) = 20"
         (= 20 (ev '(:if (:= 1 2) 10 20)))))


;;; --------------------------------------------------------------------------
;;;  Tests : expressions imbriquées et complexes
;;; --------------------------------------------------------------------------

(deftest test/nested-expressions
  (check "(:+ (:* 2 3) (:- 10 4)) = 12"
         (= 12 (ev '(:+ (:* 2 3) (:- 10 4)))))
  (check "(:lo (:+ #x1200 #x34)) = #x34"
         (= #x34 (ev '(:lo (:+ #x1200 #x34)))))
  (check "(:hi (:+ #x1200 #x34)) = #x12"
         (= #x12 (ev '(:hi (:+ #x1200 #x34))))))

(deftest test/c64-typical-expressions
  ;; Patterns typiques en assembleur C64
  (let ((st (make-st-with "HANDLER" #xE000
                          "SCREEN"  #x0400
                          "BASE"    #x0800)))
    ;; Adresse basse / haute d'un vecteur
    (check "octet bas de HANDLER"
           (= #x00 (ev '(:lo "HANDLER") :st st)))
    (check "octet haut de HANDLER"
           (= #xE0 (ev '(:hi "HANDLER") :st st)))
    ;; Offset dans une page
    (check "SCREEN + 40 (ligne 2)"
           (= #x0428 (ev '(:+ "SCREEN" 40) :st st)))
    ;; Taille d'un bloc
    (check "HANDLER - BASE = taille du programme"
           (= (- #xE000 #x0800) (ev '(:- "HANDLER" "BASE") :st st)))))

(deftest test/pc-relative-expression
  ;; (:- "TARGET" :*) est le pattern classique pour un offset relatif
  (let ((st (make-st-with "TARGET" #x1050)))
    (check "TARGET - PC (offset relatif)"
           (= 16 (ev '(:- "TARGET" :*) :st st :pc #x1040)))))


;;; --------------------------------------------------------------------------
;;;  Tests : forward références dans les expressions
;;; --------------------------------------------------------------------------

(deftest test/expr-unresolved-propagates
  ;; Si un sous-arbre est non résolu, toute l'expression l'est
  (check "(:+ unresolved 1) → :unresolved"
         (eq :unresolved (ev '(:+ "FUTURE" 1))))
  (check "(:lo unresolved) → :unresolved"
         (eq :unresolved (ev '(:lo "FUTURE"))))
  (check "(:* 2 unresolved) → :unresolved"
         (eq :unresolved (ev '(:* 2 "FUTURE")))))

(deftest test/expr-partial-resolution
  ;; La partie résolue n'est pas ?evaluée partiellement - tout ou rien
  (let ((st (make-st-with "KNOWN" 10)))
    (check "(:+ KNOWN UNKNOWN) → :unresolved si UNKNOWN absent"
           (eq :unresolved (ev '(:+ "KNOWN" "UNKNOWN") :st st)))
    (check "(:+ KNOWN KNOWN) → 20 si les deux sont connus"
           (= 20 (ev '(:+ "KNOWN" "KNOWN") :st st)))))


;;; --------------------------------------------------------------------------
;;;  Tests : vérification de plage (eval-expr/integer & co)
;;; --------------------------------------------------------------------------

(deftest test/eval-byte-ok
  (let ((env (make-env)))
    (check "0 tient dans un byte"   (= 0   (eval-expr/byte 0   env)))
    (check "255 tient dans un byte" (= 255 (eval-expr/byte 255 env)))
    (check "128 tient dans un byte" (= 128 (eval-expr/byte 128 env)))))

(deftest test/eval-byte-overflow
  (let ((env (make-env)))
    (check-error "256 ne tient pas dans un byte → asm-range-error"
                 cl-asm/ir:asm-range-error
                 (eval-expr/byte 256 env))
    (check-error "-1 ne tient pas dans un byte non signé → asm-range-error"
                 cl-asm/ir:asm-range-error
                 (eval-expr/byte -1 env))))

(deftest test/eval-sbyte-ok
  (let ((env (make-env)))
    (check "-128 tient dans un sbyte" (= -128 (eval-expr/sbyte -128 env)))
    (check " 127 tient dans un sbyte" (= 127  (eval-expr/sbyte  127 env)))
    (check "   0 tient dans un sbyte" (= 0    (eval-expr/sbyte    0 env)))))

(deftest test/eval-sbyte-overflow
  (let ((env (make-env)))
    (check-error "128 ne tient pas dans un sbyte → asm-range-error"
                 cl-asm/ir:asm-range-error
                 (eval-expr/sbyte 128 env))
    (check-error "-129 ne tient pas dans un sbyte → asm-range-error"
                 cl-asm/ir:asm-range-error
                 (eval-expr/sbyte -129 env))))

(deftest test/eval-word-ok
  (let ((env (make-env)))
    (check "0 tient dans un word"      (= 0      (eval-expr/word 0      env)))
    (check "#xFFFF tient dans un word" (= #xFFFF (eval-expr/word #xFFFF env)))))

(deftest test/eval-word-overflow
  (let ((env (make-env)))
    (check-error "#x10000 ne tient pas dans un word → asm-range-error"
                 cl-asm/ir:asm-range-error
                 (eval-expr/word #x10000 env))))

(deftest test/eval-unresolved-no-range-check
  ;; En pass 1, un :unresolved ne doit pas déclencher de range-error
  (let ((env (make-env)))
    (check "forward ref → 0 sans range-error"
           (multiple-value-bind (val resolvedp)
               (eval-expr/byte '(:lo "FUTURE") env)
             (and (= 0 val) (not resolvedp))))))


;;; --------------------------------------------------------------------------
;;;  Tests : erreurs
;;; --------------------------------------------------------------------------

(deftest test/unknown-operator
  (check-error "opérateur inconnu → unknown-operator-error"
               unknown-operator-error
               (ev '(:plouf 1 2))))

(deftest test/wrong-arity
  (check-error ":lo avec 2 args → wrong-arity-error"
               wrong-arity-error
               (ev '(:lo 1 2)))
  (check-error ":/ avec 1 arg → wrong-arity-error"
               wrong-arity-error
               (ev '(:/ 10)))
  (check-error ":current-pc avec 1 arg → wrong-arity-error"
               wrong-arity-error
               (ev '(:current-pc 42))))

(deftest test/invalid-expr-form
  (check-error "forme invalide (vecteur) → expression-error"
               expression-error
               (ev #(1 2 3))))


;;; --------------------------------------------------------------------------
;;;  Tests : constant-expr-p
;;; --------------------------------------------------------------------------

(deftest test/constant-expr-p
  (check "entier → constant"         (constant-expr-p 42))
  (check "char → constant"           (constant-expr-p #\A))
  (check "string → pas constant"     (not (constant-expr-p "LABEL")))
  (check ":* → pas constant"         (not (constant-expr-p :*)))
  (check "(:+ 1 2) → constant"       (constant-expr-p '(:+ 1 2)))
  (check "(:+ 1 \"X\") → pas const"  (not (constant-expr-p '(:+ 1 "X"))))
  (check "(:lo 42) → constant"       (constant-expr-p '(:lo 42)))
  (check "(:defined \"X\") → pas constant" (not (constant-expr-p '(:defined "X"))))
  (check "(:current-pc) → pas constant"    (not (constant-expr-p '(:current-pc)))))


;;; --------------------------------------------------------------------------
;;;  Lanceur global
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests cl-asm/expression ===~%")
  (test/literal-integer)
  (test/literal-character)
  (test/current-pc)
  (test/symbol-ref-resolved)
  (test/symbol-ref-unresolved-pass1)
  (test/symbol-ref-undefined-pass2)
  (test/addition)
  (test/soustraction)
  (test/multiplication)
  (test/division)
  (test/division-by-zero)
  (test/modulo)
  (test/bitwise-and)
  (test/bitwise-or)
  (test/bitwise-xor)
  (test/bitwise-not)
  (test/shift-right)
  (test/shift-left)
  (test/lo-hi)
  (test/bank)
  (test/word)
  (test/lo-hi-with-symbol)
  (test/comparisons)
  (test/logical)
  (test/neg)
  (test/abs)
  (test/min-max)
  (test/defined)
  (test/if-expr)
  (test/nested-expressions)
  (test/c64-typical-expressions)
  (test/pc-relative-expression)
  (test/expr-unresolved-propagates)
  (test/expr-partial-resolution)
  (test/eval-byte-ok)
  (test/eval-byte-overflow)
  (test/eval-sbyte-ok)
  (test/eval-sbyte-overflow)
  (test/eval-word-ok)
  (test/eval-word-overflow)
  (test/eval-unresolved-no-range-check)
  (test/unknown-operator)
  (test/wrong-arity)
  (test/invalid-expr-form)
  (test/constant-expr-p)
  (when *failures*
    (format t "~&Échecs expression :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
