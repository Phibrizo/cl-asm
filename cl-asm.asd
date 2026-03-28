; -*- coding: utf-8 -*-
;;; cl-asm.asd — définition du système ASDF pour cl-asm

(defsystem "cl-asm"
  :description "Assembleur multi-architecture en Common Lisp (6502, 45GS02)"
  :version "0.18.0"
  :author "cl-asm contributors"
  :license "MIT"
  :depends-on ()
  :components
  ((:file "src/core/version")
   (:file "src/core/backends"
    :depends-on ("src/core/version"))
   (:file "src/core/disassemblers"
    :depends-on ("src/core/version"))
   (:file "src/core/emitters"
    :depends-on ("src/core/version"))
   (:file "src/core/linker"
    :depends-on ("src/core/ir"
                 "src/core/symbol-table"))
   (:file "src/core/linker-script"
    :depends-on ("src/core/linker"
                 "src/core/symbol-table"))
   (:file "src/core/optimizer"
    :depends-on ("src/core/ir"))
   (:file "src/core/restarts"
    :depends-on ("src/core/ir"))
   (:file "src/core/ir"
    :depends-on ("src/core/version"))
   (:file "src/core/debug-map"
    :depends-on ("src/core/ir"))
   (:file "src/core/expression"
    :depends-on ("src/core/ir"))
   (:file "src/core/symbol-table"
    :depends-on ("src/core/ir" "src/core/expression" "src/core/restarts"))
   (:file "src/frontend/classic-lexer"
    :depends-on ("src/core/ir"))
   (:file "src/frontend/classic-parser"
    :depends-on ("src/core/ir"
                 "src/frontend/classic-lexer"))
   (:file "src/backend/6502"
    :depends-on ("src/core/ir"
                 "src/core/debug-map"
                 "src/core/backends"
                 "src/core/linker"
                 "src/core/optimizer"
                 "src/core/restarts"
                 "src/core/expression"
                 "src/core/symbol-table"
                 "src/frontend/classic-parser"))
   (:file "src/backend/6510"
    :depends-on ("src/backend/6502"))
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
   (:file "src/backend/i8086"
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
                 "src/backend/6510"
                 "src/backend/45gs02"
                 "src/backend/65c02"
                 "src/backend/r65c02"
                 "src/backend/65816"
                 "src/backend/z80"
                 "src/backend/m68k"
                 "src/backend/i8080"
                 "src/backend/i8086"))
   (:file "src/emit/output"
    :depends-on ("src/core/ir"
                 "src/core/disassemblers"
                 "src/core/emitters"
                 "src/backend/6502"))
   (:file "src/emit/ihex"
    :depends-on ("src/core/emitters"))
   (:file "src/emit/srec"
    :depends-on ("src/core/emitters"))
   (:file "src/simulator/6502"
    :depends-on ())
   (:file "src/disassembler/6502"
    :depends-on ("src/core/disassemblers"))
   (:file "src/disassembler/45gs02"
    :depends-on ("src/disassembler/6502"))
   (:file "src/disassembler/65c02"
    :depends-on ("src/disassembler/6502"))
   (:file "src/debugger/6502"
    :depends-on ("src/core/ir"
                 "src/core/debug-map"
                 "src/simulator/6502"
                 "src/disassembler/6502"
                 "src/disassembler/45gs02"))
   (:file "src/profiler/6502"
    :depends-on ("src/simulator/6502"
                 "src/disassembler/6502"))
   (:file "src/optimizer/6502"
    :depends-on ("src/core/optimizer"
                 "src/backend/6502"))
   (:file "src/optimizer/65c02"
    :depends-on ("src/optimizer/6502"
                 "src/backend/65c02"))))

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
   (:file "tests/test-6510"
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
   (:file "tests/test-8086"
    :depends-on ())
   (:file "tests/test-sim-6502"
    :depends-on ())
   (:file "tests/test-sim-programs"
    :depends-on ())
   (:file "tests/test-acme2clasm"
    :depends-on ())
   (:file "tests/test-disasm-6502"
    :depends-on ())
   (:file "tests/test-disasm-45gs02"
    :depends-on ())
   (:file "tests/test-disasm-65c02"
    :depends-on ())
   (:file "tests/test-debugger-6502"
    :depends-on ())
   (:file "tests/test-m68k-parser"
    :depends-on ())
   (:file "tests/test-m68k"
    :depends-on ())
   (:file "tests/test-linker-6502"
    :depends-on ())
   (:file "tests/test-linker-script"
    :depends-on ())
   (:file "tests/test-profiler-6502"
    :depends-on ())
   (:file "tests/test-optimizer"
    :depends-on ())
   (:file "tests/test-restarts"
    :depends-on ())
   (:file "tests/test-listing"
    :depends-on ("tests/test-6502"
                 "tests/test-disasm-6502"
                 "tests/test-disasm-65c02"))
   (:file "tests/test-emitters"
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
                 "tests/test-6510"
                 "tests/test-45gs02"
                 "tests/test-r65c02"
                 "tests/test-65816"
                 "tests/test-z80"
                 "tests/test-8080"
                 "tests/test-8086"
                 "tests/test-sim-6502"
                 "tests/test-sim-programs"
                 "tests/test-acme2clasm"
                 "tests/test-disasm-6502"
                 "tests/test-disasm-45gs02"
                 "tests/test-disasm-65c02"
                 "tests/test-debugger-6502"
                 "tests/test-m68k-parser"
                 "tests/test-m68k"
                 "tests/test-linker-6502"
                 "tests/test-linker-script"
                 "tests/test-profiler-6502"
                 "tests/test-optimizer"
                 "tests/test-restarts"
                 "tests/test-listing"
                 "tests/test-emitters")))
  :perform (test-op (o c)
             (let ((output (make-string-output-stream)))
               (let ((*standard-output* output))
                 (uiop:symbol-call :cl-asm/test :run-all-tests))
               (write-string (get-output-stream-string output)
                             *standard-output*)
               (finish-output *standard-output*))))
