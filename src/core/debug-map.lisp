; -*- coding: utf-8 -*-
;;;
;;; src/core/debug-map.lisp — Table adresse → source-loc pour le débogueur
;;;
;;; Défini ici (et non dans src/debugger/) pour que le backend 6502 puisse
;;; la remplir sans dépendre du package débogueur.

(defpackage #:cl-asm/debug-map
  (:use #:cl)
  (:export
   #:debug-map
   #:make-debug-map
   #:debug-map-get
   #:debug-map-set))

(in-package #:cl-asm/debug-map)

(defstruct (debug-map (:constructor make-debug-map ()))
  "Table adresse (0–65535) → source-loc.
   Construite optionnellement par le backend (passe 2) et consommée
   par le débogueur pour afficher la ligne source correspondant à chaque PC."
  (entries (make-array 65536 :initial-element nil :element-type t)))

(defun debug-map-get (dm addr)
  "Retourne la source-loc associée à ADDR (0–65535), ou NIL."
  (aref (debug-map-entries dm) (logand addr #xFFFF)))

(defun debug-map-set (dm addr loc)
  "Enregistre LOC (source-loc ou nil) pour ADDR dans DM."
  (setf (aref (debug-map-entries dm) (logand addr #xFFFF)) loc))
