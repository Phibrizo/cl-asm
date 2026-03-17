; -*- coding: utf-8 -*-
;;; tests/test-conditional.lisp

(defpackage #:cl-asm/test.conditional
  (:use #:cl #:cl-asm/parser #:cl-asm/ir)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.conditional)


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

(defun asm (source &key (origin #x0801))
  (cl-asm/backend.6502:assemble-string source :origin origin))

(defun nodes (source)
  (ir-section-nodes
   (program-find-section (parse-string source) :text)))

(defun bytes= (vec &rest expected)
  (and (= (length vec) (length expected))
       (every #'= vec expected)))


;;; --------------------------------------------------------------------------
;;;  Tests : condition vraie
;;; --------------------------------------------------------------------------

(deftest test/if-vrai-simple
  ;; .if 1 → bloc inclus
  (let ((nd (nodes (format nil ".if 1~%NOP~%.endif"))))
    (check "1 noeud"    (= 1 (length nd)))
    (check "NOP inclus" (string= "NOP"
                                  (ir-instruction-mnemonic (first nd))))))

(deftest test/if-vrai-binaire
  (let ((bytes (asm (format nil ".if 1~%NOP~%.endif"))))
    (check "NOP = EA"   (bytes= bytes #xEA))))

(deftest test/if-expression-vraie
  ;; .if avec une expression arithmétique
  (let ((bytes (asm (format nil ".if 2+2~%NOP~%.endif"))))
    (check "expression vraie → NOP" (bytes= bytes #xEA))))

(deftest test/if-constante-vraie
  ;; .if avec une constante définie avant
  (let ((bytes (asm (format nil "DEBUG = 1~%.if DEBUG~%NOP~%.endif"))))
    (check "constante vraie → NOP" (bytes= bytes #xEA))))


;;; --------------------------------------------------------------------------
;;;  Tests : condition fausse
;;; --------------------------------------------------------------------------

(deftest test/if-faux-simple
  ;; .if 0 → bloc ignoré
  (let ((nd (nodes (format nil ".if 0~%NOP~%.endif"))))
    (check "0 noeuds"   (null nd))))

(deftest test/if-faux-binaire
  (let ((bytes (asm (format nil ".if 0~%NOP~%.endif"))))
    (check "rien emis"  (= 0 (length bytes)))))

(deftest test/if-constante-fausse
  (let ((bytes (asm (format nil "DEBUG = 0~%.if DEBUG~%NOP~%.endif"))))
    (check "constante fausse → rien" (= 0 (length bytes)))))


;;; --------------------------------------------------------------------------
;;;  Tests : .if / .else / .endif
;;; --------------------------------------------------------------------------

(deftest test/if-else-vrai
  ;; Condition vraie → bloc .if, pas .else
  (let ((bytes (asm (format nil
                            ".if 1~%LDA #$01~%.else~%LDA #$02~%.endif"))))
    (check "LDA #$01 emis" (and (= #xA9 (aref bytes 0))
                                 (= #x01 (aref bytes 1))))
    (check "2 octets seulement" (= 2 (length bytes)))))

(deftest test/if-else-faux
  ;; Condition fausse → bloc .else
  (let ((bytes (asm (format nil
                            ".if 0~%LDA #$01~%.else~%LDA #$02~%.endif"))))
    (check "LDA #$02 emis" (and (= #xA9 (aref bytes 0))
                                 (= #x02 (aref bytes 1))))
    (check "2 octets seulement" (= 2 (length bytes)))))

(deftest test/if-else-choix-plateforme
  ;; Cas d'usage typique : sélection selon une constante
  (let* ((src "PLATFORM = 64
.if PLATFORM = 64
LDA #$01
.else
LDA #$02
.endif")
         (bytes (asm src)))
    (check "plateforme 64 → LDA #$01"
           (= #x01 (aref bytes 1)))))


;;; --------------------------------------------------------------------------
;;;  Tests : imbrication
;;; --------------------------------------------------------------------------

(deftest test/if-imbrique-vv
  ;; Deux conditions vraies imbriquées
  (let ((bytes (asm (format nil
                            ".if 1~%.if 1~%NOP~%.endif~%.endif"))))
    (check "NOP emis" (bytes= bytes #xEA))))

(deftest test/if-imbrique-vf
  ;; Externe vraie, interne fausse
  (let ((bytes (asm (format nil
                            ".if 1~%.if 0~%NOP~%.endif~%SEC~%.endif"))))
    (check "SEC emis, pas NOP" (bytes= bytes #x38))))

(deftest test/if-imbrique-fv
  ;; Externe fausse → tout le bloc ignoré y compris le .if interne
  (let ((bytes (asm (format nil
                            ".if 0~%.if 1~%NOP~%.endif~%.endif"))))
    (check "rien emis" (= 0 (length bytes)))))

(deftest test/if-imbrique-avec-else
  ;; Imbrication avec .else à chaque niveau
  (let* ((src ".if 1
  .if 0
    LDA #$01
  .else
    LDA #$02
  .endif
.else
  LDA #$03
.endif")
         (bytes (asm src)))
    (check "LDA #$02 (if-vrai / else-interne)"
           (= #x02 (aref bytes 1)))))


;;; --------------------------------------------------------------------------
;;;  Tests : bloc multi-lignes
;;; --------------------------------------------------------------------------

(deftest test/if-bloc-multi-lignes
  ;; Plusieurs instructions dans le bloc
  (let* ((src ".if 1
CLC
LDA #$00
STA $D020
.endif")
         (bytes (asm src)))
    ;; CLC(1) + LDA #$00(2) + STA $D020(3) = 6
    (check "6 octets" (= 6 (length bytes)))
    (check "CLC = $18" (= #x18 (aref bytes 0)))
    (check "LDA = $A9" (= #xA9 (aref bytes 1)))))

(deftest test/if-avec-labels
  ;; Les labels dans un bloc conditionnel sont bien definis
  (let* ((src ".if 1
target:
  NOP
.endif
  JMP target")
         (bytes (asm src)))
    ;; NOP($EA) + JMP target($4C $01 $08) = 4 octets
    (check "4 octets"  (= 4 (length bytes)))
    (check "NOP = EA"  (= #xEA (aref bytes 0)))
    (check "JMP = 4C"  (= #x4C (aref bytes 1)))))

(deftest test/if-avec-macro
  ;; .if et .macro peuvent coexister
  (let* ((src ".macro NOP2
NOP
NOP
.endmacro
.if 1
  NOP2
.endif")
         (bytes (asm src)))
    (check "EA EA" (bytes= bytes #xEA #xEA))))


;;; --------------------------------------------------------------------------
;;;  Tests : erreurs
;;; --------------------------------------------------------------------------

(deftest test/if-non-ferme
  (check-error ".if sans .endif -> asm-syntax-error"
               cl-asm/ir:asm-syntax-error
               (parse-string (format nil ".if 1~%NOP~%"))))

(deftest test/else-sans-if
  (check-error ".else sans .if -> asm-syntax-error"
               cl-asm/ir:asm-syntax-error
               (parse-string ".else")))

(deftest test/endif-sans-if
  (check-error ".endif sans .if -> asm-syntax-error"
               cl-asm/ir:asm-syntax-error
               (parse-string ".endif")))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests cl-asm/conditionnel ===~%")
  (test/if-vrai-simple)
  (test/if-vrai-binaire)
  (test/if-expression-vraie)
  (test/if-constante-vraie)
  (test/if-faux-simple)
  (test/if-faux-binaire)
  (test/if-constante-fausse)
  (test/if-else-vrai)
  (test/if-else-faux)
  (test/if-else-choix-plateforme)
  (test/if-imbrique-vv)
  (test/if-imbrique-vf)
  (test/if-imbrique-fv)
  (test/if-imbrique-avec-else)
  (test/if-bloc-multi-lignes)
  (test/if-avec-labels)
  (test/if-avec-macro)
  (test/if-non-ferme)
  (test/else-sans-if)
  (test/endif-sans-if)
  (when *failures*
    (format t "~&Echecs conditionnel :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
