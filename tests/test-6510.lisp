; -*- coding: utf-8 -*-
;;; tests/test-6510.lisp
;;;
;;; Tests unitaires — backend MOS 6510 (Commodore 64).
;;;
;;; Vérifie :
;;;   1. Les instructions 6502 standard fonctionnent toujours (héritage)
;;;   2. Chaque opcode illégal stable est encodé correctement
;;;      LAX / SAX / SLO / RLA / SRE / RRA / DCP / ISC
;;;      ALR / ANC / ARR / AXS / LAS / KIL

(defpackage #:cl-asm/test.6510
  (:use #:cl)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.6510)


;;; --------------------------------------------------------------------------
;;;  Infrastructure de test
;;; --------------------------------------------------------------------------

(defvar *pass*     0)
(defvar *fail*     0)
(defvar *failures* '())

(defmacro check (description form)
  `(let ((result (handler-case ,form
                   (error (e)
                     (format t "~&  ERREUR inattendue [~A] : ~A~%" ,description e)
                     nil))))
     (if result
         (progn (incf *pass*) (format t "~&  OK  ~A~%" ,description))
         (progn (incf *fail*)
                (push ,description *failures*)
                (format t "~&  KO  ~A~%" ,description)))))

(defun asm6510 (src &key (origin 0))
  "Assemble SRC avec le backend 6510, retourne le vecteur d'octets."
  (cl-asm/backend.6510:assemble-string-6510 src :origin origin))

(defun bytes= (got &rest expected)
  "Vérifie que GOT = #(expected...)."
  (and (= (length got) (length expected))
       (every #'= got expected)))


;;; --------------------------------------------------------------------------
;;;  Héritage 6502
;;; --------------------------------------------------------------------------

(defun test/6510-6502-heritage ()
  (format t "~%--- héritage 6502 ---~%")
  (check "LDA #$42 → $A9 $42"
         (bytes= (asm6510 "LDA #$42") #xA9 #x42))
  (check "STA $10 → $85 $10"
         (bytes= (asm6510 "STA $10") #x85 #x10))
  (check "JMP $C000 → $4C $00 $C0"
         (bytes= (asm6510 "JMP $C000") #x4C #x00 #xC0))
  (check "JSR $E000 → $20 $00 $E0"
         (bytes= (asm6510 "JSR $E000") #x20 #x00 #xE0))
  (check "RTS → $60"
         (bytes= (asm6510 "RTS") #x60)))


;;; --------------------------------------------------------------------------
;;;  LAX — Load A and X
;;; --------------------------------------------------------------------------

(defun test/6510-lax ()
  (format t "~%--- LAX ---~%")
  (check "LAX $10 (zp) → $A7 $10"
         (bytes= (asm6510 "LAX $10") #xA7 #x10))
  (check "LAX $10,Y (zp,Y) → $B7 $10"
         (bytes= (asm6510 "LAX $10,Y") #xB7 #x10))
  (check "LAX $1234 (abs) → $AF $34 $12"
         (bytes= (asm6510 "LAX $1234") #xAF #x34 #x12))
  (check "LAX $1234,Y (abs,Y) → $BF $34 $12"
         (bytes= (asm6510 "LAX $1234,Y") #xBF #x34 #x12))
  (check "LAX ($10,X) (ind,X) → $A3 $10"
         (bytes= (asm6510 "LAX ($10,X)") #xA3 #x10))
  (check "LAX ($10),Y (ind,Y) → $B3 $10"
         (bytes= (asm6510 "LAX ($10),Y") #xB3 #x10)))


;;; --------------------------------------------------------------------------
;;;  SAX — Store A AND X
;;; --------------------------------------------------------------------------

(defun test/6510-sax ()
  (format t "~%--- SAX ---~%")
  (check "SAX $10 (zp) → $87 $10"
         (bytes= (asm6510 "SAX $10") #x87 #x10))
  (check "SAX $10,Y (zp,Y) → $97 $10"
         (bytes= (asm6510 "SAX $10,Y") #x97 #x10))
  (check "SAX $1234 (abs) → $8F $34 $12"
         (bytes= (asm6510 "SAX $1234") #x8F #x34 #x12))
  (check "SAX ($10,X) (ind,X) → $83 $10"
         (bytes= (asm6510 "SAX ($10,X)") #x83 #x10)))


;;; --------------------------------------------------------------------------
;;;  SLO — ASL + ORA
;;; --------------------------------------------------------------------------

(defun test/6510-slo ()
  (format t "~%--- SLO ---~%")
  (check "SLO $10 (zp) → $07 $10"
         (bytes= (asm6510 "SLO $10") #x07 #x10))
  (check "SLO $10,X (zp,X) → $17 $10"
         (bytes= (asm6510 "SLO $10,X") #x17 #x10))
  (check "SLO $1234 (abs) → $0F $34 $12"
         (bytes= (asm6510 "SLO $1234") #x0F #x34 #x12))
  (check "SLO $1234,X (abs,X) → $1F $34 $12"
         (bytes= (asm6510 "SLO $1234,X") #x1F #x34 #x12))
  (check "SLO $1234,Y (abs,Y) → $1B $34 $12"
         (bytes= (asm6510 "SLO $1234,Y") #x1B #x34 #x12))
  (check "SLO ($10,X) → $03 $10"
         (bytes= (asm6510 "SLO ($10,X)") #x03 #x10))
  (check "SLO ($10),Y → $13 $10"
         (bytes= (asm6510 "SLO ($10),Y") #x13 #x10)))


;;; --------------------------------------------------------------------------
;;;  RLA — ROL + AND
;;; --------------------------------------------------------------------------

(defun test/6510-rla ()
  (format t "~%--- RLA ---~%")
  (check "RLA $10 (zp) → $27 $10"
         (bytes= (asm6510 "RLA $10") #x27 #x10))
  (check "RLA $10,X (zp,X) → $37 $10"
         (bytes= (asm6510 "RLA $10,X") #x37 #x10))
  (check "RLA $1234 (abs) → $2F $34 $12"
         (bytes= (asm6510 "RLA $1234") #x2F #x34 #x12))
  (check "RLA $1234,X (abs,X) → $3F $34 $12"
         (bytes= (asm6510 "RLA $1234,X") #x3F #x34 #x12))
  (check "RLA $1234,Y (abs,Y) → $3B $34 $12"
         (bytes= (asm6510 "RLA $1234,Y") #x3B #x34 #x12))
  (check "RLA ($10,X) → $23 $10"
         (bytes= (asm6510 "RLA ($10,X)") #x23 #x10))
  (check "RLA ($10),Y → $33 $10"
         (bytes= (asm6510 "RLA ($10),Y") #x33 #x10)))


;;; --------------------------------------------------------------------------
;;;  SRE — LSR + EOR
;;; --------------------------------------------------------------------------

(defun test/6510-sre ()
  (format t "~%--- SRE ---~%")
  (check "SRE $10 (zp) → $47 $10"
         (bytes= (asm6510 "SRE $10") #x47 #x10))
  (check "SRE $10,X → $57 $10"
         (bytes= (asm6510 "SRE $10,X") #x57 #x10))
  (check "SRE $1234 → $4F $34 $12"
         (bytes= (asm6510 "SRE $1234") #x4F #x34 #x12))
  (check "SRE $1234,X → $5F $34 $12"
         (bytes= (asm6510 "SRE $1234,X") #x5F #x34 #x12))
  (check "SRE $1234,Y → $5B $34 $12"
         (bytes= (asm6510 "SRE $1234,Y") #x5B #x34 #x12))
  (check "SRE ($10,X) → $43 $10"
         (bytes= (asm6510 "SRE ($10,X)") #x43 #x10))
  (check "SRE ($10),Y → $53 $10"
         (bytes= (asm6510 "SRE ($10),Y") #x53 #x10)))


;;; --------------------------------------------------------------------------
;;;  RRA — ROR + ADC
;;; --------------------------------------------------------------------------

(defun test/6510-rra ()
  (format t "~%--- RRA ---~%")
  (check "RRA $10 (zp) → $67 $10"
         (bytes= (asm6510 "RRA $10") #x67 #x10))
  (check "RRA $10,X → $77 $10"
         (bytes= (asm6510 "RRA $10,X") #x77 #x10))
  (check "RRA $1234 → $6F $34 $12"
         (bytes= (asm6510 "RRA $1234") #x6F #x34 #x12))
  (check "RRA $1234,X → $7F $34 $12"
         (bytes= (asm6510 "RRA $1234,X") #x7F #x34 #x12))
  (check "RRA $1234,Y → $7B $34 $12"
         (bytes= (asm6510 "RRA $1234,Y") #x7B #x34 #x12))
  (check "RRA ($10,X) → $63 $10"
         (bytes= (asm6510 "RRA ($10,X)") #x63 #x10))
  (check "RRA ($10),Y → $73 $10"
         (bytes= (asm6510 "RRA ($10),Y") #x73 #x10)))


;;; --------------------------------------------------------------------------
;;;  DCP — DEC + CMP
;;; --------------------------------------------------------------------------

(defun test/6510-dcp ()
  (format t "~%--- DCP ---~%")
  (check "DCP $10 (zp) → $C7 $10"
         (bytes= (asm6510 "DCP $10") #xC7 #x10))
  (check "DCP $10,X → $D7 $10"
         (bytes= (asm6510 "DCP $10,X") #xD7 #x10))
  (check "DCP $1234 → $CF $34 $12"
         (bytes= (asm6510 "DCP $1234") #xCF #x34 #x12))
  (check "DCP $1234,X → $DF $34 $12"
         (bytes= (asm6510 "DCP $1234,X") #xDF #x34 #x12))
  (check "DCP $1234,Y → $DB $34 $12"
         (bytes= (asm6510 "DCP $1234,Y") #xDB #x34 #x12))
  (check "DCP ($10,X) → $C3 $10"
         (bytes= (asm6510 "DCP ($10,X)") #xC3 #x10))
  (check "DCP ($10),Y → $D3 $10"
         (bytes= (asm6510 "DCP ($10),Y") #xD3 #x10)))


;;; --------------------------------------------------------------------------
;;;  ISC — INC + SBC
;;; --------------------------------------------------------------------------

(defun test/6510-isc ()
  (format t "~%--- ISC ---~%")
  (check "ISC $10 (zp) → $E7 $10"
         (bytes= (asm6510 "ISC $10") #xE7 #x10))
  (check "ISC $10,X → $F7 $10"
         (bytes= (asm6510 "ISC $10,X") #xF7 #x10))
  (check "ISC $1234 → $EF $34 $12"
         (bytes= (asm6510 "ISC $1234") #xEF #x34 #x12))
  (check "ISC $1234,X → $FF $34 $12"
         (bytes= (asm6510 "ISC $1234,X") #xFF #x34 #x12))
  (check "ISC $1234,Y → $FB $34 $12"
         (bytes= (asm6510 "ISC $1234,Y") #xFB #x34 #x12))
  (check "ISC ($10,X) → $E3 $10"
         (bytes= (asm6510 "ISC ($10,X)") #xE3 #x10))
  (check "ISC ($10),Y → $F3 $10"
         (bytes= (asm6510 "ISC ($10),Y") #xF3 #x10)))


;;; --------------------------------------------------------------------------
;;;  Opcodes mode immédiat et divers
;;; --------------------------------------------------------------------------

(defun test/6510-immediat-et-divers ()
  (format t "~%--- ALR / ANC / ARR / AXS / LAS / KIL ---~%")
  (check "ALR #$FF → $4B $FF"
         (bytes= (asm6510 "ALR #$FF") #x4B #xFF))
  (check "ANC #$0F → $0B $0F"
         (bytes= (asm6510 "ANC #$0F") #x0B #x0F))
  (check "ARR #$AA → $6B $AA"
         (bytes= (asm6510 "ARR #$AA") #x6B #xAA))
  (check "AXS #$01 → $CB $01"
         (bytes= (asm6510 "AXS #$01") #xCB #x01))
  (check "LAS $1234,Y → $BB $34 $12"
         (bytes= (asm6510 "LAS $1234,Y") #xBB #x34 #x12))
  (check "KIL → $02"
         (bytes= (asm6510 "KIL") #x02)))


;;; --------------------------------------------------------------------------
;;;  Programme mixte (6502 + illégaux)
;;; --------------------------------------------------------------------------

(defun test/6510-programme-mixte ()
  (format t "~%--- programme mixte ---~%")
  ;; Séquence typique C64 : LAX pour charger A et X en un coup, puis STA/STX
  (let ((bytes (asm6510 "LAX $FC
  SAX $FD
  RTS")))
    (check "programme mixte : LAX $FC → $A7 $FC"
           (and (= (aref bytes 0) #xA7)
                (= (aref bytes 1) #xFC)))
    (check "programme mixte : SAX $FD → $87 $FD"
           (and (= (aref bytes 2) #x87)
                (= (aref bytes 3) #xFD)))
    (check "programme mixte : RTS → $60"
           (= (aref bytes 4) #x60))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~%=== MOS 6510 (Commodore 64) ===~%")
  (test/6510-6502-heritage)
  (test/6510-lax)
  (test/6510-sax)
  (test/6510-slo)
  (test/6510-rla)
  (test/6510-sre)
  (test/6510-rra)
  (test/6510-dcp)
  (test/6510-isc)
  (test/6510-immediat-et-divers)
  (test/6510-programme-mixte)
  (format t "~%=== 6510 : ~3D OK, ~D KO~%" *pass* *fail*)
  (when *failures*
    (format t "  Échecs :~%")
    (dolist (f (reverse *failures*))
      (format t "    - ~A~%" f))))
