# Changelog cl-asm

All notable changes to this project are documented here.
Format inspired by [Keep a Changelog](https://keepachangelog.com/).

---

## [0.15.0] — 2026-03-28

### Added
- **Intel 8086/8088 backend** (`src/backend/i8086.lisp`): full 16-bit x86 real-mode encoder. MOV (all forms), XCHG, LEA, LDS, LES, ALU (ADD/SUB/AND/OR/XOR/CMP + immediate, accumulator short forms), ADC/SBB, INC/DEC, NEG/NOT/MUL/IMUL/DIV/IDIV, shifts/rotates (ROL/ROR/RCL/RCR/SHL/SAL/SHR/SAR × 1/CL/imm8), PUSH/POP (reg/seg/imm), all Jcc (rel8), LOOP/LOOPE/LOOPNE/JCXZ, JMP (short/near/far/reg/mem), CALL (near/far/reg/mem), RET/RETF/IRET, INT/INTO/BOUND, IN/OUT, all 1-byte implied instructions (CLC/STC/CLI/STI/CLD/STD/CBW/CWD/XLAT/NOP/HLT/WAIT/LOCK/PUSHF/POPF/LAHF/SAHF/AAA/AAS/AAM/AAD/DAA/DAS/SALC/XLATB).
- ModRM byte encoding: all 8086 addressing modes — `[BX+SI]`, `[BX+DI]`, `[BP+SI]`, `[BP+DI]`, `[SI]`, `[DI]`, `[BP]`, `[BX]`, direct address, with 16-bit displacement.
- `*i8086-mode*` variable and `i8086-mnemonic-p` hook in the classic parser — same pattern as Z80/M68K/8080 to avoid mnemonic conflicts.
- `parse-i8086-operands`/`parse-i8086-mem-ref` in `classic-parser.lisp`: `[base+index+disp]` memory references, `BYTE/WORD PTR [...]`, `SHORT expr` for `JMP SHORT`.
- Backend registered under aliases: `"8086"` `"i8086"` `"8088"` `"i8088"` `"ibmpc"` `"msdos"` `"x86-16"`.
- 236 tests in `tests/test-8086.lisp`.

### Tests

| Suite | Tests |
|-------|-------|
| test-8086 | 236 |
| **Total** | **2706** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.14.0] — 2026-03-27

### Added
- **Conditions/Restarts** (`src/core/restarts.lisp`): CL restart protocol on assembly errors — `use-value`, `use-zero` for `asm-undefined-label`; `skip-instruction` for `asm-unknown-mnemonic`/`asm-syntax-error`; `clamp-value`/`use-value` for `asm-range-error` (out-of-range branches).
- `with-asm-use-zero` macro: auto-resolve undefined labels to 0.
- `with-asm-skip-errors` macro: silently ignore unknown mnemonics and unsupported addressing modes.

### Changed
- `symbol-table.lisp`: `%signal-undefined-label` helper wraps `asm-undefined-label` with `restart-case`.
- `6502.lisp`: `encode-instruction` adds `skip-instruction` restart; `encode-relative` adds `clamp-value` and `use-value` restarts. All existing behaviour unchanged when no handler is bound.

### Tests

| Suite | Tests |
|-------|-------|
| test-restarts | 14 |
| **Total** | **2470** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.13.0] — 2026-03-27

### Added
- **Peephole optimizer** (`src/core/optimizer.lisp`): extensible registry — `register-peephole-optimizer`, `find-peephole-optimizer`, `optimize-sections`. Called before pass-1 when `assemble` is invoked with `&key optimize t`.
- **6502/6510 rules** (`src/optimizer/6502.lisp`): rule A (JMP→next label elimination), rule B (JSR/RTS→JMP tail-call). Exported as `*rules-6502*`.
- **65C02/45GS02 rules** (`src/optimizer/65c02.lisp`): rules A+B+C for `:65c02`; rules A+B only for `:45gs02`. Rule C: `LDA #0 / STA :direct` → `STZ :direct` (nil or :x index-reg). Note: STZ on 45GS02 means "Store Z register", so rule C is excluded for that target.

### Tests

| Suite | Tests |
|-------|-------|
| optimizer-6502 (new) | 28 |
| **Total** | **2456** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.12.0] — 2026-03-27

### Added

**In-memory modular linker** (`src/core/linker.lisp`) — new module:
- `link-unit` struct: wraps the IR sections of a parsed source file + target architecture
- `link-unit-from-program name program &optional target`: convenience constructor from an IR-PROGRAM
- `link units &key origin`: merges sections from all units, creates a shared symbol table, runs both passes → `(unsigned-byte 8)` vector
- Extensible registry: `register-linker-backend` / `find-linker-backend` / `all-linker-backends`
- Registered backends: `:6502`, `:6510`, `:65c02`, `:45gs02`
- Cross-file label references: labels defined in one unit are resolved by the others
- Validation: error if the list is empty, backend is unknown, or targets are mixed

### Tests

| Suite | 0.11.0 | 0.12.0 |
|---|---|---|
| linker-6502 (new) | — | 26 |
| **TOTAL** | **2402** | **2428** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.11.0] — 2026-03-26

### Added

**Extensible disassembler registry** (`src/core/disassemblers.lisp`) — new module:
- `register-disassembler` / `find-disassembler-by-keyword` / `all-disassemblers`
- Same design as the backend registry; each disassembler self-registers at load time

**45GS02 disassembler** (`src/disassembler/45gs02.lisp`) — new module:
- Full prefix dispatcher: `$EA` (indirect-32), `$42` (long branches), `$42 $42` (Q register), `$42 $42 $EA` (Q indirect-32)
- 45GS02-specific non-prefixed opcodes: LDZ, STZ (Z register), INZ, DEZ, PHZ, PLZ, TAZ, TZA, TBA, TAB, TSY, TYS, MAP, EOM, ASR, INW, DEW, ROW, NEG
- Inherits 6502 base table, overrides STZ ($84/$94 store Z register)
- Long-branch target computation (signed 16-bit offset, PC+4 relative)
- Registered as `:45gs02` with aliases `"45gs02"` / `"mega65"`

**65C02 disassembler** (`src/disassembler/65c02.lisp`) — new module:
- No-prefix flat table (same structure as 6502 disassembler)
- New instructions: BRA, STZ, TRB, TSB, PHX/PLX/PHY/PLY, INC A, DEC A
- New modes: `:zero-page-indirect` → `($nn)`, `:indirect-absolute-x` → `($nnnn,X)`
- Extended modes: LDA/STA/ADC/SBC/AND/ORA/EOR/CMP `($nn)`, JMP `($nnnn,X)`, BIT `#imm`/`zp,X`/`abs,X`
- Registered as `:65c02` with aliases `"65c02"` / `"x16"` / `"commander-x16"`

**Pluggable disassembler in debugger** (`src/debugger/6502.lisp`):
- New `disasm-fn` slot in `debugger` struct (default: `#'cl-asm/disassembler.6502:disasm-one`)
- `make-debugger` accepts `:disasm-fn` keyword; `show-current`, `show-disasm`, `debugger-next` use it
- Debugger is now architecture-agnostic for disassembly display

### Tests

| Suite | 0.10.0 | 0.11.0 |
|---|---|---|
| disasm-45gs02 (new) | — | 97 |
| disasm-65c02 (new) | — | 44 |
| **TOTAL** | **2261** | **2402** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.10.0] — 2026-03-26

### Added

**MOS 6510 backend** (`src/backend/6510.lisp`) — new module:
- Extends the 6502 backend with **stable illegal opcodes** used in C64 demos and games
- 14 new mnemonics, 58 new opcode entries:
  - `LAX` — load A and X simultaneously (6 modes: zp / zp,Y / abs / abs,Y / (ind,X) / (ind),Y)
  - `SAX` — store A AND X (4 modes: zp / zp,Y / abs / (ind,X))
  - `SLO` — ASL memory then ORA A (7 modes, alias ASO)
  - `RLA` — ROL memory then AND A (7 modes)
  - `SRE` — LSR memory then EOR A (7 modes, alias LSE)
  - `RRA` — ROR memory then ADC A (7 modes)
  - `DCP` — DEC memory then CMP A (7 modes, alias DCM)
  - `ISC` — INC memory then SBC A (7 modes, alias ISB/INS)
  - `ALR` — AND #imm then LSR A (1 mode, alias ASR)
  - `ANC` — AND #imm, bit 7 → C (1 mode)
  - `ARR` — AND #imm then ROR A (1 mode, non-standard V/C flags)
  - `AXS` — (A AND X) − #imm → X, NZC updated (1 mode, alias SBX)
  - `LAS` — (abs,Y) AND SP → A/X/SP (1 mode)
  - `KIL` — freeze CPU / JAM (implied, opcode $02)
- Unstable opcodes excluded (XAA/ANE, AHX/SHA, TAS/SHS, SHY, SHX)
- `assemble-6510` / `assemble-string-6510` / `assemble-file-6510` (with `&key debug-map`)
- Target aliases: `"6510"`, `"mos6510"`, `"c64"`

### Modified

- `src/backend/6502.lisp` — `"c64"` alias moved to the 6510 backend; 6502 now registers as `"6502"` / `"mos6502"` only
- `cl-asm.asd` — 6510 added between 6502 and 45gs02 in the dependency graph

### Tests

| Suite | 0.9.0 | 0.10.0 |
|---|---|---|
| 6510 (new) | — | 66 |
| **TOTAL** | **2195** | **2261** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.9.0] — 2026-03-25

### Added

**6502 Debugger — source display** (`src/debugger/6502.lisp`):
- `show-current` now reads the actual source file when `source-loc-file` is non-nil (set by `assemble-file`)
- Displays `; file:line | source text` above the disassembly line
- `source-cache` (hash filename → vector-of-lines) in the `debugger` struct — each file loaded once per session
- Zero overhead when no file is available (parse-string path or no debug-map)

**6502 Debugger — conditional breakpoints in REPL**:
- REPL command `b $ADDR <lisp-expr>` compiles a condition via `eval`: `(lambda (cpu) <expr>)`
- `cpu` is bound to the CPU struct; use full package prefix, e.g. `(cl-asm/simulator.6502:cpu-a cpu)`
- Example: `b $0210 (= (cl-asm/simulator.6502:cpu-a cpu) #xFF)`
- Invalid expression prints an error message without crashing the REPL
- `b $ADDR` without condition remains unconditional (unchanged behavior)

### Modified

- `src/backend/6502.lisp` — `assemble-file` now accepts `&key debug-map` and passes it to `assemble`

### Tests

| Suite | 0.8.0 | 0.9.0 |
|---|---|---|
| debugger-6502 | 68 | 80 |
| **TOTAL** | **2183** | **2195** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.8.0] — 2026-03-25

### Added

**Watchpoints** — memory surveillance in the 6502 debugger:
- `set-watchpoint dbg addr &key kind` — `:read` | `:write` | `:rw` (default `:write`)
- `clear-watchpoint dbg addr`, `list-watchpoints dbg`
- Wired to the simulator via `cpu-watch-table` (hash-table addr → kind in the `cpu` struct)
- `cpu-watchpoint` condition (address, kind) signaled by `mem-read`/`mem-write` when a watch entry matches
- `%step-one` captures `cpu-watchpoint` and returns `:watchpoint`; `debugger-last-watchpoint` stores `(address kind)`
- All execution functions (`step`, `next`, `continue`) return/handle `:watchpoint`
- REPL commands: `w $ADDR [read|write|rw]`, `dw $ADDR`, `lw`

### Modified

- `src/simulator/6502.lisp`: `cpu` struct gains `watch-table` slot (nil by default — zero overhead when not used); `mem-read`/`mem-write` check the table; `cpu-watchpoint` condition defined
- `src/debugger/6502.lisp`: watchpoints fully wired; `debugger` struct gains `last-watchpoint` slot; REPL help updated

### Tests

| Suite | 0.7.0 | 0.8.0 |
|---|---|---|
| debugger-6502 | 56 | 68 |
| **TOTAL** | **2171** | **2183** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.7.0] — 2026-03-25

### Added

**6502 Interactive Debugger** (`src/debugger/6502.lisp`) — new module:
- `make-debugger cpu &key debug-map` — create a debugger session
- `debugger-repl dbg &key input output` — interactive REPL with string-stream support (testable)
- `debugger-step` / `debugger-next` / `debugger-continue` — atomic execution primitives
  - `next` implements step-over: skips JSR subroutine bodies entirely
  - All return `:ok` | `:brk` | `:breakpoint` | `:illegal`
- `set-breakpoint dbg addr &key condition` — unconditional (v0.7.0) or conditional breakpoints
  - `condition` slot already present for future `(lambda (cpu) → bool)` breakpoints
- `clear-breakpoint`, `list-breakpoints` — breakpoint management
- `watchpoint` struct defined (wiring to simulator: extended scope)
- Display helpers: `show-registers`, `show-current`, `show-memory`, `show-disasm`
- `format-flags` — renders P register as `NV-BDIZC` (uppercase = set)
- REPL commands: `s`/`step`, `n`/`next`, `c`/`continue`, `b`/`d`/`lb`, `r`/`regs`, `m`/`mem`, `x`/`disasm`, `h`/`help`, `q`/`quit`, empty = repeat

**Address→source mapping** (`src/core/debug-map.lisp`) — new module:
- `debug-map` struct: vector of 65536 entries (address → source-loc)
- `make-debug-map`, `debug-map-get`, `debug-map-set`
- Defined in `cl-asm/debug-map` (core layer) so both the backend and debugger can use it without circular dependency

### Modified

**`src/backend/6502.lisp`** — `assemble` and `pass-2` accept `&key debug-map`:
- When provided, `pass-2` records `address → source-loc` for every assembled instruction
- Zero overhead when `debug-map` is `nil` (default)

### Tests

| Suite | 0.6.0 | 0.7.0 |
|---|---|---|
| debugger-6502 (new) | — | 56 |
| **TOTAL** | **2115** | **2171** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.6.0] — 2026-03-22

### Added

**6502 CPU Simulator** (`src/simulator/6502.lisp`) — new module:
- CPU struct with registers A/X/Y/PC/SP/P and 64 KB memory array
- `make-cpu`, `reset-cpu`, `load-program`
- `mem-read`, `mem-write`, `mem-read16` (inline)
- `fetch`, `fetch16` — inline helpers for reading operands at PC
- Addressing mode helpers: `addr-zp`, `addr-zpx`, `addr-zpy`, `addr-abs`, `addr-absx*`, `addr-absy*`, `addr-indx`, `addr-indy*`
- Flag helpers: `set-flag`, `update-nz`, `flag-c/z/i/d/b/v/n`, 8 mask constants
- Stack: `stack-push`, `stack-pull`
- ALU helpers: `do-adc` (with V flag), `do-sbc`, `do-and`, `do-ora`, `do-eor`, `do-cmp`, `do-bit`, `do-asl`, `do-lsr`, `do-rol`, `do-ror`
- `step-cpu`: 152 opcodes covering the full 6502 instruction set:
  - 23 implied (NOP BRK TAX TXA TAY TYA TSX TXS PHA PLA PHP PLP INX INY DEX DEY CLC SEC CLI SEI CLV CLD SED)
  - Load/store: LDA×8, LDX×5, LDY×5, STA×7, STX×3, STY×3
  - ALU: ADC×8, SBC×8, AND×8, ORA×8, EOR×8, CMP×8, CPX×3, CPY×3, BIT×2
  - Shifts/rotations: ASL×5, LSR×5, ROL×5, ROR×5
  - Memory inc/dec: INC×4, DEC×4
  - Jumps/branches: JMP abs, JMP (ind) with original 6502 page bug, JSR, RTS, RTI, BCC BCS BEQ BNE BMI BPL BVC BVS
- Page-crossing cycle penalty (+1 read, fixed for writes)
- Conditions: `cpu-break`, `cpu-illegal-opcode`, `cpu-step-limit`
- `run-cpu` loops until BRK or `max-steps`, returns `(values cpu :brk|:step-limit)`

### Tests

| Suite | 0.5.0 | 0.6.0 |
|---|---|---|
| sim-6502 (new) | — | 294 |
| **TOTAL** | **1627** | **1921** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.5.0] — 2026-03-22

### Added

**Intel 8080 backend** (`src/backend/i8080.lisp`) — new architecture:
- Full Intel 8080 instruction set (~78 mnemonics): MOV, MVI, LXI, LDA, STA, LHLD, SHLD, LDAX, STAX, INR, DCR, INX, DCX, DAD, ADD, ADC, SUB, SBB, ANA, XRA, ORA, CMP, ADI/ACI/SUI/SBI/ANI/XRI/ORI/CPI, JMP, CALL, RET, Jcc, Ccc, Rcc, PUSH, POP, IN, OUT, RST, NOP, HLT, XCHG, XTHL, PCHL, SPHL, DI, EI, RLC, RRC, RAL, RAR, DAA, CMA, STC, CMC
- All directives inherited from Z80 pattern: `.org`, `.byte`, `.word`, `.dword`, `.fill`, `.padto`, `.assertpc`, `assert-size`, `.incbin`, `.defstruct`, `.defenum`, `.asciiz`, `.pascalstr`, `.petscii`
- Two-pass assembly, symbol table, forward references
- `*i8080-mode*` variable in `cl-asm/parser` (same pattern as `*z80-mode*`) — avoids mnemonic conflicts with 6502 parser
- `assemble-i8080`, `assemble-string-i8080`, `assemble-file-i8080` API
- Backend aliases: `"i8080"`, `"8080"`, `"cpm"`, `"altair"`, `"intel8080"`

**`.lasm` frontend helpers for Intel 8080:**
- `(i8080r "A")` — register 8-bit operand (B C D E H L M A)
- `(i8080rp "H")` — register pair operand (B D H SP PSW)
- `(i8080 "MOV" op1 op2)` — emit generic 8080 instruction
- Target dispatch: `(assemble-lasm-string src :target :i8080)`

**`cl-asm/parser` additions:**
- `*i8080-mode*` defvar (NIL by default)
- `*i8080-mnemonics*` list
- `i8080-mnemonic-p` predicate
- Comma-separated operand parsing reuses Z80 parser when `*i8080-mode* = T`

### Tests

| Suite | 0.4.4 | 0.5.0 |
|---|---|---|
| i8080 (new) | — | 144 |
| **TOTAL** | **1483** | **1627** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.4.4] — 2026-03-22

### Fixed

**`acme2clasm` converter — `label: !directive` lines** — lines combining a label
and an ACME directive on the same line (e.g. `my_data: !byte $01, $02`) were
previously emitted with the raw directive text instead of being converted. The
directive part is now recursively converted to `.asm` syntax.

### Tests

| Suite | 0.4.3 | 0.4.4 |
|---|---|---|
| acme2clasm | — | 20 |
| **TOTAL** | **1463** | **1483** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.4.3] — 2026-03-22

### Added

**`(petscii "str")` directive** — emit string with ASCII→PETSCII conversion:
- Lisp frontend (`.lasm`): `(petscii "hello")`
- Classic frontend (`.asm`): `.petscii "hello"` (alias → `:pet`)
- Lowercase a-z → PETSCII uppercase (A-Z); uppercase A-Z → PETSCII shifted set
- Supported on all architectures: 6502, 65C02, R65C02, 45GS02, 65816, Z80, M68K

**`(assert-size N body…)` macro** — verify that a block emits exactly N bytes:
- Lisp frontend (`.lasm`): `(assert-size 16 (lda :imm 0) …)`
- Generates a hidden label + `:assertsize` directive; error if actual size ≠ N
- Supported on all architectures: 6502, 65C02, R65C02, 45GS02, 65816, Z80, M68K

**`(sine-table label n amplitude offset)` directive** — sine wave lookup table:
- Emits N bytes: `round(sin(2π·i/N) × amplitude + offset)` for i in [0, N)
- Example: `(sine-table 'sin-tbl 256 127 128)` → 256-entry table, range [1, 255]

**`(cosine-table label n amplitude offset)` directive** — cosine wave lookup table:
- Same as `sine-table` but using cosine
- Example: `(cosine-table 'cos-tbl 256 127 128)`

**`(linear-ramp label from to n)` directive** — linear ramp lookup table:
- Emits N bytes linearly interpolated from `from` to `to`
- Example: `(linear-ramp 'ramp 0 255 256)` → 256-entry ramp from 0 to 255

### Tests

| Suite | 0.4.2 | 0.4.3 |
|---|---|---|
| lasm | 82 | 100 |
| **TOTAL** | **1445** | **1463** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.4.2] — 2026-03-22

### Added

**`.padto` directive** — fill from current PC to an absolute target address:
- Classic frontend (`.asm`): `.padto ADDR` or `.padto ADDR, VAL`
- Lisp frontend (`.lasm`): `(pad-to addr)` or `(pad-to addr fill-val)`
- Supported on all architectures: 6502, 65C02, R65C02, 45GS02, 65816, Z80, M68K
- Emits fill byte `VAL` (default `$00`) from current PC until `ADDR`; error if PC > ADDR
- If PC == ADDR: no bytes emitted

**`.assertpc` directive** — layout assertion: error if current PC ≠ expected address:
- Classic frontend (`.asm`): `.assertpc ADDR`
- Lisp frontend (`.lasm`): `(assert-pc addr)`
- Supported on all architectures: 6502, 65C02, R65C02, 45GS02, 65816, Z80, M68K
- No bytes emitted; error message includes expected and actual PC values

**`.asciiz` directive** — emit ASCII string with null terminator:
- Classic frontend (`.asm`): `.asciiz "string"`
- Lisp frontend (`.lasm`): `(ascii-z "string")`
- Supported on all architectures

**`.pascalstr` directive** — emit length-prefixed string (Pascal style):
- Classic frontend (`.asm`): `.pascalstr "string"`
- Lisp frontend (`.lasm`): `(pascal-str "string")`
- Length byte (max 255) followed by the string bytes; supported on all architectures

**`defenum` / `.defenum` directive** — sequential named constants:
- Lisp frontend (`.lasm`): `(defenum color :black :white :red)`
- Classic frontend (`.asm`): `.defenum`/`.val`/`.endenum` block
- Values numbered from 0; `ENUM.COUNT` defined automatically
- Supported on all architectures

**`include-binary` / `.incbin` directive** — include raw binary file as data:
- Lisp frontend (`.lasm`): `(include-binary "sprite.bin")` or `(include-binary "file" offset count)`
- Classic frontend (`.asm`): `.incbin "file"` or `.incbin "file", offset` or `.incbin "file", offset, count`
- Supported on all architectures
- Optional `offset` (skip first N bytes) and `count` (emit N bytes); default = whole file
- Listing shows filename and byte count

**`defstruct-asm` / `.defstruct` directive** — struct with automatic field offset computation:
- Lisp frontend (`.lasm`): `(defstruct-asm player :x :y (:hp 2) :state)`
- Classic frontend (`.asm`): `.defstruct`/`.field`/`.endstruct` block
- Fields: keyword = 1-byte field; `(keyword size)` = multi-byte field
- Defines `STRUCT.FIELD` constants for each field + `STRUCT.SIZE` for total size
- Supported on all architectures (6502, 65C02, R65C02, 45GS02, 65816, Z80, M68K)
- Listing expanded: `.DEFSTRUCT` header + one `FIELD = offset` line per field

**`.lasm` frontend extended to all architectures** — `assemble-lasm-string` and `assemble-lasm`
now support all targets:
- `:6502` (default), `:45gs02`/`:mega65`, `:65c02`/`:x16`, `:r65c02`
- `:65816`/`:snes`/`:apple2gs`
- `:z80`/`:spectrum`/`:msx`/`:cpc` — use `(z80r)`, `(z80ind)`, `(zi)` helpers
- `:m68k`/`:amiga`/`:atari`/`:mac68k` — use `(dn)`, `(an)`, `(ind-an)`, `(mi)` helpers
- New `.lasm` mnemonics: 65C02 (`bra`, `stz`, `trb`, `tsb`, `phx/phy/plx/ply`);
  R65C02 (`rmb0-7`, `smb0-7`, `bbr0-7`, `bbs0-7`);
  65816 (`xba`, `xce`, `jsl`, `jml`, `brl`, `sep`, `rep`, `mvn`, `mvp`, `pea`, etc.)

### Tests

| Suite | 0.4.1 | 0.4.2 |
|---|---|---|
| 6502 | 82 | 94 |
| lasm | 58 | 82 |
| 6502 | 94 | 105 |
| **TOTAL** | **1398** | **1445** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.4.1] — 2026-03-22

### Added

**Native ACME syntax support** — cl-asm's classic frontend now accepts ACME source files
directly without conversion:
- `*=ADDR` — ACME-style org (equivalent to `.org ADDR`)
- `!BYTE` / `!WORD` / `!FILL` — direct aliases for `.byte`/`.word`/`.fill`
- `!PET "str",n,...` — PETSCII emission: a-z → 0x41-0x5A (−0x20), A-Z → 0xC1-0xDA (+0x80); numeric args passed as-is; mixed forms supported (`!PET 147,"str",13,0`)
- `!to "file",cbm` — ignored (output name handled by `--target`)
- `!cpu 65c02` — ignored (CPU fixed by `--target`)

**ca65 anonymous labels** — `:` on its own line defines an anonymous label;
`:-` / `:--` / `:---` reference the 1st/2nd/3rd previous; `:+` / `:++` reference
the 1st/2nd following.

**ca65 scoped `@`-labels** — `@name:` defines a label local to the enclosing global
label; `@name` references it. Two routines can each have their own `@loop:` without conflict.

**`.res N` directive** — alias for `.fill N` (reserve N bytes, ca65 compatibility).

**`tests/regression/x16/06-bank-byte-operator.asm`** — regression test for `^` (bank byte operator).

**`tests/regression/x16/07-anon-scoped-labels.asm`** — regression test: anonymous labels, scoped `@`-labels, `.res`, inline `.byte "string"`, immediate forward-ref.

**`tests/regression/x16/08-acme-directives.asm`** — regression test: `!to`, `!cpu`, `*=`, `!BYTE`, `!PET` (PETSCII conversion verified against ACME assembler output).

**Skip lists** — `tests/regression/x16/.ca65-skip` and `.acme-skip` to handle files that are specific to one syntax.

### Fixed

**Pass 1 immediate forward-ref size** — `ldx #<forward_label` previously estimated 3 bytes (max for LDX) instead of 2 in pass 1, causing all subsequent addresses to be off. Now correctly estimates 2 bytes for immediate mode regardless of resolution.

**`ASL`/`LSR`/`ROL`/`ROR` without operand** — `:implied` now falls back to `:accumulator` when no `:implied` clause exists (e.g. `ASL` alone = `ASL A`).

**`.byte "string"` inline** — string arguments to `.byte` were incorrectly passed to the expression evaluator. Now handled separately in both pass 1 (size estimation) and pass 2 (byte emission).

**`acme2clasm` — `!PET` conversion** — mixed-argument forms (`"str",13,0` and `147,"str",0`) now correctly handled; PETSCII conversion applied (a-z → A-Z, A-Z → shifted).

### Tests

| Suite | 0.4.0 | 0.4.1 |
|---|---|---|
| symbol-table | 65 | 65 |
| expression | 129 | 129 |
| lexer | 119 | 119 |
| parser | 84 | 84 |
| macros | 27 | 27 |
| conditional | 27 | 27 |
| lasm | 58 | 58 |
| 6502 | 82 | 82 |
| **65c02** | **41** | **86** |
| r65c02 | 117 | 117 |
| 45gs02 | 80 | 80 |
| 65816 | 104 | 104 |
| z80 | 191 | 191 |
| m68k-parser | 85 | 85 |
| m68k | 144 | 144 |
| **TOTAL** | **1353** | **1398** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.4.0] — 2026-03-21

### Added

**Motorola 68000 backend** — new file `src/backend/m68k.lisp`
(package `cl-asm/backend.m68k`) supporting the M68K processor (Amiga, Atari ST, Mac 68k):

- CLI aliases: `m68k`, `68000`, `68k`, `amiga`, `atari`, `mac68k`, `atarist`
- Default origin `$0000`
- Full M68K instruction set:
  - Data movement: `MOVE`, `MOVEA`, `MOVEQ`, `MOVEM`, `MOVEP`, `LEA`, `PEA`, `EXG`, `SWAP`
  - Arithmetic: `ADD`, `ADDI`, `ADDQ`, `ADDA`, `SUB`, `SUBI`, `SUBQ`, `SUBA`, `MULS`, `MULU`, `DIVS`, `DIVU`, `ABCD`, `SBCD`, `NBCD`
  - Logic: `AND`, `ANDI`, `OR`, `ORI`, `EOR`, `EORI`, `NOT`
  - Compare: `CMP`, `CMPI`, `CMPA`, `CMPM`, `TST`
  - Shifts: `ASL`, `ASR`, `LSL`, `LSR`, `ROL`, `ROR`, `ROXL`, `ROXR` (immediate, register, memory)
  - Bit manipulation: `BTST`, `BSET`, `BCLR`, `BCHG`
  - Unary: `CLR`, `NEG`, `NEGX`, `EXT`, `EXTB`
  - Branch/jump: `BRA`, `BSR`, `Bcc` (all 14 conditions), `DBcc`, `JMP`, `JSR`, `RTS`, `RTR`, `RTE`
  - System: `TRAP`, `TRAPV`, `LINK`, `UNLK`, `NOP`, `STOP`, `RESET`, `ILLEGAL`, `CHK`
  - All addressing modes: Dn, An, (An), (An)+, -(An), d(An), d(An,Xi), abs.W, abs.L, d(PC), d(PC,Xi), #imm
- Big-endian encoding throughout (`words->bytes`)

**M68K parser tests** — `tests/test-m68k-parser.lisp`: 85 tests covering M68K operand parsing, EA modes, size suffixes, register syntax.

**M68K backend tests** — `tests/test-m68k.lisp`: 139 tests across 17 groups:
implied, MOVE, MOVEA, MOVEQ, ADD/ADDI/ADDQ/ADDA, SUB/SUBI/SUBQ/SUBA,
AND/ANDI, OR/ORI, EOR/EORI, CMP/CMPI/CMPA, MULDIV, shifts, unary (CLR/NEG/etc.),
EXT/SWAP, JMP/JSR/LEA, branches/DBcc, misc (LINK/UNLK/TRAP/EXG/BCD), bit ops,
labels, addressing modes.

### Modified

**`src/core/version.lisp`** — version bumped: `0.3.0` → `0.4.0`

**Test scripts** — `run-tests.sh`, `run-tests-clisp.lisp`, `run-tests-ecl.lisp`
now load `src/backend/m68k.lisp`, `tests/test-m68k-parser.lisp`, and `tests/test-m68k.lisp`.

**`tests/run-tests.lisp`** — added `run-suite cl-asm/test.m68k-parser` and `run-suite cl-asm/test.m68k`; new "Architecture parsers" section in the summary output.

### Tests

| Suite | 0.3.0 | 0.4.0 |
|---|---|---|
| symbol-table | 65 | 65 |
| expression | 129 | 129 |
| lexer | 119 | 119 |
| parser | 84 | 84 |
| macros | 27 | 27 |
| conditional | 27 | 27 |
| lasm | 58 | 58 |
| 6502 | 82 | 82 |
| 65c02 | 41 | 41 |
| r65c02 | 117 | 117 |
| 45gs02 | 80 | 80 |
| 65816 | 104 | 104 |
| z80 | 191 | 191 |
| **m68k-parser** | — | **85** |
| **m68k** | — | **139** |
| **TOTAL** | **1124** | **1348** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.3.0] — 2026-03-21

### Added

**Zilog Z80 backend** — new file `src/backend/z80.lisp`
(package `cl-asm/backend.z80`) supporting the Z80 processor (ZX Spectrum, MSX, CPC, ZX81):

- CLI aliases: `z80`, `z80cpu`, `zx80`, `zx81`, `zxspectrum`, `spectrum`, `cpc`, `msx`
- Default origin `$0000`
- Full Z80 instruction set:
  - Implied, full LD (44 forms), ALU (ADD/ADC/SUB/SBC/AND/OR/XOR/CP)
  - INC/DEC 8/16-bit registers and indirects
  - PUSH/POP BC/DE/HL/AF/IX/IY
  - EX DE,HL / EX (SP),HL/IX/IY / EXX
  - CB-prefix rotations/shifts: RLC/RRC/RL/RR/SLA/SRA/SRL/SLL
  - BIT/SET/RES (CB) + (IX+d)/(IY+d) forms (DD CB/FD CB)
  - JP/JR conditional and unconditional, conditional CALL/RET
  - DJNZ (relative branch with B decrement)
  - IN r,(C) / IN A,(n) / OUT (C),r / OUT (n),A
  - ED-prefix extended: NEG, RETN, RETI, RLD, RRD, IM 0/1/2
  - Block operations: LDI/LDIR/LDD/LDDR/CPI/CPIR/CPD/CPDR/INI/INIR/IND/INDR/OUTI/OTIR/OUTD/OTDR
  - RST $00-$38

**Mnemonic conflict resolution** — `cl-asm/parser:*z80-mode*` variable:
  - Some Z80 mnemonics (`INC`, `DEC`, `AND`, `BIT`, `ADC`…) also exist in 6502.
  - `*z80-mode*` is NIL by default; set to T by `assemble-string-z80`/`assemble-file-z80` during parsing.
  - Prevents any parsing conflict between backends without modifying the 6502 parser.

**Z80 tests** — `tests/test-z80.lisp`: 191 tests across 19 groups:
implied, LD r/r' and n, LD indirect, LD 16-bit, LD memory,
PUSH/POP, INC/DEC, ALU, CB rotations, BIT/SET/RES, JP/JR/CALL/RET/DJNZ,
EX/EXX, IN/OUT, ADD IX/IY, misc (IM/blocks), directives, forward references,
minimal ZX Spectrum program, expected errors.

### Modified

**`src/core/version.lisp`** — version bumped: `0.2.0` → `0.3.0`

**`src/frontend/classic-parser.lisp`** — Z80 dispatch added to `parse-line`
and helpers: `*z80-mode*`, `*z80-mnemonics*`, `z80-mnemonic-p`,
`z80-comma-is-6502-index-p`, `parse-z80-operand-raw`, `parse-z80-operands`.

**Test scripts** — `run-tests.sh`, `run-tests-clisp.lisp`, `run-tests-ecl.lisp`
now load `src/backend/z80.lisp` and `tests/test-z80.lisp`.

### Tests

| Suite | 0.2.0 | 0.3.0 |
|---|---|---|
| symbol-table | 65 | 65 |
| expression | 129 | 129 |
| lexer | 119 | 119 |
| parser | 84 | 84 |
| macros | 27 | 27 |
| conditional | 27 | 27 |
| lasm | 58 | 58 |
| 6502 | 82 | 82 |
| 65c02 | 41 | 41 |
| r65c02 | 117 | 117 |
| 45gs02 | 80 | 80 |
| 65816 | 104 | 104 |
| **z80** | — | **191** |
| **TOTAL** | **933** | **1124** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.2.0] — 2026-03-20

### Added

**Backend WDC 65816** — nouveau fichier `src/backend/65816.lisp`
(package `cl-asm/backend.65816`) supportant le processeur WDC 65816 (SNES, Apple IIgs) :

- Origine par défaut `$8000` (LoROM SNES bank 0)
- Alias CLI : `65816`, `wdc65816`, `snes`, `apple2gs`
- 20+ modes d'adressage, dont :
  - `:absolute-long` / `:absolute-long-x` — adresses 24-bit (`$xxxxxx`)
  - `:dp-indirect-long` / `:dp-indirect-long-y` — `[$nn]`, `[$nn],Y`
  - `:stack-relative` / `:sr-indirect-y` — `$nn,S`, `($nn,S),Y`
  - `:relative-long` — branches 16-bit signées (BRL, PER)
  - `:block-move` — deux opérandes banque (MVN, MVP)
- **Accumulateur et index 16-bit** — immédiat variable selon les flags M/X :
  - `.al`/`.as` — bascule l'accumulateur entre 16-bit et 8-bit
  - `.xl`/`.xs` — bascule les index X/Y entre 16-bit et 8-bit
  - `REP`/`SEP` — instructions pour modifier les flags en dynamique
- `JSL`/`JML` — saut long 24-bit (4 et 3 octets)
- `BRL`/`PER` — branche longue / push effective relative address
- `MVN`/`MVP` — block move (deux opérandes banque séparés par une virgule)
- `PEA` — push effective address (toujours 16-bit)
- Toutes les instructions 6502 de base héritées

**Parser étendu** — `src/frontend/classic-parser.lisp` :
- Directives `.al`, `.as`, `.xl`, `.xs` ajoutées à `*directive-names*`
- Parsing multi-opérandes étendu (MVN/MVP) en parallèle des BBR/BBS R65C02

**Tests 65816** — `tests/test-65816.lisp` : 104 tests répartis en 12 groupes :
compatibilité 6502, instructions implied, absolute long, JSL/JML,
dp-indirect-long, JMP indirect long, stack-relative, BRL, REP/SEP,
directives de mode + immédiat 16-bit, block move, PEA, forward references,
erreurs, programme SNES minimal.

### Changed

**`src/core/version.lisp`** — version incrémentée : `0.1.3` → `0.2.0`

**Scripts de test** — `run-tests.sh`, `run-tests-clisp.lisp`, `run-tests-ecl.lisp`
chargent désormais `src/backend/65816.lisp` et `tests/test-65816.lisp`.

### Tests

| Suite | 0.1.3 | 0.2.0 |
|---|---|---|
| symbol-table | 65 | 65 |
| expression | 129 | 129 |
| lexer | 119 | 119 |
| parser | 84 | 84 |
| macros | 27 | 27 |
| conditionnel | 27 | 27 |
| lasm | 58 | 58 |
| 6502 | 82 | 82 |
| 65c02 | 41 | 41 |
| r65c02 | 117 | 117 |
| 45gs02 | 80 | 80 |
| **65816** | — | **104** |
| **TOTAL** | **829** | **933** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+.

---

## [0.1.3] — 2026-03-20

### Added

**Registre extensible de backends** — nouveau module `src/core/backends.lisp`
(package `cl-asm/backends`) centralisant la déclaration des backends d'assemblage.
Chaque backend s'enregistre via `register-backend` en fin de son fichier source.
Le script CLI n'a plus besoin d'être modifié pour ajouter une nouvelle architecture.

- `register-backend keyword aliases package function desc-fr desc-en` — enregistre un backend
- `find-backend-by-alias alias` — résolution CLI string → keyword
- `all-backends` — liste ordonnée des backends enregistrés

### Changed

**`cl-asm-script.lisp` refactorisé** — plus aucun `ecase` codé en dur :

- `assemble-source` délègue via le registre (`all-backends` + lookup par keyword)
- Parsing `--target` utilise `find-backend-by-alias` (insensible à la casse)
- `print-usage` génère dynamiquement la liste des alias CLI
- `detect-target` itère sur `all-backends` au lieu de chercher des chaînes fixes
- Alias supplémentaires : `mos6502`, `c64`, `mega65`, `65c02`, `commander-x16`, `rockwell`

**`src/backend/45gs02.lisp`** — ajout de `assemble-file-45gs02` (manquante) et
de son export, pour uniformiser l'interface avec les autres backends.

**Scripts de test** — `run-tests.sh`, `run-tests-clisp.lisp`, `run-tests-ecl.lisp`
chargent désormais `src/core/backends.lisp` après `version.lisp`.

### Tests

| Suite | 0.1.2 | 0.1.3 |
|---|---|---|
| Toutes suites | 829 | 829 |
| **TOTAL** | **829** | **829** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+.

---

## [0.1.2] — 2026-03-17

### Added

**Backend Rockwell R65C02** — nouveau backend `src/backend/r65c02.lisp`
supportant les 32 instructions spécifiques au R65C02 (variante Rockwell du WDC 65C02) :

- `RMB0`..`RMB7` — Reset Memory Bit (opcode `$n7`, 2 octets, zero-page)
- `SMB0`..`SMB7` — Set Memory Bit (opcode `$n7 + $80`, 2 octets, zero-page)
- `BBR0`..`BBR7` — Branch on Bit Reset (opcode `$nF`, 3 octets, zero-page + relatif)
- `BBS0`..`BBS7` — Branch on Bit Set (opcode `$nF + $80`, 3 octets, zero-page + relatif)

Le backend hérite de `cl-asm/backend.65c02` (toutes les instructions 65C02
sont disponibles). Les instructions `BBRn`/`BBSn` prennent deux opérandes
séparés par une virgule : adresse zero-page et étiquette de branche.

**Helpers Rockwell dans le parser** — nouvelles fonctions exportées depuis
`cl-asm/parser` : `rockwell-mnemonic-p`, `rockwell-bit-number`,
`rockwell-opcode`, `rockwell-two-operands-p`.

**Tests R65C02** — `tests/test-r65c02.lisp` : 10 suites couvrant
le mapping opcode complet, le calcul d'offset relatif des branches,
les forward references et la combinaison des instructions.

### Modifié

**Framework de régression — config par famille d'architectures** —
`config.sh` renommé en `config-6502.sh` et étendu avec `config_handles_target()`
pour déclarer les cibles qu'il gère (`c64`, `mega65`, `x16`).
`run-regression.sh` charge désormais dynamiquement le bon `config-<arch>.sh`
selon la cible traitée, via `find_config_for_target()` / `load_config_for_target()`.
Chaque cible charge son propre config indépendamment dans les boucles `--update`
et test. L'en-tête de section affiche le compilateur actif (`=== c64 (acme) ===`).
Ajouter le support d'une nouvelle architecture (Z80, 68000…) ne nécessite
plus de modifier `run-regression.sh` — il suffit de créer `config-z80.sh`
avec `ref_assemble()`, `ref_check_available()` et `config_handles_target()`.
`README.md` mis à jour en conséquence.

---

## [0.1.1] — 2026-03-15

Patch de corrections et outillage de régression.

### Corrigé

**Bug `define-label` vs constantes** — `define-label` déclenchait une erreur
"Label défini plusieurs fois" quand un label portait le même nom qu'une
constante déjà définie (ex: `COLOR = $D800` puis `color_lp:`). La table des
symboles distingue maintenant les kinds `:label`, `:constant` et `:equate` —
un label ne peut pas entrer en conflit avec une constante, et vice versa.

**Script `cl-asm`** — correction du mode de sélection de la cible :
remplacement des variables booléennes `USE_45GS02`/`USE_X16` par un
`ecase target` Lisp dans un fichier temporaire, éliminant les problèmes
de quoting shell dans `--eval`.

**Lexer** — les octets nuls et les caractères non-ASCII sont ignorés
silencieusement hors des commentaires, évitant les erreurs "Caractère
inattendu : #\\Nul" sur les fichiers convertis depuis ACME.

**`acme2clasm`** — `!cpu m65` converti en `; target: 45gs02` (directive
sémantique) au lieu d'un simple commentaire. `!cpu 65c02` converti en
`; target: x16`. Normalisation NFD des accents dans les commentaires
(latin-1 → ASCII). Suppression des octets nuls dans le flux de lecture.

### Ajouté

**Backend 65C02 (Commander X16)** — 41 nouvelles instructions encodées :
`BRA`, `STZ`, `TRB`, `TSB`, `PHX`/`PLX`/`PHY`/`PLY`, `INC A`/`DEC A`,
mode `:zero-page-indirect` `($nn)`, `JMP ($addr,X)` indirect absolu indexé,
modes étendus pour `BIT`, `ADC`/`SBC`/`AND`/`ORA`/`EOR`/`CMP`/`LDA`/`STA`.

**`encode-instruction`** — accepte `&key table resolve-fn` pour permettre
aux backends dérivés (65C02, 45GS02) de déléguer l'encodage complet sans
dupliquer la logique de branches relatives et forward-references.

**Versioning** — module `cl-asm/version` avec `+version+`, `+version-major+`,
`+version-minor+`, `+version-patch+` et `(version-string)`.

**Framework de régression** — `tests/regression/` avec :
- `run-regression.sh` — modes `--update`, `--clear`, `--verbose`, filtre
  par architecture et par fichier
- `config.sh` — compilateur de référence configurable : ACME et ca65/ld65
  avec conversion automatique de syntaxe (`clasm_to_acme`, `clasm_to_ca65`)
- `c64/*.asm` — 7 fichiers de test C64 couvrant instructions de base,
  modes d'adressage, branches, directives, macros, programme complet
- `.acme-skip` / `.ca65-skip` — exclusions documentées par compilateur

**Exemples X16** — `x16-hello.asm`, `x16-minimal.asm`, `x16-debug.asm`
fonctionnels sous l'émulateur X16, via `CHROUT` (`$FFD2`).

### Tests

| Suite | 0.1.0 | 0.1.1 | 0.1.2 | 0.1.3 |
|---|---|---|---|---|
| symbol-table | 59 | 61 | 65 | 65 |
| expression | — | — | 129 | 129 |
| lexer | — | — | 119 | 119 |
| parser | — | — | 84 | 84 |
| macros | — | — | 27 | 27 |
| conditionnel | — | — | 27 | 27 |
| lasm | — | — | 58 | 58 |
| 6502 | — | — | 82 | 82 |
| 65c02 | — | 41 | 41 | 41 |
| r65c02 | — | — | 117 | 117 |
| 45gs02 | — | — | 80 | 80 |
| **TOTAL** | **647** | **706** | **829** | **829** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+.

**Régression binaire** : 5/5 OK vs ACME, 6/6 OK vs ca65.

### Limitations levées

- Les caractères non-ASCII dans les commentaires ne bloquent plus le lexer.
- `acme2clasm` gère correctement `!cpu m65` et les fichiers encodés en Latin-1.

---
- Z80 backend (Amstrad CPC, MSX, ZX Spectrum)
- 68000 backend (Amiga, Atari ST)
- Direct VERA access for X16
- Real hardware testing (C64, Mega65, X16)

---

## [0.1.0] — 2026-03-15

First functional release. The assembler is usable from the command line
and from a Common Lisp REPL. Tested on SBCL 2.6.2, CLISP 2.49.95+ and
SLIME on Linux.

### Added

**Infrastructure**
- IR (Intermediate Representation) — pivot between frontends and backends
- Expression evaluator — 28 operators, forward-references, 2 passes
- Symbol table — labels, constants, equates, local scopes, numeric labels
  (ca65 style `1:` `1-` `1+`), relocations
- ASDF — incremental loading, `(asdf:test-system "cl-asm")`
- Quicklisp — `(ql:quickload "cl-asm")`
- Versioning — `cl-asm/version:+version+` → `"0.1.0"`

**Classic frontend (ca65-like syntax)**
- Lexer — literals `$FF` `%1010` `0xFF` `'A'`, labels, operators
- Parser — all 6502 and 45GS02 addressing modes, expressions
- Text macros — `.macro`/`.endmacro`, parameters, unique local labels
  per invocation (`__` prefix)
- Conditional assembly — `.if`/`.else`/`.endif`, nesting, constants
  evaluated at parse time (no forward-references)

**Native Lisp frontend (.lasm)**
- Source files = valid Common Lisp executed in `cl-asm/lasm`
- Full power of CL available: `dotimes`, `loop`, `defun`…
- Addressing mode convention: no keyword = inferred, keyword = explicit
  (`:imm`, `:x`, `:y`, `:z`, `:ind`, `:ix`, `:iy`, `:abs`, `:zp`, `:a`)
- `(target :45gs02)` directive for automatic target detection

**6502 backend**
- 56 mnemonics, all addressing modes
- Automatic zero-page vs absolute selection
- 2-pass assembly with forward-reference resolution
- `assemble`, `assemble-string`, `assemble-file`

**45GS02 backend (Mega65)**
- 6502 superset: Z, B, Q 32-bit registers
- Instructions: `LDZ`/`STZ`, `INZ`/`DEZ`, `TAZ`/`TZA`, `TAB`/`TBA`,
  `LDQ`/`STQ`, Q ALU, 16-bit long branches (`LBNE`…)
- Modes: `($nn),Z`, `$nnnn,Z`, `[$nn]`, `[$nn],Z`, `($nn,SP),Y`
- Prefixes `$42`, `$42 $42`, `$EA`

**65C02 backend (Commander X16)**
- 6502 superset: WDC new instructions
- `BRA` (unconditional branch), `STZ`, `TRB`, `TSB`
- `PHX`/`PLX`/`PHY`/`PLY`, `INC A`/`DEC A`
- `($nn)` zero-page indirect without index
- `JMP ($addr,X)` absolute indexed indirect
- Extended modes for `BIT`, `ADC`/`SBC`/`AND`/`ORA`/`EOR`/`CMP`

**Emitters**
- BIN — raw binary, no header
- PRG — C64/Mega65 format: 2-byte LE header + binary
- Annotated listing — address | hex | source

**Tooling**
- `./cl-asm` — command-line script with automatic target detection
  (`; target: 45gs02`, `; target: x16`, `(target :45gs02)`)
- `./acme2clasm` — ACME to cl-asm converter
  (`!addr`, `!byte`/`!8`, `!word`/`!16`, `!pet`, `!fill`, `!align`,
  `!macro`, `!if`, `!source`, `!cpu m65`→`; target: 45gs02`)

**Examples**
- `examples/c64-raster.asm` — C64 raster bar with macros and `.if DEBUG`
- `examples/mega65-hello.lasm` — Mega65 hello world in .lasm syntax
- `examples/mega65-minimal.lasm` — minimal Mega65 program
- `examples/x16-hello.asm` — X16 hello world via CHROUT
- `examples/x16-minimal.asm` — minimal X16 program via CHROUT
- `examples/x16-debug.asm` — X16 diagnostic program (BRK)

### Tests

| Suite | Tests |
|---|---|
| symbol-table | 59 |
| expression | 129 |
| lexer | 119 |
| parser | 84 |
| macros | 27 |
| conditional | 27 |
| lasm | 58 |
| 6502 | 82 |
| 65c02 | 41 |
| 45gs02 | 80 |
| **TOTAL** | **706** |

0 failures, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, SLIME.

### Known Limitations

- Conditional assembly: forward-references are not supported in `.if`
  expressions — only symbols defined *before* the `.if` are visible.
- Text macros: arguments are single tokens (no multi-token expressions
  as parameters).
- `.lasm` frontend: `(target :45gs02)` is a no-op at runtime — used
  only by the `cl-asm` script.
- Direct VERA access (X16): not tested on real hardware; example programs
  use CHROUT for safety.

### Not yet supported

Z80, 68000, ARM32, ARM64, x86-64 — planned for future releases.

---
