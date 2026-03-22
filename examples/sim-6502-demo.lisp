; -*- coding: utf-8 -*-
;;; examples/sim-6502-demo.lisp
;;;
;;; Démonstration du simulateur 6502 — trois exemples progressifs.
;;;
;;; Prérequis : système cl-asm chargé via ASDF/Quicklisp.
;;;
;;; Usage depuis la racine du projet :
;;;   sbcl --eval '(asdf:load-system "cl-asm")' \
;;;        --load examples/sim-6502-demo.lisp --quit
;;;
;;; Ou depuis le REPL (SBCL, SLIME, SLY…) :
;;;   (asdf:load-system "cl-asm")
;;;   (load "examples/sim-6502-demo.lisp")

(defpackage #:cl-asm/demo.sim6502
  (:use #:cl))

(in-package #:cl-asm/demo.sim6502)

;;; --------------------------------------------------------------------------
;;;  Helpers
;;; --------------------------------------------------------------------------

(defun run-prog (source origin)
  "Assemble SOURCE (syntaxe classique), charge à ORIGIN, exécute jusqu'au BRK.
Retourne le struct CPU final."
  (let* ((bytes (cl-asm/backend.6502:assemble-string source))
         (cpu   (cl-asm/simulator.6502:make-cpu))
         (cpu   (cl-asm/simulator.6502:load-program cpu bytes :origin origin)))
    ;; run-cpu capture cpu-break et cpu-step-limit en interne ;
    ;; il retourne (values cpu raison) où raison est :brk ou :step-limit.
    (nth-value 0 (cl-asm/simulator.6502:run-cpu cpu))))

(defun print-regs (cpu)
  "Affiche l'état des registres sur une ligne."
  (format t "  A=$~2,'0X  X=$~2,'0X  Y=$~2,'0X  SP=$~2,'0X  cycles=~D~%"
          (cl-asm/simulator.6502:cpu-a      cpu)
          (cl-asm/simulator.6502:cpu-x      cpu)
          (cl-asm/simulator.6502:cpu-y      cpu)
          (cl-asm/simulator.6502:cpu-sp     cpu)
          (cl-asm/simulator.6502:cpu-cycles cpu)))

(defun print-mem (cpu start count)
  "Affiche COUNT octets consécutifs depuis l'adresse START."
  (format t "  [$~4,'0X]" start)
  (dotimes (i count)
    (format t " ~2,'0X" (cl-asm/simulator.6502:mem-read cpu (+ start i))))
  (terpri))

;;; --------------------------------------------------------------------------
;;;  Demo 1 — Multiplication par additions répétées : 5 × 6 = 30 ($1E)
;;; --------------------------------------------------------------------------
;;;
;;;  Algorithme :
;;;    A = 0 ; X = 6
;;;    répéter 6 fois : A += 5
;;;    → A = 30 = $1E
;;;
;;;  Instructions démontrées : LDA, LDX, CLC, ADC, DEX, BNE, BRK

(format t "~%=== Demo 1 : 5 x 6 = 30 (additions repetees) ===~%")

(let ((cpu (run-prog "
    .org $0300
    LDA #$00        ; accumulateur = 0
    LDX #$06        ; compteur = 6
loop:
    CLC
    ADC #$05        ; A += 5
    DEX
    BNE loop        ; repeter 6 fois
    BRK
" #x0300)))
  (print-regs cpu)
  (format t "  => A = ~D  (attendu : 30 = $1E)~%"
          (cl-asm/simulator.6502:cpu-a cpu)))

;;; --------------------------------------------------------------------------
;;;  Demo 2 — Suite de Fibonacci : F[0..9] en page zéro ($00–$09)
;;; --------------------------------------------------------------------------
;;;
;;;  Algorithme (adressage zéro-page indexé) :
;;;    $00 = F[0] = 0 ;  $01 = F[1] = 1
;;;    pour X = 0..7 : $02+X = ($00+X) + ($01+X)   → F[i] = F[i-2] + F[i-1]
;;;
;;;  Résultat attendu : 0 1 1 2 3 5 8 13 21 34 ($00 $01 $01 $02 $03 $05 $08 $0D $15 $22)
;;;
;;;  Instructions démontrées : STA zp, LDA zp,X, ADC zp,X, INX, CPX, BNE

(format t "~%=== Demo 2 : suite de Fibonacci F[0..9] en page zero ===~%")

(let ((cpu (run-prog "
    .org $0300
    LDA #$00
    STA $00         ; F[0] = 0
    LDA #$01
    STA $01         ; F[1] = 1
    LDX #$00        ; X = offset courant (0-base)
fib:
    LDA $00,X       ; A = F[i-2]
    CLC
    ADC $01,X       ; A += F[i-1]
    STA $02,X       ; F[i] = A
    INX
    CPX #$08        ; 8 iterations : calcule F[2]..F[9]
    BNE fib
    BRK
" #x0300)))
  (print-regs cpu)
  (format t "  mem $00..$09 :")
  (dotimes (i 10)
    (format t " ~2,'0X" (cl-asm/simulator.6502:mem-read cpu i)))
  (terpri)
  (format t "  attendu    : 00 01 01 02 03 05 08 0D 15 22~%"))

;;; --------------------------------------------------------------------------
;;;  Demo 3 — Sous-programme JSR/RTS : carré d'un entier — SQUARE(7) = 49
;;; --------------------------------------------------------------------------
;;;
;;;  Algorithme :
;;;    SQUARE(n) : résultat = 0 ; répéter n fois : résultat += n → A = n²
;;;
;;;    main :  LDA #7  →  JSR SQUARE  →  A = 49 = $31
;;;
;;;  Instructions démontrées : JSR, RTS, STA zp (sauvegarde temp), TAX

(format t "~%=== Demo 3 : sous-programme SQUARE(7) = 49 ===~%")

(let ((cpu (run-prog "
    .org $0300
    LDA #$07        ; argument : n = 7
    JSR SQUARE      ; appel sous-programme
    BRK             ; A = 49 = $31 a ce stade

SQUARE:             ; entree : A = n   sortie : A = n*n   clobbers : X, $F0
    STA $F0         ; sauver n en page zero ($F0 = zone temporaire)
    TAX             ; X = n (compteur de boucle)
    LDA #$00        ; accumulateur resultat = 0
sq_loop:
    CLC
    ADC $F0         ; A += n
    DEX
    BNE sq_loop
    RTS
" #x0300)))
  (print-regs cpu)
  (format t "  => A = ~D  (attendu : 49 = $31)~%"
          (cl-asm/simulator.6502:cpu-a cpu)))

(format t "~%Fin de la demonstration.~%")
