; -*- coding: utf-8 -*-
;;; tests/test-emitters.lisp
;;;
;;; Tests unitaires pour le registre d'émetteurs et les formats
;;; Intel HEX et Motorola S-record.

(defpackage #:cl-asm/test.emitters
  (:use #:cl)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.emitters)

(defvar *pass* 0)
(defvar *fail* 0)
(defvar *failures* '())

(defmacro check (desc expr)
  `(if ,expr
       (progn (incf *pass*)
              (format t "  OK  ~A~%" ,desc))
       (progn (incf *fail*)
              (push ,desc *failures*)
              (format t "  KO  ~A~%" ,desc))))

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&--- ~A ---~%" ',name)
     ,@body))

;;; Helpers

(defun bytes (&rest octets)
  "Construit un vecteur (unsigned-byte 8) à partir d'OCTETS."
  (make-array (length octets)
              :element-type '(unsigned-byte 8)
              :initial-contents octets))

(defun emit-ihex-string (byte-vector &key (origin 0))
  "Retourne la sortie Intel HEX de BYTE-VECTOR sous forme de chaîne."
  (with-output-to-string (s)
    (cl-asm/emit.ihex:emit-ihex byte-vector s :origin origin)))

(defun emit-srec-string (byte-vector &key (origin 0))
  "Retourne la sortie Motorola S-record de BYTE-VECTOR sous forme de chaîne."
  (with-output-to-string (s)
    (cl-asm/emit.srec:emit-srec byte-vector s :origin origin)))

(defun lines (str)
  "Découpe STR en lignes (supprime les lignes vides finales)."
  (let ((result '())
        (start 0)
        (len (length str)))
    (loop for i from 0 below len
          when (char= (char str i) #\Newline)
            do (when (> i start)
                 (push (subseq str start i) result))
               (setf start (1+ i)))
    (when (< start len)
      (push (subseq str start len) result))
    (nreverse result)))


;;; --------------------------------------------------------------------------
;;;  Registre des émetteurs
;;; --------------------------------------------------------------------------

(deftest test/emitters-registry
  ;; Les 4 émetteurs de base sont enregistrés
  (check "registre — au moins 4 émetteurs"
         (>= (length (cl-asm/emitters:all-emitters)) 4))
  ;; Lookup par alias
  (check "registre — alias 'bin' → :bin"
         (let ((e (cl-asm/emitters:find-emitter-by-alias "bin")))
           (and e (eq (cl-asm/emitters:emitter-keyword e) :bin))))
  (check "registre — alias 'raw' → :bin"
         (let ((e (cl-asm/emitters:find-emitter-by-alias "raw")))
           (and e (eq (cl-asm/emitters:emitter-keyword e) :bin))))
  (check "registre — alias 'prg' → :prg"
         (let ((e (cl-asm/emitters:find-emitter-by-alias "prg")))
           (and e (eq (cl-asm/emitters:emitter-keyword e) :prg))))
  (check "registre — alias 'c64' → :prg"
         (let ((e (cl-asm/emitters:find-emitter-by-alias "c64")))
           (and e (eq (cl-asm/emitters:emitter-keyword e) :prg))))
  (check "registre — alias 'ihex' → :ihex"
         (let ((e (cl-asm/emitters:find-emitter-by-alias "ihex")))
           (and e (eq (cl-asm/emitters:emitter-keyword e) :ihex))))
  (check "registre — alias 'hex' → :ihex"
         (let ((e (cl-asm/emitters:find-emitter-by-alias "hex")))
           (and e (eq (cl-asm/emitters:emitter-keyword e) :ihex))))
  (check "registre — alias 'srec' → :srec"
         (let ((e (cl-asm/emitters:find-emitter-by-alias "srec")))
           (and e (eq (cl-asm/emitters:emitter-keyword e) :srec))))
  (check "registre — alias 'mot' → :srec"
         (let ((e (cl-asm/emitters:find-emitter-by-alias "mot")))
           (and e (eq (cl-asm/emitters:emitter-keyword e) :srec))))
  (check "registre — alias inconnu → nil"
         (null (cl-asm/emitters:find-emitter-by-alias "elf")))
  ;; Extensions de fichier
  (check "registre — extension :bin = \"bin\""
         (string= (cl-asm/emitters:emitter-extension
                   (cl-asm/emitters:find-emitter-by-keyword :bin)) "bin"))
  (check "registre — extension :prg = \"prg\""
         (string= (cl-asm/emitters:emitter-extension
                   (cl-asm/emitters:find-emitter-by-keyword :prg)) "prg"))
  (check "registre — extension :ihex = \"hex\""
         (string= (cl-asm/emitters:emitter-extension
                   (cl-asm/emitters:find-emitter-by-keyword :ihex)) "hex"))
  (check "registre — extension :srec = \"srec\""
         (string= (cl-asm/emitters:emitter-extension
                   (cl-asm/emitters:find-emitter-by-keyword :srec)) "srec")))


;;; --------------------------------------------------------------------------
;;;  Intel HEX
;;; --------------------------------------------------------------------------

(deftest test/ihex-structure
  (let* ((data (bytes #xA9 #x00 #x60))
         (out  (emit-ihex-string data :origin #x0200))
         (ls   (lines out)))
    ;; Chaque ligne commence par ':'
    (check "ihex — chaque ligne commence par ':'"
           (every (lambda (l) (and (plusp (length l))
                                   (char= (char l 0) #\:)))
                  ls))
    ;; Dernier enregistrement = EOF
    (check "ihex — dernier enregistrement = :00000001FF"
           (string= (car (last ls)) ":00000001FF"))
    ;; Exactement 2 lignes : 1 donnée + EOF
    (check "ihex — 3 octets → 1 data record + 1 EOF"
           (= (length ls) 2))))

(deftest test/ihex-checksum
  ;; LDA #$00 / RTS = A9 00 60 à $0200
  ;; Somme : 03+02+00+00+A9+00+60 = 3+2+169+96 = 270 → checksum = (-270)&FF = F2
  (let ((out (emit-ihex-string (bytes #xA9 #x00 #x60) :origin #x0200)))
    (check "ihex — data record A9 00 60 à $0200"
           (search ":03020000A90060F2" out)))
  ;; EOF toujours :00000001FF
  (let ((out (emit-ihex-string (bytes #x00) :origin 0)))
    (check "ihex — EOF record = :00000001FF"
           (search ":00000001FF" out))))

(deftest test/ihex-multi-records
  ;; 17 octets → 2 data records (16 + 1) + EOF
  (let* ((data  (make-array 17 :element-type '(unsigned-byte 8) :initial-element #x00))
         (out   (emit-ihex-string data :origin 0))
         (ls    (lines out)))
    (check "ihex — 17 octets → 3 lignes (16+1+EOF)"
           (= (length ls) 3))
    ;; Premier record : 16 octets
    (check "ihex — premier record LL=10 (16)"
           (string= (subseq (first ls) 1 3) "10"))
    ;; Deuxième record : 1 octet
    (check "ihex — deuxième record LL=01"
           (string= (subseq (second ls) 1 3) "01"))))

(deftest test/ihex-origin
  ;; Origin décale l'adresse dans les records
  (let ((out (emit-ihex-string (bytes #xFF) :origin #x8000)))
    (check "ihex — origin $8000 → adresse 8000 dans le record"
           (search ":018000" out))))

(deftest test/ihex-empty
  ;; Tableau vide → juste le record EOF
  (let* ((out (emit-ihex-string (bytes) :origin 0))
         (ls  (lines out)))
    (check "ihex — tableau vide → 1 ligne (EOF seulement)"
           (= (length ls) 1))
    (check "ihex — tableau vide → :00000001FF"
           (string= (first ls) ":00000001FF"))))


;;; --------------------------------------------------------------------------
;;;  Motorola S-record
;;; --------------------------------------------------------------------------

(deftest test/srec-structure
  (let* ((data (bytes #xA9 #x00 #x60))
         (out  (emit-srec-string data :origin #x0200))
         (ls   (lines out)))
    ;; Première ligne = S0 (header)
    (check "srec — première ligne commence par 'S0'"
           (and (plusp (length (first ls)))
                (string= (subseq (first ls) 0 2) "S0")))
    ;; Dernière ligne = S9 (end)
    (check "srec — dernière ligne commence par 'S9'"
           (and (plusp (length (car (last ls))))
                (string= (subseq (car (last ls)) 0 2) "S9")))
    ;; 3 octets → S0 + 1 data (S1) + S9
    (check "srec — 3 octets → 3 lignes"
           (= (length ls) 3))))

(deftest test/srec-checksum
  ;; A9 00 60 à $0200 :
  ;; byte_count=6, addr=(02 00), data=(A9 00 60)
  ;; somme = 6+2+0+A9+0+60 = 6+2+169+96 = 273 = 0x111 → checksum = FF-11 = EE
  (let ((out (emit-srec-string (bytes #xA9 #x00 #x60) :origin #x0200)))
    (check "srec — data record A9 00 60 à $0200"
           (search "S1060200A90060EE" out)))
  ;; S9 pour adresse 0 : byte_count=3, addr=(00 00), data=()
  ;; somme=3+0+0=3 → checksum=FC
  (let ((out (emit-srec-string (bytes #x00) :origin 0)))
    (check "srec — end record S9030000FC"
           (search "S9030000FC" out))))

(deftest test/srec-multi-records
  ;; 17 octets → S0 + 2 data (16+1) + S9
  (let* ((data (make-array 17 :element-type '(unsigned-byte 8) :initial-element #x00))
         (out  (emit-srec-string data :origin 0))
         (ls   (lines out)))
    (check "srec — 17 octets → 4 lignes (S0+S1+S1+S9)"
           (= (length ls) 4))))

(deftest test/srec-empty
  ;; Tableau vide → S0 + S9 seulement
  (let* ((out (emit-srec-string (bytes) :origin 0))
         (ls  (lines out)))
    (check "srec — tableau vide → 2 lignes (S0+S9)"
           (= (length ls) 2))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== emitters ===~%")
  (test/emitters-registry)
  (test/ihex-structure)
  (test/ihex-checksum)
  (test/ihex-multi-records)
  (test/ihex-origin)
  (test/ihex-empty)
  (test/srec-structure)
  (test/srec-checksum)
  (test/srec-multi-records)
  (test/srec-empty)
  (format t "  emitters : ~D OK, ~D KO~%" *pass* *fail*))
