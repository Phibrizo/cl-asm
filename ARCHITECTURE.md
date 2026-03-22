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
│  Backends (target architectures)                        │
│  6502 · 65C02 · R65C02 · 45GS02 · 65816 · Z80 · M68K   │
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
| `cl-asm/backend.65816` | `src/backend/65816.lisp` | WDC 65816 backend (SNES/Apple IIgs) |
| `cl-asm/backend.z80` | `src/backend/z80.lisp` | Z80 backend (ZX Spectrum, MSX, CPC, ZX81) |
| `cl-asm/backend.m68k` | `src/backend/m68k.lisp` | M68K backend (Amiga, Atari ST, Mac 68k) |
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

### Z80 mode

The parser is shared between 6502 and Z80. A dynamic variable controls
which set of mnemonics is active:

```lisp
cl-asm/parser:*z80-mode*   ; NIL by default (6502 mode)
```

`assemble-string-z80` and `assemble-file-z80` bind `*z80-mode*` to T
before parsing. This prevents shared mnemonics (`INC`, `DEC`, `AND`,
`ADC`, `BIT`…) from being misinterpreted in 6502 code.

Z80 operands use `:direct "A"` for registers (not `:register`),
`:indirect "HL"` for `(HL)`, and `:indirect (:+ "IX" d)` for `(IX+d)`.

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

## Module `cl-asm/backend.r65c02`

65C02 superset for the Rockwell R65C02 (used in some Commander X16 revisions).
Default origin: `$0801`.

### Interface

```lisp
(cl-asm/backend.r65c02:assemble-r65c02        PROGRAM &key origin)
(cl-asm/backend.r65c02:assemble-string-r65c02 SOURCE  &key origin)
(cl-asm/backend.r65c02:assemble-file-r65c02   PATH    &key origin)
```

### New instructions (32 Rockwell bit-manipulation)

| Group | Instructions | Opcode | Bytes |
|---|---|---|---|
| Reset bit | `RMB0`…`RMB7` | `$n7` | 2 (ZP) |
| Set bit | `SMB0`…`SMB7` | `$n7+$80` | 2 (ZP) |
| Branch if reset | `BBR0`…`BBR7` | `$nF` | 3 (ZP + rel) |
| Branch if set | `BBS0`…`BBS7` | `$nF+$80` | 3 (ZP + rel) |

`BBRn`/`BBSn` take **two operands** separated by a comma: zero-page address
and branch target. The parser recognises these via `rockwell-two-operands-p`.

---

## Module `cl-asm/backend.65816`

Full WDC 65816 backend (SNES, Apple IIgs). Default origin: `$8000` (SNES LoROM bank 0).

### Interface

```lisp
(cl-asm/backend.65816:assemble-65816        PROGRAM &key origin)
(cl-asm/backend.65816:assemble-string-65816 SOURCE  &key origin)
(cl-asm/backend.65816:assemble-file-65816   PATH    &key origin)
```

### Addressing modes (in addition to base 6502)

| Mode | Syntax | Bytes |
|---|---|---|
| `:absolute-long` | `LDA $123456` | 4 |
| `:absolute-long-x` | `LDA $123456,X` | 4 |
| `:dp-indirect-long` | `LDA [$10]` | 2 |
| `:dp-indirect-long-y` | `LDA [$10],Y` | 2 |
| `:stack-relative` | `LDA $10,S` | 2 |
| `:sr-indirect-y` | `LDA ($10,S),Y` | 2 |
| `:relative-long` | `BRL label` | 3 |
| `:block-move` | `MVN $7E,$7F` | 3 (two bank bytes) |

### Variable-width immediate

The accumulator and index registers can operate in 8-bit or 16-bit mode,
controlled by the M and X flags in the processor status register.

| Flag | Instructions affected | 8-bit | 16-bit |
|---|---|---|---|
| M (bit 5) | `LDA/STA/ADC/SBC/AND/ORA/EOR/CMP/BIT` | immediate = 2 bytes | immediate = 3 bytes |
| X (bit 4) | `LDX/LDY/CPX/CPY` | immediate = 2 bytes | immediate = 3 bytes |

### Mode directives

| Directive | Effect |
|---|---|
| `.al` | Clear M flag — accumulator 16-bit |
| `.as` | Set M flag — accumulator 8-bit |
| `.xl` | Clear X flag — index registers 16-bit |
| `.xs` | Set X flag — index registers 8-bit |

State is tracked across both passes via a mutable `(list m-long x-long)` cons.

### Notable instructions

| Instruction | Description | Bytes |
|---|---|---|
| `JSL addr24` | Jump to subroutine long | 4 |
| `JML addr24` | Jump long | 4 |
| `RTL` | Return from subroutine long | 1 |
| `BRL label` | Branch long (±32KB, 16-bit signed offset) | 3 |
| `PER label` | Push effective relative address | 3 |
| `PEA #nn` | Push effective absolute address (always 16-bit) | 3 |
| `MVN dst,src` | Block move negative (bank bytes) | 3 |
| `MVP dst,src` | Block move positive (bank bytes) | 3 |
| `REP #nn` | Reset processor status bits | 2 |
| `SEP #nn` | Set processor status bits | 2 |

---

## Module `cl-asm/backend.z80`

Full Zilog Z80 backend (ZX Spectrum, MSX, CPC, ZX81). Default origin: `$8000`.

### Interface

```lisp
(cl-asm/backend.z80:assemble-z80        PROGRAM &key origin)
(cl-asm/backend.z80:assemble-string-z80 SOURCE  &key origin)
(cl-asm/backend.z80:assemble-file-z80   PATH    &key origin)
```

### Instruction prefixes

| Prefix | Instructions |
|---|---|
| (none) | Main set: LD, ADD, ADC, SUB, SBC, AND, OR, XOR, CP, INC, DEC, JR, JP, CALL, RET, PUSH, POP, EX, DJNZ, RST, IN, OUT, IM, block ops |
| `$CB` | Rotations (RLC/RRC/RL/RR/SLA/SRA/SLL/SRL) + BIT/SET/RES |
| `$DD` | IX register operations |
| `$ED` | Extended: 16-bit ADD, block ops (LDIR/LDDR/CPIR/CPDR…), IN/OUT groups, IM |
| `$FD` | IY register operations |
| `$DD $CB` | Bit ops on (IX+d) |
| `$FD $CB` | Bit ops on (IY+d) |

### Addressing modes

| Mode | Syntax | Example |
|---|---|---|
| Implied | — | `NOP`, `LDIR` |
| Register direct | `A`, `B`, `HL`… | `LD A, B` |
| Immediate byte | `n` | `LD A, $42` |
| Immediate word | `nn` | `LD HL, $1234` |
| Register indirect | `(HL)`, `(BC)`, `(DE)` | `LD A, (HL)` |
| Indexed | `(IX+d)`, `(IY+d)` | `LD A, (IX+2)` |
| Direct memory | `(nn)` | `LD A, ($8000)` |
| Relative | `e` (signed byte offset) | `JR NZ, label` |
| Bit + register | `n, r` | `BIT 3, A` |

---

## Module `cl-asm/backend.m68k`

Full Motorola 68000 backend (Amiga, Atari ST, Mac 68k). Default origin: `$0000`.

### Interface

```lisp
(cl-asm/backend.m68k:assemble-m68k        PROGRAM &key origin)
(cl-asm/backend.m68k:assemble-string-m68k SOURCE  &key origin)
(cl-asm/backend.m68k:assemble-file-m68k   PATH    &key origin)
```

### EA field encoding

The 6-bit EA field is `(mode << 3) | reg`, embedded directly in the instruction word.

| Mode | Encoding | Syntax |
|---|---|---|
| Data register | `000 rrr` | `Dn` |
| Address register | `001 rrr` | `An` |
| Address indirect | `010 rrr` | `(An)` |
| Post-increment | `011 rrr` | `(An)+` |
| Pre-decrement | `100 rrr` | `-(An)` |
| Displacement | `101 rrr` | `d(An)` |
| Indexed | `110 rrr` | `d(An,Xi)` |
| Abs.W | `111 000` | `$nnnn.W` |
| Abs.L | `111 001` | `$nnnnnn` |
| PC displacement | `111 010` | `d(PC)` |
| PC indexed | `111 011` | `d(PC,Xi)` |
| Immediate | `111 100` | `#n` |

### MOVE encoding peculiarity

MOVE reverses the destination EA bits in the opcode word:
bits 11-9 = dst_reg, bits 8-6 = dst_mode (opposite of all other instructions).
MOVE size field (bits 13-12): `.B`→1, `.W`→3, `.L`→2.

### Big-endian output

`words->bytes` converts a list of 16-bit words to a big-endian byte sequence.
All extension words (immediates, displacements, addresses) follow the opcode word.

---

## Module `cl-asm/lasm`

Native Lisp frontend. `.lasm` files are valid Common Lisp where each
mnemonic is a function and the full CL environment is available
(`defun`, `defmacro`, `let`, `dotimes`, `loop`, etc.).

**Supported targets:** `:6502` (default) and `:45gs02`. Support for
`:65c02`, `:r65c02`, `:65816`, `:z80`, and `:m68k` is planned.

**Shadowed CL symbols:** `fill`, `bit`, `sec`, `and`, `map` are
redefined as assembly instructions inside the `cl-asm/lasm` package.
Use `cl:fill`, `cl:and`, etc. to access the original CL definitions.

### Interface

```lisp
(assemble-lasm-string SOURCE &key origin target)
(assemble-lasm        PATH   &key origin target)
(load-lasm-string     SOURCE)  ; → IR-PROGRAM
(load-lasm            PATH)    ; → IR-PROGRAM
```

### Addressing mode keywords

| Keyword | Mode | Notes |
|---------|------|-------|
| `:imm` | Immediate | |
| `:x` | Indexed X | |
| `:y` | Indexed Y | |
| `:z` | Indexed Z | 45GS02 only |
| `:ind` | Indirect | |
| `:ix` | Pre-indexed X | |
| `:iy` | Post-indexed Y | |
| `:iz` | Post-indexed Z | 45GS02 only |
| `:abs` | Forced absolute | |
| `:zp` | Forced zero-page | |
| `:a` | Accumulator | |

Without keyword: value ≤ 255 → zero-page; > 255 or symbol → absolute.

### Available directives

```lisp
(org n)               ; set origin
(label 'x)            ; local label
(global-label 'x)     ; global (exported) label
(equ 'x n)            ; constant definition
(db v …)              ; emit bytes
(dw v …)              ; emit 16-bit words (little-endian)
(dd v …)              ; emit 32-bit words (little-endian)
(text "str")          ; emit ASCII string (no null terminator)
(fill n [v])          ; emit n bytes of value v (default 0)
(align n [v])         ; align PC to boundary n
(section :name)       ; switch section
(target :arch)        ; CLI hint, no-op at runtime
```

### Helper macros

```lisp
(genlabel)                              ; → unique anonymous label keyword
(with-label name &body)                 ; place label, then emit body
(lasm-if cond-fn t-label f-label &body) ; conditional if/else structure
```

`(target :arch)` is detected by the `cl-asm` script via `grep` before
loading the file; it is a no-op at runtime and does not affect
assembly.

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
- **SBCL/CLISP/ECL compatibility**: test on all three at each session.
