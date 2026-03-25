; -*- coding: utf-8 -*-
(defpackage #:cl-asm/backend.6502
  (:use #:cl)
  (:export
   #:assemble #:assemble-string #:assemble-file
   #:*instructions* #:lookup-instruction #:find-clause
   #:clause-mode #:clause-opcode #:clause-bytes
   #:resolve-mode #:encode-instruction
   #:encode-byte #:encode-word-le #:encode-relative
   #:eval-operand-value
   #:process-directive-pass1 #:process-directive-pass2))
;;; src/backend/6502.lisp
;;;
;;; Backend d'assemblage pour le processeur MOS 6502.
;;; Cible : Commodore 64, Apple II, et toute machine 6502.
;;;
;;; Ce module prend un IR-PROGRAM (produit par le parser) et produit
;;; un vecteur d'octets pret a etre ecrit dans un fichier binaire.
;;;
;;; Processus en deux passes :
;;;   Passe 1 : parcourt l'IR, enregistre les labels avec leur adresse,
;;;             estime la taille de chaque instruction.
;;;   Passe 2 : encode chaque instruction avec les adresses definitives.
;;;
;;; Modes d'adressage 6502 :
;;;   :implied       RTS NOP ...            1 octet
;;;   :accumulator   LSR A                  1 octet
;;;   :immediate     LDA #$FF               2 octets
;;;   :zero-page     LDA $10                2 octets
;;;   :zero-page-x   LDA $10,X              2 octets
;;;   :zero-page-y   LDX $10,Y              2 octets
;;;   :absolute      LDA $1234              3 octets
;;;   :absolute-x    LDA $1234,X            3 octets
;;;   :absolute-y    LDA $1234,Y            3 octets
;;;   :indirect      JMP ($FFFC)            3 octets
;;;   :indirect-x    LDA ($00,X)            2 octets
;;;   :indirect-y    LDA ($00),Y            2 octets
;;;   :relative      BNE label              2 octets  (offset signe -128..127)


(in-package #:cl-asm/backend.6502)

(declaim (ftype (function (t t t) t) process-directive-pass1 eval-operand-value))
(declaim (ftype (function (t t t t) t) process-directive-pass2))


;;; --------------------------------------------------------------------------
;;;  Table des instructions
;;;
;;; Format : hashtable mnemonique -> liste de clauses
;;; Chaque clause : (:mode MODE :opcode OCTET :bytes TAILLE :cycles N)
;;; --------------------------------------------------------------------------

(defparameter *instructions*
  (let ((tbl (make-hash-table :test #'equal)))
    (flet ((add (mn &rest clauses)
             (setf (gethash mn tbl) clauses)))

      ;; --- Transferts registre <-> memoire ---
      (add "LDA"
           '(:mode :immediate   :opcode #xA9 :bytes 2 :cycles 2)
           '(:mode :zero-page   :opcode #xA5 :bytes 2 :cycles 3)
           '(:mode :zero-page-x :opcode #xB5 :bytes 2 :cycles 4)
           '(:mode :absolute    :opcode #xAD :bytes 3 :cycles 4)
           '(:mode :absolute-x  :opcode #xBD :bytes 3 :cycles 4)
           '(:mode :absolute-y  :opcode #xB9 :bytes 3 :cycles 4)
           '(:mode :indirect-x  :opcode #xA1 :bytes 2 :cycles 6)
           '(:mode :indirect-y  :opcode #xB1 :bytes 2 :cycles 5))
      (add "LDX"
           '(:mode :immediate   :opcode #xA2 :bytes 2 :cycles 2)
           '(:mode :zero-page   :opcode #xA6 :bytes 2 :cycles 3)
           '(:mode :zero-page-y :opcode #xB6 :bytes 2 :cycles 4)
           '(:mode :absolute    :opcode #xAE :bytes 3 :cycles 4)
           '(:mode :absolute-y  :opcode #xBE :bytes 3 :cycles 4))
      (add "LDY"
           '(:mode :immediate   :opcode #xA0 :bytes 2 :cycles 2)
           '(:mode :zero-page   :opcode #xA4 :bytes 2 :cycles 3)
           '(:mode :zero-page-x :opcode #xB4 :bytes 2 :cycles 4)
           '(:mode :absolute    :opcode #xAC :bytes 3 :cycles 4)
           '(:mode :absolute-x  :opcode #xBC :bytes 3 :cycles 4))
      (add "STA"
           '(:mode :zero-page   :opcode #x85 :bytes 2 :cycles 3)
           '(:mode :zero-page-x :opcode #x95 :bytes 2 :cycles 4)
           '(:mode :absolute    :opcode #x8D :bytes 3 :cycles 4)
           '(:mode :absolute-x  :opcode #x9D :bytes 3 :cycles 5)
           '(:mode :absolute-y  :opcode #x99 :bytes 3 :cycles 5)
           '(:mode :indirect-x  :opcode #x81 :bytes 2 :cycles 6)
           '(:mode :indirect-y  :opcode #x91 :bytes 2 :cycles 6))
      (add "STX"
           '(:mode :zero-page   :opcode #x86 :bytes 2 :cycles 3)
           '(:mode :zero-page-y :opcode #x96 :bytes 2 :cycles 4)
           '(:mode :absolute    :opcode #x8E :bytes 3 :cycles 4))
      (add "STY"
           '(:mode :zero-page   :opcode #x84 :bytes 2 :cycles 3)
           '(:mode :zero-page-x :opcode #x94 :bytes 2 :cycles 4)
           '(:mode :absolute    :opcode #x8C :bytes 3 :cycles 4))

      ;; --- Transferts entre registres ---
      (add "TAX" '(:mode :implied :opcode #xAA :bytes 1 :cycles 2))
      (add "TAY" '(:mode :implied :opcode #xA8 :bytes 1 :cycles 2))
      (add "TXA" '(:mode :implied :opcode #x8A :bytes 1 :cycles 2))
      (add "TYA" '(:mode :implied :opcode #x98 :bytes 1 :cycles 2))
      (add "TSX" '(:mode :implied :opcode #xBA :bytes 1 :cycles 2))
      (add "TXS" '(:mode :implied :opcode #x9A :bytes 1 :cycles 2))

      ;; --- Pile ---
      (add "PHA" '(:mode :implied :opcode #x48 :bytes 1 :cycles 3))
      (add "PLA" '(:mode :implied :opcode #x68 :bytes 1 :cycles 4))
      (add "PHP" '(:mode :implied :opcode #x08 :bytes 1 :cycles 3))
      (add "PLP" '(:mode :implied :opcode #x28 :bytes 1 :cycles 4))

      ;; --- Arithmetique ---
      (add "ADC"
           '(:mode :immediate   :opcode #x69 :bytes 2 :cycles 2)
           '(:mode :zero-page   :opcode #x65 :bytes 2 :cycles 3)
           '(:mode :zero-page-x :opcode #x75 :bytes 2 :cycles 4)
           '(:mode :absolute    :opcode #x6D :bytes 3 :cycles 4)
           '(:mode :absolute-x  :opcode #x7D :bytes 3 :cycles 4)
           '(:mode :absolute-y  :opcode #x79 :bytes 3 :cycles 4)
           '(:mode :indirect-x  :opcode #x61 :bytes 2 :cycles 6)
           '(:mode :indirect-y  :opcode #x71 :bytes 2 :cycles 5))
      (add "SBC"
           '(:mode :immediate   :opcode #xE9 :bytes 2 :cycles 2)
           '(:mode :zero-page   :opcode #xE5 :bytes 2 :cycles 3)
           '(:mode :zero-page-x :opcode #xF5 :bytes 2 :cycles 4)
           '(:mode :absolute    :opcode #xED :bytes 3 :cycles 4)
           '(:mode :absolute-x  :opcode #xFD :bytes 3 :cycles 4)
           '(:mode :absolute-y  :opcode #xF9 :bytes 3 :cycles 4)
           '(:mode :indirect-x  :opcode #xE1 :bytes 2 :cycles 6)
           '(:mode :indirect-y  :opcode #xF1 :bytes 2 :cycles 5))

      ;; --- Increments / decrements ---
      (add "INC"
           '(:mode :zero-page   :opcode #xE6 :bytes 2 :cycles 5)
           '(:mode :zero-page-x :opcode #xF6 :bytes 2 :cycles 6)
           '(:mode :absolute    :opcode #xEE :bytes 3 :cycles 6)
           '(:mode :absolute-x  :opcode #xFE :bytes 3 :cycles 7))
      (add "DEC"
           '(:mode :zero-page   :opcode #xC6 :bytes 2 :cycles 5)
           '(:mode :zero-page-x :opcode #xD6 :bytes 2 :cycles 6)
           '(:mode :absolute    :opcode #xCE :bytes 3 :cycles 6)
           '(:mode :absolute-x  :opcode #xDE :bytes 3 :cycles 7))
      (add "INX" '(:mode :implied :opcode #xE8 :bytes 1 :cycles 2))
      (add "INY" '(:mode :implied :opcode #xC8 :bytes 1 :cycles 2))
      (add "DEX" '(:mode :implied :opcode #xCA :bytes 1 :cycles 2))
      (add "DEY" '(:mode :implied :opcode #x88 :bytes 1 :cycles 2))

      ;; --- Operations logiques ---
      (add "AND"
           '(:mode :immediate   :opcode #x29 :bytes 2 :cycles 2)
           '(:mode :zero-page   :opcode #x25 :bytes 2 :cycles 3)
           '(:mode :zero-page-x :opcode #x35 :bytes 2 :cycles 4)
           '(:mode :absolute    :opcode #x2D :bytes 3 :cycles 4)
           '(:mode :absolute-x  :opcode #x3D :bytes 3 :cycles 4)
           '(:mode :absolute-y  :opcode #x39 :bytes 3 :cycles 4)
           '(:mode :indirect-x  :opcode #x21 :bytes 2 :cycles 6)
           '(:mode :indirect-y  :opcode #x31 :bytes 2 :cycles 5))
      (add "ORA"
           '(:mode :immediate   :opcode #x09 :bytes 2 :cycles 2)
           '(:mode :zero-page   :opcode #x05 :bytes 2 :cycles 3)
           '(:mode :zero-page-x :opcode #x15 :bytes 2 :cycles 4)
           '(:mode :absolute    :opcode #x0D :bytes 3 :cycles 4)
           '(:mode :absolute-x  :opcode #x1D :bytes 3 :cycles 4)
           '(:mode :absolute-y  :opcode #x19 :bytes 3 :cycles 4)
           '(:mode :indirect-x  :opcode #x01 :bytes 2 :cycles 6)
           '(:mode :indirect-y  :opcode #x11 :bytes 2 :cycles 5))
      (add "EOR"
           '(:mode :immediate   :opcode #x49 :bytes 2 :cycles 2)
           '(:mode :zero-page   :opcode #x45 :bytes 2 :cycles 3)
           '(:mode :zero-page-x :opcode #x55 :bytes 2 :cycles 4)
           '(:mode :absolute    :opcode #x4D :bytes 3 :cycles 4)
           '(:mode :absolute-x  :opcode #x5D :bytes 3 :cycles 4)
           '(:mode :absolute-y  :opcode #x59 :bytes 3 :cycles 4)
           '(:mode :indirect-x  :opcode #x41 :bytes 2 :cycles 6)
           '(:mode :indirect-y  :opcode #x51 :bytes 2 :cycles 5))
      (add "BIT"
           '(:mode :zero-page   :opcode #x24 :bytes 2 :cycles 3)
           '(:mode :absolute    :opcode #x2C :bytes 3 :cycles 4))

      ;; --- Decalages ---
      (add "ASL"
           '(:mode :accumulator :opcode #x0A :bytes 1 :cycles 2)
           '(:mode :zero-page   :opcode #x06 :bytes 2 :cycles 5)
           '(:mode :zero-page-x :opcode #x16 :bytes 2 :cycles 6)
           '(:mode :absolute    :opcode #x0E :bytes 3 :cycles 6)
           '(:mode :absolute-x  :opcode #x1E :bytes 3 :cycles 7))
      (add "LSR"
           '(:mode :accumulator :opcode #x4A :bytes 1 :cycles 2)
           '(:mode :zero-page   :opcode #x46 :bytes 2 :cycles 5)
           '(:mode :zero-page-x :opcode #x56 :bytes 2 :cycles 6)
           '(:mode :absolute    :opcode #x4E :bytes 3 :cycles 6)
           '(:mode :absolute-x  :opcode #x5E :bytes 3 :cycles 7))
      (add "ROL"
           '(:mode :accumulator :opcode #x2A :bytes 1 :cycles 2)
           '(:mode :zero-page   :opcode #x26 :bytes 2 :cycles 5)
           '(:mode :zero-page-x :opcode #x36 :bytes 2 :cycles 6)
           '(:mode :absolute    :opcode #x2E :bytes 3 :cycles 6)
           '(:mode :absolute-x  :opcode #x3E :bytes 3 :cycles 7))
      (add "ROR"
           '(:mode :accumulator :opcode #x6A :bytes 1 :cycles 2)
           '(:mode :zero-page   :opcode #x66 :bytes 2 :cycles 5)
           '(:mode :zero-page-x :opcode #x76 :bytes 2 :cycles 6)
           '(:mode :absolute    :opcode #x6E :bytes 3 :cycles 6)
           '(:mode :absolute-x  :opcode #x7E :bytes 3 :cycles 7))

      ;; --- Comparaisons ---
      (add "CMP"
           '(:mode :immediate   :opcode #xC9 :bytes 2 :cycles 2)
           '(:mode :zero-page   :opcode #xC5 :bytes 2 :cycles 3)
           '(:mode :zero-page-x :opcode #xD5 :bytes 2 :cycles 4)
           '(:mode :absolute    :opcode #xCD :bytes 3 :cycles 4)
           '(:mode :absolute-x  :opcode #xDD :bytes 3 :cycles 4)
           '(:mode :absolute-y  :opcode #xD9 :bytes 3 :cycles 4)
           '(:mode :indirect-x  :opcode #xC1 :bytes 2 :cycles 6)
           '(:mode :indirect-y  :opcode #xD1 :bytes 2 :cycles 5))
      (add "CPX"
           '(:mode :immediate   :opcode #xE0 :bytes 2 :cycles 2)
           '(:mode :zero-page   :opcode #xE4 :bytes 2 :cycles 3)
           '(:mode :absolute    :opcode #xEC :bytes 3 :cycles 4))
      (add "CPY"
           '(:mode :immediate   :opcode #xC0 :bytes 2 :cycles 2)
           '(:mode :zero-page   :opcode #xC4 :bytes 2 :cycles 3)
           '(:mode :absolute    :opcode #xCC :bytes 3 :cycles 4))

      ;; --- Branchements conditionnels (mode :relative) ---
      (add "BCC" '(:mode :relative :opcode #x90 :bytes 2 :cycles 2))
      (add "BCS" '(:mode :relative :opcode #xB0 :bytes 2 :cycles 2))
      (add "BEQ" '(:mode :relative :opcode #xF0 :bytes 2 :cycles 2))
      (add "BNE" '(:mode :relative :opcode #xD0 :bytes 2 :cycles 2))
      (add "BMI" '(:mode :relative :opcode #x30 :bytes 2 :cycles 2))
      (add "BPL" '(:mode :relative :opcode #x10 :bytes 2 :cycles 2))
      (add "BVC" '(:mode :relative :opcode #x50 :bytes 2 :cycles 2))
      (add "BVS" '(:mode :relative :opcode #x70 :bytes 2 :cycles 2))

      ;; --- Sauts ---
      (add "JMP"
           '(:mode :absolute :opcode #x4C :bytes 3 :cycles 3)
           '(:mode :indirect :opcode #x6C :bytes 3 :cycles 5))
      (add "JSR" '(:mode :absolute :opcode #x20 :bytes 3 :cycles 6))
      (add "RTS" '(:mode :implied  :opcode #x60 :bytes 1 :cycles 6))
      (add "RTI" '(:mode :implied  :opcode #x40 :bytes 1 :cycles 6))
      (add "BRK" '(:mode :implied  :opcode #x00 :bytes 1 :cycles 7))

      ;; --- Drapeaux ---
      (add "CLC" '(:mode :implied :opcode #x18 :bytes 1 :cycles 2))
      (add "SEC" '(:mode :implied :opcode #x38 :bytes 1 :cycles 2))
      (add "CLI" '(:mode :implied :opcode #x58 :bytes 1 :cycles 2))
      (add "SEI" '(:mode :implied :opcode #x78 :bytes 1 :cycles 2))
      (add "CLD" '(:mode :implied :opcode #xD8 :bytes 1 :cycles 2))
      (add "SED" '(:mode :implied :opcode #xF8 :bytes 1 :cycles 2))
      (add "CLV" '(:mode :implied :opcode #xB8 :bytes 1 :cycles 2))

      ;; --- Divers ---
      (add "NOP" '(:mode :implied :opcode #xEA :bytes 1 :cycles 2)))

    tbl)
  "Table des instructions 6502 : string -> liste de clauses d'encodage.")


;;; --------------------------------------------------------------------------
;;;  Helpers sur la table
;;; --------------------------------------------------------------------------

(defun lookup-instruction (mnemonic)
  "Retourne les clauses d'encodage pour MNEMONIC, ou NIL."
  (gethash (string-upcase mnemonic) *instructions*))

(defun clause-mode   (c) (getf c :mode))
(defun clause-opcode (c) (getf c :opcode))
(defun clause-bytes  (c) (getf c :bytes))

(defun find-clause (mnemonic mode)
  "Retourne la clause pour MNEMONIC en MODE, ou NIL."
  (find mode (lookup-instruction mnemonic) :key #'clause-mode))


;;; --------------------------------------------------------------------------
;;;  Resolution du mode d'adressage depuis un IR-OPERAND
;;; --------------------------------------------------------------------------

(defun resolve-mode (operand addr-value)
  "Determine le mode d'adressage 6502 a partir d'un IR-OPERAND et de la
   valeur numerique resolue de l'adresse/valeur (ou NIL si non resolue).
   Retourne un keyword de mode."
  (when (null operand)
    (return-from resolve-mode :implied))
  (let ((kind     (cl-asm/ir:ir-operand-kind     operand))
        (idx-reg  (cl-asm/ir:ir-operand-index-reg operand))
        (hint     (cl-asm/ir:ir-operand-size-hint operand)))
    (ecase kind
      (:register    :accumulator)
      (:immediate   :immediate)
      (:indirect
       :indirect)
      (:indirect-x  :indirect-x)
      (:indirect-y  :indirect-y)
      (:direct
       ;; Choix zero-page vs absolue selon la valeur et le hint
       (let ((zp (and addr-value
                      (not (eq hint :word))
                      (<= 0 addr-value 255))))
         (ecase (or idx-reg :none)
           (:none  (if zp :zero-page  :absolute))
           (:x     (if zp :zero-page-x :absolute-x))
           (:y     (if zp :zero-page-y :absolute-y))))))))


;;; --------------------------------------------------------------------------
;;;  Encodage des operandes
;;; --------------------------------------------------------------------------

(defun encode-byte (val)
  "Encode VAL comme un octet non signe [0..255]."
  (logand val #xFF))

(defun encode-word-le (val)
  "Encode VAL comme deux octets little-endian."
  (list (logand val #xFF)
        (logand (ash val -8) #xFF)))

(defun encode-relative (target-addr current-pc loc)
  "Calcule l'offset relatif pour une branche.
   L'offset est relatif a l'adresse de l'instruction suivante (PC+2)."
  (let ((offset (- target-addr (+ current-pc 2))))
    (unless (<= -128 offset 127)
      (error 'cl-asm/ir:asm-range-error
             :value offset
             :bits  8
             :message (format nil
                               "Branche hors portee : offset ~D (limite -128..127)"
                               offset)
             :source-loc loc))
    (encode-byte offset)))


;;; --------------------------------------------------------------------------
;;;  Evaluation d'un operande dans le contexte d'assemblage
;;; --------------------------------------------------------------------------

(defun eval-operand-value (operand symtable pc)
  "Evalue la valeur numerique de OPERAND.
   Retourne (values VALEUR RESOLVEDP)."
  (when (null operand)
    (return-from eval-operand-value (values nil t)))
  ;; Les registres (A, X, Y...) n'ont pas de valeur numerique a evaluer
  (when (eq (cl-asm/ir:ir-operand-kind operand) :register)
    (return-from eval-operand-value (values nil t)))
  (let ((expr (cl-asm/ir:ir-operand-value operand))
        (env  (cl-asm/expression:make-env
               :symbol-table symtable
               :pc           pc)))
    (cl-asm/expression:eval-expr expr env)))


;;; --------------------------------------------------------------------------
;;;  Encodage d'une instruction
;;; --------------------------------------------------------------------------

(defun encode-instruction (instr symtable pc pass
                           &key (table *instructions*)
                                (resolve-fn #'resolve-mode))
  "Encode INSTR et retourne (values LISTE-OCTETS TAILLE).
   TABLE permet d'utiliser une table d'instructions alternative (ex: 65C02).
   RESOLVE-FN permet d'utiliser un resolver de mode alternatif.
   En passe 1, les forward-refs donnent une taille estimee (3 octets max).
   En passe 2, tout doit etre resolu."
  (let* ((mn      (cl-asm/ir:ir-instruction-mnemonic  instr))
         (ops     (cl-asm/ir:ir-instruction-operands   instr))
         (operand (first ops))
         (loc     (cl-asm/ir:ir-instruction-loc        instr))
         (clauses (gethash (string-upcase mn) table)))

    ;; Valider le mnemonique
    (unless clauses
      (error 'cl-asm/ir:asm-unknown-mnemonic
             :mnemonic mn
             :message  (format nil "Mnemonique inconnu : ~A" mn)
             :source-loc loc))

    ;; Evaluer la valeur de l'operande
    (multiple-value-bind (addr-val resolved)
        (eval-operand-value operand symtable pc)

      ;; Determiner le mode d'adressage
      (let* ((mode   (if operand
                         (funcall resolve-fn operand (if resolved addr-val nil))
                         :implied))
             (clause (find mode clauses :key #'clause-mode)))

        ;; En passe 1 avec forward-ref : estimer la taille
        (when (and (not resolved) (= pass 1))
          (let* ((has-relative (find :relative clauses :key #'clause-mode))
                 (max-bytes (reduce #'max clauses
                                    :key #'clause-bytes :initial-value 1))
                 ;; Si le mode est déjà déterminé sans ambiguïté ZP/abs,
                 ;; utiliser la taille exacte de la clause (ex: #imm = 2 octets)
                 (exact-bytes (when (and clause (not (member mode '(:absolute :absolute-x
                                                                    :absolute-y :zero-page
                                                                    :zero-page-x :zero-page-y))))
                                (clause-bytes clause)))
                 (estimated (cond (has-relative 2)
                                  (exact-bytes exact-bytes)
                                  (t max-bytes))))
            (return-from encode-instruction
              (values (make-list estimated :initial-element 0)
                      estimated))))

        ;; Verifier qu'on a un encodage pour ce mode
        (unless clause
          ;; Fallback :implied → :accumulator (ex: ASL sans opérande = ASL A)
          (when (eq mode :implied)
            (let ((acc (find :accumulator clauses :key #'clause-mode)))
              (when acc
                (setf mode :accumulator clause acc))))
          ;; Essayer le mode :relative pour les branches
          (when (and (null clause) resolved (find :relative clauses :key #'clause-mode))
            (setf mode :relative
                  clause (find :relative clauses :key #'clause-mode)))
          (unless clause
            (error 'cl-asm/ir:asm-syntax-error
                   :message (format nil
                                     "~A : mode d'adressage non supporte (~A)"
                                     mn mode)
                   :source-loc loc)))

        ;; Encoder selon le mode
        (let ((opcode (clause-opcode clause)))
          (ecase mode
            (:implied
             (values (list opcode) 1))
            (:accumulator
             (values (list opcode) 1))
            (:immediate
             (values (list opcode (encode-byte addr-val)) 2))
            ((:zero-page :zero-page-x :zero-page-y :indirect-x :indirect-y
              :zero-page-indirect)
             (values (list opcode (encode-byte addr-val)) 2))
            ((:absolute :absolute-x :absolute-y :indirect :indirect-absolute-x)
             (values (cons opcode (encode-word-le addr-val)) 3))
            (:relative
             (values (list opcode (encode-relative addr-val pc loc)) 2))))))))

;;; --------------------------------------------------------------------------
;;;  Passe 1 : collecte des labels et calcul des adresses
;;; --------------------------------------------------------------------------

(defun pass-1 (sections symtable origin)
  "Parcourt les sections, enregistre les labels, calcule les adresses.
   Retourne la table des adresses de section."
  (let ((pc origin))
    (dolist (section sections)
      ;; Appliquer l'origine de la section si definie
      (when (cl-asm/ir:ir-section-origin section)
        (setf pc (cl-asm/ir:ir-section-origin section)))
      (dolist (node (cl-asm/ir:ir-section-nodes section))
        (typecase node
          (cl-asm/ir:ir-label
           ;; Synchroniser le PC de la table des symboles avant de definir le label
           (setf (cl-asm/symbol-table:st-current-pc symtable) pc)
           (cl-asm/symbol-table:define-label
            symtable
            (cl-asm/ir:ir-label-name node)
            :source-loc (cl-asm/ir:ir-label-loc node)))
          (cl-asm/ir:ir-instruction
           ;; Estimer la taille et avancer le PC
           (multiple-value-bind (bytes nbytes)
               (encode-instruction node symtable pc 1)
             (declare (ignore bytes))
             (incf pc nbytes)))
          (cl-asm/ir:ir-directive
           ;; Traiter les directives qui affectent le PC
           (setf pc (process-directive-pass1
                     node symtable pc))))))
    pc))

(defun process-directive-pass1 (directive symtable pc)
  "Traite une directive en passe 1. Retourne le nouveau PC."
  (let ((name (cl-asm/ir:ir-directive-name directive))
        (args (cl-asm/ir:ir-directive-args  directive))
        (env  (cl-asm/expression:make-env
               :symbol-table symtable :pc pc)))
    (case name
      (:org
       (multiple-value-bind (val ok)
           (cl-asm/expression:eval-expr (first args) env)
         (if ok val pc)))
      (:equ
       (let ((sym-name (first args))
             (expr     (second args)))
         (multiple-value-bind (val ok)
             (cl-asm/expression:eval-expr expr env)
           (when ok
             (cl-asm/symbol-table:define-constant
              symtable sym-name val)))
         pc))
      ((:byte :pet)
       (+ pc (reduce #'+ args
                     :key (lambda (a) (if (stringp a) (length a) 1))
                     :initial-value 0)))
      (:word
       (+ pc (* 2 (length args))))
      (:dword
       (+ pc (* 4 (length args))))
      (:text
       (+ pc (reduce #'+ args
                     :key (lambda (a)
                            (if (stringp a) (length a) 1))
                     :initial-value 0)))
      (:asciiz
       ;; chaine + octet nul final
       (+ pc (if (stringp (first args)) (length (first args)) 0) 1))
      (:pascalstr
       ;; octet de longueur + chaine
       (+ pc (if (stringp (first args)) (length (first args)) 0) 1))
      (:fill
       (let ((count (first args)))
         (multiple-value-bind (n ok)
             (cl-asm/expression:eval-expr count env)
           (if ok (+ pc n) (+ pc 0)))))
      (:align
       (let* ((align (first args))
              (val   (cl-asm/expression:eval-expr align env)))
         (if (zerop (mod pc val))
             pc
             (+ pc (- val (mod pc val))))))
      (:padto
       (multiple-value-bind (target ok)
           (cl-asm/expression:eval-expr (first args) env)
         (if ok
             (if (> pc target)
                 (error 'cl-asm/ir:asm-error
                        :message (format nil ".padto $~X : PC courant ($~X) depasse la cible"
                                         target pc))
                 target)
             pc)))
      (:incbin
       (let* ((filename  (first args))
              (offset    (if (second args)
                             (multiple-value-bind (v ok)
                                 (cl-asm/expression:eval-expr (second args) env)
                               (if ok v 0))
                             0))
              (count-arg (when (third args)
                           (multiple-value-bind (v ok)
                               (cl-asm/expression:eval-expr (third args) env)
                             (when ok v)))))
         (handler-case
             (let* ((fsize (with-open-file (s filename :element-type '(unsigned-byte 8))
                             (file-length s)))
                    (avail (max 0 (- fsize offset)))
                    (n     (if count-arg (min count-arg avail) avail)))
               (+ pc n))
           (file-error ()
             (error 'cl-asm/ir:asm-error
                    :message (format nil ".incbin : fichier introuvable \"~A\"" filename))))))
      (:assertpc pc)    ; verifie en passe 2 uniquement
      (:assertsize pc)  ; verifie en passe 2 uniquement
      (:defstruct
       (let* ((struct-name (first args))
              (fields      (second args))
              (offset      0))
         (dolist (field fields)
           (cl-asm/symbol-table:define-constant
            symtable
            (format nil "~A.~A" struct-name (car field))
            offset)
           (incf offset (cdr field)))
         (cl-asm/symbol-table:define-constant
          symtable
          (format nil "~A.SIZE" struct-name)
          offset))
       pc)
      (:defenum
       (let ((enum-name (first args))
             (values    (second args)))
         (dolist (entry values)
           (cl-asm/symbol-table:define-constant
            symtable
            (format nil "~A.~A" enum-name (car entry))
            (cdr entry)))
         (cl-asm/symbol-table:define-constant
          symtable
          (format nil "~A.COUNT" enum-name)
          (length values)))
       pc)
      (otherwise pc))))


;;; --------------------------------------------------------------------------
;;;  Conversion ASCII → PETSCII (pour la directive ACME !PET)
;;; --------------------------------------------------------------------------

(defun ascii-to-petscii (code)
  "Convertit un code ASCII en PETSCII, comme ACME !PET :
   a-z (0x61-0x7A) → A-Z PETSCII (0x41-0x5A, soustrait 0x20)
   A-Z (0x41-0x5A) → shifted PETSCII (0xC1-0xDA, ajoute 0x80)
   Tout autre code → inchangé."
  (cond
    ((and (>= code #x61) (<= code #x7A)) (- code #x20))
    ((and (>= code #x41) (<= code #x5A)) (+ code #x80))
    (t code)))


;;; --------------------------------------------------------------------------
;;;  Passe 2 : encodage definitif
;;; --------------------------------------------------------------------------

(defun pass-2 (sections symtable origin &key debug-map)
  "Encode toutes les instructions et directives.
   Retourne un vecteur d'octets.
   DEBUG-MAP (optionnel) : cl-asm/debugger.6502:debug-map à remplir avec
   la correspondance adresse → source-loc pour chaque instruction assemblée."
  (let ((result (make-array 0 :element-type '(unsigned-byte 8)
                              :adjustable t :fill-pointer 0))
        (pc origin))
    (dolist (section sections)
      (when (cl-asm/ir:ir-section-origin section)
        (setf pc (cl-asm/ir:ir-section-origin section)))
      (dolist (node (cl-asm/ir:ir-section-nodes section))
        (typecase node
          (cl-asm/ir:ir-label
           ;; Synchroniser le PC de la table des symboles
           (setf (cl-asm/symbol-table:st-current-pc symtable) pc)
           (cl-asm/symbol-table:define-label
            symtable
            (cl-asm/ir:ir-label-name node)
            :source-loc (cl-asm/ir:ir-label-loc node)))
          (cl-asm/ir:ir-instruction
           (multiple-value-bind (bytes nbytes)
               (encode-instruction node symtable pc 2)
             ;; Enregistrer la correspondance adresse → source-loc si demandé
             (when (and debug-map (cl-asm/ir:ir-instruction-loc node))
               (cl-asm/debug-map:debug-map-set
                debug-map pc (cl-asm/ir:ir-instruction-loc node)))
             (dolist (b bytes) (vector-push-extend b result))
             (incf pc nbytes)))
          (cl-asm/ir:ir-directive
           (setf pc (process-directive-pass2
                     node symtable pc result))))))
    result))

(defun process-directive-pass2 (node symtable pc result)
  "Traite une directive en passe 2, emettant les octets dans RESULT."
  (let ((name (cl-asm/ir:ir-directive-name node))
        (args (cl-asm/ir:ir-directive-args  node))
        (env  (cl-asm/expression:make-env
               :symbol-table symtable :pc pc)))
    (case name
      (:org
       (multiple-value-bind (val ok)
           (cl-asm/expression:eval-expr (first args) env)
         (if ok val pc)))
      (:equ pc)   ; deja traite en passe 1
      (:section pc)
      (:global pc)
      (:extern pc)
      (:byte
       (dolist (arg args)
         (if (stringp arg)
             ;; Chaîne inline : émettre les octets ASCII directement
             (loop for c across arg
                   do (vector-push-extend (char-code c) result)
                      (incf pc))
             ;; Expression numérique
             (multiple-value-bind (val ok)
                 (cl-asm/expression:eval-expr arg env)
               (if ok
                   (vector-push-extend (logand val #xFF) result)
                   (vector-push-extend 0 result))
               (incf pc))))
       pc)
      ;; !PET (ACME) : comme .byte mais avec conversion ASCII→PETSCII pour les chaînes
      (:pet
       (dolist (arg args)
         (if (stringp arg)
             (loop for c across arg
                   do (vector-push-extend (ascii-to-petscii (char-code c)) result)
                      (incf pc))
             (multiple-value-bind (val ok)
                 (cl-asm/expression:eval-expr arg env)
               (vector-push-extend (logand (if ok val 0) #xFF) result)
               (incf pc))))
       pc)
      (:word
       (dolist (arg args)
         (multiple-value-bind (val ok)
             (cl-asm/expression:eval-expr arg env)
           (let ((w (if ok val 0)))
             (vector-push-extend (logand w #xFF) result)
             (vector-push-extend (logand (ash w -8) #xFF) result)
             (incf pc 2))))
       pc)
      (:dword
       (dolist (arg args)
         (multiple-value-bind (val ok)
             (cl-asm/expression:eval-expr arg env)
           (let ((d (if ok val 0)))
             (dotimes (i 4)
               (vector-push-extend (logand (ash d (* -8 i)) #xFF) result))
             (incf pc 4))))
       pc)
      (:text
       (dolist (arg args)
         (etypecase arg
           (string
            (loop for c across arg
                  do (vector-push-extend (char-code c) result)
                     (incf pc)))
           (integer
            (vector-push-extend (logand arg #xFF) result)
            (incf pc))))
       pc)
      (:asciiz
       (let ((str (first args)))
         (when (stringp str)
           (loop for c across str
                 do (vector-push-extend (char-code c) result)
                    (incf pc)))
         (vector-push-extend 0 result)
         (incf pc))
       pc)
      (:pascalstr
       (let ((str (first args)))
         (let ((len (if (stringp str) (length str) 0)))
           (vector-push-extend (logand len #xFF) result)
           (incf pc)
           (when (stringp str)
             (loop for c across str
                   do (vector-push-extend (char-code c) result)
                      (incf pc)))))
       pc)
      (:fill
       (multiple-value-bind (count ok-n)
           (cl-asm/expression:eval-expr (first args) env)
         (let* ((fill-val (if (second args)
                              (multiple-value-bind (v ok)
                                  (cl-asm/expression:eval-expr
                                   (second args) env)
                                (if ok (logand v #xFF) 0))
                              0)))
           (when ok-n
             (dotimes (i count)
               (vector-push-extend fill-val result)
               (incf pc)))))
       pc)
      (:align
       (multiple-value-bind (align ok)
           (cl-asm/expression:eval-expr (first args) env)
         (when ok
           (let* ((fill-val (if (second args)
                                (multiple-value-bind (v fok)
                                    (cl-asm/expression:eval-expr
                                     (second args) env)
                                  (if fok (logand v #xFF) 0))
                                0))
                  (pad (if (zerop (mod pc align))
                           0
                           (- align (mod pc align)))))
             (dotimes (i pad)
               (vector-push-extend fill-val result)
               (incf pc)))))
       pc)
      (:padto
       (multiple-value-bind (target ok)
           (cl-asm/expression:eval-expr (first args) env)
         (when ok
           (when (> pc target)
             (error 'cl-asm/ir:asm-error
                    :message (format nil ".padto $~X : PC courant ($~X) depasse la cible"
                                     target pc)))
           (let ((fill-val (if (second args)
                               (multiple-value-bind (v fok)
                                   (cl-asm/expression:eval-expr
                                    (second args) env)
                                 (if fok (logand v #xFF) 0))
                               0)))
             (dotimes (i (- target pc))
               (vector-push-extend fill-val result)
               (incf pc)))))
       pc)
      (:assertpc
       (multiple-value-bind (target ok)
           (cl-asm/expression:eval-expr (first args) env)
         (when ok
           (unless (= pc target)
             (error 'cl-asm/ir:asm-error
                    :message (format nil ".assertpc $~X : PC courant est $~X"
                                     target pc)
                    :source-loc (cl-asm/ir:ir-directive-loc node)))))
       pc)
      (:assertsize
       (let ((expected (first args))
             (lbl      (second args)))
         (multiple-value-bind (start-pc ok)
             (cl-asm/expression:eval-expr lbl env)
           (when ok
             (let ((actual (- pc start-pc)))
               (unless (= actual expected)
                 (error 'cl-asm/ir:asm-error
                        :message (format nil "(assert-size ~D) : bloc emet ~D octet~:P (attendu ~D)"
                                         expected actual expected)
                        :source-loc (cl-asm/ir:ir-directive-loc node)))))))
       pc)
      (:incbin
       (let* ((filename  (first args))
              (offset    (if (second args)
                             (multiple-value-bind (v ok)
                                 (cl-asm/expression:eval-expr (second args) env)
                               (if ok v 0))
                             0))
              (count-arg (when (third args)
                           (multiple-value-bind (v ok)
                               (cl-asm/expression:eval-expr (third args) env)
                             (when ok v)))))
         (handler-case
             (with-open-file (s filename :element-type '(unsigned-byte 8))
               (let* ((fsize (file-length s))
                      (avail (max 0 (- fsize offset)))
                      (n     (if count-arg (min count-arg avail) avail)))
                 (when (> offset 0)
                   (file-position s offset))
                 (dotimes (_ n)
                   (let ((b (read-byte s nil nil)))
                     (when b
                       (vector-push-extend b result)
                       (incf pc))))))
           (file-error ()
             (error 'cl-asm/ir:asm-error
                    :message (format nil ".incbin : fichier introuvable \"~A\"" filename)))))
       pc)
      (:defstruct pc)   ; symboles deja definis en passe 1
      (:defenum   pc)   ; symboles deja definis en passe 1
      (otherwise pc))))


;;; --------------------------------------------------------------------------
;;;  Point d'entree public
;;; --------------------------------------------------------------------------

(defun assemble (program &key (origin #x0801) (section :text) debug-map)
  "Assemble PROGRAM (IR-PROGRAM) et retourne un vecteur d'octets.
   ORIGIN    : adresse de chargement par defaut ($0801 pour C64).
   SECTION   : section principale a assembler (:text par defaut).
   DEBUG-MAP : cl-asm/debugger.6502:debug-map a remplir (adresse → source-loc)
               pour un usage avec le debogueur interactif."
  (let* ((symtable (cl-asm/symbol-table:make-symbol-table))
         ;; On assemble toutes les sections dans l'ordre, en commencant
         ;; par la section principale
         (sections (let ((main (cl-asm/ir:program-find-section
                                program section))
                         (rest (remove-if
                                (lambda (s)
                                  (eq (cl-asm/ir:ir-section-name s) section))
                                (cl-asm/ir:ir-program-sections program))))
                     (if main (cons main rest) rest))))

    ;; Initialiser le PC de la table des symboles
    (setf (cl-asm/symbol-table:st-current-pc symtable) origin)

    ;; Passe 1 : collecte des labels
    (pass-1 sections symtable origin)

    ;; Passe 2 : encodage (+ remplissage de la debug-map si fournie)
    (cl-asm/symbol-table:begin-pass-2 symtable)
    (setf (cl-asm/symbol-table:st-current-pc symtable) origin)
    (pass-2 sections symtable origin :debug-map debug-map)))

(defun assemble-string (source &key (origin #x0801))
  "Raccourci : parse SOURCE puis assemble. Retourne le vecteur d'octets."
  (let ((program (cl-asm/parser:parse-string source)))
    (assemble program :origin origin)))

(defun assemble-file (path &key (origin #x0801) debug-map)
  "Raccourci : lit, parse et assemble le fichier a PATH.
   Retourne le vecteur d'octets.
   DEBUG-MAP (optionnel) : debug-map a remplir (adresse → source-loc)."
  (let ((program (cl-asm/parser:parse-file path)))
    (assemble program :origin origin :debug-map debug-map)))

(cl-asm/backends:register-backend
 :6502
 '("6502" "mos6502" "c64")
 "CL-ASM/BACKEND.6502" "ASSEMBLE-FILE"
 "MOS 6502 / Commodore 64"
 "MOS 6502 / Commodore 64")
