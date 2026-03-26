; -*- coding: utf-8 -*-
;;; tests/test-disasm-45gs02.lisp
;;;
;;; Tests unitaires pour le désassembleur Mega65 (45GS02).

(defpackage #:cl-asm/test.disasm-45gs02
  (:use #:cl #:cl-asm/disassembler.45gs02)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.disasm-45gs02)

(defvar *pass* 0)
(defvar *fail* 0)
(defvar *failures* '())

(defmacro check (desc expr)
  `(if ,expr
       (progn (incf *pass*)
              (format t "  OK  ~A~%" ,desc))
       (progn (incf *fail*)
              (push ,desc *failures*)
              (format t "  KO  ~A~%" ,desc))))

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&--- ~A ---~%" ',name)
     ,@body))

;;; Helper : crée une mémoire de 65536 octets avec des octets à $0200.
(defun mem (&rest bytes)
  (let ((m (make-array 65536 :element-type '(unsigned-byte 8) :initial-element 0)))
    (loop for b in bytes for i from 0
          do (setf (aref m (+ #x0200 i)) b))
    m))

;;; Helper : désassemble 1 instruction à $0200, retourne (mn op size).
(defun d1 (&rest bytes)
  (multiple-value-list (disasm-one (apply #'mem bytes) #x0200)))


;;; --------------------------------------------------------------------------
;;;  Opcodes 6502 hérités
;;; --------------------------------------------------------------------------

(deftest test/heritage-6502
  (check "LDA #$05"      (equal (d1 #xA9 #x05) '("LDA" "#$05" 2)))
  (check "LDA $10"       (equal (d1 #xA5 #x10) '("LDA" "$10" 2)))
  (check "LDA $1234"     (equal (d1 #xAD #x34 #x12) '("LDA" "$1234" 3)))
  (check "LDA $10,X"     (equal (d1 #xB5 #x10) '("LDA" "$10,X" 2)))
  (check "LDA $1234,X"   (equal (d1 #xBD #x34 #x12) '("LDA" "$1234,X" 3)))
  (check "LDA ($10,X)"   (equal (d1 #xA1 #x10) '("LDA" "($10,X)" 2)))
  (check "LDA ($10),Y"   (equal (d1 #xB1 #x10) '("LDA" "($10),Y" 2)))
  (check "STA $20"       (equal (d1 #x85 #x20) '("STA" "$20" 2)))
  (check "RTS"           (equal (d1 #x60) '("RTS" "" 1)))
  (check "JMP $C000"     (equal (d1 #x4C #x00 #xC0) '("JMP" "$C000" 3)))
  (check "BEQ $0212"     (equal (d1 #xF0 #x10) '("BEQ" "$0212" 2)))
  (check "NOP illégal"   (equal (car (d1 #x02)) "???")))


;;; --------------------------------------------------------------------------
;;;  Opcodes 45GS02 non-préfixés
;;; --------------------------------------------------------------------------

(deftest test/registre-z
  (check "LDZ #$42"      (equal (d1 #xA3 #x42) '("LDZ" "#$42" 2)))
  (check "LDZ $1234"     (equal (d1 #xAB #x34 #x12) '("LDZ" "$1234" 3)))
  (check "LDZ $1234,X"   (equal (d1 #xBB #x34 #x12) '("LDZ" "$1234,X" 3)))
  (check "INZ"           (equal (d1 #x1B) '("INZ" "" 1)))
  (check "DEZ"           (equal (d1 #x3B) '("DEZ" "" 1)))
  (check "PHZ"           (equal (d1 #xDB) '("PHZ" "" 1)))
  (check "PLZ"           (equal (d1 #xFB) '("PLZ" "" 1)))
  (check "TAZ"           (equal (d1 #x4B) '("TAZ" "" 1)))
  (check "TZA"           (equal (d1 #x6B) '("TZA" "" 1))))

(deftest test/stz-override
  ;; Sur 45GS02, $84/$94 stockent le registre Z (STZ), pas STY comme en 6502.
  (check "STZ $10 (zp)"    (equal (d1 #x84 #x10) '("STZ" "$10" 2)))
  (check "STZ $10,X (zp,x)" (equal (d1 #x94 #x10) '("STZ" "$10,X" 2)))
  (check "STZ $1234"       (equal (d1 #x9C #x34 #x12) '("STZ" "$1234" 3)))
  (check "STZ $1234,X"     (equal (d1 #x9E #x34 #x12) '("STZ" "$1234,X" 3))))

(deftest test/divers-45gs02
  (check "TBA"    (equal (d1 #xCB) '("TBA" "" 1)))
  (check "TAB"    (equal (d1 #x5B) '("TAB" "" 1)))
  (check "TSY"    (equal (d1 #x0B) '("TSY" "" 1)))
  (check "TYS"    (equal (d1 #x2B) '("TYS" "" 1)))
  (check "MAP"    (equal (d1 #x5C) '("MAP" "" 1)))
  (check "INW $10" (equal (d1 #xE3 #x10) '("INW" "$10" 2)))
  (check "DEW $20" (equal (d1 #xC3 #x20) '("DEW" "$20" 2)))
  (check "ROW $1234" (equal (d1 #xEB #x34 #x12) '("ROW" "$1234" 3)))
  (check "NEG A (seul)" (equal (d1 #x42 #x99) '("NEG" "A" 1)))
  (check "ASR A"   (equal (d1 #x43) '("ASR" "A" 1)))
  (check "ASR $10" (equal (d1 #x44 #x10) '("ASR" "$10" 2)))
  (check "ASR $10,X" (equal (d1 #x54 #x10) '("ASR" "$10,X" 2))))

(deftest test/eom-vs-prefix-ea
  ;; $EA seul (suivi d'un byte non-indirect-y) → EOM (1 octet)
  (check "EOM ($EA $00)"   (equal (d1 #xEA #x00) '("EOM" "" 1)))
  (check "EOM ($EA $42)"   (equal (d1 #xEA #x42) '("EOM" "" 1)))
  ;; $EA suivi d'un opcode indirect-y connu → indirect-32
  (check "LDA [$10]"  (equal (d1 #xEA #xB1 #x10) '("LDA" "[$10]" 3)))
  (check "STA [$20]"  (equal (d1 #xEA #x91 #x20) '("STA" "[$20]" 3)))
  (check "ADC [$30]"  (equal (d1 #xEA #x71 #x30) '("ADC" "[$30]" 3)))
  (check "SBC [$40]"  (equal (d1 #xEA #xF1 #x40) '("SBC" "[$40]" 3)))
  (check "CMP [$50]"  (equal (d1 #xEA #xD1 #x50) '("CMP" "[$50]" 3)))
  (check "AND [$60]"  (equal (d1 #xEA #x31 #x60) '("AND" "[$60]" 3)))
  (check "ORA [$70]"  (equal (d1 #xEA #x11 #x70) '("ORA" "[$70]" 3)))
  (check "EOR [$80]"  (equal (d1 #xEA #x51 #x80) '("EOR" "[$80]" 3))))


;;; --------------------------------------------------------------------------
;;;  Préfixe $42 — branches longues
;;; --------------------------------------------------------------------------

(deftest test/long-branches
  ;; Calcul de la cible : addr($0200) + 4 + offset
  ;; offset = $0010 → target = $0214
  (check "LBCC $0214"
         (equal (d1 #x42 #x90 #x10 #x00) '("LBCC" "$0214" 4)))
  (check "LBCS $0214"
         (equal (d1 #x42 #xB0 #x10 #x00) '("LBCS" "$0214" 4)))
  (check "LBEQ $0214"
         (equal (d1 #x42 #xF0 #x10 #x00) '("LBEQ" "$0214" 4)))
  (check "LBNE $0214"
         (equal (d1 #x42 #xD0 #x10 #x00) '("LBNE" "$0214" 4)))
  (check "LBMI $0214"
         (equal (d1 #x42 #x30 #x10 #x00) '("LBMI" "$0214" 4)))
  (check "LBPL $0214"
         (equal (d1 #x42 #x10 #x10 #x00) '("LBPL" "$0214" 4)))
  (check "LBVC $0214"
         (equal (d1 #x42 #x50 #x10 #x00) '("LBVC" "$0214" 4)))
  (check "LBVS $0214"
         (equal (d1 #x42 #x70 #x10 #x00) '("LBVS" "$0214" 4)))
  ;; Offset négatif : offset = $FFEC (-20) → target = $0200 + 4 - 20 = $01F0
  (check "LBNE $01F0 (offset négatif)"
         (equal (d1 #x42 #xD0 #xEC #xFF) '("LBNE" "$01F0" 4))))


;;; --------------------------------------------------------------------------
;;;  Préfixe $42 $42 — registre Q
;;; --------------------------------------------------------------------------

(deftest test/q-accumulator
  (check "ASLQ A"  (equal (d1 #x42 #x42 #x0A) '("ASLQ" "A" 3)))
  (check "LSRQ A"  (equal (d1 #x42 #x42 #x4A) '("LSRQ" "A" 3)))
  (check "ROLQ A"  (equal (d1 #x42 #x42 #x2A) '("ROLQ" "A" 3)))
  (check "RORQ A"  (equal (d1 #x42 #x42 #x6A) '("RORQ" "A" 3)))
  (check "ASRQ A"  (equal (d1 #x42 #x42 #x43) '("ASRQ" "A" 3))))

(deftest test/q-zero-page
  (check "LDQ $20"    (equal (d1 #x42 #x42 #xA5 #x20) '("LDQ"  "$20" 4)))
  (check "STQ $30"    (equal (d1 #x42 #x42 #x85 #x30) '("STQ"  "$30" 4)))
  (check "ADCQ $40"   (equal (d1 #x42 #x42 #x65 #x40) '("ADCQ" "$40" 4)))
  (check "SBCQ $50"   (equal (d1 #x42 #x42 #xE5 #x50) '("SBCQ" "$50" 4)))
  (check "ANDQ $60"   (equal (d1 #x42 #x42 #x25 #x60) '("ANDQ" "$60" 4)))
  (check "ORAQ $70"   (equal (d1 #x42 #x42 #x05 #x70) '("ORAQ" "$70" 4)))
  (check "EORQ $80"   (equal (d1 #x42 #x42 #x45 #x80) '("EORQ" "$80" 4)))
  (check "CMPQ $90"   (equal (d1 #x42 #x42 #xC5 #x90) '("CMPQ" "$90" 4)))
  (check "BITQ $10"   (equal (d1 #x42 #x42 #x24 #x10) '("BITQ" "$10" 4)))
  (check "ASLQ $20"   (equal (d1 #x42 #x42 #x06 #x20) '("ASLQ" "$20" 4)))
  (check "LSRQ $30"   (equal (d1 #x42 #x42 #x46 #x30) '("LSRQ" "$30" 4)))
  (check "ROLQ $40"   (equal (d1 #x42 #x42 #x26 #x40) '("ROLQ" "$40" 4)))
  (check "RORQ $50"   (equal (d1 #x42 #x42 #x66 #x50) '("RORQ" "$50" 4)))
  (check "ASRQ $60"   (equal (d1 #x42 #x42 #x44 #x60) '("ASRQ" "$60" 4))))

(deftest test/q-absolute
  (check "LDQ $1234" (equal (d1 #x42 #x42 #xAD #x34 #x12) '("LDQ" "$1234" 5)))
  (check "STQ $1234" (equal (d1 #x42 #x42 #x8D #x34 #x12) '("STQ" "$1234" 5))))

(deftest test/q-indirect-z
  (check "LDQ ($10),Z"  (equal (d1 #x42 #x42 #xB2 #x10) '("LDQ"  "($10),Z" 4)))
  (check "STQ ($20),Z"  (equal (d1 #x42 #x42 #x92 #x20) '("STQ"  "($20),Z" 4)))
  (check "ADCQ ($30),Z" (equal (d1 #x42 #x42 #x72 #x30) '("ADCQ" "($30),Z" 4)))
  (check "SBCQ ($40),Z" (equal (d1 #x42 #x42 #xF2 #x40) '("SBCQ" "($40),Z" 4)))
  (check "ANDQ ($50),Z" (equal (d1 #x42 #x42 #x32 #x50) '("ANDQ" "($50),Z" 4)))
  (check "ORAQ ($60),Z" (equal (d1 #x42 #x42 #x12 #x60) '("ORAQ" "($60),Z" 4)))
  (check "EORQ ($70),Z" (equal (d1 #x42 #x42 #x52 #x70) '("EORQ" "($70),Z" 4)))
  (check "CMPQ ($80),Z" (equal (d1 #x42 #x42 #xD2 #x80) '("CMPQ" "($80),Z" 4))))

(deftest test/q-indirect-32
  ;; $42 $42 $EA <opcode> zp = 5 octets
  (check "LDQ [$10]" (equal (d1 #x42 #x42 #xEA #xB2 #x10) '("LDQ" "[$10]" 5)))
  (check "STQ [$20]" (equal (d1 #x42 #x42 #xEA #x92 #x20) '("STQ" "[$20]" 5))))

(deftest test/q-opcode-inconnu
  ;; Opcode inconnu après $42 $42 → "???"
  (check "??? après $42 $42"
         (equal (d1 #x42 #x42 #xFF) '("???" "" 1))))


;;; --------------------------------------------------------------------------
;;;  Désassemblage de séquences
;;; --------------------------------------------------------------------------

(deftest test/disasm-sequence
  (let* ((bytes (list #xA3 #x42        ; LDZ #$42  (2)
                      #x42 #x42 #xA5 #x10  ; LDQ $10   (4)
                      #x60))               ; RTS       (1)
         (m (apply #'mem bytes))
         (result (disasm m #x0200 :count 3)))
    (check "sequence: 3 instructions décodées"
           (= (length result) 3))
    (check "sequence: LDZ #$42"
           (equal (cddr (first result)) '("LDZ" "#$42")))
    (check "sequence: LDQ $10 à $0202"
           (and (= (first (second result)) #x0202)
                (string= (third (second result)) "LDQ")))
    (check "sequence: RTS à $0206"
           (and (= (first (third result)) #x0206)
                (string= (third (third result)) "RTS")))))

(deftest test/disasm-string-format
  (let* ((m (mem #x42 #x42 #xAD #x34 #x12))  ; LDQ $1234
         (s (disasm-string m #x0200 :count 1)))
    (check "disasm-string contient LDQ"
           (and (stringp s)
                (search "LDQ" s)
                (search "$1234" s)))))


;;; --------------------------------------------------------------------------
;;;  Registre des désassembleurs
;;; --------------------------------------------------------------------------

(deftest test/registre
  (let ((entry (cl-asm/disassemblers:find-disassembler-by-keyword :45gs02)))
    (check "entrée :45gs02 dans le registre"
           (not (null entry)))
    (check "alias 45gs02"
           (member "45gs02" (cl-asm/disassemblers:disassembler-aliases entry)
                   :test #'string=))
    (check "alias mega65"
           (member "mega65" (cl-asm/disassemblers:disassembler-aliases entry)
                   :test #'string=)))
  (let ((entry-6502 (cl-asm/disassemblers:find-disassembler-by-keyword :6502)))
    (check "entrée :6502 dans le registre"
           (not (null entry-6502)))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~%=== Désassembleur 45GS02 ===~%")
  (test/heritage-6502)
  (test/registre-z)
  (test/stz-override)
  (test/divers-45gs02)
  (test/eom-vs-prefix-ea)
  (test/long-branches)
  (test/q-accumulator)
  (test/q-zero-page)
  (test/q-absolute)
  (test/q-indirect-z)
  (test/q-indirect-32)
  (test/q-opcode-inconnu)
  (test/disasm-sequence)
  (test/disasm-string-format)
  (test/registre)
  (format t "~%=== disasm-45gs02: ~3D OK, ~D KO~%~%" *pass* *fail*))
