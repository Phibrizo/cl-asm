; -*- coding: utf-8 -*-
;;; tests/test-lasm.lisp

(defpackage #:cl-asm/test.lasm
  (:use #:cl #:cl-asm/lasm)
  (:export #:run-all-tests #:*pass* #:*fail* #:*failures*))

(in-package #:cl-asm/test.lasm)


;;; --------------------------------------------------------------------------
;;;  Infra de test
;;; --------------------------------------------------------------------------

(defvar *pass* 0)
(defvar *fail* 0)
(defvar *failures* '())

(defmacro check (description form)
  `(let ((result (handler-case ,form
                   (error (e)
                     (format t "~&  ERREUR inattendue dans [~A] : ~A~%"
                             ,description e)
                     nil))))
     (if result
         (progn (incf *pass*) (format t "~&  OK  ~A~%" ,description))
         (progn (incf *fail*)
                (push ,description *failures*)
                (format t "~&  KO  ~A~%" ,description)))))

(defmacro deftest (name &body body)
  `(defun ,name ()
     (format t "~&~%[~A]~%" ',name)
     ,@body))

(defun asm (source &key (origin #x0801))
  (assemble-lasm-string source :origin origin))

(defun bytes= (vec &rest expected)
  (and (= (length vec) (length expected))
       (every #'= vec expected)))


;;; --------------------------------------------------------------------------
;;;  Tests : instructions implied
;;; --------------------------------------------------------------------------

(deftest test/implied
  (check "NOP = EA"  (bytes= (asm "(nop)") #xEA))
  (check "RTS = 60"  (bytes= (asm "(rts)") #x60))
  (check "CLC = 18"  (bytes= (asm "(clc)") #x18))
  (check "SEI = 78"  (bytes= (asm "(sei)") #x78))
  (check "TAX = AA"  (bytes= (asm "(tax)") #xAA))
  (check "PHA = 48"  (bytes= (asm "(pha)") #x48)))

(deftest test/accumulator
  (check "LSR :a = 4A" (bytes= (asm "(lsr :a)") #x4A))
  (check "ASL :a = 0A" (bytes= (asm "(asl :a)") #x0A))
  (check "ROL :a = 2A" (bytes= (asm "(rol :a)") #x2A))
  (check "ROR :a = 6A" (bytes= (asm "(ror :a)") #x6A)))


;;; --------------------------------------------------------------------------
;;;  Tests : mode immediat
;;; --------------------------------------------------------------------------

(deftest test/immediate
  (check "LDA :imm #xFF = A9 FF"
         (bytes= (asm "(lda :imm #xFF)") #xA9 #xFF))
  (check "LDA :imm 0 = A9 00"
         (bytes= (asm "(lda :imm 0)") #xA9 #x00))
  (check "LDX :imm 1 = A2 01"
         (bytes= (asm "(ldx :imm 1)") #xA2 #x01))
  (check "ADC :imm #x10 = 69 10"
         (bytes= (asm "(adc :imm #x10)") #x69 #x10)))


;;; --------------------------------------------------------------------------
;;;  Tests : deduction automatique du mode
;;; --------------------------------------------------------------------------

(deftest test/auto-mode
  ;; Entier ≤ 255 → zero-page
  (check "LDA #x10 = A5 10 (zp auto)"
         (bytes= (asm "(lda #x10)") #xA5 #x10))
  ;; Entier > 255 → absolu
  (check "LDA #x1234 = AD 34 12 (abs auto)"
         (bytes= (asm "(lda #x1234)") #xAD #x34 #x12))
  (check "STA #xD020 = 8D 20 D0"
         (bytes= (asm "(sta #xD020)") #x8D #x20 #xD0)))


;;; --------------------------------------------------------------------------
;;;  Tests : mode force
;;; --------------------------------------------------------------------------

(deftest test/forced-mode
  ;; :abs force le mode absolu meme pour une valeur ≤ 255
  (check "LDA :abs #x10 = AD 10 00 (absolu force)"
         (bytes= (asm "(lda :abs #x10)") #xAD #x10 #x00))
  ;; :zp force le mode zero-page
  (check "LDA :zp #x10 = A5 10 (zp force)"
         (bytes= (asm "(lda :zp #x10)") #xA5 #x10)))


;;; --------------------------------------------------------------------------
;;;  Tests : modes indexes
;;; --------------------------------------------------------------------------

(deftest test/indexed
  (check "LDA :x #x10 = B5 10 (zp,X)"
         (bytes= (asm "(lda :x #x10)") #xB5 #x10))
  (check "LDA :x #x1234 = BD 34 12 (abs,X)"
         (bytes= (asm "(lda :x #x1234)") #xBD #x34 #x12))
  (check "LDA :y #x1234 = B9 34 12 (abs,Y)"
         (bytes= (asm "(lda :y #x1234)") #xB9 #x34 #x12))
  (check "STA :x #xD000 = 9D 00 D0"
         (bytes= (asm "(sta :x #xD000)") #x9D #x00 #xD0)))


;;; --------------------------------------------------------------------------
;;;  Tests : modes indirects
;;; --------------------------------------------------------------------------

(deftest test/indirect
  (check "JMP :ind #xFFFC = 6C FC FF"
         (bytes= (asm "(jmp :ind #xFFFC)") #x6C #xFC #xFF))
  (check "LDA :ix #x00 = A1 00"
         (bytes= (asm "(lda :ix #x00)") #xA1 #x00))
  (check "STA :iy #xB0 = 91 B0"
         (bytes= (asm "(sta :iy #xB0)") #x91 #xB0)))


;;; --------------------------------------------------------------------------
;;;  Tests : directives
;;; --------------------------------------------------------------------------

(deftest test/directives
  (check "org ne produit pas d'octets"
         (= 0 (length (asm "(org #xC000)"))))
  (check "db = octets bruts"
         (bytes= (asm "(db #x01 #x02 #x03)") #x01 #x02 #x03))
  (check "dw = little-endian"
         (bytes= (asm "(dw #x1234)") #x34 #x12))
  (check "fill = remplissage"
         (bytes= (asm "(fill 3 #xFF)") #xFF #xFF #xFF))
  (check "text = ASCII"
         (bytes= (asm "(text \"HI\")") (char-code #\H) (char-code #\I))))


;;; --------------------------------------------------------------------------
;;;  Tests : labels et symboles
;;; --------------------------------------------------------------------------

(deftest test/labels-forward
  ;; Label forward-ref : JMP suivi du label
  (let* ((src "(jmp 'end) (nop) (label 'end) (rts)")
         (bytes (asm src)))
    (check "JMP = 4C"    (= #x4C (aref bytes 0)))
    (check "target = $05" (= #x05 (aref bytes 1)))  ; $0801+3+1=$0805
    (check "NOP apres"   (= #xEA (aref bytes 3)))
    (check "RTS a end"   (= #x60 (aref bytes 4)))))

(deftest test/labels-backward
  (let* ((src "(label 'start) (nop) (jmp 'start)")
         (bytes (asm src)))
    (check "NOP = EA"        (= #xEA (aref bytes 0)))
    (check "JMP start = 4C"  (= #x4C (aref bytes 1)))
    (check "lo = $01"        (= #x01 (aref bytes 2)))
    (check "hi = $08"        (= #x08 (aref bytes 3)))))

(deftest test/equ-symbole
  (let* ((src "(equ 'cols 40) (lda :imm 'cols)")
         (bytes (asm src)))
    (check "LDA #40 = A9 28"
           (and (= #xA9 (aref bytes 0))
                (= 40   (aref bytes 1))))))


;;; --------------------------------------------------------------------------
;;;  Tests : puissance de Lisp
;;; --------------------------------------------------------------------------

(deftest test/lisp-dotimes
  ;; Générer 3 NOP avec dotimes
  (let ((bytes (asm "(dotimes (i 3) (nop))")))
    (check "3 NOP = EA EA EA"
           (bytes= bytes #xEA #xEA #xEA))))

(deftest test/lisp-let
  ;; Constante locale Lisp
  (let* ((src "(let ((couleur #x00))
                 (lda :imm couleur)
                 (sta #xD020))")
         (bytes (asm src)))
    (check "LDA #$00" (= #x00 (aref bytes 1)))
    (check "STA $D020" (= #x8D (aref bytes 2)))))

(deftest test/lisp-defun
  ;; Definir une fonction Lisp qui emet du code
  (let* ((src "(defun set-border (col)
                 (lda :imm col)
                 (sta #xD020))
               (set-border 0)
               (set-border 1)")
         (bytes (asm src)))
    ;; Deux fois LDA + STA = 2 x 5 = 10 octets
    (check "10 octets"   (= 10 (length bytes)))
    (check "LDA #$00"    (= #x00 (aref bytes 1)))
    (check "LDA #$01"    (= #x01 (aref bytes 6)))))

(deftest test/lisp-loop
  ;; Boucle loop pour remplir un tableau
  (let* ((src "(org #x0801)
               (loop for i from 0 to 3
                     do (lda :imm i)
                        (sta (+ #xD800 i)))")
         (bytes (asm src)))
    ;; 4 x (LDA #imm + STA abs) = 4 x 5 = 20 octets
    (check "20 octets"   (= 20 (length bytes)))
    (check "LDA #0"      (= #x00 (aref bytes 1)))
    (check "STA $D800"   (= #x8D (aref bytes 2)))
    (check "LDA #3"      (= #x03 (aref bytes 16)))))


;;; --------------------------------------------------------------------------
;;;  Tests : programme C64 complet
;;; --------------------------------------------------------------------------

(deftest test/c64-hello
  (let* ((src
           "(org #x0801)
            (db #x0B #x08 #xE2 #x07 #x9E
                #x32 #x30 #x36 #x34 #x00 #x00 #x00)
            (label 'start)
            (lda :imm 0)
            (sta #xD020)
            (rts)")
         (bytes (asm src)))
    (check "au moins 15 octets"  (>= (length bytes) 15))
    (check "stub BASIC = $0B"    (= #x0B (aref bytes 0)))
    (check "LDA #$00 = A9"       (= #xA9 (aref bytes 12)))
    (check "STA $D020 = 8D"      (= #x8D (aref bytes 14)))))


;;; --------------------------------------------------------------------------
;;;  Tests : 45GS02
;;; --------------------------------------------------------------------------

(deftest test/45gs02-basic
  (let* ((src "(ldz :imm 0) (taz) (inz) (rts)")
         (bytes (assemble-lasm-string src :target :45gs02 :origin #x2001)))
    (check "LDZ #0 = A3 00" (and (= #xA3 (aref bytes 0))
                                  (= #x00 (aref bytes 1))))
    (check "TAZ = 4B"        (= #x4B (aref bytes 2)))
    (check "INZ = 1B"        (= #x1B (aref bytes 3)))
    (check "RTS = 60"        (= #x60 (aref bytes 4)))))

(deftest test/assert-size-lasm
  (check "assert-size ok : 2 instructions 1 octet"
         (let ((bytes (assemble-lasm-string
                       "(assert-size 2 (nop) (rts))")))
           (and (= 2 (length bytes))
                (= #xEA (aref bytes 0))
                (= #x60 (aref bytes 1)))))
  (check "assert-size ok : LDA #imm = 2 octets"
         (let ((bytes (assemble-lasm-string
                       "(assert-size 2 (lda :imm 0))")))
           (= 2 (length bytes))))
  (check "assert-size echoue si taille incorrecte"
         (handler-case
             (progn (assemble-lasm-string "(assert-size 3 (nop) (rts))") nil)
           (cl-asm/ir:asm-error () t))))

(deftest test/petscii-lasm
  (check "petscii convertit a-z en A-Z PETSCII"
         ;; 'a'=0x61 → 0x41, 'b'=0x62 → 0x42
         (bytes= (assemble-lasm-string "(petscii \"ab\")")
                 #x41 #x42))
  (check "petscii convertit A-Z en shifted PETSCII"
         ;; 'A'=0x41 → 0xC1
         (bytes= (assemble-lasm-string "(petscii \"A\")")
                 #xC1))
  (check "petscii : chiffres et ponctuation inchanges"
         ;; '0'=0x30, ' '=0x20
         (bytes= (assemble-lasm-string "(petscii \"0 \")")
                 #x30 #x20)))

(deftest test/include-binary
  (let ((tmp "/tmp/cl-asm-test-incbin.bin"))
    (with-open-file (s tmp :direction :output :element-type '(unsigned-byte 8)
                          :if-exists :supersede)
      (write-byte #x01 s) (write-byte #x02 s) (write-byte #x03 s))
    (check "include-binary emet tous les octets"
           (bytes= (assemble-lasm-string
                    (format nil "(include-binary \"~A\")" tmp))
                   #x01 #x02 #x03))
    (check "include-binary avec offset"
           (bytes= (assemble-lasm-string
                    (format nil "(include-binary \"~A\" 1)" tmp))
                   #x02 #x03))
    (check "include-binary avec offset et count"
           (bytes= (assemble-lasm-string
                    (format nil "(include-binary \"~A\" 0 2)" tmp))
                   #x01 #x02))))

(deftest test/defenum-lasm
  (let ((bytes (assemble-lasm-string
                "(defenum color :black :white :red) (lda 'color.white)"
                :origin #x0801)))
    (check "defenum : color.white = 1" (= #x01 (aref bytes 1))))
  (let ((bytes (assemble-lasm-string
                "(defenum state :idle :run :pause) (lda 'state.count)"
                :origin #x0801)))
    (check "defenum : state.count = 3" (= #x03 (aref bytes 1))))
  (let ((bytes (assemble-lasm-string
                "(defenum dir :north :south :east :west) (lda 'dir.north)"
                :origin #x0801)))
    (check "defenum : premiere valeur = 0" (= #x00 (aref bytes 1)))))

(deftest test/defstruct-lasm
  ;; Champs 1 octet : player.hp = offset 2
  (let ((bytes (assemble-lasm-string
                "(defstruct-asm player :x :y :hp) (lda 'player.hp)"
                :origin #x0801)))
    (check "defstruct-asm : player.hp = 2" (= #x02 (aref bytes 1))))
  ;; Champ multibyte : npc.state = 0+1+1+2 = 4
  (let ((bytes (assemble-lasm-string
                "(defstruct-asm npc :x :y (:score 2) :state) (lda 'npc.state)"
                :origin #x0801)))
    (check "defstruct-asm : npc.state = 4" (= #x04 (aref bytes 1))))
  ;; .SIZE = somme des tailles
  (let ((bytes (assemble-lasm-string
                "(defstruct-asm obj :x (:y 2)) (lda 'obj.size)"
                :origin #x0801)))
    (check "defstruct-asm : obj.size = 3" (= #x03 (aref bytes 1)))))

(deftest test/65c02-basic
  ;; BRA vers instruction suivante (offset 0) : BRA $0803 avec origin $0801
  (let ((bytes (assemble-lasm-string "(bra #x0803)" :target :65c02)))
    (check "BRA opcode = 80"   (= #x80 (aref bytes 0)))
    (check "BRA offset = 00"   (= #x00 (aref bytes 1))))
  ;; STZ zp = $64
  (let ((bytes (assemble-lasm-string "(stz #x10)" :target :x16)))
    (check "STZ $10 = 64 10" (and (= #x64 (aref bytes 0))
                                   (= #x10 (aref bytes 1)))))
  ;; PHX = $DA, PLY = $7A
  (let ((bytes (assemble-lasm-string "(phx) (ply)" :target :65c02)))
    (check "PHX = DA" (= #xDA (aref bytes 0)))
    (check "PLY = 7A" (= #x7A (aref bytes 1)))))

(deftest test/r65c02-basic
  ;; RMB0 zp = $07 zp
  (let ((bytes (assemble-lasm-string "(rmb0 #x20)" :target :r65c02)))
    (check "RMB0 $20 = 07 20" (and (= #x07 (aref bytes 0))
                                    (= #x20 (aref bytes 1)))))
  ;; SMB3 zp = $B7 zp
  (let ((bytes (assemble-lasm-string "(smb3 #x10)" :target :r65c02)))
    (check "SMB3 $10 = B7 10" (and (= #xB7 (aref bytes 0))
                                    (= #x10 (aref bytes 1))))))

(deftest test/65816-basic
  ;; XBA = $EB (echange A high/low)
  (let ((bytes (assemble-lasm-string "(xba)" :target :65816 :origin #x8000)))
    (check "XBA = EB" (= #xEB (aref bytes 0))))
  ;; SEP #$30 = $E2 $30 (mode immediat obligatoire)
  (let ((bytes (assemble-lasm-string "(sep :imm #x30)" :target :snes :origin #x8000)))
    (check "SEP #$30 = E2 30" (and (= #xE2 (aref bytes 0))
                                    (= #x30 (aref bytes 1))))))

(deftest test/z80-basic
  ;; NOP Z80 = $00
  (let ((bytes (assemble-lasm-string "(zi \"NOP\")" :target :z80 :origin 0)))
    (check "Z80 NOP = 00" (= #x00 (aref bytes 0))))
  ;; LD A, B = $78
  (let ((bytes (assemble-lasm-string
                "(zi \"LD\" (z80r \"A\") (z80r \"B\"))" :target :z80 :origin 0)))
    (check "Z80 LD A,B = 78" (= #x78 (aref bytes 0))))
  ;; Directives fonctionnent avec :z80
  (let ((bytes (assemble-lasm-string "(db #x01 #x02)" :target :spectrum :origin 0)))
    (check "Z80 .byte fonctionne" (bytes= bytes #x01 #x02))))

(deftest test/m68k-basic
  ;; NOP M68K = $4E71
  (let ((bytes (assemble-lasm-string "(mi \"NOP\")" :target :m68k :origin 0)))
    (check "M68K NOP = 4E 71" (and (= #x4E (aref bytes 0))
                                    (= #x71 (aref bytes 1)))))
  ;; MOVE.W D0, D1 = $3200
  (let ((bytes (assemble-lasm-string
                "(mi \"MOVE\" :word (dn 0) (dn 1))" :target :m68k :origin 0)))
    (check "M68K MOVE.W D0,D1 = 32 00" (and (= #x32 (aref bytes 0))
                                              (= #x00 (aref bytes 1)))))
  ;; Alias :amiga
  (let ((bytes (assemble-lasm-string "(mi \"NOP\")" :target :amiga :origin 0)))
    (check "M68K alias :amiga fonctionne" (= 2 (length bytes)))))


;;; --------------------------------------------------------------------------
;;;  Tests : tables mathématiques
;;; --------------------------------------------------------------------------

(deftest test/sine-table-lasm
  (check "sine-table : 256 octets"
         (let ((bytes (assemble-lasm-string "(sine-table nil 256 127 128)")))
           (= 256 (length bytes))))
  (check "sine-table[0] = 128 (offset, sin(0)=0)"
         (let ((bytes (assemble-lasm-string "(sine-table nil 256 127 128)")))
           (= 128 (aref bytes 0))))
  (check "sine-table[64] ≈ 255 (quart de période, max)"
         (let ((bytes (assemble-lasm-string "(sine-table nil 256 127 128)")))
           (>= (aref bytes 64) 254))))

(deftest test/cosine-table-lasm
  (check "cosine-table : 256 octets"
         (let ((bytes (assemble-lasm-string "(cosine-table nil 256 127 128)")))
           (= 256 (length bytes))))
  (check "cosine-table[0] ≈ 255 (cos(0)=1, max)"
         (let ((bytes (assemble-lasm-string "(cosine-table nil 256 127 128)")))
           (>= (aref bytes 0) 254))))

(deftest test/linear-ramp-lasm
  (check "linear-ramp : N octets"
         (let ((bytes (assemble-lasm-string "(linear-ramp nil 0 255 256)")))
           (= 256 (length bytes))))
  (check "linear-ramp[0] = 0 (debut)"
         (let ((bytes (assemble-lasm-string "(linear-ramp nil 0 255 256)")))
           (= 0 (aref bytes 0))))
  (check "linear-ramp[255] = 255 (fin)"
         (let ((bytes (assemble-lasm-string "(linear-ramp nil 0 255 256)")))
           (= 255 (aref bytes 255))))
  (check "linear-ramp : 4 pas de 0 a 3"
         (let ((bytes (assemble-lasm-string "(linear-ramp nil 0 3 4)")))
           (and (= 0 (aref bytes 0))
                (= 1 (aref bytes 1))
                (= 2 (aref bytes 2))
                (= 3 (aref bytes 3))))))


;;; --------------------------------------------------------------------------
;;;  Tests : include-source
;;; --------------------------------------------------------------------------

(deftest test/include-source
  (let ((utils "/tmp/cl-asm-test-lasm-utils.lasm")
        (main  "/tmp/cl-asm-test-lasm-main.lasm"))

    ;; --- fichiers temporaires ---
    (with-open-file (s utils :direction :output :if-exists :supersede)
      (write-string
"(equ 'magic #x42)
(label 'helper)
(lda :imm 'magic)
(rts)
" s))
    (with-open-file (s main :direction :output :if-exists :supersede)
      (format s
"(org #xC000)
(include-source \"~A\")
(jsr 'helper)
(nop)
" utils))

    ;; Test 1 : bytes assemblés corrects
    ;; $C000: LDA #$42 (A9 42), RTS (60), JSR $C000 (20 00 C0), NOP (EA)
    (check "include-source : octets assemblés corrects"
      (let ((bytes (assemble-lasm main)))
        (and (>= (length bytes) 7)
             (= #xA9 (aref bytes 0))    ; LDA #
             (= #x42 (aref bytes 1))    ; magic
             (= #x60 (aref bytes 2))    ; RTS
             (= #x20 (aref bytes 3))    ; JSR
             (= #xEA (aref bytes 6))))) ; NOP

    ;; Test 2 : constante définie dans l'inclus résolue
    (check "include-source : constante MAGIC résolue à $42"
      (let ((bytes (assemble-lasm main)))
        (= #x42 (aref bytes 1))))

    ;; Test 3 : include imbriqué
    (let ((deep "/tmp/cl-asm-test-lasm-deep.lasm"))
      (with-open-file (s deep :direction :output :if-exists :supersede)
        (write-string "(equ 'deep-val #xFF)" s))
      (with-open-file (s utils :direction :output :if-exists :supersede)
        (format s "(include-source \"~A\")~%(label 'sub)~%(lda :imm 'deep-val)~%(rts)~%" deep))
      (with-open-file (s main :direction :output :if-exists :supersede)
        (format s "(org #xC000)~%(include-source \"~A\")~%(jsr 'sub)~%" utils))
      (check "include-source imbriqué : deep-val=$FF résolu"
        (let ((bytes (assemble-lasm main)))
          (and (>= (length bytes) 2)
               (= #xA9 (aref bytes 0))
               (= #xFF (aref bytes 1))))))

    ;; Test 4 : erreur si fichier inexistant
    (check "include-source : erreur si fichier introuvable"
      (handler-case
          (progn (assemble-lasm-string
                  "(include-source \"/tmp/cl-asm-lasm-inexistant-xyz.lasm\")")
                 nil)
        (error () t)))

    ;; Test 5 : inclusion circulaire détectée
    (let ((circ-a "/tmp/cl-asm-lasm-circ-a.lasm")
          (circ-b "/tmp/cl-asm-lasm-circ-b.lasm"))
      (with-open-file (s circ-a :direction :output :if-exists :supersede)
        (format s "(include-source \"~A\")~%" circ-b))
      (with-open-file (s circ-b :direction :output :if-exists :supersede)
        (format s "(include-source \"~A\")~%" circ-a))
      (check "include-source : inclusion circulaire détectée"
        (handler-case
            (progn (assemble-lasm circ-a) nil)
          (error () t))))))


;;; --------------------------------------------------------------------------
;;;  Lanceur
;;; --------------------------------------------------------------------------

(defun run-all-tests ()
  (setf *pass* 0 *fail* 0 *failures* '())
  (format t "~&=== Tests cl-asm/lasm ===~%")
  (test/implied)
  (test/accumulator)
  (test/immediate)
  (test/auto-mode)
  (test/forced-mode)
  (test/indexed)
  (test/indirect)
  (test/directives)
  (test/labels-forward)
  (test/labels-backward)
  (test/equ-symbole)
  (test/lisp-dotimes)
  (test/lisp-let)
  (test/lisp-defun)
  (test/lisp-loop)
  (test/c64-hello)
  (test/45gs02-basic)
  (test/assert-size-lasm)
  (test/petscii-lasm)
  (test/sine-table-lasm)
  (test/cosine-table-lasm)
  (test/linear-ramp-lasm)
  (test/include-binary)
  (test/include-source)
  (test/defenum-lasm)
  (test/defstruct-lasm)
  (test/65c02-basic)
  (test/r65c02-basic)
  (test/65816-basic)
  (test/z80-basic)
  (test/m68k-basic)
  (when *failures*
    (format t "~&Echecs lasm :~%")
    (dolist (f (reverse *failures*))
      (format t "  - ~A~%" f)))
  (zerop *fail*))
