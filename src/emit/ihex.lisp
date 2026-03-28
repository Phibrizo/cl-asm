; -*- coding: utf-8 -*-
(defpackage #:cl-asm/emit.ihex
  (:use #:cl)
  (:export #:emit-ihex #:write-ihex))
;;; src/emit/ihex.lisp
;;;
;;; Emetteur Intel HEX (format .hex).
;;;
;;; Utilisé pour flasher des microcontrôleurs : AVR (Arduino), PIC,
;;; STM32, Z80/8080 (CP/M loaders), 8086 (DOS debug).
;;;
;;; Format d'un enregistrement :
;;;   :LLAAAATTDD...CC
;;;   LL   — nombre d'octets de données (2 chiffres hex)
;;;   AAAA — adresse de départ (4 chiffres hex, big-endian)
;;;   TT   — type : 00=données, 01=fin de fichier
;;;   DD   — octets de données (2 chiffres hex chacun)
;;;   CC   — checksum = complément à 2 de la somme LL+AAAA+TT+DD
;;;
;;; Adresses > 64 Ko : non gérées (pas nécessaire pour les cibles actuelles).
;;; Taille max par enregistrement : 16 octets (standard de facto).

(in-package #:cl-asm/emit.ihex)

(defun %ihex-checksum (bytes)
  "Complément à 2 du LSB de la somme des octets BYTES."
  (logand #xFF (- (reduce #'+ bytes :initial-value 0))))

(defun %emit-record (stream type address data)
  "Emet un enregistrement Intel HEX dans STREAM.
TYPE    : 0 = données, 1 = fin de fichier
ADDRESS : adresse 16 bits
DATA    : liste d'octets (vide pour l'enregistrement de fin)"
  (let* ((len      (length data))
         (addr-hi  (logand (ash address -8) #xFF))
         (addr-lo  (logand address #xFF))
         (checksum (%ihex-checksum
                    (list* len addr-hi addr-lo type data))))
    (format stream ":~2,'0X~4,'0X~2,'0X~{~2,'0X~}~2,'0X~%"
            len address type data checksum)))

(defun emit-ihex (bytes stream &key (origin 0))
  "Emet le vecteur BYTES en format Intel HEX dans STREAM.
ORIGIN : adresse de base (défaut 0)."
  (let ((len (length bytes)))
    (loop for offset from 0 below len by 16
          do (let* ((end     (min (+ offset 16) len))
                    (chunk   (coerce (subseq bytes offset end) 'list))
                    (address (logand (+ origin offset) #xFFFF)))
               (%emit-record stream 0 address chunk)))
    ;; Enregistrement de fin de fichier
    (%emit-record stream 1 0 '())))

(defun write-ihex (bytes path &key (origin 0))
  "Ecrit le vecteur BYTES en format Intel HEX dans le fichier PATH.
ORIGIN : adresse de base (défaut 0)."
  (with-open-file (s path
                     :direction :output
                     :if-exists :supersede)
    (emit-ihex bytes s :origin origin))
  path)


;;; --------------------------------------------------------------------------
;;; Enregistrement dans le registre des émetteurs
;;; --------------------------------------------------------------------------

(cl-asm/emitters:register-emitter
  :ihex
  '("ihex" "hex" "intel")
  "hex"
  (lambda (bytes path &key (origin 0)) (write-ihex bytes path :origin origin))
  "Intel HEX (.hex) — microcontrôleurs, flasheurs"
  "Intel HEX (.hex) — microcontrollers, flash programmers")
