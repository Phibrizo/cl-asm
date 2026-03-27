; -*- coding: utf-8 -*-
(defpackage #:cl-asm/optimizer
  (:use #:cl)
  (:export
   #:register-peephole-optimizer
   #:find-peephole-optimizer
   #:all-peephole-optimizers
   #:peephole-entry
   #:peephole-entry-p
   #:peephole-entry-target
   #:peephole-entry-rules
   #:peephole-entry-description
   #:optimize-sections))

;;; src/core/optimizer.lisp
;;;
;;; Registre des optimiseurs peephole pour cl-asm.
;;;
;;; Un optimiseur peephole travaille sur l'IR AVANT la passe 1, ce qui
;;; permet à la passe 1 de recalculer les adresses des labels correctement
;;; après chaque remplacement d'instructions.
;;;
;;; Protocole des règles :
;;;   (rule nodes) → NIL si la règle ne s'applique pas
;;;                → (values replacement-list consumed-count) si la règle s'applique
;;;   - NODES est la liste complète des nœuds restants à traiter.
;;;   - REPLACEMENT-LIST : liste de nœuds IR en remplacement (peut être vide).
;;;   - CONSUMED-COUNT   : nombre de nœuds consommés depuis la tête de NODES.
;;;
;;; Enregistrement :
;;;   (register-peephole-optimizer target rules description)
;;;   Un backend appelle cette fonction à la fin de son fichier optimizer.
;;;   TARGET est un keyword (:6502, :6510, :65c02, :45gs02 …).
;;;   RULES  est une liste de fonctions suivant le protocole ci-dessus.

(in-package #:cl-asm/optimizer)


;;; --------------------------------------------------------------------------
;;;  Entrée de registre
;;; --------------------------------------------------------------------------

(defstruct peephole-entry
  "Entrée du registre des optimiseurs peephole."
  (target      :6502 :type keyword)
  (rules       '()   :type list)
  (description ""    :type string))


;;; --------------------------------------------------------------------------
;;;  Registre
;;; --------------------------------------------------------------------------

(defparameter *registry* '()
  "Liste des entrées peephole (ordre LIFO, inversé pour all-peephole-optimizers).")

(defun register-peephole-optimizer (target rules description)
  "Enregistre un optimiseur peephole pour TARGET.
   Si un optimiseur pour ce TARGET existait déjà, il est remplacé."
  (setf *registry*
        (remove-if (lambda (e) (eq (peephole-entry-target e) target)) *registry*))
  (push (make-peephole-entry :target target :rules rules :description description)
        *registry*))

(defun find-peephole-optimizer (target)
  "Retourne l'entrée peephole pour TARGET, ou NIL si aucune n'est enregistrée."
  (find target *registry* :key #'peephole-entry-target))

(defun all-peephole-optimizers ()
  "Retourne la liste de toutes les entrées peephole enregistrées."
  (reverse *registry*))


;;; --------------------------------------------------------------------------
;;;  Moteur d'application des règles
;;; --------------------------------------------------------------------------

(defun %apply-rules (nodes rules)
  "Applique les règles peephole sur la liste de nœuds NODES.
   Retourne la liste de nœuds optimisée.

   Pour chaque position dans NODES, tente chaque règle dans l'ordre.
   Dès qu'une règle s'applique (retourne un CONSUMED-COUNT non-NIL),
   les nœuds consommés sont remplacés par REPLACEMENT-LIST et
   le traitement continue depuis le premier nœud restant.
   Aucune règle n'est ré-appliquée sur les nœuds déjà produits par
   un remplacement (une seule passe sur la séquence originale)."
  (let ((result '()))
    (loop while nodes do
      (let ((fired nil))
        (dolist (rule rules)
          (unless fired
            (multiple-value-bind (replacement consumed)
                (funcall rule nodes)
              (when consumed
                (setf result  (nconc result replacement))
                (setf nodes   (nthcdr consumed nodes))
                (setf fired   t)))))
        (unless fired
          (setf result (nconc result (list (first nodes))))
          (setf nodes (rest nodes)))))
    result))

(defun %optimize-section (section rules)
  "Retourne une nouvelle IR-SECTION avec les nœuds optimisés."
  (let* ((old-nodes (cl-asm/ir:ir-section-nodes section))
         (new-nodes (%apply-rules old-nodes rules)))
    (cl-asm/ir:make-ir-section
     :name   (cl-asm/ir:ir-section-name   section)
     :origin (cl-asm/ir:ir-section-origin section)
     :nodes  new-nodes
     :binary nil)))


;;; --------------------------------------------------------------------------
;;;  Point d'entrée public
;;; --------------------------------------------------------------------------

(defun optimize-sections (sections target)
  "Applique l'optimiseur peephole enregistré pour TARGET à toutes les SECTIONS.
   Si aucun optimiseur n'est enregistré pour TARGET, retourne SECTIONS inchangé."
  (let ((entry (find-peephole-optimizer target)))
    (if entry
        (mapcar (lambda (s) (%optimize-section s (peephole-entry-rules entry)))
                sections)
        sections)))
