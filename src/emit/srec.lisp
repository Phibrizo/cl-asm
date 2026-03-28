; -*- coding: utf-8 -*-
(defpackage #:cl-asm/emit.srec
  (:use #:cl)
  (:export #:emit-srec #:write-srec))
;;; src/emit/srec.lisp
;;;
;;; Emetteur Motorola S-record (format .srec / .mot).
;;;
;;; Utilisé pour flasher des systèmes Motorola 68k : Amiga, Atari ST,
;;; SNES (certains outils), et flasheurs embarqués industriels.
;;;
;;; Types d'enregistrements utilisés (adresses 16 bits) :
;;;   S0 — header (nom du module)
;;;   S1 — enregistrement de données (adresse 2 octets)
;;;   S9 — enregistrement de fin      (adresse 2 octets)
;;;
;;; Format d'un enregistrement :
;;;   SnHHAAAADD...CC
;;;   n    — type (0, 1, 9)
;;;   HH   — byte count = nb octets (adresse + données + checksum)
;;;   AAAA — adresse (2 octets, big-endian pour S0/S1/S9)
;;;   DD   — octets de données
;;;   CC   — checksum = complément à 1 du LSB de (HH + AAAA + DD)
;;;
;;; Taille max par enregistrement : 16 octets de données (standard).

(in-package #:cl-asm/emit.srec)

(defun %srec-checksum (bytes)
  "Complément à 1 du LSB de la somme des octets BYTES."
  (logand #xFF (lognot (reduce #'+ bytes :initial-value 0))))

(defun %addr-bytes-16 (address)
  "Décompose ADDRESS en 2 octets big-endian."
  (list (logand (ash address -8) #xFF)
        (logand address #xFF)))

(defun %emit-record (stream type address data)
  "Emet un enregistrement Motorola S-record dans STREAM.
TYPE    : 0 = header, 1 = données, 9 = fin
ADDRESS : adresse 16 bits
DATA    : liste d'octets"
  (let* ((addr-list  (%addr-bytes-16 address))
         (byte-count (+ 2 (length data) 1))   ; addr(2) + data + checksum(1)
         (checksum   (%srec-checksum
                      (list* byte-count (append addr-list data)))))
    (format stream "S~D~2,'0X~{~2,'0X~}~{~2,'0X~}~2,'0X~%"
            type byte-count addr-list data checksum)))

(defun emit-srec (bytes stream &key (origin 0))
  "Emet le vecteur BYTES en format Motorola S-record dans STREAM.
ORIGIN : adresse de base (défaut 0)."
  (let ((len (length bytes)))
    ;; S0 : enregistrement d'en-tête (nom du module)
    (%emit-record stream 0 0 (mapcar #'char-code (coerce "cl-asm" 'list)))
    ;; S1 : enregistrements de données
    (loop for offset from 0 below len by 16
          do (let* ((end     (min (+ offset 16) len))
                    (chunk   (coerce (subseq bytes offset end) 'list))
                    (address (logand (+ origin offset) #xFFFF)))
               (%emit-record stream 1 address chunk)))
    ;; S9 : enregistrement de fin
    (%emit-record stream 9 0 '())))

(defun write-srec (bytes path &key (origin 0))
  "Ecrit le vecteur BYTES en format Motorola S-record dans le fichier PATH.
ORIGIN : adresse de base (défaut 0)."
  (with-open-file (s path
                     :direction :output
                     :if-exists :supersede)
    (emit-srec bytes s :origin origin))
  path)


;;; --------------------------------------------------------------------------
;;; Enregistrement dans le registre des émetteurs
;;; --------------------------------------------------------------------------

(cl-asm/emitters:register-emitter
  :srec
  '("srec" "mot" "motorola" "srecord")
  "srec"
  (lambda (bytes path &key (origin 0)) (write-srec bytes path :origin origin))
  "Motorola S-record (.srec) — 68k, flasheurs embarqués"
  "Motorola S-record (.srec) — 68k, embedded flash programmers")
