; -*- coding: utf-8 -*-
(defpackage #:cl-asm/backend.45gs02
  (:use #:cl)
  (:export
   #:assemble-45gs02 #:assemble-string-45gs02 #:assemble-file-45gs02
   #:lookup-45gs02 #:find-clause-45gs02
   #:encode-instruction-45gs02 #:resolve-mode-45gs02
   #:*instructions-45gs02*))
;;; src/backend/45gs02.lisp
;;;
;;; Backend d'assemblage pour le processeur 45GS02 (Mega65).
;;;
;;; Le 45GS02 est un superset du 6502/6510. Ce backend etend le
;;; backend 6502 avec :
;;;
;;;   1. Nouveaux modes d'adressage
;;;      :zero-page-z     LDA $10,Z          2 octets
;;;      :absolute-z      LDA $1234,Z        3 octets
;;;      :indirect-z      LDA ($00),Z        2 octets
;;;      :indirect-32     LDA [$00]          2 octets  (ptr 32 bits)
;;;      :indirect-32-z   LDA [$00],Z        2 octets  (ptr 32 bits + Z)
;;;      :indirect-sp-y   LDA ($00,SP),Y     2 octets
;;;
;;;   2. Instructions exclusives 45GS02
;;;      Registres supplementaires : Z (compteur 8 bits), B (base page),
;;;      registre Q 32 bits (A:X:Y:Z concatenes).
;;;
;;;   3. Encodage avec prefixes
;;;      Prefixe $42       : active certains modes etendus
;;;      Prefixe $42 $42   : instruction Q (32 bits, registre A:X:Y:Z)
;;;      Prefixe $EA       : NOP prefixe (pseudo-NOP, padding)
;;;
;;;   Chaque clause d'instruction peut avoir un champ :prefix qui
;;;   liste les octets a emettre avant l'opcode principal.
;;;
;;;   (:mode :implied :opcode #xXX :bytes N :prefix (#x42 #x42))


(in-package #:cl-asm/backend.45gs02)

(declaim (ftype (function (t t t) t)
                process-directive-pass1-45 eval-operand-value-45))
(declaim (ftype (function (t t t t) t) process-directive-pass2-45))


;;; --------------------------------------------------------------------------
;;;  Table des instructions 45GS02
;;;
;;;  On construit d'abord une copie de la table 6502, puis on y ajoute
;;;  les instructions et modes supplementaires.
;;; --------------------------------------------------------------------------

(defun build-45gs02-table ()
  "Construit la table d'instructions 45GS02 complete."
  (let ((tbl (make-hash-table :test #'equal)))

    ;; -----------------------------------------------------------------------
    ;; Copier toutes les instructions 6502
    ;; -----------------------------------------------------------------------
    (maphash (lambda (k v)
               (setf (gethash k tbl) (copy-list v)))
             cl-asm/backend.6502:*instructions*)

    (flet ((add (mn &rest clauses)
             "Ajoute ou remplace les clauses de MN dans la table."
             (setf (gethash mn tbl) clauses))
           (add-mode (mn &rest new-clauses)
             "Ajoute des modes supplementaires a un mnemonique existant."
             (let ((existing (gethash mn tbl)))
               (setf (gethash mn tbl)
                     (append existing new-clauses)))))

      ;; -----------------------------------------------------------------------
      ;; Extensions de modes pour les instructions LDA/STA/ADC/SBC/CMP/AND/ORA/EOR
      ;; -----------------------------------------------------------------------
      ;;
      ;; Mode :indirect-z   : LDA ($nn),Z  -- opcode identique a indirect-y
      ;;                       mais avec le registre Z comme index
      ;; Mode :indirect-32  : LDA [$nn]    -- deref 32 bits (prefixe $EA)
      ;; Mode :indirect-32-z: LDA [$nn],Z  -- deref 32 bits + Z (prefixe $EA)

      (dolist (mn '("LDA" "STA" "ADC" "SBC" "CMP" "AND" "ORA" "EOR"))
        (let ((iy-opcode (cl-asm/backend.6502:clause-opcode
                          (cl-asm/backend.6502:find-clause mn :indirect-y))))
          (when iy-opcode
            (add-mode mn
                      ;; ($nn),Z  -- meme opcode que ($nn),Y
                      (list :mode :indirect-z
                            :opcode iy-opcode
                            :bytes 2 :cycles 5)
                      ;; [$nn]    -- prefixe $EA + opcode indirect-y
                      (list :mode :indirect-32
                            :opcode iy-opcode
                            :prefix '(#xEA)
                            :bytes 3 :cycles 6)
                      ;; [$nn],Z  -- prefixe $EA + opcode indirect-y
                      (list :mode :indirect-32-z
                            :opcode iy-opcode
                            :prefix '(#xEA)
                            :bytes 3 :cycles 6)))))

      ;; Mode :absolute-z et :zero-page-z pour LDA/STA/ADC/SBC/CMP/AND/ORA/EOR
      (dolist (mn '("LDA" "STA" "ADC" "SBC" "CMP" "AND" "ORA" "EOR"))
        (let ((ay-op (cl-asm/backend.6502:clause-opcode
                      (cl-asm/backend.6502:find-clause mn :absolute-y)))
              (zy-op (cl-asm/backend.6502:clause-opcode
                      (cl-asm/backend.6502:find-clause mn :zero-page-y))))
          (when ay-op
            (add-mode mn
                      (list :mode :absolute-z
                            :opcode ay-op
                            :bytes 3 :cycles 4)))
          (when zy-op
            (add-mode mn
                      (list :mode :zero-page-z
                            :opcode zy-op
                            :bytes 2 :cycles 4)))))

      ;; -----------------------------------------------------------------------
      ;; Registre Z — instructions de gestion
      ;; -----------------------------------------------------------------------
      (add "LDZ"
           '(:mode :immediate   :opcode #xA3 :bytes 2 :cycles 2)
           '(:mode :absolute    :opcode #xAB :bytes 3 :cycles 4)
           '(:mode :absolute-x  :opcode #xBB :bytes 3 :cycles 4))
      (add "STZ"
           ;; STZ sur 45GS02 : store Z (different de STZ 65C02 qui store zero)
           '(:mode :zero-page   :opcode #x84 :bytes 2 :cycles 3)   ; STZ zp
           '(:mode :zero-page-x :opcode #x94 :bytes 2 :cycles 4)   ; STZ zp,X
           '(:mode :absolute    :opcode #x9C :bytes 3 :cycles 4)   ; STZ abs
           '(:mode :absolute-x  :opcode #x9E :bytes 3 :cycles 5))  ; STZ abs,X
      (add "INZ"  '(:mode :implied :opcode #x1B :bytes 1 :cycles 2))
      (add "DEZ"  '(:mode :implied :opcode #x3B :bytes 1 :cycles 2))
      (add "PHZ"  '(:mode :implied :opcode #xDB :bytes 1 :cycles 3))
      (add "PLZ"  '(:mode :implied :opcode #xFB :bytes 1 :cycles 4))
      (add "TAZ"  '(:mode :implied :opcode #x4B :bytes 1 :cycles 2))
      (add "TZA"  '(:mode :implied :opcode #x6B :bytes 1 :cycles 2))

      ;; -----------------------------------------------------------------------
      ;; Registre B (base page register)
      ;; -----------------------------------------------------------------------
      (add "TBA"  '(:mode :implied :opcode #xCB :bytes 1 :cycles 2))
      (add "TAB"  '(:mode :implied :opcode #x5B :bytes 1 :cycles 2))

      ;; -----------------------------------------------------------------------
      ;; Decalages et rotations supplementaires
      ;; -----------------------------------------------------------------------
      (add "NEG"
           '(:mode :accumulator :opcode #x42 :bytes 1 :cycles 2))
      (add "ASR"
           '(:mode :accumulator :opcode #x43 :bytes 1 :cycles 2)
           '(:mode :zero-page   :opcode #x44 :bytes 2 :cycles 5)
           '(:mode :zero-page-x :opcode #x54 :bytes 2 :cycles 6))

      ;; -----------------------------------------------------------------------
      ;; Instructions de largeur de bus (16/32 bits sur les adresses)
      ;; -----------------------------------------------------------------------
      ;; INW / DEW — increment/decrement d'un mot 16 bits en memoire
      (add "INW"
           '(:mode :zero-page   :opcode #xE3 :bytes 2 :cycles 6))
      (add "DEW"
           '(:mode :zero-page   :opcode #xC3 :bytes 2 :cycles 6))
      ;; ASW / ROW — arithmetic shift / rotate word
      (add "ASW"
           '(:mode :absolute    :opcode #xCB :bytes 3 :cycles 6))  ; attention : conflit TBA
      (add "ROW"
           '(:mode :absolute    :opcode #xEB :bytes 3 :cycles 6))

      ;; -----------------------------------------------------------------------
      ;; Branchements etendus (16 bits, prefixe $42)
      ;; -----------------------------------------------------------------------
      ;; Les branches relatives 16 bits permettent de sauter sur -32768..+32767
      (add "LBCC" '(:mode :relative16 :opcode #x90 :prefix (#x42) :bytes 4 :cycles 3))
      (add "LBCS" '(:mode :relative16 :opcode #xB0 :prefix (#x42) :bytes 4 :cycles 3))
      (add "LBEQ" '(:mode :relative16 :opcode #xF0 :prefix (#x42) :bytes 4 :cycles 3))
      (add "LBNE" '(:mode :relative16 :opcode #xD0 :prefix (#x42) :bytes 4 :cycles 3))
      (add "LBMI" '(:mode :relative16 :opcode #x30 :prefix (#x42) :bytes 4 :cycles 3))
      (add "LBPL" '(:mode :relative16 :opcode #x10 :prefix (#x42) :bytes 4 :cycles 3))
      (add "LBVC" '(:mode :relative16 :opcode #x50 :prefix (#x42) :bytes 4 :cycles 3))
      (add "LBVS" '(:mode :relative16 :opcode #x70 :prefix (#x42) :bytes 4 :cycles 3))

      ;; -----------------------------------------------------------------------
      ;; Instructions Q (32 bits) — prefixe $42 $42
      ;; -----------------------------------------------------------------------
      ;; Le registre Q = A:X:Y:Z concatenes (32 bits, little-endian : Z=MSB, A=LSB)
      ;; L'instruction encodee est : $42 $42 <opcode-LDA-equvalent>
      (add "LDQ"
           '(:mode :indirect-z  :opcode #xB2 :prefix (#x42 #x42) :bytes 4 :cycles 8)
           '(:mode :indirect-32 :opcode #xB2 :prefix (#x42 #x42 #xEA) :bytes 5 :cycles 9)
           '(:mode :zero-page   :opcode #xA5 :prefix (#x42 #x42) :bytes 4 :cycles 6)
           '(:mode :absolute    :opcode #xAD :prefix (#x42 #x42) :bytes 5 :cycles 8))
      (add "STQ"
           '(:mode :indirect-z  :opcode #x92 :prefix (#x42 #x42) :bytes 4 :cycles 8)
           '(:mode :indirect-32 :opcode #x92 :prefix (#x42 #x42 #xEA) :bytes 5 :cycles 9)
           '(:mode :zero-page   :opcode #x85 :prefix (#x42 #x42) :bytes 4 :cycles 6)
           '(:mode :absolute    :opcode #x8D :prefix (#x42 #x42) :bytes 5 :cycles 8))
      (add "ADCQ"
           '(:mode :indirect-z  :opcode #x72 :prefix (#x42 #x42) :bytes 4 :cycles 8)
           '(:mode :zero-page   :opcode #x65 :prefix (#x42 #x42) :bytes 4 :cycles 6))
      (add "SBCQ"
           '(:mode :indirect-z  :opcode #xF2 :prefix (#x42 #x42) :bytes 4 :cycles 8)
           '(:mode :zero-page   :opcode #xE5 :prefix (#x42 #x42) :bytes 4 :cycles 6))
      (add "ANDQ"
           '(:mode :indirect-z  :opcode #x32 :prefix (#x42 #x42) :bytes 4 :cycles 8)
           '(:mode :zero-page   :opcode #x25 :prefix (#x42 #x42) :bytes 4 :cycles 6))
      (add "ORAQ"
           '(:mode :indirect-z  :opcode #x12 :prefix (#x42 #x42) :bytes 4 :cycles 8)
           '(:mode :zero-page   :opcode #x05 :prefix (#x42 #x42) :bytes 4 :cycles 6))
      (add "EORQ"
           '(:mode :indirect-z  :opcode #x52 :prefix (#x42 #x42) :bytes 4 :cycles 8)
           '(:mode :zero-page   :opcode #x45 :prefix (#x42 #x42) :bytes 4 :cycles 6))
      (add "ASLQ"
           '(:mode :accumulator :opcode #x0A :prefix (#x42 #x42) :bytes 3 :cycles 4)
           '(:mode :zero-page   :opcode #x06 :prefix (#x42 #x42) :bytes 4 :cycles 8))
      (add "LSRQ"
           '(:mode :accumulator :opcode #x4A :prefix (#x42 #x42) :bytes 3 :cycles 4)
           '(:mode :zero-page   :opcode #x46 :prefix (#x42 #x42) :bytes 4 :cycles 8))
      (add "ROLQ"
           '(:mode :accumulator :opcode #x2A :prefix (#x42 #x42) :bytes 3 :cycles 4)
           '(:mode :zero-page   :opcode #x26 :prefix (#x42 #x42) :bytes 4 :cycles 8))
      (add "RORQ"
           '(:mode :accumulator :opcode #x6A :prefix (#x42 #x42) :bytes 3 :cycles 4)
           '(:mode :zero-page   :opcode #x66 :prefix (#x42 #x42) :bytes 4 :cycles 8))
      (add "ASRQ"
           '(:mode :accumulator :opcode #x43 :prefix (#x42 #x42) :bytes 3 :cycles 4)
           '(:mode :zero-page   :opcode #x44 :prefix (#x42 #x42) :bytes 4 :cycles 8))
      (add "BITQ"
           '(:mode :zero-page   :opcode #x24 :prefix (#x42 #x42) :bytes 4 :cycles 6))
      (add "CMPQ"
           '(:mode :indirect-z  :opcode #xD2 :prefix (#x42 #x42) :bytes 4 :cycles 8)
           '(:mode :zero-page   :opcode #xC5 :prefix (#x42 #x42) :bytes 4 :cycles 6))

      ;; -----------------------------------------------------------------------
      ;; Instructions speciales
      ;; -----------------------------------------------------------------------
      (add "MAP"  '(:mode :implied :opcode #x5C :bytes 1 :cycles 4))
      (add "EOM"  '(:mode :implied :opcode #xEA :bytes 1 :cycles 1))

      ;; Transferts supplementaires
      (add "TSY"  '(:mode :implied :opcode #x0B :bytes 1 :cycles 2))
      (add "TYS"  '(:mode :implied :opcode #x2B :bytes 1 :cycles 2)))

    tbl))

(defparameter *instructions-45gs02*
  (build-45gs02-table)
  "Table des instructions 45GS02 complete (superset 6502).")


;;; --------------------------------------------------------------------------
;;;  Helpers
;;; --------------------------------------------------------------------------

(defun lookup-45gs02 (mnemonic)
  "Retourne les clauses pour MNEMONIC dans la table 45GS02."
  (gethash (string-upcase mnemonic) *instructions-45gs02*))

(defun find-clause-45gs02 (mnemonic mode)
  "Retourne la clause pour MNEMONIC en MODE dans la table 45GS02."
  (find mode (lookup-45gs02 mnemonic)
        :key #'cl-asm/backend.6502:clause-mode))

(defun clause-prefix (c)
  "Retourne la liste de prefixes d'une clause, ou NIL."
  (getf c :prefix))


;;; --------------------------------------------------------------------------
;;;  Resolution du mode d'adressage 45GS02
;;; --------------------------------------------------------------------------

(defun resolve-mode-45gs02 (operand addr-value)
  "Determine le mode d'adressage 45GS02.
   Etend resolve-mode avec les modes Z, 32 bits et pile."
  (when (null operand)
    (return-from resolve-mode-45gs02 :implied))
  (let ((kind    (cl-asm/ir:ir-operand-kind     operand))
        (idx-reg (cl-asm/ir:ir-operand-index-reg operand))
        (hint    (cl-asm/ir:ir-operand-size-hint operand)))
    (ecase kind
      (:register    :accumulator)
      (:immediate   :immediate)
      ;; Indirect simple (parentheses) ou 32 bits (crochets)
      (:indirect
       :indirect)
      (:indirect-32
       :indirect-32)
      ;; Pre-indexe
      (:indirect-x  :indirect-x)
      ;; Post-indexe : ,Y ou ,Z selon le registre
      (:indirect-y
       (ecase (or idx-reg :y)
         (:y :indirect-y)
         (:z :indirect-z)))
      ;; Post-indexe 32 bits
      (:indirect-32-z
       :indirect-32-z)
      ;; Relatif pile
      (:indirect-sp-y :indirect-sp-y)
      ;; Direct : choix parmi plusieurs modes selon valeur et registre
      (:direct
       (let ((zp (and addr-value
                      (not (eq hint :word))
                      (<= 0 addr-value 255))))
         (ecase (or idx-reg :none)
           (:none  (if zp :zero-page  :absolute))
           (:x     (if zp :zero-page-x :absolute-x))
           (:y     (if zp :zero-page-y :absolute-y))
           (:z     (if zp :zero-page-z :absolute-z))))))))


;;; --------------------------------------------------------------------------
;;;  Encodage d'une instruction 45GS02
;;; --------------------------------------------------------------------------

(defun encode-relative16 (target-addr current-pc loc)
  "Calcule l'offset 16 bits signe pour une branche longue.
   L'offset est relatif a l'adresse de l'instruction suivante (PC+4)."
  (let ((offset (- target-addr (+ current-pc 4))))
    (unless (<= -32768 offset 32767)
      (error 'cl-asm/ir:asm-range-error
             :value  offset
             :bits   16
             :message (format nil
                               "Branche longue hors portee : offset ~D" offset)
             :source-loc loc))
    (let ((u (logand offset #xFFFF)))
      (list (logand u #xFF) (logand (ash u -8) #xFF)))))

(defun encode-instruction-45gs02 (instr symtable pc pass)
  "Encode INSTR pour le 45GS02. Retourne (values LISTE-OCTETS TAILLE)."
  (let* ((mn      (cl-asm/ir:ir-instruction-mnemonic  instr))
         (ops     (cl-asm/ir:ir-instruction-operands   instr))
         (operand (first ops))
         (loc     (cl-asm/ir:ir-instruction-loc        instr)))

    ;; Valider le mnemonique (table 45GS02 en premier, puis 6502)
    (unless (lookup-45gs02 mn)
      (error 'cl-asm/ir:asm-unknown-mnemonic
             :mnemonic mn
             :message  (format nil "Mnemonique inconnu : ~A" mn)
             :source-loc loc))

    ;; Evaluer la valeur de l'operande
    (multiple-value-bind (addr-val resolved)
        (cl-asm/backend.6502:eval-operand-value operand symtable pc)

      ;; Determiner le mode
      (let* ((mode   (resolve-mode-45gs02 operand (if resolved addr-val nil)))
             (clause (find-clause-45gs02 mn mode)))

        ;; Passe 1, forward-ref : estimer la taille maximale
        (when (and (not resolved) (= pass 1))
          (let* ((clauses (lookup-45gs02 mn))
                 (max-bytes (reduce #'max clauses
                                    :key #'cl-asm/backend.6502:clause-bytes
                                    :initial-value 1))
                 ;; Tenir compte des prefixes dans l'estimation
                 (max-prefix (reduce #'max clauses
                                     :key (lambda (c)
                                            (length (or (clause-prefix c) nil)))
                                     :initial-value 0))
                 (has-relative (find-clause-45gs02 mn :relative))
                 (has-relative16 (find-clause-45gs02 mn :relative16)))
            (cond
              (has-relative
               (return-from encode-instruction-45gs02 (values '(0 0) 2)))
              (has-relative16
               (return-from encode-instruction-45gs02 (values '(0 0 0 0) 4)))
              (t
               (let ((est (+ max-bytes max-prefix)))
                 (return-from encode-instruction-45gs02
                   (values (make-list est :initial-element 0) est)))))))

        ;; Verifier qu'on a un encodage
        (unless clause
          (when (and resolved (find-clause-45gs02 mn :relative))
            (setf mode :relative
                  clause (find-clause-45gs02 mn :relative)))
          (when (and resolved (find-clause-45gs02 mn :relative16))
            (setf mode :relative16
                  clause (find-clause-45gs02 mn :relative16)))
          (unless clause
            (error 'cl-asm/ir:asm-syntax-error
                   :message (format nil "~A : mode non supporte (~A)" mn mode)
                   :source-loc loc)))

        ;; Construire la liste d'octets : prefixes + opcode + operande
        (let* ((prefix  (or (clause-prefix clause) nil))
               (opcode  (cl-asm/backend.6502:clause-opcode clause))
               (octets  (append
                         prefix
                         (ecase mode
                           (:implied
                            (list opcode))
                           (:accumulator
                            (list opcode))
                           (:immediate
                            (list opcode (cl-asm/backend.6502:encode-byte addr-val)))
                           ((:zero-page :zero-page-x :zero-page-y :zero-page-z
                             :indirect-x :indirect-y :indirect-z
                             :indirect-32 :indirect-32-z :indirect-sp-y)
                            (list opcode (cl-asm/backend.6502:encode-byte addr-val)))
                           ((:absolute :absolute-x :absolute-y :absolute-z :indirect)
                            (cons opcode
                                  (cl-asm/backend.6502:encode-word-le addr-val)))
                           (:relative
                            (list opcode
                                  (cl-asm/backend.6502:encode-relative
                                   addr-val pc loc)))
                           (:relative16
                            (cons opcode
                                  (encode-relative16 addr-val pc loc)))))))
          (values octets (length octets)))))))


;;; --------------------------------------------------------------------------
;;;  Passes 1 et 2 pour le 45GS02
;;; --------------------------------------------------------------------------
;;;
;;; Ces fonctions sont identiques aux passes 6502 a ceci pres qu'elles
;;; utilisent encode-instruction-45gs02.

(defun process-directive-pass1-45 (directive symtable pc)
  "Identique a process-directive-pass1 du 6502."
  (cl-asm/backend.6502:process-directive-pass1 directive symtable pc))

(defun process-directive-pass2-45 (node symtable pc result)
  "Identique a process-directive-pass2 du 6502."
  (cl-asm/backend.6502:process-directive-pass2 node symtable pc result))

(defun pass-1-45gs02 (sections symtable origin)
  "Passe 1 pour le 45GS02."
  (let ((pc origin))
    (dolist (section sections)
      (when (cl-asm/ir:ir-section-origin section)
        (setf pc (cl-asm/ir:ir-section-origin section)))
      (dolist (node (cl-asm/ir:ir-section-nodes section))
        (typecase node
          (cl-asm/ir:ir-label
           (setf (cl-asm/symbol-table:st-current-pc symtable) pc)
           (cl-asm/symbol-table:define-label
            symtable
            (cl-asm/ir:ir-label-name node)
            :source-loc (cl-asm/ir:ir-label-loc node)))
          (cl-asm/ir:ir-instruction
           (multiple-value-bind (bytes nbytes)
               (encode-instruction-45gs02 node symtable pc 1)
             (declare (ignore bytes))
             (incf pc nbytes)))
          (cl-asm/ir:ir-directive
           (setf pc (process-directive-pass1-45 node symtable pc))))))
    pc))

(defun pass-2-45gs02 (sections symtable origin)
  "Passe 2 pour le 45GS02."
  (let ((result (make-array 0 :element-type '(unsigned-byte 8)
                              :adjustable t :fill-pointer 0))
        (pc origin))
    (dolist (section sections)
      (when (cl-asm/ir:ir-section-origin section)
        (setf pc (cl-asm/ir:ir-section-origin section)))
      (dolist (node (cl-asm/ir:ir-section-nodes section))
        (typecase node
          (cl-asm/ir:ir-label
           (setf (cl-asm/symbol-table:st-current-pc symtable) pc)
           (cl-asm/symbol-table:define-label
            symtable
            (cl-asm/ir:ir-label-name node)
            :source-loc (cl-asm/ir:ir-label-loc node)))
          (cl-asm/ir:ir-instruction
           (multiple-value-bind (bytes nbytes)
               (encode-instruction-45gs02 node symtable pc 2)
             (dolist (b bytes) (vector-push-extend b result))
             (incf pc nbytes)))
          (cl-asm/ir:ir-directive
           (setf pc (process-directive-pass2-45
                     node symtable pc result))))))
    result))


;;; --------------------------------------------------------------------------
;;;  Point d'entree public
;;; --------------------------------------------------------------------------

(defun assemble-45gs02 (program &key (origin #x2001) (section :text))
  "Assemble PROGRAM pour le 45GS02. Retourne un vecteur d'octets.
   ORIGIN : adresse de chargement par defaut ($2001 pour Mega65 BASIC)."
  (let* ((symtable (cl-asm/symbol-table:make-symbol-table))
         (sections (let ((main (cl-asm/ir:program-find-section
                                program section))
                         (rest (remove-if
                                (lambda (s)
                                  (eq (cl-asm/ir:ir-section-name s) section))
                                (cl-asm/ir:ir-program-sections program))))
                     (if main (cons main rest) rest))))
    (setf (cl-asm/symbol-table:st-current-pc symtable) origin)
    (pass-1-45gs02 sections symtable origin)
    (cl-asm/symbol-table:begin-pass-2 symtable)
    (setf (cl-asm/symbol-table:st-current-pc symtable) origin)
    (pass-2-45gs02 sections symtable origin)))

(defun assemble-string-45gs02 (source &key (origin #x2001))
  "Raccourci : parse SOURCE puis assemble pour le 45GS02."
  (let ((program (cl-asm/parser:parse-string source)))
    (assemble-45gs02 program :origin origin)))

(defun assemble-file-45gs02 (path &key (origin #x2001))
  "Raccourci : lit, parse et assemble le fichier à PATH pour le 45GS02."
  (let ((program (cl-asm/parser:parse-file path)))
    (assemble-45gs02 program :origin origin)))

(cl-asm/backends:register-backend
 :45gs02
 '("45gs02" "mega65")
 "CL-ASM/BACKEND.45GS02" "ASSEMBLE-FILE-45GS02"
 "Mega65 (45GS02)"
 "Mega65 (45GS02)")

(cl-asm/linker:register-linker-backend
 :45gs02
 '("45gs02" "mega65")
 (lambda (sections symtable origin) (pass-1-45gs02 sections symtable origin))
 (lambda (sections symtable origin) (pass-2-45gs02 sections symtable origin))
 "Mega65 (45GS02)")
