; -*- coding: utf-8 -*-
;;; run-tests-clisp.lisp
;;;
;;; Lance la suite de tests complète de cl-asm sous CLISP.
;;; Entièrement en Common Lisp standard, sans dépendance externe.
;;;
;;; Usage depuis la racine du projet :
;;;   clisp run-tests-clisp.lisp
;;;
;;; Problème géré : CLISP ne supporte pas la syntaxe &key dans les
;;; signatures ftype des declaim. Ces formes ne servent qu'à supprimer
;;; des style-warnings sous SBCL — elles n'ont aucun effet sur le
;;; comportement du programme. On les filtre à la lecture.


;;; --------------------------------------------------------------------------
;;;  Chargement filtré : lit un fichier forme par forme,
;;;  évalue tout sauf les declaim ftype contenant &key
;;; --------------------------------------------------------------------------

(defun ftype-with-key-p (form)
  "Vrai si FORM est un declaim ftype dont la signature contient &key."
  (and (consp form)
       (eq (car form) 'declaim)
       (consp (cdr form))
       (let ((spec (cadr form)))
         (and (consp spec)
              (eq (car spec) 'ftype)
              (consp (cdr spec))
              (let ((sig (cadr spec)))
                (and (consp sig)
                     (eq (car sig) 'function)
                     (consp (cdr sig))
                     (member '&key (cadr sig))))))))

(defun load-filtered (path)
  "Charge PATH en sautant les declaim ftype incompatibles avec CLISP."
  (let* ((truepath (truename path))
         (*load-truename* truepath)
         (*load-pathname* (pathname path)))
    (with-open-file (stream truepath :direction :input)
      (let ((*package* *package*)
            (*readtable* *readtable*))
        (loop
          (let ((form (read stream nil stream)))
            (when (eq form stream) (return))
            (if (ftype-with-key-p form)
                (format t "; skipped: ~S~%" (car form))
                (eval form))))))))


;;; --------------------------------------------------------------------------
;;;  Chargement de tous les fichiers du projet
;;; --------------------------------------------------------------------------

(load-filtered "src/core/version.lisp")
(load-filtered "src/core/backends.lisp")
(load-filtered "src/core/ir.lisp")
(load-filtered "src/core/expression.lisp")
(load-filtered "src/core/symbol-table.lisp")
(load-filtered "src/frontend/classic-lexer.lisp")
(load-filtered "src/frontend/classic-parser.lisp")
(load-filtered "src/backend/6502.lisp")
(load-filtered "src/backend/45gs02.lisp")
(load-filtered "src/emit/output.lisp")
(load-filtered "src/backend/65c02.lisp")
(load-filtered "src/backend/r65c02.lisp")
(load-filtered "src/backend/65816.lisp")
(load-filtered "src/backend/z80.lisp")
(load-filtered "src/backend/m68k.lisp")
(load-filtered "src/backend/i8080.lisp")
(load-filtered "src/frontend/lasm.lisp")
(load-filtered "src/simulator/6502.lisp")
(load-filtered "tests/test-65c02.lisp")
(load-filtered "tests/test-r65c02.lisp")
(load-filtered "tests/test-lasm.lisp")
(load-filtered "tests/test-conditional.lisp")
(load-filtered "tests/test-macros.lisp")
(load-filtered "tests/test-45gs02.lisp")
(load-filtered "tests/test-6502.lisp")
(load-filtered "tests/test-parser.lisp")
(load-filtered "tests/test-lexer.lisp")
(load-filtered "tests/test-expression.lisp")
(load-filtered "tests/test-symbol-table.lisp")
(load-filtered "tests/test-65816.lisp")
(load-filtered "tests/test-z80.lisp")
(load-filtered "tests/test-m68k-parser.lisp")
(load-filtered "tests/test-m68k.lisp")
(load-filtered "tests/test-8080.lisp")
(load-filtered "tests/test-sim-6502.lisp")
(load-filtered "tests/test-sim-programs.lisp")
(load-filtered "tests/test-acme2clasm.lisp")
(load-filtered "tests/run-tests.lisp")


;;; --------------------------------------------------------------------------
;;;  Lancement des tests et sortie
;;; --------------------------------------------------------------------------

(let ((result (cl-asm/test:run-all-tests)))
  (ext:exit (if result 0 1)))
