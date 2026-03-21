; -*- coding: utf-8 -*-
;;; tests/test-m68k-parser.lisp
;;;
;;; Tests unitaires pour le parser M68K.
;;; Vérifie l'IR produit par parse-string avec *m68k-mode* = T.
;;; Aucun backend requis — on inspecte directement les structures IR.

(defpackage #:cl-asm/test.m68k-parser
  (:use #:cl)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.m68k-parser)


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

(defun parse-m68k (src)
  "Parse SRC en mode M68K, retourne l'IR-PROGRAM."
  (let ((cl-asm/parser:*m68k-mode* t))
    (cl-asm/parser:parse-string src)))

(defun all-nodes (prog)
  (cl-asm/ir:ir-section-nodes
   (first (cl-asm/ir:ir-program-sections prog))))

(defun instr-nodes (prog)
  (remove-if-not #'cl-asm/ir:ir-instruction-p (all-nodes prog)))

(defun first-instr (prog)
  (first (instr-nodes prog)))

(defun nth-instr (prog n)
  (nth n (instr-nodes prog)))

(defun imnem (instr) (cl-asm/ir:ir-instruction-mnemonic instr))
(defun isize (instr) (cl-asm/ir:ir-instruction-size instr))
(defun iops  (instr) (cl-asm/ir:ir-instruction-operands instr))

(defun op (instr n)  (nth n (iops instr)))
(defun ok (instr n)  (cl-asm/ir:ir-operand-kind  (op instr n)))
(defun ov (instr n)  (cl-asm/ir:ir-operand-value (op instr n)))


;;; --------------------------------------------------------------------------
;;;  1. Activation du mode — isolation des autres architectures
;;; --------------------------------------------------------------------------

(deftest test-m68k-mode-isolation
  ;; Sans *m68k-mode*, MOVE n'est pas un mnémonique M68K reconnu
  (check "*m68k-mode* = NIL par défaut"
    (null cl-asm/parser:*m68k-mode*))
  ;; Avec *m68k-mode* = T, MOVE est reconnu
  (check "MOVE reconnu en mode M68K"
    (let ((cl-asm/parser:*m68k-mode* t))
      (cl-asm/parser:m68k-mnemonic-p "MOVE")))
  ;; Sans *m68k-mode*, MOVE n'est pas reconnu
  (check "MOVE non reconnu hors mode M68K"
    (null (cl-asm/parser:m68k-mnemonic-p "MOVE")))
  ;; AND fonctionne comme mnemonic 6502 quand *m68k-mode* = NIL
  (check "AND parse en 6502 hors mode M68K"
    (let* ((prog (cl-asm/parser:parse-string "AND #$FF"))
           (i    (first-instr prog)))
      (and (string= (imnem i) "AND")
           (eq (ok i 0) :immediate)
           (= (ov i 0) #xFF)))))


;;; --------------------------------------------------------------------------
;;;  2. Suffixes de taille sur les mnémoniques
;;; --------------------------------------------------------------------------

(deftest test-m68k-size-suffixes
  (check "MOVE.B — mnémonique de base"
    (string= (imnem (first-instr (parse-m68k "MOVE.B D0,D1"))) "MOVE"))
  (check "MOVE.B — taille :byte"
    (eq (isize (first-instr (parse-m68k "MOVE.B D0,D1"))) :byte))
  (check "MOVE.W — taille :word"
    (eq (isize (first-instr (parse-m68k "MOVE.W D0,D1"))) :word))
  (check "MOVE.L — taille :long"
    (eq (isize (first-instr (parse-m68k "MOVE.L D0,D1"))) :long))
  (check "BRA.S — taille :byte (suffixe S = short)"
    (eq (isize (first-instr (parse-m68k "BRA.S loop
loop:"))) :byte))
  (check "NOP — pas de suffixe, taille NIL"
    (null (isize (first-instr (parse-m68k "NOP")))))
  (check "ADD sans suffixe — taille NIL"
    (null (isize (first-instr (parse-m68k "ADD D0,D1"))))))


;;; --------------------------------------------------------------------------
;;;  3. Instructions sans opérande
;;; --------------------------------------------------------------------------

(deftest test-m68k-implied
  (check "NOP — mnémonique"
    (string= (imnem (first-instr (parse-m68k "NOP"))) "NOP"))
  (check "NOP — 0 opérandes"
    (null (iops (first-instr (parse-m68k "NOP")))))
  (check "RTS — mnémonique"
    (string= (imnem (first-instr (parse-m68k "RTS"))) "RTS"))
  (check "RTS — 0 opérandes"
    (null (iops (first-instr (parse-m68k "RTS")))))
  (check "RTE — 0 opérandes"
    (null (iops (first-instr (parse-m68k "RTE")))))
  (check "ILLEGAL — 0 opérandes"
    (null (iops (first-instr (parse-m68k "ILLEGAL"))))))


;;; --------------------------------------------------------------------------
;;;  4. Opérande immédiat
;;; --------------------------------------------------------------------------

(deftest test-m68k-immediate
  (check "#$42 — kind :immediate"
    (eq (ok (first-instr (parse-m68k "MOVE.B #$42,D0")) 0) :immediate))
  (check "#$42 — valeur $42"
    (= (ov (first-instr (parse-m68k "MOVE.B #$42,D0")) 0) #x42))
  (check "#$1234 — valeur $1234"
    (= (ov (first-instr (parse-m68k "MOVE.W #$1234,D0")) 0) #x1234))
  (check "#0 — valeur 0"
    (= (ov (first-instr (parse-m68k "MOVE.B #0,D0")) 0) 0))
  (check "#(1+1) — expression"
    (equal (ov (first-instr (parse-m68k "MOVE.B #(1+1),D0")) 0) '(:+ 1 1))))


;;; --------------------------------------------------------------------------
;;;  5. Registres de données (Dn)
;;; --------------------------------------------------------------------------

(deftest test-m68k-data-registers
  (check "D0 — kind :direct"
    (eq (ok (first-instr (parse-m68k "MOVE.B D0,D1")) 0) :direct))
  (check "D0 — valeur \"D0\""
    (equal (ov (first-instr (parse-m68k "MOVE.B D0,D1")) 0) "D0"))
  (check "D7 — valeur \"D7\""
    (equal (ov (first-instr (parse-m68k "MOVE.L D7,D0")) 0) "D7"))
  (check "D1 en 2e opérande"
    (equal (ov (first-instr (parse-m68k "MOVE.B D0,D1")) 1) "D1"))
  (check "D3 — valeur \"D3\""
    (equal (ov (first-instr (parse-m68k "ADD.W D3,D5")) 0) "D3")))


;;; --------------------------------------------------------------------------
;;;  6. Registres d'adresse (An, SP)
;;; --------------------------------------------------------------------------

(deftest test-m68k-addr-registers
  (check "A0 — kind :direct"
    (eq (ok (first-instr (parse-m68k "MOVEA.L A0,A1")) 0) :direct))
  (check "A0 — valeur \"A0\""
    (equal (ov (first-instr (parse-m68k "MOVEA.L A0,A1")) 0) "A0"))
  (check "A7 — valeur \"A7\""
    (equal (ov (first-instr (parse-m68k "MOVEA.L A7,A0")) 0) "A7"))
  (check "SP — valeur \"SP\""
    (equal (ov (first-instr (parse-m68k "MOVEA.L SP,A0")) 0) "SP"))
  (check "A1 en 2e opérande"
    (equal (ov (first-instr (parse-m68k "MOVEA.L A0,A1")) 1) "A1")))


;;; --------------------------------------------------------------------------
;;;  7. Registres spéciaux (PC, SR, CCR)
;;; --------------------------------------------------------------------------

(deftest test-m68k-special-registers
  (check "SR — kind :direct"
    (eq (ok (first-instr (parse-m68k "MOVE.W D0,SR")) 1) :direct))
  (check "SR — valeur \"SR\""
    (equal (ov (first-instr (parse-m68k "MOVE.W D0,SR")) 1) "SR"))
  (check "CCR — valeur \"CCR\""
    (equal (ov (first-instr (parse-m68k "MOVE.B D0,CCR")) 1) "CCR")))


;;; --------------------------------------------------------------------------
;;;  8. Indirect registre — (An)
;;; --------------------------------------------------------------------------

(deftest test-m68k-indirect
  (check "(A0) — kind :indirect"
    (eq (ok (first-instr (parse-m68k "MOVE.L (A0),D0")) 0) :indirect))
  (check "(A0) — valeur \"A0\""
    (equal (ov (first-instr (parse-m68k "MOVE.L (A0),D0")) 0) "A0"))
  (check "(A6) — valeur \"A6\""
    (equal (ov (first-instr (parse-m68k "MOVE.W (A6),D1")) 0) "A6"))
  (check "(SP) — valeur \"SP\""
    (equal (ov (first-instr (parse-m68k "MOVE.W (SP),D0")) 0) "SP"))
  (check "(A1) en 2e opérande"
    (eq (ok (first-instr (parse-m68k "MOVE.L D0,(A1)")) 1) :indirect)))


;;; --------------------------------------------------------------------------
;;;  9. Post-incrémentation — (An)+
;;; --------------------------------------------------------------------------

(deftest test-m68k-post-increment
  (check "(A0)+ — kind :post-increment"
    (eq (ok (first-instr (parse-m68k "MOVE.L (A0)+,D0")) 0) :post-increment))
  (check "(A0)+ — valeur \"A0\""
    (equal (ov (first-instr (parse-m68k "MOVE.L (A0)+,D0")) 0) "A0"))
  (check "(A7)+ — valeur \"A7\""
    (equal (ov (first-instr (parse-m68k "MOVE.W (A7)+,D1")) 0) "A7"))
  (check "(SP)+ — valeur \"SP\""
    (equal (ov (first-instr (parse-m68k "MOVE.W (SP)+,D0")) 0) "SP"))
  (check "(A0)+ en 2e opérande"
    (eq (ok (first-instr (parse-m68k "MOVE.L D0,(A0)+")) 1) :post-increment)))


;;; --------------------------------------------------------------------------
;;;  10. Pré-décrémentation — -(An)
;;; --------------------------------------------------------------------------

(deftest test-m68k-pre-decrement
  (check "-(A0) — kind :pre-decrement"
    (eq (ok (first-instr (parse-m68k "MOVE.L -(A0),D0")) 0) :pre-decrement))
  (check "-(A0) — valeur \"A0\""
    (equal (ov (first-instr (parse-m68k "MOVE.L -(A0),D0")) 0) "A0"))
  (check "-(A7) — valeur \"A7\""
    (equal (ov (first-instr (parse-m68k "MOVE.W -(A7),D1")) 0) "A7"))
  (check "-(SP) — valeur \"SP\""
    (equal (ov (first-instr (parse-m68k "MOVE.W -(SP),D0")) 0) "SP"))
  (check "post-inc source, pré-déc destination"
    (and (eq (ok (first-instr (parse-m68k "MOVE.L (A0)+,-(A1)")) 0) :post-increment)
         (eq (ok (first-instr (parse-m68k "MOVE.L (A0)+,-(A1)")) 1) :pre-decrement))))


;;; --------------------------------------------------------------------------
;;;  11. Déplacement — d(An) et d(PC)
;;; --------------------------------------------------------------------------

(deftest test-m68k-displacement
  (check "4(A0) — kind :indirect"
    (eq (ok (first-instr (parse-m68k "MOVE.W 4(A0),D0")) 0) :indirect))
  (check "4(A0) — valeur (:disp \"A0\" 4)"
    (equal (ov (first-instr (parse-m68k "MOVE.W 4(A0),D0")) 0) '(:disp "A0" 4)))
  (check "0(A0) — déplacement 0"
    (equal (ov (first-instr (parse-m68k "MOVE.W 0(A0),D0")) 0) '(:disp "A0" 0)))
  (check "$100(A3) — déplacement $100"
    (equal (ov (first-instr (parse-m68k "MOVE.W $100(A3),D0")) 0) '(:disp "A3" #x100)))
  (check "4(PC) — valeur (:disp :pc 4)"
    (equal (ov (first-instr (parse-m68k "LEA 4(PC),A0")) 0) '(:disp :pc 4)))
  (check "0(PC) — déplacement PC nul"
    (equal (ov (first-instr (parse-m68k "LEA 0(PC),A0")) 0) '(:disp :pc 0))))


;;; --------------------------------------------------------------------------
;;;  12. Indexé sans déplacement — (An,Xi.s)
;;; --------------------------------------------------------------------------

(deftest test-m68k-indexed-no-disp
  (check "(A0,D1.W) — kind :indirect"
    (eq (ok (first-instr (parse-m68k "MOVE.W (A0,D1.W),D0")) 0) :indirect))
  (check "(A0,D1.W) — valeur (:indexed \"A0\" \"D1\" :word 0)"
    (equal (ov (first-instr (parse-m68k "MOVE.W (A0,D1.W),D0")) 0)
           '(:indexed "A0" "D1" :word 0)))
  (check "(A0,D1.L) — taille Xi :long"
    (equal (ov (first-instr (parse-m68k "MOVE.L (A0,D1.L),D0")) 0)
           '(:indexed "A0" "D1" :long 0)))
  (check "(A0,A1.W) — registre d'adresse comme index"
    (equal (ov (first-instr (parse-m68k "MOVE.W (A0,A1.W),D0")) 0)
           '(:indexed "A0" "A1" :word 0)))
  (check "(A3,D2) — sans suffixe de taille, taille NIL"
    (equal (ov (first-instr (parse-m68k "MOVE.W (A3,D2),D0")) 0)
           '(:indexed "A3" "D2" nil 0))))


;;; --------------------------------------------------------------------------
;;;  13. Indexé avec déplacement — d(An,Xi.s) et d(PC,Xi.s)
;;; --------------------------------------------------------------------------

(deftest test-m68k-indexed-with-disp
  (check "4(A0,D1.W) — kind :indirect"
    (eq (ok (first-instr (parse-m68k "MOVE.W 4(A0,D1.W),D0")) 0) :indirect))
  (check "4(A0,D1.W) — valeur (:indexed \"A0\" \"D1\" :word 4)"
    (equal (ov (first-instr (parse-m68k "MOVE.W 4(A0,D1.W),D0")) 0)
           '(:indexed "A0" "D1" :word 4)))
  (check "0(A0,D1.L) — déplacement 0"
    (equal (ov (first-instr (parse-m68k "MOVE.L 0(A0,D1.L),D0")) 0)
           '(:indexed "A0" "D1" :long 0)))
  (check "$10(A3,A2.W) — registre d'adresse comme index, déplacement $10"
    (equal (ov (first-instr (parse-m68k "MOVE.W $10(A3,A2.W),D0")) 0)
           '(:indexed "A3" "A2" :word #x10)))
  (check "4(PC,D0.W) — PC-relatif indexé"
    (equal (ov (first-instr (parse-m68k "LEA 4(PC,D0.W),A0")) 0)
           '(:indexed :pc "D0" :word 4))))


;;; --------------------------------------------------------------------------
;;;  14. Adresse absolue et référence symbole
;;; --------------------------------------------------------------------------

(deftest test-m68k-absolute
  (check "$1234 — kind :direct"
    (eq (ok (first-instr (parse-m68k "JMP $1234")) 0) :direct))
  (check "$1234 — valeur $1234"
    (= (ov (first-instr (parse-m68k "JMP $1234")) 0) #x1234))
  (check "$FFFF00 — grande adresse"
    (= (ov (first-instr (parse-m68k "JMP $FFFF00")) 0) #xFFFF00))
  (check "LABEL — référence symbolique"
    (equal (ov (first-instr (parse-m68k "JMP LABEL")) 0) "LABEL")))


;;; --------------------------------------------------------------------------
;;;  15. Instructions à deux opérandes
;;; --------------------------------------------------------------------------

(deftest test-m68k-two-operands
  (check "MOVE.B D0,D1 — 2 opérandes"
    (= (length (iops (first-instr (parse-m68k "MOVE.B D0,D1")))) 2))
  (check "MOVE.B D0,D1 — src D0"
    (equal (ov (first-instr (parse-m68k "MOVE.B D0,D1")) 0) "D0"))
  (check "MOVE.B D0,D1 — dst D1"
    (equal (ov (first-instr (parse-m68k "MOVE.B D0,D1")) 1) "D1"))
  (check "MOVE.W #$1234,D0 — src immédiat"
    (and (eq (ok (first-instr (parse-m68k "MOVE.W #$1234,D0")) 0) :immediate)
         (= (ov (first-instr (parse-m68k "MOVE.W #$1234,D0")) 0) #x1234)))
  (check "MOVE.L (A0)+,-(A1) — post-inc → pré-déc"
    (and (eq (ok (first-instr (parse-m68k "MOVE.L (A0)+,-(A1)")) 0) :post-increment)
         (eq (ok (first-instr (parse-m68k "MOVE.L (A0)+,-(A1)")) 1) :pre-decrement)))
  (check "LEA 4(PC),A0 — déplacement PC → registre"
    (and (eq  (ok (first-instr (parse-m68k "LEA 4(PC),A0")) 0) :indirect)
         (equal (ov (first-instr (parse-m68k "LEA 4(PC),A0")) 0) '(:disp :pc 4))
         (equal (ov (first-instr (parse-m68k "LEA 4(PC),A0")) 1) "A0")))
  (check "ADD.W D0,D1 — deux registres données"
    (and (equal (ov (first-instr (parse-m68k "ADD.W D0,D1")) 0) "D0")
         (equal (ov (first-instr (parse-m68k "ADD.W D0,D1")) 1) "D1"))))


;;; --------------------------------------------------------------------------
;;;  16. Labels en mode M68K
;;; --------------------------------------------------------------------------

(deftest test-m68k-labels
  (let* ((prog  (parse-m68k "loop:
NOP
BRA loop"))
         (nodes (all-nodes prog)))
    (check "label local 'loop' présent"
      (find-if (lambda (n)
                 (and (cl-asm/ir:ir-label-p n)
                      (string= (cl-asm/ir:ir-label-name n) "LOOP")))
               nodes))
    (check "NOP après le label"
      (string= (imnem (nth-instr prog 0)) "NOP"))
    (check "BRA avec référence forward"
      (string= (imnem (nth-instr prog 1)) "BRA"))
    (check "BRA — opérande = \"LOOP\""
      (equal (ov (nth-instr prog 1) 0) "LOOP"))))


;;; --------------------------------------------------------------------------
;;;  17. Séquence d'instructions
;;; --------------------------------------------------------------------------

(deftest test-m68k-sequence
  (let ((prog (parse-m68k "MOVE.W D0,D1
ADD.L D2,D3
NOP")))
    (check "3 instructions dans la séquence"
      (= (length (instr-nodes prog)) 3))
    (check "1re instruction : MOVE.W"
      (and (string= (imnem (nth-instr prog 0)) "MOVE")
           (eq (isize (nth-instr prog 0)) :word)))
    (check "2e instruction : ADD.L"
      (and (string= (imnem (nth-instr prog 1)) "ADD")
           (eq (isize (nth-instr prog 1)) :long)))
    (check "3e instruction : NOP"
      (string= (imnem (nth-instr prog 2)) "NOP"))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~%--- M68K Parser ---~%")
  (test-m68k-mode-isolation)
  (test-m68k-size-suffixes)
  (test-m68k-implied)
  (test-m68k-immediate)
  (test-m68k-data-registers)
  (test-m68k-addr-registers)
  (test-m68k-special-registers)
  (test-m68k-indirect)
  (test-m68k-post-increment)
  (test-m68k-pre-decrement)
  (test-m68k-displacement)
  (test-m68k-indexed-no-disp)
  (test-m68k-indexed-with-disp)
  (test-m68k-absolute)
  (test-m68k-two-operands)
  (test-m68k-labels)
  (test-m68k-sequence)
  (format t "~%=== m68k-parser  : ~3D OK, ~D KO~%" *pass* *fail*))
