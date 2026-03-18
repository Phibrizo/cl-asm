; -*- coding: utf-8 -*-
;;; tests/test-parser.lisp

(defpackage #:cl-asm/test.parser
  (:use #:cl #:cl-asm/parser #:cl-asm/ir)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.parser)


;;; --------------------------------------------------------------------------
;;;  Infra de test
;;; --------------------------------------------------------------------------

(defvar *pass* 0)
(defvar *fail* 0)
(defvar *failures* '())

(defmacro check (description form)
  `(let ((result (handler-case ,form
                   (error (e)
                     (format t "~&  ERREUR inattendue dans «~A» : ~A~%"
                             ,description e)
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
         (format t "~&  ERREUR inattendue dans «~A» : ~A~%" ,description e)))
     (if fired
         (progn (incf *pass*)
                (format t "~&  OK  ~A (erreur attendue)~%" ,description))
         (progn (incf *fail*)
                (push ,description *failures*)
                (format t "~&  KO  ~A (erreur NON declenchee)~%" ,description)))))

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&~%[~A]~%" ',name)
     ,@body))


;;; --------------------------------------------------------------------------
;;;  Helpers
;;; --------------------------------------------------------------------------

(defun parse (source)
  "Parse SOURCE et retourne le IR-PROGRAM."
  (parse-string source))

(defun nodes (source)
  "Retourne les noeuds de la section :text."
  (let ((prog (parse source)))
    (ir-section-nodes
     (program-find-section prog :text))))

(defun first-node (source)
  (first (nodes source)))

(defun instr (source)
  "Parse SOURCE et retourne la premiere instruction."
  (let ((n (first-node source)))
    (unless (ir-instruction-p n)
      (error "Pas une instruction : ~S" n))
    n))

(defun operand (source)
  "Retourne le premier operande de la premiere instruction."
  (first (ir-instruction-operands (instr source))))

(defun directive (source)
  "Parse SOURCE et retourne la premiere directive."
  (let ((n (first-node source)))
    (unless (ir-directive-p n)
      (error "Pas une directive : ~S" n))
    n))

(defun label-node (source)
  "Parse SOURCE et retourne le premier label."
  (let ((n (first-node source)))
    (unless (ir-label-p n)
      (error "Pas un label : ~S" n))
    n))


;;; --------------------------------------------------------------------------
;;;  Tests : instructions simples
;;; --------------------------------------------------------------------------

(deftest test/instr-implied
  ;; NOP — aucun operande
  (let ((i (instr "NOP")))
    (check "mnemonic NOP"   (string= "NOP" (ir-instruction-mnemonic i)))
    (check "0 operandes"    (null (ir-instruction-operands i)))))

(deftest test/instr-accumulator
  ;; LSR A — operande registre A
  (let ((op (operand "LSR A")))
    (check "kind = :register"  (eq :register (ir-operand-kind op)))
    (check "value = \"A\""     (string= "A" (ir-operand-value op)))))

(deftest test/instr-immediate
  ;; LDA #$FF
  (let ((op (operand "LDA #$FF")))
    (check "kind = :immediate" (eq :immediate (ir-operand-kind op)))
    (check "value = 255"       (= 255 (ir-operand-value op)))))

(deftest test/instr-immediate-expr
  ;; LDA #<HANDLER
  (let ((op (operand "LDA #<HANDLER")))
    (check "kind = :immediate" (eq :immediate (ir-operand-kind op)))
    (check "value = (:lo ...)" (equal '(:lo "HANDLER") (ir-operand-value op)))))

(deftest test/instr-direct
  ;; STA $0400
  (let ((op (operand "STA $0400")))
    (check "kind = :direct"   (eq :direct (ir-operand-kind op)))
    (check "value = #x0400"   (= #x0400 (ir-operand-value op)))))

(deftest test/instr-direct-x
  ;; STA $0400,X
  (let ((op (operand "STA $0400,X")))
    (check "kind = :direct"     (eq :direct (ir-operand-kind op)))
    (check "index-reg = :x"     (eq :x (ir-operand-index-reg op)))
    (check "value = #x0400"     (= #x0400 (ir-operand-value op)))))

(deftest test/instr-direct-y
  ;; LDA $B2,Y
  (let ((op (operand "LDA $B2,Y")))
    (check "kind = :direct"    (eq :direct (ir-operand-kind op)))
    (check "index-reg = :y"    (eq :y (ir-operand-index-reg op)))))

(deftest test/instr-indirect
  ;; JMP ($FFFC)
  (let ((op (operand "JMP ($FFFC)")))
    (check "kind = :indirect"  (eq :indirect (ir-operand-kind op)))
    (check "value = #xFFFC"    (= #xFFFC (ir-operand-value op)))))

(deftest test/instr-indirect-x
  ;; LDA ($00,X)
  (let ((op (operand "LDA ($00,X)")))
    (check "kind = :indirect-x"  (eq :indirect-x (ir-operand-kind op)))
    (check "value = 0"           (= 0 (ir-operand-value op)))
    (check "index-reg = :x"      (eq :x (ir-operand-index-reg op)))))

(deftest test/instr-indirect-y
  ;; STA ($B0),Y
  (let ((op (operand "STA ($B0),Y")))
    (check "kind = :indirect-y"  (eq :indirect-y (ir-operand-kind op)))
    (check "value = #xB0"        (= #xB0 (ir-operand-value op)))
    (check "index-reg = :y"      (eq :y (ir-operand-index-reg op)))))


;;; --------------------------------------------------------------------------
;;;  Tests : labels
;;; --------------------------------------------------------------------------

(deftest test/label-local
  (let ((nd (nodes "loop:")))
    (check "1 noeud"          (= 1 (length nd)))
    (check "label node"       (ir-label-p (first nd)))
    (check "name = LOOP"      (string= "LOOP" (ir-label-name (first nd))))
    (check "kind = :local"    (eq :local (ir-label-kind (first nd))))))

(deftest test/label-global
  (let ((nd (nodes "main::")))
    (check "label global"     (ir-label-p (first nd)))
    (check "kind = :global"   (eq :global (ir-label-kind (first nd))))
    (check "name = MAIN"      (string= "MAIN" (ir-label-name (first nd))))))

(deftest test/numeric-label
  (let ((nd (nodes "1:")))
    (check "numeric label"    (ir-label-p (first nd)))
    (check "kind = :numeric"  (eq :numeric (ir-label-kind (first nd))))
    (check "number = 1"       (= 1 (ir-label-number (first nd))))))

(deftest test/label-then-instr
  ;; loop: DEX
  (let ((nd (nodes "loop: DEX")))
    (check "2 noeuds"         (= 2 (length nd)))
    (check "premier = label"  (ir-label-p (first nd)))
    (check "second = instr"   (ir-instruction-p (second nd)))
    (check "mnemonic = DEX"   (string= "DEX"
                                       (ir-instruction-mnemonic (second nd))))))

(deftest test/multiple-labels
  ;; Plusieurs labels sur des lignes successives
  (let ((nd (nodes (format nil "start:~%main:~%  NOP"))))
    (check "3 noeuds"         (= 3 (length nd)))
    (check "label start"      (string= "START" (ir-label-name (first nd))))
    (check "label main"       (string= "MAIN"  (ir-label-name (second nd))))
    (check "instr NOP"        (ir-instruction-p (third nd)))))


;;; --------------------------------------------------------------------------
;;;  Tests : directives
;;; --------------------------------------------------------------------------

(deftest test/directive-org
  (let ((d (directive ".org $0801")))
    (check "name = :org"    (eq :org (ir-directive-name d)))
    (check "arg = #x0801"   (= #x0801 (first (ir-directive-args d))))))

(deftest test/directive-byte
  (let ((d (directive ".byte $01, $02, $03")))
    (check "name = :byte"   (eq :byte (ir-directive-name d)))
    (check "3 args"         (= 3 (length (ir-directive-args d))))
    (check "arg1 = 1"       (= 1 (first  (ir-directive-args d))))
    (check "arg2 = 2"       (= 2 (second (ir-directive-args d))))
    (check "arg3 = 3"       (= 3 (third  (ir-directive-args d))))))

(deftest test/directive-word
  (let ((d (directive ".word $1234, $5678")))
    (check "name = :word"   (eq :word (ir-directive-name d)))
    (check "2 args"         (= 2 (length (ir-directive-args d))))
    (check "arg1 = #x1234"  (= #x1234 (first  (ir-directive-args d))))
    (check "arg2 = #x5678"  (= #x5678 (second (ir-directive-args d))))))

(deftest test/directive-equ
  ;; SCREEN = $0400
  (let ((nd (nodes "SCREEN = $0400")))
    (check "1 noeud"         (= 1 (length nd)))
    (check "directive :equ"  (eq :equ (ir-directive-name (first nd))))
    (check "nom = SCREEN"
           (string= "SCREEN" (first (ir-directive-args (first nd)))))
    (check "valeur = #x0400"
           (= #x0400 (second (ir-directive-args (first nd)))))))

(deftest test/directive-text
  (let ((d (directive ".text \"Hello\"")))
    (check "name = :text"   (eq :text (ir-directive-name d)))
    (check "arg = string"   (string= "Hello" (first (ir-directive-args d))))))


;;; --------------------------------------------------------------------------
;;;  Tests : expressions dans les operandes
;;; --------------------------------------------------------------------------

(deftest test/expr-arithmetic
  ;; LDA BASE+1
  (let ((op (operand "LDA BASE+1")))
    (check "kind = :direct"
           (eq :direct (ir-operand-kind op)))
    (check "value = (:+ BASE 1)"
           (equal '(:+ "BASE" 1) (ir-operand-value op)))))

(deftest test/expr-lo-hi
  ;; LDA #<VEC  -> (:lo "VEC")
  ;; LDA #>VEC  -> (:hi "VEC")
  (check ":lo"
         (equal '(:lo "VEC") (ir-operand-value (operand "LDA #<VEC"))))
  (check ":hi"
         (equal '(:hi "VEC") (ir-operand-value (operand "LDA #>VEC")))))

(deftest test/expr-complex
  ;; LDA #(BASE + OFFSET * 2)
  (let ((op (operand "LDA #(BASE + OFFSET * 2)")))
    (check "immediat"
           (eq :immediate (ir-operand-kind op)))
    (check "arbre (:+ BASE (:* OFFSET 2))"
           (equal '(:+ "BASE" (:* "OFFSET" 2))
                  (ir-operand-value op)))))

(deftest test/expr-pc-relative
  ;; BNE *-2  (branche vers PC-2)
  (let ((op (operand "BNE *-2")))
    (check "kind = :direct"
           (eq :direct (ir-operand-kind op)))
    (check "value = (:- :* 2)"
           (equal '(:- :* 2) (ir-operand-value op)))))


;;; --------------------------------------------------------------------------
;;;  Tests : programmes complets
;;; --------------------------------------------------------------------------

(deftest test/c64-basic-stub
  ;; Programme C64 minimal avec stub BASIC
  (let* ((src (format nil
                      ".org $0801~%~
                       .byte $0B,$08,$E2,$07,$9E,$32,$30,$36,$34,$00,$00,$00~%~
                       start:~%~
                       LDA #$00~%~
                       STA $D020~%~
                       RTS"))
         (nd (nodes src)))
    (check "noeud .org"    (eq :org  (ir-directive-name  (nth 0 nd))))
    (check "noeud .byte"   (eq :byte (ir-directive-name  (nth 1 nd))))
    (check "label start"   (string= "START" (ir-label-name (nth 2 nd))))
    (check "LDA"           (string= "LDA" (ir-instruction-mnemonic (nth 3 nd))))
    (check "STA"           (string= "STA" (ir-instruction-mnemonic (nth 4 nd))))
    (check "RTS"           (string= "RTS" (ir-instruction-mnemonic (nth 5 nd))))
    (check "6 noeuds"      (= 6 (length nd)))))

(deftest test/multiline-program
  ;; Programme avec plusieurs labels et instructions
  (let* ((src (format nil
                      "COLS = 40~%~
                       ROWS = 25~%~
                       screen:~%~
                       LDA #COLS~%~
                       STA $D020"))
         (nd (nodes src)))
    (check "5 noeuds"       (= 5 (length nd)))
    (check ".equ COLS"
           (and (eq :equ (ir-directive-name (nth 0 nd)))
                (string= "COLS" (first (ir-directive-args (nth 0 nd))))))
    (check ".equ ROWS"
           (and (eq :equ (ir-directive-name (nth 1 nd)))
                (string= "ROWS" (first (ir-directive-args (nth 1 nd))))))
    (check "label screen"
           (string= "SCREEN" (ir-label-name (nth 2 nd))))
    (check "LDA #COLS"
           (string= "LDA" (ir-instruction-mnemonic (nth 3 nd))))))

(deftest test/sections
  ;; Changement de section
  (let* ((prog (parse (format nil
                              ".section text~%~
                               NOP~%~
                               .section data~%~
                               .byte $FF")))
         (text (program-find-section prog :text))
         (data (program-find-section prog :data)))
    (check "section :text existe"  (not (null text)))
    (check "section :data existe"  (not (null data)))))

(deftest test/empty-program
  (let ((nd (nodes "")))
    (check "programme vide = 0 noeuds" (null nd))))

(deftest test/comments-ignored
  ;; Les commentaires ne produisent aucun noeud
  (let ((nd (nodes "; ceci est un commentaire")))
    (check "commentaire = 0 noeuds" (null nd))))


;;; --------------------------------------------------------------------------
;;;  Tests : erreurs de syntaxe
;;; --------------------------------------------------------------------------

(deftest test/error-unexpected-token
  (check-error "token inattendu -> asm-syntax-error"
               cl-asm/ir:asm-syntax-error
               (parse "123 LDA")))

(deftest test/error-missing-rparen
  (check-error "parenthese non fermee -> asm-syntax-error"
               cl-asm/ir:asm-syntax-error
               (parse "LDA ($00,X")))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests cl-asm/parser ===~%")
  (test/instr-implied)
  (test/instr-accumulator)
  (test/instr-immediate)
  (test/instr-immediate-expr)
  (test/instr-direct)
  (test/instr-direct-x)
  (test/instr-direct-y)
  (test/instr-indirect)
  (test/instr-indirect-x)
  (test/instr-indirect-y)
  (test/label-local)
  (test/label-global)
  (test/numeric-label)
  (test/label-then-instr)
  (test/multiple-labels)
  (test/directive-org)
  (test/directive-byte)
  (test/directive-word)
  (test/directive-equ)
  (test/directive-text)
  (test/expr-arithmetic)
  (test/expr-lo-hi)
  (test/expr-complex)
  (test/expr-pc-relative)
  (test/c64-basic-stub)
  (test/multiline-program)
  (test/sections)
  (test/empty-program)
  (test/comments-ignored)
  (test/error-unexpected-token)
  (test/error-missing-rparen)
  (when *failures*
    (format t "~&Echecs parser :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
