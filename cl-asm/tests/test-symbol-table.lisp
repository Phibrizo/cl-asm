; -*- coding: utf-8 -*-
;;; tests/test-symbol-table.lisp
;;;
;;; Tests unitaires pour cl-asm/symbol-table.
;;; Pas de dépendance externe - chaque test est une fonction retournant T/NIL.
;;; Exécution : (run-all-tests)

(defpackage #:cl-asm/test.symbol-table
  (:use #:cl #:cl-asm/symbol-table #:cl-asm/ir)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.symbol-table)

;;; --------------------------------------------------------------------------
;;;  Infra de test minimaliste
;;; --------------------------------------------------------------------------

(defvar *pass* 0)
(defvar *fail* 0)
(defvar *failures* '())

(defmacro check (description form)
  `(let ((result (handler-case ,form
                   (error (e) (progn
                                (format t "~&  ERREUR inattendue dans é~Aé : ~A~%"
                                        ,description e)
                                nil)))))
     (if result
         (progn (incf *pass*) (format t "~&  OK  ~A~%" ,description))
         (progn (incf *fail*)
                (push ,description *failures*)
                (format t "~&  KO  ~A~%" ,description)))))

(defmacro check-error (description condition-type form)
  `(let ((fired nil))
     (handler-case ,form
       (,condition-type () (setf fired t))
       (error (e) (format t "~&  ERREUR inattendue dans é~Aé : ~A~%" ,description e)))
     (if fired
         (progn (incf *pass*) (format t "~&  OK  ~A (erreur attendue)~%" ,description))
         (progn (incf *fail*)
                (push ,description *failures*)
                (format t "~&  KO  ~A (erreur NON déclenchée)~%" ,description)))))

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&~%[~A]~%" ',name)
     ,@body))


;;; --------------------------------------------------------------------------
;;;  Helpers
;;; --------------------------------------------------------------------------

(defun make-st (&key (pass 1) (pc 0) (section :text))
  (let ((st (make-symbol-table)))
    (setf (st-current-pass    st) pass
          (st-current-pc      st) pc
          (st-current-section st) section)
    st))

(defun set-pc (st pc)
  (setf (st-current-pc st) pc) st)


;;; --------------------------------------------------------------------------
;;;  Tests : définition de labels
;;; --------------------------------------------------------------------------

(deftest test/define-label-basic
  (let ((st (make-st :pc #x0810)))
    (define-label st "start")
    (check "label 'start' est défini"
           (symbol-defined-p st "start"))
    (check "valeur = PC au moment de la définition"
           (= #x0810
              (symbol-entry-value
               (scope-lookup (current-scope st) "start"))))))

(deftest test/define-label-global
  (let ((st (make-st :pc #x1000)))
    (define-label st "main" :global t)
    (let ((entry (scope-lookup (st-global-scope st) "main")))
      (check "label global présent dans la portée globale"
             (not (null entry)))
      (check "global-p = T"
             (symbol-entry-global-p entry)))))

(deftest test/define-label-redefinition-pass1-error
  (let ((st (make-st)))
    (define-label st "dup")
    (check-error "redéfinition en pass 1 → asm-error"
                 asm-error
                 (define-label st "dup"))))

(deftest test/define-label-pass2-value-stable
  ;; En pass 2, redéfinir un label avec la méme valeur ne doit pas génèrer d'avertissement
  (let ((st (make-st :pass 1 :pc #x0820)))
    (define-label st "loop")
    (begin-pass-2 st)
    (set-pc st #x0820)
    (define-label st "loop")   ; méme valeur → OK
    (check "aucun avertissement si valeur stable"
           (null (st-warnings st)))))

(deftest test/define-label-pass2-value-changed
  ;; En pass 2, une valeur différente doit génèrer un avertissement
  (let ((st (make-st :pass 1 :pc #x0820)))
    (define-label st "unstable")
    (begin-pass-2 st)
    (set-pc st #x0830)          ; adresse différente
    (define-label st "unstable")
    (check "avertissement generé si valeur a changé"
           (= 1 (length (st-warnings st))))))


;;; --------------------------------------------------------------------------
;;;  Tests : définition de constantes
;;; --------------------------------------------------------------------------

(deftest test/define-constant-basic
  (let ((st (make-st)))
    (define-constant st "SCREEN" #xD000)
    (multiple-value-bind (val resolvedp)
        (resolve-symbol st "SCREEN")
      (check "constante résolue immédiatement"
             resolvedp)
      (check "valeur correcte"
             (= #xD000 val)))))

(deftest test/define-constant-redefinition-error
  (let ((st (make-st)))
    (define-constant st "C" 42)
    (check-error "redéfinition de constante → asm-error"
                 asm-error
                 (define-constant st "C" 99))))


;;; --------------------------------------------------------------------------
;;;  Tests : équates
;;; --------------------------------------------------------------------------

(deftest test/equate-simple
  (let ((st (make-st)))
    (define-constant st "BASE" #x8000)
    (define-equate   st "ADDR" '(:+ "BASE" 16))
    (multiple-value-bind (val resolvedp)
        (resolve-symbol st "ADDR")
      (check "équate résolu"
             resolvedp)
      (check "valeur = BASE + 16"
             (= (+ #x8000 16) val)))))

(deftest test/equate-lo-hi
  (let ((st (make-st)))
    (define-constant st "VEC" #x1234)
    (define-equate   st "VEC_LO" '(:lo "VEC"))
    (define-equate   st "VEC_HI" '(:hi "VEC"))
    (multiple-value-bind (lo r1) (resolve-symbol st "VEC_LO")
      (multiple-value-bind (hi r2) (resolve-symbol st "VEC_HI")
        (check ":lo résolu" r1)
        (check ":hi résolu" r2)
        (check "VEC_LO = $34" (= #x34 lo))
        (check "VEC_HI = $12" (= #x12 hi))))))


;;; --------------------------------------------------------------------------
;;;  Tests : forward références (pass 1 → pass 2)
;;; --------------------------------------------------------------------------

(deftest test/forward-ref-pass1
  ;; En pass 1, un label pas encore vu doit retourner :unresolved sans erreur
  (let ((st (make-st :pass 1 :pc #x0810)))
    (multiple-value-bind (val resolvedp)
        (resolve-symbol st "future")
    (check "forward ref en pass 1 → :unresolved"
           (eq :unresolved val))
    (check "resolvedp = nil"
           (not resolvedp)))))

(deftest test/forward-ref-resolved-in-pass2
  ;; Scénario complet : référence avant définition
  (let ((st (make-st :pass 1 :pc #x0800)))
    ;; Pass 1 : on tente de résoudre "target" (pas encore défini)
    (multiple-value-bind (v1 r1) (resolve-symbol st "target")
      (check "pass 1 : non résolu" (not r1))
      (check "pass 1 : :unresolved" (eq :unresolved v1)))
    ;; Pass 1 : on définit "target" plus loin
    (set-pc st #x0850)
    (define-label st "target")
    ;; Pass 2 : on repart depuis le début
    (begin-pass-2 st)
    (set-pc st #x0800)
    ;; Maintenant on doit résoudre sans probléme
    (multiple-value-bind (v2 r2) (resolve-symbol st "target")
      (declare (ignore v2))
      (check "pass 2 : résolu" r2)
      (check "pass 2 : valeur correcte"
             ;; En pass 2, begin-pass-2 remet PC à 0 mais la valeur du label
             ;; n'a pas encore été mise à jour (il faut re-parcourir l'IR).
             ;; Ici on simule le re-parcours :
             (progn
               (set-pc st #x0850)
               (define-label st "target")   ; re-définition en pass 2
               (set-pc st #x0800)
               (multiple-value-bind (v r)
                   (resolve-symbol st "target")
                 (and r (= #x0850 v))))))))

(deftest test/forward-ref-undefined-pass2-error
  ;; En pass 2, un symbole absent doit déclencher asm-undefined-label
  (let ((st (make-st :pass 2 :pc #x0800)))
    (check-error "pass 2 : symbole indéfini → asm-undefined-label"
                 asm-undefined-label
                 (resolve-symbol st "ghost"))))


;;; --------------------------------------------------------------------------
;;;  Tests : portées locales
;;; --------------------------------------------------------------------------

(deftest test/local-scope-isolation
  (let ((st (make-st :pc #x1000)))
    (define-label st "outer")
    (with-local-scope (st)
      (set-pc st #x1010)
      (define-label st "inner")
      (check "inner visible depuis portée locale"
             (symbol-defined-p st "inner"))
      (check "outer visible depuis portée locale (remontée)"
             (symbol-defined-p st "outer")))
    ;; Aprés depilage, "inner" ne doit plus être visible
    (check "inner invisible depuis portée parente"
           (not (symbol-defined-p st "inner")))
    (check "outer toujours visible"
           (symbol-defined-p st "outer"))))

(deftest test/local-scope-shadowing
  ;; Un label local peut masquer un label de méme nom dans une portée parente
  (let ((st (make-st :pc #x0000)))
    (define-label st "x")          ; x = #x0000 globalement
    (with-local-scope (st)
      (set-pc st #x0100)
      (define-label st "x")        ; x = #x0100 localement
      (multiple-value-bind (val _) (resolve-symbol st "x")
        (declare (ignore _))
        (check "portée locale : x = #x0100 (masquage)"
               (= #x0100 val))))
    ;; Retour à la portée globale
    (multiple-value-bind (val _) (resolve-symbol st "x")
      (declare (ignore _))
      (check "portée globale : x = #x0000 (restauré)"
             (= #x0000 val)))))

(deftest test/nested-local-scopes
  ;; Trois niveaux d'imbrication
  (let ((st (make-st :pc #x0000)))
    (define-constant st "A" 1)
    (with-local-scope (st)
      (define-constant st "B" 2)
      (with-local-scope (st)
        (define-constant st "C" 3)
        (check "A visible niveau 3" (symbol-defined-p st "A"))
        (check "B visible niveau 3" (symbol-defined-p st "B"))
        (check "C visible niveau 3" (symbol-defined-p st "C")))
      (check "A visible niveau 2" (symbol-defined-p st "A"))
      (check "B visible niveau 2" (symbol-defined-p st "B"))
      (check "C invisible niveau 2" (not (symbol-defined-p st "C"))))
    (check "A visible niveau 1"  (symbol-defined-p st "A"))
    (check "B invisible niveau 1" (not (symbol-defined-p st "B")))
    (check "C invisible niveau 1" (not (symbol-defined-p st "C")))))

(deftest test/with-local-scope-unwind-on-error
  ;; with-local-scope doit dépiler méme si le body signalé une condition.
  ;; On passe une variable intermédiaire à with-local-scope pour éviter
  ;; le rebind inutilisé? : le body ne touche pas la table, il fait juste error.
  (let ((st (make-st)))
    (let ((depth-before (length (st-scope-stack st)))
          (st-ref st))                  ; alias explicite passé à la macro
      (ignore-errors
        (with-local-scope (st-ref)
          (error "erreur simulée")))
      (check "pile restaurée après condition dans with-local-scope"
             (= depth-before (length (st-scope-stack st)))))))


;;; --------------------------------------------------------------------------
;;;  Tests : labels numériques
;;; --------------------------------------------------------------------------

(deftest test/numeric-label-backward
  (let ((st (make-st :pc #x1000)))
    (define-numeric-label st 1)       ; 1: à $1000
    (set-pc st #x1010)
    (define-numeric-label st 1)       ; 1: à $1010
    (set-pc st #x1020)
    ;; 1- depuis $1020 doit retourner $1010 (le plus récent)
    (let ((addr (resolve-numeric-label st 1 :backward)))
      (check "1- = adresse du 1: précédent le plus proche"
             (= #x1010 addr)))))

(deftest test/numeric-label-forward
  (let ((st (make-st :pc #x1000)))
    (set-pc st #x1010)
    (define-numeric-label st 2)       ; 2: à $1010
    (set-pc st #x1020)
    (define-numeric-label st 2)       ; 2: à $1020
    ;; 2+ depuis $1000 doit retourner $1010 (le plus proche après)
    (set-pc st #x1000)
    (let ((addr (resolve-numeric-label st 2 :forward)))
      (check "2+ = adresse du 2: suivant le plus proche"
             (= #x1010 addr)))))

(deftest test/numeric-label-backward-not-found-pass2
  (let ((st (make-st :pass 2 :pc #x1000)))
    (check-error "1- introuvable en pass 2 → asm-undefined-label"
                 asm-undefined-label
                 (resolve-numeric-label st 1 :backward))))

(deftest test/numeric-label-different-numbers-dont-clash
  (let ((st (make-st :pc #x0000)))
    (set-pc st #x0100)
    (define-numeric-label st 1)
    (set-pc st #x0200)
    (define-numeric-label st 2)
    ;; 1- depuis $0300 doit retourner $0100, pas $0200
    (set-pc st #x0300)
    (check "labels numériques différents ne se croisent pas"
           (= #x0100 (resolve-numeric-label st 1 :backward)))))


;;; --------------------------------------------------------------------------
;;;  Tests : relocations
;;; --------------------------------------------------------------------------

(deftest test/add-and-resolve-relocation
  (let ((st (make-st :pc #x0810)))
    ;; déclare un symbole qui n'est pas encore connu
    ;; On simule une relocation vers "irq_handler"
    (add-relocation st "irq_handler" :abs16)
    (check "une relocation enregistrée"
           (= 1 (length (st-relocations st))))
    ;; Maintenant on définit le symbole
    (set-pc st #xE000)
    (define-label st "irq_handler")
    ;; Résolution
    (multiple-value-bind (resolved unresolved)
        (resolve-relocations st)
      (check "relocation résolue"
             (= 1 (length resolved)))
      (check "aucune relocation non résolue"
             (null unresolved)))))

(deftest test/unresolved-relocation
  (let ((st (make-st :pc #x0810)))
    (add-relocation st "ghost_symbol" :abs16)
    (multiple-value-bind (resolved unresolved)
        (resolve-relocations st)
      (check "aucune relocation résolue"
             (null resolved))
      (check "une relocation non résolue"
             (= 1 (length unresolved))))))


;;; --------------------------------------------------------------------------
;;;  Tests : utilitaires
;;; --------------------------------------------------------------------------

(deftest test/symbol-defined-p
  (let ((st (make-st :pc #x1000)))
    (check "symbole inexistant → nil"
           (not (symbol-defined-p st "nope")))
    (define-label st "yes")
    (check "symbole défini → t"
           (symbol-defined-p st "yes"))))

(deftest test/list-symbols-filter
  (let ((st (make-st)))
    (set-pc st #x0810) (define-label st "lbl1" :global t)
    (set-pc st #x0820) (define-label st "lbl2")
    (define-constant st "C1" 42 :global t)
    (define-constant st "C2" 99)
    (let ((labels    (list-symbols st :kind :label))
          (constants (list-symbols st :kind :constant))
          (globals   (list-symbols st :global-only t)))
      (check "2 labels"    (= 2 (length labels)))
      (check "2 constantes" (= 2 (length constants)))
      (check "2 globaux"   (= 2 (length globals))))))

(deftest test/dump-does-not-error
  (let ((st (make-st)))
    (set-pc st #x0801) (define-label st "start" :global t)
    (define-constant st "COLS" 40)
    (check "dump-symbol-table s'exécute sans erreur"
           (progn
             (with-output-to-string (s)
               (dump-symbol-table st s))
             t))))

(deftest test/warn-unused
  (let ((st (make-st)))
    (set-pc st #x0810) (define-label st "used")
    (set-pc st #x0820) (define-label st "dead")
    ;; On référence "used" → seul "dead" reste inutilisé?
    (resolve-symbol st "used")
    ;; warn-unused-symbols retourne la liste des noms inutilisé?s ET
    ;; écrit dans le stream. On capture les deux séparément.
    (let* ((unused nil)
           (output (with-output-to-string (s)
                     (setf unused (warn-unused-symbols st s)))))
      (declare (ignore output))
      (check "1 label inutilisé? détecté"
             (= 1 (length unused)))
      (check "c'est bien 'dead'"
             (string= "dead" (first unused))))))

(deftest test/begin-pass-2-resets-pc
  (let ((st (make-st :pc #x1234 :section :data)))
    (begin-pass-2 st)
    (check "PC remis à 0 en début de pass 2"
           (= 0 (st-current-pc st)))
    (check "section remise à :text"
           (eq :text (st-current-section st)))
    (check "pass = 2"
           (= 2 (st-current-pass st)))))

(deftest test/label-does-not-conflict-with-constant
  ;; Un label dont le nom diffère d'une constante ne doit pas déclencher
  ;; d'erreur, même si la normalisation uppercase donne un préfixe commun.
  ;; Ex: COLOR = $D800 (constante) puis COLOR_LOOP: (label) -> pas de conflit.
  (let ((st (make-st)))
    (define-constant st "COLOR" #xD800)
    (check "constante COLOR définie"
           (symbol-defined-p st "COLOR"))
    (check "define-label COLOR_LOOP ne plante pas"
           (progn (define-label st "COLOR_LOOP") t))
    (check "COLOR_LOOP est un label"
           (symbol-defined-p st "COLOR_LOOP"))
    (check "COLOR est toujours une constante à $D800"
           (= #xD800 (resolve-symbol st "COLOR")))))

(deftest test/label-same-name-as-constant-ignored
  ;; Si un label porte exactement le même nom qu'une constante déjà définie,
  ;; define-label l'ignore silencieusement (la constante a priorité).
  (let ((st (make-st :pc #x0810)))
    (define-constant st "SCREEN" #x0400)
    (check "define-label SCREEN ignoré silencieusement"
           (progn (define-label st "SCREEN") t))
    (check "SCREEN vaut toujours $0400 (constante, pas le PC)"
           (= #x0400 (resolve-symbol st "SCREEN")))))


;;; --------------------------------------------------------------------------
;;;  Lanceur global
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests cl-asm/symbol-table ===~%")
  (test/define-label-basic)
  (test/define-label-global)
  (test/define-label-redefinition-pass1-error)
  (test/define-label-pass2-value-stable)
  (test/define-label-pass2-value-changed)
  (test/define-constant-basic)
  (test/define-constant-redefinition-error)
  (test/equate-simple)
  (test/equate-lo-hi)
  (test/forward-ref-pass1)
  (test/forward-ref-resolved-in-pass2)
  (test/forward-ref-undefined-pass2-error)
  (test/local-scope-isolation)
  (test/local-scope-shadowing)
  (test/nested-local-scopes)
  (test/with-local-scope-unwind-on-error)
  (test/numeric-label-backward)
  (test/numeric-label-forward)
  (test/numeric-label-backward-not-found-pass2)
  (test/numeric-label-different-numbers-dont-clash)
  (test/add-and-resolve-relocation)
  (test/unresolved-relocation)
  (test/symbol-defined-p)
  (test/list-symbols-filter)
  (test/dump-does-not-error)
  (test/warn-unused)
  (test/begin-pass-2-resets-pc)
  (test/label-does-not-conflict-with-constant)
  (test/label-same-name-as-constant-ignored)
  (when *failures*
    (format t "~&Échecs symbol-table :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
