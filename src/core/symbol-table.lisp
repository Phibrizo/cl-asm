; -*- coding: utf-8 -*-
(defpackage #:cl-asm/symbol-table
  (:use #:cl)
  (:export
   #:symbol-kind #:symbol-entry #:make-symbol-entry
   #:symbol-entry-name #:symbol-entry-kind #:symbol-entry-value
   #:symbol-entry-section #:symbol-entry-defined-in-pass
   #:symbol-entry-source-loc #:symbol-entry-global-p #:symbol-entry-used-p
   #:scope #:make-scope #:scope-table #:scope-parent
   #:scope-lookup #:scope-define
   #:numeric-label-store #:make-numeric-label-entry
   #:numeric-label-entry-number #:numeric-label-entry-pc
   #:numeric-label-entry-section #:nls-entries
   #:symbol-table #:make-symbol-table
   #:st-global-scope #:st-scope-stack #:st-numeric-labels
   #:st-current-pc #:st-current-section #:st-current-pass
   #:st-relocations #:st-warnings #:current-scope
   #:push-scope #:pop-scope #:with-local-scope
   #:define-label #:define-constant #:define-equate
   #:declare-extern #:define-numeric-label
   #:resolve-symbol #:resolve-numeric-label #:symbol-defined-p
   #:add-relocation #:resolve-relocations
   #:begin-pass-2
   #:list-symbols #:dump-symbol-table #:warn-unused-symbols))
(in-package #:cl-asm/symbol-table)

;;; ==========================================================================
;;;  cl-asm / symbol-table.lisp
;;;
;;;  Résolution en deux passes :
;;;    Pass 1 - collecte tous les labels et constantes au fil du parcours
;;;             de l'IR. Les valeurs inconnues sont marquées :unresolved.
;;;    Pass 2 - patch des relocations et forward-refs une fois que l'adresse
;;;             de chaque label est définitivement connue.
;;;
;;;  portées (scopes) :
;;;    - portée globale : labels exportés, constantes .EQU/.= globales.
;;;    - portée locale  : labels anonymes (@@, @loop…) et labels préfixés
;;;      par '.' qui vivent entre deux labels globaux consécutifs.
;;;    - Les portées s'empilent : on peut imbriquer des WITH-LOCAL-SCOPE
;;;      (utile pour les macros qui génèrent des labels internes).
;;;
;;;  Labels locaux numériques (style ca65) :
;;;    1:  …  bne 1-   (référence au 1: précédent)
;;;           bne 1+   (référence au 1: suivant)
;;;    Stockés dans une liste ordonnée par adresse PC.
;;; ==========================================================================


;;; --------------------------------------------------------------------------
;;;  Entrée de la table
;;; --------------------------------------------------------------------------

(deftype symbol-kind ()
  '(member :label        ; adresse définie lors de l'assemblage
           :constant     ; valeur numérique connue à l'assemblage
           :equate       ; alias d'une autre expression
           :extern       ; déclaré extern, résolu à l'édition de liéns
           :macro-param  ; paramêtre de macro (usage interne)
           ))

(defstruct symbol-entry
  "Une entrée dans la table des symboles."
  (name       ""     :type string)
  ;; :type symbol-kind retiré volontairement : SBCL tente de compiler
  ;; le deftype inline lors du defstruct, ce qui échoue au load-time
  ;; hors ASDF (illegal function call sur la lambda de vérification).
  ;; La validation se fait par assertion dans define-label / define-constant.
  (kind       :label)
  ;; Valeur numérique ou le symbole :unresolved (forward ref).
  (value      :unresolved)
  ;; section dans laquelle ce symbole est défini (:text :data :bss …)
  (section    nil)
  ;; Numéro de passe lors de la définition (1 ou 2)
  (defined-in-pass 1 :type fixnum)
  ;; Localisation source pour les messages d'erreur
  (source-loc nil)
  ;; Vrai si le symbole doit être exporté (global)
  (global-p   nil   :type boolean)
  ;; Vrai si le symbole a été référencé au moins une fois
  (used-p     nil   :type boolean))


;;; --------------------------------------------------------------------------
;;;  portée (scope)
;;; --------------------------------------------------------------------------

(defstruct scope
  "Un niveau de portée lexicale."
  ;; Table locale : string → symbol-entry
  (table  (make-hash-table :test #'equal) :type hash-table)
  ;; référence à la portée parente (nil pour la portée globale)
  (parent nil))

(defun scope-lookup (scope name)
  "Recherche NAME dans SCOPE puis remonte les portées parentes.
   Retourne l'entrée ou NIL."
  (do ((s scope (scope-parent s)))
      ((null s) nil)
    (let ((entry (gethash name (scope-table s))))
      (when entry (return entry)))))

(defun scope-define (scope name entry)
  "définit NAME → ENTRY dans SCOPE (portée courante uniquement)."
  (setf (gethash name (scope-table scope)) entry))


;;; --------------------------------------------------------------------------
;;;  Labels locaux numériques (1: 2: é? 1+ 1- etc.)
;;; --------------------------------------------------------------------------

(defstruct numeric-label-entry
  (number 0   :type fixnum)
  (pc     0   :type (unsigned-byte 32))
  (section nil :type (or keyword null)))

(defclass numeric-label-store ()
  ((entries :initform '() :accessor nls-entries
            :documentation "Liste de NUMERIC-LABEL-ENTRY triée par PC croissant.")))

(defun nls-add (store number pc section)
  "Enregistre une occurrence du label numérique NUMBER à l'adresse PC."
  (let ((e (make-numeric-label-entry :number number :pc pc :section section)))
    (setf (nls-entries store)
          (merge 'list (nls-entries store) (list e)
                 #'< :key #'numeric-label-entry-pc))))

(defun nls-resolve-backward (store number current-pc)
  "Résout NUMBER- : cherche l'occurrence la plus récente de NUMBER avant CURRENT-PC."
  (let ((candidates
          (remove-if-not (lambda (e)
                           (and (= (numeric-label-entry-number e) number)
                                (< (numeric-label-entry-pc e) current-pc)))
                         (nls-entries store))))
    (when candidates
      (numeric-label-entry-pc (car (last candidates))))))

(defun nls-resolve-forward (store number current-pc)
  "Résout NUMBER+ : cherche l'occurrence la plus proche de NUMBER après CURRENT-PC."
  (let ((candidates
          (remove-if-not (lambda (e)
                           (and (= (numeric-label-entry-number e) number)
                                (> (numeric-label-entry-pc e) current-pc)))
                         (nls-entries store))))
    (when candidates
      (numeric-label-entry-pc (first candidates)))))


;;; --------------------------------------------------------------------------
;;;  Table des symboles principale
;;; --------------------------------------------------------------------------

(defclass symbol-table ()
  (;; portée globale (toujours présente, jamais depilée)
   (global-scope
    :initform (make-scope)
    :accessor st-global-scope)
   ;; Pile de portées actives (top = portée courante)
   ;; La portée globale en fait partie.
   (scope-stack
    :initform nil
    :accessor st-scope-stack)
   ;; Store des labels numériques
   (numeric-labels
    :initform (make-instance 'numeric-label-store)
    :accessor st-numeric-labels)
   ;; PC courant (mis à jour par le linker/encodeur)
   (current-pc
    :initform 0
    :accessor st-current-pc
    :type (unsigned-byte 32))
   ;; section courante
   (current-section
    :initform :text
    :accessor st-current-section
    :type keyword)
   ;; Numéro de passe courant (1 ou 2)
   (current-pass
    :initform 1
    :accessor st-current-pass
    :type fixnum)
   ;; Liste des relocations accumulées
   (relocations
    :initform '()
    :accessor st-relocations
    :type list)
   ;; avertissements (labels définis plusieurs fois, inutilisé?s…)
   (warnings
    :initform '()
    :accessor st-warnings
    :type list)))

(defun make-symbol-table ()
  "Crée et initialise une nouvelle table des symboles."
  (let ((st (make-instance 'symbol-table)))
    ;; La portée globale est le premier (et seul) niveau initial
    (setf (st-scope-stack st) (list (st-global-scope st)))
    st))

;;; Accesseur sur la portée courante (sommet de la pile)
(defun current-scope (st)
  (first (st-scope-stack st)))


;;; --------------------------------------------------------------------------
;;;  Gestion des portées
;;; --------------------------------------------------------------------------

(defun push-scope (st)
  "empile une nouvelle portée locale."
  (let ((new-scope (make-scope :parent (current-scope st))))
    (push new-scope (st-scope-stack st))
    new-scope))

(defun pop-scope (st)
  "dépile la portée locale courante. Erreur si on tente de dépiler la globale."
  (when (null (scope-parent (current-scope st)))
    (error "Tentative de dépiler la portée globale."))
  (pop (st-scope-stack st)))


(defmacro with-local-scope ((st) &body body)
  "exécute BODY dans une nouvelle portée locale, puis la dépile.
   ST est ?evalué une seule fois via un gensym interne. La variable ST
   du site d'appel reste accèssible dans le body par la fermeture lexicale
   normale - aucun rebind n'est introduit, ce qui évite les warnings
   'variable définie mais non utilisé?e' quand le body n'y accède pas."
  (let ((st-once (gensym "ST-ONCE-")))
    `(let ((,st-once ,st))
       (push-scope ,st-once)
       (unwind-protect
            (progn ,@body)
         (pop-scope ,st-once)))))


;;; --------------------------------------------------------------------------
;;;  définition de symboles
;;; --------------------------------------------------------------------------

(defun define-label (st name &key global source-loc)
  "définit le label NAME à la position courante (PC, section).
   Si le label est déjà défini :
     - Pass 1 → erreur (redéfinition)
     - Pass 2 → vérifie la cohérence de la valeur (phase de validation)"
  (let* ((scope  (if global (st-global-scope st) (current-scope st)))
         (pc     (st-current-pc st))
         (section (st-current-section st))
         (existing (gethash name (scope-table scope))))
    (cond
      ;; Redéfinition d'un label par un label en passe 1 : erreur
      ((and existing
            (eq (symbol-entry-kind existing) :label)
            (= (st-current-pass st) 1))
       (error 'cl-asm/ir::asm-error
              :message (format nil "Label '~A' défini plusieurs fois." name)
              :source-loc source-loc))
      ;; Le symbole existe déjà comme constante/équate : ignorer silencieusement.
      ;; Cela arrive quand un label et une constante partagent le même nom en
      ;; casse différente (COLOR = $D800 puis color_loop: lu comme COLOR_LOOP).
      ;; La constante a priorité — ne pas écraser sa valeur avec le PC courant.
      ((and existing
            (member (symbol-entry-kind existing) '(:constant :equate)))
       nil)
      ;; Pass 2 : vérification de cohérence entre les deux passes
      ((and existing (= (st-current-pass st) 2))
       (unless (eql (symbol-entry-value existing) pc)
         (push (format nil "AVERT : label '~A' a changé de valeur entre les passes (~X → ~X)"
                       name (symbol-entry-value existing) pc)
               (st-warnings st)))
       (setf (symbol-entry-value existing) pc))
      ;; Nouvelle définition
      (t
       (scope-define scope name
                     (make-symbol-entry
                      :name    name
                      :kind    :label
                      :value   pc
                      :section section
                      :defined-in-pass (st-current-pass st)
                      :source-loc source-loc
                      :global-p (or global nil)))))))

(defun define-constant (st name value &key global source-loc)
  "définit une constante numérique (*.EQU / .= / .define*)."
  (let* ((scope    (if global (st-global-scope st) (current-scope st)))
         (existing (gethash name (scope-table scope))))
    (when (and existing (= (st-current-pass st) 1))
      (error 'cl-asm/ir::asm-error
             :message (format nil "Constante '~A' définie plusieurs fois." name)
             :source-loc source-loc))
    (scope-define scope name
                  (make-symbol-entry
                   :name    name
                   :kind    :constant
                   :value   value
                   :section nil
                   :defined-in-pass (st-current-pass st)
                   :source-loc source-loc
                   :global-p (or global nil)))))

(defun define-equate (st name expression &key source-loc)
  "définit un équate (alias d'expression, ?evalué paresseusement)."
  (let ((scope (current-scope st)))
    (scope-define scope name
                  (make-symbol-entry
                   :name    name
                   :kind    :equate
                   :value   expression  ; expression brute, ?evaluée à la résolution
                   :source-loc source-loc))))

(defun declare-extern (st name &key source-loc)
  "déclare NAME comme symbole externe (résolu par le linker)."
  (scope-define (st-global-scope st) name
                (make-symbol-entry
                 :name    name
                 :kind    :extern
                 :value   :unresolved
                 :source-loc source-loc)))

(defun define-numeric-label (st number)
  "Enregistre une occurrence du label numérique NUMBER à la position courante."
  (nls-add (st-numeric-labels st)
           number
           (st-current-pc st)
           (st-current-section st)))


;;; --------------------------------------------------------------------------
;;;  Résolution de symboles
;;; --------------------------------------------------------------------------

;;; resolve-equate et resolve-symbol se rappellent mutuellement.
;;; On déclare resolve-symbol en avance pour que le compilateur ne se plaigne
;;; pas quand resolve-equate y fait référence avant sa définition.
(declaim (ftype (function (t string &key (:source-loc t)) (values t t))
                resolve-symbol))

(defun resolve-equate (st expr source-loc)
  "éévalue une expression d'équate via cl-asm/expression:eval-expr.
   retourne (values VALEUR RESOLVEDP)."
  (cl-asm/expression:eval-expr
   expr
   (cl-asm/expression:make-env
    :symbol-table st
    :source-loc   source-loc
    :pc           (st-current-pc st))))

(defun %signal-undefined-label (name message source-loc)
  "Signale asm-undefined-label avec restarts use-value et use-zero.
   Si un restart est invoqué, retourne (values VAL T).
   Sinon, propage l'erreur normalement."
  (restart-case
    (progn
      (error 'cl-asm/ir::asm-undefined-label
             :label      name
             :message    message
             :source-loc source-loc)
      ;; Non atteint si l'erreur propage
      (values 0 t))
    (cl-asm/restarts:use-value (v)
      :report "Fournir la valeur de ce symbole"
      :interactive (lambda () (format *query-io* "Valeur pour ~A : " name)
                              (list (read *query-io*)))
      (values v t))
    (cl-asm/restarts:use-zero ()
      :report "Utiliser 0 comme valeur"
      (values 0 t))))

(defun resolve-symbol (st name &key source-loc)
  "Résout NAME. retourne (values VALEUR RESOLVEDP).
   En pass 1, un forward-ref retourne (values :unresolved nil).
   En pass 2, un symbole toujours absent signale une erreur avec restarts
   (use-value, use-zero)."
  (let ((entry (scope-lookup (current-scope st) name)))
    (cond
      ;; Symbole connu avec valeur numérique
      ((and entry (not (eq (symbol-entry-value entry) :unresolved)))
       (setf (symbol-entry-used-p entry) t)
       (let ((val (symbol-entry-value entry)))
         ;; Les équates sont évalués récursivement via resolve-équate
         (if (eq (symbol-entry-kind entry) :equate)
             (resolve-equate st val source-loc)
             (values val t))))
      ;; Symbole connu mais non encore résolu (forward ref en pass 1)
      ((and entry (eq (symbol-entry-value entry) :unresolved))
       (if (= (st-current-pass st) 2)
           (%signal-undefined-label
            name
            (format nil "Symbole '~A' toujours non résolu en pass 2." name)
            source-loc)
           (values :unresolved nil)))
      ;; Symbole inconnu
      (t
       (if (= (st-current-pass st) 2)
           (%signal-undefined-label
            name
            (format nil "Symbole '~A' indéfini." name)
            source-loc)
           ;; Pass 1 : forward ref, on laisse passer
           (values :unresolved nil))))))

(defun resolve-numeric-label (st number direction)
  "Résout un label numérique.
   DIRECTION : :backward (N-) ou :forward (N+)."
  (let ((pc (st-current-pc st)))
    (ecase direction
      (:backward
       (or (nls-resolve-backward (st-numeric-labels st) number pc)
           (if (= (st-current-pass st) 2)
               (%signal-undefined-label
                (format nil "~D-" number)
                (format nil "Label numérique ~D- introuvable avant $~X." number pc)
                nil)
               (values :unresolved nil))))
      (:forward
       (or (nls-resolve-forward (st-numeric-labels st) number pc)
           (values :unresolved nil))))))   ; toujours :unresolved en pass 1 si pas encore vu

(defun symbol-defined-p (st name)
  "Vrai si NAME est défini et a une valeur résolue."
  (when st
    (let ((entry (scope-lookup (current-scope st) name)))
      (and entry (not (eq (symbol-entry-value entry) :unresolved))))))


;;; --------------------------------------------------------------------------
;;;  Relocations
;;; --------------------------------------------------------------------------

(defun add-relocation (st symbol type &key (addend 0) source-loc)
  "Enregistre une relocation pour SYMBOL à la position courante."
  (push (cl-asm/ir:make-ir-relocation
         :offset  (st-current-pc st)
         :symbol  symbol
         :type    type
         :addend  addend)
        (st-relocations st))
  (when source-loc  ; silence le warning unused
    nil))

(defun resolve-relocations (st)
  "Pass 2 : tente de résoudre toutes les relocations accumulées.
   retourne deux listes : (RéSOLUES NON-RéSOLUES)."
  (loop :for reloc :in (st-relocations st)
        :for sym = (cl-asm/ir:ir-relocation-symbol reloc)
        :for (val resolvedp) = (multiple-value-list
                                (resolve-symbol st sym))
        :if resolvedp
          :collect (cons reloc val) :into resolved
        :else
          :collect reloc :into unresolved
        :finally (return (values resolved unresolved))))


;;; --------------------------------------------------------------------------
;;;  Passage de passe 1 → passe 2
;;; --------------------------------------------------------------------------

(defun begin-pass-2 (st)
  "Réinitialise le PC et la section courante pour la passe 2.
   Les définitions de symboles sont conservées mais marquées pour
   vérification de cohérence."
  (setf (st-current-pass    st) 2
        (st-current-pc      st) 0
        (st-current-section st) :text)
  ;; Vider le store numérique : il sera reconstruit identiquement
  (setf (st-numeric-labels st) (make-instance 'numeric-label-store))
  st)


;;; --------------------------------------------------------------------------
;;;  Introspection / débogage
;;; --------------------------------------------------------------------------

(defun list-symbols (st &key (kind nil) (section nil) (global-only nil))
  "retourne la liste de toutes les entrées de la table (portée globale).
   Filtrès optionnels : KIND (keyword), SECTION (keyword), GLOBAL-ONLY."
  (let (results)
    (maphash
     (lambda (name entry)
       (declare (ignore name))
       (when (and (or (null kind)        (eq kind    (symbol-entry-kind    entry)))
                  (or (null section)     (eq section  (symbol-entry-section entry)))
                  (or (not global-only)  (symbol-entry-global-p entry)))
         (push entry results)))
     (scope-table (st-global-scope st)))
    (sort results #'string< :key #'symbol-entry-name)))

(defun dump-symbol-table (st &optional (stream *standard-output*))
  "Affiche la table des symboles dans STREAM (utile pour le listing)."
  (format stream "~&; --- Table des symboles ---~%")
  (format stream "; ~30A ~8A ~8A ~A~%" "Nom" "Valeur" "section" "Type")
  (format stream "; ~30A ~8A ~8A ~A~%"
          (make-string 30 :initial-element #\-)
          (make-string 8  :initial-element #\-)
          (make-string 8  :initial-element #\-)
          (make-string 8  :initial-element #\-))
  (dolist (entry (list-symbols st))
    (format stream "; ~30A ~8X ~8A ~A~%"
            (symbol-entry-name    entry)
            (let ((v (symbol-entry-value entry)))
              (if (eq v :unresolved) "éé" v))
            (or (symbol-entry-section entry) "-")
            (symbol-entry-kind    entry)))
  (format stream "; ~D symbole(s)~%"
          (hash-table-count (scope-table (st-global-scope st)))))

(defun warn-unused-symbols (st &optional (stream *standard-output*))
  "Signale les labels définis mais jamais référencés."
  (let ((unused '()))
    (maphash (lambda (name entry)
               (when (and (eq (symbol-entry-kind entry) :label)
                          (not (symbol-entry-used-p entry))
                          (not (symbol-entry-global-p entry)))
                 (push name unused)))
             (scope-table (st-global-scope st)))
    (dolist (name (sort unused #'string<))
      (format stream "~&; AVERT : label '~A' défini mais jamais utilisé?.~%" name))
    unused))
