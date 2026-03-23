; -*- coding: utf-8 -*-
;;; tests/test-disasm-6502.lisp
;;;
;;; Tests unitaires pour le désassembleur 6502.

(defpackage #:cl-asm/test.disasm-6502
  (:use #:cl #:cl-asm/disassembler.6502)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.disasm-6502)

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

;;; Helper : crée un vecteur de 65536 octets mis à zéro, puis initialise les
;;; zones spécifiées par des couples (addr byte1 byte2 ...).
(defun make-mem (&rest specs)
  "Crée une mémoire de 65536 octets.
Chaque SPEC est (addr . bytes)."
  (let ((mem (make-array 65536 :element-type '(unsigned-byte 8) :initial-element 0)))
    (dolist (s specs mem)
      (let ((addr (car s)) (bytes (cdr s)))
        (loop for b in bytes for i from 0
              do (setf (aref mem (logand (+ addr i) #xFFFF)) b))))))

;;; Helper raccourci : octets à partir de $0200
(defun mem (&rest bytes)
  (apply #'make-mem (list (list* #x0200 bytes))))


;;; --------------------------------------------------------------------------
;;;  Tests : disasm-one — modes d'adressage
;;; --------------------------------------------------------------------------

(deftest test/disasm-one-implied
  (multiple-value-bind (mn op size) (disasm-one (mem #xEA) #x0200)   ; NOP
    (check "NOP — mnemonic" (string= mn "NOP"))
    (check "NOP — operand vide" (string= op ""))
    (check "NOP — size=1" (= size 1)))
  (multiple-value-bind (mn op size) (disasm-one (mem #x60) #x0200)   ; RTS
    (check "RTS — ok" (and (string= mn "RTS") (= size 1) (string= op ""))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x18) #x0200)   ; CLC
    (check "CLC — ok" (and (string= mn "CLC") (= size 1))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x38) #x0200)   ; SEC
    (check "SEC — ok" (and (string= mn "SEC") (= size 1))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x48) #x0200)   ; PHA
    (check "PHA — ok" (and (string= mn "PHA") (= size 1))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x68) #x0200)   ; PLA
    (check "PLA — ok" (and (string= mn "PLA") (= size 1))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x00) #x0200)   ; BRK
    (check "BRK — ok" (and (string= mn "BRK") (= size 1)))))

(deftest test/disasm-one-accumulator
  (multiple-value-bind (mn op size) (disasm-one (mem #x0A) #x0200)   ; ASL A
    (check "ASL A — mnemonic" (string= mn "ASL"))
    (check "ASL A — operand=A" (string= op "A"))
    (check "ASL A — size=1" (= size 1)))
  (multiple-value-bind (mn op size) (disasm-one (mem #x4A) #x0200)   ; LSR A
    (check "LSR A — ok" (and (string= mn "LSR") (string= op "A") (= size 1))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x2A) #x0200)   ; ROL A
    (check "ROL A — ok" (and (string= mn "ROL") (string= op "A") (= size 1))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x6A) #x0200)   ; ROR A
    (check "ROR A — ok" (and (string= mn "ROR") (string= op "A") (= size 1)))))

(deftest test/disasm-one-immediate
  (multiple-value-bind (mn op size) (disasm-one (mem #xA9 #x42) #x0200)  ; LDA #$42
    (check "LDA #$42 — mnemonic" (string= mn "LDA"))
    (check "LDA #$42 — operand" (string= op "#$42"))
    (check "LDA #$42 — size=2" (= size 2)))
  (multiple-value-bind (mn op size) (disasm-one (mem #xA2 #xFF) #x0200)  ; LDX #$FF
    (check "LDX #$FF" (and (string= mn "LDX") (string= op "#$FF") (= size 2))))
  (multiple-value-bind (mn op size) (disasm-one (mem #xA0 #x00) #x0200)  ; LDY #$00
    (check "LDY #$00" (and (string= mn "LDY") (string= op "#$00") (= size 2))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x69 #x05) #x0200)  ; ADC #$05
    (check "ADC #$05" (and (string= mn "ADC") (string= op "#$05") (= size 2))))
  (multiple-value-bind (mn op size) (disasm-one (mem #xE9 #x01) #x0200)  ; SBC #$01
    (check "SBC #$01" (and (string= mn "SBC") (string= op "#$01") (= size 2))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x09 #x0F) #x0200)  ; ORA #$0F
    (check "ORA #$0F" (and (string= mn "ORA") (string= op "#$0F") (= size 2))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x29 #xF0) #x0200)  ; AND #$F0
    (check "AND #$F0" (and (string= mn "AND") (string= op "#$F0") (= size 2))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x49 #x55) #x0200)  ; EOR #$55
    (check "EOR #$55" (and (string= mn "EOR") (string= op "#$55") (= size 2))))
  (multiple-value-bind (mn op size) (disasm-one (mem #xC9 #x10) #x0200)  ; CMP #$10
    (check "CMP #$10" (and (string= mn "CMP") (string= op "#$10") (= size 2)))))

(deftest test/disasm-one-zero-page
  (multiple-value-bind (mn op size) (disasm-one (mem #xA5 #x10) #x0200)  ; LDA $10
    (check "LDA $10 — mnemonic" (string= mn "LDA"))
    (check "LDA $10 — operand" (string= op "$10"))
    (check "LDA $10 — size=2" (= size 2)))
  (multiple-value-bind (mn op size) (disasm-one (mem #x85 #x20) #x0200)  ; STA $20
    (check "STA $20" (and (string= mn "STA") (string= op "$20") (= size 2))))
  (multiple-value-bind (mn op size) (disasm-one (mem #xB5 #x30) #x0200)  ; LDA $30,X
    (check "LDA $30,X — mnemonic" (string= mn "LDA"))
    (check "LDA $30,X — operand" (string= op "$30,X"))
    (check "LDA $30,X — size=2" (= size 2)))
  (multiple-value-bind (mn op size) (disasm-one (mem #xB6 #x40) #x0200)  ; LDX $40,Y
    (check "LDX $40,Y" (and (string= mn "LDX") (string= op "$40,Y") (= size 2))))
  (multiple-value-bind (mn op size) (disasm-one (mem #xC6 #x50) #x0200)  ; DEC $50
    (check "DEC $50" (and (string= mn "DEC") (string= op "$50") (= size 2))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x24 #x01) #x0200)  ; BIT $01
    (check "BIT $01" (and (string= mn "BIT") (string= op "$01") (= size 2)))))

(deftest test/disasm-one-absolute
  (multiple-value-bind (mn op size) (disasm-one (mem #xAD #x00 #x02) #x0200)  ; LDA $0200
    (check "LDA $0200 — mnemonic" (string= mn "LDA"))
    (check "LDA $0200 — operand" (string= op "$0200"))
    (check "LDA $0200 — size=3" (= size 3)))
  (multiple-value-bind (mn op size) (disasm-one (mem #x8D #x00 #xD0) #x0200)  ; STA $D000
    (check "STA $D000" (and (string= mn "STA") (string= op "$D000") (= size 3))))
  (multiple-value-bind (mn op size) (disasm-one (mem #xBD #x00 #x03) #x0200)  ; LDA $0300,X
    (check "LDA $0300,X" (and (string= mn "LDA") (string= op "$0300,X") (= size 3))))
  (multiple-value-bind (mn op size) (disasm-one (mem #xB9 #x00 #x04) #x0200)  ; LDA $0400,Y
    (check "LDA $0400,Y" (and (string= mn "LDA") (string= op "$0400,Y") (= size 3))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x4C #x00 #x06) #x0200)  ; JMP $0600
    (check "JMP $0600" (and (string= mn "JMP") (string= op "$0600") (= size 3))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x20 #x50 #x03) #x0200)  ; JSR $0350
    (check "JSR $0350" (and (string= mn "JSR") (string= op "$0350") (= size 3))))
  (multiple-value-bind (mn op size) (disasm-one (mem #xEE #x00 #x02) #x0200)  ; INC $0200
    (check "INC $0200" (and (string= mn "INC") (string= op "$0200") (= size 3)))))

(deftest test/disasm-one-indirect
  (multiple-value-bind (mn op size) (disasm-one (mem #x6C #xFC #xFF) #x0200)  ; JMP ($FFFC)
    (check "JMP ($FFFC) — mnemonic" (string= mn "JMP"))
    (check "JMP ($FFFC) — operand" (string= op "($FFFC)"))
    (check "JMP ($FFFC) — size=3" (= size 3)))
  (multiple-value-bind (mn op size) (disasm-one (mem #xA1 #x20) #x0200)       ; LDA ($20,X)
    (check "LDA ($20,X)" (and (string= mn "LDA") (string= op "($20,X)") (= size 2))))
  (multiple-value-bind (mn op size) (disasm-one (mem #xB1 #x30) #x0200)       ; LDA ($30),Y
    (check "LDA ($30),Y" (and (string= mn "LDA") (string= op "($30),Y") (= size 2))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x81 #x10) #x0200)       ; STA ($10,X)
    (check "STA ($10,X)" (and (string= mn "STA") (string= op "($10,X)") (= size 2))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x91 #x20) #x0200)       ; STA ($20),Y
    (check "STA ($20),Y" (and (string= mn "STA") (string= op "($20),Y") (= size 2)))))

(deftest test/disasm-one-relative
  ;; BNE $D0 offset $02 → target = $0200 + 2 + 2 = $0204
  (multiple-value-bind (mn op size) (disasm-one (mem #xD0 #x02) #x0200)
    (check "BNE +2 — mnemonic" (string= mn "BNE"))
    (check "BNE +2 — target $0204" (string= op "$0204"))
    (check "BNE +2 — size=2" (= size 2)))
  ;; BEQ offset $00 → target = $0200 + 2 + 0 = $0202
  (multiple-value-bind (mn op size) (disasm-one (mem #xF0 #x00) #x0200)
    (check "BEQ +0 → $0202" (and (string= mn "BEQ") (string= op "$0202"))))
  ;; BPL offset $FE = -2 → target = $0200 + 2 - 2 = $0200
  (multiple-value-bind (mn op size) (disasm-one (mem #x10 #xFE) #x0200)
    (check "BPL -2 → $0200" (and (string= mn "BPL") (string= op "$0200") (= size 2))))
  ;; BMI offset $80 = -128 → target = $0300 + 2 - 128 = $0282
  (let ((m (apply #'make-mem (list (list* #x0300 '(#x30 #x80))))))
    (multiple-value-bind (mn op size) (disasm-one m #x0300)
      (check "BMI -128 → $0282" (and (string= mn "BMI") (string= op "$0282")))))
  ;; BVC offset $10 → $0200 + 2 + 16 = $0212
  (multiple-value-bind (mn op size) (disasm-one (mem #x50 #x10) #x0200)
    (check "BVC +16 → $0212" (and (string= mn "BVC") (string= op "$0212"))))
  ;; BCC offset $7F = +127 → $0200 + 2 + 127 = $0281
  (multiple-value-bind (mn op size) (disasm-one (mem #x90 #x7F) #x0200)
    (check "BCC +127 → $0281" (and (string= mn "BCC") (string= op "$0281"))))
  ;; BCS, BVS
  (multiple-value-bind (mn op size) (disasm-one (mem #xB0 #x0A) #x0200)
    (check "BCS +10 → $020C" (and (string= mn "BCS") (string= op "$020C"))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x70 #x04) #x0200)
    (check "BVS +4 → $0206" (and (string= mn "BVS") (string= op "$0206")))))

(deftest test/disasm-one-illegal
  (multiple-value-bind (mn op size) (disasm-one (mem #x02) #x0200)
    (check "opcode $02 — ??? " (string= mn "???"))
    (check "opcode $02 — operand vide" (string= op ""))
    (check "opcode $02 — size=1" (= size 1)))
  (multiple-value-bind (mn op size) (disasm-one (mem #xFF) #x0200)
    (check "opcode $FF illégal" (and (string= mn "???") (= size 1))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x80) #x0200)
    (check "opcode $80 illégal" (and (string= mn "???") (= size 1))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x12) #x0200)
    (check "opcode $12 illégal" (and (string= mn "???") (= size 1))))
  (multiple-value-bind (mn op size) (disasm-one (mem #x03) #x0200)
    (check "opcode $03 illégal" (and (string= mn "???") (= size 1)))))


;;; --------------------------------------------------------------------------
;;;  Tests : disasm — séquences
;;; --------------------------------------------------------------------------

(deftest test/disasm-sequence
  ;; $0200: A9 42  LDA #$42
  ;; $0202: 85 00  STA $00
  ;; $0204: 60     RTS
  (let* ((m (mem #xA9 #x42 #x85 #x00 #x60))
         (result (disasm m #x0200 :count 3)))
    (check "disasm 3 lignes" (= (length result) 3))
    (destructuring-bind (pc hex mn op) (first result)
      (check "ligne 1 — addr $0200" (= pc #x0200))
      (check "ligne 1 — hex A9 42" (string= hex "A9 42"))
      (check "ligne 1 — LDA" (string= mn "LDA"))
      (check "ligne 1 — #$42" (string= op "#$42")))
    (destructuring-bind (pc hex mn op) (second result)
      (check "ligne 2 — addr $0202" (= pc #x0202))
      (check "ligne 2 — hex 85 00" (string= hex "85 00"))
      (check "ligne 2 — STA" (string= mn "STA"))
      (check "ligne 2 — $00" (string= op "$00")))
    (destructuring-bind (pc hex mn op) (third result)
      (check "ligne 3 — addr $0204" (= pc #x0204))
      (check "ligne 3 — hex 60" (string= hex "60"))
      (check "ligne 3 — RTS" (string= mn "RTS"))
      (check "ligne 3 — operand vide" (string= op ""))))
  ;; Boucle : LDX #$0A / DEX / BNE →DEX / RTS
  ;; $0300: A2 0A  LDX #$0A
  ;; $0302: CA     DEX
  ;; $0303: D0 FD  BNE (offset $FD=-3 → $0303+2-3=$0302)
  ;; $0305: 60     RTS
  (let* ((m (apply #'make-mem (list (list* #x0300 '(#xA2 #x0A #xCA #xD0 #xFD #x60)))))
         (result (disasm m #x0300 :count 4)))
    (check "boucle — 4 lignes" (= (length result) 4))
    (destructuring-bind (pc hex mn op) (third result)
      (declare (ignore hex))
      (check "BNE addr $0303" (= pc #x0303))
      (check "BNE → $0302" (and (string= mn "BNE") (string= op "$0302"))))))

(deftest test/disasm-default-count
  ;; Sans :count, doit retourner 10 instructions
  (let* ((m (make-array 65536 :element-type '(unsigned-byte 8) :initial-element #xEA))
         (result (disasm m #x0000)))
    (check "count par défaut = 10" (= (length result) 10))))

(deftest test/disasm-wraparound
  ;; Instruction à cheval sur $FFFF/$0000
  (let ((m (make-array 65536 :element-type '(unsigned-byte 8) :initial-element 0)))
    (setf (aref m #xFFFF) #xA9)    ; LDA imm
    (setf (aref m #x0000) #xFF)    ; opérande $FF
    (multiple-value-bind (mn op size) (disasm-one m #xFFFF)
      (check "wraparound — LDA" (string= mn "LDA"))
      (check "wraparound — #$FF" (string= op "#$FF"))
      (check "wraparound — size=2" (= size 2)))))


;;; --------------------------------------------------------------------------
;;;  Tests : disasm-string — format textuel
;;; --------------------------------------------------------------------------

(deftest test/disasm-string-format
  ;; "$0200  A9 05     LDA #$05"
  (let* ((m (mem #xA9 #x05))
         (s (string-right-trim '(#\Newline #\Return) (disasm-string m #x0200 :count 1))))
    (check "format LDA #$05" (string= s "$0200  A9 05     LDA #$05")))
  ;; NOP sans opérande : "$0200  EA        NOP"
  (let* ((m (mem #xEA))
         (s (string-right-trim '(#\Newline #\Return) (disasm-string m #x0200 :count 1))))
    (check "format NOP" (string= s "$0200  EA        NOP")))
  ;; Instruction 3 octets : "$0200  20 50 03  JSR $0350"
  (let* ((m (mem #x20 #x50 #x03))
         (s (string-right-trim '(#\Newline #\Return) (disasm-string m #x0200 :count 1))))
    (check "format JSR $0350" (string= s "$0200  20 50 03  JSR $0350")))
  ;; Deux lignes : 2 newlines
  (let* ((m (mem #xA9 #x00 #x60))
         (s (disasm-string m #x0200 :count 2)))
    (check "2 lignes → 2 newlines" (= (count #\Newline s) 2)))
  ;; Dix lignes de NOP
  (let* ((m (make-array 65536 :element-type '(unsigned-byte 8) :initial-element #xEA))
         (s (disasm-string m #x0200 :count 10)))
    (check "10 NOP → 10 newlines" (= (count #\Newline s) 10))))

(deftest test/disasm-string-stream
  (let* ((m (mem #xEA))
         (out (make-string-output-stream)))
    (disasm-string m #x0200 :count 1 :stream out)
    (let ((s (get-output-stream-string out)))
      (check "stream : contient NOP" (and (> (length s) 0) (search "NOP" s)))))
  ;; print-disasm
  (let* ((m (mem #xA9 #x42))
         (out (make-string-output-stream)))
    (print-disasm m #x0200 :count 1 :stream out)
    (let ((s (get-output-stream-string out)))
      (check "print-disasm contient LDA" (search "LDA" s))
      (check "print-disasm contient #$42" (search "#$42" s)))))


;;; --------------------------------------------------------------------------
;;;  Tests : *opcode-table* — intégrité
;;; --------------------------------------------------------------------------

(deftest test/opcode-table
  (check "taille 256" (= (length *opcode-table*) 256))
  ;; Entrées connues
  (let ((e (aref *opcode-table* #xEA)))
    (check "$EA = NOP implied" (and e (string= (car e) "NOP") (eq (cdr e) :implied))))
  (let ((e (aref *opcode-table* #xA9)))
    (check "$A9 = LDA immediate" (and e (string= (car e) "LDA") (eq (cdr e) :immediate))))
  (let ((e (aref *opcode-table* #x20)))
    (check "$20 = JSR absolute" (and e (string= (car e) "JSR") (eq (cdr e) :absolute))))
  (let ((e (aref *opcode-table* #x4C)))
    (check "$4C = JMP absolute" (and e (string= (car e) "JMP") (eq (cdr e) :absolute))))
  (let ((e (aref *opcode-table* #x6C)))
    (check "$6C = JMP indirect" (and e (string= (car e) "JMP") (eq (cdr e) :indirect))))
  (let ((e (aref *opcode-table* #x00)))
    (check "$00 = BRK implied" (and e (string= (car e) "BRK") (eq (cdr e) :implied))))
  (let ((e (aref *opcode-table* #x0A)))
    (check "$0A = ASL accumulator" (and e (string= (car e) "ASL") (eq (cdr e) :accumulator))))
  (let ((e (aref *opcode-table* #xD0)))
    (check "$D0 = BNE relative" (and e (string= (car e) "BNE") (eq (cdr e) :relative))))
  ;; Opcodes illégaux
  (check "$02 = NIL" (null (aref *opcode-table* #x02)))
  (check "$12 = NIL" (null (aref *opcode-table* #x12)))
  (check "$22 = NIL" (null (aref *opcode-table* #x22)))
  (check "$FF = NIL" (null (aref *opcode-table* #xFF)))
  (check "$80 = NIL" (null (aref *opcode-table* #x80)))
  ;; Exactement 151 opcodes légaux
  (let ((n (count-if #'identity *opcode-table*)))
    (check "151 opcodes légaux" (= n 151))))


;;; --------------------------------------------------------------------------
;;;  Tests : round-trip (octets connus → désassemblage)
;;; --------------------------------------------------------------------------

(deftest test/roundtrip
  ;; Séquence :
  ;;   $0400: A9 00        LDA #$00
  ;;   $0402: 8D 20 D0     STA $D020
  ;;   $0405: A2 08        LDX #$08
  ;;   $0407: CA           DEX
  ;;   $0408: D0 FD        BNE $0407  (offset $FD=-3 → $0408+2-3=$0407)
  ;;   $040A: 60           RTS
  (let* ((m (apply #'make-mem
                   (list (list* #x0400
                                '(#xA9 #x00 #x8D #x20 #xD0 #xA2 #x08
                                  #xCA #xD0 #xFD #x60)))))
         (result (disasm m #x0400 :count 6)))
    (check "roundtrip — 6 instructions" (= (length result) 6))
    (check "roundtrip — LDA" (string= (third (first result)) "LDA"))
    (check "roundtrip — STA" (string= (third (second result)) "STA"))
    (check "roundtrip — STA $D020" (string= (fourth (second result)) "$D020"))
    (check "roundtrip — LDX" (string= (third (third result)) "LDX"))
    (check "roundtrip — DEX" (string= (third (fourth result)) "DEX"))
    (check "roundtrip — BNE" (string= (third (fifth result)) "BNE"))
    (check "roundtrip — BNE cible $0407" (string= (fourth (fifth result)) "$0407"))
    (check "roundtrip — RTS" (string= (third (sixth result)) "RTS"))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests désassembleur 6502 ===~%")
  (test/disasm-one-implied)
  (test/disasm-one-accumulator)
  (test/disasm-one-immediate)
  (test/disasm-one-zero-page)
  (test/disasm-one-absolute)
  (test/disasm-one-indirect)
  (test/disasm-one-relative)
  (test/disasm-one-illegal)
  (test/disasm-sequence)
  (test/disasm-default-count)
  (test/disasm-wraparound)
  (test/disasm-string-format)
  (test/disasm-string-stream)
  (test/opcode-table)
  (test/roundtrip)
  (when *failures*
    (format t "~&Echecs disasm-6502 :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
