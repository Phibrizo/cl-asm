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
  (format t "~&~%=== sim-6502     : ~D OK, ~D KO sur ~D tests~%"
          *pass* *fail* (+ *pass* *fail*))
  (when *failures*
    (format t "Échecs :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
