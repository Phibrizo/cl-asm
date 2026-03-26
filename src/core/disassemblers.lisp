; -*- coding: utf-8 -*-
(defpackage #:cl-asm/disassemblers
  (:use #:cl)
  (:export
   #:register-disassembler
   #:find-disassembler-by-keyword
   #:disassembler-keyword
   #:disassembler-aliases
   #:disassembler-package
   #:disassembler-function
   #:disassembler-description
   #:all-disassemblers))
;;; src/core/disassemblers.lisp
;;;
;;; Registre extensible des désassembleurs.
;;;
;;; Chaque désassembleur s'enregistre une seule fois via REGISTER-DISASSEMBLER.
;;; La clé est un mot-clé Lisp (:6502, :45gs02…).
;;; Le slot FUNCTION donne le nom de la fonction DISASM-ONE de ce désassembleur.

(in-package #:cl-asm/disassemblers)


;;; --------------------------------------------------------------------------
;;;  Structure d'une entrée du registre
;;; --------------------------------------------------------------------------

(defstruct disassembler-entry
  keyword
  aliases
  package
  function
  description)


;;; --------------------------------------------------------------------------
;;;  Le registre
;;; --------------------------------------------------------------------------

(defparameter *registry* '()
  "Liste de DISASSEMBLER-ENTRY, dans l'ordre d'enregistrement.")


;;; --------------------------------------------------------------------------
;;;  API publique
;;; --------------------------------------------------------------------------

(defun register-disassembler (keyword aliases package function description)
  "Enregistre un désassembleur dans le registre global.
KEYWORD     — mot-clé interne       (ex: :6502)
ALIASES     — liste de chaînes CLI  (ex: '(\"6502\" \"mos6502\"))
PACKAGE     — chaîne nom du package (ex: \"CL-ASM/DISASSEMBLER.6502\")
FUNCTION    — chaîne nom de la fonction DISASM-ONE
DESCRIPTION — description courte"
  (setf *registry*
        (cons (make-disassembler-entry
               :keyword     keyword
               :aliases     aliases
               :package     package
               :function    function
               :description description)
              (remove keyword *registry*
                      :key #'disassembler-entry-keyword)))
  keyword)

(defun all-disassemblers ()
  "Retourne la liste des DISASSEMBLER-ENTRY dans l'ordre d'enregistrement."
  (reverse *registry*))

(defun find-disassembler-by-keyword (keyword)
  "Cherche un désassembleur par mot-clé. Retourne le DISASSEMBLER-ENTRY ou NIL."
  (find keyword (all-disassemblers) :key #'disassembler-entry-keyword))

;;; Accesseurs symboliques

(defun disassembler-keyword (e)     (disassembler-entry-keyword     e))
(defun disassembler-aliases (e)     (disassembler-entry-aliases     e))
(defun disassembler-package (e)     (disassembler-entry-package     e))
(defun disassembler-function (e)    (disassembler-entry-function    e))
(defun disassembler-description (e) (disassembler-entry-description e))
