; -*- coding: utf-8 -*-
;;; tests/test-lexer.lisp

(defpackage #:cl-asm/test.lexer
  (:use #:cl #:cl-asm/lexer)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.lexer)


;;; --------------------------------------------------------------------------
;;;  Infra de test
;;; --------------------------------------------------------------------------

(defvar *pass* 0)
(defvar *fail* 0)
(defvar *failures* '())

(defmacro check (description form)
  `(let ((result (handler-case ,form
                   (error (e)
                     (format t "~&  ERREUR inattendue dans «~A» : ~A~%" ,description e)
                     nil))))
     (if result
         (progn (incf *pass*) (format t "~&  OK  ~A~%" ,description))
         (progn (incf *fail*)
                (push ,description *failures*)
                (format t "~&  KO  ~A~%" ,description)))))

(defmacro check-error (description condition-type form)
  `(let ((fired nil))
     (handler-case ,form
       (,condition-type () (setf fired t))
       (error (e)
         (format t "~&  ERREUR inattendue dans «~A» : ~A~%" ,description e)))
     (if fired
         (progn (incf *pass*) (format t "~&  OK  ~A (erreur attendue)~%" ,description))
         (progn (incf *fail*)
                (push ,description *failures*)
                (format t "~&  KO  ~A (erreur NON déclenchée)~%" ,description)))))

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&~%[~A]~%" ',name)
     ,@body))


;;; --------------------------------------------------------------------------
;;;  Helpers
;;; --------------------------------------------------------------------------

(defun tok (source)
  "Tokenise SOURCE et retourne la liste de tokens sans le :eof final."
  (remove-if (lambda (tk) (token-is tk :eof))
             (tokenize-string source)))

(defun kinds (source)
  "Retourne uniquement les kinds des tokens (sans :newline ni :eof)."
  (mapcar #'token-kind
          (remove-if (lambda (tk)
                       (member (token-kind tk) '(:newline :eof)))
                     (tokenize-string source))))

(defun values* (source)
  "Retourne uniquement les valeurs des tokens (sans :newline ni :eof)."
  (mapcar #'token-value
          (remove-if (lambda (tk)
                       (member (token-kind tk) '(:newline :eof)))
                     (tokenize-string source))))

(defun first-tok (source)
  (first (tok source)))

(defun first-kind (source)
  (token-kind (first-tok source)))

(defun first-val (source)
  (token-value (first-tok source)))


;;; --------------------------------------------------------------------------
;;;  Tests : littéraux entiers
;;; --------------------------------------------------------------------------

(deftest test/integer-decimal
  (check "42"          (= 42    (first-val "42")))
  (check "0"           (= 0     (first-val "0")))
  (check "65535"       (= 65535 (first-val "65535")))
  (check "kind = :integer" (eq :integer (first-kind "42"))))

(deftest test/integer-hex-dollar
  (check "$FF"         (= 255   (first-val "$FF")))
  (check "$0000"       (= 0     (first-val "$0000")))
  (check "$FFFF"       (= 65535 (first-val "$FFFF")))
  (check "$1234"       (= #x1234 (first-val "$1234")))
  (check "minuscules"  (= 255   (first-val "$ff"))))

(deftest test/integer-hex-0x
  (check "0xFF"        (= 255   (first-val "0xFF")))
  (check "0xFFFF"      (= 65535 (first-val "0xFFFF")))
  (check "0XFF"        (= 255   (first-val "0XFF"))))

(deftest test/integer-binary
  (check "%10000000"   (= 128   (first-val "%10000000")))
  (check "%00000001"   (= 1     (first-val "%00000001")))
  (check "%11111111"   (= 255   (first-val "%11111111")))
  (check "0b10110011"  (= #b10110011 (first-val "0b10110011")))
  (check "0B00001111"  (= 15    (first-val "0B00001111"))))


;;; --------------------------------------------------------------------------
;;;  Tests : littéraux caractères
;;; --------------------------------------------------------------------------

(deftest test/char-literal
  (check "'A' = 65"    (= 65  (first-val "'A'")))
  (check "'a' = 97"    (= 97  (first-val "'a'")))
  (check "'0' = 48"    (= 48  (first-val "'0'")))
  (check "' ' = 32"    (= 32  (first-val "' '")))
  (check "kind = :integer" (eq :integer (first-kind "'A'")))
  (check "'\\n' = 10"  (= 10  (first-val "'\\n'")))
  (check "'\\t' = 9"   (= 9   (first-val "'\\t'")))
  (check "'\\0' = 0"   (= 0   (first-val "'\\0'"))))


;;; --------------------------------------------------------------------------
;;;  Tests : chaînes
;;; --------------------------------------------------------------------------

(deftest test/string-literal
  (check "chaîne simple"
         (string= "hello" (first-val "\"hello\"")))
  (check "chaîne vide"
         (string= "" (first-val "\"\"")))
  (check "kind = :string"
         (eq :string (first-kind "\"hello\"")))
  (check "escape \\n"
         (string= (coerce '(#\h #\i #\Newline) 'string)
                  (first-val "\"hi\\n\"")))
  (check "escape \\\\"
         (string= "\\" (first-val "\"\\\\\""))))

(deftest test/string-error-eof
  (check-error "fin de fichier dans chaîne → lexer-error"
               lexer-error
               (tokenize-string "\"")))

(deftest test/string-error-newline
  (check-error "retour à la ligne dans chaîne → lexer-error"
               lexer-error
               (tokenize-string "\"hello
\"")))


;;; --------------------------------------------------------------------------
;;;  Tests : identifiants
;;; --------------------------------------------------------------------------

(deftest test/identifiers
  (check "simple"        (string= "lda"   (first-val "lda")))
  (check "majuscules"    (string= "LDA"   (first-val "LDA")))
  (check "avec chiffre"  (string= "loop1" (first-val "loop1")))
  (check "avec tiret bas" (string= "my_var" (first-val "my_var")))
  (check "kind = :identifier" (eq :identifier (first-kind "lda"))))

(deftest test/directive
  (check ".byte"    (string= ".byte"  (first-val ".byte")))
  (check ".word"    (string= ".word"  (first-val ".word")))
  (check ".org"     (string= ".org"   (first-val ".org")))
  (check ".equ"     (string= ".equ"   (first-val ".equ")))
  (check "kind = :identifier" (eq :identifier (first-kind ".byte"))))

(deftest test/local-label-at
  (check "@loop"    (string= "@loop" (first-val "@loop")))
  (check "@1"       (string= "@1"    (first-val "@1")))
  (check "kind = :identifier" (eq :identifier (first-kind "@loop"))))


;;; --------------------------------------------------------------------------
;;;  Tests : labels
;;; --------------------------------------------------------------------------

(deftest test/label-def
  (let ((tokens (tok "loop:")))
    (check "un token label-def"
           (= 1 (length tokens)))
    (check "kind = :label-def"
           (eq :label-def (token-kind (first tokens))))
    (check "value = \"loop\""
           (string= "loop" (token-value (first tokens))))))

(deftest test/label-def-global
  (let ((tokens (tok "main::")))
    (check "un token label-def global"
           (= 1 (length tokens)))
    (check "kind = :label-def"
           (eq :label-def (token-kind (first tokens))))
    (check "value contient :global"
           (member :global (token-value (first tokens))))))

(deftest test/numeric-label-def
  (let ((tokens (tok "1:")))
    (check "un token numeric-label-def"
           (= 1 (length tokens)))
    (check "kind = :numeric-label-def"
           (eq :numeric-label-def (token-kind (first tokens))))
    (check "value = 1"
           (= 1 (token-value (first tokens))))))


;;; --------------------------------------------------------------------------
;;;  Tests : opérateurs et ponctuations
;;; --------------------------------------------------------------------------

(deftest test/punctuation
  (check ","    (eq :comma     (first-kind ",")))
  (check ":"    (eq :colon     (first-kind ":")))
  (check "#"    (eq :hash      (first-kind "#")))
  (check "("    (eq :lparen    (first-kind "(")))
  (check ")"    (eq :rparen    (first-kind ")")))
  (check "["    (eq :lbracket  (first-kind "[")))
  (check "]"    (eq :rbracket  (first-kind "]")))
  (check "+"    (eq :plus      (first-kind "+")))
  (check "-"    (eq :minus     (first-kind "-")))
  (check "*"    (eq :star      (first-kind "*")))
  (check "&"    (eq :ampersand (first-kind "&")))
  (check "^"    (eq :caret     (first-kind "^")))
  (check "~"    (eq :tilde     (first-kind "~")))
  (check "="    (eq :equals    (first-kind "=")))
  (check "|"    (eq :pipe      (first-kind "|")))
  (check "<"    (eq :lt        (first-kind "<")))
  (check ">"    (eq :gt        (first-kind ">")))
  (check "<<"   (eq :lshift    (first-kind "<<")))
  (check ">>"   (eq :rshift    (first-kind ">>")))
  (check "/"    (eq :slash     (first-kind "/"))))


;;; --------------------------------------------------------------------------
;;;  Tests : commentaires
;;; --------------------------------------------------------------------------

(deftest test/comments
  (check "commentaire ; ignoré"
         (null (kinds "; ceci est un commentaire")))
  (check "commentaire // ignoré"
         (null (kinds "// ceci est un commentaire")))
  (check "code avant commentaire"
         (equal '(:identifier) (kinds "lda ; commentaire")))
  (check "code avant commentaire //"
         (equal '(:identifier) (kinds "lda // commentaire"))))


;;; --------------------------------------------------------------------------
;;;  Tests : séquences complètes
;;; --------------------------------------------------------------------------

(deftest test/lda-immediate
  ;; LDA #$FF -> :identifier :hash :integer (3 tokens)
  ;; values* retourne (nil nil 255) car # et LDA ont value=nil
  (let ((ks (kinds "LDA #$FF")))
    (check "3 tokens"        (= 3 (length ks)))
    (check "mnémonique"      (eq :identifier  (first ks)))
    (check "hash"            (eq :hash        (second ks)))
    (check "valeur"          (eq :integer     (third ks)))
    (check "valeur = 255"    (= 255 (third (values* "LDA #$FF"))))))

(deftest test/lda-indirect-x
  ;; LDA ($00,X) -> :identifier :lparen :integer :comma :identifier :rparen (6 tokens)
  (let ((ks (kinds "LDA ($00,X)")))
    (check "6 tokens"    (= 6 (length ks)))
    (check ":identifier" (eq :identifier (nth 0 ks)))
    (check ":lparen"     (eq :lparen     (nth 1 ks)))
    (check ":integer"    (eq :integer    (nth 2 ks)))
    (check ":comma"      (eq :comma      (nth 3 ks)))
    (check ":identifier" (eq :identifier (nth 4 ks)))
    (check ":rparen"     (eq :rparen     (nth 5 ks)))))

(deftest test/sta-indirect-y
  ;; STA ($00),Y -> :identifier :lparen :integer :rparen :comma :identifier (6 tokens)
  (let ((ks (kinds "STA ($00),Y")))
    (check "6 tokens"    (= 6 (length ks)))
    (check ":rparen"     (eq :rparen  (nth 3 ks)))
    (check ":comma"      (eq :comma   (nth 4 ks)))))

(deftest test/equ-directive
  ;; SCREEN = $0400
  (let* ((ks (kinds "SCREEN = $0400"))
         (vs (values* "SCREEN = $0400")))
    (check "3 tokens"    (= 3 (length ks)))
    (check ":identifier" (eq :identifier (nth 0 ks)))
    (check ":equals"     (eq :equals     (nth 1 ks)))
    (check ":integer"    (eq :integer    (nth 2 ks)))
    (check "valeur"      (= #x0400 (nth 2 vs)))))

(deftest test/label-and-instruction
  ;; loop: DEX
  (let ((ks (kinds "loop: DEX")))
    (check "2 tokens"    (= 2 (length ks)))
    (check ":label-def"  (eq :label-def  (nth 0 ks)))
    (check ":identifier" (eq :identifier (nth 1 ks)))))

(deftest test/dot-byte-directive
  ;; .byte $01, $02, $03 -> :identifier :integer :comma :integer :comma :integer (6 tokens)
  (let ((ks (kinds ".byte $01, $02, $03")))
    (check "6 tokens"   (= 6 (length ks)))
    (check "directive"  (eq :identifier (nth 0 ks)))
    (check "virgule 1"  (eq :comma      (nth 2 ks)))
    (check "virgule 2"  (eq :comma      (nth 4 ks)))))

(deftest test/multiline
  ;; Plusieurs lignes — :newline entre les instructions
  (let ((tokens (tokenize-string "LDA #0
STA $D020")))
    (let ((ks (mapcar #'token-kind tokens)))
      (check "newline entre instructions"
             (member :newline ks))
      (check "pas de newline en double"
             (notany (lambda (pair)
                       (and (eq (car pair) :newline)
                            (eq (cdr pair) :newline)))
                     (mapcar #'cons ks (cdr ks)))))))

(deftest test/newline-dedup
  ;; Les lignes vides ne produisent qu'un seul :newline
  (let ((tokens (tokenize-string (format nil "LDA #0~%~%~%STA $D020"))))
    (let ((ks (mapcar #'token-kind tokens)))
      (check "pas de :newline consécutifs"
             (notany (lambda (pair)
                       (and (eq (car pair) :newline)
                            (eq (cdr pair) :newline)))
                     (mapcar #'cons ks (cdr ks)))))))

(deftest test/expression-tokens
  ;; BASE + OFFSET * 2
  (let ((ks (kinds "BASE + OFFSET * 2")))
    (check "5 tokens"    (= 5 (length ks)))
    (check "id"          (eq :identifier (nth 0 ks)))
    (check "+"           (eq :plus       (nth 1 ks)))
    (check "id"          (eq :identifier (nth 2 ks)))
    (check "*"           (eq :star       (nth 3 ks)))
    (check "int"         (eq :integer    (nth 4 ks)))))

(deftest test/source-loc
  ;; Les tokens portent leur localisation source.
  ;; "LDA\n STA" donne [:identifier"LDA" :newline :identifier"STA"]
  ;; donc t1=LDA (index 0), t2=STA (index 2, après le :newline)
  (let* ((tokens (tok (format nil "LDA~% STA")))
         (t1 (first tokens))
         (t2 (third tokens)))   ; STA est le 3ème token (1=LDA, 2=newline, 3=STA)
    (check "t1 ligne 1"  (= 1 (cl-asm/ir:source-loc-line   (token-loc t1))))
    (check "t1 col 1"    (= 1 (cl-asm/ir:source-loc-column (token-loc t1))))
    (check "t2 ligne 2"  (= 2 (cl-asm/ir:source-loc-line   (token-loc t2))))
    (check "t2 col 2"    (= 2 (cl-asm/ir:source-loc-column (token-loc t2))))))

(deftest test/unknown-char
  (check-error "caractère inconnu → lexer-error"
               lexer-error
               (tokenize-string "LDA ?")))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests cl-asm/lexer ===~%")
  (test/integer-decimal)
  (test/integer-hex-dollar)
  (test/integer-hex-0x)
  (test/integer-binary)
  (test/char-literal)
  (test/string-literal)
  (test/string-error-eof)
  (test/string-error-newline)
  (test/identifiers)
  (test/directive)
  (test/local-label-at)
  (test/label-def)
  (test/label-def-global)
  (test/numeric-label-def)
  (test/punctuation)
  (test/comments)
  (test/lda-immediate)
  (test/lda-indirect-x)
  (test/sta-indirect-y)
  (test/equ-directive)
  (test/label-and-instruction)
  (test/dot-byte-directive)
  (test/multiline)
  (test/newline-dedup)
  (test/expression-tokens)
  (test/source-loc)
  (test/unknown-char)
  (when *failures*
    (format t "~&Échecs lexer :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
