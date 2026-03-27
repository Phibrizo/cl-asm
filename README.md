# cl-asm — Multi-architecture Assembler in Common Lisp

A modular assembler written in Common Lisp. Current targets: **6502**
(Apple II…), **6510** (Commodore 64, with stable illegal opcodes), **45GS02**
(Mega65), **65C02** (Commander X16), **R65C02** (Rockwell), **WDC 65816**
(SNES, Apple IIgs), **Z80** (ZX Spectrum, MSX, CPC, ZX81),
**M68K** (Amiga, Atari ST, Mac 68k), and **Intel 8080** (CP/M, Altair).
The architecture is designed to accommodate additional backends without modifying the core.

## Version

**Current version: 0.12.0**

```
cl-asm/version:+version+         ; → "0.12.0"
cl-asm/version:+version-major+   ; → 0
cl-asm/version:+version-minor+   ; → 12
cl-asm/version:+version-patch+   ; → 0
(cl-asm/version:version-string)  ; → "0.12.0"
```

---

## Project Status

| Module | Status | Tests |
| --- | --- | --- |
| IR (Intermediate Representation) | ✓ | — |
| Expression evaluator | ✓ | 129 |
| Symbol table | ✓ | 65 |
| Classic lexer | ✓ | 119 |
| Classic parser (ca65-like) | ✓ | 84 |
| 6502 backend | ✓ | 108 |
| 6510 backend (C64, illegal opcodes) | ✓ | 66 |
| 45GS02 backend | ✓ | 80 |
| 65C02 backend (X16) | ✓ | 86 |
| R65C02 backend (Rockwell) | ✓ | 117 |
| WDC 65816 backend (SNES/Apple IIgs) | ✓ | 104 |
| Z80 backend (ZX Spectrum, MSX, CPC, ZX81) | ✓ | 191 |
| M68K parser | ✓ | 85 |
| M68K backend (Amiga, Atari ST, Mac 68k) | ✓ | 144 |
| Intel 8080 backend (CP/M, Altair) | ✓ | 144 |
| 6502 simulator | ✓ | 294 |
| 6502 simulator programs | ✓ | 73 |
| 6502 disassembler | ✓ | 121 |
| 45GS02 disassembler | ✓ | 97 |
| 65C02 disassembler (X16) | ✓ | 44 |
| 6502 debugger (interactive REPL) | ✓ | 80 |
| BIN / PRG / listing emitters | ✓ | — |
| Text macros | ✓ | 27 |
| Conditional assembly | ✓ | 27 |
| .lasm frontend (native Lisp) | ✓ | 97 |
| acme2clasm converter | ✓ | 20 |
| In-memory modular linker (6502 family) | ✓ | 26 |

**Total: 2428 tests, 0 failures, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, and ECL 21.x+**

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
│   │   ├── disassemblers.lisp  extensible disassembler registry
│   │   ├── ir.lisp             intermediate representation
│   │   ├── expression.lisp     expression evaluator
│   │   ├── debug-map.lisp      address→source-loc table (for debugger)
│   │   ├── symbol-table.lisp   symbol table, 2 passes
│   │   └── linker.lisp         in-memory modular linker (6502 family)
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
│   │   ├── z80.lisp            Z80 encoder (ZX Spectrum, MSX, CPC, ZX81)
│   │   ├── m68k.lisp           M68K encoder (Amiga, Atari ST, Mac 68k)
│   │   └── i8080.lisp          Intel 8080 encoder (CP/M, Altair)
│   ├── simulator/
│   │   └── 6502.lisp           6502 CPU simulator (152 opcodes, cycle-accurate)
│   ├── disassembler/
│   │   ├── 6502.lisp           6502 disassembler (151 official opcodes)
│   │   ├── 45gs02.lisp         45GS02 disassembler (prefix dispatcher)
│   │   └── 65c02.lisp          65C02 / X16 disassembler (flat table)
│   ├── debugger/
│   │   └── 6502.lisp           interactive 6502 step debugger (REPL)
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
│   ├── test-z80.lisp
│   ├── test-m68k-parser.lisp
│   ├── test-m68k.lisp
│   ├── test-8080.lisp
│   ├── test-sim-6502.lisp
│   ├── test-sim-programs.lisp
│   ├── test-disasm-6502.lisp
│   ├── test-disasm-45gs02.lisp
│   ├── test-disasm-65c02.lisp
│   ├── test-debugger-6502.lisp
│   ├── test-acme2clasm.lisp
│   └── test-linker-6502.lisp
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
=== symbol-table :  65 OK, 0 KO
=== expression   : 129 OK, 0 KO
--- Frontend ---
=== lexer        : 119 OK, 0 KO
=== parser       :  84 OK, 0 KO
=== macros       :  27 OK, 0 KO
=== conditionnel :  27 OK, 0 KO
=== lasm         :  97 OK, 0 KO
--- Backends ---
=== 6502         : 108 OK, 0 KO
=== 65c02        :  86 OK, 0 KO
=== r65c02       : 117 OK, 0 KO
=== 45gs02       :  80 OK, 0 KO
=== 65816        : 104 OK, 0 KO
=== z80          : 191 OK, 0 KO
--- Architecture parsers ---
=== m68k-parser  :  85 OK, 0 KO
=== m68k         : 144 OK, 0 KO
--- Intel 8080 ---
=== i8080        : 144 OK, 0 KO
--- Simulator ---
=== sim-6502     : 294 OK, 0 KO
--- Tools ---
=== acme2clasm   :  20 OK, 0 KO
-------------------------------
=== TOTAL        : 1921 OK, 0 KO out of 1921 tests
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

### Linker — multi-file assembly with cross-file label references

Package `cl-asm/linker`. Link multiple source files into a single binary;
labels defined in one file are visible to all others.

```lisp
;; Two source units sharing a symbol table
(let* ((u1 (cl-asm/linker:link-unit-from-program
             "main"
             (cl-asm/parser:parse-string
               "main: JSR helper
                      RTS")
             :6502))
       (u2 (cl-asm/linker:link-unit-from-program
             "utils"
             (cl-asm/parser:parse-string
               "helper: LDA #$42
                        RTS")
             :6502))
       (bytes (cl-asm/linker:link (list u1 u2) :origin #x0200)))
  bytes)
;; => #(#x20 #x04 #x02   ; JSR $0204 (helper)
;;       #x60             ; RTS
;;       #xA9 #x42        ; LDA #$42
;;       #x60)            ; RTS

;; Supported targets: :6502  :6510  :65c02  :45gs02
```

---

## 6502 Simulator

Package `cl-asm/simulator.6502` — a cycle-accurate 6502 CPU simulator with 64 KB memory.

### Quick start

```lisp
(ql:quickload "cl-asm")

(let* ((cpu (cl-asm/simulator.6502:make-cpu))
       (program #(#xa9 #x42   ; LDA #$42
                  #x85 #x00   ; STA $00
                  #x00))      ; BRK
       (cpu (cl-asm/simulator.6502:load-program cpu program #x0300)))
  (multiple-value-bind (cpu reason)
      (cl-asm/simulator.6502:run-cpu cpu :origin #x0300)
    (format t "A=~2,'0X  reason=~A~%" (cl-asm/simulator.6502:cpu-a cpu) reason)))
;; A=42  reason=:BRK
```

### Key exports

| Symbol | Description |
| --- | --- |
| `make-cpu` | Create a new CPU with zeroed memory and registers |
| `reset-cpu` | Reset registers (PC/SP/P) without clearing memory |
| `load-program cpu bytes addr` | Copy byte vector into memory at `addr`, return updated cpu |
| `step-cpu cpu` | Execute one instruction; signals `cpu-break` on BRK, `cpu-illegal-opcode` on unknown opcode |
| `run-cpu cpu &key origin max-steps` | Loop until BRK or `max-steps`; returns `(values cpu :brk\|:step-limit)` |
| `mem-read cpu addr` | Read one byte from memory |
| `mem-write cpu addr val` | Write one byte to memory |
| `cpu-a`, `cpu-x`, `cpu-y` | Accumulator / index register accessors |
| `cpu-pc`, `cpu-sp`, `cpu-p` | Program counter / stack pointer / processor flags accessors |
| `cpu-cycles` | Cycle counter accessor |
| `flag-c`, `flag-z`, `flag-i`, `flag-d`, `flag-b`, `flag-v`, `flag-n` | Read individual flags (0 or 1) from a cpu |
| `+flag-c+`, `+flag-z+`, `+flag-i+`, `+flag-d+`, `+flag-b+`, `+flag-v+`, `+flag-n+` | Bit-mask constants for each flag |

### Instruction coverage

152 opcodes covering the complete 6502 instruction set:

- **Implied (23):** NOP BRK TAX TXA TAY TYA TSX TXS PHA PLA PHP PLP INX INY DEX DEY CLC SEC CLI SEI CLV CLD SED
- **Load/store:** LDA×8, LDX×5, LDY×5, STA×7, STX×3, STY×3
- **ALU:** ADC×8, SBC×8, AND×8, ORA×8, EOR×8, CMP×8, CPX×3, CPY×3, BIT×2
- **Shifts/rotations:** ASL×5, LSR×5, ROL×5, ROR×5
- **Memory inc/dec:** INC×4, DEC×4
- **Jumps/branches:** JMP abs, JMP (ind) with original 6502 page bug, JSR, RTS, RTI, BCC BCS BEQ BNE BMI BPL BVC BVS

Page-crossing cycle penalty is applied (+1 for reads; fixed cost for writes). Cycle counts match the original NMOS 6502.

---

## 6502 Disassembler

Package `cl-asm/disassembler.6502` — disassembles 6502 machine code into human-readable mnemonics. 151 official opcodes, all addressing modes.

```lisp
(let ((mem (make-array 65536 :element-type '(unsigned-byte 8) :initial-element 0)))
  (setf (aref mem #x0200) #xA9  ; LDA
        (aref mem #x0201) #x42  ;   #$42
        (aref mem #x0202) #x85  ; STA
        (aref mem #x0203) #x00  ;   $00
        (aref mem #x0204) #x00) ; BRK
  (cl-asm/disassembler.6502:print-disasm mem #x0200 :count 3))
;; $0200  A9 42     LDA #$42
;; $0202  85 00     STA $00
;; $0204  00        BRK
```

| Symbol | Description |
| --- | --- |
| `disasm-one mem addr` | Disassemble one instruction → `(values mnemonic operand size)` |
| `disasm mem addr &key count` | Disassemble `count` instructions → list of `(addr hex mnemonic operand)` |
| `disasm-string mem addr &key count` | Return a formatted listing as a string |
| `print-disasm mem addr &key count stream` | Print disassembly to `stream` |

---

## 6502 Debugger

Package `cl-asm/debugger.6502` — interactive step debugger built on top of the 6502 simulator.

### Interactive session

```lisp
(ql:quickload "cl-asm")

(let* ((prog  (cl-asm/parser:parse-string "
.org $0200
  LDA #$01
  CLC
  ADC #$02
  BRK"))
       (dm    (cl-asm/debug-map:make-debug-map))  ; optional: source line mapping
       (bytes (cl-asm/backend.6502:assemble prog :origin #x0200 :debug-map dm))
       (cpu   (cl-asm/simulator.6502:make-cpu))
       (dbg   (cl-asm/debugger.6502:make-debugger cpu :debug-map dm)))
  (cl-asm/simulator.6502:load-program cpu bytes :origin #x0200)
  (cl-asm/debugger.6502:debugger-repl dbg))
```

Sample session:

```
=== Débogueur 6502 — cl-asm v0.12.0 ===
Tapez 'h' pour l'aide.

$0200  A9 01     LDA #$01  ; :3:3
 A=$00 X=$00 Y=$00 SP=$FF P=nv-bdIzc  cyc=0

dbg> s
$0202  18        CLC  ; :4:3
 A=$01 X=$00 Y=$00 SP=$FF P=nv-bdIzc  cyc=2

dbg> b $0205
Breakpoint posé à $0205

dbg> c
[BREAKPOINT] à $0205
$0205  00        BRK  ; :6:3
 A=$03 X=$00 Y=$00 SP=$FF P=nv-bdIzc  cyc=8

dbg> r
 A=$03 X=$00 Y=$00 SP=$FF P=nv-bdIzc  cyc=8

dbg> m $00 8
$0000  00 00 00 00 00 00 00 00

dbg> q
Au revoir.
```

When assembled from a file, source locations show as `filename.asm:line:col`.

### REPL commands

| Command | Description |
| --- | --- |
| `s` / `step` | Execute one instruction |
| `n` / `next` | Step-over: execute JSR and return, stopping after |
| `c` / `continue` | Run until breakpoint, watchpoint, or BRK |
| `b $ADDR [expr]` | Set breakpoint; optional Lisp condition `(lambda (cpu) expr)`, `cpu` bound to CPU |
| `d $ADDR` | Delete breakpoint |
| `lb` | List all active breakpoints |
| `w $ADDR [read\|write\|rw]` | Set watchpoint (default `write`) |
| `dw $ADDR` | Delete watchpoint |
| `lw` | List all active watchpoints |
| `r` / `regs` | Show registers and flags (NV-BDIZC) |
| `m $ADDR [N]` | Hex dump of N bytes from address (default 16) |
| `x [$ADDR] [N]` | Disassemble N instructions from address (default 8, default PC) |
| `h` / `help` | Show command reference |
| `q` / `quit` | Exit debugger |
| _(empty line)_ | Repeat last command |

### Programmatic API

```lisp
;; Create a session
(let* ((dm  (cl-asm/debug-map:make-debug-map))
       (bytes (cl-asm/backend.6502:assemble prog :origin #x0200 :debug-map dm))
       (cpu (cl-asm/simulator.6502:make-cpu))
       (dbg (cl-asm/debugger.6502:make-debugger cpu :debug-map dm)))
  (cl-asm/simulator.6502:load-program cpu bytes :origin #x0200)

  ;; Breakpoints
  (cl-asm/debugger.6502:set-breakpoint dbg #x0204)
  (cl-asm/debugger.6502:set-breakpoint dbg #x0210
    :condition (lambda (cpu) (= (cl-asm/simulator.6502:cpu-a cpu) 0)))

  ;; Watchpoints
  (cl-asm/debugger.6502:set-watchpoint dbg #x00F0 :kind :write)  ; break on write to $00F0
  (cl-asm/debugger.6502:set-watchpoint dbg #x00F1 :kind :rw)     ; break on read OR write
  (cl-asm/debugger.6502:list-watchpoints dbg)
  (cl-asm/debugger.6502:clear-watchpoint dbg #x00F0)

  ;; Execution
  (cl-asm/debugger.6502:debugger-step dbg)      ; → :ok | :brk | :breakpoint | :watchpoint | :illegal
  (cl-asm/debugger.6502:debugger-next dbg)      ; step-over JSR
  (cl-asm/debugger.6502:debugger-continue dbg)  ; → :brk | :breakpoint | :watchpoint | :illegal

  ;; Source map query (requires :debug-map at assemble time)
  (cl-asm/debug-map:debug-map-get dm #x0200))   ; → source-loc or NIL
```

| Symbol | Description |
| --- | --- |
| `make-debugger cpu &key debug-map` | Create a debugger session |
| `debugger-repl dbg &key input output` | Launch interactive REPL (streams default to `*standard-input*`/`*standard-output*`) |
| `debugger-step dbg [stream]` | Execute one instruction; display state on `stream` |
| `debugger-next dbg [stream]` | Step-over (skips JSR bodies entirely) |
| `debugger-continue dbg [stream]` | Run to breakpoint or BRK |
| `set-breakpoint dbg addr &key condition` | Add breakpoint; `condition` is `nil` (unconditional) or `(lambda (cpu) → bool)` |
| `clear-breakpoint dbg addr` | Remove breakpoint at address |
| `list-breakpoints dbg` | List breakpoints sorted by address |
| `set-watchpoint dbg addr &key kind` | Add watchpoint; `kind` is `:read` \| `:write` \| `:rw` (default `:write`) |
| `clear-watchpoint dbg addr` | Remove watchpoint at address |
| `list-watchpoints dbg` | List watchpoints sorted by address |
| `debugger-last-watchpoint dbg` | `(address kind)` of the last triggered watchpoint |
| `show-registers cpu [stream]` | Display registers in `A=$XX X=$XX … P=NV-BDIZC cyc=N` format |
| `assemble-file path &key origin debug-map` | Parse and assemble a file (debug-map now supported) |
| `show-current dbg [stream]` | Display current instruction + registers (with source loc if available) |
| `show-memory cpu addr [count stream]` | Hex dump |
| `show-disasm cpu addr [count stream]` | Disassemble from address |
| `make-debug-map` | Create an address→source-loc map (package `cl-asm/debug-map`) |

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
        .padto $C000       ; pad to absolute address (with $00)
        .padto $C000, $FF  ; pad to absolute address (with $FF)
        .assertpc $C000    ; error if PC ≠ $C000
        .asciiz "HELLO"   ; ASCII string + null terminator
        .pascalstr "HI"   ; length byte + string

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

# Intel 8080 / CP/M target
./cl-asm prog.asm --target 8080

# Assemble an ACME source file directly (no conversion needed)
./cl-asm terminal.asm --target x16

# Verbose mode
./cl-asm programme.asm -v
```

### Options

| Option | Description | Default |
| --- | --- | --- |
| `-o FILE` | Output file | same name, .prg extension |
| `-f FORMAT` | `prg` or `bin` | `prg` |
| `--origin ADDR` | Origin address (e.g. `0x0801`) | `0x0801` |
| `-t TARGET` | `6502` (also `mos6502`), `6510` (also `mos6510`, `c64`), `45gs02` (also `mega65`), `x16` (also `65c02`, `commander-x16`), `r65c02` (also `rockwell`), `65816` (also `wdc65816`, `snes`, `apple2gs`), `z80` (also `z80cpu`, `zxspectrum`, `spectrum`, `cpc`, `msx`), `i8080` (also `8080`, `cpm`, `altair`, `intel8080`) | `6502` |
| `-v` | Verbose mode | — |

Target is auto-detected from the first lines of the source file:

* `.asm`: `; target: 45gs02` or `; target: x16`
* `.lasm`: `(target :45gs02)`

---

## .lasm Frontend — Native Lisp Syntax

`.lasm` files are valid Common Lisp executed in a context where each
mnemonic is a function. The full power of CL is available: `let`,
`dotimes`, `loop`, `defun`, `defmacro`, etc.

**Supported targets:** all architectures — `:6502` (default),
`:45gs02`/`:mega65`, `:65c02`/`:x16`, `:r65c02`, `:65816`/`:snes`/`:apple2gs`,
`:z80`/`:spectrum`/`:msx`/`:cpc`, `:m68k`/`:amiga`/`:atari`,
`:i8080`/`:8080`/`:cpm`/`:altair`.

> **Note for Z80 and M68K:** use `:origin 0` (the default `#x0801` is for 6502).
> Architecture-specific instructions use `zi`/`mi` helpers (see below).

> **Note on shadowed symbols:** the following CL standard names are
> redefined as assembly instructions inside `.lasm` files: `fill`,
> `bit`, `sec`, `and`, `map`. Use `cl:fill`, `cl:and`, etc. if you
> need the original CL function.

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

```
(lda #x10)        ; LDA $10   (zero-page, value ≤ 255)
(lda #x1234)      ; LDA $1234 (absolute, value > 255)
(lda 'screen)     ; LDA SCREEN (symbol, resolved at assembly)
```

With keyword — explicit mode:

| Keyword | Mode | Example |
|---------|------|---------|
| `:imm` | Immediate | `(lda :imm #xFF)` → `LDA #$FF` |
| `:x` | Indexed X | `(lda :x #x10)` → `LDA $10,X` |
| `:y` | Indexed Y | `(lda :y #x1234)` → `LDA $1234,Y` |
| `:z` | Indexed Z (45GS02) | `(lda :z #x10)` → `LDA $10,Z` |
| `:ind` | Indirect | `(jmp :ind #xFFFC)` → `JMP ($FFFC)` |
| `:ix` | Pre-indexed X | `(lda :ix #x00)` → `LDA ($00,X)` |
| `:iy` | Post-indexed Y | `(lda :iy #xB0)` → `LDA ($B0),Y` |
| `:iz` | Post-indexed Z (45GS02) | `(lda :iz #xB0)` → `LDA ($B0),Z` |
| `:abs` | Forced absolute | `(lda :abs #x10)` → `LDA $0010` |
| `:zp` | Forced zero-page | `(lda :zp #x100)` → `LDA $00` |
| `:a` | Accumulator | `(lsr :a)` → `LSR A` |

### Available directives

| Directive | Description |
|-----------|-------------|
| `(org n)` | Set assembly origin |
| `(label 'name)` | Place a local label |
| `(global-label 'name)` | Place a global (exported) label |
| `(equ 'name value)` | Define a constant: `(equ 'cols 40)` → `COLS = 40` |
| `(db v …)` | Emit bytes (`.byte`) |
| `(dw v …)` | Emit 16-bit words, little-endian (`.word`) |
| `(dd v …)` | Emit 32-bit words, little-endian (`.dword`) |
| `(text "str")` | Emit ASCII string without null terminator |
| `(fill n [v])` | Emit `n` bytes of value `v` (default 0) |
| `(align n [v])` | Align PC to boundary `n`, pad with `v` |
| `(pad-to addr [v])` | Fill from PC to `addr` with `v` (default 0); error if PC > addr |
| `(assert-pc addr)` | Error if current PC ≠ `addr` (layout check) |
| `(ascii-z "str")` | Emit ASCII string + null terminator (`$00`) |
| `(pascal-str "str")` | Emit length byte (1 byte) followed by string |
| `(defstruct-asm name f…)` | Define a struct: auto-compute field offsets (see below) |
| `(defenum name v…)` | Define an enum: sequential constants from 0 (see below) |
| `(include-binary "file" [off [n]])` | Include raw binary file (optional offset and byte count) |
| `(petscii "str")` | Emit string with ASCII→PETSCII conversion (a-z → PETSCII A-Z) |
| `(assert-size n body…)` | Error if `body` does not emit exactly `n` bytes |
| `(sine-table 'lbl n amp off)` | Emit N-entry sine wave table (amplitude + offset) |
| `(cosine-table 'lbl n amp off)` | Emit N-entry cosine wave table |
| `(linear-ramp 'lbl from to n)` | Emit N-entry linear ramp from `from` to `to` |
| `(section :name)` | Switch to named section |
| `(target :arch)` | Architecture hint for CLI (no-op at runtime) |

### Z80 helpers

| Function | Description |
|----------|-------------|
| `(z80r "HL")` | Z80 register operand (`:direct "HL"`) |
| `(z80ind "HL")` | Indirect Z80 operand `(HL)` |
| `(z80ind "IX" 5)` | Indexed indirect `(IX+5)` |
| `(zi "LD" op1 op2)` | Emit arbitrary Z80 instruction |

```lisp
(assemble-lasm-string
  "(zi \"LD\" (z80r \"A\") (z80r \"B\"))   ; LD A, B
   (zi \"PUSH\" (z80r \"HL\"))              ; PUSH HL
   (zi \"JP\" (make-dir 'start))"           ; JP start
  :target :z80 :origin 0)
```

### M68K helpers

| Function | Description |
|----------|-------------|
| `(dn n)` | Data register Dn (`:direct "Dn"`) |
| `(an n)` | Address register An (`:direct "An"`) |
| `(ind-an n)` | Indirect `(An)` |
| `(post-an n)` | Post-increment `(An)+` |
| `(pre-an n)` | Pre-decrement `-(An)` |
| `(m68k-imm val)` | Immediate `#val` |
| `(mi "MOVE" :word op1 op2)` | Emit M68K instruction with optional size |

```lisp
(assemble-lasm-string
  "(mi \"MOVE\" :word (dn 0) (dn 1))   ; MOVE.W D0, D1
   (mi \"CLR\"  :byte (dn 3))           ; CLR.B  D3
   (mi \"NOP\")"                        ; NOP
  :target :m68k :origin 0)
```

### Helper macros

| Macro | Description |
|-------|-------------|
| `(genlabel)` | Generate a unique anonymous label keyword |
| `(with-label name &body)` | Place label `name`, then execute body |
| `(lasm-if cond-fn t-label f-label &body)` | Emit a conditional if/else structure |

`lasm-if` example:
```lisp
; Branch to generated end label if BEQ condition met
(lasm-if (lambda (l) (beq l)) 'done 'skip
  (lda :imm 0)
  (sta #xD020))
```

### `defstruct-asm` — struct with automatic field offsets

Fields are either a keyword (1-byte field) or `(keyword size)` for multi-byte fields.
All architectures supported.

```lisp
(defstruct-asm player :x :y (:hp 2) :state)
; → PLAYER.X=0, PLAYER.Y=1, PLAYER.HP=2, PLAYER.STATE=4, PLAYER.SIZE=5
```

Classic `.asm` syntax — multi-line block:
```asm
.defstruct player
  .field x
  .field y
  .field hp, 2
  .field state
.endstruct
; PLAYER.X=0  PLAYER.Y=1  PLAYER.HP=2  PLAYER.STATE=4  PLAYER.SIZE=5
```

### `defenum` — sequential constants

Values are numbered from 0. `ENUM.COUNT` is automatically defined.
All architectures supported.

```lisp
(defenum color :black :white :red :green :blue)
; → COLOR.BLACK=0, COLOR.WHITE=1, COLOR.RED=2, COLOR.GREEN=3, COLOR.BLUE=4
;   COLOR.COUNT=5
```

Classic `.asm` syntax — multi-line block:
```asm
.defenum state
  .val idle
  .val running
  .val paused
.endenum
; STATE.IDLE=0  STATE.RUNNING=1  STATE.PAUSED=2  STATE.COUNT=3
```

### 45GS02-specific instructions

When using `:target :45gs02`, additional mnemonics are available:

- **Z register:** `ldz  stz  inz  dez  phz  plz  taz  tza`
- **B register:** `tab  tba  tsy  tys`
- **Q register (32-bit):** `ldq  stq  adcq  sbcq  andq  oraq  eorq  aslq  lsrq  rolq  rorq  asrq  bitq  cmpq`
- **Long branches:** `lbcc  lbcs  lbeq  lbne  lbmi  lbpl  lbvc  lbvs`
- **Misc:** `map  eom  neg  asr  inw  dew`

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

; Reusable subroutine
(defun set-border (col)
  (lda :imm col)
  (sta #xD020))

(set-border 0)
(set-border 14)

; Loop with anonymous label
(let ((loop-lbl (genlabel)))
  (label loop-lbl)
  (dex)
  (bne loop-lbl))
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
`!word`/`!16` → `.word`, `!pet` → `.byte` with explicit PETSCII codes
(a-z → A-Z uppercase −0x20, A-Z → shifted +0x80; mixed forms supported),
`!fill` → `.fill`, `!macro`/`!if` → `.macro`/`.if`,
`!cpu m65` → `; target: 45gs02`, `!cpu 65c02` → `; target: x16`.
Non-ASCII characters in comments are normalized to ASCII.

Simple ACME files (using `!byte`, `!pet`, `*=addr`, `!to`, `!cpu`) can also be
assembled directly without conversion:

    ./cl-asm source.s --target x16

Use `acme2clasm` for files requiring `!source`, `!binary`, `!pseudopc`, macros,
or other advanced ACME features not yet supported natively.

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
