# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Contraintes

- Toujours répondre en français.
- Ne jamais lancer de commandes système affectant l'extérieur du projet (installation de paquets, modifications globales, etc.) sans confirmation explicite de l'utilisateur.

## Project Overview

cl-asm is a modular, multi-architecture assembler written in Common Lisp (ASDF 3.x). Supported targets: 6502, MOS 6510 (C64), 65C02, R65C02 (Rockwell), 45GS02 (Mega65), WDC 65816 (SNES/Apple IIgs), Z80 (ZX Spectrum/MSX/CPC), M68K (Amiga/Atari ST/Mac), Intel 8080 (CP/M/Altair), Intel 8086/8088 (IBM PC/MS-DOS). Two input frontends: classic ca65-like `.asm` syntax and native Lisp `.lasm` syntax.

## Build & Test Commands

**Run all tests (SBCL):**
```bash
./run-tests.sh
```

**Run all tests (other implementations):**
```bash
./run-tests-clisp.sh   # CLISP
./run-tests-ecl.sh     # ECL
```

**Run tests from REPL:**
```lisp
(asdf:test-system "cl-asm")
;; or
(ql:quickload "cl-asm/tests")
(cl-asm/test:run-all-tests)
```

**Load system manually (without ASDF):**
```lisp
(load "bootstrap.lisp")
```

**Assemble a file:**
```bash
./cl-asm programme.asm                          # 6502 → .prg
./cl-asm programme.asm -o out.bin --format bin  # raw binary
./cl-asm mega65.lasm --target 45gs02            # 45GS02
./cl-asm prog.asm --target x16                  # 65C02/Commander X16
```

**Clean FASL cache:**
```bash
find . -name "*.fasl" -delete
```

## Architecture

Three-layer pipeline:

```
Frontend (.asm/.lasm) → IR → Backend (target encoder) → Emitter (BIN/PRG/listing)
```

### Core (`src/core/`)

- **`ir.lisp`** — Intermediate Representation shared by all frontends and backends: `IR-PROGRAM`, `IR-SECTION`, `IR-INSTRUCTION`, `IR-LABEL`, `IR-DIRECTIVE`, `IR-OPERAND`, `SOURCE-LOC`, error conditions.
- **`backends.lisp`** — Extensible backend registry. New backends call `register-backend`; the CLI queries the registry dynamically (no hard-coded dispatch).
- **`expression.lisp`** — Prefix-tree expression evaluator: arithmetic, bitwise, shifts, lo/hi/bank extraction, comparisons. Supports forward references (returns unresolved in pass 1).
- **`symbol-table.lisp`** — Two-pass symbol table: labels (local/global/numeric), constants, equates. Call `begin-pass-2` between passes.

### Frontend (`src/frontend/`)

- **`classic-lexer.lisp`** / **`classic-parser.lisp`** — Tokenizer and recursive-descent parser for ca65-like `.asm` syntax. Supports macros (`.macro`/`.endmacro`) and conditional assembly (`.if`/`.endif`). Also supports: native ACME syntax (`!byte`/`!word`/`!fill`/`!pet` directives, `*=addr` org, `!to`/`!cpu` ignored); ca65 anonymous labels (`preprocess-anonymous-labels`); scoped `@`-labels (`preprocess-scoped-labels`); `.res N` as alias for `.fill N`. Extra directives: `.padto ADDR[,VAL]`, `.assertpc ADDR`, `.asciiz "str"`, `.pascalstr "str"`, `.defstruct`/`.field`/`.endstruct`, `.defenum`/`.val`/`.endenum`, `.incbin "file"[,offset[,count]]`, `.include "file"` (source include, resolved at parse time). Include implementation: `do-include` saves/restores the token stream, processes the included file in the same parse context (shared sections, macros, symtable); `*include-stack*` detects cycles; `*base-dir*` resolves relative paths.
- **`lasm.lisp`** — Native Lisp frontend: `.lasm` files are valid Common Lisp where mnemonics are functions. Addressing modes as keywords (`:imm`, `:x`, `:y`, `:z`, `:ind`, `:ix`, `:iy`, `:abs`, `:zp`, `:a`). Extra directives: `(pad-to addr [v])`, `(assert-pc addr)`, `(ascii-z "str")`, `(pascal-str "str")`, `(defstruct-asm name fields…)`, `(defenum name vals…)`, `(include-binary "file" [offset [count]])`, `(include-source "file")` (source include, same assembly context).

### Backend (`src/backend/`)

All backends implement two-pass assembly against the shared IR and symbol table.

- **`6502.lisp`** — Base 6502 encoder (56 mnemonics, 10 addressing modes).
- **`6510.lisp`** — MOS 6510 encoder (Commodore 64): extends 6502 with 14 stable illegal opcodes (LAX, SAX, SLO, RLA, SRE, RRA, DCP, ISC, ALR, ANC, ARR, AXS, LAS, KIL). Aliases: `"6510"` `"mos6510"` `"c64"`.
- **`65c02.lisp`** — Extends 6502 (BRA, STZ, PHX/PLY, etc.) for Commander X16/WDC.
- **`r65c02.lisp`** — Extends 65C02 with Rockwell bit manipulation (RMB/SMB/BBR/BBS).
- **`45gs02.lisp`** — Extends 6502 with Mega65 additions (Z/Q registers, long branches, 32-bit ops).
- **`65816.lisp`** — WDC 65816 encoder (SNES/Apple IIgs): 24-bit addressing, 16-bit M/X modes, JSL/JML, BRL, MVN/MVP, PEA. State M/X tracked across passes via `.al`/`.as`/`.xl`/`.xs` directives.
- **`z80.lisp`** — Zilog Z80 encoder (ZX Spectrum, MSX, CPC, ZX81): no-prefix + CB + DD + ED + FD + DD CB/FD CB prefixes. Activated via `cl-asm/parser:*z80-mode*` to avoid parser conflicts with 6502 mnemonics.
- **`m68k.lisp`** — Motorola 68000 encoder (Amiga, Atari ST, Mac 68k): EA field encoding (mode×8+reg), all addressing modes, MOVE/MOVEA/MOVEQ, ALU (ADD/SUB/AND/OR/EOR/CMP + immediate/quick variants), MUL/DIV, shifts (ASL/LSR/ROR/ROL/ASR/ROXL/ROXR), bit ops (BTST/BSET/BCLR/BCHG), branches (Bcc/DBcc), LEA/PEA, LINK/UNLK, EXG, EXT, ABCD/SBCD, TRAP. Big-endian encoding via `words->bytes`. Default origin `$0000`.
- **`i8080.lisp`** — Intel 8080 encoder (CP/M, Altair): full 8080 instruction set (~78 mnemonics). Registers B=0..A=7, pairs BC=0/DE=1/HL=2/SP=3, PUSH/POP use PSW=3. Instruction sizes: 1 byte (implied/register), 2 bytes (MVI/ALU-imm/IN/OUT), 3 bytes (LXI/LDA/STA/LHLD/SHLD/JMP/CALL/Jcc/Ccc). `*i8080-mode*` variable avoids parser conflicts with 6502. Aliases: `"i8080"` `"8080"` `"cpm"` `"altair"`.
- **`i8086.lisp`** — Intel 8086/8088 real-mode encoder (IBM PC, MS-DOS): MOV/XCHG/LEA/LDS/LES, ALU (ADD/SUB/AND/OR/XOR/CMP/ADC/SBB + imm/short-acc forms), INC/DEC, NEG/NOT/MUL/IMUL/DIV/IDIV, shifts/rotates ×1/CL/imm8, PUSH/POP reg/seg/imm, all Jcc rel8, LOOP family, JMP/CALL (near/far/short/reg/mem), RET/RETF/IRET, INT/INTO/BOUND, IN/OUT, ~30 1-byte implied instructions. ModRM encoding: all 8086 addressing modes `[BX+SI]`…`[BX]` + direct address + 16-bit displacement. `*i8086-mode*` variable avoids parser conflicts. Aliases: `"i8086"` `"8086"` `"8088"` `"i8088"` `"ibmpc"` `"msdos"` `"x86-16"`.

### Simulator (`src/simulator/`)

- **`6502.lisp`** — MOS 6502 CPU simulator: struct `cpu` (A/X/Y/PC/SP/P/mem/cycles), `make-cpu`/`reset-cpu`/`load-program`, `mem-read`/`mem-write`/`mem-read16`, flag helpers, `stack-push`/`stack-pull`, `step-cpu` (152 opcodes, full 6502 ISA), `run-cpu`.

### Disassembler registry (`src/core/disassemblers.lisp`)

- **`disassemblers.lisp`** — Extensible disassembler registry. New disassemblers call `register-disassembler`; lookup via `find-disassembler-by-keyword`. Same design as `backends.lisp`.

### Disassemblers (`src/disassembler/`)

- **`6502.lisp`** — 6502 disassembler: `disasm-one mem addr` → `(values mnemonic operand size)`, `disasm`, `disasm-string`, `print-disasm`. 151 official opcodes.
- **`45gs02.lisp`** — Mega65 (45GS02) disassembler: full prefix dispatcher (`$EA` indirect-32, `$42` long branches, `$42 $42` Q register, `$42 $42 $EA` Q indirect-32). Inherits 6502 table, adds all 45GS02-specific opcodes.
- **`65c02.lisp`** — WDC 65C02 / Commander X16 disassembler: flat table (no prefixes). New modes: `:zero-page-indirect` `($nn)`, `:indirect-absolute-x` `($nnnn,X)`. BRA, STZ, TRB, TSB, PHX/PLX/PHY/PLY, INC A/DEC A, extended BIT.

### Debug map (`src/core/debug-map.lisp`)

- **`debug-map`** — vector of 65536 entries (address → `source-loc`). Built optionally by `assemble` (`&key debug-map`). Consumed by the debugger to display source lines. Package `cl-asm/debug-map`.

### Debugger (`src/debugger/`)

- **`6502.lisp`** — Interactive step debugger. `make-debugger cpu &key debug-map` → session. `debugger-repl` REPL with commands: step/next/continue/b/d/lb/w/dw/lw/regs/mem/disasm/quit. `debugger-step`/`debugger-next`/`debugger-continue` return `:ok`/`:brk`/`:breakpoint`/`:watchpoint`/`:illegal`. Breakpoints: `set-breakpoint addr &key condition` (condition slot present for future conditional breakpoints). Watchpoints: `set-watchpoint addr &key kind` (`:read`/`:write`/`:rw`), wired to `cpu-watch-table`; `cpu-watchpoint` condition captured by `%step-one`; `debugger-last-watchpoint` stores `(addr kind)`. Source display: `show-current` reads source file via `source-cache` (hash filename → vector-of-lines), shows `; file:line | text` above disassembly when `source-loc-file` is non-nil. Conditional breakpoints in REPL: `b $ADDR <lisp-expr>` compiles `(lambda (cpu) <expr>)` via `eval`; `cpu` is bound to the CPU struct.

### Linker (`src/core/linker.lisp`, `src/core/linker-script.lisp`)

- **`linker.lisp`** — In-memory modular linker for the 6502 family. `link-unit` struct wraps a list of IR sections + target keyword. `link-unit-from-program name program target` constructs a unit from a parsed IR-PROGRAM. `link units &key origin` merges all sections into a shared symbol table, runs pass-1 then pass-2 via the registered backend functions → `(unsigned-byte 8)` vector. Registered backends: `:6502` / `:6510` / `:65c02` / `:45gs02`. Enables cross-file label references. Package `cl-asm/linker`.
- **`linker-script.lisp`** — Multi-segment linker script. `script-segment` struct (`:name`, `:at`, `:units`, `:fill`). `link-segments segments &key target` → list of `script-result` (`:name`, `:address`, `:bytes`): runs pass-1 over all segments with a shared symbol table (cross-segment JSR/branch/`.equ`), then pass-2 per segment. `segments->flat-binary results &key (fill #x00)` → `(values bytes base-address)`: assembles results into a contiguous vector, padding gaps with `fill`. Package `cl-asm/linker-script`.

### Conditions/Restarts (`src/core/restarts.lisp`)

- **`restarts.lisp`** — Restart names and convenience macros. Restart names exported: `use-value`, `use-zero`, `skip-instruction`, `clamp-value`. `with-asm-use-zero` wraps assembly, auto-resolving undefined labels to 0. `with-asm-skip-errors` ignores unknown mnemonics/unsupported modes (0 bytes emitted). Restarts are established in `symbol-table.lisp` (`%signal-undefined-label` — `use-value`, `use-zero`) and `6502.lisp` (`encode-instruction` — `skip-instruction`; `encode-relative` — `clamp-value`, `use-value`). Package `cl-asm/restarts`.

### Profiler/Tracer (`src/profiler/`)

- **`6502.lisp`** — Profiler and tracer for the 6502/6510 simulator. Package `cl-asm/profiler.6502`.
  - **Profiler**: `profiler` struct — two 65536-entry fixnum arrays (`hit-count`, `cycle-count`) + incremental `total-hits`/`total-cycles`. `make-profiler`, `profiler-reset profiler`, `profile-step cpu profiler` (uses `handler-bind` to record even on BRK/illegal before an outer `handler-case` unwinds), `run-with-profiler cpu profiler &key (max-steps 1000000)` → `(values cpu status)` with status `:brk`/`:illegal`/`:step-limit`/`:watchpoint`. `print-profile profiler &key (stream t) (top 20)` — sorted by hit count.
  - **Tracer**: `tracer` struct — circular ring buffer of `trace-entry` (PC, A, X, Y, SP, P, delta-cycles, mnemonic, operand). `make-tracer &key (max-size 1000)`, `tracer-reset tracer`, `tracer-count tracer` (entries in buffer), `tracer-total tracer` (total recorded), `trace-step cpu tracer`, `run-with-tracer cpu tracer &key (max-steps 1000000)`, `tracer-entries-in-order tracer &optional last` (chronological slice of last N entries), `print-trace tracer &key (stream t) (last 20)`.

### Dead code detector (`src/core/dead-code.lisp`, `src/dead-code/`)

- **`dead-code.lisp`** — Extensible dead code analyzer registry. BFS reachability analysis on the IR. `register-dead-code-analyzer target &key branch-mnemonics jump-mnemonics call-mnemonics return-mnemonics classify-fn target-operand-fn description`, `find-dead-code-analyzer target`, `all-dead-code-analyzers`, `analyze-dead-code sections target &key entry-points` → list of `dead-code-warning` (label + source-loc). Returns NIL for unregistered targets. `classify-fn`/`target-operand-fn` handle ambiguous mnemonics (e.g. Z80 `JR`/`JP`). Package `cl-asm/dead-code`.
- **`src/dead-code/6502.lisp`** — Tables for 6502 family: `:6502`, `:6510` (+KIL), `:65c02`/`:r65c02` (+BRA jump), `:45gs02` (+long branches/LBRA/JSQ/RTQ), `:65816` (+BRL/JML/JSL/RTL/COP).
- **`src/dead-code/z80.lisp`** — Z80 with `classify-fn`: 1-op `JR`/`JP` → `:jump`; 2-op → `:branch`; `JP (HL)/(IX)/(IY)` → `:return`; `RET` alone → `:return`, `RET cond` → `:normal`; `CALL` alone → `:call`, `CALL cond` → `:branch`.
- **`src/dead-code/m68k.lisp`** — M68K: Bcc/DBcc → branches; BRA/JMP → jumps; BSR/JSR → calls; RTS/RTR/RTE → returns.
- **`src/dead-code/i8080.lisp`** — Intel 8080: conditional JX/CX → branches; conditional RX → normal; JMP → jump; CALL → call; RET/HLT → returns.
- **`src/dead-code/i8086.lisp`** — Intel 8086: Jcc/LOOP → branches; JMP/JMPF → jumps; CALL/CALLF → calls; RET/RETF/IRET/HLT → returns.

### Optimizer (`src/core/optimizer.lisp`, `src/optimizer/`)

- **`optimizer.lisp`** — Extensible peephole optimizer registry. `register-peephole-optimizer target rules description`, `find-peephole-optimizer target`, `optimize-sections sections target` (called before pass-1). Each rule is a function `(nodes) → nil | (values replacement-list consumed-count)`. Package `cl-asm/optimizer`.
- **`src/optimizer/6502.lisp`** — Rules A (JMP→next-label) and B (JSR/RTS→JMP) for `:6502` and `:6510`. Exports `*rules-6502*`.
- **`src/optimizer/65c02.lisp`** — Rules A+B+C for `:65c02`; rules A+B only for `:45gs02` (STZ on 45GS02 means "Store Z register", not "Store Zero"). Rule C: `LDA #0 / STA :direct` → `STZ :direct` (nil or :x index-reg).

### Emitter registry (`src/core/emitters.lisp`)

- **`emitters.lisp`** — Extensible emitter registry. New formats call `register-emitter`; lookup via `find-emitter-by-keyword` / `find-emitter-by-alias`. Same design as `backends.lisp`. Each entry stores a lambda `(bytes path &key (origin 0))`. Package `cl-asm/emitters`.

### Emitters (`src/emit/`)

- **`output.lisp`** — `write-bin`, `write-prg` (adds 2-byte C64 load address header), `write-listing`. Registers `:bin` and `:prg` in the emitter registry.
- **`ihex.lisp`** — Intel HEX emitter: `:LLAAAATT...CC` records, 16 bytes/record, EOF `:00000001FF`. Registers `:ihex` (aliases `"ihex"` `"hex"` `"intel"`, extension `"hex"`). Package `cl-asm/emit.ihex`.
- **`srec.lisp`** — Motorola S-record emitter: S0 header, S1 data (16 bytes/record), S9 end. One's complement checksum. Registers `:srec` (aliases `"srec"` `"mot"` `"motorola"` `"srecord"`, extension `"srec"`). Package `cl-asm/emit.srec`.

**Listing annoté avec cycles CPU :** `emit-listing` / `write-listing` acceptent `&key target` (`:6502` `:6510` `:65c02` `:r65c02` `:45gs02`). Quand fourni, active :
- La correction de la taille des instructions via le désassembleur enregistré (bugfix : retournait 1 par défaut).
- L'affichage des cycles CPU en colonne droite : `Ncy` (fixe), `Ncy+` (+1 page-crossing), `Ncy*` (branche).

Tables exportées : `*cycles-6502*` (151 opcodes, valide aussi pour 6510), `*cycles-65c02*` (hérite du 6502, ajoute BRA/STZ/PHX/PLX/PHY/PLY/TSB/TRB/zero-page-indirect, JMP(ind)=6cy ; valide pour X16 et 45GS02 approximativement). Fallbacks : `:6510`→`:6502`, `:r65c02`→`:65c02`.

## Key Design Decisions

**Two-pass assembly:** Pass 1 traverses IR, registers labels, estimates sizes (forward refs allowed); `begin-pass-2` resets PC; pass 2 encodes with all symbols resolved.

**IR is frontend-agnostic:** Both `.asm` and `.lasm` frontends produce the same IR structures. Backends consume IR without knowing the source syntax.

**Extensible backend registry:** Adding a new architecture requires only creating a new file that calls `register-backend` — no changes to `cl-asm-script.lisp` or any dispatch table.

**File encoding:** All source files use UTF-8 with `; -*- coding: utf-8 -*-` header — required for SBCL and SLIME/SLY.

## Programmatic API

```lisp
;; Direct assemble from string
(cl-asm/backend.6502:assemble-string ".org $0801\n LDA #$00\n RTS")
;; → #(169 0 96)

;; Parse then assemble
(let* ((prog (cl-asm/parser:parse-string "LDA #$00\n RTS"))
       (bytes (cl-asm/backend.6502:assemble prog :origin #x0801)))
  (cl-asm/emit:write-prg bytes "/tmp/out.prg" :load-address #x0801))
```

## Test Structure

2966 tests across 33 suites in `tests/test-*.lisp`. Regression test reference binaries live in `tests/regression/{c64,mega65,x16}/` as `.ref.prg` files.

Expected output after all tests pass:
```
=== TOTAL        : 2919 OK, 0 KO sur 2919 tests
```

## Règle documentaire

**Après chaque ajout d'une nouvelle architecture**, mettre à jour tous les `.md` :
1. `README.md` et `README.fr.md` — titre, tableau de statut (nouveau backend + total), **matrice des fonctionnalités** (nouvelle ligne, toutes colonnes à ✗ sauf Assembleur), structure des fichiers, section CLI (alias), section programmatic usage (exemple), section syntax (modes spécifiques).
2. `CHANGELOG.md` et `CHANGELOG.fr.md` — nouvelle entrée `[X.Y.Z]` avec date, ajouts, modifications, tableau des tests.
3. `ARCHITECTURE.md` et `ARCHITECTURE.fr.md` — diagramme de couches (backends), tableau des packages, nouvelle section de module.
4. `CLAUDE.md` — section Backend, compteur de tests, section Upcoming Work.
5. `src/core/version.lisp` — incrémenter le numéro de version (minor pour un nouveau backend).

**Après chaque ajout d'une nouvelle fonctionnalité transversale** (désassembleur, simulateur, linker, optimiseur, profiler…), mettre à jour la **matrice des fonctionnalités** dans `README.md` et `README.fr.md` :
- Nouvelle colonne si la fonctionnalité est nouvelle.
- Mise à jour des cellules existantes (✗ → ✓ ou ~) pour les architectures concernées.
- Mettre à jour la note explicative sous le tableau si nécessaire (règles optimiseur, fallbacks cycles…).

## Z80-specific parser design

The Z80 parser shares the classic frontend with 6502. Some mnemonics are common (`INC`, `DEC`, `AND`, `ADC`, `SBC`, `BIT`, `NOP`…). To avoid conflicts:
- `cl-asm/parser:*z80-mode*` is a dynamic variable, NIL by default.
- `z80-mnemonic-p` returns T only when `*z80-mode*` is T.
- `assemble-string-z80`/`assemble-file-z80` bind `*z80-mode*` to T before parsing.
- Operand format: Z80 registers are `:direct "A"` (not `:register`); indirect is `:indirect "HL"` or `:indirect (:+ "IX" d)`.

## M68K-specific encoding

- **EA field** = `(mode << 3) | reg` — 6 bits embedded in the opcode word.
- **Mode 7 special cases**: abs.W = `#b111_000`, abs.L = `#b111_001`, `#(imm)` = `#b111_100`, `d(PC)` = `#b111_010`, `d(PC,Xi)` = `#b111_011`.
- **MOVE encoding** reverses destination EA bits: bits 11-9 = dst_reg, bits 8-6 = dst_mode (unlike all other instructions).
- **MOVE size field** (bits 13-12): `.B`→1, `.W`→3, `.L`→2 (unusual order).
- **ALU direction bit** (bit 8): 0 = EA→Dn, 1 = Dn→EA. Exception: EOR always dir=1, CMP always dir=0.
- **ADDQ bit 8=0** (`$5000`), **SUBQ bit 8=1** (`$5100`).
- **Shift type** encoded in bits 4-3: `(ash type 3)`.
- **Immediate byte** uses a single 16-bit word (value in low byte, not two words).
- **`words->bytes`** converts a list of 16-bit words to a big-endian byte vector.

## i8086-specific encoding

- **ModRM byte**: `[mod:2][reg:3][rm:3]`. mod=11 → register; mod=00/01/10 → memory with 0/8/16-bit displacement.
- **rm codes**: 0=[BX+SI], 1=[BX+DI], 2=[BP+SI], 3=[BP+DI], 4=[SI], 5=[DI], 6=[BP] (mod=00 → direct addr), 7=[BX].
- **BP alone**: `[BP]` must use mod=10 disp=0 (mod=00 rm=6 = direct address).
- **Register codes**: AX=0, CX=1, DX=2, BX=3, SP=4, BP=5, SI=6, DI=7 (non-alphabetical).
- **Segment registers**: ES=0, CS=1, SS=2, DS=3.
- **ALU opcode**: base = op_code×8; d-bit (bit 1) = direction, w-bit (bit 0) = word/byte.
- **Accumulator short form**: e.g. `ADD AX, imm16` → `0x05 + imm16` (2 bytes saved vs ModRM form).
- **Two-pass stability**: always use mod=10 (16-bit displacement) for any non-zero displacement, so pass-1 size = pass-2 size.
- **Jcc**: only rel8 in 8086 (no near form, always 2 bytes).
- **`parse-i8086-mem-ref`**: parses `[base+index+disp]` — tokens after `[` until `]`.
- **`*i8086-mode*`**: same pattern as `*z80-mode*` and `*i8080-mode*` — gates mnemonic recognition.

## Upcoming Work (TODO.md)

- ~~**clasm→acme/ca65 converter**: handle `label: .directive` lines~~ — done in v0.4.4.
- ~~**Intel 8080 backend**: CP/M, Altair support~~ — done in v0.5.0.
- ~~**CPU Simulator**: execute instructions step-by-step in a virtual memory environment~~ — done in v0.6.0 (6502 complete, 152 opcodes).
- ~~**Debugger (minimal scope)**: step/next/continue, breakpoints, register/memory/disasm display, REPL~~ — done in v0.7.0 (56 tests).
- ~~**Debugger (watchpoints)**: `:read`/`:write`/`:rw` watchpoints wired to simulator via `cpu-watch-table`~~ — done in v0.8.0 (68 tests).
- ~~**Debugger (source display)**: display actual source line text at breakpoint/watchpoint~~ — done in v0.9.0 (source-cache, `show-current` updated).
- ~~**Debugger (conditional breakpoints in REPL)**: expose `condition` slot in REPL syntax~~ — done in v0.9.0 (`b $ADDR <lisp-expr>` via `eval`).
- ~~**MOS 6510 backend**: stable illegal opcodes (LAX/SAX/SLO/RLA/SRE/RRA/DCP/ISC/ALR/ANC/ARR/AXS/LAS/KIL); `"c64"` alias moved from 6502 to 6510~~ — done in v0.10.0 (66 tests).
- ~~**Extensible disassembler registry** + **45GS02 disassembler** (prefix dispatcher) + **65C02 disassembler** + pluggable `disasm-fn` in debugger~~ — done in v0.11.0 (141 tests).
- ~~**In-memory modular linker** for 6502/6510/65C02/45GS02: `link-unit` struct, shared symbol table, cross-file label references~~ — done in v0.12.0 (26 tests).
- ~~**Peephole optimizer** (optional `&key optimize`): rule A (JMP→next label), rule B (JSR/RTS→JMP tail-call), rule C (LDA #0/STA→STZ, 65C02 only). Extensible registry. 45GS02 excluded from rule C (STZ = Store Z register there)~~ — done in v0.13.0 (28 tests).
- ~~**Conditions/restarts**: `use-value`, `use-zero` on `asm-undefined-label`; `skip-instruction` on `asm-unknown-mnemonic`/`asm-syntax-error`; `clamp-value`/`use-value` on `asm-range-error`. `with-asm-use-zero` and `with-asm-skip-errors` convenience macros~~ — done in v0.14.0 (14 tests).
- ~~**Intel 8086/8088 backend**: real-mode x86 encoder, ModRM byte, all addressing modes, full instruction set~~ — done in v0.15.0 (236 tests).
- ~~**Annotated listing with CPU cycles**: `--listing` CLI flag, `*cycles-6502*`/`*cycles-65c02*` tables, instruction size bugfix, `&key target` on `emit-listing`/`write-listing`~~ — done in v0.16.0 (40 tests).
- ~~**Intel HEX / Motorola S-record output formats**: extensible emitter registry (`src/core/emitters.lisp`), `src/emit/ihex.lisp`, `src/emit/srec.lisp`. CLI `--format ihex/srec`. Adding a new format = one file + `register-emitter`, no CLI changes~~ — done in v0.17.0 (32 tests).
- ~~**Linker script**: multi-segment placement at distinct addresses, shared symbol table for cross-segment references (JSR/branches/`.equ`), `segments->flat-binary` with fill-byte padding~~ — done in v0.18.0 (50 tests).
- ~~**Profiler/Tracer 6502/6510**: hit-count + cycle-count arrays, ring-buffer tracer, `profile-step`/`trace-step`, `run-with-profiler`/`run-with-tracer`, `print-profile`/`print-trace`, `tracer-entries-in-order`. Uses `handler-bind` for guaranteed recording on BRK/illegal~~ — done in v0.19.0 (78 tests).
- ~~**Full Lisp evaluation in `.lasm`**: `dotimes`/`loop`/`let`/`defmacro` etc. already work natively — `load-lasm-string` calls `(eval form)` in the `cl-asm/lasm` package. Validated by `test/lisp-dotimes` and `test/lisp-loop`.~~ — already done, not a new feature.
- ~~**`.include "file"` / `(include-source "file")`**: source file inclusion resolved at parse time, shared context (macros/labels/constants), relative paths, cycle detection~~ — done in v0.20.0 (13 tests).
- ~~**Dead code detector**: static CFG reachability (BFS) from declared entry points, extensible registry pattern, classify-fn/target-operand-fn for ambiguous mnemonics (Z80), 10 architectures registered~~ — done in v0.21.0 (47 tests).
- **Profiler/Tracer for 65C02/45GS02 (Commander X16, Mega65)**: requires extending the 6502 simulator to support 65C02 and 45GS02 ISAs first — deferred.
- **Declarative instruction tables** (`define-instruction` DSL): macro generating hash-table entries + compile-time consistency checks + automatic disassembler table derivation. Low priority — current format is already readable.
- **Incremental REPL assembly** (`with-asm` macro): build a program form-by-form in SLIME/SLY with `inspect-pc` feedback. Low complexity, ergonomic gain for interactive sessions.
