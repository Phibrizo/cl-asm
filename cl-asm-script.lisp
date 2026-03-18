; -*- coding: utf-8 -*-
;;;
;;; cl-asm-script.lisp -- Script ligne de commande pour cl-asm
;;;
;;; Usage (via le wrapper shell cl-asm) :
;;;   ./cl-asm source.asm
;;;   ./cl-asm source.asm -o sortie.prg
;;;   ./cl-asm source.asm -o sortie.bin --format bin
;;;   ./cl-asm source.asm --origin 0xC000
;;;   ./cl-asm source.asm --target 45gs02
;;;   ./cl-asm source.asm --target x16
;;;   ./cl-asm source.asm --target r65c02
;;;   ./cl-asm source.asm -v
;;;
;;; Compatible SBCL, CLISP et ECL.
;;;

;;; --------------------------------------------------------------------------
;;; Portabilité SBCL / CLISP / ECL
;;; --------------------------------------------------------------------------

(defun get-script-args ()
  #+sbcl
  (let ((argv sb-ext:*posix-argv*))
    (let ((sep (member "--" argv :test #'string=)))
      (if sep (rest sep) nil)))
  #+clisp ext:*args*
  #+ecl   (rest (si:command-args))
  #-(or sbcl clisp ecl)
  (error "Implémentation Lisp non supportée (utiliser SBCL, CLISP ou ECL)"))

(defun exit-lisp (code)
  #+sbcl  (sb-ext:exit :code code)
  #+clisp (ext:exit code)
  #+ecl   (si:exit code)
  #-(or sbcl clisp ecl) (error "exit non disponible"))

;;; --------------------------------------------------------------------------
;;; Chargement de ASDF et cl-asm
;;; --------------------------------------------------------------------------

(require :asdf)

(defun find-cl-asm-asd (script-dir)
  "Cherche cl-asm.asd depuis script-dir, puis dans le répertoire courant."
  (let ((candidates (list
                     (merge-pathnames "cl-asm.asd" script-dir)
                     (merge-pathnames "cl-asm.asd" *default-pathname-defaults*))))
    (find-if #'probe-file candidates)))

(defun load-cl-asm (script-dir)
  "Charge cl-asm en cherchant cl-asm.asd depuis le répertoire du script."
  (let ((asd (find-cl-asm-asd script-dir)))
    (if asd
        (let ((dir (make-pathname :name nil :type nil :defaults asd)))
          (pushnew dir asdf:*central-registry* :test #'equal)
          (asdf:load-system "cl-asm" :verbose nil))
        (error "cl-asm.asd introuvable (cherché dans ~A et ~A)"
               script-dir *default-pathname-defaults*))))

;;; --------------------------------------------------------------------------
;;; Utilitaires
;;; --------------------------------------------------------------------------

(defun starts-with (str prefix)
  (and (>= (length str) (length prefix))
       (string= str prefix :end1 (length prefix))))

(defun parse-integer-auto (s)
  "Parse un entier en décimal, hex (0x/$) ou binaire (%/0b)."
  (cond
    ((or (starts-with s "0x") (starts-with s "0X"))
     (parse-integer s :start 2 :radix 16))
    ((starts-with s "$")
     (parse-integer s :start 1 :radix 16))
    ((or (starts-with s "0b") (starts-with s "0B"))
     (parse-integer s :start 2 :radix 2))
    ((starts-with s "%")
     (parse-integer s :start 1 :radix 2))
    (t
     (parse-integer s))))

(defun default-output (input fmt)
  "Retourne le nom de sortie par défaut selon le format."
  (let* ((s (namestring input))
         (dot (position #\. s :from-end t))
         (base (if dot (subseq s 0 dot) s)))
    (concatenate 'string base "." (string-downcase (symbol-name fmt)))))

(defun detect-target (source-path)
  "Détecte la cible depuis les premières lignes du fichier source."
  (with-open-file (in source-path :if-does-not-exist nil)
    (when in
      (loop repeat 10
            for line = (read-line in nil nil)
            while line
            do (cond
                 ((or (search "target: 45gs02" line)
                      (search ":45gs02" line))
                  (return :45gs02))
                 ((or (search "target: x16" line)
                      (search ":x16" line))
                  (return :x16))
                 ((search "target: r65c02" line)
                  (return :r65c02))))))
  nil)

;;; --------------------------------------------------------------------------
;;; Assemblage selon la cible
;;; --------------------------------------------------------------------------

(defun call (package-name function-name &rest args)
  "Appelle PACKAGE-NAME:FUNCTION-NAME avec ARGS de façon dynamique."
  (apply (find-symbol (string function-name) (string package-name)) args))

(defun assemble-source (source-path target origin verbose)
  "Assemble le fichier et retourne un vecteur d'octets."
  (when verbose
    (format t "Cible : ~A  Origine : $~4,'0X~%" target origin))
  (let ((ext (pathname-type source-path)))
    (cond
      ;; Fichiers .lasm — frontend Lisp natif
      ((string-equal ext "lasm")
       (call "CL-ASM/LASM" "ASSEMBLE-LASM"
             source-path :origin origin :target target))
      ;; Fichiers .asm — syntaxe classique
      (t
       (ecase target
         (:6502
          (call "CL-ASM/BACKEND.6502" "ASSEMBLE-FILE"
                source-path :origin origin))
         (:45gs02
          (call "CL-ASM/BACKEND.45GS02" "ASSEMBLE-FILE-45GS02"
                source-path :origin origin))
         (:x16
          (call "CL-ASM/BACKEND.65C02" "ASSEMBLE-FILE-65C02"
                source-path :origin origin))
         (:r65c02
          (call "CL-ASM/BACKEND.R65C02" "ASSEMBLE-FILE-R65C02"
                source-path :origin origin)))))))

;;; --------------------------------------------------------------------------
;;; Point d'entrée
;;; --------------------------------------------------------------------------

(defun print-usage ()
  (format t "Usage: cl-asm SOURCE [options]~%~%")
  (format t "Options:~%")
  (format t "  -o FILE          Fichier de sortie~%")
  (format t "  -f, --format FMT Format : prg (defaut) ou bin~%")
  (format t "  --origin ADDR    Adresse d'origine (ex: 0x0801, $0801)~%")
  (format t "  -t, --target T   Cible : 6502 (defaut), 45gs02, x16, r65c02~%")
  (format t "  -v, --verbose    Mode verbose~%")
  (format t "  -h, --help       Cette aide~%"))

(defun get-script-dir ()
  "Retourne le répertoire du script cl-asm via la variable d'environnement CL_ASM_DIR."
  (let ((env (uiop:getenv "CL_ASM_DIR")))
    (if (and env (> (length env) 0))
        (pathname (concatenate 'string env "/"))
        *default-pathname-defaults*)))

(defun main ()
  (let ((args (get-script-args))
        (script-dir (get-script-dir)))

    ;; Aide
    (when (or (null args)
              (member "--help" args :test #'string=)
              (member "-h" args :test #'string=))
      (print-usage)
      (exit-lisp 0))

    ;; Parser les arguments
    (let ((input    nil)
          (output   nil)
          (format   :prg)
          (origin   #x0801)
          (target   nil)
          (verbose  nil))

      (loop for i from 0 below (length args)
            for arg = (nth i args)
            do (cond
                 ((string= arg "-o")
                  (setf output (nth (1+ i) args)))
                 ((or (string= arg "-f") (string= arg "--format"))
                  (let ((fmt (nth (1+ i) args)))
                    (setf format (if (string-equal fmt "bin") :bin :prg))))
                 ((string= arg "--origin")
                  (setf origin (parse-integer-auto (nth (1+ i) args))))
                 ((or (string= arg "-t") (string= arg "--target"))
                  (let ((tgt (string-downcase (nth (1+ i) args))))
                    (setf target (cond
                                   ((string= tgt "45gs02") :45gs02)
                                   ((string= tgt "x16")    :x16)
                                   ((string= tgt "r65c02") :r65c02)
                                   (t                      :6502)))))
                 ((or (string= arg "-v") (string= arg "--verbose"))
                  (setf verbose t))
                 ((not (starts-with arg "-"))
                  (when (null input) (setf input arg)))))

      ;; Vérifications
      (unless input
        (format *error-output* "Erreur : fichier source manquant.~%")
        (print-usage)
        (exit-lisp 1))

      (unless (probe-file input)
        (format *error-output* "Erreur : fichier introuvable : ~A~%" input)
        (exit-lisp 1))

      ;; Détection automatique de la cible si non spécifiée
      (unless target
        (setf target (or (detect-target input) :6502)))

      ;; Fichier de sortie par défaut
      (unless output
        (setf output (default-output input format)))

      ;; Charger cl-asm
      (handler-case
          (load-cl-asm script-dir)
        (error (e)
          (format *error-output* "Erreur chargement cl-asm : ~A~%" e)
          (exit-lisp 1)))

      ;; Assembler
      (when verbose
        (format t "Assemblage de ~A...~%" input))

      (let ((bytes (handler-case
                       (assemble-source input target origin verbose)
                     (error (e)
                       (format *error-output* "Erreur assemblage : ~A~%" e)
                       (exit-lisp 1)))))

        ;; Écrire le fichier de sortie
        (handler-case
            (ecase format
              (:prg (call "CL-ASM/EMIT" "WRITE-PRG"
                          bytes output :load-address origin))
              (:bin (call "CL-ASM/EMIT" "WRITE-BIN"
                          bytes output)))
          (error (e)
            (format *error-output* "Erreur écriture : ~A~%" e)
            (exit-lisp 1)))

        (format t "~A -> ~A (~D octets)~%" input output (length bytes))))))

(main)
