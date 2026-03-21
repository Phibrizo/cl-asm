# Changelog cl-asm

All notable changes to this project are documented here.
Format inspired by [Keep a Changelog](https://keepachangelog.com/).

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
