; -*- coding: utf-8 -*-
;;; cl-asm.asd — définition du système ASDF pour cl-asm

(defsystem "cl-asm"
  :description "Assembleur multi-architecture en Common Lisp (6502, 45GS02)"
  :version "0.1.3"
  :author "cl-asm contributors"
  :license "MIT"
  :depends-on ()
  :components
  ((:file "src/core/version")
   (:file "src/core/backends"
    :depends-on ("src/core/version"))
   (:file "src/core/ir"
    :depends-on ("src/core/version"))
   (:file "src/core/expression"
    :depends-on ("src/core/ir"))
   (:file "src/core/symbol-table"
    :depends-on ("src/core/ir" "src/core/expression"))
   (:file "src/frontend/classic-lexer"
    :depends-on ("src/core/ir"))
   (:file "src/frontend/classic-parser"
    :depends-on ("src/core/ir"
                 "src/frontend/classic-lexer"))
   (:file "src/backend/6502"
    :depends-on ("src/core/ir"
                 "src/core/backends"
                 "src/core/expression"
                 "src/core/symbol-table"
                 "src/frontend/classic-parser"))
   (:file "src/backend/45gs02"
    :depends-on ("src/backend/6502"))
   (:file "src/backend/65c02"
    :depends-on ("src/backend/6502"))
   (:file "src/backend/r65c02"
    :depends-on ("src/backend/65c02"
                 "src/frontend/classic-parser"))
   (:file "src/backend/65816"
    :depends-on ("src/backend/6502"
                 "src/frontend/classic-parser"))
   (:file "src/backend/z80"
    :depends-on ("src/core/ir"
                 "src/core/backends"
                 "src/core/expression"
                 "src/core/symbol-table"
                 "src/frontend/classic-parser"))
   (:file "src/backend/m68k"
    :depends-on ("src/core/ir"
                 "src/core/backends"
                 "src/core/expression"
                 "src/core/symbol-table"
                 "src/frontend/classic-parser"))
   (:file "src/backend/i8080"
    :depends-on ("src/core/ir"
                 "src/core/backends"
                 "src/core/expression"
                 "src/core/symbol-table"
                 "src/frontend/classic-parser"))
   (:file "src/frontend/lasm"
    :depends-on ("src/core/ir"
                 "src/core/expression"
                 "src/core/symbol-table"
                 "src/backend/6502"
                 "src/backend/45gs02"
                 "src/backend/65c02"
                 "src/backend/r65c02"
                 "src/backend/65816"
                 "src/backend/z80"
                 "src/backend/m68k"
                 "src/backend/i8080"))
   (:file "src/emit/output"
    :depends-on ("src/core/ir"
                 "src/backend/6502"))))

(defsystem "cl-asm/tests"
  :description "Suite de tests pour cl-asm"
  :depends-on ("cl-asm")
  :components
  ((:file "tests/test-expression"
    :depends-on ())
   (:file "tests/test-symbol-table"
    :depends-on ())
   (:file "tests/test-lexer"
    :depends-on ())
   (:file "tests/test-parser"
    :depends-on ())
   (:file "tests/test-6502"
    :depends-on ())
   (:file "tests/test-65c02"
    :depends-on ())
   (:file "tests/test-lasm"
    :depends-on ())
   (:file "tests/test-conditional"
    :depends-on ())
   (:file "tests/test-macros"
    :depends-on ("tests/test-6502"))
   (:file "tests/test-45gs02"
    :depends-on ("tests/test-6502"))
   (:file "tests/test-r65c02"
    :depends-on ("tests/test-65c02"))
   (:file "tests/test-65816"
    :depends-on ("tests/test-6502"))
   (:file "tests/test-z80"
    :depends-on ())
   (:file "tests/test-8080"
    :depends-on ())
   (:file "tests/test-m68k-parser"
    :depends-on ())
   (:file "tests/test-m68k"
    :depends-on ())
   (:file "tests/run-tests"
    :depends-on ("tests/test-expression"
                 "tests/test-symbol-table"
                 "tests/test-lexer"
                 "tests/test-parser"
                 "tests/test-6502"
                 "tests/test-65c02"
                 "tests/test-lasm"
                 "tests/test-conditional"
                 "tests/test-macros"
                 "tests/test-45gs02"
                 "tests/test-r65c02"
                 "tests/test-65816"
                 "tests/test-z80"
                 "tests/test-8080"
                 "tests/test-m68k-parser"
                 "tests/test-m68k")))
  :perform (test-op (o c)
             (let ((output (make-string-output-stream)))
               (let ((*standard-output* output))
                 (uiop:symbol-call :cl-asm/test :run-all-tests))
               (write-string (get-output-stream-string output)
                             *standard-output*)
               (finish-output *standard-output*))))
