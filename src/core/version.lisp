; -*- coding: utf-8 -*-
(defpackage #:cl-asm/version
  (:use #:cl)
  (:export #:+version+ #:+version-major+ #:+version-minor+ #:+version-patch+
           #:version-string))

(in-package #:cl-asm/version)

;;; src/core/version.lisp
;;;
;;; Version de cl-asm.
;;; Format : MAJOR.MINOR.PATCH
;;;   MAJOR : changement incompatible de l'API
;;;   MINOR : nouvelle fonctionnalite compatible
;;;   PATCH : correction de bug

(defparameter +version-major+ 0)
(defparameter +version-minor+ 16)
(defparameter +version-patch+ 0)

(defparameter +version+
  (format nil "~D.~D.~D"
          +version-major+ +version-minor+ +version-patch+))

(defun version-string ()
  "Retourne la version de cl-asm sous forme de string."
  +version+)
