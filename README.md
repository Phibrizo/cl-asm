# cl-asm — Multi-architecture Assembler in Common Lisp

A modular assembler written in Common Lisp. Current targets: **6502**
(Commodore 64, Apple II…), **45GS02** (Mega65), **65C02**
(Commander X16), **R65C02** (Rockwell), **WDC 65816**
(SNES, Apple IIgs), and **Z80** (ZX Spectrum, MSX, CPC, ZX81). The
architecture is designed to accommodate additional backends (68000…)
without modifying the core.

## Version

**Current version: 0.3.0**

```
cl-asm/version:+version+         ; → "0.3.0"
cl-asm/version:+version-major+   ; → 0
cl-asm/version:+version-minor+   ; → 3
cl-asm/version:+version-patch+   ; → 0
(cl-asm/version:version-string)  ; → "0.3.0"
```

---

## Project Status

| Module | Status | Tests |
| --- | --- | --- |
| IR (Intermediate Representation) | ✓ | — |
| Expression evaluator | ✓ | 129 |
| Symbol table | ✓ | 59 |
| Classic lexer | ✓ | 119 |
| Classic parser (ca65-like) | ✓ | 84 |
| 6502 backend | ✓ | 82 |
| 45GS02 backend | ✓ | 80 |
| 65C02 backend (X16) | ✓ | 41 |
| R65C02 backend (Rockwell) | ✓ | 117 |
| WDC 65816 backend (SNES/Apple IIgs) | ✓ | 104 |
| Z80 backend (ZX Spectrum, MSX, CPC, ZX81) | ✓ | 191 |
| BIN / PRG / listing emitters | ✓ | — |
| Text macros | ✓ | 27 |
| Conditional assembly | ✓ | 27 |
| .lasm frontend (native Lisp) | ✓ | 58 |

**Total: 1124 tests, 0 failures, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, and ECL 21.x+**

---

## Prerequisites

* **SBCL** 2.x (recommended), **CLISP** 2.49.95+, or **ECL** 21.x+
* **ASDF** 3.x (included with SBCL)
* **Quicklisp** (optional, recommended)

Installing SBCL:

```
sudo pacman -S sbcl      # Arch / Manjaro
sudo apt install sbcl    # Debian / Ubuntu
sudo dnf install sbcl    # Fedora
brew install sbcl        # macOS
```

Installing ECL:

```
sudo pacman -S ecl       # Arch / Manjaro
sudo apt install ecl     # Debian / Ubuntu
sudo dnf install ecl     # Fedora
brew install ecl         # macOS
```

---

## Project Structure

```
cl-asm/
├── cl-asm.asd              ASDF system definition
├── bootstrap.lisp          manual loading (without ASDF)
├── run-tests.sh            SBCL test script
├── run-tests-clisp.sh      CLISP test script
├── run-tests-ecl.sh        ECL test script
├── cl-asm                  command-line script
├── acme2clasm              ACME to cl-asm converter (shell wrapper)
├── acme2clasm.lisp         ACME to cl-asm converter (Common Lisp engine)
├── src/
│   ├── core/
│   │   ├── version.lisp        version number
│   │   ├── backends.lisp       extensible backend registry
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
│   │   ├── 65c02.lisp          65C02 encoder (6502 superset, X16)
│   │   ├── r65c02.lisp         R65C02 encoder (65C02 + Rockwell bit ops)
│   │   ├── 65816.lisp          WDC 65816 encoder (SNES/Apple IIgs, 24-bit)
│   │   └── z80.lisp            Z80 encoder (ZX Spectrum, MSX, CPC, ZX81)
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
│   ├── test-r65c02.lisp
│   ├── test-45gs02.lisp
│   ├── test-macros.lisp
│   ├── test-conditional.lisp
│   ├── test-lasm.lisp
│   ├── test-65816.lisp
│   └── test-z80.lisp
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

```
cd cl-asm/
./run-tests.sh          # SBCL
./run-tests-clisp.sh    # CLISP
./run-tests-ecl.sh      # ECL
```

### Method 2 — ASDF from a REPL

```
;; Run tests in one command (loads cl-asm/tests if needed)
(asdf:test-system "cl-asm")
```

If `cl-asm` is already loaded and sources are unchanged, ASDF uses
cached `.fasl` files and the command runs instantly. The tests still
execute.

To force full recompilation:

```
(asdf:load-system "cl-asm" :force t)
(asdf:test-system "cl-asm")
```

### Method 3 — load and test separately (recommended for development)

```
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
=== r65c02       : 117 OK, 0 KO
=== 45gs02       :  80 OK, 0 KO
=== 65816        : 104 OK, 0 KO
=== z80          : 191 OK, 0 KO
-------------------------------
=== TOTAL        : 1124 OK, 0 KO
```

---

## Installation with Quicklisp

### Install Quicklisp (once)

```
curl -O https://beta.quicklisp.org/quicklisp.lisp
sbcl --load quicklisp.lisp \
     --eval "(quicklisp-quickstart:install)" \
     --eval "(ql:add-to-init-file)" \
     --quit
```

Quicklisp installs into `~/quicklisp/` and loads automatically on
every SBCL startup.

### Register cl-asm with Quicklisp

```
# Symbolic link (recommended — project stays in place)
ln -s /path/to/cl-asm ~/quicklisp/local-projects/cl-asm

# Then in the REPL, update the registry:
(ql:register-local-projects)
```

### Load and test from any REPL

```
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

```
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

```
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

```
;; Default origin: $2001 (Mega65 BASIC area)
(cl-asm/backend.45gs02:assemble-string-45gs02
  ".org $2001
   LDZ #$00
   LDQ ($20),Z
   STQ ($30),Z
   RTS")
```

### Assemble 65C02 code (Commander X16)

```
(cl-asm/backend.65c02:assemble-string-65c02
  ".org $0801
   BRA start
   start:
   STZ $10
   PHY
   PLY
   RTS")
```

### Assemble R65C02 code (Rockwell — bit manipulation)

```
;; RMBn/SMBn: reset/set bit n of a zero-page address
;; BBRn/BBSn: branch if bit n of zero-page is reset/set
(cl-asm/backend.r65c02:assemble-string-r65c02
  ".org $1000
   SMB3 $10        ; set bit 3 of address $10
   BBR3 $10, skip  ; branch if bit 3 is reset (not taken)
   RMB3 $10        ; reset bit 3
   skip:
   RTS")
```

### Assemble WDC 65816 code (SNES / Apple IIgs)

```
;; Default origin: $8000 (SNES LoROM bank 0)
(cl-asm/backend.65816:assemble-string-65816
  ".org $8000
   .al             ; switch accumulator to 16-bit
   LDA #$1234      ; 16-bit immediate (3 bytes)
   STA $7E0000     ; store to absolute long address
   JSL $008000     ; jump to subroutine long (24-bit)
   RTL")

;; 8-bit mode (default on reset)
(cl-asm/backend.65816:assemble-string-65816
  ".org $8000
   SEP #$30        ; set M and X flags (8-bit mode)
   LDA #$42        ; 8-bit immediate
   STA $00,X       ; zero-page,X
   RTS")

;; Block move
(cl-asm/backend.65816:assemble-string-65816
  ".org $8000
   MVN $7E,$7F     ; move block from bank $7F to bank $7E
   RTS")
```

### Assemble Z80 code (ZX Spectrum / MSX / CPC)

```
(cl-asm/backend.z80:assemble-string-z80
  ".org $8000
   LD A, $42
   LD (HL), A
   INC HL
   DJNZ loop
   loop:
   RET")
```

### Full pipeline: parse then assemble

```
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
| --- | --- | --- |
| BIN | `write-bin` | Raw binary, no header |
| PRG | `write-prg` | C64 format: 2-byte LE header + binary |
| LST | `write-listing` | Annotated listing: address |

---

## Supported Assembly Syntax

```
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

; R65C02 additional instructions (Rockwell bit manipulation)
        rmb3 $10           ; reset bit 3 of $10
        smb3 $10           ; set bit 3 of $10
        bbr3 $10, label    ; branch if bit 3 of $10 is reset
        bbs3 $10, label    ; branch if bit 3 of $10 is set

; WDC 65816 additional modes and instructions
        lda $123456        ; absolute long (24-bit address)
        lda $123456,X      ; absolute long,X
        lda [$10]          ; dp indirect long
        lda [$10],Y        ; dp indirect long,Y
        lda $10,S          ; stack-relative
        lda ($10,S),Y      ; (stack-relative indirect),Y
        jsl $008000        ; jump subroutine long (24-bit)
        jml $008000        ; jump long (24-bit)
        brl label          ; branch long (16-bit offset)
        mvn $7e,$7f        ; block move negative (dst,src)
        mvp $7e,$7f        ; block move positive (dst,src)
        pea #$1234         ; push effective address (16-bit)
        rep #$30           ; reset processor status bits
        sep #$30           ; set processor status bits

; Directives de mode 65816
        .al                ; accumulateur 16-bit (clear M)
        .as                ; accumulateur 8-bit (set M)
        .xl                ; index 16-bit (clear X)
        .xs                ; index 8-bit (set X)

; 45GS02 additional modes
        lda ($00),Z        ; (indirect),Z
        lda $1234,Z        ; absolute,Z
        lda [$00]          ; [32-bit indirect]
        ldq ($20),Z        ; 32-bit Q register

; Z80 addressing modes (use --target z80)
        ld a, $42       ; immediate
        ld (hl), a      ; register indirect
        ld a, (ix+2)    ; indexed (IX+d) or (IY+d)
        ld a, ($8000)   ; direct memory
        push bc         ; register pair
        bit 3, a        ; bit test (CB prefix)
        set 3, a        ; bit set (CB prefix)
        res 3, a        ; bit reset (CB prefix)
        jr nz, label    ; relative branch
        djnz loop       ; decrement B, jump if non-zero
        ldir            ; block copy (ED prefix)
        in a, ($FE)     ; I/O port read
        out ($FE), a    ; I/O port write

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

```
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

# Rockwell R65C02 target
./cl-asm prog.asm --target r65c02

# WDC 65816 / SNES target
./cl-asm snes.asm --target 65816

# Z80 / ZX Spectrum / MSX target
./cl-asm prog.asm --target z80

# Verbose mode
./cl-asm programme.asm -v
```

### Options

| Option | Description | Default |
| --- | --- | --- |
| `-o FILE` | Output file | same name, .prg extension |
| `-f FORMAT` | `prg` or `bin` | `prg` |
| `--origin ADDR` | Origin address (e.g. `0x0801`) | `0x0801` |
| `-t TARGET` | `6502` (also `mos6502`, `c64`), `45gs02` (also `mega65`), `x16` (also `65c02`, `commander-x16`), `r65c02` (also `rockwell`), `65816` (also `wdc65816`, `snes`, `apple2gs`), `z80` (also `z80cpu`, `zxspectrum`, `spectrum`, `cpc`, `msx`) | `6502` |
| `-v` | Verbose mode | — |

Target is auto-detected from the first lines of the source file:

* `.asm`: `; target: 45gs02` or `; target: x16`
* `.lasm`: `(target :45gs02)`

---

## .lasm Frontend — Native Lisp Syntax

`.lasm` files are valid Common Lisp executed in a context where each
mnemonic is a function. The full power of CL is available: `let`,
`dotimes`, `loop`, `defun`, etc.

### Usage

```
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

```
(lda #x10)        ; LDA $10   (zero-page, value ≤ 255)
(lda #x1234)      ; LDA $1234 (absolute, value > 255)
(lda 'screen)     ; LDA SCREEN (symbol, resolved at assembly)
```

With keyword — explicit mode:

```
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

```
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

The `acme2clasm` converter is written in pure Common Lisp (no Python
required). It runs with SBCL, CLISP, or ECL — whichever is available
on your system.

```
./acme2clasm source.s              # → source.asm
./acme2clasm source.s -o out.asm   # explicit output
./acme2clasm source.s --report     # show conversion warnings
```

Conversions performed: `!addr` → constant, `!byte`/`!8` → `.byte`,
`!word`/`!16` → `.word`, `!pet` → `.byte` with explicit codes,
`!fill` → `.fill`, `!macro`/`!if` → `.macro`/`.if`,
`!cpu m65` → `; target: 45gs02`, `!cpu 65c02` → `; target: x16`.
Non-ASCII characters in comments are normalized to ASCII.

The converter consists of two files:

* `acme2clasm` — shell wrapper, auto-detects SBCL / CLISP / ECL
* `acme2clasm.lisp` — conversion engine (standard ANSI Common Lisp)

---

## Note on `.fasl` files

SBCL compiles sources to `.fasl` files on first load via ASDF.
Subsequent compilations are instant if sources have not changed.

To force full recompilation after modifying package declarations:

```
find cl-asm/ -name "*.fasl" -delete
```

---

## Note on encoding

All source files use UTF-8. The `; -*- coding: utf-8 -*-` line at the
top of each file is required for SBCL and editors (Emacs/SLIME,
VS Code/SLY).

---

## License

MIT — see [LICENSE](https://github.com/Phibrizo/cl-asm/blob/main/LICENSE).
