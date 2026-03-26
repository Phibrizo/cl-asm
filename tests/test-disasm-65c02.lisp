; -*- coding: utf-8 -*-
;;; tests/test-disasm-65c02.lisp
;;;
;;; Tests unitaires pour le désassembleur WDC 65C02 / Commander X16.

(defpackage #:cl-asm/test.disasm-65c02
  (:use #:cl #:cl-asm/disassembler.65c02)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.disasm-65c02)

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

(defun mem (&rest bytes)
  (let ((m (make-array 65536 :element-type '(unsigned-byte 8) :initial-element 0)))
    (loop for b in bytes for i from 0
          do (setf (aref m (+ #x0200 i)) b))
    m))

(defun d1 (&rest bytes)
  (multiple-value-list (disasm-one (apply #'mem bytes) #x0200)))


;;; --------------------------------------------------------------------------
;;;  Opcodes 6502 hérités
;;; --------------------------------------------------------------------------

(deftest test/heritage-6502
  (check "LDA #$42"     (equal (d1 #xA9 #x42) '("LDA" "#$42" 2)))
  (check "STA $10"      (equal (d1 #x85 #x10) '("STA" "$10" 2)))
  (check "JMP $C000"    (equal (d1 #x4C #x00 #xC0) '("JMP" "$C000" 3)))
  (check "RTS"          (equal (d1 #x60) '("RTS" "" 1)))
  (check "BEQ $0212"    (equal (d1 #xF0 #x10) '("BEQ" "$0212" 2)))
  (check "LDA ($10,X)"  (equal (d1 #xA1 #x10) '("LDA" "($10,X)" 2)))
  (check "LDA ($10),Y"  (equal (d1 #xB1 #x10) '("LDA" "($10),Y" 2)))
  (check "opcode illégal $02" (equal (car (d1 #x02)) "???")))


;;; --------------------------------------------------------------------------
;;;  Nouvelles instructions 65C02
;;; --------------------------------------------------------------------------

(deftest test/bra
  ;; BRA $80 : offset $10 → target = $0200 + 2 + $10 = $0212
  (check "BRA $0212"  (equal (d1 #x80 #x10) '("BRA" "$0212" 2)))
  ;; Offset négatif : $F0 (-16) → target = $0200 + 2 - 16 = $01F2
  (check "BRA $01F2"  (equal (d1 #x80 #xF0) '("BRA" "$01F2" 2))))

(deftest test/stz
  (check "STZ $10"      (equal (d1 #x64 #x10) '("STZ" "$10" 2)))
  (check "STZ $10,X"    (equal (d1 #x74 #x10) '("STZ" "$10,X" 2)))
  (check "STZ $1234"    (equal (d1 #x9C #x34 #x12) '("STZ" "$1234" 3)))
  (check "STZ $1234,X"  (equal (d1 #x9E #x34 #x12) '("STZ" "$1234,X" 3))))

(deftest test/trb-tsb
  (check "TRB $10"   (equal (d1 #x14 #x10) '("TRB" "$10" 2)))
  (check "TRB $1234" (equal (d1 #x1C #x34 #x12) '("TRB" "$1234" 3)))
  (check "TSB $10"   (equal (d1 #x04 #x10) '("TSB" "$10" 2)))
  (check "TSB $1234" (equal (d1 #x0C #x34 #x12) '("TSB" "$1234" 3))))

(deftest test/push-pull
  (check "PHX" (equal (d1 #xDA) '("PHX" "" 1)))
  (check "PLX" (equal (d1 #xFA) '("PLX" "" 1)))
  (check "PHY" (equal (d1 #x5A) '("PHY" "" 1)))
  (check "PLY" (equal (d1 #x7A) '("PLY" "" 1))))

(deftest test/inc-dec-acc
  (check "INC A" (equal (d1 #x1A) '("INC" "A" 1)))
  (check "DEC A" (equal (d1 #x3A) '("DEC" "A" 1))))

(deftest test/zero-page-indirect
  ;; ($nn) — nouveau mode 65C02, sans index
  (check "LDA ($10)"  (equal (d1 #xB2 #x10) '("LDA" "($10)" 2)))
  (check "STA ($20)"  (equal (d1 #x92 #x20) '("STA" "($20)" 2)))
  (check "ADC ($30)"  (equal (d1 #x72 #x30) '("ADC" "($30)" 2)))
  (check "SBC ($40)"  (equal (d1 #xF2 #x40) '("SBC" "($40)" 2)))
  (check "AND ($50)"  (equal (d1 #x32 #x50) '("AND" "($50)" 2)))
  (check "ORA ($60)"  (equal (d1 #x12 #x60) '("ORA" "($60)" 2)))
  (check "EOR ($70)"  (equal (d1 #x52 #x70) '("EOR" "($70)" 2)))
  (check "CMP ($80)"  (equal (d1 #xD2 #x80) '("CMP" "($80)" 2))))

(deftest test/jmp-indirect-x
  (check "JMP ($1234,X)" (equal (d1 #x7C #x34 #x12) '("JMP" "($1234,X)" 3))))

(deftest test/bit-etendu
  (check "BIT #$42"    (equal (d1 #x89 #x42) '("BIT" "#$42" 2)))
  (check "BIT $10,X"   (equal (d1 #x34 #x10) '("BIT" "$10,X" 2)))
  (check "BIT $1234,X" (equal (d1 #x3C #x34 #x12) '("BIT" "$1234,X" 3))))


;;; --------------------------------------------------------------------------
;;;  Séquence et formatage
;;; --------------------------------------------------------------------------

(deftest test/sequence
  (let* ((m (mem #xB2 #x10   ; LDA ($10)
                 #x64 #x20   ; STZ $20
                 #x60))      ; RTS
         (result (disasm m #x0200 :count 3)))
    (check "3 instructions décodées" (= (length result) 3))
    (check "LDA ($10) à $0200"
           (equal (cddr (first result)) '("LDA" "($10)")))
    (check "STZ $20 à $0202"
           (and (= (first (second result)) #x0202)
                (string= (third (second result)) "STZ")))
    (check "RTS à $0204"
           (= (first (third result)) #x0204))))

(deftest test/disasm-string-format
  (let* ((m (mem #x7C #x34 #x12))   ; JMP ($1234,X)
         (s (disasm-string m #x0200 :count 1)))
    (check "disasm-string contient JMP"
           (and (stringp s) (search "JMP" s) (search "$1234" s)))))


;;; --------------------------------------------------------------------------
;;;  Registre des désassembleurs
;;; --------------------------------------------------------------------------

(deftest test/registre
  (let ((entry (cl-asm/disassemblers:find-disassembler-by-keyword :65c02)))
    (check "entrée :65c02 dans le registre" (not (null entry)))
    (check "alias 65c02"
           (member "65c02" (cl-asm/disassemblers:disassembler-aliases entry)
                   :test #'string=))
    (check "alias x16"
           (member "x16" (cl-asm/disassemblers:disassembler-aliases entry)
                   :test #'string=))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~%=== Désassembleur 65C02 ===~%")
  (test/heritage-6502)
  (test/bra)
  (test/stz)
  (test/trb-tsb)
  (test/push-pull)
  (test/inc-dec-acc)
  (test/zero-page-indirect)
  (test/jmp-indirect-x)
  (test/bit-etendu)
  (test/sequence)
  (test/disasm-string-format)
  (test/registre)
  (format t "~%=== disasm-65c02 : ~3D OK, ~D KO~%~%" *pass* *fail*))
