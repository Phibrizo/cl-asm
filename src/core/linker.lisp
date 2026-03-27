; -*- coding: utf-8 -*-
(defpackage #:cl-asm/linker
  (:use #:cl)
  (:export
   #:register-linker-backend
   #:find-linker-backend
   #:all-linker-backends
   #:linker-backend-entry
   #:linker-backend-entry-keyword
   #:linker-backend-entry-aliases
   #:linker-backend-entry-pass-1-fn
   #:linker-backend-entry-pass-2-fn
   #:linker-backend-entry-description
   #:link-unit
   #:make-link-unit
   #:link-unit-name
   #:link-unit-sections
   #:link-unit-target
   #:link-unit-from-program
   #:link))
;;; src/core/linker.lisp
;;;
;;; Linker modulaire en mémoire pour la famille 6502.
;;;
;;; Principe :
;;;   Chaque fichier source est parsé en IR-PROGRAM puis emballé dans un
;;;   LINK-UNIT.  La fonction LINK fusionne les sections de toutes les unités,
;;;   crée une table de symboles partagée et exécute les deux passes
;;;   d'assemblage sur l'ensemble, permettant ainsi les références croisées
;;;   entre fichiers.
;;;
;;; Usage typique :
;;;
;;;   (let* ((u1 (link-unit-from-program "main"  (parse-file "main.asm")  :6502))
;;;          (u2 (link-unit-from-program "utils" (parse-file "utils.asm") :6502)))
;;;     (link (list u1 u2) :origin #x0801))
;;;
;;; Les backends s'enregistrent via REGISTER-LINKER-BACKEND en fin de
;;; fichier ; aucune modification du code d'appel n'est nécessaire pour
;;; ajouter une nouvelle architecture.

(in-package #:cl-asm/linker)

;;; --------------------------------------------------------------------------
;;;  Registre des backends de linkage
;;; --------------------------------------------------------------------------

(defstruct linker-backend-entry
  "Entrée du registre des backends de linkage.
   PASS-1-FN : (lambda (sections symtable origin) ...) → pc final
   PASS-2-FN : (lambda (sections symtable origin) ...) → (unsigned-byte 8) vector"
  keyword
  aliases
  pass-1-fn
  pass-2-fn
  description)

(defparameter *registry* '()
  "Liste ordonnée des linker-backend-entry enregistrés.")

(defun register-linker-backend (keyword aliases pass-1-fn pass-2-fn description)
  "Enregistre un backend de linkage.
   KEYWORD  : symbole clé principal, ex. :6502
   ALIASES  : liste de strings alternatifs, ex. '(\"6502\" \"mos6502\")
   PASS-1-FN, PASS-2-FN : fonctions de linkage (voir linker-backend-entry)"
  (let ((entry (make-linker-backend-entry
                :keyword keyword
                :aliases (mapcar #'string-downcase aliases)
                :pass-1-fn pass-1-fn
                :pass-2-fn pass-2-fn
                :description description)))
    (setf *registry*
          (cons entry
                (remove-if (lambda (e)
                             (eq (linker-backend-entry-keyword e) keyword))
                           *registry*)))))

(defun all-linker-backends ()
  "Retourne la liste de tous les backends enregistrés (du plus récent au plus ancien)."
  (reverse *registry*))

(defun find-linker-backend (keyword-or-alias)
  "Cherche un backend par son mot-clé ou un alias string.
   Retourne un LINKER-BACKEND-ENTRY ou NIL."
  (let ((key (if (keywordp keyword-or-alias)
                 keyword-or-alias
                 (intern (string-upcase (string keyword-or-alias)) :keyword))))
    (or
     ;; Recherche par mot-clé
     (find key *registry* :key #'linker-backend-entry-keyword)
     ;; Recherche par alias string
     (let ((s (string-downcase (string keyword-or-alias))))
       (find-if (lambda (e)
                  (member s (linker-backend-entry-aliases e) :test #'string=))
                *registry*)))))

;;; --------------------------------------------------------------------------
;;;  Structure LINK-UNIT
;;; --------------------------------------------------------------------------

(defstruct link-unit
  "Unité de linkage : sections IR issues d'un fichier source parsé.
   NAME    : identifiant lisible (ex. nom du fichier)
   SECTIONS: liste de IR-SECTION
   TARGET  : mot-clé du backend cible (:6502, :6510, :65c02, :45gs02 …)"
  (name    "" :type string)
  sections
  (target  :6502 :type keyword))

(defun link-unit-from-program (name program &optional (target :6502))
  "Crée un LINK-UNIT à partir d'un IR-PROGRAM parsé.
   NAME    : identifiant string pour les messages d'erreur
   PROGRAM : IR-PROGRAM retourné par cl-asm/parser:parse-*
   TARGET  : mot-clé du backend cible (:6502 par défaut)"
  (make-link-unit :name name
                  :sections (cl-asm/ir:ir-program-sections program)
                  :target target))

;;; --------------------------------------------------------------------------
;;;  Fonction principale : LINK
;;; --------------------------------------------------------------------------

(defun link (units &key (origin #x0801))
  "Lie plusieurs LINK-UNITs en un seul vecteur d'octets (unsigned-byte 8).

   Toutes les unités doivent cibler la même architecture (le mot-clé TARGET
   de la première unité fait foi ; les autres sont vérifiés).

   Le linkage crée une table de symboles partagée, fusionne les sections dans
   l'ordre des unités puis exécute les deux passes d'assemblage, permettant
   ainsi les références de labels croisées entre fichiers.

   UNITS  : liste non vide de LINK-UNIT
   ORIGIN : adresse de chargement ($0801 par défaut, standard C64/6502)"
  (when (null units)
    (error "LINK : liste d'unités vide."))
  (let* ((target  (link-unit-target (first units)))
         (backend (find-linker-backend target)))
    ;; Vérifier que le backend est connu
    (unless backend
      (error "LINK : backend de linkage inconnu pour la cible ~A.~%~
              Backends disponibles : ~{~A~^, ~}"
             target
             (mapcar #'linker-backend-entry-keyword (all-linker-backends))))
    ;; Vérifier la cohérence des cibles
    (dolist (u (rest units))
      (unless (eq (link-unit-target u) target)
        (error "LINK : les unités doivent toutes cibler la même architecture.~%~
                Première unité : ~A (~A), unité ~A : ~A"
               (link-unit-name (first units)) target
               (link-unit-name u) (link-unit-target u))))
    ;; Fusionner toutes les sections dans l'ordre des unités
    (let ((all-sections (mapcan (lambda (u)
                                  (copy-list (link-unit-sections u)))
                                units))
          (symtable (cl-asm/symbol-table:make-symbol-table)))
      ;; Initialiser le PC
      (setf (cl-asm/symbol-table:st-current-pc symtable) origin)
      ;; Passe 1 : collecte des labels dans toutes les sections
      (funcall (linker-backend-entry-pass-1-fn backend)
               all-sections symtable origin)
      ;; Passe 2 : encodage avec tous les symboles résolus
      (cl-asm/symbol-table:begin-pass-2 symtable)
      (setf (cl-asm/symbol-table:st-current-pc symtable) origin)
      (funcall (linker-backend-entry-pass-2-fn backend)
               all-sections symtable origin))))
