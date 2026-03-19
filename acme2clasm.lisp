; -*- coding: utf-8 -*-
;;;
;;; acme2clasm.lisp -- Convertit un fichier source ACME vers la syntaxe cl-asm.
;;;
;;; Usage (via le wrapper shell acme2clasm) :
;;;   ./acme2clasm source.s          -> source.asm
;;;   ./acme2clasm source.s -o out.asm
;;;   ./acme2clasm source.s --report
;;;
;;; Compatible SBCL et CLISP.
;;;

;;; --------------------------------------------------------------------------
;;; Portabilité SBCL / CLISP
;;; --------------------------------------------------------------------------

(defun get-script-args ()
  "Retourne la liste des arguments passés au script (sans le nom du programme)."
  #+sbcl
  (let ((argv sb-ext:*posix-argv*))
    ;; Sous --script, argv = ("sbcl" "--script" "fichier.lisp" "--" arg1 arg2 ...)
    ;; On cherche "--" et on prend ce qui suit
    (let ((sep (member "--" argv :test #'string=)))
      (if sep (rest sep) nil)))
  #+clisp
  ext:*args*
  #+ecl
  (rest (si:command-args))
  #-(or sbcl clisp ecl)
  (error "Implémentation Lisp non supportée (utiliser SBCL, CLISP ou ECL)"))

(defun exit-lisp (code)
  #+sbcl  (sb-ext:exit :code code)
  #+clisp (ext:exit code)
  #+ecl   (si:exit code)
  #-(or sbcl clisp ecl) (error "exit non disponible"))

;;; --------------------------------------------------------------------------
;;; Utilitaires chaînes
;;; --------------------------------------------------------------------------

(defun string-prefix-p (prefix str)
  "Vrai si STR commence par PREFIX (insensible à la casse)."
  (let ((pl (length prefix))
        (sl (length str)))
    (and (<= pl sl)
         (string-equal prefix (subseq str 0 pl)))))

(defun trim (s)
  (string-trim '(#\Space #\Tab) s))

(defun starts-with-char (str ch)
  (and (> (length str) 0) (char= (char str 0) ch)))

(defun string-replace-all (str old new)
  "Remplace toutes les occurrences de OLD par NEW dans STR."
  (let ((result str)
        (olen (length old)))
    (loop
      (let ((pos (search old result)))
        (if pos
            (setf result (concatenate 'string
                                      (subseq result 0 pos)
                                      new
                                      (subseq result (+ pos olen))))
            (return result))))))

(defun to-ascii (str)
  "Remplace les caractères non-ASCII par '?' dans STR."
  (map 'string
       (lambda (c) (if (< (char-code c) 128) c #\?))
       str))

;;; --------------------------------------------------------------------------
;;; Mnémoniques 6502/45GS02 connus
;;; --------------------------------------------------------------------------

(defparameter *mnemonics*
  (let ((ht (make-hash-table :test 'equal)))
    (dolist (m '("LDA" "LDX" "LDY" "STA" "STX" "STY" "LDZ" "STZ"
                 "ADC" "SBC" "CMP" "CPX" "CPY"
                 "AND" "ORA" "EOR" "BIT"
                 "INC" "DEC" "INX" "INY" "INZ" "DEX" "DEY" "DEZ"
                 "ASL" "LSR" "ROL" "ROR"
                 "JMP" "JSR" "RTS" "RTI" "BRK"
                 "BCC" "BCS" "BEQ" "BNE" "BMI" "BPL" "BVC" "BVS"
                 "LBCC" "LBCS" "LBEQ" "LBNE" "LBMI" "LBPL" "LBVC" "LBVS"
                 "CLC" "SEC" "CLI" "SEI" "CLD" "SED" "CLV"
                 "TAX" "TAY" "TXA" "TYA" "TSX" "TXS" "TAZ" "TZA" "TAB" "TBA"
                 "PHA" "PLA" "PHP" "PLP" "PHZ" "PLZ"
                 "NOP" "MAP" "EOM" "NEG" "ASR"
                 "INW" "DEW" "ASW" "ROW"
                 "LDQ" "STQ" "ADCQ" "SBCQ" "ANDQ" "ORAQ" "EORQ"
                 "ASLQ" "LSRQ" "ROLQ" "RORQ" "ASRQ" "BITQ" "CMPQ"))
      (setf (gethash m ht) t))
    ht))

(defun mnemonic-p (s)
  (gethash (string-upcase s) *mnemonics*))

;;; --------------------------------------------------------------------------
;;; Regex léger : correspondance de patterns simples
;;; Utilise CL-PPCRE si disponible, sinon une recherche basique.
;;; On implémente nos propres helpers pour rester sans dépendance.
;;; --------------------------------------------------------------------------

;;; Pour rester compatible sans CL-PPCRE, on utilise des fonctions
;;; de parsing manuel sur les patterns récurrents.

(defun skip-whitespace (str &optional (start 0))
  "Retourne l'index du premier caractère non-blanc à partir de START."
  (let ((len (length str)))
    (loop for i from start below len
          while (member (char str i) '(#\Space #\Tab))
          finally (return i))))

(defun read-identifier (str &optional (start 0))
  "Lit un identifiant [A-Za-z_][A-Za-z0-9_]* à partir de START.
   Retourne (identifiant . fin) ou NIL."
  (let ((len (length str)))
    (when (< start len)
      (let ((c (char str start)))
        (when (or (alpha-char-p c) (char= c #\_))
          (let ((end (loop for i from (1+ start) below len
                           while (let ((cc (char str i)))
                                   (or (alphanumericp cc) (char= cc #\_)))
                           finally (return i))))
            (cons (subseq str start end) end)))))))

(defun strip-comment (str)
  "Supprime le commentaire de fin de ligne (;...) de STR."
  (let ((pos (position #\; str)))
    (if pos
        (trim (subseq str 0 pos))
        str)))

;;; --------------------------------------------------------------------------
;;; Conversion des opérateurs ACME dans les expressions
;;; --------------------------------------------------------------------------

(defun convert-expression (expr)
  "Remplace AND/OR/EOR/XOR entourés d'opérandes par &/|/^."
  (flet ((replace-op (s old new)
           ;; Remplace ' AND '/' OR ' etc. seulement entre opérandes
           (string-replace-all s (concatenate 'string " " old " ")
                                  (concatenate 'string " " new " "))))
    (let ((r expr))
      (setf r (replace-op r "AND" "&"))
      (setf r (replace-op r "OR"  "|"))
      (setf r (replace-op r "EOR" "^"))
      (setf r (replace-op r "XOR" "^"))
      r)))

;;; --------------------------------------------------------------------------
;;; Conversion PETSCII
;;; --------------------------------------------------------------------------

(defun pet-string-to-bytes (s)
  "Convertit le contenu d'un !pet \"...\" en liste d'octets décimaux."
  (let ((result '())
        (i 0)
        (len (length s)))
    (loop while (< i len) do
      (let ((ch (char s i)))
        (cond
          ((and (char= ch #\\) (< (1+ i) len))
           (let ((nxt (char s (1+ i))))
             (cond
               ((char= nxt #\n)  (push #x0D result) (incf i 2))
               ((char= nxt #\t)  (push #x09 result) (incf i 2))
               ((char= nxt #\\) (push (char-code #\\) result) (incf i 2))
               ((char= nxt #\") (push (char-code #\") result) (incf i 2))
               ((and (char= nxt #\x) (< (+ i 3) len))
                (push (parse-integer s :start (+ i 2) :end (+ i 4) :radix 16)
                      result)
                (incf i 4))
               (t (push (char-code ch) result) (incf i)))))
          (t (push (char-code ch) result) (incf i)))))
    (nreverse result)))

;;; --------------------------------------------------------------------------
;;; Extracteur d'indent
;;; --------------------------------------------------------------------------

(defun extract-indent (line)
  "Retourne le préfixe d'espaces/tabs de LINE."
  (let ((i (skip-whitespace line 0)))
    (subseq line 0 i)))

;;; --------------------------------------------------------------------------
;;; Convertisseur principal
;;; --------------------------------------------------------------------------

(defstruct converter
  source-path
  (warnings '())   ; liste de (lineno . message)
  (in-macro nil)
  (macro-depth 0))

(defun conv-warn (conv lineno msg)
  (push (cons lineno msg) (converter-warnings conv)))

;;; Helpers de matching sur une ligne (après strip)

(defun match-directive (stripped directive)
  "Vrai si STRIPPED commence par DIRECTIVE (insensible casse) suivi d'espace ou fin."
  (let ((dl (length directive))
        (sl (length stripped)))
    (and (string-prefix-p directive stripped)
         (or (= sl dl)
             (member (char stripped dl) '(#\Space #\Tab))))))

(defun after-directive (stripped directive)
  "Retourne le reste de la ligne après DIRECTIVE + espaces."
  (trim (subseq stripped (length directive))))

(defun convert-line (conv lineno line)
  "Convertit une ligne ACME. Retourne la ligne convertie (string)."
  (let* ((line (string-right-trim '(#\Return #\Newline) line))
         (stripped (trim line))
         (indent (extract-indent line)))

    ;; Ligne vide
    (when (= (length stripped) 0)
      (return-from convert-line ""))

    ;; Commentaire pur
    (when (starts-with-char stripped #\;)
      (return-from convert-line line))

    ;; ------------------------------------------------------------------
    ;; !cpu
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!CPU")
      (let ((cpu (string-downcase (after-directive stripped "!cpu"))))
        (cond
          ((member cpu '("m65" "45gs02") :test #'string=)
           (return-from convert-line
             (format nil "~A; target: 45gs02 ; [acme2clasm] !cpu ~A" indent cpu)))
          ((member cpu '("6502" "6510" "nmos6502" "65c02") :test #'string=)
           (return-from convert-line
             (format nil "~A; [acme2clasm] !cpu ~A -> cible 6502 (defaut)" indent cpu)))
          (t
           (conv-warn conv lineno (format nil "!cpu ~A : cible inconnue" cpu))
           (return-from convert-line
             (format nil "~A; TODO [acme2clasm] !cpu ~A : cible inconnue" indent cpu))))))

    ;; ------------------------------------------------------------------
    ;; !to "fichier", format
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!TO")
      (let* ((rest (after-directive stripped "!to"))
             (q1 (position #\" rest))
             (q2 (and q1 (position #\" rest :start (1+ q1)))))
        (if (and q1 q2)
            (let* ((fname (subseq rest (1+ q1) q2))
                   (after-q (trim (subseq rest (1+ q2))))
                   (fmt (if (and (> (length after-q) 0)
                                 (char= (char after-q 0) #\,))
                            (trim (subseq after-q 1))
                            "prg")))
              (return-from convert-line
                (format nil "~A; [acme2clasm] sortie : ~A (format ~A)~%~A; Assembler avec : ./cl-asm SOURCE -o ~A"
                        indent fname fmt indent fname)))
            (return-from convert-line
              (format nil "~A; TODO [acme2clasm] !to ~A" indent rest)))))

    ;; ------------------------------------------------------------------
    ;; !addr NOM = VALEUR
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!ADDR")
      (let* ((rest (after-directive stripped "!addr"))
             (eq-pos (position #\= rest)))
        (if eq-pos
            (let ((name (trim (subseq rest 0 eq-pos)))
                  (val  (strip-comment (trim (subseq rest (1+ eq-pos))))))
              (return-from convert-line
                (format nil "~A~A = ~A" indent name (convert-expression val))))
            (return-from convert-line
              (format nil "~A; TODO [acme2clasm] !addr ~A" indent rest)))))

    ;; ------------------------------------------------------------------
    ;; !byte / !8
    ;; ------------------------------------------------------------------
    (when (or (match-directive (string-upcase stripped) "!BYTE")
              (match-directive (string-upcase stripped) "!8"))
      (let ((rest (if (match-directive (string-upcase stripped) "!BYTE")
                      (after-directive stripped "!byte")
                      (after-directive stripped "!8"))))
        (return-from convert-line
          (format nil "~A.byte ~A" indent (convert-expression rest)))))

    ;; ------------------------------------------------------------------
    ;; !word / !16
    ;; ------------------------------------------------------------------
    (when (or (match-directive (string-upcase stripped) "!WORD")
              (match-directive (string-upcase stripped) "!16"))
      (let ((rest (if (match-directive (string-upcase stripped) "!WORD")
                      (after-directive stripped "!word")
                      (after-directive stripped "!16"))))
        (return-from convert-line
          (format nil "~A.word ~A" indent (convert-expression rest)))))

    ;; ------------------------------------------------------------------
    ;; !32
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!32")
      (let ((rest (after-directive stripped "!32")))
        (return-from convert-line
          (format nil "~A.dword ~A" indent (convert-expression rest)))))

    ;; ------------------------------------------------------------------
    ;; !text
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!TEXT")
      (let ((rest (after-directive stripped "!text")))
        (return-from convert-line
          (format nil "~A.text ~A" indent rest))))

    ;; ------------------------------------------------------------------
    ;; !pet "..."
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!PET")
      (let* ((rest (after-directive stripped "!pet"))
             (q1 (position #\" rest))
             (q2 (and q1 (position #\" rest :start (1+ q1)))))
        (if (and q1 q2)
            (let* ((content (subseq rest (1+ q1) q2))
                   (codes (handler-case (pet-string-to-bytes content)
                            (error () nil))))
              (if codes
                  (return-from convert-line
                    (format nil "~A.byte ~A ; [acme2clasm] !pet \"~A\""
                            indent
                            (format nil "~{$~2,'0X~^, ~}" codes)
                            content))
                  (progn
                    (conv-warn conv lineno (format nil "!pet : conversion impossible de \"~A\"" content))
                    (return-from convert-line
                      (format nil "~A; TODO !pet \"~A\"" indent content)))))
            (return-from convert-line
              (format nil "~A; TODO [acme2clasm] !pet ~A" indent rest)))))

    ;; ------------------------------------------------------------------
    ;; !fill
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!FILL")
      (let ((rest (after-directive stripped "!fill")))
        (return-from convert-line
          (format nil "~A.fill ~A" indent (convert-expression rest)))))

    ;; ------------------------------------------------------------------
    ;; !align
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!ALIGN")
      (let ((rest (after-directive stripped "!align")))
        (return-from convert-line
          (format nil "~A.align ~A" indent (convert-expression rest)))))

    ;; ------------------------------------------------------------------
    ;; !source
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!SOURCE")
      (let* ((rest (after-directive stripped "!source"))
             (q1 (position #\" rest))
             (q2 (and q1 (position #\" rest :start (1+ q1))))
             (fname (if (and q1 q2) (subseq rest (1+ q1) q2) rest)))
        (conv-warn conv lineno (format nil "!source \"~A\" : inclusion manuelle requise" fname))
        (return-from convert-line
          (format nil "~A; TODO [acme2clasm] inclure manuellement : ~A" indent fname))))

    ;; ------------------------------------------------------------------
    ;; !binary
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!BINARY")
      (let* ((rest (after-directive stripped "!binary"))
             (q1 (position #\" rest))
             (q2 (and q1 (position #\" rest :start (1+ q1))))
             (fname (if (and q1 q2) (subseq rest (1+ q1) q2) rest)))
        (conv-warn conv lineno (format nil "!binary \"~A\" : inclusion manuelle requise" fname))
        (return-from convert-line
          (format nil "~A; TODO [acme2clasm] inclure manuellement (binaire) : ~A" indent fname))))

    ;; ------------------------------------------------------------------
    ;; !macro NOM { ...
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!MACRO")
      (let* ((rest (after-directive stripped "!macro"))
             ;; Supprimer le { éventuel en fin
             (rest (string-right-trim '(#\Space #\Tab #\{) rest))
             (id (read-identifier rest 0))
             (name (if id (car id) rest))
             (params (if id (trim (subseq rest (cdr id))) "")))
        (setf (converter-in-macro conv) t)
        (setf (converter-macro-depth conv) 1)
        (return-from convert-line
          (if (> (length params) 0)
              (format nil "~A.macro ~A ~A" indent name params)
              (format nil "~A.macro ~A" indent name)))))

    ;; ------------------------------------------------------------------
    ;; } fermant une macro
    ;; ------------------------------------------------------------------
    (when (and (converter-in-macro conv)
               (string= stripped "}"))
      (setf (converter-in-macro conv) nil)
      (setf (converter-macro-depth conv) 0)
      (return-from convert-line (format nil "~A.endmacro" indent)))

    ;; ------------------------------------------------------------------
    ;; !if EXPR {
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!IF")
      (let* ((rest (after-directive stripped "!if"))
             ;; Supprimer le { éventuel en fin
             (rest (string-right-trim '(#\Space #\Tab #\{) rest))
             (expr (trim rest)))
        (return-from convert-line
          (format nil "~A.if ~A" indent (convert-expression expr)))))

    ;; ------------------------------------------------------------------
    ;; !else
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!ELSE")
      (return-from convert-line (format nil "~A.else" indent)))

    ;; ------------------------------------------------------------------
    ;; !zone
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!ZONE")
      (conv-warn conv lineno "!zone : pas d'equivalent direct, ignore")
      (return-from convert-line
        (format nil "~A; [acme2clasm] !zone ignore" indent)))

    ;; ------------------------------------------------------------------
    ;; !pseudopc
    ;; ------------------------------------------------------------------
    (when (match-directive (string-upcase stripped) "!PSEUDOPC")
      (conv-warn conv lineno "!pseudopc : pas d'equivalent direct")
      (return-from convert-line
        (format nil "~A; TODO [acme2clasm] !pseudopc : conversion manuelle" indent)))

    ;; ------------------------------------------------------------------
    ;; Directive inconnue commençant par !
    ;; ------------------------------------------------------------------
    (when (starts-with-char stripped #\!)
      (let* ((id (read-identifier stripped 1))
             (directive (if id (format nil "!~A" (car id)) "!")))
        (conv-warn conv lineno (format nil "~A : directive inconnue, ignoree" directive))
        (return-from convert-line
          (format nil "~A; TODO [acme2clasm] ~A" indent stripped))))

    ;; ------------------------------------------------------------------
    ;; * = ADDR  ->  .org ADDR
    ;; ------------------------------------------------------------------
    (when (and (starts-with-char stripped #\*)
               (> (length stripped) 1)
               (char= (char stripped 1) #\=))
      (let ((addr (strip-comment (trim (subseq stripped 2)))))
        (return-from convert-line
          (format nil "~A.org ~A" indent (convert-expression addr)))))
    (when (and (starts-with-char stripped #\*)
               (> (length stripped) 1)
               (member (char stripped 1) '(#\Space #\Tab)))
      (let* ((rest (trim (subseq stripped 1))))
        (when (and (> (length rest) 0) (char= (char rest 0) #\=))
          (let ((addr (strip-comment (trim (subseq rest 1)))))
            (return-from convert-line
              (format nil "~A.org ~A" indent (convert-expression addr)))))))

    ;; ------------------------------------------------------------------
    ;; Labels sans ':', avec ':' ou avec '::' et instructions normales
    ;; ------------------------------------------------------------------
    (when (and (> (length line) 0)
               (not (member (char line 0) '(#\Space #\Tab))))
      ;; Ligne commençant en colonne 0 : label ou instruction
      (let ((id (read-identifier stripped 0)))
        (when id
          (let* ((name (car id))
                 (after-name (subseq stripped (cdr id)))
                 ;; Consommer les ':' éventuels (label: ou label::)
                 (rest (trim (string-left-trim '(#\:) after-name))))
            (when (not (mnemonic-p name))
              ;; Assignation : NOM = EXPR
              (when (and (> (length rest) 0) (char= (char rest 0) #\=))
                (let ((val (strip-comment (trim (subseq rest 1)))))
                  (return-from convert-line
                    (format nil "~A~A = ~A" indent name (convert-expression val)))))
              ;; Label (avec ou sans ':' dans le source)
              (return-from convert-line
                (if (> (length rest) 0)
                    (format nil "~A~A:~%        ~A" indent name (convert-expression rest))
                    (format nil "~A~A:" indent name))))))))

    ;; Ligne d'instruction normale
    (to-ascii (convert-expression line))))

;;; --------------------------------------------------------------------------
;;; Lecture du fichier source
;;; --------------------------------------------------------------------------

(defun read-source-lines (path)
  "Lit le fichier PATH et retourne la liste des lignes."
  (with-open-file (in path :direction :input
                          :external-format
                          #+sbcl  :utf-8
                          #+clisp charset:utf-8
                          #+ecl   :utf-8
                          #-(or sbcl clisp ecl) :default
                          :if-does-not-exist nil)
    (unless in
      (error "Fichier introuvable : ~A" path))
    (loop for line = (read-line in nil nil)
          while line
          collect line)))

;;; --------------------------------------------------------------------------
;;; Conversion complète
;;; --------------------------------------------------------------------------

(defun convert-file (source-path)
  "Convertit le fichier ACME. Retourne (values lignes warnings)."
  (let* ((conv (make-converter :source-path source-path))
         (lines (handler-case (read-source-lines source-path)
                  (error (e)
                    (format *error-output* "Erreur lecture : ~A~%" e)
                    (exit-lisp 1))))
         (result '()))
    (push "; -*- coding: utf-8 -*-" result)
    (push (format nil "; Converti depuis ~A par acme2clasm"
                  (file-namestring source-path)) result)
    (push "; Verifier les lignes marquees TODO avant assemblage" result)
    (push "" result)
    (loop for line in lines
          for lineno from 1
          do (push (convert-line conv lineno line) result))
    (values (nreverse result)
            (nreverse (converter-warnings conv)))))

(defun format-report (warnings)
  (if (null warnings)
      "Conversion terminee sans avertissement."
      (format nil "~A avertissement(s) :~%~{  Ligne ~4D : ~A~%~}"
              (length warnings)
              (loop for (lineno . msg) in warnings
                    append (list lineno msg)))))

;;; --------------------------------------------------------------------------
;;; Nom de fichier de sortie par défaut
;;; --------------------------------------------------------------------------

(defun default-output (input-path)
  "Remplace l'extension de INPUT-PATH par .asm."
  (let* ((s (namestring input-path))
         (dot (position #\. s :from-end t)))
    (if dot
        (concatenate 'string (subseq s 0 dot) ".asm")
        (concatenate 'string s ".asm"))))

;;; --------------------------------------------------------------------------
;;; Point d'entrée
;;; --------------------------------------------------------------------------

(defun main ()
  (let ((args (get-script-args)))

    ;; Aide
    (when (or (null args)
              (member "--help" args :test #'string=)
              (member "-h" args :test #'string=))
      (format t "Usage: acme2clasm SOURCE.s [-o SORTIE.asm] [--report]~%")
      (exit-lisp 0))

    ;; Parser les arguments
    (let ((input nil)
          (output nil)
          (show-report nil))
      (loop for i from 0 below (length args)
            for arg = (nth i args)
            do (cond
                 ((or (string= arg "-o") (string= arg "--output"))
                  (setf output (nth (1+ i) args)))
                 ((string= arg "--report")
                  (setf show-report t))
                 ((starts-with-char arg #\-)
                  nil) ; option inconnue, ignorer
                 ((null input)
                  (setf input arg))))

      (unless input
        (format *error-output* "Erreur : fichier source manquant.~%")
        (exit-lisp 1))

      (unless (probe-file input)
        (format *error-output* "Erreur : fichier introuvable : ~A~%" input)
        (exit-lisp 1))

      (let ((out-path (or output (default-output input))))
        ;; Protection : refuser d'écraser le fichier source
        (when (string= (namestring (truename input))
                       (namestring (merge-pathnames out-path)))
          (format *error-output*
                  "Erreur : le fichier de sortie (~A) est identique au fichier source.~%~
                   Utilisez -o pour spécifier un nom de sortie différent.~%" out-path)
          (exit-lisp 1))
        (multiple-value-bind (lines warnings)
            (convert-file input)
          (with-open-file (out out-path :direction :output
                                        :if-exists :supersede
                                        :external-format
                                        #+sbcl  :utf-8
                                        #+clisp charset:utf-8
                                        #+ecl   :utf-8
                                        #-(or sbcl clisp ecl) :default)
            (dolist (line lines)
              (write-line line out)))
          (format t "~A -> ~A~%" input out-path)
          (when (or show-report warnings)
            (format t "~A~%" (format-report warnings))))))))

(main)
