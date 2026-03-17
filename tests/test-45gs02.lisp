; -*- coding: utf-8 -*-
;;; tests/test-45gs02.lisp

(defpackage #:cl-asm/test.45gs02
  (:use #:cl #:cl-asm/backend.45gs02)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.45gs02)


;;; --------------------------------------------------------------------------
;;;  Infra de test
;;; --------------------------------------------------------------------------

(defvar *pass* 0)
(defvar *fail* 0)
(defvar *failures* '())

(defmacro check (description form)
  `(let ((result (handler-case ,form
                   (error (e)
                     (format t "~&  ERREUR inattendue dans [~A] : ~A~%"
                             ,description e)
                     nil))))
     (if result
         (progn (incf *pass*) (format t "~&  OK  ~A~%" ,description))
         (progn (incf *fail*)
                (push ,description *failures*)
                (format t "~&  KO  ~A~%" ,description)))))

(defmacro check-error (description condition-type form)
  `(let ((fired nil))
     (handler-case ,form
       (,condition-type () (setf fired t))
       (error (e)
         (format t "~&  ERREUR inattendue dans [~A] : ~A~%" ,description e)))
     (if fired
         (progn (incf *pass*)
                (format t "~&  OK  ~A (erreur attendue)~%" ,description))
         (progn (incf *fail*)
                (push ,description *failures*)
                (format t "~&  KO  ~A (erreur NON declenchee)~%" ,description)))))

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&~%[~A]~%" ',name)
     ,@body))


;;; --------------------------------------------------------------------------
;;;  Helpers
;;; --------------------------------------------------------------------------

(defun asm (source &key (origin #x2001))
  "Assemble SOURCE pour le 45GS02."
  (assemble-string-45gs02 source :origin origin))

(defun bytes= (vec &rest expected)
  (and (= (length vec) (length expected))
       (every #'= vec expected)))

(defun starts-with (vec &rest expected)
  (and (>= (length vec) (length expected))
       (every #'= vec expected)))


;;; --------------------------------------------------------------------------
;;;  Tests : compatibilite 6502
;;; --------------------------------------------------------------------------

(deftest test/6502-compat-nop
  ;; Les instructions 6502 doivent fonctionner identiquement
  (check "NOP = $EA"     (bytes= (asm "NOP") #xEA))
  (check "RTS = $60"     (bytes= (asm "RTS") #x60))
  (check "CLC = $18"     (bytes= (asm "CLC") #x18))
  (check "SEI = $78"     (bytes= (asm "SEI") #x78)))

(deftest test/6502-compat-lda
  (check "LDA #$FF = A9 FF"
         (bytes= (asm "LDA #$FF") #xA9 #xFF))
  (check "LDA $10 = A5 10"
         (bytes= (asm "LDA $10")  #xA5 #x10))
  (check "LDA $1234 = AD 34 12"
         (bytes= (asm "LDA $1234") #xAD #x34 #x12))
  (check "STA $D020 = 8D 20 D0"
         (bytes= (asm "STA $D020") #x8D #x20 #xD0)))


;;; --------------------------------------------------------------------------
;;;  Tests : registre Z
;;; --------------------------------------------------------------------------

(deftest test/register-z-load-store
  (check "LDZ #$00 = A3 00"
         (bytes= (asm "LDZ #$00") #xA3 #x00))
  (check "LDZ #$FF = A3 FF"
         (bytes= (asm "LDZ #$FF") #xA3 #xFF))
  (check "LDZ $1234 = AB 34 12"
         (bytes= (asm "LDZ $1234") #xAB #x34 #x12))
  (check "LDZ $1234,X = BB 34 12"
         (bytes= (asm "LDZ $1234,X") #xBB #x34 #x12)))

(deftest test/register-z-inc-dec
  (check "INZ = $1B"   (bytes= (asm "INZ") #x1B))
  (check "DEZ = $3B"   (bytes= (asm "DEZ") #x3B)))

(deftest test/register-z-stack
  (check "PHZ = $DB"   (bytes= (asm "PHZ") #xDB))
  (check "PLZ = $FB"   (bytes= (asm "PLZ") #xFB)))

(deftest test/register-z-transfer
  (check "TAZ = $4B"   (bytes= (asm "TAZ") #x4B))
  (check "TZA = $6B"   (bytes= (asm "TZA") #x6B)))


;;; --------------------------------------------------------------------------
;;;  Tests : registre B
;;; --------------------------------------------------------------------------

(deftest test/register-b-transfer
  (check "TAB = $5B"   (bytes= (asm "TAB") #x5B))
  (check "TBA = $CB"   (bytes= (asm "TBA") #xCB)))


;;; --------------------------------------------------------------------------
;;;  Tests : mode indirect-z  ($nn),Z
;;; --------------------------------------------------------------------------

(deftest test/indirect-z
  ;; LDA ($nn),Z  -- meme opcode que LDA ($nn),Y mais avec Z
  (check "LDA ($B0),Z = B1 B0"
         (bytes= (asm "LDA ($B0),Z") #xB1 #xB0))
  (check "STA ($00),Z = 91 00"
         (bytes= (asm "STA ($00),Z") #x91 #x00))
  (check "ADC ($10),Z = 71 10"
         (bytes= (asm "ADC ($10),Z") #x71 #x10)))


;;; --------------------------------------------------------------------------
;;;  Tests : mode absolu-z  $nnnn,Z
;;; --------------------------------------------------------------------------

(deftest test/absolute-z
  ;; LDA $nnnn,Z  -- meme opcode que LDA $nnnn,Y
  (check "LDA $1234,Z = B9 34 12"
         (bytes= (asm "LDA $1234,Z") #xB9 #x34 #x12))
  (check "STA $D000,Z = 99 00 D0"
         (bytes= (asm "STA $D000,Z") #x99 #x00 #xD0)))


;;; --------------------------------------------------------------------------
;;;  Tests : mode indirect 32 bits  [$nn] et [$nn],Z
;;; --------------------------------------------------------------------------

(deftest test/indirect-32
  ;; [$nn] -- prefixe $EA + opcode indirect-y
  (let ((bytes (asm "LDA [$20]")))
    (check "LDA [$20] : 3 octets"   (= 3 (length bytes)))
    (check "LDA [$20] : prefixe EA" (= #xEA (aref bytes 0)))
    (check "LDA [$20] : opcode B1"  (= #xB1 (aref bytes 1)))
    (check "LDA [$20] : addr $20"   (= #x20  (aref bytes 2)))))

(deftest test/indirect-32-z
  (let ((bytes (asm "LDA [$20],Z")))
    (check "LDA [$20],Z : 3 octets"   (= 3 (length bytes)))
    (check "LDA [$20],Z : prefixe EA" (= #xEA (aref bytes 0)))
    (check "LDA [$20],Z : opcode B1"  (= #xB1 (aref bytes 1)))
    (check "LDA [$20],Z : addr $20"   (= #x20  (aref bytes 2)))))


;;; --------------------------------------------------------------------------
;;;  Tests : instructions Q (32 bits, prefixe $42 $42)
;;; --------------------------------------------------------------------------

(deftest test/ldq-stq
  ;; LDQ ($nn),Z  = $42 $42 $B2 $nn
  (let ((bytes (asm "LDQ ($20),Z")))
    (check "LDQ : 4 octets"        (= 4 (length bytes)))
    (check "LDQ : prefixe $42"     (= #x42 (aref bytes 0)))
    (check "LDQ : prefixe $42"     (= #x42 (aref bytes 1)))
    (check "LDQ : opcode $B2"      (= #xB2 (aref bytes 2)))
    (check "LDQ : addr $20"        (= #x20  (aref bytes 3))))
  ;; STQ ($nn),Z  = $42 $42 $92 $nn
  (let ((bytes (asm "STQ ($20),Z")))
    (check "STQ : prefixe $42 $42" (and (= #x42 (aref bytes 0))
                                        (= #x42 (aref bytes 1))))
    (check "STQ : opcode $92"      (= #x92 (aref bytes 2)))))

(deftest test/ldq-zp
  ;; LDQ $nn (zero-page) = $42 $42 $A5 $nn
  (let ((bytes (asm "LDQ $10")))
    (check "LDQ zp : 4 octets"     (= 4 (length bytes)))
    (check "LDQ zp : prefix 42 42" (and (= #x42 (aref bytes 0))
                                         (= #x42 (aref bytes 1))))
    (check "LDQ zp : opcode A5"    (= #xA5 (aref bytes 2)))
    (check "LDQ zp : addr $10"     (= #x10  (aref bytes 3)))))

(deftest test/q-alu
  ;; ADCQ ($nn),Z = $42 $42 $72 $nn
  (let ((bytes (asm "ADCQ ($00),Z")))
    (check "ADCQ prefix"           (and (= #x42 (aref bytes 0))
                                        (= #x42 (aref bytes 1))))
    (check "ADCQ opcode $72"       (= #x72 (aref bytes 2))))
  ;; ANDQ ($nn),Z = $42 $42 $32 $nn
  (let ((bytes (asm "ANDQ ($00),Z")))
    (check "ANDQ opcode $32"       (= #x32 (aref bytes 2))))
  ;; EORQ ($nn),Z = $42 $42 $52 $nn
  (let ((bytes (asm "EORQ ($00),Z")))
    (check "EORQ opcode $52"       (= #x52 (aref bytes 2)))))

(deftest test/q-shifts
  ;; ASLQ A = $42 $42 $0A
  (let ((bytes (asm "ASLQ A")))
    (check "ASLQ A : 3 octets"    (= 3 (length bytes)))
    (check "ASLQ A : 42 42 0A"    (and (= #x42 (aref bytes 0))
                                        (= #x42 (aref bytes 1))
                                        (= #x0A (aref bytes 2)))))
  ;; LSRQ A = $42 $42 $4A
  (let ((bytes (asm "LSRQ A")))
    (check "LSRQ A : 42 42 4A"    (and (= #x42 (aref bytes 0))
                                        (= #x42 (aref bytes 1))
                                        (= #x4A (aref bytes 2)))))
  ;; ROLQ A = $42 $42 $2A
  (let ((bytes (asm "ROLQ A")))
    (check "ROLQ A : 42 42 2A"    (= #x2A (aref bytes 2))))
  ;; RORQ A = $42 $42 $6A
  (let ((bytes (asm "RORQ A")))
    (check "RORQ A : 42 42 6A"    (= #x6A (aref bytes 2)))))


;;; --------------------------------------------------------------------------
;;;  Tests : instructions speciales
;;; --------------------------------------------------------------------------

(deftest test/neg-asr
  (check "NEG A = $42"    (bytes= (asm "NEG A") #x42))
  (check "ASR A = $43"    (bytes= (asm "ASR A") #x43))
  (check "ASR $10 = 44 10" (bytes= (asm "ASR $10") #x44 #x10)))

(deftest test/map-eom
  (check "MAP = $5C"      (bytes= (asm "MAP") #x5C))
  (check "EOM = $EA"      (bytes= (asm "EOM") #xEA)))

(deftest test/inw-dew
  (check "INW $10 = E3 10" (bytes= (asm "INW $10") #xE3 #x10))
  (check "DEW $20 = C3 20" (bytes= (asm "DEW $20") #xC3 #x20)))

(deftest test/tsy-tys
  (check "TSY = $0B"      (bytes= (asm "TSY") #x0B))
  (check "TYS = $2B"      (bytes= (asm "TYS") #x2B)))


;;; --------------------------------------------------------------------------
;;;  Tests : branchements longs 16 bits (prefixe $42)
;;; --------------------------------------------------------------------------

(deftest test/long-branches
  ;; LBNE forward (3 NOP + cible)
  (let ((bytes (asm (format nil "LBNE end~%NOP~%NOP~%NOP~%end:"))))
    ;; LBNE = $42 $D0 <lo> <hi>
    (check "LBNE : prefixe $42"   (= #x42 (aref bytes 0)))
    (check "LBNE : opcode $D0"    (= #xD0 (aref bytes 1)))
    ;; offset depuis PC+4 vers end (3 NOP = 3 octets apres LBNE)
    ;; PC apres LBNE = origin+4, end = origin+4+3 = origin+7, offset=3
    (check "LBNE : offset lo = 3" (= 3 (aref bytes 2)))
    (check "LBNE : offset hi = 0" (= 0 (aref bytes 3))))
  (check "LBEQ = prefixe $42 + $F0"
         (= #xF0 (aref (asm (format nil "LBEQ end~%end:")) 1)))
  (check "LBCC = prefixe $42 + $90"
         (= #x90 (aref (asm (format nil "LBCC end~%end:")) 1))))

(deftest test/long-branch-out-of-range
  (check-error "LBNE hors portee -> asm-range-error"
               cl-asm/ir:asm-range-error
               (let ((src (with-output-to-string (s)
                            (format s "start:~%")
                            (dotimes (i 40000) (format s "NOP~%"))
                            (format s "LBNE start~%"))))
                 (asm src))))


;;; --------------------------------------------------------------------------
;;;  Tests : programme Mega65 complet
;;; --------------------------------------------------------------------------

(deftest test/mega65-hello
  ;; Programme Mega65 minimal : charge Z, fait quelques operations
  (let* ((src (format nil
                      "~A~%~A~%~A~%~A~%~A~%~A~%~A"
                      ".org $2001"
                      "start:"
                      "LDZ #$00"
                      "LDA #$01"
                      "TAZ"
                      "INZ"
                      "RTS"))
         (bytes (asm src :origin #x2001)))
    (check "au moins 7 octets"    (>= (length bytes) 7))
    (check "LDZ #$00 = A3 00"
           (and (= #xA3 (aref bytes 0)) (= #x00 (aref bytes 1))))
    (check "LDA #$01 = A9 01"
           (and (= #xA9 (aref bytes 2)) (= #x01 (aref bytes 3))))
    (check "TAZ = $4B"            (= #x4B (aref bytes 4)))
    (check "INZ = $1B"            (= #x1B (aref bytes 5)))
    (check "RTS = $60"            (= #x60 (aref bytes 6)))))


;;; --------------------------------------------------------------------------
;;;  Tests : labels et forward-refs (meme mecanique que 6502)
;;; --------------------------------------------------------------------------

(deftest test/forward-ref-45
  (let ((bytes (asm (format nil "JMP end~%NOP~%end: RTS"))))
    (check "JMP forward = 4C"     (= #x4C (aref bytes 0)))
    (check "JMP target hi = $20"  (= #x20 (aref bytes 2)))
    (check "NOP"                  (= #xEA (aref bytes 3)))
    (check "RTS"                  (= #x60 (aref bytes 4)))))


;;; --------------------------------------------------------------------------
;;;  Tests : erreurs
;;; --------------------------------------------------------------------------

(deftest test/unknown-mnemonic-45
  (check-error "mnemonique inconnu -> asm-unknown-mnemonic"
               cl-asm/ir:asm-unknown-mnemonic
               (asm "FOOBAR #$00")))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests cl-asm/backend.45gs02 ===~%")
  (test/6502-compat-nop)
  (test/6502-compat-lda)
  (test/register-z-load-store)
  (test/register-z-inc-dec)
  (test/register-z-stack)
  (test/register-z-transfer)
  (test/register-b-transfer)
  (test/indirect-z)
  (test/absolute-z)
  (test/indirect-32)
  (test/indirect-32-z)
  (test/ldq-stq)
  (test/ldq-zp)
  (test/q-alu)
  (test/q-shifts)
  (test/neg-asr)
  (test/map-eom)
  (test/inw-dew)
  (test/tsy-tys)
  (test/long-branches)
  (test/long-branch-out-of-range)
  (test/mega65-hello)
  (test/forward-ref-45)
  (test/unknown-mnemonic-45)
  (when *failures*
    (format t "~&Echecs 45GS02 :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
