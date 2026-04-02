; -*- coding: utf-8 -*-
(defpackage #:cl-asm/dead-code
  (:use #:cl)
  (:export
   #:register-dead-code-analyzer
   #:find-dead-code-analyzer
   #:all-dead-code-analyzers
   #:dead-code-entry
   #:dead-code-entry-p
   #:dead-code-entry-target
   #:dead-code-entry-description
   #:dead-code-warning
   #:dead-code-warning-p
   #:dead-code-warning-label
   #:dead-code-warning-loc
   #:analyze-dead-code))

;;; src/core/dead-code.lisp
;;;
;;; Détecteur de code mort pour cl-asm.
;;;
;;; Principe : analyse de flot de contrôle (CFG) sur l'IR, en BFS
;;; depuis des points d'entrée déclarés. Tout label non atteignable
;;; est signalé comme "code mort".
;;;
;;; Limites connues (inhérentes à l'analyse statique) :
;;;   - Les sauts indirects (JMP (addr), JP (HL)…) dont la cible
;;;     est inconnue au moment de l'analyse ne sont pas suivis.
;;;     Le code atteignable uniquement via ces sauts peut être
;;;     faussement signalé comme mort (faux positifs).
;;;   - Le code auto-modifiant est invisible à cette analyse.
;;;   - Les gestionnaires d'interruptions doivent être déclarés
;;;     explicitement comme points d'entrée.
;;;
;;; Utilisation :
;;;   ;; Analyse standalone (toutes architectures)
;;;   (cl-asm/dead-code:analyze-dead-code sections :6502
;;;                                        :entry-points '("main" "nmi"))
;;;
;;;   ;; Via assemble (6502 uniquement, intégré)
;;;   (cl-asm/backend.6502:assemble prog :detect-dead-code t
;;;                                      :dead-code-entry-points '("irq"))
;;;
;;; Enregistrement d'une nouvelle architecture :
;;;   (cl-asm/dead-code:register-dead-code-analyzer
;;;    :myarch
;;;    :branch-mnemonics  '("BEQ" "BNE")
;;;    :jump-mnemonics    '("JMP")
;;;    :call-mnemonics    '("JSR")
;;;    :return-mnemonics  '("RTS" "RTI")
;;;    :description       "Mon architecture")
;;;
;;; Pour les architectures où le même mnémonique peut être conditionnel
;;; ou non selon ses opérandes (Z80, M68K…), fournir un :classify-fn :
;;;   (lambda (instr) → :branch | :jump | :call | :return | :normal)
;;; et un :target-operand-fn :
;;;   (lambda (instr class) → ir-operand ou nil)

(in-package #:cl-asm/dead-code)


;;; --------------------------------------------------------------------------
;;;  Entrée de registre
;;; --------------------------------------------------------------------------

(defstruct dead-code-entry
  "Entrée du registre des analyseurs de code mort."
  (target             :6502 :type keyword)
  ;; Branches conditionnelles : deux successeurs (fall-through + cible)
  (branch-mnemonics   '()   :type list)
  ;; Sauts inconditionnels directs : un successeur (la cible seulement)
  (jump-mnemonics     '()   :type list)
  ;; Appels (sous-routines) : deux successeurs (fall-through + cible)
  (call-mnemonics     '()   :type list)
  ;; Instructions terminales : aucun successeur
  (return-mnemonics   '()   :type list)
  ;; Classifieur optionnel pour architectures amb.
  ;; (lambda (ir-instruction)) → :branch | :jump | :call | :return | :normal
  (classify-fn        nil)
  ;; Extracteur d'opérande cible optionnel.
  ;; Par défaut : (first (ir-instruction-operands instr)).
  ;; (lambda (ir-instruction class)) → ir-operand ou nil
  (target-operand-fn  nil)
  (description        ""    :type string))


;;; --------------------------------------------------------------------------
;;;  Registre
;;; --------------------------------------------------------------------------

(defparameter *registry* '()
  "Liste des entrées (ordre LIFO, inversé pour all-dead-code-analyzers).")

(defun register-dead-code-analyzer (target &key branch-mnemonics jump-mnemonics
                                               call-mnemonics   return-mnemonics
                                               classify-fn      target-operand-fn
                                               description)
  "Enregistre un analyseur de code mort pour TARGET.
   Si un analyseur pour ce TARGET existait déjà, il est remplacé.
   Les listes de mnémoniques sont normalisées en majuscules."
  (flet ((up-list (lst) (mapcar #'string-upcase lst)))
    (setf *registry*
          (remove-if (lambda (e) (eq (dead-code-entry-target e) target)) *registry*))
    (push (make-dead-code-entry
           :target            target
           :branch-mnemonics  (up-list (or branch-mnemonics  '()))
           :jump-mnemonics    (up-list (or jump-mnemonics    '()))
           :call-mnemonics    (up-list (or call-mnemonics    '()))
           :return-mnemonics  (up-list (or return-mnemonics  '()))
           :classify-fn       classify-fn
           :target-operand-fn target-operand-fn
           :description       (or description ""))
          *registry*)))

(defun find-dead-code-analyzer (target)
  "Retourne l'entrée pour TARGET, ou NIL si aucune n'est enregistrée."
  (find target *registry* :key #'dead-code-entry-target))

(defun all-dead-code-analyzers ()
  "Retourne la liste de toutes les entrées enregistrées."
  (reverse *registry*))


;;; --------------------------------------------------------------------------
;;;  Résultat
;;; --------------------------------------------------------------------------

(defstruct dead-code-warning
  "Un label non atteignable détecté lors de l'analyse."
  (label "" :type string)
  (loc   nil))


;;; --------------------------------------------------------------------------
;;;  Moteur d'analyse CFG
;;; --------------------------------------------------------------------------

(defun %flatten-sections (sections)
  "Aplatit toutes les SECTIONS en un vecteur de nœuds IR.
   Retourne (values nodes label-map) où label-map est une hashtable
   string → index dans nodes."
  (let ((acc '()))
    (dolist (section sections)
      (dolist (node (cl-asm/ir:ir-section-nodes section))
        (push node acc)))
    (let* ((vec     (coerce (nreverse acc) 'vector))
           (n       (length vec))
           (lbl-map (make-hash-table :test #'equal)))
      (dotimes (i n)
        (let ((node (aref vec i)))
          (when (cl-asm/ir:ir-label-p node)
            (setf (gethash (cl-asm/ir:ir-label-name node) lbl-map) i))))
      (values vec lbl-map))))

(defun %operand->label (operand)
  "Retourne la string du label si OPERAND est une référence directe à un label.
   Retourne NIL pour les opérandes immédiats, indirects ou numériques."
  (when (and operand
             (cl-asm/ir:ir-operand-p operand)
             (eq (cl-asm/ir:ir-operand-kind operand) :direct)
             (stringp (cl-asm/ir:ir-operand-value operand)))
    (cl-asm/ir:ir-operand-value operand)))

(defun %classify-instr (instr entry)
  "Classifie INSTR selon ENTRY.
   Retourne :branch | :jump | :call | :return | :normal."
  (let ((fn (dead-code-entry-classify-fn entry)))
    (if fn
        (funcall fn instr)
        (let ((m (string-upcase (cl-asm/ir:ir-instruction-mnemonic instr))))
          (cond
            ((member m (dead-code-entry-return-mnemonics  entry) :test #'string=) :return)
            ((member m (dead-code-entry-jump-mnemonics    entry) :test #'string=) :jump)
            ((member m (dead-code-entry-branch-mnemonics  entry) :test #'string=) :branch)
            ((member m (dead-code-entry-call-mnemonics    entry) :test #'string=) :call)
            (t :normal))))))

(defun %get-target-operand (instr class entry)
  "Retourne l'opérande cible de INSTR selon ENTRY.
   Par défaut : premier opérande. Peut être surchargé par target-operand-fn."
  (declare (ignore class))
  (let ((fn (dead-code-entry-target-operand-fn entry)))
    (if fn
        (funcall fn instr)
        (first (cl-asm/ir:ir-instruction-operands instr)))))

(defun %push-label-pos (label-name label-map worklist)
  "Ajoute la position du label LABEL-NAME au WORKLIST si elle est connue."
  (let ((pos (gethash label-name label-map)))
    (when pos (push pos worklist)))
  worklist)

(defun %visit (pos nodes label-map reachable worklist entry)
  "Visite la position POS : marque comme atteinte et calcule les successeurs.
   Retourne le WORKLIST mis à jour."
  (when (or (< pos 0) (>= pos (length nodes)))
    (return-from %visit worklist))
  (when (= 1 (aref reachable pos))
    (return-from %visit worklist))
  (setf (aref reachable pos) 1)
  (let ((node (aref nodes pos))
        (next  (1+ pos)))
    (cond
      ;; Label et directives : succession séquentielle
      ((or (cl-asm/ir:ir-label-p     node)
           (cl-asm/ir:ir-directive-p node))
       (when (< next (length nodes))
         (push next worklist)))
      ;; Instruction
      ((cl-asm/ir:ir-instruction-p node)
       (let* ((class        (%classify-instr node entry))
              (tgt-operand  (%get-target-operand node class entry))
              (tgt-label    (%operand->label tgt-operand)))
         (ecase class
           (:return
            ;; Aucun successeur — fin de chemin
            )
           (:jump
            ;; Saut inconditionnel : cible seulement (pas de fall-through)
            ;; Si la cible est indirecte (tgt-label=NIL), aucun successeur connu.
            (when tgt-label
              (setf worklist (%push-label-pos tgt-label label-map worklist))))
           (:branch
            ;; Branche conditionnelle : fall-through + cible
            (when (< next (length nodes))
              (push next worklist))
            (when tgt-label
              (setf worklist (%push-label-pos tgt-label label-map worklist))))
           (:call
            ;; Appel : fall-through + cible (si directe)
            (when (< next (length nodes))
              (push next worklist))
            (when tgt-label
              (setf worklist (%push-label-pos tgt-label label-map worklist))))
           (:normal
            ;; Instruction séquentielle ordinaire
            (when (< next (length nodes))
              (push next worklist)))))))
    worklist))


;;; --------------------------------------------------------------------------
;;;  Point d'entrée public
;;; --------------------------------------------------------------------------

(defun analyze-dead-code (sections target &key entry-points)
  "Détecte le code mort dans SECTIONS pour l'architecture TARGET.

   SECTIONS      : liste de IR-SECTION (issues du parser ou de l'optimiseur).
   TARGET        : keyword d'architecture (:6502 :6510 :z80 …).
   ENTRY-POINTS  : liste de noms de labels (strings) constituant les points
                   d'entrée. Si NIL, le premier nœud de la première section
                   est utilisé comme unique point d'entrée.

   Retourne une liste de DEAD-CODE-WARNING (labels jamais atteints),
   dans l'ordre de leur apparition dans le source.

   Retourne NIL si aucun analyseur n'est enregistré pour TARGET
   (pas d'erreur — l'analyse est purement optionnelle)."
  (let ((entry (find-dead-code-analyzer target)))
    (unless entry
      (return-from analyze-dead-code '()))
    (multiple-value-bind (nodes label-map)
        (%flatten-sections sections)
      (let* ((n         (length nodes))
             (reachable (make-array n :element-type 'bit :initial-element 0))
             (worklist  '()))
        ;; --- Amorçage ---
        ;; Les noms de labels dans l'IR sont en majuscules (normalisés par le parser).
        ;; On normalise donc entry-points en majuscules pour la correspondance.
        (if entry-points
            (dolist (ep entry-points)
              (let ((pos (gethash (string-upcase ep) label-map)))
                (when pos (push pos worklist))))
            (when (> n 0)
              (push 0 worklist)))
        ;; --- BFS ---
        (loop while worklist do
          (setf worklist
                (%visit (pop worklist) nodes label-map reachable worklist entry)))
        ;; --- Collecte des labels non atteints ---
        (let ((warnings '()))
          (dotimes (i n)
            (when (and (zerop (aref reachable i))
                       (cl-asm/ir:ir-label-p (aref nodes i)))
              (let ((lbl (aref nodes i)))
                (push (make-dead-code-warning
                       :label (cl-asm/ir:ir-label-name lbl)
                       :loc   (cl-asm/ir:ir-label-loc  lbl))
                      warnings))))
          (nreverse warnings))))))
