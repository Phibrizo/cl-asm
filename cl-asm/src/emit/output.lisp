; -*- coding: utf-8 -*-
(defpackage #:cl-asm/emit
  (:use #:cl)
  (:export
   #:emit-bin #:write-bin
   #:emit-prg #:write-prg
   #:emit-listing #:write-listing))
;;; src/emit/output.lisp
;;;
;;; Emetteurs de fichiers de sortie.
;;;
;;; Trois formats :
;;;   BIN  — binaire brut, pas de header
;;;   PRG  — format C64 : 2 octets header little-endian + binaire
;;;   LST  — listing annote : adresse | hex | source


(in-package #:cl-asm/emit)

(declaim (ftype (function (t) t) format-operand format-expr directive-size))
(declaim (ftype (function (t t t) t) format-directive-listing))
(declaim (ftype (function (t t t) t) instruction-size-in-binary))


;;; --------------------------------------------------------------------------
;;;  BIN — binaire brut
;;; --------------------------------------------------------------------------

(defun emit-bin (bytes stream)
  "Ecrit le vecteur BYTES dans STREAM (flux binaire)."
  (write-sequence bytes stream))

(defun write-bin (bytes path)
  "Ecrit le vecteur BYTES dans le fichier a PATH."
  (with-open-file (s path
                     :direction :output
                     :element-type '(unsigned-byte 8)
                     :if-exists :supersede)
    (emit-bin bytes s))
  path)


;;; --------------------------------------------------------------------------
;;;  PRG — format C64
;;; --------------------------------------------------------------------------

(defun emit-prg (bytes stream &key (load-address #x0801))
  "Ecrit un fichier PRG C64 dans STREAM.
   Format : 2 octets little-endian (adresse de chargement) + binaire."
  (write-byte (logand load-address #xFF) stream)
  (write-byte (logand (ash load-address -8) #xFF) stream)
  (emit-bin bytes stream))

(defun write-prg (bytes path &key (load-address #x0801))
  "Ecrit un fichier PRG C64 dans le fichier a PATH."
  (with-open-file (s path
                     :direction :output
                     :element-type '(unsigned-byte 8)
                     :if-exists :supersede)
    (emit-prg bytes s :load-address load-address))
  path)


;;; --------------------------------------------------------------------------
;;;  LST — listing annote
;;; --------------------------------------------------------------------------

(defun emit-listing (program bytes stream &key (origin #x0801))
  "Genere un listing annote dans STREAM (flux texte).
   Format de chaque ligne :
     ADDR  XX XX XX   MNEMONIC OPERANDE
   Exemple :
     0801  A9 00      LDA #$00
     0803  8D 20 D0   STA $D020"
  (let ((pc origin)
        (byte-pos 0)
        (sections (cl-asm/ir:ir-program-sections program)))
    (dolist (section sections)
      (when (cl-asm/ir:ir-section-origin section)
        (setf pc (cl-asm/ir:ir-section-origin section)))
      (dolist (node (cl-asm/ir:ir-section-nodes section))
        (typecase node
          (cl-asm/ir:ir-label
           (format stream "~4,'0X~20T~A:~%"
                   pc
                   (cl-asm/ir:ir-label-name node)))
          (cl-asm/ir:ir-instruction
           (let* ((mn  (cl-asm/ir:ir-instruction-mnemonic node))
                  (ops (cl-asm/ir:ir-instruction-operands  node))
                  ;; Taille estimee (on lit jusqu'a la prochaine instruction)
                  (sz  (or (and bytes
                                (position-if-not
                                 (lambda (b) (declare (ignore b)) nil)
                                 bytes :start byte-pos))
                           1)))
             (declare (ignore sz))
             ;; Adresse
             (format stream "~4,'0X  " pc)
             ;; Bytes hex (jusqu'a 3)
             (let ((hex-str
                     (with-output-to-string (hs)
                       (loop for i from 0 to 2
                             while (< (+ byte-pos i) (length bytes))
                             do (format hs "~2,'0X " (aref bytes (+ byte-pos i)))))))
               (format stream "~12A" hex-str))
             ;; Mnemonique et operande
             (format stream " ~A" mn)
             (when ops
               (format stream " ~A" (format-operand (first ops))))
             (format stream "~%")
             ;; Avancer les positions
             (let ((instr-size (instruction-size-in-binary
                                bytes byte-pos (+ byte-pos 3))))
               (incf pc       instr-size)
               (incf byte-pos instr-size))))
          (cl-asm/ir:ir-directive
           (format-directive-listing node stream pc)
           (let ((sz (directive-size node)))
             (incf pc       sz)
             (incf byte-pos sz))))))))

(defun format-operand (operand)
  "Formate un operande pour le listing."
  (let ((kind  (cl-asm/ir:ir-operand-kind     operand))
        (val   (cl-asm/ir:ir-operand-value     operand))
        (ireg  (cl-asm/ir:ir-operand-index-reg operand)))
    (ecase kind
      (:register   (format nil "~A" val))
      (:immediate  (format nil "#~A" (format-expr val)))
      (:direct
       (if ireg
           (format nil "~A,~A" (format-expr val) (string-upcase (symbol-name ireg)))
           (format nil "~A" (format-expr val))))
      (:indirect
       (format nil "(~A)" (format-expr val)))
      (:indirect-x
       (format nil "(~A,~A)" (format-expr val)
               (string-upcase (symbol-name ireg))))
      (:indirect-y
       (format nil "(~A),~A" (format-expr val)
               (string-upcase (symbol-name ireg)))))))

(defun format-expr (expr)
  "Formate une expression pour le listing."
  (cond
    ((integerp expr)
     (if (<= 0 expr 255)
         (format nil "$~2,'0X" expr)
         (format nil "$~4,'0X" expr)))
    ((stringp expr) expr)
    ((eq expr :*) "*")
    ((listp expr)
     (format nil "~A" expr))
    (t (format nil "~A" expr))))

(defun format-directive-listing (directive stream pc)
  "Formate une directive pour le listing."
  (let ((name (cl-asm/ir:ir-directive-name directive))
        (args (cl-asm/ir:ir-directive-args  directive)))
    (case name
      (:org
       (format stream "~4,'0X~20T.ORG $~4,'0X~%" pc (first args)))
      (:equ
       (format stream "~4,'0X~20T~A = ~A~%" pc (first args) (second args)))
      (:byte
       (format stream "~4,'0X~20T.BYTE ~{$~2,'0X~^, ~}~%" pc args))
      (:word
       (format stream "~4,'0X~20T.WORD ~{$~4,'0X~^, ~}~%" pc args))
      (otherwise
       (format stream "~4,'0X~20T.~A ~{~A~^, ~}~%"
               pc (string-upcase (symbol-name name)) args)))))

(defun instruction-size-in-binary (bytes start max-end)
  "Estime la taille d'une instruction dans le binaire."
  (declare (ignore bytes max-end))
  ;; Sans demontage complet, on retourne 1 par defaut
  ;; L'appelant avance byte-pos de la taille reelle en passe 2
  (declare (ignore start))
  1)

(defun directive-size (directive)
  "Retourne la taille en octets d'une directive."
  (let ((name (cl-asm/ir:ir-directive-name directive))
        (args (cl-asm/ir:ir-directive-args  directive)))
    (case name
      (:byte  (length args))
      (:word  (* 2 (length args)))
      (:dword (* 4 (length args)))
      (:text  (reduce #'+ args
                      :key (lambda (a) (if (stringp a) (length a) 1))
                      :initial-value 0))
      (otherwise 0))))

(defun write-listing (program bytes path &key (origin #x0801))
  "Ecrit un listing annote dans le fichier a PATH."
  (with-open-file (s path
                     :direction :output
                     :if-exists :supersede)
    (emit-listing program bytes s :origin origin))
  path)
