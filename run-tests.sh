#!/bin/bash
# run-tests.sh — Lance la suite de tests complète de cl-asm.
# Doit être exécuté depuis la racine du projet (le répertoire cl-asm/).

sbcl --load src/core/version.lisp \
     --load src/core/backends.lisp \
     --load src/core/ir.lisp \
     --load src/core/expression.lisp \
     --load src/core/symbol-table.lisp \
     --load src/frontend/classic-lexer.lisp \
     --load src/frontend/classic-parser.lisp \
     --load src/backend/6502.lisp \
     --load src/backend/45gs02.lisp \
     --load src/emit/output.lisp \
     --load src/backend/65c02.lisp \
     --load src/backend/r65c02.lisp \
     --load src/frontend/lasm.lisp \
     --load tests/test-65c02.lisp \
     --load tests/test-r65c02.lisp \
     --load tests/test-lasm.lisp \
     --load tests/test-conditional.lisp \
     --load tests/test-macros.lisp \
     --load tests/test-45gs02.lisp \
     --load tests/test-6502.lisp \
     --load tests/test-parser.lisp \
     --load tests/test-lexer.lisp \
     --load tests/test-expression.lisp \
     --load tests/test-symbol-table.lisp \
     --load tests/run-tests.lisp \
     --eval "(cl-asm/test:run-all-tests)" \
     --quit
