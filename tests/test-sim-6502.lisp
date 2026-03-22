; -*- coding: utf-8 -*-
;;; tests/test-sim-6502.lisp
;;;
;;; Tests unitaires — simulateur 6502, étape 1.
;;; Périmètre : infrastructure + 23 instructions implicites.

(defpackage #:cl-asm/test.sim-6502
  (:use #:cl #:cl-asm/simulator.6502)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.sim-6502)


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

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&--- ~A ---~%" ',name)
     ,@body))

;;; Exécute N octets dans un CPU frais, retourne le CPU après BRK.
(defun run-bytes (bytes &key (origin 0))
  (let* ((cpu    (make-cpu))
         (full   (concatenate 'vector bytes #(#x00)))  ; ajoute BRK final
         (loaded (load-program cpu full :origin origin)))
    (run-cpu loaded)))

;;; Exécute un seul opcode (step-cpu) et retourne le CPU.
;;; Les cycles reflètent uniquement cette instruction (pas de BRK terminal).
(defun run1 (opcode &key (a 0) (x 0) (y 0) (sp #xFF) (p #x24))
  (let* ((cpu (make-cpu))
         (prg (vector opcode #x00)))
    (setf (cpu-a cpu) a (cpu-x cpu) x (cpu-y cpu) y
          (cpu-sp cpu) sp (cpu-p cpu) p)
    (load-program cpu prg :origin 0)
    (handler-case (step-cpu cpu)
      (cpu-break ()))   ; BRK est rattrapé silencieusement
    cpu))


;;; --------------------------------------------------------------------------
;;;  Tests : make-cpu / reset-cpu
;;; --------------------------------------------------------------------------

(deftest test/make-cpu
  (let ((cpu (make-cpu)))
    (check "make-cpu : A = 0"    (= 0    (cpu-a  cpu)))
    (check "make-cpu : X = 0"    (= 0    (cpu-x  cpu)))
    (check "make-cpu : Y = 0"    (= 0    (cpu-y  cpu)))
    (check "make-cpu : PC = 0"   (= 0    (cpu-pc cpu)))
    (check "make-cpu : SP = $FF" (= #xFF (cpu-sp cpu)))
    (check "make-cpu : P = $24"  (= #x24 (cpu-p  cpu)))
    (check "make-cpu : cycles=0" (= 0    (cpu-cycles cpu)))
    (check "make-cpu : mem 64KB" (= 65536 (length (cpu-mem cpu))))
    (check "make-cpu : mem = 0"  (every #'zerop (cpu-mem cpu)))))

(deftest test/reset-cpu
  (let ((cpu (make-cpu)))
    (setf (cpu-a cpu) 42 (cpu-x cpu) 7 (cpu-cycles cpu) 999)
    (reset-cpu cpu :origin #x0200)
    (check "reset-cpu : A = 0"         (= 0      (cpu-a      cpu)))
    (check "reset-cpu : X = 0"         (= 0      (cpu-x      cpu)))
    (check "reset-cpu : PC = origin"   (= #x0200 (cpu-pc     cpu)))
    (check "reset-cpu : SP = $FF"      (= #xFF   (cpu-sp     cpu)))
    (check "reset-cpu : P = $24"       (= #x24   (cpu-p      cpu)))
    (check "reset-cpu : cycles = 0"    (= 0      (cpu-cycles cpu)))))


;;; --------------------------------------------------------------------------
;;;  Tests : mémoire
;;; --------------------------------------------------------------------------

(deftest test/memory
  (let ((cpu (make-cpu)))
    (mem-write cpu #x0200 #xAB)
    (check "mem-write / mem-read"       (= #xAB (mem-read cpu #x0200)))
    (check "mem-read zone non écrite"   (= 0    (mem-read cpu #x0300)))
    (mem-write cpu #x0300 #x34)
    (mem-write cpu #x0301 #x12)
    (check "mem-read16 little-endian"   (= #x1234 (mem-read16 cpu #x0300)))
    (check "mem-write masque 8 bits"    (progn (mem-write cpu 0 #x1FF) (= #xFF (mem-read cpu 0))))
    (check "mem-read wrapping $FFFF"    (progn (mem-write cpu #xFFFF #x77)
                                               (= #x77 (mem-read cpu #xFFFF))))))


;;; --------------------------------------------------------------------------
;;;  Tests : load-program
;;; --------------------------------------------------------------------------

(deftest test/load-program
  (let ((cpu (make-cpu)))
    (load-program cpu #(#xEA #x00) :origin #x0300)
    (check "load-program : PC = origin"  (= #x0300 (cpu-pc cpu)))
    (check "load-program : octet 0"      (= #xEA   (mem-read cpu #x0300)))
    (check "load-program : octet 1"      (= #x00   (mem-read cpu #x0301)))
    (check "load-program : avant = 0"    (= 0      (mem-read cpu #x02FF)))))


;;; --------------------------------------------------------------------------
;;;  Tests : helpers flags
;;; --------------------------------------------------------------------------

(deftest test/flags
  (let ((cpu (make-cpu)))
    ;; État initial : P = $24 = %00100100 → I=1, bit5=1
    (check "flag-i initial = T"  (flag-i cpu))
    (check "flag-c initial = F"  (not (flag-c cpu)))
    (check "flag-z initial = F"  (not (flag-z cpu)))
    (check "flag-n initial = F"  (not (flag-n cpu)))
    (check "flag-v initial = F"  (not (flag-v cpu)))
    (check "flag-d initial = F"  (not (flag-d cpu)))
    ;; set-flag
    (set-flag cpu +flag-c+ t)
    (check "set-flag C → 1"      (flag-c cpu))
    (set-flag cpu +flag-c+ nil)
    (check "set-flag C → 0"      (not (flag-c cpu)))
    ;; bit 5 toujours conservé
    (set-flag cpu #xFF nil)
    (check "set-flag : bit5 conservé" (logbitp 5 (cpu-p cpu)))
    ;; update-nz
    (update-nz cpu 0)
    (check "update-nz 0 → Z=T"   (flag-z cpu))
    (check "update-nz 0 → N=F"   (not (flag-n cpu)))
    (update-nz cpu #x80)
    (check "update-nz $80 → N=T" (flag-n cpu))
    (check "update-nz $80 → Z=F" (not (flag-z cpu)))
    (update-nz cpu #x01)
    (check "update-nz $01 → N=F" (not (flag-n cpu)))
    (check "update-nz $01 → Z=F" (not (flag-z cpu)))))


;;; --------------------------------------------------------------------------
;;;  Tests : pile
;;; --------------------------------------------------------------------------

(deftest test/stack
  (let ((cpu (make-cpu)))
    (setf (cpu-sp cpu) #xFF)
    (stack-push cpu #xAB)
    (check "stack-push : SP décrémenté"    (= #xFE (cpu-sp cpu)))
    (check "stack-push : valeur en $01FF"  (= #xAB (mem-read cpu #x01FF)))
    (let ((val (stack-pull cpu)))
      (check "stack-pull : valeur correcte" (= #xAB val))
      (check "stack-pull : SP incrémenté"   (= #xFF  (cpu-sp cpu))))
    ;; Wrapping SP
    (setf (cpu-sp cpu) #x00)
    (stack-push cpu #x55)
    (check "stack-push : SP wrap $FF"     (= #xFF (cpu-sp cpu)))
    (check "stack-push : valeur en $0100" (= #x55 (mem-read cpu #x0100)))))


;;; --------------------------------------------------------------------------
;;;  Tests : NOP et BRK
;;; --------------------------------------------------------------------------

(deftest test/nop-brk
  ;; NOP
  (let ((cpu (run1 #xEA)))
    (check "NOP : cycles = 2"   (= 2 (cpu-cycles cpu)))
    (check "NOP : PC avancé"    (= 1 (cpu-pc cpu))))    ; NOP = 1 octet
  ;; BRK
  (let ((cpu (run1 #x00)))
    (check "BRK : flag B mis"   (flag-b cpu))
    (check "BRK : cycles = 7"   (= 7 (cpu-cycles cpu))))
  ;; run-cpu retourne :brk
  (let ((cpu (make-cpu)))
    (load-program cpu #(#x00) :origin 0)
    (multiple-value-bind (c reason) (run-cpu cpu)
      (declare (ignore c))
      (check "run-cpu retourne :brk" (eq :brk reason))))
  ;; Opcode illégal → erreur
  (let ((cpu (make-cpu)))
    (load-program cpu #(#xFF) :origin 0)
    (check "opcode illégal → erreur"
           (handler-case (progn (step-cpu cpu) nil)
             (cpu-illegal-opcode () t)))))


;;; --------------------------------------------------------------------------
;;;  Tests : transferts de registres
;;; --------------------------------------------------------------------------

(deftest test/transfers
  ;; TAX
  (let ((cpu (run1 #xAA :a #x42)))
    (check "TAX : X = A"     (= #x42 (cpu-x cpu)))
    (check "TAX : cycles = 2" (= 2 (cpu-cycles cpu))))
  (let ((cpu (run1 #xAA :a 0)))
    (check "TAX : Z mis si A=0" (flag-z cpu)))
  (let ((cpu (run1 #xAA :a #x80)))
    (check "TAX : N mis si A=$80" (flag-n cpu)))
  ;; TXA
  (let ((cpu (run1 #x8A :x #x37)))
    (check "TXA : A = X"     (= #x37 (cpu-a cpu))))
  ;; TAY
  (let ((cpu (run1 #xA8 :a #x55)))
    (check "TAY : Y = A"     (= #x55 (cpu-y cpu))))
  ;; TYA
  (let ((cpu (run1 #x98 :y #x12)))
    (check "TYA : A = Y"     (= #x12 (cpu-a cpu))))
  ;; TSX
  (let ((cpu (run1 #xBA :sp #xF0)))
    (check "TSX : X = SP"    (= #xF0 (cpu-x cpu))))
  ;; TXS — ne met pas à jour N/Z
  (let ((cpu (run1 #x9A :x #xC0)))
    (check "TXS : SP = X"    (= #xC0 (cpu-sp cpu)))
    (check "TXS : Z non mis" (not (flag-z cpu)))
    (check "TXS : N non mis" (not (flag-n cpu)))))


;;; --------------------------------------------------------------------------
;;;  Tests : PHA / PLA / PHP / PLP
;;; --------------------------------------------------------------------------

(deftest test/stack-instructions
  ;; PHA
  (let ((cpu (run1 #x48 :a #xBE :sp #xFF)))
    (check "PHA : A empilé"    (= #xBE (mem-read cpu #x01FF)))
    (check "PHA : SP--"        (= #xFE (cpu-sp cpu)))
    (check "PHA : cycles = 3"  (= 3 (cpu-cycles cpu))))
  ;; PLA
  (let ((cpu (run-bytes #(#x48 #x68) :origin 0)))   ; PHA + PLA + BRK
    (check "PLA : cycles cumulés" (= 14 (cpu-cycles cpu))))
  (let ((cpu (run1 #x68 :sp #xFE)))
    ;; La valeur à $01FF est 0 (mémoire non initialisée → 0)
    (check "PLA : A = valeur dépilée" (= 0 (cpu-a cpu)))
    (check "PLA : SP++"               (= #xFF (cpu-sp cpu)))
    (check "PLA : Z mis si 0"         (flag-z cpu))
    (check "PLA : cycles = 4"         (= 4 (cpu-cycles cpu))))
  ;; PHP — B forcé à 1 dans la valeur empilée
  ;; On utilise step-cpu pour mesurer les cycles sans le BRK terminal.
  (let ((cpu (make-cpu)))
    (setf (cpu-p cpu) #x20 (cpu-sp cpu) #xFF)
    (load-program cpu #(#x08 #x00) :origin 0)
    (step-cpu cpu)            ; PHP seulement
    (check "PHP : valeur empilée a B=1"
           (logbitp 4 (mem-read cpu #x01FF)))
    (check "PHP : cycles = 3" (= 3 (cpu-cycles cpu))))
  ;; PLP — restaure P, bit5 forcé
  ;; On utilise step-cpu directement pour tester P avant que BRK ne le modifie.
  (let ((cpu (make-cpu)))
    (setf (cpu-sp cpu) #xFF)
    (stack-push cpu #b11001111)   ; C Z I D V N tous à 1, B à 0
    (load-program cpu #(#x28 #x00) :origin 0)
    (step-cpu cpu)                ; PLP seulement
    (check "PLP : P restauré"      (= (logior #x20 #b11001111) (cpu-p cpu)))
    (check "PLP : bit5 toujours 1" (logbitp 5 (cpu-p cpu)))
    (check "PLP : cycles = 4"      (= 4 (cpu-cycles cpu)))))


;;; --------------------------------------------------------------------------
;;;  Tests : INX / INY / DEX / DEY
;;; --------------------------------------------------------------------------

(deftest test/inc-dec
  ;; INX
  (let ((cpu (run1 #xE8 :x 0)))
    (check "INX : X = 1"          (= 1 (cpu-x cpu)))
    (check "INX : Z = F"          (not (flag-z cpu))))
  (let ((cpu (run1 #xE8 :x #xFF)))
    (check "INX : wrap $FF → 0"   (= 0 (cpu-x cpu)))
    (check "INX : Z mis si wrap"  (flag-z cpu)))
  (let ((cpu (run1 #xE8 :x #x7F)))
    (check "INX : N mis si $80"   (flag-n cpu)))
  ;; INY
  (let ((cpu (run1 #xC8 :y 5)))
    (check "INY : Y = 6"          (= 6 (cpu-y cpu))))
  (let ((cpu (run1 #xC8 :y #xFF)))
    (check "INY : wrap $FF → 0"   (= 0 (cpu-y cpu))))
  ;; DEX
  (let ((cpu (run1 #xCA :x 1)))
    (check "DEX : X = 0"          (= 0 (cpu-x cpu)))
    (check "DEX : Z mis"          (flag-z cpu)))
  (let ((cpu (run1 #xCA :x 0)))
    (check "DEX : wrap 0 → $FF"   (= #xFF (cpu-x cpu)))
    (check "DEX : N mis si $FF"   (flag-n cpu)))
  ;; DEY
  (let ((cpu (run1 #x88 :y 10)))
    (check "DEY : Y = 9"          (= 9 (cpu-y cpu))))
  (let ((cpu (run1 #x88 :y 0)))
    (check "DEY : wrap 0 → $FF"   (= #xFF (cpu-y cpu)))))


;;; --------------------------------------------------------------------------
;;;  Tests : instructions de flags
;;; --------------------------------------------------------------------------

(deftest test/flag-instructions
  ;; CLC / SEC
  (let ((cpu (run1 #x18 :p #xFF)))
    (check "CLC : C = 0"  (not (flag-c cpu))))
  (let ((cpu (run1 #x38 :p #x00)))
    (check "SEC : C = 1"  (flag-c cpu)))
  ;; CLI / SEI
  (let ((cpu (run1 #x58 :p #xFF)))
    (check "CLI : I = 0"  (not (flag-i cpu))))
  (let ((cpu (run1 #x78 :p #x00)))
    (check "SEI : I = 1"  (flag-i cpu)))
  ;; CLV
  (let ((cpu (run1 #xB8 :p #xFF)))
    (check "CLV : V = 0"  (not (flag-v cpu))))
  ;; CLD / SED
  (let ((cpu (run1 #xD8 :p #xFF)))
    (check "CLD : D = 0"  (not (flag-d cpu))))
  (let ((cpu (run1 #xF8 :p #x00)))
    (check "SED : D = 1"  (flag-d cpu)))
  ;; Cycles
  (let ((cpu (run1 #x18)))
    (check "flag instr : cycles = 2" (= 2 (cpu-cycles cpu)))))


;;; --------------------------------------------------------------------------
;;;  Tests : run-cpu
;;; --------------------------------------------------------------------------

(deftest test/run-cpu
  ;; Séquence : TAX → INX → INX → BRK
  (let ((cpu (run-bytes #(#xAA #xE8 #xE8) :origin 0)))
    (check "séquence TAX INX INX : A=0→X=0→X=2"  (= 2 (cpu-x cpu))))
  ;; SEC → CLC → SEC
  (let ((cpu (run-bytes #(#x38 #x18 #x38) :origin 0)))
    (check "SEC CLC SEC : C = 1" (flag-c cpu)))
  ;; Limite de pas
  (let ((cpu (make-cpu)))
    ;; Boucle infinie : JMP $0000 = $4C $00 $00 — pas encore implémenté,
    ;; donc on teste juste la condition step-limit avec NOP répétés
    (load-program cpu (make-array 10 :initial-element #xEA) :origin 0)
    ;; Écrire BRK après les 10 NOP
    (mem-write cpu 10 #x00)
    (multiple-value-bind (c reason) (run-cpu cpu :max-steps 5)
      (declare (ignore c))
      (check "run-cpu :step-limit si max atteint" (eq :step-limit reason)))))


;;; --------------------------------------------------------------------------
;;;  Tests : load/store (LDA LDX LDY STA STX STY)
;;; --------------------------------------------------------------------------

;;; Helper : construit un CPU avec quelques octets pré-écrits en mémoire,
;;; exécute un programme depuis l'origine et retourne le CPU.
(defun run-with-mem (prog &key (origin #x0200) (mem-inits '()))
  "Exécute PROG (vecteur) depuis ORIGIN dans un CPU frais.
   MEM-INITS est une liste de (addr . val) pré-écrits avant l'exécution."
  (let ((cpu (make-cpu)))
    (dolist (m mem-inits)
      (mem-write cpu (car m) (cdr m)))
    (load-program cpu (concatenate 'vector prog #(#x00)) :origin origin)
    (run-cpu cpu)
    cpu))

(deftest test/load-store
  ;; --- LDA ---
  (let ((cpu (make-cpu)))
    (load-program cpu #(#xA9 #x42 #x00) :origin 0)  ; LDA #$42
    (step-cpu cpu)
    (check "LDA imm : A = $42"    (= #x42 (cpu-a cpu)))
    (check "LDA imm : cycles = 2" (= 2    (cpu-cycles cpu))))
  (let ((cpu (make-cpu)))
    (load-program cpu #(#xA9 #x00 #x00) :origin 0)  ; LDA #$00
    (step-cpu cpu)
    (check "LDA imm : Z mis si 0" (flag-z cpu))
    (check "LDA imm : N = 0"      (not (flag-n cpu))))
  (let ((cpu (make-cpu)))
    (load-program cpu #(#xA9 #x80 #x00) :origin 0)  ; LDA #$80
    (step-cpu cpu)
    (check "LDA imm : N mis si $80" (flag-n cpu)))

  (let ((cpu (make-cpu)))
    (mem-write cpu #x10 #xBE)
    (load-program cpu #(#xA5 #x10 #x00) :origin 0)  ; LDA $10
    (step-cpu cpu)
    (check "LDA zp : A = $BE"    (= #xBE (cpu-a cpu)))
    (check "LDA zp : cycles = 3" (= 3    (cpu-cycles cpu))))
  ;; LDA zp,X — test direct avec step-cpu
  (let ((cpu (make-cpu)))
    (mem-write cpu #x12 #xCD)
    (setf (cpu-x cpu) 2)
    (load-program cpu #(#xB5 #x10 #x00) :origin 0)
    (step-cpu cpu)
    (check "LDA zp,X : A = $CD"    (= #xCD (cpu-a cpu)))
    (check "LDA zp,X : cycles = 4" (= 4    (cpu-cycles cpu))))

  (let ((cpu (make-cpu)))                          ; LDA $0300
    (mem-write cpu #x0300 #x55)
    (load-program cpu #(#xAD #x00 #x03 #x00) :origin 0)
    (step-cpu cpu)
    (check "LDA abs : A = $55"    (= #x55 (cpu-a cpu)))
    (check "LDA abs : cycles = 4" (= 4    (cpu-cycles cpu))))

  ;; LDA abs,X — même page (4 cycles)
  (let ((cpu (make-cpu)))
    (mem-write cpu #x0302 #x77)
    (setf (cpu-x cpu) 2)
    (load-program cpu #(#xBD #x00 #x03 #x00) :origin 0)  ; LDA $0300,X
    (step-cpu cpu)
    (check "LDA abs,X même page : A = $77"    (= #x77 (cpu-a cpu)))
    (check "LDA abs,X même page : cycles = 4" (= 4    (cpu-cycles cpu))))

  ;; LDA abs,X — franchissement de page (5 cycles)
  (let ((cpu (make-cpu)))
    (mem-write cpu #x0100 #x99)
    (setf (cpu-x cpu) #x01)
    (load-program cpu #(#xBD #xFF #x00 #x00) :origin 0)  ; LDA $00FF,X → $0100
    (step-cpu cpu)
    (check "LDA abs,X cross-page : A = $99"    (= #x99 (cpu-a cpu)))
    (check "LDA abs,X cross-page : cycles = 5" (= 5    (cpu-cycles cpu))))

  ;; LDA abs,Y
  (let ((cpu (make-cpu)))
    (mem-write cpu #x0305 #xAA)
    (setf (cpu-y cpu) 5)
    (load-program cpu #(#xB9 #x00 #x03 #x00) :origin 0)  ; LDA $0300,Y
    (step-cpu cpu)
    (check "LDA abs,Y : A = $AA" (= #xAA (cpu-a cpu))))

  ;; LDA (ind,X)
  (let ((cpu (make-cpu)))
    (mem-write cpu #x24 #x00)  ; vecteur à $24/$25 = $0300
    (mem-write cpu #x25 #x03)
    (mem-write cpu #x0300 #xDE)
    (setf (cpu-x cpu) 4)
    (load-program cpu #(#xA1 #x20 #x00) :origin 0)  ; LDA ($20,X)
    (step-cpu cpu)
    (check "LDA (ind,X) : A = $DE"    (= #xDE (cpu-a cpu)))
    (check "LDA (ind,X) : cycles = 6" (= 6    (cpu-cycles cpu))))

  ;; LDA (ind),Y
  (let ((cpu (make-cpu)))
    (mem-write cpu #x30 #x00)  ; vecteur à $30/$31 = $0400
    (mem-write cpu #x31 #x04)
    (mem-write cpu #x0403 #xEF)
    (setf (cpu-y cpu) 3)
    (load-program cpu #(#xB1 #x30 #x00) :origin 0)  ; LDA ($30),Y
    (step-cpu cpu)
    (check "LDA (ind),Y : A = $EF"    (= #xEF (cpu-a cpu)))
    (check "LDA (ind),Y : cycles = 5" (= 5    (cpu-cycles cpu))))

  ;; --- LDX ---
  (let ((cpu (make-cpu)))
    (load-program cpu #(#xA2 #x37 #x00) :origin 0)  ; LDX #$37
    (step-cpu cpu)
    (check "LDX imm : X = $37"    (= #x37 (cpu-x cpu)))
    (check "LDX imm : cycles = 2" (= 2    (cpu-cycles cpu))))

  (let ((cpu (make-cpu)))
    (mem-write cpu #x20 #x11)
    (load-program cpu #(#xA6 #x20 #x00) :origin 0)  ; LDX $20
    (step-cpu cpu)
    (check "LDX zp : X = $11"    (= #x11 (cpu-x cpu)))
    (check "LDX zp : cycles = 3" (= 3    (cpu-cycles cpu))))

  (let ((cpu (make-cpu)))
    (mem-write cpu #x22 #x33)
    (setf (cpu-y cpu) 2)
    (load-program cpu #(#xB6 #x20 #x00) :origin 0)  ; LDX $20,Y
    (step-cpu cpu)
    (check "LDX zp,Y : X = $33"    (= #x33 (cpu-x cpu)))
    (check "LDX zp,Y : cycles = 4" (= 4    (cpu-cycles cpu))))

  (let ((cpu (make-cpu)))
    (mem-write cpu #x0400 #x66)
    (load-program cpu #(#xAE #x00 #x04 #x00) :origin 0)  ; LDX $0400
    (step-cpu cpu)
    (check "LDX abs : X = $66" (= #x66 (cpu-x cpu))))

  ;; --- LDY ---
  (let ((cpu (make-cpu)))
    (load-program cpu #(#xA0 #x0A #x00) :origin 0)  ; LDY #$0A
    (step-cpu cpu)
    (check "LDY imm : Y = $0A"    (= #x0A (cpu-y cpu)))
    (check "LDY imm : cycles = 2" (= 2    (cpu-cycles cpu))))

  (let ((cpu (make-cpu)))
    (mem-write cpu #x50 #x7F)
    (load-program cpu #(#xA4 #x50 #x00) :origin 0)  ; LDY $50
    (step-cpu cpu)
    (check "LDY zp : Y = $7F" (= #x7F (cpu-y cpu))))

  ;; --- STA ---
  (let ((cpu (make-cpu)))
    (setf (cpu-a cpu) #xAB)
    (load-program cpu #(#x85 #x40 #x00) :origin 0)  ; STA $40
    (step-cpu cpu)
    (check "STA zp : mem[$40] = $AB" (= #xAB (mem-read cpu #x40)))
    (check "STA zp : cycles = 3"     (= 3    (cpu-cycles cpu))))

  (let ((cpu (make-cpu)))
    (setf (cpu-a cpu) #xCD (cpu-x cpu) 1)
    (load-program cpu #(#x95 #x40 #x00) :origin 0)  ; STA $40,X
    (step-cpu cpu)
    (check "STA zp,X : mem[$41] = $CD" (= #xCD (mem-read cpu #x41)))
    (check "STA zp,X : cycles = 4"     (= 4    (cpu-cycles cpu))))

  (let ((cpu (make-cpu)))
    (setf (cpu-a cpu) #xEF)
    (load-program cpu #(#x8D #x00 #x05 #x00) :origin 0)  ; STA $0500
    (step-cpu cpu)
    (check "STA abs : mem[$0500] = $EF" (= #xEF (mem-read cpu #x0500)))
    (check "STA abs : cycles = 4"       (= 4    (cpu-cycles cpu))))

  (let ((cpu (make-cpu)))
    (setf (cpu-a cpu) #x12 (cpu-x cpu) 3)
    (load-program cpu #(#x9D #x00 #x05 #x00) :origin 0)  ; STA $0500,X
    (step-cpu cpu)
    (check "STA abs,X : mem[$0503] = $12" (= #x12 (mem-read cpu #x0503)))
    (check "STA abs,X : cycles = 5"       (= 5    (cpu-cycles cpu))))

  (let ((cpu (make-cpu)))
    (setf (cpu-a cpu) #x34 (cpu-y cpu) 2)
    (load-program cpu #(#x99 #x00 #x05 #x00) :origin 0)  ; STA $0500,Y
    (step-cpu cpu)
    (check "STA abs,Y : mem[$0502] = $34" (= #x34 (mem-read cpu #x0502)))
    (check "STA abs,Y : cycles = 5"       (= 5    (cpu-cycles cpu))))

  ;; STA (ind,X)
  (let ((cpu (make-cpu)))
    (mem-write cpu #x44 #x00)  ; vecteur $44/$45 = $0600
    (mem-write cpu #x45 #x06)
    (setf (cpu-a cpu) #x56 (cpu-x cpu) 4)
    (load-program cpu #(#x81 #x40 #x00) :origin 0)  ; STA ($40,X)
    (step-cpu cpu)
    (check "STA (ind,X) : mem[$0600] = $56" (= #x56 (mem-read cpu #x0600)))
    (check "STA (ind,X) : cycles = 6"       (= 6    (cpu-cycles cpu))))

  ;; STA (ind),Y
  (let ((cpu (make-cpu)))
    (mem-write cpu #x60 #x00)  ; vecteur $60/$61 = $0700
    (mem-write cpu #x61 #x07)
    (setf (cpu-a cpu) #x78 (cpu-y cpu) 5)
    (load-program cpu #(#x91 #x60 #x00) :origin 0)  ; STA ($60),Y
    (step-cpu cpu)
    (check "STA (ind),Y : mem[$0705] = $78" (= #x78 (mem-read cpu #x0705)))
    (check "STA (ind),Y : cycles = 6"       (= 6    (cpu-cycles cpu))))

  ;; --- STX ---
  (let ((cpu (make-cpu)))
    (setf (cpu-x cpu) #x9A)
    (load-program cpu #(#x86 #x70 #x00) :origin 0)  ; STX $70
    (step-cpu cpu)
    (check "STX zp : mem[$70] = $9A" (= #x9A (mem-read cpu #x70)))
    (check "STX zp : cycles = 3"     (= 3    (cpu-cycles cpu))))

  (let ((cpu (make-cpu)))
    (setf (cpu-x cpu) #xBC (cpu-y cpu) 2)
    (load-program cpu #(#x96 #x70 #x00) :origin 0)  ; STX $70,Y
    (step-cpu cpu)
    (check "STX zp,Y : mem[$72] = $BC" (= #xBC (mem-read cpu #x72))))

  (let ((cpu (make-cpu)))
    (setf (cpu-x cpu) #xDE)
    (load-program cpu #(#x8E #x00 #x08 #x00) :origin 0)  ; STX $0800
    (step-cpu cpu)
    (check "STX abs : mem[$0800] = $DE" (= #xDE (mem-read cpu #x0800))))

  ;; --- STY ---
  (let ((cpu (make-cpu)))
    (setf (cpu-y cpu) #xF0)
    (load-program cpu #(#x84 #x80 #x00) :origin 0)  ; STY $80
    (step-cpu cpu)
    (check "STY zp : mem[$80] = $F0" (= #xF0 (mem-read cpu #x80)))
    (check "STY zp : cycles = 3"     (= 3    (cpu-cycles cpu))))

  (let ((cpu (make-cpu)))
    (setf (cpu-y cpu) #x0F (cpu-x cpu) 1)
    (load-program cpu #(#x94 #x80 #x00) :origin 0)  ; STY $80,X
    (step-cpu cpu)
    (check "STY zp,X : mem[$81] = $0F" (= #x0F (mem-read cpu #x81))))

  (let ((cpu (make-cpu)))
    (setf (cpu-y cpu) #x1E)
    (load-program cpu #(#x8C #x00 #x09 #x00) :origin 0)  ; STY $0900
    (step-cpu cpu)
    (check "STY abs : mem[$0900] = $1E" (= #x1E (mem-read cpu #x0900)))))


;;; --------------------------------------------------------------------------
;;;  Point d'entrée
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (test/make-cpu)
  (test/reset-cpu)
  (test/memory)
  (test/load-program)
  (test/flags)
  (test/stack)
  (test/nop-brk)
  (test/transfers)
  (test/stack-instructions)
  (test/inc-dec)
  (test/flag-instructions)
  (test/run-cpu)
  (test/load-store)
  (format t "~&~%=== sim-6502     : ~D OK, ~D KO sur ~D tests~%"
          *pass* *fail* (+ *pass* *fail*))
  (when *failures*
    (format t "Échecs :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
