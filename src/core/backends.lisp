; -*- coding: utf-8 -*-
(defpackage #:cl-asm/backends
  (:use #:cl)
  (:export
   #:register-backend
   #:find-backend-by-alias
   #:backend-keyword
   #:backend-aliases
   #:backend-package
   #:backend-function
   #:backend-description-fr
   #:backend-description-en
   #:all-backends))
;;; src/core/backends.lisp
;;;
;;; Registre extensible des backends d'assemblage.
;;;
;;; Chaque backend s'enregistre une seule fois via REGISTER-BACKEND.
;;; Le script CLI (cl-asm-script.lisp) et tout autre outil n'ont plus
;;; besoin de connaître la liste des backends à la compilation.
;;;
;;; Structure d'une entrée :
;;;   :keyword      — identifiant interne  (ex: :6502)
;;;   :aliases      — chaînes CLI acceptées (ex: ("6502" "mos6502"))
;;;   :package      — nom du package contenant la fonction d'assemblage
;;;   :function     — nom de la fonction ASSEMBLE-FILE-xxx
;;;   :desc-fr      — description courte (aide CLI, français)
;;;   :desc-en      — description courte (aide CLI, anglais)

(in-package #:cl-asm/backends)

;;; --------------------------------------------------------------------------
;;; Structure d'une entrée du registre
;;; --------------------------------------------------------------------------

(defstruct backend-entry
  keyword
  aliases
  package
  function
  description-fr
  description-en)

;;; --------------------------------------------------------------------------
;;; Le registre (liste ordonnée — ordre d'enregistrement = ordre d'affichage)
;;; --------------------------------------------------------------------------

(defparameter *registry* '()
  "Liste de BACKEND-ENTRY, dans l'ordre d'enregistrement.")

;;; --------------------------------------------------------------------------
;;; API publique
;;; --------------------------------------------------------------------------

(defun register-backend (keyword aliases package function desc-fr desc-en)
  "Enregistre un backend dans le registre global.
KEYWORD   — mot-clé Lisp identifiant la cible  (ex: :6502)
ALIASES   — liste de chaînes CLI               (ex: '(\"6502\" \"mos6502\"))
PACKAGE   — chaîne nom du package              (ex: \"CL-ASM/BACKEND.6502\")
FUNCTION  — chaîne nom de la fonction          (ex: \"ASSEMBLE-FILE\")
DESC-FR   — description courte en français
DESC-EN   — description courte en anglais"
  ;; Remplace une entrée existante avec le même keyword (idempotent
  ;; en cas de rechargement du fichier sous SLIME).
  (setf *registry*
        (cons (make-backend-entry
               :keyword keyword
               :aliases aliases
               :package package
               :function function
               :description-fr desc-fr
               :description-en desc-en)
              (remove keyword *registry*
                      :key #'backend-entry-keyword)))
  keyword)

(defun all-backends ()
  "Retourne la liste des BACKEND-ENTRY dans l'ordre d'enregistrement."
  (reverse *registry*))

(defun find-backend-by-alias (alias)
  "Cherche un backend dont la liste ALIASES contient la chaîne ALIAS
(comparaison insensible à la casse).
Retourne le BACKEND-ENTRY ou NIL."
  (let ((alias-down (string-downcase alias)))
    (find-if (lambda (entry)
               (member alias-down
                       (backend-entry-aliases entry)
                       :test #'string=))
             (all-backends))))

;;; Accesseurs symboliques (pour ne pas exposer la structure brute)

(defun backend-keyword (entry)      (backend-entry-keyword      entry))
(defun backend-aliases (entry)      (backend-entry-aliases      entry))
(defun backend-package (entry)      (backend-entry-package      entry))
(defun backend-function (entry)     (backend-entry-function     entry))
(defun backend-description-fr (entry) (backend-entry-description-fr entry))
(defun backend-description-en (entry) (backend-entry-description-en entry))
