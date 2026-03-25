; -*- coding: utf-8 -*-
;;; tests/test-debugger-6502.lisp
;;;
;;; Tests unitaires — débogueur 6502.
;;;
;;; Groupes :
;;;   test/dbg-debug-map     — debug-map : get/set, remplissage par assemble   ( 6 tests)
;;;   test/dbg-breakpoints   — set/clear/list, hit-p, conditions               ( 9 tests)
;;;   test/dbg-step          — step, retour :ok / :brk / :illegal             ( 7 tests)
;;;   test/dbg-next          — next step-over JSR                              ( 5 tests)
;;;   test/dbg-continue      — continue jusqu'à BRK / breakpoint               ( 6 tests)
;;;   test/dbg-display       — format-flags, show-registers, show-current      ( 8 tests)
;;;   test/dbg-repl          — REPL piloté par string-stream                  (12 tests)
;;;   test/dbg-watchpoints   — watchpoints :write / :read / :rw               ( 9 tests)
;;;   test/dbg-source-display — affichage ligne source depuis fichier          ( 5 tests)
;;;   test/dbg-cond-bp-repl  — breakpoints conditionnels via REPL             ( 5 tests)

(defpackage #:cl-asm/test.debugger-6502
  (:use #:cl
        #:cl-asm/simulator.6502
        #:cl-asm/debug-map
        #:cl-asm/debugger.6502)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.debugger-6502)


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
     (format t "~&[~A]~%" ',name)
     ,@body))


;;; --------------------------------------------------------------------------
;;;  Helpers
;;; --------------------------------------------------------------------------

(defun asm-dbg (source &key (origin #x0200))
  "Assemble SOURCE, charge dans un CPU frais, retourne (values dbg debug-map)."
  (let* ((prog  (cl-asm/parser:parse-string source))
         (dm    (make-debug-map))
         (bytes (cl-asm/backend.6502:assemble prog :origin origin :debug-map dm))
         (cpu   (make-cpu))
         (dbg   (make-debugger cpu :debug-map dm)))
    (load-program cpu bytes :origin origin)
    (values dbg dm)))

(defun step-n (dbg n)
  "Exécute N steps silencieux. Retourne le dernier résultat."
  (let (r)
    (dotimes (_ n r)
      (setq r (debugger-step dbg nil)))))

(defun repl-run (dbg commands)
  "Exécute le REPL avec COMMANDS (string), retourne la sortie."
  (let ((in  (make-string-input-stream commands))
        (out (make-string-output-stream)))
    (debugger-repl dbg :input in :output out)
    (get-output-stream-string out)))


;;; --------------------------------------------------------------------------
;;;  test/dbg-debug-map
;;; --------------------------------------------------------------------------

(deftest test/dbg-debug-map
  (format t "~%--- debug-map ---~%")

  ;; Construction et accès de base
  (let ((dm (make-debug-map)))
    (check "debug-map vide : get $0000 → NIL"
           (null (debug-map-get dm #x0000)))
    (check "debug-map vide : get $FFFF → NIL"
           (null (debug-map-get dm #xFFFF))))

  ;; Set / Get aller-retour
  (let ((dm  (make-debug-map))
        (loc (cl-asm/ir:make-source-loc :file "test.asm" :line 42 :column 2)))
    (debug-map-set dm #x0200 loc)
    (check "debug-map-set puis get : même objet"
           (eq (debug-map-get dm #x0200) loc))
    (check "adresse voisine reste NIL"
           (null (debug-map-get dm #x0201))))

  ;; Remplissage automatique par assemble
  (multiple-value-bind (dbg dm)
      (asm-dbg ".org $0300
  LDA #$01
  STA $10
  RTS")
    (declare (ignore dbg))
    (check "assemble remplit debug-map à $0300 (LDA)"
           (let ((loc (debug-map-get dm #x0300)))
             (and loc (> (cl-asm/ir:source-loc-line loc) 0))))
    (check "assemble remplit debug-map à $0302 (STA)"
           (not (null (debug-map-get dm #x0302))))
    (check "assemble ne remplit pas les adresses vides ($0000)"
           (null (debug-map-get dm #x0000)))))


;;; --------------------------------------------------------------------------
;;;  test/dbg-breakpoints
;;; --------------------------------------------------------------------------

(deftest test/dbg-breakpoints
  (format t "~%--- breakpoints ---~%")

  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  NOP
  NOP
  BRK")

    ;; set / list / clear
    (check "list vide au départ"
           (null (list-breakpoints dbg)))

    (set-breakpoint dbg #x0201)
    (check "un breakpoint après set"
           (= 1 (length (list-breakpoints dbg))))
    (check "breakpoint à la bonne adresse"
           (= #x0201 (breakpoint-address (first (list-breakpoints dbg)))))
    (check "breakpoint inconditionnel par défaut"
           (null (breakpoint-condition (first (list-breakpoints dbg)))))

    (set-breakpoint dbg #x0202)
    (check "deux breakpoints après second set"
           (= 2 (length (list-breakpoints dbg))))
    (check "list-breakpoints triée par adresse"
           (< (breakpoint-address (first  (list-breakpoints dbg)))
              (breakpoint-address (second (list-breakpoints dbg)))))

    (clear-breakpoint dbg #x0201)
    (check "un breakpoint après clear"
           (= 1 (length (list-breakpoints dbg))))

    ;; breakpoint-hit-p
    (let ((bp  (make-breakpoint :address #x0202))
          (cpu (debugger-cpu dbg)))
      (setf (cpu-pc cpu) #x0202)
      (check "breakpoint-hit-p vrai quand PC = adresse"
             (cl-asm/debugger.6502::breakpoint-hit-p bp cpu))
      (setf (cpu-pc cpu) #x0201)
      (check "breakpoint-hit-p faux quand PC ≠ adresse"
             (not (cl-asm/debugger.6502::breakpoint-hit-p bp cpu))))

    ;; breakpoint conditionnel (anticipation scope étendu)
    (set-breakpoint dbg #x0200
                    :condition (lambda (cpu) (= (cpu-a cpu) #xFF)))
    (let ((bp  (gethash #x0200 (debugger-breakpoints dbg)))
          (cpu (debugger-cpu dbg)))
      (setf (cpu-pc cpu) #x0200 (cpu-a cpu) #x00)
      (check "breakpoint conditionnel : faux si condition non satisfaite"
             (not (cl-asm/debugger.6502::breakpoint-hit-p bp cpu)))
      (setf (cpu-a cpu) #xFF)
      (check "breakpoint conditionnel : vrai si condition satisfaite"
             (cl-asm/debugger.6502::breakpoint-hit-p bp cpu)))))


;;; --------------------------------------------------------------------------
;;;  test/dbg-step
;;; --------------------------------------------------------------------------

(deftest test/dbg-step
  (format t "~%--- step ---~%")

  ;; Step → :ok, PC avance
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$42
  LDX #$01
  BRK")
    (let ((cpu (debugger-cpu dbg)))
      (check "step initial : PC = $0200"
             (= #x0200 (cpu-pc cpu)))
      (check "step retourne :ok"
             (eq :ok (debugger-step dbg nil)))
      (check "après step LDA : PC = $0202"
             (= #x0202 (cpu-pc cpu)))
      (check "après step LDA : A = $42"
             (= #x42 (cpu-a cpu)))
      (check "step suivant : PC = $0204"
             (progn (debugger-step dbg nil)
                    (= #x0204 (cpu-pc cpu))))
      (check "après step LDX : X = $01"
             (= #x01 (cpu-x cpu)))))

  ;; Step sur BRK → :brk
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  BRK")
    (check "step sur BRK retourne :brk"
           (eq :brk (debugger-step dbg nil)))))


;;; --------------------------------------------------------------------------
;;;  test/dbg-next
;;; --------------------------------------------------------------------------

(deftest test/dbg-next
  (format t "~%--- next (step-over) ---~%")

  ;; next sur instruction ordinaire = step
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$05
  BRK")
    (let ((cpu (debugger-cpu dbg)))
      (check "next sur LDA : PC avance comme step"
             (progn (debugger-next dbg nil)
                    (= #x0202 (cpu-pc cpu))))))

  ;; next sur JSR : saute la sous-routine
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  JSR sub
  LDA #$AA    ; <- on doit arriver ici après next
  BRK
sub:
  LDA #$BB    ; ne doit PAS s'exécuter en un seul next
  RTS")
    (let ((cpu (debugger-cpu dbg)))
      (check "next sur JSR : retourne :ok"
             (eq :ok (debugger-next dbg nil)))
      (check "next sur JSR : PC pointe après le JSR ($0203)"
             (= #x0203 (cpu-pc cpu)))
      (check "next sur JSR : A=$BB (sous-routine exécutée)"
             (= #xBB (cpu-a cpu)))
      (check "pas de breakpoint résiduel après next"
             (null (gethash #x0203 (debugger-breakpoints dbg))))))

  ;; next préserve un breakpoint existant à l'adresse de retour
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  JSR sub
  NOP
  BRK
sub:
  RTS")
    (set-breakpoint dbg #x0203)
    (debugger-next dbg nil)
    (check "breakpoint préexistant à l'adresse de retour survit au next"
           (not (null (gethash #x0203 (debugger-breakpoints dbg)))))))


;;; --------------------------------------------------------------------------
;;;  test/dbg-continue
;;; --------------------------------------------------------------------------

(deftest test/dbg-continue
  (format t "~%--- continue ---~%")

  ;; continue jusqu'à BRK
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$01
  LDA #$02
  BRK")
    (check "continue retourne :brk sur BRK"
           (eq :brk (debugger-continue dbg nil))))

  ;; continue jusqu'à breakpoint
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  NOP
  NOP
  NOP
  BRK")
    (set-breakpoint dbg #x0202)
    (check "continue retourne :breakpoint"
           (eq :breakpoint (debugger-continue dbg nil)))
    (check "PC = $0202 après arrêt sur breakpoint"
           (= #x0202 (cpu-pc (debugger-cpu dbg)))))

  ;; continue exécute bien toutes les instructions intermédiaires
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$00
  CLC
  ADC #$01
  ADC #$01
  ADC #$01
  BRK")
    (debugger-continue dbg nil)
    (check "continue : A = $03 après 3 ADC #$01"
           (= #x03 (cpu-a (debugger-cpu dbg))))))


;;; --------------------------------------------------------------------------
;;;  test/dbg-display
;;; --------------------------------------------------------------------------

(deftest test/dbg-display
  (format t "~%--- affichage ---~%")

  ;; format-flags
  (check "P=$00 : tous minuscules (sauf -)"
         (string= "nv-bdizc"
                  (cl-asm/debugger.6502::format-flags #x00)))
  (check "P=$FF : tous majuscules"
         (string= "NV-BDIZC"
                  (cl-asm/debugger.6502::format-flags #xFF)))
  (check "P=$24 (état initial : I=1, bit5=1)"
         (string= "nv-bdIzc"
                  (cl-asm/debugger.6502::format-flags #x24)))

  ;; show-registers capture
  (let* ((cpu (make-cpu))
         (out (make-string-output-stream)))
    (setf (cpu-a cpu) #x42 (cpu-x cpu) #x01 (cpu-y cpu) #x02
          (cpu-sp cpu) #xFD)
    (show-registers cpu out)
    (let ((s (get-output-stream-string out)))
      (check "show-registers contient A=$42"
             (search "A=$42" s))
      (check "show-registers contient X=$01"
             (search "X=$01" s))
      (check "show-registers contient SP=$FD"
             (search "SP=$FD" s))))

  ;; show-current capture
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$55
  BRK")
    (let* ((out (make-string-output-stream)))
      (debugger-step dbg out)
      (let ((s (get-output-stream-string out)))
        (check "show-current après LDA contient $0202"
               (search "$0202" s))
        (check "show-current contient 'BRK'"
               (search "BRK" s))))))


;;; --------------------------------------------------------------------------
;;;  test/dbg-repl
;;; --------------------------------------------------------------------------

(deftest test/dbg-repl
  (format t "~%--- REPL (string-stream) ---~%")

  ;; quit immédiat
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  NOP
  BRK")
    (let ((out (repl-run dbg "q")))
      (check "repl : 'q' retourne immédiatement"
             (search "revoir" out))))

  ;; step puis quit
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$07
  BRK")
    (let* ((out  (repl-run dbg (format nil "s~%q~%")))
           (cpu  (debugger-cpu dbg)))
      (check "repl : 's' exécute une instruction"
             (= #x0202 (cpu-pc cpu)))
      (check "repl : sortie contient '$0202'"
             (search "$0202" out))))

  ;; continue jusqu'à BRK
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$01
  LDA #$02
  BRK")
    (let ((out (repl-run dbg "c")))
      (check "repl : 'c' jusqu'à BRK affiche [BRK]"
             (search "BRK" out))))

  ;; breakpoint pose / supprime
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  NOP
  NOP
  BRK")
    (repl-run dbg (format nil "b $0201~%q~%"))
    (check "repl : 'b $0201' pose un breakpoint"
           (not (null (gethash #x0201 (debugger-breakpoints dbg)))))
    (repl-run dbg (format nil "d $0201~%q~%"))
    (check "repl : 'd $0201' supprime le breakpoint"
           (null (gethash #x0201 (debugger-breakpoints dbg)))))

  ;; list breakpoints
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  NOP
  BRK")
    (set-breakpoint dbg #x0200)
    (let ((out (repl-run dbg (format nil "lb~%q~%"))))
      (check "repl : 'lb' affiche l'adresse du breakpoint"
             (search "$0200" out))))

  ;; commande mémoire
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$AB
  BRK")
    (let ((out (repl-run dbg (format nil "m $0200 4~%q~%"))))
      (check "repl : 'm $0200 4' affiche '$0200'"
             (search "$0200" out))
      (check "repl : 'm' affiche l'opcode LDA #imm ($A9)"
             (search "A9" out))))

  ;; désassembler
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$AB
  BRK")
    (let ((out (repl-run dbg (format nil "x $0200 2~%q~%"))))
      (check "repl : 'x' affiche 'LDA'"
             (search "LDA" out))))

  ;; entrée vide = répéter dernière commande
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  NOP
  NOP
  NOP
  BRK")
    (repl-run dbg (format nil "s~%~%~%q~%"))
    (check "repl : entrée vide répète la dernière commande (3 steps)"
           (= #x0203 (cpu-pc (debugger-cpu dbg)))))

  ;; aide
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  BRK")
    (let ((out (repl-run dbg (format nil "h~%q~%"))))
      (check "repl : 'h' affiche l'aide (contient 'step')"
             (search "step" out))))

  ;; commande inconnue : pas de crash
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  BRK")
    (check "repl : commande inconnue ne crashe pas"
           (handler-case
               (progn (repl-run dbg (format nil "zzz~%q~%")) t)
             (error () nil)))))


;;; --------------------------------------------------------------------------
;;;  test/dbg-watchpoints
;;; --------------------------------------------------------------------------

(deftest test/dbg-watchpoints
  (format t "~%--- watchpoints ---~%")

  ;; set / list / clear
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$01
  STA $10
  BRK")
    (check "list-watchpoints vide au départ"
           (null (list-watchpoints dbg)))

    (set-watchpoint dbg #x0010 :kind :write)
    (check "un watchpoint après set"
           (= 1 (length (list-watchpoints dbg))))
    (check "watchpoint à la bonne adresse"
           (= #x0010 (watchpoint-address (first (list-watchpoints dbg)))))
    (check "watchpoint kind :write"
           (eq :write (watchpoint-kind (first (list-watchpoints dbg)))))

    (clear-watchpoint dbg #x0010)
    (check "aucun watchpoint après clear"
           (null (list-watchpoints dbg))))

  ;; watchpoint :write déclenche sur écriture mémoire
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$42
  STA $10    ; écrit à $0010
  NOP
  BRK")
    (set-watchpoint dbg #x0010 :kind :write)
    (check "continue retourne :watchpoint sur STA $10"
           (eq :watchpoint (debugger-continue dbg nil)))
    (check "last-watchpoint adresse = $0010"
           (= #x0010 (first (debugger-last-watchpoint dbg))))
    (check "last-watchpoint kind = :write"
           (eq :write (second (debugger-last-watchpoint dbg)))))

  ;; watchpoint :read déclenche sur lecture mémoire
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA $10    ; lit à $0010
  BRK")
    (set-watchpoint dbg #x0010 :kind :read)
    (check "continue retourne :watchpoint sur LDA $10"
           (eq :watchpoint (debugger-continue dbg nil))))

  ;; watchpoint :rw déclenche sur écriture ET lecture
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  STA $10    ; écriture
  BRK")
    (set-watchpoint dbg #x0010 :kind :rw)
    (check "continue retourne :watchpoint (:rw) sur STA"
           (eq :watchpoint (debugger-continue dbg nil))))

  ;; REPL : commande w pose un watchpoint
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  NOP
  BRK")
    (repl-run dbg (format nil "w $0010 write~%q~%"))
    (check "repl : 'w $0010 write' pose un watchpoint"
           (not (null (gethash #x0010 (debugger-watchpoints dbg))))))

  ;; REPL : commande lw liste les watchpoints
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  BRK")
    (set-watchpoint dbg #x0020 :kind :rw)
    (let ((out (repl-run dbg (format nil "lw~%q~%"))))
      (check "repl : 'lw' affiche l'adresse du watchpoint"
             (search "$0020" out)))))


;;; --------------------------------------------------------------------------
;;;  test/dbg-source-display
;;; --------------------------------------------------------------------------

(defun asm-dbg-file (source &key (origin #x0200))
  "Écrit SOURCE dans un fichier temporaire, assemble avec debug-map,
   retourne (values dbg dm path)."
  (let* ((path (merge-pathnames "cl-asm-dbg-src-test.asm"
                                (or (uiop:temporary-directory) #p"/tmp/")))
         (dm   (make-debug-map)))
    (with-open-file (out path :direction :output :if-exists :supersede
                         :if-does-not-exist :create)
      (write-string source out))
    (let* ((bytes (cl-asm/backend.6502:assemble-file path :origin origin :debug-map dm))
           (cpu   (make-cpu))
           (dbg   (make-debugger cpu :debug-map dm)))
      (load-program cpu bytes :origin origin)
      (values dbg dm path))))

(deftest test/dbg-source-display
  (format t "~%--- affichage source ---~%")

  ;; Le texte de la ligne source apparaît dans show-current
  (multiple-value-bind (dbg _dm path)
      (asm-dbg-file (format nil "  .org $0200~%  LDA #$42~%  NOP~%  BRK~%"))
    (declare (ignore _dm))
    (let* ((out (make-string-output-stream)))
      (show-current dbg out)
      (let ((s (get-output-stream-string out)))
        (check "show-current avec fichier source : contient le texte de la ligne"
               (search "LDA #$42" s))
        (check "show-current avec fichier source : contient le nom de fichier"
               (search "cl-asm-dbg-src-test.asm" s))))
    ;; Nettoyage
    (ignore-errors (delete-file path)))

  ;; Après un step, la ligne suivante est affichée
  (multiple-value-bind (dbg _dm path)
      (asm-dbg-file (format nil "  .org $0200~%  LDA #$01~%  NOP~%  BRK~%"))
    (declare (ignore _dm))
    (let* ((out (make-string-output-stream)))
      (debugger-step dbg out)
      (let ((s (get-output-stream-string out)))
        (check "après step, show-current affiche la ligne suivante (NOP)"
               (search "NOP" s))))
    (ignore-errors (delete-file path)))

  ;; Sans fichier (parse-string) : pas de crash, pas de ligne source
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$55
  BRK")
    (let* ((out (make-string-output-stream)))
      (show-current dbg out)
      (let ((s (get-output-stream-string out)))
        (check "sans fichier source : show-current ne crashe pas"
               (search "LDA" s))
        (check "sans fichier source : pas de ligne '| '"
               (not (search " | " s))))))

  ;; Cache : le fichier n'est lu qu'une fois (deux appels successifs)
  (multiple-value-bind (dbg _dm path)
      (asm-dbg-file (format nil "  .org $0200~%  NOP~%  NOP~%  BRK~%"))
    (declare (ignore _dm))
    (let* ((out1 (make-string-output-stream))
           (out2 (make-string-output-stream)))
      (show-current dbg out1)
      (show-current dbg out2)
      (check "cache source : deuxième appel donne le même résultat"
             (string= (get-output-stream-string out1)
                      (get-output-stream-string out2))))
    (ignore-errors (delete-file path))))


;;; --------------------------------------------------------------------------
;;;  test/dbg-cond-bp-repl
;;; --------------------------------------------------------------------------

(deftest test/dbg-cond-bp-repl
  (format t "~%--- breakpoints conditionnels (REPL) ---~%")

  ;; Breakpoint conditionnel via REPL : condition A=#xFF
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$FE
  LDA #$FF
  NOP
  BRK")
    ;; Pose le breakpoint conditionnel à $0204 (NOP) avec condition A=$FF
    (repl-run dbg (format nil
      "b $0204 (= (cl-asm/simulator.6502:cpu-a cpu) #xFF)~%q~%"))
    (check "repl : breakpoint conditionnel posé"
           (not (null (gethash #x0204 (debugger-breakpoints dbg)))))
    (check "repl : slot condition non-nil"
           (not (null (breakpoint-condition
                        (gethash #x0204 (debugger-breakpoints dbg)))))))

  ;; Le breakpoint conditionnel s'arrête quand la condition est vraie
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$FF    ; A = #xFF
  NOP         ; breakpoint conditionnel ici (A=$FF → true)
  BRK")
    (set-breakpoint dbg #x0202
      :condition (lambda (cpu) (= (cpu-a cpu) #xFF)))
    (check "continue s'arrête quand condition vraie (A=#xFF)"
           (eq :breakpoint (debugger-continue dbg nil))))

  ;; Le breakpoint conditionnel ne s'arrête PAS quand la condition est fausse
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  LDA #$00    ; A = #x00
  NOP         ; breakpoint conditionnel ici (A=$FF → faux)
  BRK")
    (set-breakpoint dbg #x0202
      :condition (lambda (cpu) (= (cpu-a cpu) #xFF)))
    (check "continue dépasse le breakpoint quand condition fausse (A≠#xFF)"
           (eq :brk (debugger-continue dbg nil))))

  ;; Syntaxe REPL invalide : pas de crash
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  BRK")
    (check "repl : condition invalide ne crashe pas"
           (handler-case
               (progn (repl-run dbg (format nil "b $0200 )))~%q~%")) t)
             (error () nil))))

  ;; REPL sans condition → breakpoint inconditionnel
  (multiple-value-bind (dbg)
      (asm-dbg ".org $0200
  NOP
  BRK")
    (repl-run dbg (format nil "b $0200~%q~%"))
    (check "repl : 'b $ADDR' sans condition → condition nil"
           (null (breakpoint-condition
                   (gethash #x0200 (debugger-breakpoints dbg)))))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~%=== Débogueur 6502 ===~%")
  (test/dbg-debug-map)
  (test/dbg-breakpoints)
  (test/dbg-step)
  (test/dbg-next)
  (test/dbg-continue)
  (test/dbg-display)
  (test/dbg-repl)
  (test/dbg-watchpoints)
  (test/dbg-source-display)
  (test/dbg-cond-bp-repl)
  (format t "~%=== debugger-6502 : ~3D OK, ~D KO~%" *pass* *fail*)
  (when *failures*
    (format t "  Échecs :~%")
    (dolist (f (reverse *failures*))
      (format t "    - ~A~%" f))))
