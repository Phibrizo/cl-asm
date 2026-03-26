; -*- coding: utf-8 -*-
;;;
;;; src/debugger/6502.lisp — Débogueur interactif MOS 6502
;;;
;;; Scope v0.7.0 (minimal) :
;;;   - REPL interactif : step / next / continue / quit
;;;   - Breakpoints par adresse (inconditionnels)
;;;   - Affichage registres, mémoire, désassemblage
;;;
;;; Scope v0.8.0 (étendu — watchpoints) :
;;;   - Watchpoints mémoire : :read | :write | :rw
;;;   - Raccordés au simulateur via cpu-watch-table (hash addr → kind)
;;;   - cpu-watchpoint condition capturée par %step-one → :watchpoint
;;;   - REPL : commandes w / dw / lw
;;;
;;; Anticipation breakpoints conditionnels (scope futur) :
;;;   - Struct BREAKPOINT avec slot CONDITION (nil = inconditionnel)
;;;     → les breakpoints conditionnels s'ajouteront sans changer l'API

(defpackage #:cl-asm/debugger.6502
  (:use #:cl)
  (:import-from #:cl-asm/debug-map
                #:debug-map
                #:make-debug-map
                #:debug-map-get
                #:debug-map-set)
  (:import-from #:cl-asm/simulator.6502
                #:cpu-a #:cpu-x #:cpu-y #:cpu-pc #:cpu-sp #:cpu-p
                #:cpu-mem #:cpu-cycles #:cpu-watch-table
                #:step-cpu
                #:cpu-break
                #:cpu-illegal-opcode #:cpu-illegal-opcode-cpu #:cpu-illegal-opcode-opcode
                #:cpu-watchpoint #:cpu-watchpoint-cpu
                #:cpu-watchpoint-address #:cpu-watchpoint-kind)
  (:import-from #:cl-asm/disassembler.6502
                #:disasm-one)
  (:export
   ;; debug-map (réexportée depuis cl-asm/debug-map pour commodité)
   #:debug-map
   #:make-debug-map
   #:debug-map-get
   #:debug-map-set
   ;; désassembleur pluggable
   #:debugger-disasm-fn
   ;; breakpoints
   #:breakpoint
   #:make-breakpoint
   #:breakpoint-address
   #:breakpoint-condition
   #:breakpoint-enabled
   #:set-breakpoint
   #:clear-breakpoint
   #:list-breakpoints
   ;; watchpoints
   #:watchpoint
   #:make-watchpoint
   #:watchpoint-address
   #:watchpoint-kind
   #:watchpoint-enabled
   #:set-watchpoint
   #:clear-watchpoint
   #:list-watchpoints
   ;; session débogueur
   #:debugger
   #:make-debugger
   #:debugger-cpu
   #:debugger-breakpoints
   #:debugger-watchpoints
   #:debugger-last-watchpoint
   #:debugger-debug-map
   #:debugger-source-cache
   ;; exécution
   #:debugger-step
   #:debugger-next
   #:debugger-continue
   ;; affichage (utiles hors REPL)
   #:show-registers
   #:show-current
   #:show-memory
   #:show-disasm
   ;; REPL
   #:debugger-repl))

(in-package #:cl-asm/debugger.6502)


;;; --------------------------------------------------------------------------
;;;  Breakpoints
;;;
;;;  Le slot CONDITION est NIL en v0.7.0 (breakpoints inconditionnels).
;;;  En scope étendu, on pourra passer (lambda (cpu) ...) → booléen.
;;; --------------------------------------------------------------------------

(defstruct (breakpoint (:constructor %make-breakpoint))
  "Point d'arrêt.
   CONDITION : NIL = inconditionnel ; sinon (function (cpu) → boolean)."
  (address   0  :type (unsigned-byte 16))
  (condition nil)
  (enabled   t  :type boolean))

(defun make-breakpoint (&key (address 0) condition (enabled t))
  (%make-breakpoint :address address :condition condition :enabled enabled))

(defun breakpoint-hit-p (bp cpu)
  "Vrai si BP est actif et sa condition (si définie) est satisfaite au PC courant."
  (and (breakpoint-enabled bp)
       (= (cpu-pc cpu) (breakpoint-address bp))
       (or (null (breakpoint-condition bp))
           (funcall (breakpoint-condition bp) cpu))))


;;; --------------------------------------------------------------------------
;;;  Watchpoints (raccordés au simulateur depuis v0.8.0)
;;;
;;;  Le simulateur expose cpu-watch-table (hash-table addr → kind).
;;;  set-watchpoint initialise cette table si nécessaire et y insère l'entrée.
;;;  %step-one capture cpu-watchpoint et retourne :watchpoint.
;;; --------------------------------------------------------------------------

(defstruct (watchpoint (:constructor %make-watchpoint))
  "Point de surveillance mémoire.
   KIND : :read | :write | :rw"
  (address 0    :type (unsigned-byte 16))
  (kind    :write)
  (enabled t    :type boolean))

(defun make-watchpoint (&key (address 0) (kind :write) (enabled t))
  (%make-watchpoint :address address :kind kind :enabled enabled))


;;; --------------------------------------------------------------------------
;;;  Session débogueur
;;; --------------------------------------------------------------------------

(defstruct (debugger (:constructor %make-debugger))
  "Session de débogage pour un CPU 6502.
   DISASM-FN : fonction (mem addr) → (values mn op size), défaut = désassembleur 6502."
  (cpu              nil)
  (breakpoints      (make-hash-table :test #'eql))
  (watchpoints      (make-hash-table :test #'eql))
  (last-watchpoint  nil)   ; (address kind) du dernier watchpoint déclenché
  (debug-map        nil)
  (source-cache     (make-hash-table :test #'equal))   ; filename → vector-of-lines
  (disasm-fn        #'disasm-one :type function))       ; désassembleur pluggable

(defun make-debugger (cpu &key debug-map disasm-fn)
  "Crée une session débogueur pour CPU.
   DEBUG-MAP  (optionnel) : table adresse → source-loc pour affichage source.
   DISASM-FN  (optionnel) : fonction (mem addr) → (values mn op size) ;
               défaut #'cl-asm/disassembler.6502:disasm-one."
  (%make-debugger :cpu cpu :debug-map debug-map
                  :disasm-fn (or disasm-fn #'disasm-one)))


;;; --------------------------------------------------------------------------
;;;  Gestion des breakpoints
;;; --------------------------------------------------------------------------

(defun set-breakpoint (dbg address &key condition)
  "Pose un breakpoint à ADDRESS.
   CONDITION : fonction (cpu) → bool, NIL = inconditionnel (v0.7.0)."
  (setf (gethash address (debugger-breakpoints dbg))
        (make-breakpoint :address address :condition condition))
  address)

(defun clear-breakpoint (dbg address)
  "Supprime le breakpoint à ADDRESS. Retourne T si un breakpoint existait."
  (remhash address (debugger-breakpoints dbg)))

(defun list-breakpoints (dbg)
  "Retourne la liste des breakpoints triés par adresse."
  (let (bps)
    (maphash (lambda (k v) (declare (ignore k)) (push v bps))
             (debugger-breakpoints dbg))
    (sort bps #'< :key #'breakpoint-address)))


;;; --------------------------------------------------------------------------
;;;  Gestion des watchpoints
;;; --------------------------------------------------------------------------

(defun set-watchpoint (dbg address &key (kind :write))
  "Pose un watchpoint à ADDRESS. KIND : :read | :write | :rw (défaut :write).
   Le watchpoint est immédiatement actif dans le simulateur."
  ;; Initialise la table dans le CPU si ce n'est pas encore fait
  (unless (cpu-watch-table (debugger-cpu dbg))
    (setf (cpu-watch-table (debugger-cpu dbg))
          (make-hash-table :test #'eql)))
  ;; Enregistre dans le débogueur (pour list-watchpoints)
  (setf (gethash address (debugger-watchpoints dbg))
        (make-watchpoint :address address :kind kind))
  ;; Enregistre dans la table du CPU (consulté par mem-read/mem-write)
  (setf (gethash address (cpu-watch-table (debugger-cpu dbg)))
        kind)
  address)

(defun clear-watchpoint (dbg address)
  "Supprime le watchpoint à ADDRESS."
  (remhash address (debugger-watchpoints dbg))
  (when (cpu-watch-table (debugger-cpu dbg))
    (remhash address (cpu-watch-table (debugger-cpu dbg)))))

(defun list-watchpoints (dbg)
  "Retourne la liste des watchpoints triés par adresse."
  (let (wps)
    (maphash (lambda (k v) (declare (ignore k)) (push v wps))
             (debugger-watchpoints dbg))
    (sort wps #'< :key #'watchpoint-address)))


;;; --------------------------------------------------------------------------
;;;  Cache de fichiers source
;;; --------------------------------------------------------------------------

(defun %load-source-lines (filename)
  "Charge FILENAME et retourne un vecteur de lignes, ou NIL si inaccessible."
  (handler-case
      (with-open-file (s filename :if-does-not-exist nil)
        (when s
          (let ((lines (make-array 16 :fill-pointer 0 :adjustable t)))
            (loop for line = (read-line s nil nil)
                  while line
                  do (vector-push-extend line lines))
            lines)))
    (error () nil)))

(defun %get-source-line (dbg filename line-num)
  "Retourne la ligne LINE-NUM (1-indexed) de FILENAME via le cache de DBG, ou NIL."
  (when (and filename (> (length filename) 0))
    (let* ((cache (debugger-source-cache dbg))
           (lines (or (gethash filename cache)
                      (let ((loaded (%load-source-lines filename)))
                        (when loaded
                          (setf (gethash filename cache) loaded))
                        loaded))))
      (when (and lines (>= line-num 1) (<= line-num (length lines)))
        (aref lines (1- line-num))))))


;;; --------------------------------------------------------------------------
;;;  Utilitaires d'affichage
;;; --------------------------------------------------------------------------

(defun format-flags (p)
  "Retourne 'NV-BDIZC' : majuscule = flag actif, minuscule = inactif."
  (labels ((bit-char (bit-n upper lower)
             (if (logbitp bit-n p) upper lower)))
    (format nil "~C~C-~C~C~C~C~C"
            (bit-char 7 #\N #\n)
            (bit-char 6 #\V #\v)
            (bit-char 4 #\B #\b)
            (bit-char 3 #\D #\d)
            (bit-char 2 #\I #\i)
            (bit-char 1 #\Z #\z)
            (bit-char 0 #\C #\c))))

(defun show-registers (cpu &optional (stream *standard-output*))
  "Affiche les registres sur STREAM."
  (format stream " A=$~2,'0X X=$~2,'0X Y=$~2,'0X SP=$~2,'0X P=~A  cyc=~D~%"
          (cpu-a cpu) (cpu-x cpu) (cpu-y cpu) (cpu-sp cpu)
          (format-flags (cpu-p cpu))
          (cpu-cycles cpu)))

(defun show-current (dbg &optional (stream *standard-output*))
  "Affiche l'instruction au PC courant puis les registres.
   Si une debug-map est disponible et que le fichier source est lisible,
   affiche aussi le texte de la ligne source."
  (let* ((cpu (debugger-cpu dbg))
         (mem (cpu-mem cpu))
         (pc  (cpu-pc cpu)))
    (multiple-value-bind (mnemonic operand size)
        (funcall (debugger-disasm-fn dbg) mem pc)
      ;; Octets hex (1–3), cadrés sur 8 caractères
      (let* ((hex-str (format nil "~{~2,'0X~^ ~}"
                              (loop for i from 0 below size
                                    collect (aref mem (logand (+ pc i) #xFFFF)))))
             ;; Source-loc optionnelle depuis la debug-map
             (src (when (debugger-debug-map dbg)
                    (debug-map-get (debugger-debug-map dbg) pc)))
             ;; Texte de la ligne source (quand fichier disponible)
             (src-text (when (and src (cl-asm/ir:source-loc-file src))
                         (%get-source-line dbg
                                           (cl-asm/ir:source-loc-file src)
                                           (cl-asm/ir:source-loc-line src)))))
        ;; Ligne source optionnelle au-dessus de la désassemblée
        (when src-text
          (format stream "  ; ~A:~D | ~A~%"
                  (cl-asm/ir:source-loc-file src)
                  (cl-asm/ir:source-loc-line src)
                  (string-trim '(#\Space #\Tab) src-text)))
        (format stream "$~4,'0X  ~8A  ~A~@[ ~A~]~@[  ; ~A~]~%"
                pc hex-str mnemonic
                (when (string/= operand "") operand)
                ;; Affiche loc uniquement quand pas de texte source (évite la redondance)
                (when (and src (not src-text))
                  (cl-asm/ir:source-loc->string src)))))
    (show-registers cpu stream)))

(defun show-memory (cpu addr &optional (count 16) (stream *standard-output*))
  "Affiche COUNT octets à partir de ADDR en format hexadécimal."
  (let ((mem (cpu-mem cpu)))
    (loop for row from 0 below (ceiling count 16)
          for base = (logand (+ addr (* row 16)) #xFFFF)
          do (format stream "$~4,'0X  " base)
             (dotimes (col (min 16 (- count (* row 16))))
               (format stream "~2,'0X " (aref mem (logand (+ base col) #xFFFF))))
             (terpri stream))))

(defun show-disasm (dbg addr &optional (count 8) (stream *standard-output*))
  "Désassemble COUNT instructions à partir de ADDR."
  (let ((mem (cpu-mem (debugger-cpu dbg)))
        (pc  addr))
    (dotimes (_ count)
      (multiple-value-bind (mnemonic operand size)
          (funcall (debugger-disasm-fn dbg) mem pc)
        (let ((hex-str (format nil "~{~2,'0X~^ ~}"
                               (loop for i from 0 below size
                                     collect (aref mem (logand (+ pc i) #xFFFF))))))
          (format stream "$~4,'0X  ~8A  ~A~@[ ~A~]~%"
                  pc hex-str mnemonic (when (string/= operand "") operand)))
        (incf pc size)))))

(defun show-help (&optional (stream *standard-output*))
  (format stream "Commandes du débogueur 6502 :~%")
  (format stream "  s  / step              Exécuter une instruction~%")
  (format stream "  n  / next              Step-over (saute les JSR)~%")
  (format stream "  c  / continue          Continuer jusqu'au breakpoint/watchpoint/BRK~%")
  (format stream "  b  $ADDR [condition]   Poser un breakpoint (condition : expr Lisp, cpu lié)~%")
  (format stream "  d  $ADDR               Supprimer un breakpoint~%")
  (format stream "  lb                     Lister les breakpoints~%")
  (format stream "  w  $ADDR [read|write|rw]  Poser un watchpoint (défaut write)~%")
  (format stream "  dw $ADDR               Supprimer un watchpoint~%")
  (format stream "  lw                     Lister les watchpoints~%")
  (format stream "  r  / regs              Afficher les registres~%")
  (format stream "  m  $ADDR [N]           Afficher N octets mémoire (défaut 16)~%")
  (format stream "  x  [$ADDR] [N]         Désassembler N instructions (défaut 8)~%")
  (format stream "  h  / help              Cette aide~%")
  (format stream "  q  / quit              Quitter le débogueur~%")
  (format stream "  (entrée vide = répéter la dernière commande)~%"))


;;; --------------------------------------------------------------------------
;;;  Parsing des entrées REPL
;;; --------------------------------------------------------------------------

(defun split-whitespace (str)
  "Découpe STR sur les espaces/tabs, retourne une liste de tokens non-vides."
  (let (tokens start)
    (dotimes (i (length str))
      (let ((c (char str i)))
        (if (member c '(#\Space #\Tab))
            (when start
              (push (subseq str start i) tokens)
              (setf start nil))
            (unless start (setf start i)))))
    (when start (push (subseq str start) tokens))
    (nreverse tokens)))

(defun parse-hex (str)
  "Parse '$XXXX' ou 'XXXX' (hexadécimal). Retourne NIL si invalide."
  (let ((s (string-trim '(#\Space #\Tab) str)))
    (when (and (> (length s) 0) (char= (char s 0) #\$))
      (setf s (subseq s 1)))
    (when (> (length s) 0)
      (handler-case (parse-integer s :radix 16)
        (error () nil)))))

(defun parse-count (str &optional (default 8))
  "Parse un entier décimal ou hexadécimal. Retourne DEFAULT si invalide."
  (when str
    (or (parse-hex str)
        (handler-case (parse-integer str)
          (error () nil))))
  (or (when str
        (or (parse-hex str)
            (handler-case (parse-integer str)
              (error () nil))))
      default))


;;; --------------------------------------------------------------------------
;;;  Noyau d'exécution
;;; --------------------------------------------------------------------------

(defun %check-breakpoint (dbg)
  "Retourne :BREAKPOINT si un breakpoint est actif au PC courant, sinon NIL."
  (let* ((cpu (debugger-cpu dbg))
         (bp  (gethash (cpu-pc cpu) (debugger-breakpoints dbg))))
    (and bp (breakpoint-hit-p bp cpu) :breakpoint)))

(defun %step-one (dbg)
  "Exécute une instruction atomique. N'affiche rien.
   Retourne :ok | :brk | :breakpoint | :watchpoint | :illegal."
  (handler-case
      (progn
        (step-cpu (debugger-cpu dbg))
        (or (%check-breakpoint dbg) :ok))
    (cpu-watchpoint (c)
      (setf (debugger-last-watchpoint dbg)
            (list (cpu-watchpoint-address c) (cpu-watchpoint-kind c)))
      :watchpoint)
    (cpu-break ()
      :brk)
    (cpu-illegal-opcode (c)
      (declare (ignore c))
      :illegal)))

(defun debugger-step (dbg &optional (stream *standard-output*))
  "Exécute une instruction et affiche l'état résultant.
   Retourne :ok | :brk | :breakpoint | :watchpoint | :illegal."
  (let ((result (%step-one dbg)))
    (when stream (show-current dbg stream))
    result))

(defun debugger-next (dbg &optional (stream *standard-output*))
  "Step-over : si l'instruction courante est JSR, continue jusqu'à l'adresse
   suivante (après le JSR). Sinon, équivalent à STEP.
   Retourne :ok | :brk | :breakpoint | :watchpoint | :illegal."
  (let* ((cpu (debugger-cpu dbg))
         (pc  (cpu-pc cpu)))
    (multiple-value-bind (mnemonic _op size)
        (funcall (debugger-disasm-fn dbg) (cpu-mem cpu) pc)
      (declare (ignore _op))
      (if (string= mnemonic "JSR")
          ;; Breakpoint temporaire à PC+3 (taille JSR abs = 3)
          (let* ((return-addr (logand (+ pc size) #xFFFF))
                 (had-bp (gethash return-addr (debugger-breakpoints dbg))))
            (unless had-bp
              (set-breakpoint dbg return-addr))
            (let ((result (loop (let ((r (%step-one dbg)))
                                  (unless (eq r :ok) (return r))))))
              (unless had-bp
                (clear-breakpoint dbg return-addr))
              (when stream (show-current dbg stream))
              ;; :breakpoint sur le BP temporaire → :ok (détail d'implémentation)
              (if (and (eq result :breakpoint)
                       (= (cpu-pc (debugger-cpu dbg)) return-addr)
                       (null had-bp))
                  :ok
                  result)))
          ;; Pas un JSR : simple step
          (debugger-step dbg stream)))))

(defun debugger-continue (dbg &optional (stream *standard-output*))
  "Exécute jusqu'au prochain breakpoint, watchpoint, BRK ou opcode illégal.
   Retourne :brk | :breakpoint | :watchpoint | :illegal."
  (let ((result (loop (let ((r (%step-one dbg)))
                        (unless (eq r :ok) (return r))))))
    (when stream
      (case result
        (:brk
         (format stream "~%[BRK] à $~4,'0X~%" (cpu-pc (debugger-cpu dbg))))
        (:breakpoint
         (format stream "~%[BREAKPOINT] à $~4,'0X~%" (cpu-pc (debugger-cpu dbg))))
        (:watchpoint
         (let ((wp (debugger-last-watchpoint dbg)))
           (format stream "~%[WATCHPOINT ~A] à $~4,'0X (PC=$~4,'0X)~%"
                   (second wp) (first wp) (cpu-pc (debugger-cpu dbg)))))
        (:illegal
         (format stream "~%[OPCODE ILLÉGAL] à $~4,'0X~%" (cpu-pc (debugger-cpu dbg)))))
      (show-current dbg stream))
    result))


;;; --------------------------------------------------------------------------
;;;  REPL interactif
;;; --------------------------------------------------------------------------

(defun debugger-repl (dbg &key (input *standard-input*) (output *standard-output*))
  "Lance la boucle interactive du débogueur 6502.
   DBG : session créée avec MAKE-DEBUGGER.
   Retourne :quit | :brk | :illegal selon la raison de sortie."
  (format output "~%=== Débogueur 6502 — cl-asm v0.7.0 ===~%")
  (format output "Tapez 'h' pour l'aide.~%~%")
  (show-current dbg output)
  (let ((last-cmd "s"))
    (loop
      (format output "~%dbg> ")
      (force-output output)
      (let* ((raw (string-trim '(#\Space #\Tab #\Newline #\Return)
                               (or (read-line input nil "") "")))
             (line (if (string= raw "") last-cmd raw))
             (tokens (or (split-whitespace line) (list "s")))
             (cmd  (first tokens))
             (args (rest tokens)))
        (setf last-cmd line)
        (cond

          ;; --- Quit ---
          ((member cmd '("q" "quit") :test #'string=)
           (format output "Au revoir.~%")
           (return :quit))

          ;; --- Aide ---
          ((member cmd '("h" "help") :test #'string=)
           (show-help output))

          ;; --- Step ---
          ((member cmd '("s" "step") :test #'string=)
           (let ((r (debugger-step dbg output)))
             (cond
               ((eq r :watchpoint)
                (let ((wp (debugger-last-watchpoint dbg)))
                  (format output "~%[WATCHPOINT ~A] à $~4,'0X~%" (second wp) (first wp))))
               ((member r '(:brk :illegal))
                (format output "~%[FIN : ~A]~%" r)
                (return r)))))

          ;; --- Next (step-over) ---
          ((member cmd '("n" "next") :test #'string=)
           (let ((r (debugger-next dbg output)))
             (cond
               ((eq r :watchpoint)
                (let ((wp (debugger-last-watchpoint dbg)))
                  (format output "~%[WATCHPOINT ~A] à $~4,'0X~%" (second wp) (first wp))))
               ((member r '(:brk :illegal))
                (format output "~%[FIN : ~A]~%" r)
                (return r)))))

          ;; --- Continue ---
          ((member cmd '("c" "continue") :test #'string=)
           (let ((r (debugger-continue dbg output)))
             (when (member r '(:brk :illegal))
               (format output "~%[FIN : ~A]~%" r)
               (return r))))

          ;; --- Poser breakpoint ---
          ((member cmd '("b" "break") :test #'string=)
           (if (null args)
               (format output "Usage : b $ADDR [expr-condition]~%")
               (let ((addr (parse-hex (first args))))
                 (if (null addr)
                     (format output "Adresse invalide : ~A~%" (first args))
                     (let* (;; condition optionnelle : le reste des tokens rejoint et évalué
                            (cond-str (when (rest args)
                                        (format nil "~{~A~^ ~}" (rest args))))
                            (condition nil)
                            (cond-ok   t))
                       (when cond-str
                         (handler-case
                             (let ((form (read-from-string cond-str)))
                               (setf condition
                                     (eval `(lambda (cpu)
                                              (declare (ignorable cpu))
                                              ,form))))
                           (error (e)
                             (format output "Condition invalide : ~A~%" e)
                             (setf cond-ok nil))))
                       (when cond-ok
                         (set-breakpoint dbg addr :condition condition)
                         (if condition
                             (format output "Breakpoint conditionnel posé à $~4,'0X~%" addr)
                             (format output "Breakpoint posé à $~4,'0X~%" addr))))))))

          ;; --- Supprimer breakpoint ---
          ((member cmd '("d" "delete") :test #'string=)
           (if (null args)
               (format output "Usage : d $ADDR~%")
               (let ((addr (parse-hex (first args))))
                 (if addr
                     (if (clear-breakpoint dbg addr)
                         (format output "Breakpoint supprimé à $~4,'0X~%" addr)
                         (format output "Aucun breakpoint à $~4,'0X~%" addr))
                     (format output "Adresse invalide : ~A~%" (first args))))))

          ;; --- Lister les breakpoints ---
          ((member cmd '("lb" "list-breaks") :test #'string=)
           (let ((bps (list-breakpoints dbg)))
             (if (null bps)
                 (format output "Aucun breakpoint.~%")
                 (dolist (bp bps)
                   (format output "  $~4,'0X~:[~; [condition]~]~@[  (désactivé)~]~%"
                           (breakpoint-address bp)
                           (breakpoint-condition bp)
                           (not (breakpoint-enabled bp)))))))

          ;; --- Poser watchpoint ---
          ((member cmd '("w" "watch") :test #'string=)
           (if (null args)
               (format output "Usage : w $ADDR [read|write|rw]~%")
               (let ((addr (parse-hex (first args)))
                     (kind (let ((s (second args)))
                             (cond ((null s) :write)
                                   ((string= s "read")  :read)
                                   ((string= s "write") :write)
                                   ((string= s "rw")    :rw)
                                   (t nil)))))
                 (cond
                   ((null addr)
                    (format output "Adresse invalide : ~A~%" (first args)))
                   ((null kind)
                    (format output "Kind invalide : ~A (read|write|rw)~%" (second args)))
                   (t
                    (set-watchpoint dbg addr :kind kind)
                    (format output "Watchpoint ~A posé à $~4,'0X~%" kind addr))))))

          ;; --- Supprimer watchpoint ---
          ((member cmd '("dw" "delete-watch") :test #'string=)
           (if (null args)
               (format output "Usage : dw $ADDR~%")
               (let ((addr (parse-hex (first args))))
                 (if addr
                     (progn (clear-watchpoint dbg addr)
                            (format output "Watchpoint supprimé à $~4,'0X~%" addr))
                     (format output "Adresse invalide : ~A~%" (first args))))))

          ;; --- Lister les watchpoints ---
          ((member cmd '("lw" "list-watches") :test #'string=)
           (let ((wps (list-watchpoints dbg)))
             (if (null wps)
                 (format output "Aucun watchpoint.~%")
                 (dolist (wp wps)
                   (format output "  $~4,'0X  ~A~@[  (désactivé)~]~%"
                           (watchpoint-address wp)
                           (watchpoint-kind wp)
                           (not (watchpoint-enabled wp)))))))

          ;; --- Registres ---
          ((member cmd '("r" "regs" "registers") :test #'string=)
           (show-registers (debugger-cpu dbg) output))

          ;; --- Mémoire ---
          ((member cmd '("m" "mem" "memory") :test #'string=)
           (if (null args)
               (format output "Usage : m $ADDR [N]~%")
               (let ((addr (parse-hex (first args))))
                 (if addr
                     (show-memory (debugger-cpu dbg) addr
                                  (parse-count (second args) 16) output)
                     (format output "Adresse invalide : ~A~%" (first args))))))

          ;; --- Désassembler ---
          ((member cmd '("x" "disasm") :test #'string=)
           (let* ((addr-or-count (first args))
                  (addr  (if addr-or-count (parse-hex addr-or-count) nil))
                  (count (parse-count (second args) 8)))
             (show-disasm dbg
                          (or addr (cpu-pc (debugger-cpu dbg)))
                          count output)))

          ;; --- Commande inconnue ---
          (t
           (format output "Commande inconnue : ~S (tapez 'h' pour l'aide)~%" cmd)))))))
