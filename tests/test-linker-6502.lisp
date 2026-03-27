; -*- coding: utf-8 -*-
;;; tests/test-linker-6502.lisp
;;;
;;; Tests unitaires pour le linker modulaire en mémoire (famille 6502).

(defpackage #:cl-asm/test.linker-6502
  (:use #:cl
        #:cl-asm/linker)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.linker-6502)

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

;;; Helpers

(defun parse (src)
  (cl-asm/parser:parse-string src))

(defun bytes (&rest args) (coerce args '(vector (unsigned-byte 8))))

;;; --------------------------------------------------------------------------
;;;  Registre des backends
;;; --------------------------------------------------------------------------

(deftest test-registry
  (check "backend :6502 enregistré"
         (not (null (find-linker-backend :6502))))
  (check "backend :6510 enregistré"
         (not (null (find-linker-backend :6510))))
  (check "backend :65c02 enregistré"
         (not (null (find-linker-backend :65c02))))
  (check "backend :45gs02 enregistré"
         (not (null (find-linker-backend :45gs02))))
  (check "alias \"6502\" reconnu"
         (not (null (find-linker-backend "6502"))))
  (check "alias \"c64\" reconnu"
         (not (null (find-linker-backend "c64"))))
  (check "alias \"mega65\" reconnu"
         (not (null (find-linker-backend "mega65"))))
  (check "backend inconnu → NIL"
         (null (find-linker-backend :z80)))
  (check "au moins 4 backends listés"
         (>= (length (all-linker-backends)) 4)))

;;; --------------------------------------------------------------------------
;;;  Linkage d'une seule unité (équivalent à assemble)
;;; --------------------------------------------------------------------------

(deftest test-single-unit-6502
  (let* ((prog (parse "LDA #$FF
                       RTS"))
         (unit (link-unit-from-program "test" prog :6502))
         (result (link (list unit) :origin #x0000)))
    (check "single unit 6502 — LDA #$FF RTS"
           (equalp result (bytes #xA9 #xFF #x60))))

  (let* ((prog (parse ".org $0200
                       NOP
                       NOP
                       RTS"))
         (unit (link-unit-from-program "test" prog :6502))
         (result (link (list unit) :origin #x0000)))
    (check "single unit 6502 — .org override"
           (equalp result (bytes #xEA #xEA #x60)))))

(deftest test-single-unit-with-labels
  (let* ((prog (parse "start: LDA #$01
                              STA $10
                              JMP start"))
         (unit (link-unit-from-program "test" prog :6502))
         (result (link (list unit) :origin #x0200)))
    ;; start = $0200 → JMP $0200 = $4C $00 $02
    (check "single unit — label forward ref"
           (equalp result (bytes #xA9 #x01 #x85 #x10 #x4C #x00 #x02)))))

;;; --------------------------------------------------------------------------
;;;  Linkage de deux unités — références croisées
;;; --------------------------------------------------------------------------

(deftest test-two-units-cross-reference
  ;; unit1 définit "main" et appelle "helper" (défini dans unit2)
  ;; unit2 définit "helper"
  ;; Le linkage doit résoudre les deux labels dans la table partagée
  (let* ((src1 "main: JSR helper
                      RTS")
         (src2 "helper: LDA #$42
                        RTS")
         (u1 (link-unit-from-program "main"   (parse src1) :6502))
         (u2 (link-unit-from-program "helper" (parse src2) :6502))
         (result (link (list u1 u2) :origin #x0200)))
    ;; main   = $0200 : JSR helper ($0206) = $20 $06 $02
    ;;                   RTS                = $60
    ;; helper = $0204 : LDA #$42            = $A9 $42
    ;;                   RTS                = $60
    (check "deux unités — cross-ref JSR"
           (equalp result (bytes #x20 #x04 #x02   ; JSR $0204
                                 #x60             ; RTS
                                 #xA9 #x42        ; LDA #$42
                                 #x60)))))        ; RTS

(deftest test-two-units-shared-constant
  ;; unit1 définit une constante via .equ, unit2 l'utilise
  (let* ((src1 ".equ KERNAL_CHROUT = $FFD2
                JSR KERNAL_CHROUT
                RTS")
         (src2 "again: JSR KERNAL_CHROUT
                       BNE again")
         (u1 (link-unit-from-program "unit1" (parse src1) :6502))
         (u2 (link-unit-from-program "unit2" (parse src2) :6502))
         (result (link (list u1 u2) :origin #x0200)))
    ;; $0200 : JSR $FFD2 = $20 $D2 $FF
    ;; $0203 : RTS       = $60
    ;; $0204 (again): JSR $FFD2 = $20 $D2 $FF
    ;; $0207 : BNE again ($0204 → offset -5 = $FB) = $D0 $FB
    (check "deux unités — constante .equ partagée"
           (equalp result (bytes #x20 #xD2 #xFF   ; JSR $FFD2
                                 #x60             ; RTS
                                 #x20 #xD2 #xFF   ; JSR $FFD2
                                 #xD0 #xFB)))))   ; BNE again

(deftest test-three-units
  (let* ((u1 (link-unit-from-program "a" (parse "LDA #$01") :6502))
         (u2 (link-unit-from-program "b" (parse "LDA #$02") :6502))
         (u3 (link-unit-from-program "c" (parse "LDA #$03") :6502))
         (result (link (list u1 u2 u3) :origin #x0000)))
    (check "trois unités concaténées"
           (equalp result (bytes #xA9 #x01 #xA9 #x02 #xA9 #x03)))))

;;; --------------------------------------------------------------------------
;;;  Linkage avec le backend 6510 (opcodes illégaux)
;;; --------------------------------------------------------------------------

(deftest test-single-unit-6510
  (let* ((prog (parse "LAX $10"))
         (unit (link-unit-from-program "test" prog :6510))
         (result (link (list unit) :origin #x0200)))
    (check "unit 6510 — LAX zero-page"
           (equalp result (bytes #xA7 #x10))))

  (let* ((src1 "SAX $20")
         (src2 "LAX $30")
         (u1 (link-unit-from-program "u1" (parse src1) :6510))
         (u2 (link-unit-from-program "u2" (parse src2) :6510))
         (result (link (list u1 u2) :origin #x0300)))
    (check "deux unités 6510 — opcodes illégaux"
           (equalp result (bytes #x87 #x20   ; SAX $20
                                 #xA7 #x30))))) ; LAX $30

;;; --------------------------------------------------------------------------
;;;  Linkage avec le backend 65c02
;;; --------------------------------------------------------------------------

(deftest test-single-unit-65c02
  (let* ((prog (parse "BRA next
                       NOP
                       next: RTS"))
         (unit (link-unit-from-program "test" prog :65c02))
         (result (link (list unit) :origin #x0000)))
    ;; BRA next : $80 $01 (offset +1 → NOP, puis RTS)
    (check "unit 65c02 — BRA forward"
           (equalp result (bytes #x80 #x01 #xEA #x60))))

  (let* ((src1 "STZ $10")
         (src2 "RTS")
         (u1 (link-unit-from-program "u1" (parse src1) :65c02))
         (u2 (link-unit-from-program "u2" (parse src2) :65c02))
         (result (link (list u1 u2) :origin #x0000)))
    (check "deux unités 65c02 — STZ + RTS"
           (equalp result (bytes #x64 #x10 #x60)))))

;;; --------------------------------------------------------------------------
;;;  Linkage avec le backend 45gs02
;;; --------------------------------------------------------------------------

(deftest test-single-unit-45gs02
  (let* ((prog (parse "INZ
                       DEZ
                       RTS"))
         (unit (link-unit-from-program "test" prog :45gs02))
         (result (link (list unit) :origin #x2001)))
    (check "unit 45gs02 — INZ DEZ RTS"
           (equalp result (bytes #x1B #x3B #x60)))))

;;; --------------------------------------------------------------------------
;;;  link-unit-from-program — constructeur de commodité
;;; --------------------------------------------------------------------------

(deftest test-link-unit-from-program
  (let* ((prog (parse "NOP"))
         (unit (link-unit-from-program "myfile.asm" prog :6502)))
    (check "name correct"
           (string= (link-unit-name unit) "myfile.asm"))
    (check "target correct"
           (eq (link-unit-target unit) :6502))
    (check "sections non nulles"
           (not (null (link-unit-sections unit))))))

;;; --------------------------------------------------------------------------
;;;  Gestion des erreurs
;;; --------------------------------------------------------------------------

(deftest test-error-unknown-backend
  (let* ((prog (parse "NOP"))
         (unit (link-unit-from-program "test" prog :z80)))
    (check "backend inconnu → erreur"
           (handler-case
               (progn (link (list unit) :origin #x0000) nil)
             (error () t)))))

(deftest test-error-mixed-targets
  (let* ((u1 (link-unit-from-program "a" (parse "NOP") :6502))
         (u2 (link-unit-from-program "b" (parse "NOP") :6510)))
    (check "cibles mixtes → erreur"
           (handler-case
               (progn (link (list u1 u2) :origin #x0000) nil)
             (error () t)))))

(deftest test-error-empty-units
  (check "liste vide → erreur"
         (handler-case
             (progn (link '() :origin #x0000) nil)
           (error () t))))

;;; --------------------------------------------------------------------------
;;;  Point d'entrée
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Suite : test-linker-6502 ===~%")
  (test-registry)
  (test-single-unit-6502)
  (test-single-unit-with-labels)
  (test-two-units-cross-reference)
  (test-two-units-shared-constant)
  (test-three-units)
  (test-single-unit-6510)
  (test-single-unit-65c02)
  (test-single-unit-45gs02)
  (test-link-unit-from-program)
  (test-error-unknown-backend)
  (test-error-mixed-targets)
  (test-error-empty-units)
  (format t "~&--- Résultat : ~D OK, ~D KO sur ~D tests ---~%"
          *pass* *fail* (+ *pass* *fail*))
  (when *failures*
    (format t "Échecs :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (values *pass* *fail*))
