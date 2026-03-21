; -*- coding: utf-8 -*-
;;; tests/test-m68k.lisp
;;;
;;; Tests unitaires pour le backend M68K (Motorola 68000).
;;; Toutes les valeurs attendues sont calculées depuis le PRM Motorola M68000.

(defpackage #:cl-asm/test.m68k
  (:use #:cl #:cl-asm/backend.m68k)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.m68k)


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

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&~%[~A]~%" ',name)
     ,@body))

(defun asm (src &key (origin 0))
  "Assemble une chaîne source M68K et retourne un vecteur d'octets."
  (assemble-string-m68k src :origin origin))

(defun bytes= (result &rest expected)
  "Compare le résultat avec la séquence d'octets attendus."
  (and (= (length result) (length expected))
       (every #'= result expected)))


;;; --------------------------------------------------------------------------
;;;  1. Instructions sans opérande (implied)
;;; --------------------------------------------------------------------------

(deftest test-m68k-implied
  ;; NOP = $4E71
  (check "NOP"     (bytes= (asm "NOP")     #x4E #x71))
  ;; RTS = $4E75
  (check "RTS"     (bytes= (asm "RTS")     #x4E #x75))
  ;; RTR = $4E77
  (check "RTR"     (bytes= (asm "RTR")     #x4E #x77))
  ;; RTE = $4E73
  (check "RTE"     (bytes= (asm "RTE")     #x4E #x73))
  ;; TRAPV = $4E76
  (check "TRAPV"   (bytes= (asm "TRAPV")   #x4E #x76))
  ;; RESET = $4E70
  (check "RESET"   (bytes= (asm "RESET")   #x4E #x70))
  ;; ILLEGAL = $4AFC
  (check "ILLEGAL" (bytes= (asm "ILLEGAL") #x4A #xFC)))


;;; --------------------------------------------------------------------------
;;;  2. MOVE — transferts
;;; --------------------------------------------------------------------------

(deftest test-m68k-move-rr
  ;; MOVE.W D0, D1
  ;; Format MOVE : (sz<<12)|(dst_reg<<9)|(dst_mode<<6)|(src_mode<<3)|src_reg
  ;; .W → size_code=3 ; src=D0(mode=0,reg=0) ; dst=D1(mode=0,reg=1)
  ;; word = (3<<12)|(1<<9)|(0<<6)|(0<<3)|0 = $3200
  (check "MOVE.W D0,D1"  (bytes= (asm "MOVE.W D0, D1")  #x32 #x00))
  ;; MOVE.B D0, D1 → size_code=1 → $1200
  (check "MOVE.B D0,D1"  (bytes= (asm "MOVE.B D0, D1")  #x12 #x00))
  ;; MOVE.L D0, D1 → size_code=2 → $2200
  (check "MOVE.L D0,D1"  (bytes= (asm "MOVE.L D0, D1")  #x22 #x00))
  ;; MOVE.W D7, D0 → dst=D0(reg=0), src=D7(reg=7)
  ;; word = (3<<12)|(0<<9)|(0<<6)|(0<<3)|7 = $3007
  (check "MOVE.W D7,D0"  (bytes= (asm "MOVE.W D7, D0")  #x30 #x07))
  ;; MOVE.L A0, D0 → src=A0(mode=1,reg=0) ; .L→2 ; dst=D0
  ;; word = (2<<12)|(0<<9)|(0<<6)|(1<<3)|0 = $2008
  (check "MOVE.L A0,D0"  (bytes= (asm "MOVE.L A0, D0")  #x20 #x08)))

(deftest test-m68k-move-imm
  ;; MOVE.W #$1234, D0
  ;; src=imm(mode=7,reg=4)→ea_field=$3C ; dst=D0(mode=0,reg=0)
  ;; word = (3<<12)|(0<<9)|(0<<6)|(7<<3)|4 = $303C ; ext=($1234)
  (check "MOVE.W #$1234,D0"
         (bytes= (asm "MOVE.W #$1234, D0")  #x30 #x3C #x12 #x34))
  ;; MOVE.L #$12345678, D0
  ;; word = (2<<12)|(0<<9)|(0<<6)|$3C = $203C ; ext=($1234,$5678)
  (check "MOVE.L #$12345678,D0"
         (bytes= (asm "MOVE.L #$12345678, D0")
                 #x20 #x3C #x12 #x34 #x56 #x78))
  ;; MOVE.B #$FF, D3
  ;; src=imm→$3C ; dst=D3(mode=0,reg=3) ; .B→1
  ;; word=(1<<12)|(3<<9)|$3C = $163C ; ext=($00FF) → 2 octets $00,$FF
  (check "MOVE.B #$FF,D3"
         (bytes= (asm "MOVE.B #$FF, D3")    #x16 #x3C #x00 #xFF)))

(deftest test-m68k-move-indirect
  ;; MOVE.W (A0), D0
  ;; src=(A0)(mode=2,reg=0)→ea=$10 ; dst=D0(mode=0,reg=0) ; .W→3
  ;; word=(3<<12)|(0<<9)|(0<<6)|(2<<3)|0 = $3010
  (check "MOVE.W (A0),D0"
         (bytes= (asm "MOVE.W (A0), D0")    #x30 #x10))
  ;; MOVE.W (A0)+, -(A1)
  ;; src=(A0)+(mode=3,reg=0)→$18 ; dst=-(A1)(mode=4,reg=1)
  ;; word=(3<<12)|(1<<9)|(4<<6)|(3<<3)|0 = $3318
  (check "MOVE.W (A0)+,-(A1)"
         (bytes= (asm "MOVE.W (A0)+, -(A1)") #x33 #x18))
  ;; MOVE.W #$1234, (A0)
  ;; src=imm→$3C ; dst=(A0)(mode=2,reg=0)
  ;; word=(3<<12)|(0<<9)|(2<<6)|(7<<3)|4 = $30BC ; ext=($1234)
  (check "MOVE.W #$1234,(A0)"
         (bytes= (asm "MOVE.W #$1234, (A0)") #x30 #xBC #x12 #x34)))

(deftest test-m68k-movea
  ;; MOVEA.L D0, A0 : MOVE vers An (mode=1)
  ;; .L→size_code=2 ; dst_reg=A0=0 ; dst_mode=1 ; src=D0
  ;; word=(2<<12)|(0<<9)|(1<<6)|(0<<3)|0 = $2040
  (check "MOVEA.L D0,A0"
         (bytes= (asm "MOVEA.L D0, A0")     #x20 #x40))
  ;; MOVE.L D0, A0 (même encodage via dispatch automatique)
  (check "MOVE.L D0,A0 (→MOVEA)"
         (bytes= (asm "MOVE.L D0, A0")      #x20 #x40))
  ;; MOVEA.W D0, A0 : .W→3 ; word=(3<<12)|(0<<9)|(1<<6)|0 = $3040
  (check "MOVEA.W D0,A0"
         (bytes= (asm "MOVEA.W D0, A0")     #x30 #x40)))

(deftest test-m68k-moveq
  ;; MOVEQ #$42, D3 : word = 0111 011 0 0100 0010 = $7642
  (check "MOVEQ #$42,D3"   (bytes= (asm "MOVEQ #$42, D3")   #x76 #x42))
  ;; MOVEQ #0, D0 : word = $7000
  (check "MOVEQ #0,D0"     (bytes= (asm "MOVEQ #0, D0")     #x70 #x00))
  ;; MOVEQ #$7F, D7 : word = 0111 111 0 0111 1111 = $7E7F
  (check "MOVEQ #$7F,D7"   (bytes= (asm "MOVEQ #$7F, D7")   #x7E #x7F))
  ;; MOVEQ #-1, D0 : #-1 = #$FF → $70FF
  (check "MOVEQ #-1,D0"    (bytes= (asm "MOVEQ #-1, D0")    #x70 #xFF)))


;;; --------------------------------------------------------------------------
;;;  3. ADD / ADDI / ADDQ / ADDA
;;; --------------------------------------------------------------------------

(deftest test-m68k-add
  ;; ADD.W D0, D1 : EA→Dn (dir=0), Dn=D1, EA=D0
  ;; Format : 1101 Dn 0 sz EA → ($D<<12)|(1<<9)|(0<<8)|(1<<6)|0 = $D240
  (check "ADD.W D0,D1"
         (bytes= (asm "ADD.W D0, D1")       #xD2 #x40))
  ;; ADD.L D0, D1 : sc=2 → ($D<<12)|(1<<9)|0|(2<<6)|0 = $D280
  (check "ADD.L D0,D1"
         (bytes= (asm "ADD.L D0, D1")       #xD2 #x80))
  ;; ADD.W D0, (A1) : Dn→EA (dir=1), Dn=D0, EA=(A1)(mode=2,reg=1)=$11
  ;; word = ($D<<12)|(0<<9)|(1<<8)|(1<<6)|$11 = $D151
  (check "ADD.W D0,(A1)"
         (bytes= (asm "ADD.W D0, (A1)")     #xD1 #x51))
  ;; ADD.B (A0), D1 : EA→Dn (dir=0), sc=0
  ;; EA=(A0)(mode=2,reg=0)=$10 ; word=($D<<12)|(1<<9)|0|0|$10 = $D210
  (check "ADD.B (A0),D1"
         (bytes= (asm "ADD.B (A0), D1")     #xD2 #x10)))

(deftest test-m68k-addi
  ;; ADDI.W #$10, D0
  ;; base=$0600, sc=1, ea=D0=0 → word=$0640 ; ext=($0010)
  (check "ADDI.W #$10,D0"
         (bytes= (asm "ADDI.W #$10, D0")    #x06 #x40 #x00 #x10))
  ;; ADDI.B #$FF, D0 : base=$0600, sc=0, ea=0 → $0600 ; ext=($00FF)
  (check "ADDI.B #$FF,D0"
         (bytes= (asm "ADDI.B #$FF, D0")    #x06 #x00 #x00 #xFF))
  ;; ADDI.L #$12345678, D0 : sc=2 → word=$0680 ; ext=($1234,$5678)
  (check "ADDI.L #$12345678,D0"
         (bytes= (asm "ADDI.L #$12345678, D0")
                 #x06 #x80 #x12 #x34 #x56 #x78)))

(deftest test-m68k-addq
  ;; ADDQ.W #4, D0
  ;; Format : 0101 nnn 1 ss EA  (bit8=1 pour ADDQ)
  ;; n=4(100) ; sc=1(01) ; ea=D0=0 → (5<<12)|(4<<9)|(1<<8)|(1<<6)|0 = $5940
  (check "ADDQ.W #4,D0"
         (bytes= (asm "ADDQ.W #4, D0")      #x59 #x40))
  ;; ADDQ.L #1, D0 : n=1, sc=2, bit8=1 → 0101 001 1 10 000 000 = $5380
  (check "ADDQ.L #1,D0"
         (bytes= (asm "ADDQ.L #1, D0")      #x53 #x80))
  ;; ADDQ.W #8, D0 : n=8→encodé comme 0 → (5<<12)|(0<<9)|(1<<8)|(1<<6)|0 = $5140
  (check "ADDQ.W #8,D0"
         (bytes= (asm "ADDQ.W #8, D0")      #x51 #x40)))

(deftest test-m68k-adda
  ;; ADDA.L D0, A0
  ;; Format : 1101 An 1 sz EA avec sz: .W=011, .L=111 (en bits 8-6)
  ;; base=$D000 ; an=0 ; sc_bit=1(.L) ; bits 7-6=11 → (3<<6) ; ea=D0=0
  ;; word = $D000|(0<<9)|(1<<8)|(3<<6)|0 = $D1C0
  (check "ADDA.L D0,A0"
         (bytes= (asm "ADDA.L D0, A0")      #xD1 #xC0))
  ;; ADDA.W D0, A0 : sc_bit=0 → word=$D0C0
  (check "ADDA.W D0,A0"
         (bytes= (asm "ADDA.W D0, A0")      #xD0 #xC0))
  ;; ADDA.L #$1000, A1 : ea=imm(mode7,reg4)=$3C ; an=1
  ;; word=$D000|(1<<9)|(1<<8)|(3<<6)|$3C = $D3FC ; ext=($0000,$1000)
  (check "ADDA.L #$1000,A1"
         (bytes= (asm "ADDA.L #$1000, A1")
                 #xD3 #xFC #x00 #x00 #x10 #x00)))


;;; --------------------------------------------------------------------------
;;;  4. SUB / SUBI / SUBQ / SUBA
;;; --------------------------------------------------------------------------

(deftest test-m68k-sub
  ;; SUB.W D0, D1 : ($9<<12)|(1<<9)|0|(1<<6)|0 = $9240
  (check "SUB.W D0,D1"
         (bytes= (asm "SUB.W D0, D1")       #x92 #x40))
  ;; SUB.W D1, D0 : EA=D1(mode=0,reg=1)=1 ; Dn=D0(0) ; dir=0
  ;; word=($9<<12)|(0<<9)|0|(1<<6)|1 = $9041
  (check "SUB.W D1,D0"
         (bytes= (asm "SUB.W D1, D0")       #x90 #x41))
  ;; SUB.L D0, D1 : sc=2 → $9280
  (check "SUB.L D0,D1"
         (bytes= (asm "SUB.L D0, D1")       #x92 #x80)))

(deftest test-m68k-subi
  ;; SUBI.W #$10, D0 : base=$0400, sc=1, ea=0 → $0440 ; ext=($0010)
  (check "SUBI.W #$10,D0"
         (bytes= (asm "SUBI.W #$10, D0")    #x04 #x40 #x00 #x10)))

(deftest test-m68k-subq
  ;; SUBQ.W #4, D0
  ;; Format : 0101 nnn 0 ss EA (bit8=0 pour SUBQ)
  ;; n=4 ; sc=1 ; ea=D0=0 → (5<<12)|(4<<9)|(0<<8)|(1<<6)|0 = $5840
  (check "SUBQ.W #4,D0"
         (bytes= (asm "SUBQ.W #4, D0")      #x58 #x40))
  ;; SUBQ.L #1, D0 : n=1, sc=2, bit8=0 → 0101 001 0 10 000 000 = $5280
  (check "SUBQ.L #1,D0"
         (bytes= (asm "SUBQ.L #1, D0")      #x52 #x80)))

(deftest test-m68k-suba
  ;; SUBA.L D0, A0 : base=$9000 ; sc_bit=1 ; word=$91C0
  (check "SUBA.L D0,A0"
         (bytes= (asm "SUBA.L D0, A0")      #x91 #xC0))
  ;; SUBA.W D0, A0 : sc_bit=0 → word=$90C0
  (check "SUBA.W D0,A0"
         (bytes= (asm "SUBA.W D0, A0")      #x90 #xC0)))


;;; --------------------------------------------------------------------------
;;;  5. AND / OR / EOR
;;; --------------------------------------------------------------------------

(deftest test-m68k-and
  ;; AND.W D0, D1 : ($C<<12)|(1<<9)|0|(1<<6)|0 = $C240
  (check "AND.W D0,D1"
         (bytes= (asm "AND.W D0, D1")       #xC2 #x40))
  ;; AND.W D1, D0 : EA=D1=1 ; Dn=D0=0 ; dir=0
  ;; word=($C<<12)|(0<<9)|0|(1<<6)|1 = $C041
  (check "AND.W D1,D0"
         (bytes= (asm "AND.W D1, D0")       #xC0 #x41))
  ;; AND.L D0, D1 : sc=2 → $C280
  (check "AND.L D0,D1"
         (bytes= (asm "AND.L D0, D1")       #xC2 #x80)))

(deftest test-m68k-andi
  ;; ANDI.W #$FF00, D0 : base=$0200, sc=1, ea=0 → $0240 ; ext=($FF00)
  (check "ANDI.W #$FF00,D0"
         (bytes= (asm "ANDI.W #$FF00, D0")  #x02 #x40 #xFF #x00)))

(deftest test-m68k-or
  ;; OR.W D0, D1 : ($8<<12)|(1<<9)|0|(1<<6)|0 = $8240
  (check "OR.W D0,D1"
         (bytes= (asm "OR.W D0, D1")        #x82 #x40))
  ;; OR.L D0, D1 : $8280
  (check "OR.L D0,D1"
         (bytes= (asm "OR.L D0, D1")        #x82 #x80)))

(deftest test-m68k-ori
  ;; ORI.W #$1234, D0 : base=$0000, sc=1, ea=0 → $0040 ; ext=($1234)
  (check "ORI.W #$1234,D0"
         (bytes= (asm "ORI.W #$1234, D0")   #x00 #x40 #x12 #x34)))

(deftest test-m68k-eor
  ;; EOR.W D0, D1 : toujours Dn→EA (dir=1)
  ;; ($B<<12)|(0<<9)|(1<<8)|(1<<6)|1 = $B141
  (check "EOR.W D0,D1"
         (bytes= (asm "EOR.W D0, D1")       #xB1 #x41))
  ;; EOR.L D0, D1 : sc=2 → ($B<<12)|(0<<9)|(1<<8)|(2<<6)|1 = $B181
  (check "EOR.L D0,D1"
         (bytes= (asm "EOR.L D0, D1")       #xB1 #x81)))

(deftest test-m68k-eori
  ;; EORI.W #$1234, D0 : base=$0A00, sc=1, ea=0 → $0A40 ; ext=($1234)
  (check "EORI.W #$1234,D0"
         (bytes= (asm "EORI.W #$1234, D0")  #x0A #x40 #x12 #x34)))


;;; --------------------------------------------------------------------------
;;;  6. CMP / CMPI / CMPA
;;; --------------------------------------------------------------------------

(deftest test-m68k-cmp
  ;; CMP.W D0, D1 : EA→Dn (dir=0 implicite pour CMP)
  ;; ($B<<12)|(1<<9)|(0<<8)|(1<<6)|0 = $B240
  (check "CMP.W D0,D1"
         (bytes= (asm "CMP.W D0, D1")       #xB2 #x40))
  ;; CMP.L D0, D1 : sc=2 → $B280
  (check "CMP.L D0,D1"
         (bytes= (asm "CMP.L D0, D1")       #xB2 #x80))
  ;; CMP.B #$42, D0 : ea=imm=$3C ; Dn=D0=0 ; dir=0 ; sc=0
  ;; word=($B<<12)|(0<<9)|0|0|$3C = $B03C ; ext=($0042)
  (check "CMP.B #$42,D0"
         (bytes= (asm "CMP.B #$42, D0")     #xB0 #x3C #x00 #x42)))

(deftest test-m68k-cmpi
  ;; CMPI.W #$1234, D0 : base=$0C00, sc=1, ea=0 → $0C40 ; ext=($1234)
  (check "CMPI.W #$1234,D0"
         (bytes= (asm "CMPI.W #$1234, D0")  #x0C #x40 #x12 #x34)))

(deftest test-m68k-cmpa
  ;; CMPA.L D0, A0 : base=$B000 ; an=0 ; sc_bit=1(.L) ; word=$B1C0
  (check "CMPA.L D0,A0"
         (bytes= (asm "CMPA.L D0, A0")      #xB1 #xC0))
  ;; CMPA.W D0, A0 : sc_bit=0 → $B0C0
  (check "CMPA.W D0,A0"
         (bytes= (asm "CMPA.W D0, A0")      #xB0 #xC0)))


;;; --------------------------------------------------------------------------
;;;  7. MUL / DIV
;;; --------------------------------------------------------------------------

(deftest test-m68k-muldiv
  ;; MULU D0, D1 : $C0C0|(1<<9)|0 = $C2C0
  (check "MULU D0,D1"
         (bytes= (asm "MULU D0, D1")        #xC2 #xC0))
  ;; MULS D0, D1 : $C1C0|(1<<9)|0 = $C3C0
  (check "MULS D0,D1"
         (bytes= (asm "MULS D0, D1")        #xC3 #xC0))
  ;; DIVU D0, D1 : $80C0|(1<<9)|0 = $82C0
  (check "DIVU D0,D1"
         (bytes= (asm "DIVU D0, D1")        #x82 #xC0))
  ;; DIVS D0, D1 : $81C0|(1<<9)|0 = $83C0
  (check "DIVS D0,D1"
         (bytes= (asm "DIVS D0, D1")        #x83 #xC0)))


;;; --------------------------------------------------------------------------
;;;  8. Shifts et rotations
;;; --------------------------------------------------------------------------

(deftest test-m68k-shift-imm
  ;; ASL.W #1, D0 : format 1110 nnn d sz 0 type Dn
  ;; n=1 ; d=1(gauche) ; sz=01(W) ; type=00(AS) ; Dn=D0=0
  ;; = 1110 001 1 01 0 00 000 = $E340
  (check "ASL.W #1,D0"
         (bytes= (asm "ASL.W #1, D0")       #xE3 #x40))
  ;; ASR.W #1, D0 : d=0 → 1110 001 0 01 0 00 000 = $E240
  (check "ASR.W #1,D0"
         (bytes= (asm "ASR.W #1, D0")       #xE2 #x40))
  ;; LSL.W #2, D0 : n=2, d=1, sz=01, type=01(LS)
  ;; = 1110 010 1 01 0 01 000 = $E548
  (check "LSL.W #2,D0"
         (bytes= (asm "LSL.W #2, D0")       #xE5 #x48))
  ;; LSR.W #2, D0 : d=0 → 1110 010 0 01 0 01 000 = $E448
  (check "LSR.W #2,D0"
         (bytes= (asm "LSR.W #2, D0")       #xE4 #x48))
  ;; ROL.W #1, D0 : type=11(RO), d=1
  ;; = 1110 001 1 01 0 11 000 = $E358
  (check "ROL.W #1,D0"
         (bytes= (asm "ROL.W #1, D0")       #xE3 #x58))
  ;; ROR.W #1, D0 : d=0 → $E258
  (check "ROR.W #1,D0"
         (bytes= (asm "ROR.W #1, D0")       #xE2 #x58))
  ;; ROXL.W #1, D0 : type=10(ROX), d=1
  ;; = 1110 001 1 01 0 10 000 = $E350
  (check "ROXL.W #1,D0"
         (bytes= (asm "ROXL.W #1, D0")      #xE3 #x50))
  ;; ASL.B #3, D2 : n=3, d=1, sz=00(B), type=00, Dn=D2
  ;; = 1110 011 1 00 0 00 010 = $E702
  (check "ASL.B #3,D2"
         (bytes= (asm "ASL.B #3, D2")       #xE7 #x02))
  ;; ASL.L #1, D0 : sz=10(L) → 1110 001 1 10 0 00 000 = $E380
  (check "ASL.L #1,D0"
         (bytes= (asm "ASL.L #1, D0")       #xE3 #x80)))

(deftest test-m68k-shift-reg
  ;; ASL.W D1, D0 : format 1110 cnt d sz 1 type Dn
  ;; cnt=D1=1 ; d=1(gauche) ; sz=01(W) ; type=00(AS) ; Dn=D0=0
  ;; = 1110 001 1 01 1 00 000 = $E360... wait
  ;; bit 5 = 1 (register count) ; bits 4-3 = type = 00 ; bits 2-0 = Dn
  ;; = 1110 001 1 01 1 00 000 = $E360
  (check "ASL.W D1,D0"
         (bytes= (asm "ASL.W D1, D0")       #xE3 #x60))
  ;; ASL.W D0, D1 : cnt=D0=0 ; d=1 ; sz=01 ; Dn=D1=1
  ;; = 1110 000 1 01 1 00 001 = $E161
  (check "ASL.W D0,D1"
         (bytes= (asm "ASL.W D0, D1")       #xE1 #x61))
  ;; ROL.W D0, D1 : type=11(RO) ; cnt=0 ; Dn=D1=1
  ;; = 1110 000 1 01 1 11 001 = $E179
  (check "ROL.W D0,D1"
         (bytes= (asm "ROL.W D0, D1")       #xE1 #x79))
  ;; LSR.W D1, D0 : d=0 ; type=01(LS) ; cnt=1 ; Dn=0
  ;; = 1110 001 0 01 1 01 000 = $E268
  (check "LSR.W D1,D0"
         (bytes= (asm "LSR.W D1, D0")       #xE2 #x68)))

(deftest test-m68k-shift-mem
  ;; ASL (A0) : format 1110 op d 11 EA
  ;; op=0(AS), d=1(gauche) → 1110 000 1 11 010 000 = $E1D0
  (check "ASL (A0)"
         (bytes= (asm "ASL (A0)")           #xE1 #xD0))
  ;; ASR (A0) : d=0 → $E0D0
  (check "ASR (A0)"
         (bytes= (asm "ASR (A0)")           #xE0 #xD0))
  ;; LSL (A0) : op=1, d=1 → 1110 001 1 11 010 000 = $E3D0
  (check "LSL (A0)"
         (bytes= (asm "LSL (A0)")           #xE3 #xD0))
  ;; ROL (A0) : op=3, d=1 → 1110 011 1 11 010 000 = $E7D0
  (check "ROL (A0)"
         (bytes= (asm "ROL (A0)")           #xE7 #xD0)))


;;; --------------------------------------------------------------------------
;;;  9. CLR / NEG / NEGX / NOT / TST
;;; --------------------------------------------------------------------------

(deftest test-m68k-unary
  ;; CLR.W D0 : base=$4200, sc=1, ea=0 → $4240
  (check "CLR.W D0"
         (bytes= (asm "CLR.W D0")           #x42 #x40))
  ;; CLR.B (A0) : sc=0, ea=(A0)=(2<<3)|0=$10 → $4210
  (check "CLR.B (A0)"
         (bytes= (asm "CLR.B (A0)")         #x42 #x10))
  ;; CLR.L D0 : sc=2 → $4280
  (check "CLR.L D0"
         (bytes= (asm "CLR.L D0")           #x42 #x80))
  ;; NEG.W D0 : base=$4400, sc=1 → $4440
  (check "NEG.W D0"
         (bytes= (asm "NEG.W D0")           #x44 #x40))
  ;; NEGX.W D0 : base=$4000, sc=1 → $4040
  (check "NEGX.W D0"
         (bytes= (asm "NEGX.W D0")          #x40 #x40))
  ;; NOT.W D0 : base=$4600, sc=1 → $4640
  (check "NOT.W D0"
         (bytes= (asm "NOT.W D0")           #x46 #x40))
  ;; TST.L D0 : base=$4A00, sc=2 → $4A80
  (check "TST.L D0"
         (bytes= (asm "TST.L D0")           #x4A #x80))
  ;; TST.B D0 : sc=0 → $4A00
  (check "TST.B D0"
         (bytes= (asm "TST.B D0")           #x4A #x00)))

(deftest test-m68k-ext-swap
  ;; EXT.W D0 (byte→word) : $4880|0 = $4880
  (check "EXT.W D0"
         (bytes= (asm "EXT.W D0")           #x48 #x80))
  ;; EXT.L D0 (word→long) : $48C0|0 = $48C0
  (check "EXT.L D0"
         (bytes= (asm "EXT.L D0")           #x48 #xC0))
  ;; SWAP D0 : $4840|0 = $4840
  (check "SWAP D0"
         (bytes= (asm "SWAP D0")            #x48 #x40))
  ;; SWAP D3 : $4840|3 = $4843
  (check "SWAP D3"
         (bytes= (asm "SWAP D3")            #x48 #x43)))


;;; --------------------------------------------------------------------------
;;;  10. JMP / JSR / LEA / PEA
;;; --------------------------------------------------------------------------

(deftest test-m68k-jmp-jsr
  ;; JMP $1000 : base=$4EC0, ea=abs.W($1000)(mode=7,reg=0)→$38
  ;; word=$4EC0|$38=$4EF8 ; ext=($1000)
  (check "JMP $1000"
         (bytes= (asm "JMP $1000")          #x4E #xF8 #x10 #x00))
  ;; JSR $1000 : base=$4E80 → $4EB8 ; ext=($1000)
  (check "JSR $1000"
         (bytes= (asm "JSR $1000")          #x4E #xB8 #x10 #x00))
  ;; JMP (A0) : ea=(A0)(mode=2,reg=0)→$10 ; word=$4EC0|$10=$4ED0
  (check "JMP (A0)"
         (bytes= (asm "JMP (A0)")           #x4E #xD0))
  ;; JSR (A0) : $4E80|$10=$4E90
  (check "JSR (A0)"
         (bytes= (asm "JSR (A0)")           #x4E #x90)))

(deftest test-m68k-lea
  ;; LEA $1000, A0 : ea=abs.W→$38 ; an=0 ; word=$41C0|(0<<9)|$38=$41F8
  (check "LEA $1000,A0"
         (bytes= (asm "LEA $1000, A0")      #x41 #xF8 #x10 #x00))
  ;; LEA (A0), A1 : ea=(A0)(mode=2,reg=0)=$10 ; an=1
  ;; word=$41C0|(1<<9)|$10=$43D0
  (check "LEA (A0),A1"
         (bytes= (asm "LEA (A0), A1")       #x43 #xD0))
  ;; LEA 4(A0), A1 : ea=d(An)(mode=5,reg=0)→$28 ; an=1
  ;; word=$41C0|(1<<9)|$28=$43E8 ; ext=($0004)
  (check "LEA 4(A0),A1"
         (bytes= (asm "LEA 4(A0), A1")      #x43 #xE8 #x00 #x04))
  ;; PEA $1000 : base=$4840 ; ea=abs.W→$38 ; word=$4840|$38=$4878
  (check "PEA $1000"
         (bytes= (asm "PEA $1000")          #x48 #x78 #x10 #x00)))


;;; --------------------------------------------------------------------------
;;;  11. Branches
;;; --------------------------------------------------------------------------

(deftest test-m68k-branches
  ;; BRA.W label — branche de 2 octets en avant (disp=2 depuis fin d'instr)
  ;; .org $1000 ; NOP ; BRA.W $1004
  ;; pc=$1002, disp=$1004-($1002+2)=0, base=$6000 → $6000 $0000
  (check "BRA.W forward disp=0"
         (bytes= (asm ".org $1000
                       NOP
                       BRA.W $1004")
                 #x4E #x71         ; NOP
                 #x60 #x00 #x00 #x00)) ; BRA.W disp=0
  ;; BRA.W disp>0 : .org $1000 ; BRA.W $1006 → disp=$1006-($1000+2)=4
  (check "BRA.W disp=4"
         (bytes= (asm ".org $1000
                       BRA.W $1006")
                 #x60 #x00 #x00 #x04))
  ;; BRA.S label court : BRA.B ou taille .S
  ;; .org $1000 ; BRA.B $1002 → disp=$1002-($1000+2)=0 ; word=$6000
  (check "BRA.B disp=0"
         (bytes= (asm ".org $1000
                       BRA.B $1002")
                 #x60 #x00))
  ;; BEQ.W → condition code 7 ; base=$6700
  (check "BEQ.W disp=4"
         (bytes= (asm ".org $1000
                       BEQ.W $1006")
                 #x67 #x00 #x00 #x04))
  ;; BNE.W → cc=6 ; base=$6600
  (check "BNE.W disp=4"
         (bytes= (asm ".org $1000
                       BNE.W $1006")
                 #x66 #x00 #x00 #x04))
  ;; BSR.W → cc=1 ; base=$6100
  (check "BSR.W disp=4"
         (bytes= (asm ".org $1000
                       BSR.W $1006")
                 #x61 #x00 #x00 #x04))
  ;; Branche backward
  ;; .org $1000 ; NOP ($1002) ; NOP ($1004) ; BRA.W $1000 → disp=$1000-($1004+2)=-6
  (check "BRA.W backward"
         (bytes= (asm ".org $1000
                       NOP
                       NOP
                       BRA.W $1000")
                 #x4E #x71 #x4E #x71
                 #x60 #x00 #xFF #xFA)))

(deftest test-m68k-dbcc
  ;; DBF D0, label : cc=1, Dn=D0=0
  ;; word=$50C8|(1<<8)|0=$51C8 ; ext=(disp)
  ;; .org $1000 ; DBF D0, $1004 → disp=$1004-($1000+2)=2
  (check "DBF D0,label"
         (bytes= (asm ".org $1000
                       DBF D0, $1004")
                 #x51 #xC8 #x00 #x02))
  ;; DBRA est un alias de DBF
  (check "DBRA D0,label"
         (bytes= (asm ".org $1000
                       DBRA D0, $1004")
                 #x51 #xC8 #x00 #x02))
  ;; DBNE D1, label : cc=6
  ;; word=$50C8|(6<<8)|1=$56C9 ; ext=(disp)
  (check "DBNE D1,label"
         (bytes= (asm ".org $1000
                       DBNE D1, $1004")
                 #x56 #xC9 #x00 #x02)))


;;; --------------------------------------------------------------------------
;;;  12. LINK / UNLK / TRAP
;;; --------------------------------------------------------------------------

(deftest test-m68k-misc
  ;; LINK A0, #-8 : word=$4E50|0=$4E50 ; ext=(m68k-s16(-8)=$FFF8)
  (check "LINK A0,#-8"
         (bytes= (asm "LINK A0, #-8")       #x4E #x50 #xFF #xF8))
  ;; LINK A6, #-16 : word=$4E50|6=$4E56 ; ext=($FFF0)
  (check "LINK A6,#-16"
         (bytes= (asm "LINK A6, #-16")      #x4E #x56 #xFF #xF0))
  ;; UNLK A0 : $4E58|0=$4E58
  (check "UNLK A0"
         (bytes= (asm "UNLK A0")            #x4E #x58))
  ;; UNLK A6 : $4E58|6=$4E5E
  (check "UNLK A6"
         (bytes= (asm "UNLK A6")            #x4E #x5E))
  ;; TRAP #0 : $4E40|0=$4E40
  (check "TRAP #0"
         (bytes= (asm "TRAP #0")            #x4E #x40))
  ;; TRAP #15 : $4E40|$F=$4E4F
  (check "TRAP #15"
         (bytes= (asm "TRAP #15")           #x4E #x4F))
  ;; STOP #$2700 : $4E72 + ext=($2700)
  (check "STOP #$2700"
         (bytes= (asm "STOP #$2700")        #x4E #x72 #x27 #x00)))


;;; --------------------------------------------------------------------------
;;;  13. Bit ops
;;; --------------------------------------------------------------------------

(deftest test-m68k-bitops
  ;; BTST D0, D1 : Dn,ea form ; base=$0100|(Dn<<9)|(0<<6)|ea
  ;; Dn=D0=0 ; ea=D1(mode=0,reg=1)=1 → word=$0100|(0<<9)|(0<<6)|1=$0101
  (check "BTST D0,D1"
         (bytes= (asm "BTST D0, D1")        #x01 #x01))
  ;; BSET D0, D1 : op=3 → $0100|(0<<9)|(3<<6)|1 = $01C1
  (check "BSET D0,D1"
         (bytes= (asm "BSET D0, D1")        #x01 #xC1))
  ;; BCLR D0, D1 : op=2 → $0100|(0<<9)|(2<<6)|1 = $0181
  (check "BCLR D0,D1"
         (bytes= (asm "BCLR D0, D1")        #x01 #x81))
  ;; BCHG D0, D1 : op=1 → $0100|(0<<9)|(1<<6)|1 = $0141
  (check "BCHG D0,D1"
         (bytes= (asm "BCHG D0, D1")        #x01 #x41))
  ;; BTST #7, D0 : imm form ; base=$0800|(0<<6)|0=$0800 ; ext=(7)
  ;; word=$0800 + imm word=($0007) → bytes $08,$00,$00,$07
  (check "BTST #7,D0"
         (bytes= (asm "BTST #7, D0")        #x08 #x00 #x00 #x07))
  ;; BSET #3, D1 : op=3 ; ea=D1=1 → $0800|(3<<6)|1=$08C1 ; ext=($0003)
  (check "BSET #3,D1"
         (bytes= (asm "BSET #3, D1")        #x08 #xC1 #x00 #x03)))


;;; --------------------------------------------------------------------------
;;;  14. EXG / ABCD / NBCD
;;; --------------------------------------------------------------------------

(deftest test-m68k-exg-bcd
  ;; EXG D0, D1 : Dx,Dy → mode=$08 ; word=$C000|(0<<9)|($08<<3)|1=$C041... wait
  ;; EXG format: 1100 Rx 1 type Ry
  ;; Dx,Dy: type=01000 → 1100 000 1 01000 001 = $C141
  (check "EXG D0,D1"
         (bytes= (asm "EXG D0, D1")         #xC1 #x41))
  ;; EXG A0, A1 : Ax,Ay → type=01001 → 1100 000 1 01001 001 = $C149
  (check "EXG A0,A1"
         (bytes= (asm "EXG A0, A1")         #xC1 #x49))
  ;; EXG D0, A0 : Dx,Ay → type=10001 → 1100 000 1 10001 000 = $C188
  (check "EXG D0,A0"
         (bytes= (asm "EXG D0, A0")         #xC1 #x88))
  ;; ABCD D0, D1 : $C100|(1<<9)|(0<<3)|0 = $C300
  (check "ABCD D0,D1"
         (bytes= (asm "ABCD D0, D1")        #xC3 #x00))
  ;; SBCD D0, D1 : $8100|(1<<9)|(0<<3)|0 = $8300
  (check "SBCD D0,D1"
         (bytes= (asm "SBCD D0, D1")        #x83 #x00))
  ;; NBCD D0 : $4800|ea=0 = $4800
  (check "NBCD D0"
         (bytes= (asm "NBCD D0")            #x48 #x00)))


;;; --------------------------------------------------------------------------
;;;  15. Labels et séquences
;;; --------------------------------------------------------------------------

(deftest test-m68k-labels
  ;; Séquence avec label
  (check "NOP + RTS"
         (bytes= (asm "NOP
                       RTS")
                 #x4E #x71 #x4E #x75))
  ;; Label utilisé comme cible de branche
  (check "loop: NOP ; BRA.W loop"
         (bytes= (asm ".org $1000
                       loop: NOP
                       BRA.W loop")
                 #x4E #x71              ; NOP à $1000
                 #x60 #x00 #xFF #xFC))) ; BRA.W $1000 ; disp=$1000-($1002+2)=-4


;;; --------------------------------------------------------------------------
;;;  16. Modes d'adressage étendus
;;; --------------------------------------------------------------------------

(deftest test-m68k-addressing
  ;; MOVE.W 4(A0), D0 : ea=d(A0)(mode=5,reg=0)→$28 ; word=(3<<12)|0|0|(5<<3)|0=$3028
  ;; ext=($0004) ; dst=D0
  (check "MOVE.W 4(A0),D0"
         (bytes= (asm "MOVE.W 4(A0), D0")  #x30 #x28 #x00 #x04))
  ;; CLR.W 4(A0) : base=$4200, sc=1, ea=$28 → $4268 ; ext=($0004)
  (check "CLR.W 4(A0)"
         (bytes= (asm "CLR.W 4(A0)")       #x42 #x68 #x00 #x04))
  ;; MOVE.W (A0)+, D0 : ea=post-inc(mode=3,reg=0)→$18 ; word=$3018
  (check "MOVE.W (A0)+,D0"
         (bytes= (asm "MOVE.W (A0)+, D0")  #x30 #x18))
  ;; MOVE.W -(A0), D0 : ea=pre-dec(mode=4,reg=0)→$20 ; word=$3020
  (check "MOVE.W -(A0),D0"
         (bytes= (asm "MOVE.W -(A0), D0")  #x30 #x20))
  ;; ADD.W D0, 4(A1) : Dn=D0, ea=d(A1)(mode=5,reg=1)→$29 ; dir=1
  ;; word=($D<<12)|(0<<9)|(1<<8)|(1<<6)|$29=$D169 ; ext=($0004)
  (check "ADD.W D0,4(A1)"
         (bytes= (asm "ADD.W D0, 4(A1)")   #xD1 #x69 #x00 #x04)))


;;; --------------------------------------------------------------------------
;;;  Bilan
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (format t "~%=== Tests M68K backend ===~%")
  (setf *pass* 0 *fail* 0 *failures* '())
  (test-m68k-implied)
  (test-m68k-move-rr)
  (test-m68k-move-imm)
  (test-m68k-move-indirect)
  (test-m68k-movea)
  (test-m68k-moveq)
  (test-m68k-add)
  (test-m68k-addi)
  (test-m68k-addq)
  (test-m68k-adda)
  (test-m68k-sub)
  (test-m68k-subi)
  (test-m68k-subq)
  (test-m68k-suba)
  (test-m68k-and)
  (test-m68k-andi)
  (test-m68k-or)
  (test-m68k-ori)
  (test-m68k-eor)
  (test-m68k-eori)
  (test-m68k-cmp)
  (test-m68k-cmpi)
  (test-m68k-cmpa)
  (test-m68k-muldiv)
  (test-m68k-shift-imm)
  (test-m68k-shift-reg)
  (test-m68k-shift-mem)
  (test-m68k-unary)
  (test-m68k-ext-swap)
  (test-m68k-jmp-jsr)
  (test-m68k-lea)
  (test-m68k-branches)
  (test-m68k-dbcc)
  (test-m68k-misc)
  (test-m68k-bitops)
  (test-m68k-exg-bcd)
  (test-m68k-labels)
  (test-m68k-addressing)
  (format t "~%=== M68K backend : ~D OK, ~D KO ===~%" *pass* *fail*)
  (zerop *fail*))
