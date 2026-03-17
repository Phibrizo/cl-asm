; -*- coding: utf-8 -*-
;;; tests/test-macros.lisp

(defpackage #:cl-asm/test.macros
  (:use #:cl #:cl-asm/parser #:cl-asm/ir)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.macros)


;;; --------------------------------------------------------------------------
;;;  Infra de test
;;; --------------------------------------------------------------------------

(defvar *pass* 0)
(defvar *fail* 0)
(defvar *failures* '())

(defmacro check (description form)
  `(let ((result (handler-case ,form
                   (error (e)
                     (format t "~&  ERREUR inattendue dans [~A] : ~A~%"
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
         (format t "~&  ERREUR inattendue dans [~A] : ~A~%" ,description e)))
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
  (parse-string source))

(defun nodes (source)
  (ir-section-nodes
   (program-find-section (parse source) :text)))

(defun asm (source &key (origin #x0801))
  (cl-asm/backend.6502:assemble-string source :origin origin))

(defun bytes= (vec &rest expected)
  (and (= (length vec) (length expected))
       (every #'= vec expected)))


;;; --------------------------------------------------------------------------
;;;  Tests : definition de macros
;;; --------------------------------------------------------------------------

(deftest test/macro-def-enregistree
  ;; Une definition de macro ne produit aucun noeud IR
  (let ((nd (nodes (format nil
                           ".macro NOP2~%NOP~%NOP~%.endmacro"))))
    (check "definition seule = 0 noeuds" (null nd))))

(deftest test/macro-sans-params
  ;; Macro sans paramètres : NOP2 expande en NOP NOP
  (let ((nd (nodes (format nil
                           ".macro NOP2~%NOP~%NOP~%.endmacro~%NOP2"))))
    (check "2 noeuds apres expansion"  (= 2 (length nd)))
    (check "premier = NOP"
           (string= "NOP" (ir-instruction-mnemonic (first nd))))
    (check "second = NOP"
           (string= "NOP" (ir-instruction-mnemonic (second nd))))))

(deftest test/macro-expansion-binaire
  ;; NOP2 expande bien en 2 octets $EA $EA
  (let ((bytes (asm (format nil
                            ".macro NOP2~%NOP~%NOP~%.endmacro~%NOP2"))))
    (check "2 octets" (= 2 (length bytes)))
    (check "EA EA"    (bytes= bytes #xEA #xEA))))

(deftest test/macro-avec-un-param
  ;; Macro avec un paramètre
  (let ((bytes (asm (format nil
                            ".macro LDAI val~%LDA #val~%.endmacro~%LDAI $42"))))
    (check "LDA #$42 = A9 42"
           (bytes= bytes #xA9 #x42))))

(deftest test/macro-avec-deux-params
  ;; Macro STORE addr, val : LDA #val / STA addr
  ;; LDA #$00 = 2 octets, STA $D020 (absolu) = 3 octets → total 5
  (let ((bytes (asm (format nil
                            ".macro STORE addr, val~%~
                             LDA #val~%~
                             STA addr~%~
                             .endmacro~%~
                             STORE $D020, $00"))))
    (check "5 octets"          (= 5 (length bytes)))
    (check "LDA #$00 = A9 00"
           (and (= #xA9 (aref bytes 0)) (= #x00 (aref bytes 1))))
    (check "STA $D020 = 8D 20 D0"
           (and (= #x8D (aref bytes 2))
                (= #x20 (aref bytes 3))))))

(deftest test/macro-invoquee-plusieurs-fois
  ;; Deux invocations produisent deux expansions independantes
  (let ((bytes (asm (format nil
                            ".macro NOP2~%NOP~%NOP~%.endmacro~%~
                             NOP2~%NOP2"))))
    (check "4 octets"  (= 4 (length bytes)))
    (check "EA EA EA EA"
           (bytes= bytes #xEA #xEA #xEA #xEA))))

(deftest test/macro-push-axy
  ;; Macro classique : sauvegarde A, X, Y sur la pile
  ;; PHA($48) / TXA($8A) / PHA($48) / TYA($98) / PHA($48)
  (let* ((src (format nil
                      ".macro PUSH_AXY~%~
                       PHA~%TXA~%PHA~%TYA~%PHA~%~
                       .endmacro~%~
                       PUSH_AXY"))
         (bytes (asm src)))
    (check "5 octets"           (= 5 (length bytes)))
    (check "PHA = $48"          (= #x48 (aref bytes 0)))
    (check "TXA = $8A"          (= #x8A (aref bytes 1)))
    (check "PHA = $48"          (= #x48 (aref bytes 2)))
    (check "TYA = $98"          (= #x98 (aref bytes 3)))
    (check "PHA = $48"          (= #x48 (aref bytes 4)))))


;;; --------------------------------------------------------------------------
;;;  Tests : labels locaux dans les macros
;;; --------------------------------------------------------------------------

(deftest test/macro-labels-locaux-uniques
  ;; Les labels __NOM dans une macro sont rendus uniques à chaque invocation.
  ;; Deux invocations ne doivent pas provoquer de conflit de labels.
  (let* ((src (format nil
                      ".macro CLEAR_A~%~
                       LDA #$00~%~
                       BEQ __skip~%~
                       NOP~%~
                       __skip:~%~
                       .endmacro~%~
                       CLEAR_A~%~
                       CLEAR_A"))
         (nd (nodes src)))
    ;; Chaque invocation produit : LDA, BEQ, NOP, label = 4 noeuds x 2 = 8
    (check "8 noeuds (2 expansions x 4)"  (= 8 (length nd)))))

(deftest test/macro-label-unique-pas-conflit
  ;; Les deux invocations doivent s'assembler sans erreur de label dupliqué
  (let* ((src (format nil
                      ".macro DECLOOP cnt~%~
                       LDA cnt~%~
                       BEQ __done~%~
                       SEC~%~
                       SBC #1~%~
                       STA cnt~%~
                       BNE __done~%~
                       __done:~%~
                       .endmacro~%~
                       DECLOOP $10~%~
                       DECLOOP $20")))
    (check "pas d'erreur d'assemblage"
           (handler-case
               (progn (asm src) t)
             (error () nil)))))


;;; --------------------------------------------------------------------------
;;;  Tests : macros avec des constantes
;;; --------------------------------------------------------------------------

(deftest test/macro-avec-constante
  ;; Les constantes définies avant la macro sont visibles dans le corps
  (let ((bytes (asm (format nil
                            "NOIR = $00~%~
                             .macro BORDURE col~%~
                             LDA #col~%~
                             STA $D020~%~
                             .endmacro~%~
                             BORDURE NOIR"))))
    (check "LDA #$00"  (= #x00 (aref bytes 1)))))

(deftest test/macro-apres-instructions
  ;; Une macro peut être utilisée au milieu d'un programme
  (let* ((src (format nil
                      "CLC~%~
                       .macro INC_A~%~
                       CLC~%~
                       ADC #1~%~
                       .endmacro~%~
                       LDA #$00~%~
                       INC_A~%~
                       RTS"))
         (bytes (asm src)))
    ;; CLC(1) + LDA #$00(2) + CLC(1) + ADC #1(2) + RTS(1) = 7
    (check "7 octets"  (= 7 (length bytes)))
    (check "CLC = $18" (= #x18 (aref bytes 0)))
    (check "LDA = $A9" (= #xA9 (aref bytes 1)))
    (check "RTS = $60" (= #x60 (aref bytes 6)))))


;;; --------------------------------------------------------------------------
;;;  Tests : erreurs
;;; --------------------------------------------------------------------------

(deftest test/macro-mauvais-nb-args
  (check-error "trop d'arguments -> asm-syntax-error"
               cl-asm/ir:asm-syntax-error
               (asm (format nil
                            ".macro ADD1 val~%ADC #val~%.endmacro~%~
                             ADD1 $01, $02"))))

(deftest test/macro-non-fermee
  (check-error "macro non fermee -> asm-syntax-error"
               cl-asm/ir:asm-syntax-error
               (parse (format nil ".macro OOPS~%NOP~%"))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests cl-asm/macros ===~%")
  (test/macro-def-enregistree)
  (test/macro-sans-params)
  (test/macro-expansion-binaire)
  (test/macro-avec-un-param)
  (test/macro-avec-deux-params)
  (test/macro-invoquee-plusieurs-fois)
  (test/macro-push-axy)
  (test/macro-labels-locaux-uniques)
  (test/macro-label-unique-pas-conflit)
  (test/macro-avec-constante)
  (test/macro-apres-instructions)
  (test/macro-mauvais-nb-args)
  (test/macro-non-fermee)
  (when *failures*
    (format t "~&Echecs macros :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
