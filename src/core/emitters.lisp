; -*- coding: utf-8 -*-
(defpackage #:cl-asm/emitters
  (:use #:cl)
  (:export
   #:register-emitter
   #:find-emitter-by-alias
   #:find-emitter-by-keyword
   #:emitter-keyword
   #:emitter-aliases
   #:emitter-extension
   #:emitter-function
   #:emitter-description-fr
   #:emitter-description-en
   #:all-emitters))
;;; src/core/emitters.lisp
;;;
;;; Registre extensible des émetteurs de sortie.
;;;
;;; Chaque format s'enregistre via REGISTER-EMITTER. Le script CLI
;;; et tout autre outil n'ont plus besoin de connaître la liste des
;;; formats à la compilation.
;;;
;;; Structure d'une entrée :
;;;   :keyword    — identifiant interne      (ex: :ihex)
;;;   :aliases    — chaînes CLI acceptées    (ex: ("ihex" "hex" "intel"))
;;;   :extension  — extension de fichier     (ex: "hex")
;;;   :function   — lambda (bytes path &key (origin 0))
;;;   :desc-fr    — description courte (aide CLI, français)
;;;   :desc-en    — description courte (aide CLI, anglais)

(in-package #:cl-asm/emitters)

;;; --------------------------------------------------------------------------
;;; Structure d'une entrée du registre
;;; --------------------------------------------------------------------------

(defstruct emitter-entry
  keyword
  aliases
  extension
  function
  description-fr
  description-en)

;;; --------------------------------------------------------------------------
;;; Le registre
;;; --------------------------------------------------------------------------

(defparameter *registry* '()
  "Liste de EMITTER-ENTRY, dans l'ordre d'enregistrement.")

;;; --------------------------------------------------------------------------
;;; API publique
;;; --------------------------------------------------------------------------

(defun register-emitter (keyword aliases extension function desc-fr desc-en)
  "Enregistre un émetteur dans le registre global.
KEYWORD   — mot-clé Lisp identifiant le format   (ex: :ihex)
ALIASES   — liste de chaînes CLI                 (ex: '(\"ihex\" \"hex\"))
EXTENSION — extension de fichier sans point      (ex: \"hex\")
FUNCTION  — lambda (bytes path &key (origin 0))
DESC-FR   — description courte en français
DESC-EN   — description courte en anglais"
  (setf *registry*
        (cons (make-emitter-entry
               :keyword keyword
               :aliases aliases
               :extension extension
               :function function
               :description-fr desc-fr
               :description-en desc-en)
              (remove keyword *registry*
                      :key #'emitter-entry-keyword)))
  keyword)

(defun all-emitters ()
  "Retourne la liste des EMITTER-ENTRY dans l'ordre d'enregistrement."
  (reverse *registry*))

(defun find-emitter-by-keyword (keyword)
  "Cherche un émetteur par son mot-clé interne.
Retourne le EMITTER-ENTRY ou NIL."
  (find keyword (all-emitters) :key #'emitter-entry-keyword))

(defun find-emitter-by-alias (alias)
  "Cherche un émetteur dont la liste ALIASES contient la chaîne ALIAS
(comparaison insensible à la casse).
Retourne le EMITTER-ENTRY ou NIL."
  (let ((alias-down (string-downcase alias)))
    (find-if (lambda (entry)
               (member alias-down
                       (emitter-entry-aliases entry)
                       :test #'string=))
             (all-emitters))))

;;; Accesseurs symboliques

(defun emitter-keyword      (e) (emitter-entry-keyword      e))
(defun emitter-aliases      (e) (emitter-entry-aliases      e))
(defun emitter-extension    (e) (emitter-entry-extension    e))
(defun emitter-function     (e) (emitter-entry-function     e))
(defun emitter-description-fr (e) (emitter-entry-description-fr e))
(defun emitter-description-en (e) (emitter-entry-description-en e))
