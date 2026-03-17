; -*- coding: utf-8 -*-
;;; tests/test-r65c02.lisp
;;;
;;; Tests du backend Rockwell R65C02.
;;; Couvre :
;;;   - Héritage du backend 65C02 (instructions standard)
;;;   - RMB0..RMB7 (Reset Memory Bit)
;;;   - SMB0..SMB7 (Set Memory Bit)
;;;   - BBR0..BBR7 (Branch on Bit Reset)
;;;   - BBS0..BBS7 (Branch on Bit Set)
;;;   - Opcode mapping complet
;;;   - Calcul d'offset relatif BBRn/BBSn
;;;   - Forward references avec BBRn/BBSn

(defpackage #:cl-asm/test.r65c02
  (:use #:cl)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.r65c02)

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

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&~%[~A]~%" ',name)
     ,@body))

(defun asm (source &key (origin #x0801))
  (cl-asm/backend.r65c02:assemble-string-r65c02 source :origin origin))

(defun bytes= (vec &rest expected)
  (and (= (length vec) (length expected))
       (every #'= vec expected)))


;;; --------------------------------------------------------------------------
;;;  Tests : helpers Rockwell dans le parser
;;; --------------------------------------------------------------------------

(deftest test/rockwell-helpers
  (check "RMB0 reconnu" (cl-asm/parser:rockwell-mnemonic-p "RMB0"))
  (check "RMB7 reconnu" (cl-asm/parser:rockwell-mnemonic-p "RMB7"))
  (check "SMB0 reconnu" (cl-asm/parser:rockwell-mnemonic-p "SMB0"))
  (check "SMB7 reconnu" (cl-asm/parser:rockwell-mnemonic-p "SMB7"))
  (check "BBR0 reconnu" (cl-asm/parser:rockwell-mnemonic-p "BBR0"))
  (check "BBR7 reconnu" (cl-asm/parser:rockwell-mnemonic-p "BBR7"))
  (check "BBS0 reconnu" (cl-asm/parser:rockwell-mnemonic-p "BBS0"))
  (check "BBS7 reconnu" (cl-asm/parser:rockwell-mnemonic-p "BBS7"))
  ;; Négatifs
  (check "NOP non Rockwell"  (not (cl-asm/parser:rockwell-mnemonic-p "NOP")))
  (check "LDA non Rockwell"  (not (cl-asm/parser:rockwell-mnemonic-p "LDA")))
  (check "RMB8 invalide"     (not (cl-asm/parser:rockwell-mnemonic-p "RMB8")))
  (check "RMBA invalide"     (not (cl-asm/parser:rockwell-mnemonic-p "RMBA")))
  (check "RMB trop court"    (not (cl-asm/parser:rockwell-mnemonic-p "RMB")))
  ;; Numéros de bit
  (check "bit-number RMB0 = 0" (= 0 (cl-asm/parser:rockwell-bit-number "RMB0")))
  (check "bit-number RMB7 = 7" (= 7 (cl-asm/parser:rockwell-bit-number "RMB7")))
  (check "bit-number BBR3 = 3" (= 3 (cl-asm/parser:rockwell-bit-number "BBR3")))
  ;; Opcodes
  (check "opcode RMB0 = $07" (= #x07 (cl-asm/parser:rockwell-opcode "RMB0")))
  (check "opcode RMB1 = $17" (= #x17 (cl-asm/parser:rockwell-opcode "RMB1")))
  (check "opcode RMB7 = $77" (= #x77 (cl-asm/parser:rockwell-opcode "RMB7")))
  (check "opcode SMB0 = $87" (= #x87 (cl-asm/parser:rockwell-opcode "SMB0")))
  (check "opcode SMB7 = $F7" (= #xF7 (cl-asm/parser:rockwell-opcode "SMB7")))
  (check "opcode BBR0 = $0F" (= #x0F (cl-asm/parser:rockwell-opcode "BBR0")))
  (check "opcode BBR7 = $7F" (= #x7F (cl-asm/parser:rockwell-opcode "BBR7")))
  (check "opcode BBS0 = $8F" (= #x8F (cl-asm/parser:rockwell-opcode "BBS0")))
  (check "opcode BBS7 = $FF" (= #xFF (cl-asm/parser:rockwell-opcode "BBS7")))
  ;; two-operands-p
  (check "BBR prend 2 opérandes" (cl-asm/parser:rockwell-two-operands-p "BBR0"))
  (check "BBS prend 2 opérandes" (cl-asm/parser:rockwell-two-operands-p "BBS5"))
  (check "RMB prend 1 opérande"  (not (cl-asm/parser:rockwell-two-operands-p "RMB3")))
  (check "SMB prend 1 opérande"  (not (cl-asm/parser:rockwell-two-operands-p "SMB7"))))


;;; --------------------------------------------------------------------------
;;;  Tests : héritage 65C02
;;; --------------------------------------------------------------------------

(deftest test/65c02-compat
  (check "NOP = $EA"          (bytes= (asm "NOP") #xEA))
  (check "RTS = $60"          (bytes= (asm "RTS") #x60))
  (check "LDA #$FF = A9 FF"   (bytes= (asm "LDA #$FF") #xA9 #xFF))
  (check "LDA $10 = A5 10"    (bytes= (asm "LDA $10")  #xA5 #x10))
  (check "LDA $1234 = AD 34 12" (bytes= (asm "LDA $1234") #xAD #x34 #x12))
  (check "STZ $20 = 64 20"    (bytes= (asm "STZ $20")  #x64 #x20))
  (check "STZ $1234 = 9C 34 12" (bytes= (asm "STZ $1234") #x9C #x34 #x12))
  (check "BRA (forward+2) = 80 00"
         (bytes= (asm ".org $1000
                        BRA target
                        target:")
                 #x80 #x00)))


;;; --------------------------------------------------------------------------
;;;  Tests : RMBn — Reset Memory Bit
;;; --------------------------------------------------------------------------

(deftest test/rmb-opcodes
  ;; RMBn $zp : opcode = n*$10 + $07
  (check "RMB0 $10 = 07 10" (bytes= (asm "RMB0 $10") #x07 #x10))
  (check "RMB1 $10 = 17 10" (bytes= (asm "RMB1 $10") #x17 #x10))
  (check "RMB2 $10 = 27 10" (bytes= (asm "RMB2 $10") #x27 #x10))
  (check "RMB3 $10 = 37 10" (bytes= (asm "RMB3 $10") #x37 #x10))
  (check "RMB4 $10 = 47 10" (bytes= (asm "RMB4 $10") #x47 #x10))
  (check "RMB5 $10 = 57 10" (bytes= (asm "RMB5 $10") #x57 #x10))
  (check "RMB6 $10 = 67 10" (bytes= (asm "RMB6 $10") #x67 #x10))
  (check "RMB7 $10 = 77 10" (bytes= (asm "RMB7 $10") #x77 #x10))
  ;; Adresses zero-page variées
  (check "RMB0 $00 = 07 00" (bytes= (asm "RMB0 $00") #x07 #x00))
  (check "RMB7 $FF = 77 FF" (bytes= (asm "RMB7 $FF") #x77 #xFF))
  (check "RMB3 $42 = 37 42" (bytes= (asm "RMB3 $42") #x37 #x42))
  ;; Taille = 2 octets
  (check "RMB0 taille = 2"  (= 2 (length (asm "RMB0 $10")))))


;;; --------------------------------------------------------------------------
;;;  Tests : SMBn — Set Memory Bit
;;; --------------------------------------------------------------------------

(deftest test/smb-opcodes
  ;; SMBn $zp : opcode = n*$10 + $87
  (check "SMB0 $20 = 87 20" (bytes= (asm "SMB0 $20") #x87 #x20))
  (check "SMB1 $20 = 97 20" (bytes= (asm "SMB1 $20") #x97 #x20))
  (check "SMB2 $20 = A7 20" (bytes= (asm "SMB2 $20") #xA7 #x20))
  (check "SMB3 $20 = B7 20" (bytes= (asm "SMB3 $20") #xB7 #x20))
  (check "SMB4 $20 = C7 20" (bytes= (asm "SMB4 $20") #xC7 #x20))
  (check "SMB5 $20 = D7 20" (bytes= (asm "SMB5 $20") #xD7 #x20))
  (check "SMB6 $20 = E7 20" (bytes= (asm "SMB6 $20") #xE7 #x20))
  (check "SMB7 $20 = F7 20" (bytes= (asm "SMB7 $20") #xF7 #x20))
  ;; Adresses zero-page variées
  (check "SMB0 $00 = 87 00" (bytes= (asm "SMB0 $00") #x87 #x00))
  (check "SMB7 $FF = F7 FF" (bytes= (asm "SMB7 $FF") #xF7 #xFF))
  (check "SMB4 $55 = C7 55" (bytes= (asm "SMB4 $55") #xC7 #x55))
  ;; Taille = 2 octets
  (check "SMB0 taille = 2"  (= 2 (length (asm "SMB0 $20")))))


;;; --------------------------------------------------------------------------
;;;  Tests : BBRn — Branch on Bit Reset
;;; --------------------------------------------------------------------------

(deftest test/bbr-opcodes
  ;; BBRn $zp, target : opcode = n*$10 + $0F
  ;; Offset = target - (pc+3), ici pc=$0801, instr=3 octets, target=$0804
  ;; offset = $0804 - $0804 = 0
  (check "BBR0 offset=0 → 0F zp 00"
         (bytes= (asm ".org $0801
                        BBR0 $10, target
                        target:")
                 #x0F #x10 #x00))
  (check "BBR1 opcode = $1F"
         (= #x1F (aref (asm ".org $0801
                              BBR1 $10, target
                              target:") 0)))
  (check "BBR2 opcode = $2F"
         (= #x2F (aref (asm ".org $0801
                              BBR2 $10, target
                              target:") 0)))
  (check "BBR3 opcode = $3F"
         (= #x3F (aref (asm ".org $0801
                              BBR3 $10, target
                              target:") 0)))
  (check "BBR4 opcode = $4F"
         (= #x4F (aref (asm ".org $0801
                              BBR4 $10, target
                              target:") 0)))
  (check "BBR5 opcode = $5F"
         (= #x5F (aref (asm ".org $0801
                              BBR5 $10, target
                              target:") 0)))
  (check "BBR6 opcode = $6F"
         (= #x6F (aref (asm ".org $0801
                              BBR6 $10, target
                              target:") 0)))
  (check "BBR7 opcode = $7F"
         (= #x7F (aref (asm ".org $0801
                              BBR7 $10, target
                              target:") 0)))
  ;; Taille = 3 octets
  (check "BBR0 taille = 3"
         (= 3 (length (asm ".org $0801
                             BBR0 $10, target
                             target:")))))


;;; --------------------------------------------------------------------------
;;;  Tests : BBSn — Branch on Bit Set
;;; --------------------------------------------------------------------------

(deftest test/bbs-opcodes
  ;; BBSn $zp, target : opcode = n*$10 + $8F
  (check "BBS0 offset=0 → 8F zp 00"
         (bytes= (asm ".org $0801
                        BBS0 $20, target
                        target:")
                 #x8F #x20 #x00))
  (check "BBS1 opcode = $9F"
         (= #x9F (aref (asm ".org $0801
                              BBS1 $20, target
                              target:") 0)))
  (check "BBS2 opcode = $AF"
         (= #xAF (aref (asm ".org $0801
                              BBS2 $20, target
                              target:") 0)))
  (check "BBS3 opcode = $BF"
         (= #xBF (aref (asm ".org $0801
                              BBS3 $20, target
                              target:") 0)))
  (check "BBS4 opcode = $CF"
         (= #xCF (aref (asm ".org $0801
                              BBS4 $20, target
                              target:") 0)))
  (check "BBS5 opcode = $DF"
         (= #xDF (aref (asm ".org $0801
                              BBS5 $20, target
                              target:") 0)))
  (check "BBS6 opcode = $EF"
         (= #xEF (aref (asm ".org $0801
                              BBS6 $20, target
                              target:") 0)))
  (check "BBS7 opcode = $FF"
         (= #xFF (aref (asm ".org $0801
                              BBS7 $20, target
                              target:") 0)))
  ;; Taille = 3 octets
  (check "BBS0 taille = 3"
         (= 3 (length (asm ".org $0801
                             BBS0 $20, target
                             target:")))))


;;; --------------------------------------------------------------------------
;;;  Tests : calcul d'offset relatif pour BBRn/BBSn
;;; --------------------------------------------------------------------------

(deftest test/bbr-bbs-offset
  ;; Branche en avant de 2 octets (au-delà de NOP)
  ;; .org $0801 : BBR0 $10, target → 3 octets ($0801-$0803)
  ;;              NOP              → 1 octet  ($0804)
  ;;              target:          → $0805
  ;; offset = $0805 - ($0801+3) = $0805 - $0804 = 1
  (check "BBR offset forward +1"
         (let ((b (asm ".org $0801
                         BBR0 $10, target
                         NOP
                         target:")))
           (= 1 (aref b 2))))

  ;; Branche en avant de 5 octets
  ;; BBR0 $10, target (3 oct) + NOP NOP NOP NOP (4 oct) → target à $0808
  ;; offset = $0808 - $0804 = 4
  (check "BBR offset forward +4"
         (let ((b (asm ".org $0801
                         BBR0 $10, target
                         NOP
                         NOP
                         NOP
                         NOP
                         target:")))
           (= 4 (aref b 2))))

  ;; Branche en arrière
  ;; .org $1000 : target: (= $1000)
  ;;              NOP NOP NOP (3 oct, pc=$1003)
  ;;              BBR1 $10, target (3 oct, pc=$1003..1005)
  ;; offset = $1000 - ($1003+3) = $1000 - $1006 = -6 → $FA
  (check "BBR offset backward -6 = $FA"
         (let ((b (asm ".org $1000
                         target:
                         NOP
                         NOP
                         NOP
                         BBR1 $10, target")))
           (= #xFA (aref b 5))))

  ;; BBS : même logique
  (check "BBS offset forward +1"
         (let ((b (asm ".org $0801
                         BBS3 $30, target
                         NOP
                         target:")))
           (= 1 (aref b 2)))))


;;; --------------------------------------------------------------------------
;;;  Tests : combinaison RMBn/SMBn + BBRn/BBSn
;;; --------------------------------------------------------------------------

(deftest test/rockwell-combination
  ;; Séquence : SMB3 $10 / BBR3 $10, label / RMB3 $10 / label:
  ;; SMB3 $10 = B7 10 (2 oct, $0801-$0802)
  ;; BBR3 $10, label : 3 oct ($0803-$0805), label = $0806
  ;;   offset = $0806 - ($0803+3) = $0806 - $0806 = 0
  ;; RMB3 $10 = 37 10 (2 oct, $0806-$0807)
  ;; label: = $0806
  (let ((b (asm ".org $0801
                  SMB3 $10
                  BBR3 $10, label
                  label:
                  RMB3 $10")))
    (check "combo: SMB3 opcode = $B7"     (= #xB7 (aref b 0)))
    (check "combo: SMB3 zp = $10"         (= #x10 (aref b 1)))
    (check "combo: BBR3 opcode = $3F"     (= #x3F (aref b 2)))
    (check "combo: BBR3 zp = $10"         (= #x10 (aref b 3)))
    (check "combo: BBR3 offset = 0"       (= #x00 (aref b 4)))
    (check "combo: RMB3 opcode = $37"     (= #x37 (aref b 5)))
    (check "combo: RMB3 zp = $10"         (= #x10 (aref b 6)))
    (check "combo: longueur totale = 7"   (= 7 (length b)))))


;;; --------------------------------------------------------------------------
;;;  Tests : tous les 8 RMBn en séquence
;;; --------------------------------------------------------------------------

(deftest test/rmb-all-8
  (let ((b (asm "RMB0 $AA
                  RMB1 $AA
                  RMB2 $AA
                  RMB3 $AA
                  RMB4 $AA
                  RMB5 $AA
                  RMB6 $AA
                  RMB7 $AA")))
    (check "all-RMB longueur = 16" (= 16 (length b)))
    (check "RMB0 opcode = $07" (= #x07 (aref b  0)))
    (check "RMB1 opcode = $17" (= #x17 (aref b  2)))
    (check "RMB2 opcode = $27" (= #x27 (aref b  4)))
    (check "RMB3 opcode = $37" (= #x37 (aref b  6)))
    (check "RMB4 opcode = $47" (= #x47 (aref b  8)))
    (check "RMB5 opcode = $57" (= #x57 (aref b 10)))
    (check "RMB6 opcode = $67" (= #x67 (aref b 12)))
    (check "RMB7 opcode = $77" (= #x77 (aref b 14)))
    (loop for i below 8
          do (check (format nil "RMB~D zp = $AA" i)
                    (= #xAA (aref b (1+ (* i 2))))))))


;;; --------------------------------------------------------------------------
;;;  Tests : tous les 8 SMBn en séquence
;;; --------------------------------------------------------------------------

(deftest test/smb-all-8
  (let ((b (asm "SMB0 $55
                  SMB1 $55
                  SMB2 $55
                  SMB3 $55
                  SMB4 $55
                  SMB5 $55
                  SMB6 $55
                  SMB7 $55")))
    (check "all-SMB longueur = 16" (= 16 (length b)))
    (check "SMB0 opcode = $87" (= #x87 (aref b  0)))
    (check "SMB1 opcode = $97" (= #x97 (aref b  2)))
    (check "SMB2 opcode = $A7" (= #xA7 (aref b  4)))
    (check "SMB3 opcode = $B7" (= #xB7 (aref b  6)))
    (check "SMB4 opcode = $C7" (= #xC7 (aref b  8)))
    (check "SMB5 opcode = $D7" (= #xD7 (aref b 10)))
    (check "SMB6 opcode = $E7" (= #xE7 (aref b 12)))
    (check "SMB7 opcode = $F7" (= #xF7 (aref b 14)))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests cl-asm/r65c02 ===~%")
  (test/rockwell-helpers)
  (test/65c02-compat)
  (test/rmb-opcodes)
  (test/smb-opcodes)
  (test/bbr-opcodes)
  (test/bbs-opcodes)
  (test/bbr-bbs-offset)
  (test/rockwell-combination)
  (test/rmb-all-8)
  (test/smb-all-8)
  (when *failures*
    (format t "~&Echecs r65c02 :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
