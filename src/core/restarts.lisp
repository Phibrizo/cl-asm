; -*- coding: utf-8 -*-
(defpackage #:cl-asm/restarts
  (:use #:cl)
  (:export
   ;; Noms de restarts — à utiliser avec (invoke-restart 'cl-asm/restarts:use-zero)
   #:use-value        ; fournir une valeur de substitution
   #:use-zero         ; utiliser 0 comme valeur
   #:skip-instruction ; ignorer l'instruction (émet 0 octet)
   #:clamp-value      ; tronquer à la plage valide
   ;; Macros de commodité
   #:with-asm-use-zero
   #:with-asm-skip-errors))

;;; src/core/restarts.lisp
;;;
;;; Noms de restarts et macros de commodité pour cl-asm.
;;;
;;; Protocole des restarts d'assemblage :
;;;
;;;   cl-asm/restarts:use-value (val)
;;;     Applicable sur : asm-undefined-label, asm-range-error
;;;     Fournit VAL comme valeur de substitution.
;;;     - asm-undefined-label : VAL est l'adresse ou la constante à utiliser.
;;;     - asm-range-error     : VAL est la valeur de branche à utiliser (brut).
;;;
;;;   cl-asm/restarts:use-zero ()
;;;     Applicable sur : asm-undefined-label
;;;     Équivalent à (use-value 0) — raccourci sans argument interactif.
;;;
;;;   cl-asm/restarts:skip-instruction ()
;;;     Applicable sur : asm-unknown-mnemonic, asm-syntax-error
;;;     L'instruction fautive est ignorée : 0 octet émis, PC non incrémenté.
;;;
;;;   cl-asm/restarts:clamp-value ()
;;;     Applicable sur : asm-range-error (branche hors portée)
;;;     Tronque l'offset à la valeur la plus proche dans [-128..127].
;;;
;;; Exemple d'utilisation :
;;;
;;;   ;; Résoudre automatiquement les labels inconnus à 0
;;;   (cl-asm/restarts:with-asm-use-zero
;;;     (cl-asm/backend.6502:assemble-string "LDA unknown\nRTS"))
;;;
;;;   ;; Ignorer les mnémoniques inconnus (mode tolérant)
;;;   (cl-asm/restarts:with-asm-skip-errors
;;;     (cl-asm/backend.6502:assemble-string "BADMNEM\nRTS"))
;;;
;;;   ;; Contrôle fin avec handler-bind standard
;;;   (handler-bind
;;;     ((cl-asm/ir:asm-undefined-label
;;;       (lambda (c)
;;;         (format t "~A inconnu, on utilise #x0300~%" (cl-asm/ir:asm-error-label c))
;;;         (invoke-restart 'cl-asm/restarts:use-value #x0300))))
;;;     (cl-asm/backend.6502:assemble-string "JSR missing_fn\nRTS"))

(in-package #:cl-asm/restarts)


;;; Les symboles exportés ci-dessus (use-value, use-zero, skip-instruction,
;;; clamp-value) sont les noms de restarts — ils sont utilisés dans les
;;; restart-case des backends et de symbol-table, et référencés par les
;;; utilisateurs via invoke-restart.
;;;
;;; On n'a pas besoin de les définir explicitement : ce sont de simples
;;; symboles CL qui servent de noms dans restart-case.


;;; --------------------------------------------------------------------------
;;;  Macros de commodité
;;; --------------------------------------------------------------------------

(defmacro with-asm-use-zero (&body body)
  "Exécute BODY en résolvant automatiquement à 0 tous les labels indéfinis.
   Utile pour une première passe exploratoire ou pour les tests de layout."
  `(handler-bind
     ((cl-asm/ir:asm-undefined-label
       (lambda (c)
         (declare (ignore c))
         (invoke-restart 'use-zero))))
     ,@body))

(defmacro with-asm-skip-errors (&body body)
  "Exécute BODY en ignorant silencieusement les mnémoniques inconnus
   et les modes d'adressage non supportés (0 octet émis pour ces instructions).
   Utile pour assembler partiellement du code en cours d'écriture."
  `(handler-bind
     ((cl-asm/ir:asm-unknown-mnemonic
       (lambda (c)
         (declare (ignore c))
         (invoke-restart 'skip-instruction)))
      (cl-asm/ir:asm-syntax-error
       (lambda (c)
         (declare (ignore c))
         (invoke-restart 'skip-instruction))))
     ,@body))
