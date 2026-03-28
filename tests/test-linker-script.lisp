; -*- coding: utf-8 -*-
;;; tests/test-linker-script.lisp
;;;
;;; Tests unitaires pour le linker script multi-segments.

(defpackage #:cl-asm/test.linker-script
  (:use #:cl
        #:cl-asm/linker
        #:cl-asm/linker-script)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.linker-script)

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

(defun unit (name src &optional (target :6502))
  (link-unit-from-program name (parse src) target))

(defun seg (name at src &optional (target :6502))
  (make-script-segment :name name :at at
                       :units (list (unit name src target))))

(defun bytes (&rest args) (coerce args '(vector (unsigned-byte 8))))

;;; --------------------------------------------------------------------------
;;;  Segment unique (équivalent au linker simple)
;;; --------------------------------------------------------------------------

(deftest test-single-segment
  ;; Un seul segment se comporte comme link
  (let* ((s (seg "main" #x0000 "LDA #$FF
                               RTS"))
         (results (link-segments (list s)))
         (r (first results)))
    (check "single segment — nom correct"
           (string= (script-result-name r) "main"))
    (check "single segment — adresse correcte"
           (= (script-result-address r) #x0000))
    (check "single segment — octets LDA #$FF RTS"
           (equalp (script-result-bytes r) (bytes #xA9 #xFF #x60)))))

;;; --------------------------------------------------------------------------
;;;  Deux segments sans référence croisée
;;; --------------------------------------------------------------------------

(deftest test-two-segments-independent
  (let* ((s1 (seg "seg1" #x0200 "NOP
                               NOP"))
         (s2 (seg "seg2" #x0208 "RTS"))
         (results (link-segments (list s1 s2)))
         (r1 (first results))
         (r2 (second results)))
    (check "deux segments — r1 adresse $0200"
           (= (script-result-address r1) #x0200))
    (check "deux segments — r1 NOP NOP"
           (equalp (script-result-bytes r1) (bytes #xEA #xEA)))
    (check "deux segments — r2 adresse $0208"
           (= (script-result-address r2) #x0208))
    (check "deux segments — r2 RTS"
           (equalp (script-result-bytes r2) (bytes #x60)))))

;;; --------------------------------------------------------------------------
;;;  Référence croisée : JSR dans un segment vers label dans l'autre
;;; --------------------------------------------------------------------------

(deftest test-cross-segment-jsr
  ;; Segment "main" à $0200 appelle routine définie dans segment "lib" à $0210
  (let* ((s-main (seg "main" #x0200 "JSR routine
                                     RTS"))
         (s-lib  (seg "lib"  #x0210 "routine: LDA #$42
                                              RTS"))
         (results (link-segments (list s-main s-lib)))
         (r-main (first results))
         (r-lib  (second results)))
    ;; main : JSR $0210 = $20 $10 $02, RTS = $60
    (check "cross-segment JSR — main bytes"
           (equalp (script-result-bytes r-main)
                   (bytes #x20 #x10 #x02   ; JSR $0210
                          #x60)))           ; RTS
    ;; lib : LDA #$42 = $A9 $42, RTS = $60
    (check "cross-segment JSR — lib bytes"
           (equalp (script-result-bytes r-lib)
                   (bytes #xA9 #x42         ; LDA #$42
                          #x60)))))         ; RTS

;;; --------------------------------------------------------------------------
;;;  Référence croisée : branchement vers label dans un autre segment
;;; --------------------------------------------------------------------------

(deftest test-cross-segment-branch
  ;; Segment "loop" à $0300, segment "exit" à $0310
  ;; $0300 : loop: LDA $10      (A5 10, 2 bytes)
  ;; $0302 :       BEQ done     (D0 0C, 2 bytes — done=$0310, après-BEQ=$0304, offset=$0C)
  ;; $0304 :       JMP loop     (4C 00 03, 3 bytes)
  ;; $0310 : done: RTS          (60, 1 byte)
  (let* ((s-loop (seg "loop" #x0300 "loop: LDA $10
                                           BEQ done
                                           JMP loop"))
         (s-exit (seg "exit" #x0310 "done: RTS"))
         (results (link-segments (list s-loop s-exit)))
         (r-loop (first results))
         (r-exit (second results)))
    (check "cross-segment BEQ — loop bytes"
           (equalp (script-result-bytes r-loop)
                   (bytes #xA5 #x10         ; LDA $10
                          #xF0 #x0C         ; BEQ done (offset $0C)
                          #x4C #x00 #x03))) ; JMP loop
    (check "cross-segment BEQ — exit bytes"
           (equalp (script-result-bytes r-exit)
                   (bytes #x60)))))         ; RTS

;;; --------------------------------------------------------------------------
;;;  Référence croisée : constante .equ définie dans un segment, utilisée dans l'autre
;;; --------------------------------------------------------------------------

(deftest test-cross-segment-equ
  (let* ((s-defs (seg "defs" #x0400 ".equ MAGIC = $BE
                                      NOP"))
         (s-user (seg "user" #x0402 "LDA #MAGIC"))
         (results (link-segments (list s-defs s-user)))
         (r-defs (first results))
         (r-user (second results)))
    (check "cross-segment .equ — defs NOP"
           (equalp (script-result-bytes r-defs) (bytes #xEA)))
    (check "cross-segment .equ — user LDA #$BE"
           (equalp (script-result-bytes r-user) (bytes #xA9 #xBE)))))

;;; --------------------------------------------------------------------------
;;;  Segment avec plusieurs link-units
;;; --------------------------------------------------------------------------

(deftest test-multi-unit-segment
  ;; Un segment peut regrouper plusieurs link-units
  (let* ((u1 (unit "a" "LDA #$01"))
         (u2 (unit "b" "LDA #$02"))
         (s  (make-script-segment :name "combined" :at #x0100
                                  :units (list u1 u2)))
         (results (link-segments (list s)))
         (r (first results)))
    (check "multi-unit segment — bytes concaténés"
           (equalp (script-result-bytes r)
                   (bytes #xA9 #x01   ; LDA #$01
                          #xA9 #x02)))))  ; LDA #$02

;;; --------------------------------------------------------------------------
;;;  Trois segments
;;; --------------------------------------------------------------------------

(deftest test-three-segments
  (let* ((s1 (seg "a" #x0100 "LDA #$01"))
         (s2 (seg "b" #x0102 "LDA #$02"))
         (s3 (seg "c" #x0104 "RTS"))
         (results (link-segments (list s1 s2 s3))))
    (check "trois segments — nombre de résultats"
           (= (length results) 3))
    (check "trois segments — s1"
           (equalp (script-result-bytes (first results)) (bytes #xA9 #x01)))
    (check "trois segments — s2"
           (equalp (script-result-bytes (second results)) (bytes #xA9 #x02)))
    (check "trois segments — s3"
           (equalp (script-result-bytes (third results)) (bytes #x60)))))

;;; --------------------------------------------------------------------------
;;;  Backend 65C02
;;; --------------------------------------------------------------------------

(deftest test-65c02-segment
  (let* ((s (seg "rom" #x0000 "BRA skip
                               NOP
                               skip: RTS" :65c02))
         (results (link-segments (list s) :target :65c02))
         (r (first results)))
    ;; BRA +1 = $80 $01, NOP = $EA, RTS = $60
    (check "65c02 segment — BRA forward"
           (equalp (script-result-bytes r)
                   (bytes #x80 #x01 #xEA #x60)))))

;;; --------------------------------------------------------------------------
;;;  segments->flat-binary
;;; --------------------------------------------------------------------------

(deftest test-flat-binary-empty
  (multiple-value-bind (bytes base)
      (segments->flat-binary '())
    (check "flat-binary vide — bytes #()"
           (equalp bytes #()))
    (check "flat-binary vide — base 0"
           (= base 0))))

(deftest test-flat-binary-single
  (let* ((r (make-script-result :name "a" :address #x0200 :bytes (bytes #xA9 #xFF #x60))))
    (multiple-value-bind (b base)
        (segments->flat-binary (list r))
      (check "flat-binary single — base $0200"
             (= base #x0200))
      (check "flat-binary single — bytes identiques"
             (equalp b (bytes #xA9 #xFF #x60))))))

(deftest test-flat-binary-gap
  ;; Seg à $0200 : NOP NOP (2 bytes)
  ;; Seg à $0208 : RTS (1 byte)
  ;; Trou de 6 bytes à $0202-$0207 rempli avec #x00
  (let* ((s1 (seg "a" #x0200 "NOP
                              NOP"))
         (s2 (seg "b" #x0208 "RTS"))
         (results (link-segments (list s1 s2))))
    (multiple-value-bind (b base)
        (segments->flat-binary results)
      (check "flat-binary gap — base $0200"
             (= base #x0200))
      (check "flat-binary gap — taille 9"
             (= (length b) 9))
      (check "flat-binary gap — octets seg1"
             (and (= (aref b 0) #xEA)
                  (= (aref b 1) #xEA)))
      (check "flat-binary gap — remplissage $00"
             (loop for i from 2 to 7 always (= (aref b i) #x00)))
      (check "flat-binary gap — octet seg2"
             (= (aref b 8) #x60)))))

(deftest test-flat-binary-fill-byte
  ;; Même disposition, remplissage avec $FF
  (let* ((s1 (seg "a" #x0000 "NOP"))
         (s2 (seg "b" #x0003 "RTS"))
         (results (link-segments (list s1 s2))))
    (multiple-value-bind (b base)
        (segments->flat-binary results :fill #xFF)
      (check "flat-binary fill — base $0000"
             (= base 0))
      (check "flat-binary fill — size 4"
             (= (length b) 4))
      (check "flat-binary fill — b[0]=EA"
             (= (aref b 0) #xEA))
      (check "flat-binary fill — b[1]=FF"
             (= (aref b 1) #xFF))
      (check "flat-binary fill — b[2]=FF"
             (= (aref b 2) #xFF))
      (check "flat-binary fill — b[3]=60"
             (= (aref b 3) #x60)))))

(deftest test-flat-binary-adjacent
  ;; Segments adjacents : pas de trou
  (let* ((s1 (seg "a" #x0100 "LDA #$01"))
         (s2 (seg "b" #x0102 "LDA #$02"))
         (s3 (seg "c" #x0104 "RTS"))
         (results (link-segments (list s1 s2 s3))))
    (multiple-value-bind (b base)
        (segments->flat-binary results)
      (check "flat-binary adjacent — base $0100"
             (= base #x0100))
      (check "flat-binary adjacent — taille 5"
             (= (length b) 5))
      (check "flat-binary adjacent — contenu"
             (equalp b (bytes #xA9 #x01 #xA9 #x02 #x60))))))

(deftest test-flat-binary-cross-segment
  ;; Intégration : cross-segment JSR → flat binary complet
  (let* ((s-main (seg "main" #x0200 "JSR routine
                                     RTS"))
         (s-lib  (seg "lib"  #x0210 "routine: LDA #$42
                                              RTS"))
         (results (link-segments (list s-main s-lib))))
    (multiple-value-bind (b base)
        (segments->flat-binary results)
      ;; base=$0200, end=$0213, size=$13=19
      (check "flat-binary cross — base $0200"
             (= base #x0200))
      (check "flat-binary cross — taille 19"
             (= (length b) 19))
      (check "flat-binary cross — JSR $0210 correct"
             (and (= (aref b 0) #x20)
                  (= (aref b 1) #x10)
                  (= (aref b 2) #x02)))
      (check "flat-binary cross — routine à offset 16"
             (and (= (aref b 16) #xA9)
                  (= (aref b 17) #x42)
                  (= (aref b 18) #x60))))))

;;; --------------------------------------------------------------------------
;;;  Accesseurs
;;; --------------------------------------------------------------------------

(deftest test-script-segment-accessors
  (let ((s (make-script-segment :name "test" :at #xC000 :fill #xFF)))
    (check "script-segment name" (string= (script-segment-name s) "test"))
    (check "script-segment at"   (= (script-segment-at s) #xC000))
    (check "script-segment fill" (= (script-segment-fill s) #xFF))
    (check "script-segment units nil" (null (script-segment-units s)))))

(deftest test-script-result-accessors
  (let ((r (make-script-result :name "seg" :address #x8000 :bytes (bytes 1 2 3))))
    (check "script-result name"    (string= (script-result-name r) "seg"))
    (check "script-result address" (= (script-result-address r) #x8000))
    (check "script-result bytes"   (equalp (script-result-bytes r) (bytes 1 2 3)))))

;;; --------------------------------------------------------------------------
;;;  Gestion des erreurs
;;; --------------------------------------------------------------------------

(deftest test-error-empty-segments
  (check "liste vide → erreur"
         (handler-case
             (progn (link-segments '()) nil)
           (error () t))))

(deftest test-error-unknown-target
  (let* ((u (link-unit-from-program "t" (parse "NOP") :6502))
         (s (make-script-segment :name "t" :at 0 :units (list u))))
    (check "target inconnu → erreur"
           (handler-case
               (progn (link-segments (list s) :target :unknown-arch) nil)
             (error () t)))))

;;; --------------------------------------------------------------------------
;;;  Point d'entrée
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Suite : test-linker-script ===~%")
  (test-single-segment)
  (test-two-segments-independent)
  (test-cross-segment-jsr)
  (test-cross-segment-branch)
  (test-cross-segment-equ)
  (test-multi-unit-segment)
  (test-three-segments)
  (test-65c02-segment)
  (test-flat-binary-empty)
  (test-flat-binary-single)
  (test-flat-binary-gap)
  (test-flat-binary-fill-byte)
  (test-flat-binary-adjacent)
  (test-flat-binary-cross-segment)
  (test-script-segment-accessors)
  (test-script-result-accessors)
  (test-error-empty-segments)
  (test-error-unknown-target)
  (format t "~&--- Résultat : ~D OK, ~D KO sur ~D tests ---~%"
          *pass* *fail* (+ *pass* *fail*))
  (when *failures*
    (format t "Échecs :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (values *pass* *fail*))
