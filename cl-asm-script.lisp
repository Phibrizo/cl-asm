; -*- coding: utf-8 -*-
;;;
;;; cl-asm-script.lisp -- Script ligne de commande pour cl-asm
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
  (error "Unsupported Lisp implementation (use SBCL, CLISP or ECL)"))

(defun exit-lisp (code)
  #+sbcl  (sb-ext:exit :code code)
  #+clisp (ext:exit code)
  #+ecl   (si:exit code)
  #-(or sbcl clisp ecl) (error "exit not available"))

;;; --------------------------------------------------------------------------
;;; Internationalisation (i18n)
;;; --------------------------------------------------------------------------

(defun getenv (name)
  "Lit une variable d'environnement de façon portable."
  #+sbcl  (sb-ext:posix-getenv name)
  #+clisp (ext:getenv name)
  #+ecl   (si:getenv name)
  #-(or sbcl clisp ecl) nil)

(defparameter *lang*
  (let ((lang (or (getenv "LANG") (getenv "LANGUAGE") "")))
    (if (and (>= (length lang) 2)
             (string= (subseq lang 0 2) "fr"))
        :fr
        :en)))

(defun msg (fr en)
  "Retourne FR ou EN selon la langue détectée."
  (if (eq *lang* :fr) fr en))

;;; --------------------------------------------------------------------------
;;; Chargement de ASDF et cl-asm
;;; --------------------------------------------------------------------------

(require :asdf)

(defun find-cl-asm-asd (script-dir)
  (let ((candidates (list
                     (merge-pathnames "cl-asm.asd" script-dir)
                     (merge-pathnames "cl-asm.asd" *default-pathname-defaults*))))
    (find-if #'probe-file candidates)))

(defun load-cl-asm (script-dir)
  (let ((asd (find-cl-asm-asd script-dir)))
    (if asd
        (let ((dir (make-pathname :name nil :type nil :defaults asd)))
          (pushnew dir asdf:*central-registry* :test #'equal)
          (asdf:load-system "cl-asm" :verbose nil))
        (error (msg "cl-asm.asd introuvable (cherche dans ~A et ~A)"
                    "cl-asm.asd not found (looked in ~A and ~A)")
               script-dir *default-pathname-defaults*))))

;;; --------------------------------------------------------------------------
;;; Utilitaires
;;; --------------------------------------------------------------------------

(defun starts-with (str prefix)
  (and (>= (length str) (length prefix))
       (string= str prefix :end1 (length prefix))))

(defun parse-integer-auto (s)
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
  (let* ((s (namestring input))
         (dot (position #\. s :from-end t))
         (base (if dot (subseq s 0 dot) s)))
    (concatenate 'string base "." (string-downcase (symbol-name fmt)))))

(defun detect-target (source-path)
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
  (apply (find-symbol (string function-name) (string package-name)) args))

(defun assemble-source (source-path target origin verbose)
  (when verbose
    (format t (msg "Cible : ~A  Origine : $~4,'0X~%"
                   "Target: ~A  Origin: $~4,'0X~%")
            target origin))
  (let ((ext (pathname-type source-path)))
    (cond
      ((string-equal ext "lasm")
       (call "CL-ASM/LASM" "ASSEMBLE-LASM"
             source-path :origin origin :target target))
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
;;; Point d'entree
;;; --------------------------------------------------------------------------

(defun print-usage ()
  (if (eq *lang* :fr)
      (progn
        (format t "Usage: cl-asm SOURCE [options]~%~%")
        (format t "Options:~%")
        (format t "  -o FILE          Fichier de sortie~%")
        (format t "  -f, --format FMT Format : prg (defaut) ou bin~%")
        (format t "  --origin ADDR    Adresse d'origine (ex: 0x0801, $0801)~%")
        (format t "  -t, --target T   Cible : 6502 (defaut), 45gs02, x16, r65c02~%")
        (format t "  -v, --verbose    Mode verbose~%")
        (format t "  -h, --help       Cette aide~%"))
      (progn
        (format t "Usage: cl-asm SOURCE [options]~%~%")
        (format t "Options:~%")
        (format t "  -o FILE          Output file~%")
        (format t "  -f, --format FMT Format: prg (default) or bin~%")
        (format t "  --origin ADDR    Origin address (e.g. 0x0801, $0801)~%")
        (format t "  -t, --target T   Target: 6502 (default), 45gs02, x16, r65c02~%")
        (format t "  -v, --verbose    Verbose mode~%")
        (format t "  -h, --help       Show this help~%"))))

(defun get-script-dir ()
  (let ((env (getenv "CL_ASM_DIR")))
    (if (and env (> (length env) 0))
        (pathname (concatenate 'string env "/"))
        *default-pathname-defaults*)))

(defun main ()
  (let ((args (get-script-args))
        (script-dir (get-script-dir)))

    (when (or (null args)
              (member "--help" args :test #'string=)
              (member "-h" args :test #'string=))
      (print-usage)
      (exit-lisp 0))

    (let ((input   nil)
          (output  nil)
          (format  :prg)
          (origin  #x0801)
          (target  nil)
          (verbose nil))

      (let ((i 0))
        (loop while (< i (length args))
              for arg = (nth i args)
              do (cond
                   ((string= arg "-o")
                    (setf output (nth (1+ i) args))
                    (incf i 2))
                   ((or (string= arg "-f") (string= arg "--format"))
                    (let ((fmt (nth (1+ i) args)))
                      (setf format (if (string-equal fmt "bin") :bin :prg)))
                    (incf i 2))
                   ((string= arg "--origin")
                    (setf origin (parse-integer-auto (nth (1+ i) args)))
                    (incf i 2))
                   ((or (string= arg "-t") (string= arg "--target"))
                    (let ((tgt (string-downcase (nth (1+ i) args))))
                      (setf target (cond
                                     ((string= tgt "45gs02") :45gs02)
                                     ((string= tgt "x16")    :x16)
                                     ((string= tgt "r65c02") :r65c02)
                                     (t                      :6502))))
                    (incf i 2))
                   ((or (string= arg "-v") (string= arg "--verbose"))
                    (setf verbose t)
                    (incf i))
                   ((not (starts-with arg "-"))
                    (when (null input) (setf input arg))
                    (incf i))
                   (t (incf i)))))

      (unless input
        (format *error-output*
                (msg "Erreur : fichier source manquant.~%"
                     "Error: missing source file.~%"))
        (print-usage)
        (exit-lisp 1))

      (unless (probe-file input)
        (format *error-output*
                (msg "Erreur : fichier introuvable : ~A~%"
                     "Error: file not found: ~A~%")
                input)
        (exit-lisp 1))

      (unless target
        (setf target (or (detect-target input) :6502)))

      (unless output
        (setf output (default-output input format)))

      (handler-case
          (load-cl-asm script-dir)
        (error (e)
          (format *error-output*
                  (msg "Erreur chargement cl-asm : ~A~%"
                       "Error loading cl-asm: ~A~%")
                  e)
          (exit-lisp 1)))

      (when verbose
        (format t (msg "Assemblage de ~A...~%"
                       "Assembling ~A...~%")
                input))

      (let ((bytes (handler-case
                       (assemble-source input target origin verbose)
                     (error (e)
                       (format *error-output*
                               (msg "Erreur assemblage : ~A~%"
                                    "Assembly error: ~A~%")
                               e)
                       (exit-lisp 1)))))

        (handler-case
            (ecase format
              (:prg (call "CL-ASM/EMIT" "WRITE-PRG"
                          bytes output :load-address origin))
              (:bin (call "CL-ASM/EMIT" "WRITE-BIN"
                          bytes output)))
          (error (e)
            (format *error-output*
                    (msg "Erreur ecriture : ~A~%"
                         "Write error: ~A~%")
                    e)
            (exit-lisp 1)))

        (format t "~A -> ~A (~D ~A)~%"
                input output (length bytes)
                (msg "octets" "bytes"))))))

(main)
