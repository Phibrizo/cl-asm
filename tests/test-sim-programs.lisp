; -*- coding: utf-8 -*-
;;; tests/test-sim-programs.lisp
;;;
;;; Tests d'intégration : pipeline complet assembler → simulateur → vérification.
;;; Contrairement à test-sim-6502.lisp (opcodes unitaires), chaque test ici
;;; assemble un programme entier et contrôle le résultat final.
;;;
;;; Groupes :
;;;   test/prog-arithmetic   — arithmétique et logique          (15 tests)
;;;   test/prog-memory       — modes d'adressage mémoire        (12 tests)
;;;   test/prog-subroutines  — JSR/RTS, pile, JMP               ( 9 tests)
;;;   test/prog-algorithms   — algorithmes complets              (10 tests)
;;;   test/prog-lasm         — pipeline via syntaxe .lasm        ( 9 tests)

(defpackage #:cl-asm/test.sim-programs
  (:use #:cl #:cl-asm/simulator.6502)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.sim-programs)


;;; --------------------------------------------------------------------------
;;;  Infrastructure de test (même convention que les autres suites)
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

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&--- ~A ---~%" ',name)
     ,@body))


;;; --------------------------------------------------------------------------
;;;  Helpers
;;; --------------------------------------------------------------------------

;;; Assemble la SOURCE (syntaxe classique), charge à ORIGIN, exécute.
;;; Retourne le struct CPU final après BRK.
(defun run-asm (source &key (origin #x0200))
  (let* ((bytes (cl-asm/backend.6502:assemble-string source))
         (cpu   (make-cpu))
         (cpu   (load-program cpu bytes :origin origin)))
    (nth-value 0 (run-cpu cpu))))

;;; Identique mais via syntaxe .lasm.
(defun run-lasm (source &key (origin #x0200))
  (let* ((bytes (cl-asm/lasm:assemble-lasm-string source :origin origin :target :6502))
         (cpu   (make-cpu))
         (cpu   (load-program cpu bytes :origin origin)))
    (nth-value 0 (run-cpu cpu))))

;;; Accesseurs courts
(defun A (cpu) (cpu-a cpu))
(defun X (cpu) (cpu-x cpu))
(defun Y (cpu) (cpu-y cpu))
(defun M (cpu addr) (mem-read cpu addr))
(defun flag-set-p (cpu bit) (not (zerop (logand (cpu-p cpu) bit))))


;;; --------------------------------------------------------------------------
;;;  test/prog-arithmetic
;;; --------------------------------------------------------------------------

(deftest test/prog-arithmetic

  ;; 1. Multiplication par additions répétées : 5 × 6 = 30
  (let ((cpu (run-asm "
    .org $0200
    LDA #$00
    LDX #$06
loop:
    CLC
    ADC #$05
    DEX
    BNE loop
    BRK")))
    (check "5 x 6 = 30" (= #x1E (A cpu))))

  ;; 2. Somme 1+2+...+10 = 55
  (let ((cpu (run-asm "
    .org $0200
    LDA #$00
    LDX #$0A
loop:
    STX $00
    CLC
    ADC $00
    DEX
    BNE loop
    BRK")))
    (check "somme 1..10 = 55" (= #x37 (A cpu))))

  ;; 3. Soustraction : 100 - 37 = 63
  (let ((cpu (run-asm "
    .org $0200
    LDA #100
    SEC
    SBC #37
    BRK")))
    (check "100 - 37 = 63" (= 63 (A cpu))))

  ;; 4. Maximum de deux valeurs (42 et 17) → 42
  (let ((cpu (run-asm "
    .org $0200
    LDA #42
    CMP #17
    BCS done
    LDA #17
done:
    BRK")))
    (check "max(42, 17) = 42" (= 42 (A cpu))))

  ;; 5. Minimum de deux valeurs (42 et 17) → 17
  (let ((cpu (run-asm "
    .org $0200
    LDA #42
    CMP #17
    BCC done
    LDA #17
done:
    BRK")))
    (check "min(42, 17) = 17" (= 17 (A cpu))))

  ;; 6. Addition BCD : $39 + $48 = $87
  (let ((cpu (run-asm "
    .org $0200
    SED
    LDA #$39
    CLC
    ADC #$48
    CLD
    BRK")))
    (check "BCD $39 + $48 = $87" (= #x87 (A cpu))))

  ;; 7. Valeur absolue de -5 ($FB) → 5
  (let ((cpu (run-asm "
    .org $0200
    LDA #$FB
    BPL done
    EOR #$FF
    SEC
    ADC #$00
done:
    BRK")))
    (check "abs(-5) = 5" (= 5 (A cpu))))

  ;; 8. AND : $F0 & $3C = $30
  (let ((cpu (run-asm "
    .org $0200
    LDA #$F0
    AND #$3C
    BRK")))
    (check "AND $F0 & $3C = $30" (= #x30 (A cpu))))

  ;; 9. ORA : $F0 | $0F = $FF
  (let ((cpu (run-asm "
    .org $0200
    LDA #$F0
    ORA #$0F
    BRK")))
    (check "ORA $F0 | $0F = $FF" (= #xFF (A cpu))))

  ;; 10. EOR : $AA ^ $55 = $FF
  (let ((cpu (run-asm "
    .org $0200
    LDA #$AA
    EOR #$55
    BRK")))
    (check "EOR $AA ^ $55 = $FF" (= #xFF (A cpu))))

  ;; 11. ASL × 4 : $01 << 4 = $10
  (let ((cpu (run-asm "
    .org $0200
    LDA #$01
    ASL A
    ASL A
    ASL A
    ASL A
    BRK")))
    (check "ASL x4 : $01 → $10" (= #x10 (A cpu))))

  ;; 12. ROL avec carry entrant : $80, C=1 → A=$01, C=1 sortant
  (let ((cpu (run-asm "
    .org $0200
    LDA #$80
    SEC
    ROL A
    BRK")))
    (check "ROL $80 + C=1 → A=$01"    (= #x01 (A cpu)))
    (check "ROL $80 + C=1 → C=1 sorti" (flag-set-p cpu +flag-c+)))

  ;; 13. Débordement carry : $FF + 1 → A=0, C=1, Z=1
  (let ((cpu (run-asm "
    .org $0200
    LDA #$FF
    CLC
    ADC #$01
    BRK")))
    (check "carry : $FF+1 → A=0"  (= 0 (A cpu)))
    (check "carry : $FF+1 → C=1"  (flag-set-p cpu +flag-c+))
    (check "carry : $FF+1 → Z=1"  (flag-set-p cpu +flag-z+)))

  ;; 14. Overflow signe : $40 + $40 = $80 → V=1
  (let ((cpu (run-asm "
    .org $0200
    LDA #$40
    CLC
    ADC #$40
    BRK")))
    (check "overflow $40+$40 → V=1" (flag-set-p cpu +flag-v+)))

  ;; 15. Flag N : LDA #$80 → N=1
  (let ((cpu (run-asm "
    .org $0200
    LDA #$80
    BRK")))
    (check "LDA #$80 → N=1" (flag-set-p cpu +flag-n+))))


;;; --------------------------------------------------------------------------
;;;  test/prog-memory
;;; --------------------------------------------------------------------------

(deftest test/prog-memory

  ;; 16. Page zéro : écriture puis lecture
  (let ((cpu (run-asm "
    .org $0200
    LDA #$42
    STA $00
    LDA #$00
    LDA $00
    BRK")))
    (check "ZP write/read $42" (= #x42 (A cpu))))

  ;; 17. Absolu : écriture à $0300 puis lecture
  (let ((cpu (run-asm "
    .org $0200
    LDA #$AB
    STA $0300
    LDA #$00
    LDA $0300
    BRK")))
    (check "ABS write/read $AB at $0300" (= #xAB (A cpu))))

  ;; 18. ZP,X : tableau[2] = $33
  (let ((cpu (run-asm "
    .org $0200
    LDA #$11
    STA $00
    LDA #$22
    STA $01
    LDA #$33
    STA $02
    LDX #$02
    LDA $00,X
    BRK")))
    (check "LDA zp,X : tableau[2] = $33" (= #x33 (A cpu))))

  ;; 19. ABS,X : $0302 = $77
  (let ((cpu (run-asm "
    .org $0200
    LDA #$77
    STA $0302
    LDX #$02
    LDA $0300,X
    BRK")))
    (check "LDA abs,X : $0300[2] = $77" (= #x77 (A cpu))))

  ;; 20. ABS,Y : $0303 = $88
  (let ((cpu (run-asm "
    .org $0200
    LDA #$88
    STA $0303
    LDY #$03
    LDA $0300,Y
    BRK")))
    (check "LDA abs,Y : $0300[3] = $88" (= #x88 (A cpu))))

  ;; 21. ZP,Y (LDX zp,Y) : ZP[3] = $99
  (let ((cpu (run-asm "
    .org $0200
    LDA #$99
    STA $03
    LDY #$03
    LDX $00,Y
    BRK")))
    (check "LDX zp,Y : ZP[3] = $99" (= #x99 (X cpu))))

  ;; 22. (ind,X) écriture via pointeur ZP : $0300 ← $CD
  (let ((cpu (run-asm "
    .org $0200
    LDA #$00
    STA $10
    LDA #$03
    STA $11
    LDA #$CD
    LDX #$00
    STA ($10,X)
    BRK")))
    (check "(ind,X) write $CD at $0300" (= #xCD (M cpu #x0300))))

  ;; 23. (ind,X) lecture via pointeur ZP : $0300 = $EF
  (let ((cpu (run-asm "
    .org $0200
    LDA #$EF
    STA $0300
    LDA #$00
    STA $10
    LDA #$03
    STA $11
    LDX #$00
    LDA ($10,X)
    BRK")))
    (check "(ind,X) read $EF from $0300" (= #xEF (A cpu))))

  ;; 24. (ind),Y lecture avec Y=5 : $0305 = $AB
  (let ((cpu (run-asm "
    .org $0200
    LDA #$AB
    STA $0305
    LDA #$00
    STA $20
    LDA #$03
    STA $21
    LDY #$05
    LDA ($20),Y
    BRK")))
    (check "(ind),Y read $AB from $0305" (= #xAB (A cpu))))

  ;; 25. (ind),Y écriture avec Y=3 : $0303 ← $BA
  (let ((cpu (run-asm "
    .org $0200
    LDA #$00
    STA $20
    LDA #$03
    STA $21
    LDA #$BA
    LDY #$03
    STA ($20),Y
    BRK")))
    (check "(ind),Y write $BA at $0303" (= #xBA (M cpu #x0303))))

  ;; 26. STX / LDX absolu
  (let ((cpu (run-asm "
    .org $0200
    LDX #$55
    STX $0400
    LDX #$00
    LDX $0400
    BRK")))
    (check "STX/LDX abs : X = $55" (= #x55 (X cpu))))

  ;; 27. STY / LDY absolu
  (let ((cpu (run-asm "
    .org $0200
    LDY #$66
    STY $0400
    LDY #$00
    LDY $0400
    BRK")))
    (check "STY/LDY abs : Y = $66" (= #x66 (Y cpu)))))


;;; --------------------------------------------------------------------------
;;;  test/prog-subroutines
;;; --------------------------------------------------------------------------

(deftest test/prog-subroutines

  ;; 28. JSR/RTS simple : DOUBLE(n) = 2n via ASL
  (let ((cpu (run-asm "
    .org $0200
    LDA #$0A
    JSR DOUBLE
    BRK
DOUBLE:
    ASL A
    RTS")))
    (check "JSR DOUBLE(10) = 20" (= 20 (A cpu))))

  ;; 29. JSR/RTS : SQUARE(7) = 49
  (let ((cpu (run-asm "
    .org $0200
    LDA #$07
    JSR SQUARE
    BRK
SQUARE:
    STA $F0
    TAX
    LDA #$00
sq:
    CLC
    ADC $F0
    DEX
    BNE sq
    RTS")))
    (check "JSR SQUARE(7) = 49" (= 49 (A cpu))))

  ;; 30. JSR imbriqués : double(double(3)) = 12
  (let ((cpu (run-asm "
    .org $0200
    LDA #$03
    JSR DOUBLE
    JSR DOUBLE
    BRK
DOUBLE:
    ASL A
    RTS")))
    (check "double(double(3)) = 12" (= 12 (A cpu))))

  ;; 31. Discipline de pile : A_sub appelle B_sub, résultat = $AA
  (let ((cpu (run-asm "
    .org $0200
    JSR A_sub
    BRK
A_sub:
    JSR B_sub
    LDA #$AA
    RTS
B_sub:
    LDA #$BB
    RTS")))
    (check "pile A_sub/B_sub → A = $AA" (= #xAA (A cpu))))

  ;; 32. JSR avec paramètres via page zéro : add(5, 3) = 8
  (let ((cpu (run-asm "
    .org $0200
    LDA #$05
    STA $00
    LDA #$03
    STA $01
    JSR ADD_ZP
    LDA $02
    BRK
ADD_ZP:
    LDA $00
    CLC
    ADC $01
    STA $02
    RTS")))
    (check "JSR add_zp(5,3) → $02 = 8" (= 8 (A cpu))))

  ;; 33. Plusieurs JSR successifs : INC_A × 3 → A = 3
  (let ((cpu (run-asm "
    .org $0200
    LDA #$00
    JSR INC_A
    JSR INC_A
    JSR INC_A
    BRK
INC_A:
    CLC
    ADC #$01
    RTS")))
    (check "JSR INC_A x3 → A = 3" (= 3 (A cpu))))

  ;; 34. JMP saute une instruction, puis JSR
  (let ((cpu (run-asm "
    .org $0200
    LDA #$01
    JMP skip
    LDA #$FF
skip:
    JSR DOUBLE
    BRK
DOUBLE:
    ASL A
    RTS")))
    (check "JMP + JSR : A = 2" (= 2 (A cpu))))

  ;; 35. PHP/PLP restaure le carry à travers des instructions
  (let ((cpu (run-asm "
    .org $0200
    SEC
    PHP
    CLC
    PLP
    LDA #$00
    ADC #$00
    BRK")))
    (check "PHP/PLP restaure carry : A = 1" (= 1 (A cpu))))

  ;; 36. PHA/PLA préserve A
  (let ((cpu (run-asm "
    .org $0200
    LDA #$42
    PHA
    LDA #$00
    PLA
    BRK")))
    (check "PHA/PLA : A = $42" (= #x42 (A cpu))))

  ;; 37. BNE loop : X = 5 en sortie
  (let ((cpu (run-asm "
    .org $0200
    LDA #$00
    LDX #$00
loop:
    INX
    CPX #$05
    BNE loop
    BRK")))
    (check "BNE loop : X = 5" (= 5 (X cpu)))))


;;; --------------------------------------------------------------------------
;;;  test/prog-algorithms
;;; --------------------------------------------------------------------------

(deftest test/prog-algorithms

  ;; 38. Fibonacci F[0..9] en page zéro
  (let ((cpu (run-asm "
    .org $0200
    LDA #$00
    STA $00
    LDA #$01
    STA $01
    LDX #$00
fib:
    LDA $00,X
    CLC
    ADC $01,X
    STA $02,X
    INX
    CPX #$08
    BNE fib
    BRK")))
    (check "Fibonacci F[6] = 8"  (= 8  (M cpu 6)))
    (check "Fibonacci F[7] = 13" (= 13 (M cpu 7)))
    (check "Fibonacci F[9] = 34" (= 34 (M cpu 9))))

  ;; 39. Somme des puissances de 2 [1..128] = 255
  (let ((cpu (run-asm "
    .org $0200
    LDA #$00
    LDX #$07
loop:
    CLC
    ADC table,X
    DEX
    BPL loop
    BRK
table:
    .byte 1, 2, 4, 8, 16, 32, 64, 128")))
    (check "somme puissances de 2 = 255" (= 255 (A cpu))))

  ;; 40. Maximum dans un tableau de 8 octets → $FF
  (let ((cpu (run-asm "
    .org $0200
    LDA #$00
    LDX #$07
loop:
    CMP table,X
    BCS next
    LDA table,X
next:
    DEX
    BPL loop
    BRK
table:
    .byte $12, $45, $08, $FF, $33, $67, $01, $AA")))
    (check "max tableau 8 octets = $FF" (= #xFF (A cpu))))

  ;; 41. Compter les octets >= $80 dans un tableau → 4
  (let ((cpu (run-asm "
    .org $0200
    LDA #$00
    LDX #$07
loop:
    LDY table,X
    CPY #$80
    BCC next
    CLC
    ADC #$01
next:
    DEX
    BPL loop
    BRK
table:
    .byte $00, $80, $FF, $7F, $40, $C0, $01, $90")))
    (check "count bytes >= $80 = 4" (= 4 (A cpu))))

  ;; 42. Copie de tableau ZP : $10..$13 → $20..$23
  (let ((cpu (run-asm "
    .org $0200
    LDA #$AA
    STA $10
    LDA #$BB
    STA $11
    LDA #$CC
    STA $12
    LDA #$DD
    STA $13
    LDX #$03
copy:
    LDA $10,X
    STA $20,X
    DEX
    BPL copy
    BRK")))
    (check "copie ZP $20 = $AA" (= #xAA (M cpu #x20)))
    (check "copie ZP $21 = $BB" (= #xBB (M cpu #x21)))
    (check "copie ZP $22 = $CC" (= #xCC (M cpu #x22)))
    (check "copie ZP $23 = $DD" (= #xDD (M cpu #x23))))

  ;; 43. Remplissage : 8 octets à $10..$17 avec $AA
  (let ((cpu (run-asm "
    .org $0200
    LDA #$AA
    LDX #$07
fill:
    STA $10,X
    DEX
    BPL fill
    BRK")))
    (check "fill ZP $10..$17 = $AA (8/8)"
           (= 8 (loop for i from #x10 to #x17 count (= #xAA (M cpu i))))))

  ;; 44. Inversion de tableau : [$04 $03 $02 $01] → [$01 $02 $03 $04]
  (let ((cpu (run-asm "
    .org $0200
    LDA #$04
    STA $10
    LDA #$03
    STA $11
    LDA #$02
    STA $12
    LDA #$01
    STA $13
    LDA $10
    STA $F0
    LDA $13
    STA $10
    LDA $F0
    STA $13
    LDA $11
    STA $F0
    LDA $12
    STA $11
    LDA $F0
    STA $12
    BRK")))
    (check "inversion $10 = $01" (= 1 (M cpu #x10)))
    (check "inversion $11 = $02" (= 2 (M cpu #x11)))
    (check "inversion $12 = $03" (= 3 (M cpu #x12)))
    (check "inversion $13 = $04" (= 4 (M cpu #x13))))

  ;; 45. INC/DEC mémoire
  (let ((cpu (run-asm "
    .org $0200
    LDA #$00
    STA $00
    LDA #$05
    STA $01
    INC $00
    DEC $01
    BRK")))
    (check "INC $00 : 0 → 1" (= 1 (M cpu #x00)))
    (check "DEC $01 : 5 → 4" (= 4 (M cpu #x01))))

  ;; 46. BIT : N et V copiés depuis mémoire
  (let ((cpu (run-asm "
    .org $0200
    LDA #$C0
    STA $00
    LDA #$FF
    BIT $00
    BRK")))
    (check "BIT $C0 → N=1" (flag-set-p cpu +flag-n+))
    (check "BIT $C0 → V=1" (flag-set-p cpu +flag-v+))
    (check "BIT $FF AND $C0 != 0 → Z=0" (not (flag-set-p cpu +flag-z+))))

  ;; 47. LSR accumulator : $80 >> 1 = $40, C=0
  (let ((cpu (run-asm "
    .org $0200
    LDA #$80
    LSR A
    BRK")))
    (check "LSR $80 = $40"   (= #x40 (A cpu)))
    (check "LSR $80 → C=0"   (not (flag-set-p cpu +flag-c+))))

  ;; 48. DEC mémoire absolue : $0300 = 0 → 255 (wrap-around)
  (let ((cpu (run-asm "
    .org $0200
    LDA #$00
    STA $0300
    DEC $0300
    BRK")))
    (check "DEC $0300 : 0 → 255" (= 255 (M cpu #x0300)))))


;;; --------------------------------------------------------------------------
;;;  test/prog-lasm
;;; --------------------------------------------------------------------------

(deftest test/prog-lasm

  ;; 49. Multiplication 5 × 6 = 30
  (let ((cpu (run-lasm "
(org #x0200)
(lda :imm 0)
(ldx :imm 6)
(label 'loop)
(clc)
(adc :imm 5)
(dex)
(bne 'loop)
(brk)")))
    (check "lasm : 5 x 6 = 30" (= 30 (A cpu))))

  ;; 50. Fibonacci F[9] = 34
  (let ((cpu (run-lasm "
(org #x0200)
(lda :imm 0) (sta :zp #x00)
(lda :imm 1) (sta :zp #x01)
(ldx :imm 0)
(label 'fib)
(lda :x #x00) (clc) (adc :x #x01) (sta :x #x02)
(inx) (cpx :imm 8) (bne 'fib)
(brk)")))
    (check "lasm : Fibonacci F[9] = 34" (= 34 (M cpu 9))))

  ;; 51. dotimes générant une table, somme = 255
  (let ((cpu (run-lasm "
(defparameter *n* 8)
(org #x0200)
(lda :imm 0)
(ldx :imm (1- *n*))
(label 'sum-loop)
(clc)
(adc :x 'table)
(dex)
(bpl 'sum-loop)
(sta :zp #x00)
(brk)
(label 'table)
(dotimes (i *n*) (db (expt 2 i)))")))
    (check "lasm dotimes : somme 2^i = 255" (= 255 (A cpu)))
    (check "lasm dotimes : mem[$00] = 255"  (= 255 (M cpu 0))))

  ;; 52. JSR/RTS en lasm : SQUARE(5) = 25
  (let ((cpu (run-lasm "
(org #x0200)
(lda :imm 5)
(jsr 'square)
(brk)
(label 'square)
  (sta :zp #xF0)
  (tax)
  (lda :imm 0)
  (label 'sq)
  (clc) (adc :zp #xF0) (dex) (bne 'sq)
  (rts)")))
    (check "lasm : SQUARE(5) = 25" (= 25 (A cpu))))

  ;; 53. defparameter comme constante adresse
  (let ((cpu (run-lasm "
(defparameter *port* #x0300)
(org #x0200)
(lda :imm #x55)
(sta *port*)
(lda :imm 0)
(lda *port*)
(brk)")))
    (check "lasm : defparameter adresse → A = $55" (= #x55 (A cpu))))

  ;; 54. defun comme macro d'assemblage : fill-n émet N octets
  (let ((cpu (run-lasm "
(org #x0200)
(defun fill-n (val n) (dotimes (i n) (db val)))
(lda :imm 0)
(ldx :imm 7)
(label 'loop)
(clc) (adc :x 'tbl) (dex) (bpl 'loop)
(brk)
(label 'tbl)
(fill-n 10 8)")))
    (check "lasm : defun macro, somme 8×10 = 80" (= 80 (A cpu))))

  ;; 55. let Lisp calcule une adresse à l'assemblage
  (let ((cpu (run-lasm "
(org #x0200)
(let ((addr (+ #x0300 7)))
  (lda :imm #xAB)
  (sta addr))
(lda :imm 0)
(lda #x0307)
(brk)")))
    (check "lasm : let calcule adresse → $0307 = $AB" (= #xAB (A cpu))))

  ;; 56. dotimes émet N instructions ADC
  (let ((cpu (run-lasm "
(org #x0200)
(lda :imm 0)
(dotimes (i 5) (clc) (adc :imm 3))
(brk)")))
    (check "lasm : dotimes 5 × ADC #3 → A = 15" (= 15 (A cpu))))

  ;; 57. run-lasm et run-asm donnent le même résultat pour le même programme
  (let* ((r-asm  (A (run-asm  "
    .org $0200
    LDA #$00
    LDX #$05
lp:
    CLC
    ADC #$02
    DEX
    BNE lp
    BRK")))
         (r-lasm (A (run-lasm "
(org #x0200)
(lda :imm 0) (ldx :imm 5)
(label 'lp) (clc) (adc :imm 2) (dex) (bne 'lp)
(brk)"))))
    (check "asm == lasm : 5×2 = 10" (= r-asm r-lasm 10))))


;;; --------------------------------------------------------------------------
;;;  Point d'entrée
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (test/prog-arithmetic)
  (test/prog-memory)
  (test/prog-subroutines)
  (test/prog-algorithms)
  (test/prog-lasm))
