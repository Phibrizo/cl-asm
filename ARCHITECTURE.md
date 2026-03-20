# cl-asm Architecture

## Overview

cl-asm is structured in three independent layers:

```
┌─────────────────────────────────────────────┐
│  Frontends (pluggable syntaxes)             │
│  classic (ca65-like) · .lasm (Lisp native)  │
└──────────────┬──────────────────────────────┘
               │ produces an IR-PROGRAM
               ▼
┌─────────────────────────────────────────────┐
│  Intermediate Representation (IR)           │
│  ir-label · ir-instruction · ir-directive   │
└──────────────┬──────────────────────────────┘
               │ consumed by
               ▼
┌─────────────────────────────────────────────┐
│  Backends (target architectures)            │
│  6502 · 65C02 · 45GS02 · Z80 (future)      │
└──────────────┬──────────────────────────────┘
               │ produces a byte vector
               ▼
┌─────────────────────────────────────────────┐
│  Emitters (file formats)                    │
│  BIN · PRG (C64) · listing · ROM (future)  │
└─────────────────────────────────────────────┘
```

---

## Common Lisp Packages

| Package | File | Role |
|---|---|---|
| `cl-asm/version` | `src/core/version.lisp` | Version number |
| `cl-asm/backends` | `src/core/backends.lisp` | Extensible backend registry |
| `cl-asm/ir` | `src/core/ir.lisp` | IR structures and conditions |
| `cl-asm/expression` | `src/core/expression.lisp` | Expression evaluator |
| `cl-asm/symbol-table` | `src/core/symbol-table.lisp` | Symbol table |
| `cl-asm/lexer` | `src/frontend/classic-lexer.lisp` | Tokeniser |
| `cl-asm/parser` | `src/frontend/classic-parser.lisp` | Parser → IR |
| `cl-asm/backend.6502` | `src/backend/6502.lisp` | 6502 backend |
| `cl-asm/backend.45gs02` | `src/backend/45gs02.lisp` | 45GS02 backend |
| `cl-asm/backend.65c02` | `src/backend/65c02.lisp` | 65C02 backend (X16) |
| `cl-asm/backend.r65c02` | `src/backend/r65c02.lisp` | R65C02 backend (Rockwell) |
| `cl-asm/lasm` | `src/frontend/lasm.lisp` | Native Lisp frontend |
| `cl-asm/emit` | `src/emit/output.lisp` | File emitters |
| `cl-asm/test.*` | `tests/test-*.lisp` | Test suites |

---

## Module `cl-asm/ir`

Defines all data structures shared between frontends and backends.

### Main structures

```lisp
(ir-label       :name STRING :kind (:local|:global|:numeric) :number INT :loc)
(ir-instruction :mnemonic STRING :operands LIST :loc)
(ir-directive   :name KEYWORD :args LIST :loc)
(ir-operand     :kind KIND :value EXPR :index-reg KEYWORD :size-hint KEYWORD :loc)
```

### Operand kinds

| Kind | Syntax | Description |
|---|---|---|
| `:immediate` | `#expr` | Immediate value |
| `:direct` | `addr` or `addr,X/Y/Z` | Direct address |
| `:indirect` | `(addr)` | Classic indirect |
| `:indirect-x` | `(addr,X)` | Pre-indexed X |
| `:indirect-y` | `(addr),Y` or `(addr),Z` | Post-indexed |
| `:indirect-sp-y` | `(addr,SP),Y` | Stack (45GS02) |
| `:indirect-32` | `[addr]` | 32-bit indirect (45GS02) |
| `:indirect-32-z` | `[addr],Z` | 32-bit indirect + Z |
| `:register` | `A`, `X`, `Y`… | Register (accumulator) |

### Containers

```lisp
(ir-section :name KEYWORD :origin INT :nodes LIST :binary VECTOR)
(ir-program :sections LIST :entry-point STRING)
```

---

## Module `cl-asm/expression`

Evaluates arithmetic expressions represented as prefix trees.

### Interface

```lisp
(eval-expr       EXPR ENV)   ; → (values VALUE RESOLVEDP)
(eval-expr/byte  EXPR ENV)   ; → integer [0,255] or range error
(eval-expr/sbyte EXPR ENV)   ; → integer [-128,127]
(eval-expr/word  EXPR ENV)   ; → integer [0,65535]
(make-env :symbol-table ST :pc ADDR)
(constant-expr-p EXPR)       ; → BOOLEAN
```

### Operators

| Family | Operators |
|---|---|
| Arithmetic | `:+` `:-` `:*` `:/` `:mod` `:neg` `:abs` `:min` `:max` |
| Bitwise | `:&` `:bitor` `:^` `:~` |
| Shifts | `:>>` `:<<` |
| Extraction | `:lo` `:hi` `:bank` `:highest` `:word` |
| Comparison | `:=` `:/=` `:<` `:<=` `:>` `:>=` |
| Logic | `:and` `:or` `:not` |
| Special | `:neg` `:current-pc` `:defined` `:if` |

### Forward-references

In pass 1, `eval-expr` returns `(values :unresolved nil)` for a missing
symbol without raising an error. In pass 2, any missing symbol raises
`asm-undefined-label`.

---

## Module `cl-asm/symbol-table`

### Interface

```lisp
(make-symbol-table)
(define-label    ST NAME &key source-loc)
(define-constant ST NAME VALUE &key source-loc)
(define-equate   ST NAME EXPRESSION &key source-loc)
(define-numeric-label  ST NUMBER)
(resolve-numeric-label ST NUMBER :backward|:forward)
(resolve-symbol   ST NAME &key source-loc)  ; → (values VALUE RESOLVEDP)
(symbol-defined-p ST NAME)
(with-local-scope (ST) &body BODY)
(begin-pass-2 ST)
```

### Two passes

```
Pass 1: traverse IR → register labels → estimate sizes
        (forward-refs return :unresolved without error)

(begin-pass-2 ST) → reset PC, clear numeric labels

Pass 2: traverse IR → encode → all symbols must be resolved
```

---

## Module `cl-asm/lexer`

### Tokens produced

```
:integer     42  $FF  0xFF  %1010  'A'
:string      "hello"
:identifier  lda  .byte  start
:label-def   loop:  main::
:numeric-label-def  1:  2:
:comma :colon :hash :lparen :rparen :lbracket :rbracket
:plus :minus :star :slash :ampersand :pipe :caret :tilde
:lt :gt :lshift :rshift :equals
:newline :eof
```

### Interface

```lisp
(tokenize-string SOURCE &key file)  ; → list of TOKEN
(tokenize-file   PATH)
```

---

## Module `cl-asm/parser`

Recursive descent parser. Produces an `IR-PROGRAM`.

### Interface

```lisp
(parse-string SOURCE &key file section)
(parse-tokens TOKENS &key file section)
(parse-file   PATH   &key section)
```

### Parsed expressions

```
BASE+1    → (:+ "BASE" 1)
<VEC      → (:lo "VEC")
>VEC      → (:hi "VEC")
(A|B)&$FF → (:& (:bitor "A" "B") 255)
*-2       → (:- :current-pc 2)
```

---

## Module `cl-asm/backends`

Extensible backend registry. Each backend registers itself once via
`register-backend` at the end of its source file. The CLI script and
any other tool query the registry instead of hard-coding the list of
supported targets.

### Exported API

```lisp
(cl-asm/backends:register-backend
  :6502                          ; keyword — internal identifier
  '("6502" "mos6502" "c64")      ; CLI aliases (case-insensitive)
  "CL-ASM/BACKEND.6502"          ; package name string
  "ASSEMBLE-FILE"                ; function name string
  "MOS 6502 / Commodore 64"      ; French description
  "MOS 6502 / Commodore 64")     ; English description

(cl-asm/backends:find-backend-by-alias "c64")   ; → backend-entry for :6502
(cl-asm/backends:all-backends)                  ; → list of all entries
(cl-asm/backends:backend-keyword entry)         ; → :6502
(cl-asm/backends:backend-aliases  entry)        ; → ("6502" "mos6502" "c64")
(cl-asm/backends:backend-package  entry)        ; → "CL-ASM/BACKEND.6502"
(cl-asm/backends:backend-function entry)        ; → "ASSEMBLE-FILE"
```

### Adding a new backend

Create `src/backend/myarch.lisp`, implement `assemble-file-myarch`, then
add at the end of the file:

```lisp
(cl-asm/backends:register-backend
  :myarch '("myarch") "CL-ASM/BACKEND.MYARCH" "ASSEMBLE-FILE-MYARCH"
  "My architecture" "My architecture")
```

Add the file to `cl-asm.asd` and the three test scripts. No other file
needs to be modified.

---

## Module `cl-asm/backend.6502`

### Interface

```lisp
(assemble        PROGRAM &key origin section)
(assemble-string SOURCE  &key origin)
(assemble-file   PATH    &key origin)

;; Low level — also used by 65C02 and 45GS02 backends
(encode-instruction INSTR SYMTABLE PC PASS
                    &key table resolve-fn)  ; → (values BYTES SIZE)
(resolve-mode       OPERAND ADDR-VALUE)     ; → mode keyword
(eval-operand-value OPERAND SYMTABLE PC)    ; → (values VALUE RESOLVEDP)
```

The `&key table resolve-fn` parameters let derived backends reuse the
full encoding logic with their own instruction table and mode resolver.

### Addressing modes

| Mode | Syntax | Bytes |
|---|---|---|
| `:implied` | `NOP` | 1 |
| `:accumulator` | `LSR A` | 1 |
| `:immediate` | `LDA #$FF` | 2 |
| `:zero-page` | `LDA $10` | 2 |
| `:zero-page-x/y` | `LDA $10,X` | 2 |
| `:absolute` | `LDA $1234` | 3 |
| `:absolute-x/y` | `LDA $1234,X` | 3 |
| `:indirect` | `JMP ($FFFC)` | 3 |
| `:indirect-x` | `LDA ($00,X)` | 2 |
| `:indirect-y` | `LDA ($00),Y` | 2 |
| `:relative` | `BNE label` | 2 |

---

## Module `cl-asm/backend.45gs02`

6502 superset. Table built by copying the 6502 table then adding extensions.

### New instructions

| Group | Instructions |
|---|---|
| Z register | `LDZ` `STZ` `INZ` `DEZ` `PHZ` `PLZ` `TAZ` `TZA` |
| B register | `TAB` `TBA` `TSY` `TYS` |
| 16-bit memory | `INW` `DEW` `ASW` `ROW` |
| Long branches | `LBCC` `LBCS` `LBEQ` `LBNE` `LBMI` `LBPL` `LBVC` `LBVS` |
| Q 32-bit | `LDQ` `STQ` `ADCQ` `SBCQ` `ANDQ` `ORAQ` `EORQ` `ASLQ` `LSRQ` `ROLQ` `RORQ` `ASRQ` `BITQ` `CMPQ` |

### Prefix encoding

| Prefix | Usage |
|---|---|
| `$EA` | Activates 32-bit indirect `[$nn]` |
| `$42` | 16-bit long branch |
| `$42 $42` | 32-bit Q instruction |

```
LDQ ($20),Z  →  $42 $42 $B2 $20   (4 bytes)
LBNE label   →  $42 $D0 lo hi     (4 bytes)
LDA [$20]    →  $EA $B1 $20       (3 bytes)
```

---

## Module `cl-asm/backend.65c02`

6502 superset for the WDC 65C02 (Commander X16). Default origin: `$0801`.

### New instructions

| Instruction | Opcode | Bytes |
|---|---|---|
| `BRA rel` | `$80` | 2 |
| `STZ` zp/zp,X/abs/abs,X | `$64/$74/$9C/$9E` | 2-3 |
| `TRB` zp/abs | `$14/$1C` | 2-3 |
| `TSB` zp/abs | `$04/$0C` | 2-3 |
| `PHX` / `PLX` | `$DA` / `$FA` | 1 |
| `PHY` / `PLY` | `$5A` / `$7A` | 1 |
| `INC A` / `DEC A` | `$1A` / `$3A` | 1 |

### New mode: `:zero-page-indirect`

`LDA ($nn)` — indirect without index, ZP only. Absent from original 6502.
Opcodes: `$B2` (LDA), `$92` (STA), `$72` (ADC), `$F2` (SBC)…

### Extended modes on existing instructions

- `BIT`: `:immediate`, `:zero-page-x`, `:absolute-x`
- `JMP`: `:indirect-absolute-x` (`$7C`)
- `ADC/SBC/AND/ORA/EOR/CMP/LDA/STA`: `:zero-page-indirect`

---

## Module `cl-asm/lasm`

Native Lisp frontend. `.lasm` files are valid Common Lisp where each
mnemonic is a function.

### Interface

```lisp
(assemble-lasm-string SOURCE &key origin target)
(assemble-lasm        PATH   &key origin target)
(load-lasm-string     SOURCE)  ; → IR-PROGRAM
(load-lasm            PATH)    ; → IR-PROGRAM
```

### Addressing mode keywords

| Keyword | Mode |
|---|---|
| `:imm` | Immediate |
| `:x` `:y` `:z` | Indexed X/Y/Z |
| `:ind` | Indirect |
| `:ix` `:iy` `:iz` | Pre/post-indexed |
| `:abs` | Forced absolute |
| `:zp` | Forced zero-page |
| `:a` | Accumulator |

### Available directives

```lisp
(org n) (label 'x) (global-label 'x) (equ 'x n)
(db ...) (dw n) (dd n) (fill n v) (text "...") (align n)
(section :name) (target :45gs02)
```

---

## Module `cl-asm/emit`

### Interface

```lisp
(write-bin     BYTES PATH)
(write-prg     BYTES PATH &key load-address)  ; default: $0801
(write-listing PROGRAM BYTES PATH &key origin)
```

### PRG format

```
Offset 0-1 : load address (little-endian)
Offset 2+  : binary code/data
```

---

## Conditions (errors)

All inherit from `asm-error` which displays the message with source location.

| Condition | Raised by |
|---|---|
| `asm-syntax-error` | Unexpected token |
| `asm-undefined-label` | Missing symbol in pass 2 |
| `asm-range-error` | Value out of range |
| `asm-unknown-mnemonic` | Unknown mnemonic |
| `lexer-error` | Invalid character, unclosed string |

---

## Coding conventions

- **Encoding**: UTF-8, `; -*- coding: utf-8 -*-` on first line.
- **Packages**: one per file, named `cl-asm/module`.
- **Exports**: all public symbols in `:export` of `defpackage`.
- **Mutual recursion**: `declaim ftype` at file top for mutually recursive functions.
- **`otherwise` in `case`**: always `(t ...)` or `otherwise` as last clause,
  never followed by `declare`. SBCL rejects `declare` after `otherwise`.
- **Tests**: each module has `tests/test-<module>.lisp`, run by `run-all-tests`.
- **SBCL/CLISP compatibility**: test on both at each session.
