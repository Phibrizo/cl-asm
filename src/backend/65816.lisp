; -*- coding: utf-8 -*-
(defpackage #:cl-asm/backend.65816
  (:use #:cl)
  (:export
   #:assemble-65816 #:assemble-string-65816 #:assemble-file-65816
   #:*instructions-65816*
   #:resolve-mode-65816))
;;; src/backend/65816.lisp
;;;
;;; Backend d'assemblage pour le processeur WDC 65816.
;;; Cibles : SNES (Super Nintendo), Apple IIgs.
;;;
;;; Le 65816 est un superset du 6502 avec :
;;;   1. Modes 8/16 bits switchables via les flags M (accumulateur) et X (index)
;;;      Directives .al/.as (accumulateur 16/8 bits) et .xl/.xs (index 16/8 bits)
;;;   2. Adressage 24 bits : absolute long ($nnnnnn), 4 octets
;;;   3. Indirect long : LDA [$nn] 2 octets (DP) / JMP [$nnnn] 3 octets (abs)
;;;   4. Stack relative : LDA $nn,S — via (:indirect-sp-y) du parser
;;;   5. Block move : MVN/MVP $dst,$src — 3 octets
;;;   6. Branche longue : BRL label — 3 octets (offset 16-bit signe)
;;;
;;; Modes d'adressage 65816 :
;;;   :implied            RTS NOP ...                   1 octet
;;;   :accumulator        LSR A                         1 octet
;;;   :immediate          LDA #$FF (8-bit ou 16-bit)    2 ou 3 octets *
;;;   :zero-page          LDA $10 (direct page)         2 octets
;;;   :zero-page-x        LDA $10,X                     2 octets
;;;   :zero-page-y        LDX $10,Y                     2 octets
;;;   :absolute           LDA $1234                     3 octets
;;;   :absolute-x         LDA $1234,X                   3 octets
;;;   :absolute-y         LDA $1234,Y                   3 octets
;;;   :indirect           JMP ($FFFC)                   3 octets
;;;   :indirect-x         LDA ($00,X)                   2 octets
;;;   :indirect-y         LDA ($00),Y                   2 octets
;;;   :relative           BNE label                     2 octets
;;;   :zero-page-indirect LDA ($nn)                     2 octets
;;;   :indirect-absolute-x JMP ($abs,X)                 3 octets
;;;   :absolute-long      LDA $123456                   4 octets
;;;   :absolute-long-x    LDA $123456,X                 4 octets
;;;   :stack-relative     LDA $05,S                     2 octets
;;;   :sr-indirect-y      LDA ($05,S),Y                 2 octets
;;;   :dp-indirect-long   LDA [$10] (2 oct.) / JMP [$2000] (3 oct.)
;;;   :dp-indirect-long-y LDA [$10],Y                   2 octets
;;;   :relative-long      BRL label                     3 octets (offset 16-bit)
;;;   :block-move         MVN $7E,$00                   3 octets
;;;   :immediate-word     PEA #$1234                    3 octets (toujours 16-bit)
;;;
;;;   * Pour LDA/ADC/etc., la taille de l'immediat suit le flag M (.al/.as)
;;;     Pour LDX/LDY/CPX/CPY, la taille suit le flag X (.xl/.xs)


(in-package #:cl-asm/backend.65816)

(declaim (ftype (function (t t t t) t) process-directive-pass1-65816))
(declaim (ftype (function (t t t t t) t) process-directive-pass2-65816))


;;; --------------------------------------------------------------------------
;;;  Taille des immediats selon les flags M/X
;;; --------------------------------------------------------------------------

(defparameter *m-immediate-mnemonics*
  '("LDA" "STA" "ADC" "SBC" "AND" "ORA" "EOR" "CMP" "BIT")
  "Instructions dont l'immediat 16-bit suit le flag M.")

(defparameter *x-immediate-mnemonics*
  '("LDX" "LDY" "CPX" "CPY")
  "Instructions dont l'immediat 16-bit suit le flag X.")

(defun imm-operand-size (mnemonic m-long x-long)
  "Retourne 1 (8-bit) ou 2 (16-bit) selon le mnemonique et les flags M/X."
  (cond
    ((member (string-upcase mnemonic) *m-immediate-mnemonics* :test #'string=)
     (if m-long 2 1))
    ((member (string-upcase mnemonic) *x-immediate-mnemonics* :test #'string=)
     (if x-long 2 1))
    (t 1)))


;;; --------------------------------------------------------------------------
;;;  Encodage des operandes 24 bits
;;; --------------------------------------------------------------------------

(defun encode-long-le (val)
  "Encode VAL comme trois octets little-endian (24 bits)."
  (list (logand val #xFF)
        (logand (ash val -8) #xFF)
        (logand (ash val -16) #xFF)))

(defun encode-relative-long (target-addr current-pc loc)
  "Calcule l'offset 16-bit signe pour BRL/PER.
   L'offset est relatif a l'instruction suivante (PC+3)."
  (let ((offset (- target-addr (+ current-pc 3))))
    (unless (<= -32768 offset 32767)
      (error 'cl-asm/ir:asm-range-error
             :value offset
             :bits  16
             :message (format nil "BRL/PER hors portee : offset ~D (limite -32768..32767)"
                               offset)
             :source-loc loc))
    (list (logand offset #xFF)
          (logand (ash offset -8) #xFF))))


;;; --------------------------------------------------------------------------
;;;  Table des instructions 65816
;;; --------------------------------------------------------------------------

(defun build-65816-table ()
  "Construit la table d'instructions 65816 complete."
  (let ((tbl (make-hash-table :test #'equal)))

    ;; Copier toutes les instructions 6502
    (maphash (lambda (k v)
               (setf (gethash k tbl) (copy-list v)))
             cl-asm/backend.6502:*instructions*)

    (flet ((add (mn &rest clauses)
             (setf (gethash mn tbl) clauses))
           (add-mode (mn &rest new-clauses)
             (let ((existing (gethash mn tbl)))
               (setf (gethash mn tbl)
                     (append existing new-clauses)))))

      ;; ------------------------------------------------------------------
      ;; Nouvelles instructions implied du 65816
      ;; ------------------------------------------------------------------
      (add "PHB" '(:mode :implied :opcode #x8B :bytes 1))
      (add "PLB" '(:mode :implied :opcode #xAB :bytes 1))
      (add "PHD" '(:mode :implied :opcode #x0B :bytes 1))
      (add "PLD" '(:mode :implied :opcode #x2B :bytes 1))
      (add "PHK" '(:mode :implied :opcode #x4B :bytes 1))
      (add "RTL" '(:mode :implied :opcode #x6B :bytes 1))
      (add "WAI" '(:mode :implied :opcode #xCB :bytes 1))
      (add "STP" '(:mode :implied :opcode #xDB :bytes 1))
      (add "XBA" '(:mode :implied :opcode #xEB :bytes 1))
      (add "XCE" '(:mode :implied :opcode #xFB :bytes 1))
      (add "TCD" '(:mode :implied :opcode #x5B :bytes 1))
      (add "TCS" '(:mode :implied :opcode #x1B :bytes 1))
      (add "TDC" '(:mode :implied :opcode #x7B :bytes 1))
      (add "TSC" '(:mode :implied :opcode #x3B :bytes 1))
      (add "TXY" '(:mode :implied :opcode #x9B :bytes 1))
      (add "TYX" '(:mode :implied :opcode #xBB :bytes 1))

      ;; ------------------------------------------------------------------
      ;; BRA — branche inconditionnelle (comme 65C02)
      ;; ------------------------------------------------------------------
      (add "BRA" '(:mode :relative :opcode #x80 :bytes 2))

      ;; ------------------------------------------------------------------
      ;; JSL — Jump to Subroutine Long (adresse 24 bits, 4 octets)
      ;; ------------------------------------------------------------------
      (add "JSL" '(:mode :absolute-long :opcode #x22 :bytes 4))

      ;; ------------------------------------------------------------------
      ;; JML — Jump Long
      ;; :dp-indirect-long avec :bytes 3 = indirect absolu ($DC + 2 octets addr)
      ;; ------------------------------------------------------------------
      (add "JML"
           '(:mode :absolute-long    :opcode #x5C :bytes 4)
           '(:mode :dp-indirect-long :opcode #xDC :bytes 3))

      ;; JMP [abs] — indirect long absolu (3 octets : opcode + adresse 16-bit)
      (add-mode "JMP"
                '(:mode :dp-indirect-long :opcode #xDC :bytes 3))

      ;; ------------------------------------------------------------------
      ;; BRL — Branche longue (offset signe 16 bits, 3 octets)
      ;; ------------------------------------------------------------------
      (add "BRL" '(:mode :relative-long :opcode #x82 :bytes 3))

      ;; ------------------------------------------------------------------
      ;; REP / SEP — Reset/Set bits de statut (immediat 8-bit fixe)
      ;; ------------------------------------------------------------------
      (add "REP" '(:mode :immediate :opcode #xC2 :bytes 2))
      (add "SEP" '(:mode :immediate :opcode #xE2 :bytes 2))

      ;; ------------------------------------------------------------------
      ;; MVN / MVP — Block Move (3 octets : opcode + dst-bank + src-bank)
      ;; ------------------------------------------------------------------
      (add "MVN" '(:mode :block-move :opcode #x54 :bytes 3))
      (add "MVP" '(:mode :block-move :opcode #x44 :bytes 3))

      ;; ------------------------------------------------------------------
      ;; PEA — Push Effective Absolute (immediat, toujours 16-bit)
      ;; :bytes 3 signale a l'encodeur d'utiliser encode-word-le
      ;; ------------------------------------------------------------------
      (add "PEA" '(:mode :immediate :opcode #xF4 :bytes 3))

      ;; ------------------------------------------------------------------
      ;; PEI — Push Effective Indirect (zero-page indirect, 2 octets)
      ;; ------------------------------------------------------------------
      (add "PEI" '(:mode :zero-page-indirect :opcode #xD4 :bytes 2))

      ;; ------------------------------------------------------------------
      ;; PER — Push Effective PC Relative Long (relatif 16-bit, 3 octets)
      ;; ------------------------------------------------------------------
      (add "PER" '(:mode :relative-long :opcode #x62 :bytes 3))

      ;; ------------------------------------------------------------------
      ;; COP — Co-processor (immediat 8-bit fixe)
      ;; ------------------------------------------------------------------
      (add "COP" '(:mode :immediate :opcode #x02 :bytes 2))

      ;; ------------------------------------------------------------------
      ;; Nouveaux modes pour LDA/STA/ADC/SBC/AND/ORA/EOR/CMP
      ;;   :stack-relative      $nn,S            2 octets
      ;;   :sr-indirect-y       ($nn,S),Y        2 octets
      ;;   :dp-indirect-long    [$nn]            2 octets
      ;;   :dp-indirect-long-y  [$nn],Y          2 octets
      ;;   :absolute-long       $nnnnnn          4 octets
      ;;   :absolute-long-x     $nnnnnn,X        4 octets
      ;; ------------------------------------------------------------------
      (dolist (entry
               '(("LDA" #xA3 #xB3 #xA7 #xB7 #xAF #xBF)
                 ("STA" #x83 #x93 #x87 #x97 #x8F #x9F)
                 ("ADC" #x63 #x73 #x67 #x77 #x6F #x7F)
                 ("SBC" #xE3 #xF3 #xE7 #xF7 #xEF #xFF)
                 ("AND" #x23 #x33 #x27 #x37 #x2F #x3F)
                 ("ORA" #x03 #x13 #x07 #x17 #x0F #x1F)
                 ("EOR" #x43 #x53 #x47 #x57 #x4F #x5F)
                 ("CMP" #xC3 #xD3 #xC7 #xD7 #xCF #xDF)))
        (destructuring-bind (mn sr sry il ily al alx) entry
          (add-mode mn
                    `(:mode :stack-relative     :opcode ,sr  :bytes 2)
                    `(:mode :sr-indirect-y      :opcode ,sry :bytes 2)
                    `(:mode :dp-indirect-long   :opcode ,il  :bytes 2)
                    `(:mode :dp-indirect-long-y :opcode ,ily :bytes 2)
                    `(:mode :absolute-long      :opcode ,al  :bytes 4)
                    `(:mode :absolute-long-x    :opcode ,alx :bytes 4))))

      ;; ------------------------------------------------------------------
      ;; Mode zero-page-indirect ($nn) — comme 65C02
      ;; ------------------------------------------------------------------
      (dolist (pair '(("LDA" . #xB2) ("STA" . #x92)
                      ("ADC" . #x72) ("SBC" . #xF2)
                      ("AND" . #x32) ("ORA" . #x12)
                      ("EOR" . #x52) ("CMP" . #xD2)))
        (add-mode (car pair)
                  `(:mode :zero-page-indirect :opcode ,(cdr pair) :bytes 2)))

      ;; ------------------------------------------------------------------
      ;; STZ — store zero (comme 65C02)
      ;; ------------------------------------------------------------------
      (add "STZ"
           '(:mode :zero-page   :opcode #x64 :bytes 2)
           '(:mode :zero-page-x :opcode #x74 :bytes 2)
           '(:mode :absolute    :opcode #x9C :bytes 3)
           '(:mode :absolute-x  :opcode #x9E :bytes 3))

      ;; ------------------------------------------------------------------
      ;; TRB / TSB (comme 65C02)
      ;; ------------------------------------------------------------------
      (add "TRB"
           '(:mode :zero-page :opcode #x14 :bytes 2)
           '(:mode :absolute  :opcode #x1C :bytes 3))
      (add "TSB"
           '(:mode :zero-page :opcode #x04 :bytes 2)
           '(:mode :absolute  :opcode #x0C :bytes 3))

      ;; ------------------------------------------------------------------
      ;; PHX / PLX / PHY / PLY (comme 65C02)
      ;; ------------------------------------------------------------------
      (add "PHX" '(:mode :implied :opcode #xDA :bytes 1))
      (add "PLX" '(:mode :implied :opcode #xFA :bytes 1))
      (add "PHY" '(:mode :implied :opcode #x5A :bytes 1))
      (add "PLY" '(:mode :implied :opcode #x7A :bytes 1))

      ;; ------------------------------------------------------------------
      ;; INC A / DEC A (comme 65C02)
      ;; ------------------------------------------------------------------
      (add-mode "INC" '(:mode :accumulator :opcode #x1A :bytes 1))
      (add-mode "DEC" '(:mode :accumulator :opcode #x3A :bytes 1))

      ;; ------------------------------------------------------------------
      ;; JMP ($addr,X) — indirect indexe X absolu (comme 65C02)
      ;; ------------------------------------------------------------------
      (add-mode "JMP"
                '(:mode :indirect-absolute-x :opcode #x7C :bytes 3))

      ;; ------------------------------------------------------------------
      ;; BIT avec modes immediat et indexe (comme 65C02)
      ;; ------------------------------------------------------------------
      (add-mode "BIT"
                '(:mode :immediate   :opcode #x89 :bytes 2)
                '(:mode :zero-page-x :opcode #x34 :bytes 2)
                '(:mode :absolute-x  :opcode #x3C :bytes 3)))

    tbl))

(defparameter *instructions-65816*
  (build-65816-table)
  "Table des instructions 65816 (6502 + extensions WDC 65816).")


;;; --------------------------------------------------------------------------
;;;  Resolution du mode d'adressage
;;; --------------------------------------------------------------------------

(defun resolve-mode-65816 (operand addr-value)
  "Resout le mode d'adressage 65816 a partir d'un IR-OPERAND et de ADDR-VALUE."
  (when (null operand)
    (return-from resolve-mode-65816 :implied))
  (let ((kind      (cl-asm/ir:ir-operand-kind      operand))
        (index-reg (cl-asm/ir:ir-operand-index-reg operand))
        (size-hint (cl-asm/ir:ir-operand-size-hint operand)))
    (cond
      ;; [$nn] ou [$nnnn] — indirect long
      ;; :bytes dans la clause determine si DP (2 oct.) ou absolu (3 oct.)
      ((eq kind :indirect-32)
       :dp-indirect-long)

      ;; [$nn],Z — indirect long indexe (65816 : [$nn],Y via index-reg)
      ((eq kind :indirect-32-z)
       :dp-indirect-long-y)

      ;; ($nn,SP),Y — stack relative indirect indexe Y
      ((eq kind :indirect-sp-y)
       :sr-indirect-y)

      ;; ($nn,X) — indirect indexe X
      ((eq kind :indirect-x)
       (if (and (integerp addr-value) (> addr-value 255))
           :indirect-absolute-x
           :indirect-x))

      ;; ($nn),Y — indirect indexe Y (zero-page)
      ((eq kind :indirect-y)
       :indirect-y)

      ;; ($nnnn) — indirect absolu
      ((eq kind :indirect)
       (if (and (integerp addr-value)
                (<= 0 addr-value 255)
                (not (eq size-hint :word)))
           :zero-page-indirect
           :indirect))

      ;; Registre A
      ((eq kind :register)
       :accumulator)

      ;; Immediat
      ((eq kind :immediate)
       :immediate)

      ;; Adressage direct : zero-page, absolute, absolute-long, stack-relative
      ((eq kind :direct)
       (cond
         ;; ,S → stack relative
         ((eq index-reg :s)
          :stack-relative)

         ;; valeur > 65535 ou hint :long → absolute long
         ((or (eq size-hint :long)
              (and (integerp addr-value) (> addr-value #xFFFF)))
          (if (eq index-reg :x)
              :absolute-long-x
              :absolute-long))

         ;; sinon deleguer au resolver 6502 (zero-page vs absolute, ,X ,Y)
         (t
          (cl-asm/backend.6502:resolve-mode operand addr-value))))

      (t
       (cl-asm/backend.6502:resolve-mode operand addr-value)))))


;;; --------------------------------------------------------------------------
;;;  Encodage d'un block move (MVN/MVP)
;;; --------------------------------------------------------------------------

(defun encode-block-move (instr symtable pc)
  "Encode MVN/MVP : opcode + dst-bank + src-bank (3 octets).
   Attend deux operandes :direct dans INSTR."
  (let* ((mn       (cl-asm/ir:ir-instruction-mnemonic instr))
         (opcode   (cl-asm/backend.6502:clause-opcode
                    (first (gethash (string-upcase mn) *instructions-65816*))))
         (operands (cl-asm/ir:ir-instruction-operands instr))
         (op-dst   (first  operands))
         (op-src   (second operands))
         (loc      (cl-asm/ir:ir-instruction-loc instr)))
    (unless (and op-dst op-src)
      (error 'cl-asm/ir:asm-syntax-error
             :message (format nil "~A requiert deux operandes (dst-bank, src-bank)" mn)
             :source-loc loc))
    (multiple-value-bind (dst ok-dst)
        (cl-asm/backend.6502:eval-operand-value op-dst symtable pc)
      (multiple-value-bind (src ok-src)
          (cl-asm/backend.6502:eval-operand-value op-src symtable pc)
        (values (list opcode
                      (if ok-dst (logand dst #xFF) 0)
                      (if ok-src (logand src #xFF) 0))
                3)))))


;;; --------------------------------------------------------------------------
;;;  Encodage d'une instruction 65816
;;; --------------------------------------------------------------------------

(defun encode-instruction-65816 (instr symtable pc pass m-long x-long)
  "Encode INSTR pour le 65816.
   M-LONG : T si accumulateur en mode 16-bit (.al)
   X-LONG : T si registres index en mode 16-bit (.xl)
   Retourne (values LISTE-OCTETS TAILLE)."
  (let* ((mn      (cl-asm/ir:ir-instruction-mnemonic instr))
         (ops     (cl-asm/ir:ir-instruction-operands  instr))
         (operand (first ops))
         (loc     (cl-asm/ir:ir-instruction-loc       instr))
         (clauses (gethash (string-upcase mn) *instructions-65816*)))

    ;; Valider le mnemonique
    (unless clauses
      (error 'cl-asm/ir:asm-unknown-mnemonic
             :mnemonic mn
             :message  (format nil "Mnemonique inconnu : ~A" mn)
             :source-loc loc))

    ;; Block move : encodage special (deux operandes)
    (when (find :block-move clauses :key #'cl-asm/backend.6502:clause-mode)
      (return-from encode-instruction-65816
        (encode-block-move instr symtable pc)))

    ;; Evaluer la valeur de l'operande principale
    (multiple-value-bind (addr-val resolved)
        (cl-asm/backend.6502:eval-operand-value operand symtable pc)

      ;; Determiner le mode d'adressage
      (let* ((mode   (if operand
                         (resolve-mode-65816 operand (if resolved addr-val nil))
                         :implied))
             (clause (find mode clauses :key #'cl-asm/backend.6502:clause-mode)))

        ;; Passe 1 avec forward-ref : estimation de taille
        (when (and (not resolved) (= pass 1))
          ;; Immediat variable : taille selon M/X courant
          (when (eq mode :immediate)
            (let ((op-size (imm-operand-size mn m-long x-long)))
              (return-from encode-instruction-65816
                (let ((total (1+ op-size)))
                  (values (make-list total :initial-element 0) total)))))
          ;; Branche longue : 3 octets
          (when (find :relative-long clauses :key #'cl-asm/backend.6502:clause-mode)
            (return-from encode-instruction-65816
              (values '(0 0 0) 3)))
          ;; Branche courte : 2 octets
          (when (find :relative clauses :key #'cl-asm/backend.6502:clause-mode)
            (return-from encode-instruction-65816
              (values '(0 0) 2)))
          ;; Sinon : taille maximum parmi les clauses
          (let ((max-bytes (reduce #'max clauses
                                   :key #'cl-asm/backend.6502:clause-bytes
                                   :initial-value 1)))
            (return-from encode-instruction-65816
              (values (make-list max-bytes :initial-element 0) max-bytes))))

        ;; Clause non trouvee : essayer les fallbacks
        (unless clause
          ;; Fallback : :relative pour les branches directes (BNE label etc.)
          (when (and resolved
                     (find :relative clauses :key #'cl-asm/backend.6502:clause-mode))
            (setf mode   :relative
                  clause (find :relative clauses :key #'cl-asm/backend.6502:clause-mode)))
          ;; Fallback : :relative-long pour BRL/PER
          (when (and resolved
                     (not clause)
                     (find :relative-long clauses :key #'cl-asm/backend.6502:clause-mode))
            (setf mode   :relative-long
                  clause (find :relative-long clauses :key #'cl-asm/backend.6502:clause-mode)))
          ;; Fallback :absolute → :absolute-long (JSL/JML : adresse toujours 24-bit)
          (when (and (eq mode :absolute)
                     (not clause))
            (let ((alt (find :absolute-long clauses :key #'cl-asm/backend.6502:clause-mode)))
              (when alt (setf mode :absolute-long clause alt))))
          ;; Fallback dp-indirect-long -> indirect absolu (JMP [$n] value <= 255)
          (when (and (eq mode :dp-indirect-long)
                     (not clause))
            (let ((alt (find :indirect clauses :key #'cl-asm/backend.6502:clause-mode)))
              (when alt (setf mode :indirect clause alt))))
          (unless clause
            (error 'cl-asm/ir:asm-syntax-error
                   :message (format nil "~A : mode d'adressage non supporte (~A)" mn mode)
                   :source-loc loc)))

        ;; Encodage selon le mode
        (let ((opcode (cl-asm/backend.6502:clause-opcode clause))
              (nbytes (cl-asm/backend.6502:clause-bytes  clause)))
          (ecase mode
            (:implied
             (values (list opcode) 1))

            (:accumulator
             (values (list opcode) 1))

            (:immediate
             ;; Si :bytes = 3 dans la clause (ex: PEA), toujours 16-bit
             ;; Sinon, taille variable selon le mnemonique et les flags M/X
             (if (= nbytes 3)
                 (values (cons opcode (cl-asm/backend.6502:encode-word-le addr-val)) 3)
                 (let ((op-size (imm-operand-size mn m-long x-long)))
                   (if (= op-size 2)
                       (values (cons opcode (cl-asm/backend.6502:encode-word-le addr-val)) 3)
                       (values (list opcode (cl-asm/backend.6502:encode-byte addr-val)) 2)))))

            ;; Modes 2 octets : opcode + 1 octet
            ((:zero-page :zero-page-x :zero-page-y
              :indirect-x :indirect-y :zero-page-indirect
              :stack-relative :sr-indirect-y
              :dp-indirect-long-y)
             (values (list opcode (cl-asm/backend.6502:encode-byte addr-val)) 2))

            ;; dp-indirect-long : 2 ou 3 octets selon :bytes dans la clause
            (:dp-indirect-long
             (if (= nbytes 3)
                 (values (cons opcode (cl-asm/backend.6502:encode-word-le addr-val)) 3)
                 (values (list opcode (cl-asm/backend.6502:encode-byte addr-val)) 2)))

            ;; Modes 3 octets : opcode + 2 octets
            ((:absolute :absolute-x :absolute-y
              :indirect :indirect-absolute-x)
             (values (cons opcode (cl-asm/backend.6502:encode-word-le addr-val)) 3))

            ;; Modes 4 octets : opcode + 3 octets
            ((:absolute-long :absolute-long-x)
             (values (cons opcode (encode-long-le addr-val)) 4))

            ;; Branche courte (offset 8-bit signe)
            (:relative
             (values (list opcode
                           (cl-asm/backend.6502:encode-relative addr-val pc loc))
                     2))

            ;; Branche longue (offset 16-bit signe)
            (:relative-long
             (values (cons opcode (encode-relative-long addr-val pc loc)) 3))))))))


;;; --------------------------------------------------------------------------
;;;  Traitement des directives avec etat M/X
;;; --------------------------------------------------------------------------

(defun process-directive-pass1-65816 (directive symtable pc mx)
  "Traite une directive en passe 1 (65816).
   MX est une liste mutable (m-long x-long) modifiee par .al/.as/.xl/.xs."
  (let ((name (cl-asm/ir:ir-directive-name directive)))
    (case name
      (:al (setf (first  mx) t)   pc)
      (:as (setf (first  mx) nil) pc)
      (:xl (setf (second mx) t)   pc)
      (:xs (setf (second mx) nil) pc)
      (otherwise
       (cl-asm/backend.6502:process-directive-pass1 directive symtable pc)))))

(defun process-directive-pass2-65816 (directive symtable pc result mx)
  "Traite une directive en passe 2 (65816).
   MX est une liste mutable (m-long x-long)."
  (let ((name (cl-asm/ir:ir-directive-name directive)))
    (case name
      (:al (setf (first  mx) t)   pc)
      (:as (setf (first  mx) nil) pc)
      (:xl (setf (second mx) t)   pc)
      (:xs (setf (second mx) nil) pc)
      (otherwise
       (cl-asm/backend.6502:process-directive-pass2 directive symtable pc result)))))


;;; --------------------------------------------------------------------------
;;;  Passes d'assemblage
;;; --------------------------------------------------------------------------

(defun pass-1-65816 (sections symtable origin)
  "Passe 1 : collecte des labels, estimation des tailles.
   Maintient l'etat M/X via les directives .al/.as/.xl/.xs."
  (let ((pc origin)
        (mx (list nil nil)))          ; (m-long x-long), defaut 8-bit
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
           (multiple-value-bind (_ nbytes)
               (encode-instruction-65816 node symtable pc 1
                                         (first mx) (second mx))
             (declare (ignore _))
             (incf pc nbytes)))
          (cl-asm/ir:ir-directive
           (setf pc (process-directive-pass1-65816
                     node symtable pc mx))))))))

(defun pass-2-65816 (sections symtable origin)
  "Passe 2 : encodage definitif.
   Maintient l'etat M/X, produit le vecteur d'octets."
  (let ((pc origin)
        (mx (list nil nil))
        (result (make-array 0 :element-type '(unsigned-byte 8)
                              :adjustable t :fill-pointer 0)))
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
               (encode-instruction-65816 node symtable pc 2
                                         (first mx) (second mx))
             (dolist (b bytes) (vector-push-extend b result))
             (incf pc nbytes)))
          (cl-asm/ir:ir-directive
           (setf pc (process-directive-pass2-65816
                     node symtable pc result mx))))))
    result))


;;; --------------------------------------------------------------------------
;;;  Points d'entree publics
;;; --------------------------------------------------------------------------

(defun assemble-65816 (program &key (origin #x8000) (section :text))
  "Assemble PROGRAM pour le WDC 65816.
   ORIGIN defaut : $8000 (LoROM SNES).
   Retourne un vecteur d'octets."
  (let* ((symtable (cl-asm/symbol-table:make-symbol-table))
         (sections (let ((main (cl-asm/ir:program-find-section
                                program section))
                         (rest (remove-if
                                (lambda (s)
                                  (eq (cl-asm/ir:ir-section-name s) section))
                                (cl-asm/ir:ir-program-sections program))))
                     (if main (cons main rest) rest))))
    (setf (cl-asm/symbol-table:st-current-pc symtable) origin)
    (pass-1-65816 sections symtable origin)
    (cl-asm/symbol-table:begin-pass-2 symtable)
    (setf (cl-asm/symbol-table:st-current-pc symtable) origin)
    (pass-2-65816 sections symtable origin)))

(defun assemble-string-65816 (source &key (origin #x8000))
  "Raccourci : parse SOURCE puis assemble pour le 65816."
  (let ((program (cl-asm/parser:parse-string source)))
    (assemble-65816 program :origin origin)))

(defun assemble-file-65816 (path &key (origin #x8000))
  "Raccourci : lit, parse et assemble le fichier a PATH pour le 65816."
  (let ((program (cl-asm/parser:parse-file path)))
    (assemble-65816 program :origin origin)))

(cl-asm/backends:register-backend
 :65816
 '("65816" "wdc65816" "snes" "apple2gs")
 "CL-ASM/BACKEND.65816" "ASSEMBLE-FILE-65816"
 "WDC 65816 / SNES / Apple IIgs"
 "WDC 65816 / SNES / Apple IIgs")
