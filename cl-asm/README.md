# cl-asm — Multi-architecture Assembler in Common Lisp

A modular assembler written in Common Lisp. Current targets: **6502**
(Commodore 64, Apple II…), **45GS02** (Mega65), and **65C02**
(Commander X16). The architecture is designed to accommodate additional
backends (Z80, 68000…) without modifying the core.

## Version

**Current version: 0.1.1**

```lisp
cl-asm/version:+version+         ; → "0.1.1"
cl-asm/version:+version-major+   ; → 0
cl-asm/version:+version-minor+   ; → 1
cl-asm/version:+version-patch+   ; → 0
(cl-asm/version:version-string)  ; → "0.1.1"
```

---

## Project Status

| Module | Status | Tests |
|---|---|---|
| IR (Intermediate Representation) | ✓ | — |
| Expression evaluator | ✓ | 129 |
| Symbol table | ✓ | 59 |
| Classic lexer | ✓ | 119 |
| Classic parser (ca65-like) | ✓ | 84 |
| 6502 backend | ✓ | 82 |
| 45GS02 backend | ✓ | 80 |
| 65C02 backend (X16) | ✓ | 41 |
| BIN / PRG / listing emitters | ✓ | — |
| Text macros | ✓ | 27 |
| Conditional assembly | ✓ | 27 |
| .lasm frontend (native Lisp) | ✓ | 58 |

**Total: 706 tests, 0 failures, 0 warnings — SBCL 2.6.2 and CLISP 2.49.95+**

---

## Prerequisites

- **SBCL** 2.x (recommended) or **CLISP** 2.49.95+
- **ASDF** 3.x (included with SBCL)
- **Quicklisp** (optional, recommended)

Installing SBCL:

```bash
sudo pacman -S sbcl      # Arch / Manjaro
sudo apt install sbcl    # Debian / Ubuntu
sudo dnf install sbcl    # Fedora
brew install sbcl        # macOS
```

---

## Project Structure

```
cl-asm/
├── cl-asm.asd              ASDF system definition
├── bootstrap.lisp          manual loading (without ASDF)
├── run-tests.sh            SBCL test script
├── run-tests-clisp.sh      CLISP test script
├── cl-asm                  command-line script
├── acme2clasm              ACME to cl-asm converter
├── src/
│   ├── core/
│   │   ├── version.lisp        version number
│   │   ├── ir.lisp             intermediate representation
│   │   ├── expression.lisp     expression evaluator
│   │   └── symbol-table.lisp   symbol table, 2 passes
│   ├── frontend/
│   │   ├── classic-lexer.lisp  tokeniser (ca65-like)
│   │   ├── classic-parser.lisp parser → IR, macros, conditionals
│   │   └── lasm.lisp           native Lisp frontend (.lasm)
│   ├── backend/
│   │   ├── 6502.lisp           6502 encoder (56 mnemonics)
│   │   ├── 45gs02.lisp         45GS02 encoder (6502 superset)
│   │   └── 65c02.lisp          65C02 encoder (6502 superset, X16)
│   └── emit/
│       └── output.lisp         BIN, PRG, listing emitters
├── tests/
│   ├── run-tests.lisp
│   ├── test-expression.lisp
│   ├── test-symbol-table.lisp
│   ├── test-lexer.lisp
│   ├── test-parser.lisp
│   ├── test-6502.lisp
│   ├── test-65c02.lisp
│   ├── test-45gs02.lisp
│   ├── test-macros.lisp
│   ├── test-conditional.lisp
│   └── test-lasm.lisp
└── examples/
    ├── c64-raster.asm          C64 raster bar (classic syntax)
    ├── mega65-hello.lasm       Mega65 hello world (.lasm syntax)
    ├── mega65-minimal.lasm     minimal Mega65 program
    ├── x16-hello.asm           Commander X16 hello world (65C02)
    ├── x16-minimal.asm         minimal X16 program
    ├── x16-debug.asm           X16 diagnostic program (BRK)
    └── README.md               examples assembly guide
```

---

## Running Tests

Three methods coexist — they all produce identical output.

### Method 1 — shell scripts (without ASDF)

```bash
cd cl-asm/
./run-tests.sh          # SBCL
./run-tests-clisp.sh    # CLISP
```

### Method 2 — ASDF from a REPL

```lisp
;; Run tests in one command (loads cl-asm/tests if needed)
(asdf:test-system "cl-asm")
```

If `cl-asm` is already loaded and sources are unchanged, ASDF uses
cached `.fasl` files and the command runs instantly. The tests still
execute.

To force full recompilation:

```lisp
(asdf:load-system "cl-asm" :force t)
(asdf:test-system "cl-asm")
```

### Method 3 — load and test separately (recommended for development)

```lisp
;; Load tests (recompiles only modified files)
(ql:quickload "cl-asm/tests")   ; or (asdf:load-system "cl-asm/tests")

;; Run tests on demand
(cl-asm/test:run-all-tests)
```

Expected output (all methods):

```
--- Core ---
=== symbol-table :  59 OK, 0 KO
=== expression   : 129 OK, 0 KO
--- Frontend ---
=== lexer        : 119 OK, 0 KO
=== parser       :  84 OK, 0 KO
=== macros       :  27 OK, 0 KO
=== conditionnel :  27 OK, 0 KO
=== lasm         :  58 OK, 0 KO
--- Backends ---
=== 6502         :  82 OK, 0 KO
=== 65c02        :  41 OK, 0 KO
=== 45gs02       :  80 OK, 0 KO
-------------------------------
=== TOTAL        : 706 OK, 0 KO sur 706 tests
```

---

## Installation with Quicklisp

### Install Quicklisp (once)

```bash
curl -O https://beta.quicklisp.org/quicklisp.lisp
sbcl --load quicklisp.lisp \
     --eval "(quicklisp-quickstart:install)" \
     --eval "(ql:add-to-init-file)" \
     --quit
```

Quicklisp installs into `~/quicklisp/` and loads automatically on
every SBCL startup.

### Register cl-asm with Quicklisp

```bash
# Symbolic link (recommended — project stays in place)
ln -s /path/to/cl-asm ~/quicklisp/local-projects/cl-asm

# Then in the REPL, update the registry:
(ql:register-local-projects)
```

### Load and test from any REPL

```lisp
;; Load the project
(ql:quickload "cl-asm")

;; Load project + tests
(ql:quickload "cl-asm/tests")

;; Run tests
(cl-asm/test:run-all-tests)

;; Or all in one command
(asdf:test-system "cl-asm")
```

### Typical development workflow

```lisp
;; First time: load everything
(ql:quickload "cl-asm/tests")
(cl-asm/test:run-all-tests)

;; After modifying src/backend/6502.lisp:
;; ASDF reloads only 6502.lisp and 45gs02.lisp (which depends on it)
(asdf:load-system "cl-asm")
(cl-asm/test:run-all-tests)
```

---

## Programmatic Usage

### Assemble 6502 code

```lisp
(ql:quickload "cl-asm")

;; Assemble → byte vector
(cl-asm/backend.6502:assemble-string
  ".org $0801
   LDA #$00
   STA $D020
   RTS")
;; => #(169 0 141 32 208 96)

;; Assemble a file
(cl-asm/backend.6502:assemble-file "programme.asm" :origin #x0801)

;; Write a PRG file (Commodore 64)
(let ((bytes (cl-asm/backend.6502:assemble-string
               ".org $0801
                LDA #$00
                STA $D020
                RTS")))
  (cl-asm/emit:write-prg bytes "/tmp/demo.prg" :load-address #x0801))

;; Write a BIN file (raw binary, no header)
(cl-asm/emit:write-bin bytes "/tmp/demo.bin")
```

### Assemble 45GS02 code (Mega65)

```lisp
;; Default origin: $2001 (Mega65 BASIC area)
(cl-asm/backend.45gs02:assemble-string-45gs02
  ".org $2001
   LDZ #$00
   LDQ ($20),Z
   STQ ($30),Z
   RTS")
```

### Assemble 65C02 code (Commander X16)

```lisp
(cl-asm/backend.65c02:assemble-string-65c02
  ".org $0801
   BRA start
   start:
   STZ $10
   PHY
   PLY
   RTS")
```

### Full pipeline: parse then assemble

```lisp
(let* ((program (cl-asm/parser:parse-string
                  "start:
                   LDA #$00
                   BNE start"))
       (bytes (cl-asm/backend.6502:assemble program :origin #x0801)))
  (format t "~D bytes~%" (length bytes)))
```

---

## Output Formats

| Format | Function | Description |
|---|---|---|
| BIN | `write-bin` | Raw binary, no header |
| PRG | `write-prg` | C64 format: 2-byte LE header + binary |
| LST | `write-listing` | Annotated listing: address | hex | source |

---

## Supported Assembly Syntax

```asm
; Comments with ;  or  // (C style)

SCREEN  = $0400            ; constant
COLS    = 40

        .org  $0801        ; origin
        .byte $0B, $08     ; literal bytes
        .word $C000        ; 16-bit words (little-endian)
        .text "HELLO"      ; ASCII string
        .fill 10, $00      ; fill
        .align 256         ; alignment

start:                     ; local label
main::                     ; global label (ca65-style)
1:      bne 1-             ; numeric label + backward ref
        bne 1+             ; forward ref

; 6502 addressing modes
        lda #$FF           ; immediate
        lda $10            ; zero-page
        lda $10,X          ; zero-page,X
        lda $1234          ; absolute
        lda $1234,X        ; absolute,X / absolute,Y
        lda ($00,X)        ; (indirect,X)
        lda ($00),Y        ; (indirect),Y
        lsr A              ; accumulator
        jmp ($FFFC)        ; indirect

; 65C02 additional modes
        bra label          ; unconditional branch
        stz $10            ; store zero
        phx                ; push X
        inc A              ; increment accumulator
        lda ($10)          ; zero-page indirect (no index)

; 45GS02 additional modes
        lda ($00),Z        ; (indirect),Z
        lda $1234,Z        ; absolute,Z
        lda [$00]          ; [32-bit indirect]
        ldq ($20),Z        ; 32-bit Q register

; Text macros
.macro PUSH_AXY
    PHA
    TXA
    PHA
    TYA
    PHA
.endmacro

; Conditional assembly
; Note: forward-references NOT supported in .if
DEBUG    = 1
PLATFORM = 64

.if DEBUG
    LDA #$01
    STA $0400
.endif

.if PLATFORM = 64
    LDA #<C64_SCREEN
.else
    LDA #<M65_SCREEN
.endif

; Expressions
        lda #<VEC          ; low byte
        lda #>VEC          ; high byte
        lda BASE+1
        lda #(COLS * 2 + 1)
```

---

## Command Line

The `cl-asm` script assembles a file directly from the terminal.

```bash
# Assemble .asm → .prg (6502, default origin $0801)
./cl-asm programme.asm

# Choose output file
./cl-asm programme.asm -o demo.prg

# Raw binary (no header)
./cl-asm programme.asm -o demo.bin --format bin

# Custom origin
./cl-asm programme.asm --origin 0xC000

# Mega65 / 45GS02 target
./cl-asm mega65.lasm --target 45gs02

# Commander X16 target
./cl-asm prog.asm --target x16

# Verbose mode
./cl-asm programme.asm -v
```

### Options

| Option | Description | Default |
|---|---|---|
| `-o FILE` | Output file | same name, .prg extension |
| `-f FORMAT` | `prg` or `bin` | `prg` |
| `--origin ADDR` | Origin address (e.g. `0x0801`) | `0x0801` |
| `-t TARGET` | `6502`, `45gs02`, or `x16` | `6502` |
| `-v` | Verbose mode | — |

Target is auto-detected from the first lines of the source file:
- `.asm`: `; target: 45gs02` or `; target: x16`
- `.lasm`: `(target :45gs02)`

---

## .lasm Frontend — Native Lisp Syntax

`.lasm` files are valid Common Lisp executed in a context where each
mnemonic is a function. The full power of CL is available: `let`,
`dotimes`, `loop`, `defun`, etc.

### Usage

```lisp
(ql:quickload "cl-asm")

;; Assemble from a string
(cl-asm/lasm:assemble-lasm-string
  "(org #x0801)
   (lda :imm 0)
   (sta #xD020)
   (rts)"
  :origin #x0801)

;; Assemble a file
(cl-asm/lasm:assemble-lasm "/path/to/prog.lasm" :origin #x0801)

;; 45GS02 target
(cl-asm/lasm:assemble-lasm-string src :target :45gs02 :origin #x2001)
```

### Addressing mode convention

Without keyword — mode inferred from value:
```lisp
(lda #x10)        ; LDA $10   (zero-page, value ≤ 255)
(lda #x1234)      ; LDA $1234 (absolute, value > 255)
(lda 'screen)     ; LDA SCREEN (symbol, resolved at assembly)
```

With keyword — explicit mode:
```lisp
(lda :imm #xFF)   ; LDA #$FF  (immediate)
(lda :x   #x10)   ; LDA $10,X (indexed X)
(lda :y   #x1234) ; LDA $1234,Y (indexed Y)
(lda :ind #xFFFC) ; JMP ($FFFC) (indirect)
(lda :ix  #x00)   ; LDA ($00,X) (pre-indexed X)
(lda :iy  #xB0)   ; LDA ($B0),Y (post-indexed Y)
(lda :abs #x10)   ; LDA $0010  (forced absolute)
(lda :zp  #x10)   ; LDA $10    (forced zero-page)
(lsr :a)          ; LSR A      (accumulator)
```

### Native Lisp examples

```lisp
; Local constant
(let ((black 0))
  (lda :imm black)
  (sta #xD020))

; Generate code with dotimes
(dotimes (i 8)
  (lda :imm i)
  (sta (+ #xD800 i)))

; Reusable function
(defun set-border (col)
  (lda :imm col)
  (sta #xD020))

(set-border 0)
(set-border 14)
```

---

## ACME Converter

```bash
./acme2clasm source.s              # → source.asm
./acme2clasm source.s -o out.asm   # explicit output
./acme2clasm source.s --report     # show conversion warnings
```

Conversions performed: `!addr` → constant, `!byte`/`!8` → `.byte`,
`!word`/`!16` → `.word`, `!pet` → `.byte` with explicit codes,
`!fill` → `.fill`, `!macro`/`!if` → `.macro`/`.if`,
`!cpu m65` → `; target: 45gs02`, `!cpu 65c02` → `; target: x16`.
Non-ASCII characters in comments are normalized to ASCII.

---

## Note on `.fasl` files

SBCL compiles sources to `.fasl` files on first load via ASDF.
Subsequent compilations are instant if sources have not changed.

To force full recompilation after modifying package declarations:

```bash
find cl-asm/ -name "*.fasl" -delete
```

---

## Note on encoding

All source files use UTF-8. The `; -*- coding: utf-8 -*-` line at the
top of each file is required for SBCL and editors (Emacs/SLIME,
VS Code/SLY).

---

## License

MIT — see [LICENSE](LICENSE).
