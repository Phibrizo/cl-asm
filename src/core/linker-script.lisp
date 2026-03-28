; -*- coding: utf-8 -*-
(defpackage #:cl-asm/linker-script
  (:use #:cl)
  (:export
   ;; script-segment
   #:script-segment
   #:make-script-segment
   #:script-segment-name
   #:script-segment-at
   #:script-segment-units
   #:script-segment-fill
   ;; script-result
   #:script-result
   #:make-script-result
   #:script-result-name
   #:script-result-address
   #:script-result-bytes
   ;; fonctions principales
   #:link-segments
   #:segments->flat-binary))

;;; src/core/linker-script.lisp
;;;
;;; Linker script : placement multi-segments à des adresses distinctes.
;;;
;;; Principe :
;;;   Chaque SCRIPT-SEGMENT décrit un groupe de LINK-UNITs à placer à une
;;;   adresse mémoire donnée.  LINK-SEGMENTS crée une table de symboles
;;;   partagée, exécute la passe 1 sur tous les segments (dans l'ordre),
;;;   puis la passe 2, permettant les références croisées inter-segments.
;;;
;;;   SEGMENTS->FLAT-BINARY assemble les résultats en un vecteur contigu,
;;;   en remplissant les trous avec un octet de remplissage.
;;;
;;; Usage typique :
;;;
;;;   (let* ((u1 (link-unit-from-program "main" (parse-file "main.asm") :6502))
;;;          (u2 (link-unit-from-program "irq"  (parse-file "irq.asm")  :6502))
;;;          (segs (list (make-script-segment :name "main" :at #x0800 :units (list u1))
;;;                      (make-script-segment :name "irq"  :at #xFFFE :units (list u2)))))
;;;     (multiple-value-bind (bytes base)
;;;         (segments->flat-binary (link-segments segs))
;;;       (write-bin bytes "/tmp/out.bin")))

(in-package #:cl-asm/linker-script)

;;; --------------------------------------------------------------------------
;;;  Structures
;;; --------------------------------------------------------------------------

(defstruct script-segment
  "Description d'un segment pour le linker script.
   NAME  : identifiant lisible (ex. \"main\", \"irq\", \"rodata\")
   AT    : adresse de chargement (entier)
   UNITS : liste de LINK-UNITs (cf. cl-asm/linker:link-unit)
   FILL  : octet de remplissage intra-segment (réservé pour alignement futur)"
  (name  "" :type string)
  (at    0  :type integer)
  units
  (fill  0  :type (unsigned-byte 8)))

(defstruct script-result
  "Résultat de l'assemblage d'un segment.
   NAME    : identifiant du segment source
   ADDRESS : adresse de chargement effective
   BYTES   : vecteur (unsigned-byte 8) des octets encodés"
  (name    "" :type string)
  (address 0  :type integer)
  bytes)

;;; --------------------------------------------------------------------------
;;;  Helpers internes
;;; --------------------------------------------------------------------------

(defun %collect-sections (segment)
  "Retourne toutes les sections IR du segment, en préservant l'ordre des unités."
  (mapcan (lambda (u)
            (copy-list (cl-asm/linker:link-unit-sections u)))
          (script-segment-units segment)))

(defun %resolve-target (segments explicit-target)
  "Détermine le target effectif : EXPLICIT-TARGET ou celui du premier unit du premier segment."
  (or explicit-target
      (let ((first-seg (first segments)))
        (when (script-segment-units first-seg)
          (cl-asm/linker:link-unit-target
           (first (script-segment-units first-seg)))))))

;;; --------------------------------------------------------------------------
;;;  Fonction principale : LINK-SEGMENTS
;;; --------------------------------------------------------------------------

(defun link-segments (segments &key target)
  "Lie plusieurs segments à des adresses distinctes avec une table de symboles partagée.

   SEGMENTS : liste non vide de SCRIPT-SEGMENTs (l'ordre détermine la priorité des labels).
   TARGET   : mot-clé de backend optionnel (:6502, :65c02, etc.).
              Si omis, déduit du premier unit du premier segment.

   Retourne une liste de SCRIPT-RESULTs dans le même ordre que SEGMENTS.
   Les références croisées inter-segments sont résolues dans la table partagée."
  (when (null segments)
    (error "LINK-SEGMENTS : liste de segments vide."))
  (let* ((effective-target (%resolve-target segments target))
         (backend (cl-asm/linker:find-linker-backend effective-target)))
    (unless backend
      (error "LINK-SEGMENTS : backend de linkage inconnu pour la cible ~A.~%~
              Backends disponibles : ~{~A~^, ~}"
             effective-target
             (mapcar #'cl-asm/linker:linker-backend-entry-keyword
                     (cl-asm/linker:all-linker-backends))))
    ;; Table de symboles partagée entre tous les segments
    (let ((symtable (cl-asm/symbol-table:make-symbol-table)))
      ;; --- Passe 1 : enregistrement des labels de tous les segments ---
      (dolist (seg segments)
        (let ((sections (%collect-sections seg))
              (at (script-segment-at seg)))
          (setf (cl-asm/symbol-table:st-current-pc symtable) at)
          (funcall (cl-asm/linker:linker-backend-entry-pass-1-fn backend)
                   sections symtable at)))
      ;; --- Transition vers la passe 2 ---
      (cl-asm/symbol-table:begin-pass-2 symtable)
      ;; --- Passe 2 : encodage de chaque segment dans son espace d'adresses ---
      (mapcar (lambda (seg)
                (let* ((sections (%collect-sections seg))
                       (at (script-segment-at seg)))
                  (setf (cl-asm/symbol-table:st-current-pc symtable) at)
                  (make-script-result
                   :name    (script-segment-name seg)
                   :address at
                   :bytes   (funcall
                              (cl-asm/linker:linker-backend-entry-pass-2-fn backend)
                              sections symtable at))))
              segments))))

;;; --------------------------------------------------------------------------
;;;  Utilitaire : SEGMENTS->FLAT-BINARY
;;; --------------------------------------------------------------------------

(defun segments->flat-binary (results &key (fill #x00))
  "Assemble une liste de SCRIPT-RESULTs en un vecteur contigu (unsigned-byte 8).
   Les trous entre segments sont remplis avec l'octet FILL (#x00 par défaut).

   Retourne (values bytes base-address) :
     BYTES        : vecteur de BASE-ADDRESS au dernier octet du dernier segment
     BASE-ADDRESS : adresse la plus basse parmi tous les résultats"
  (when (null results)
    (return-from segments->flat-binary (values #() 0)))
  (let* ((base (reduce #'min results :key #'script-result-address))
         (end  (reduce #'max results
                       :key (lambda (r)
                              (+ (script-result-address r)
                                 (length (script-result-bytes r))))))
         (size (- end base))
         (buf  (make-array size
                           :element-type '(unsigned-byte 8)
                           :initial-element fill)))
    (dolist (r results)
      (let ((offset (- (script-result-address r) base))
            (bytes  (script-result-bytes r)))
        (replace buf bytes :start1 offset)))
    (values buf base)))
