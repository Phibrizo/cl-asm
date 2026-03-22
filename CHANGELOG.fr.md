# Changelog cl-asm

Toutes les modifications notables de ce projet sont documentées ici.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/).

---

## [0.4.1] — 2026-03-22

### Ajouté

**Support natif de la syntaxe ACME** — le frontend classique de cl-asm accepte désormais
les fichiers source ACME directement sans conversion :
- `*=ADDR` — org style ACME (équivalent à `.org ADDR`)
- `!BYTE` / `!WORD` / `!FILL` — alias directs pour `.byte`/`.word`/`.fill`
- `!PET "str",n,...` — émission PETSCII : a-z → 0x41-0x5A (−0x20), A-Z → 0xC1-0xDA (+0x80) ; args numériques passés tels quels ; formes mixtes supportées (`!PET 147,"str",13,0`)
- `!to "file",cbm` — ignoré (nom de sortie géré par `--target`)
- `!cpu 65c02` — ignoré (CPU fixé par `--target`)

**Labels anonymes ca65** — `:` seul en début de ligne définit un label anonyme ;
`:-` / `:--` / `:---` référencent les 1er/2e/3e précédents ; `:+` / `:++` référencent
les 1er/2e suivants.

**Labels `@`-scopés ca65** — `@nom:` définit un label local à l'espace du dernier label
global ; `@nom` le référence. Deux routines peuvent chacune avoir leur propre `@loop:`
sans conflit.

**Directive `.res N`** — alias pour `.fill N` (réserve N octets, compatibilité ca65).

**`tests/regression/x16/06-bank-byte-operator.asm`** — test de régression pour `^` (opérateur octet de banque).

**`tests/regression/x16/07-anon-scoped-labels.asm`** — test de régression : labels anonymes, labels `@`-scopés, `.res`, `.byte "string"` inline, forward-ref immédiat.

**`tests/regression/x16/08-acme-directives.asm`** — test de régression : `!to`, `!cpu`, `*=`, `!BYTE`, `!PET` (conversion PETSCII vérifiée contre la sortie de l'assembleur ACME).

**Listes d'exclusion** — `tests/regression/x16/.ca65-skip` et `.acme-skip` pour gérer les fichiers spécifiques à une syntaxe.

### Corrigé

**Taille forward-ref immédiat en passe 1** — `ldx #<forward_label` estimait 3 octets (max pour LDX) au lieu de 2 en passe 1, décalant toutes les adresses suivantes. Désormais estime correctement 2 octets en mode immédiat quelle que soit la résolution.

**`ASL`/`LSR`/`ROL`/`ROR` sans opérande** — `:implied` bascule maintenant vers `:accumulator` lorsqu'aucune clause `:implied` n'existe (ex. `ASL` seul = `ASL A`).

**`.byte "string"` inline** — les arguments chaîne de `.byte` étaient incorrectement transmis à l'évaluateur d'expressions. Désormais traités séparément en passe 1 (estimation taille) et passe 2 (émission d'octets).

**`acme2clasm` — conversion `!PET`** — les formes à arguments mixtes (`"str",13,0` et `147,"str",0`) sont désormais correctement gérées ; conversion PETSCII appliquée (a-z → A-Z, A-Z → shifted).

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

### Ajouté

**Backend Motorola 68000** — nouveau fichier `src/backend/m68k.lisp`
(package `cl-asm/backend.m68k`) supportant le processeur M68K (Amiga, Atari ST, Mac 68k) :

- Alias CLI : `m68k`, `68000`, `68k`, `amiga`, `atari`, `mac68k`, `atarist`
- Origine par défaut `$0000`
- Jeu d'instructions complet M68K :
  - Transfert de données : `MOVE`, `MOVEA`, `MOVEQ`, `MOVEM`, `MOVEP`, `LEA`, `PEA`, `EXG`, `SWAP`
  - Arithmétique : `ADD`, `ADDI`, `ADDQ`, `ADDA`, `SUB`, `SUBI`, `SUBQ`, `SUBA`, `MULS`, `MULU`, `DIVS`, `DIVU`, `ABCD`, `SBCD`, `NBCD`
  - Logique : `AND`, `ANDI`, `OR`, `ORI`, `EOR`, `EORI`, `NOT`
  - Comparaison : `CMP`, `CMPI`, `CMPA`, `CMPM`, `TST`
  - Décalages : `ASL`, `ASR`, `LSL`, `LSR`, `ROL`, `ROR`, `ROXL`, `ROXR` (immédiat, registre, mémoire)
  - Manipulation de bits : `BTST`, `BSET`, `BCLR`, `BCHG`
  - Unaires : `CLR`, `NEG`, `NEGX`, `EXT`, `EXTB`
  - Branchements/sauts : `BRA`, `BSR`, `Bcc` (14 conditions), `DBcc`, `JMP`, `JSR`, `RTS`, `RTR`, `RTE`
  - Système : `TRAP`, `TRAPV`, `LINK`, `UNLK`, `NOP`, `STOP`, `RESET`, `ILLEGAL`, `CHK`
  - Tous les modes d'adressage : Dn, An, (An), (An)+, -(An), d(An), d(An,Xi), abs.W, abs.L, d(PC), d(PC,Xi), #imm
- Encodage big-endian via `words->bytes`

**Tests parser M68K** — `tests/test-m68k-parser.lisp` : 85 tests couvrant le parsing des opérandes M68K, modes EA, suffixes de taille, syntaxe des registres.

**Tests backend M68K** — `tests/test-m68k.lisp` : 139 tests répartis en 17 groupes :
implied, MOVE, MOVEA, MOVEQ, ADD/ADDI/ADDQ/ADDA, SUB/SUBI/SUBQ/SUBA,
AND/ANDI, OR/ORI, EOR/EORI, CMP/CMPI/CMPA, MULDIV, décalages, unaires (CLR/NEG/etc.),
EXT/SWAP, JMP/JSR/LEA, branchements/DBcc, divers (LINK/UNLK/TRAP/EXG/BCD), bit ops,
labels, modes d'adressage.

### Modifié

**`src/core/version.lisp`** — version incrémentée : `0.3.0` → `0.4.0`

**Scripts de test** — `run-tests.sh`, `run-tests-clisp.lisp`, `run-tests-ecl.lisp`
chargent désormais `src/backend/m68k.lisp`, `tests/test-m68k-parser.lisp` et `tests/test-m68k.lisp`.

**`tests/run-tests.lisp`** — ajout de `run-suite cl-asm/test.m68k-parser` et `run-suite cl-asm/test.m68k` ; nouvelle section « Parsers architectures » dans le bilan.

### Tests

| Suite | 0.3.0 | 0.4.0 |
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
| 65816 | 104 | 104 |
| z80 | 191 | 191 |
| **m68k-parser** | — | **85** |
| **m68k** | — | **139** |
| **TOTAL** | **1124** | **1348** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.3.0] — 2026-03-21

### Ajouté

**Backend Zilog Z80** — nouveau fichier `src/backend/z80.lisp`
(package `cl-asm/backend.z80`) supportant le processeur Z80 (ZX Spectrum, MSX, CPC, ZX81) :

- Alias CLI : `z80`, `z80cpu`, `zx80`, `zx81`, `zxspectrum`, `spectrum`, `cpc`, `msx`
- Origine par défaut `$0000`
- Jeu d'instructions complet Z80 :
  - Instructions implied, LD complet (44 formes), ALU (ADD/ADC/SUB/SBC/AND/OR/XOR/CP)
  - INC/DEC registres 8/16 bits et indirects
  - PUSH/POP BC/DE/HL/AF/IX/IY
  - EX DE,HL / EX (SP),HL/IX/IY / EXX
  - Rotations/shifts CB : RLC/RRC/RL/RR/SLA/SRA/SRL/SLL
  - BIT/SET/RES (CB prefix) + formes (IX+d)/(IY+d) (DD CB/FD CB)
  - JP/JR conditionnel et inconditionnel, CALL/RET conditionnel
  - DJNZ (branche relative avec décrément B)
  - IN r,(C) / IN A,(n) / OUT (C),r / OUT (n),A
  - Instructions étendues ED : NEG, RETN, RETI, RLD, RRD, IM 0/1/2
  - Opérations sur blocs : LDI/LDIR/LDD/LDDR/CPI/CPIR/CPD/CPDR/INI/INIR/IND/INDR/OUTI/OTIR/OUTD/OTDR
  - RST $00-$38

**Gestion des conflits de mnémoniques** — variable `cl-asm/parser:*z80-mode*` :
  - Certains mnémoniques Z80 (`INC`, `DEC`, `AND`, `BIT`, `ADC`…) existent aussi en 6502.
  - `*z80-mode*` est NIL par défaut ; mis à T par `assemble-string-z80` / `assemble-file-z80` pendant le parsing.
  - Évite tout conflit de parsing entre backends sans modifier le parser 6502.

**Tests Z80** — `tests/test-z80.lisp` : 191 tests répartis en 19 groupes :
instructions implied, LD r/r' et n, LD indirect, LD 16 bits, LD mémoire,
PUSH/POP, INC/DEC, ALU, rotations CB, BIT/SET/RES, JP/JR/CALL/RET/DJNZ,
EX/EXX, IN/OUT, ADD IX/IY, divers (IM/blocs), directives, forward references,
programme ZX Spectrum minimal, erreurs attendues.

### Modifié

**`src/core/version.lisp`** — version incrémentée : `0.2.0` → `0.3.0`

**`src/frontend/classic-parser.lisp`** — ajout du dispatch Z80 dans `parse-line`
et des helpers : `*z80-mode*`, `*z80-mnemonics*`, `z80-mnemonic-p`,
`z80-comma-is-6502-index-p`, `parse-z80-operand-raw`, `parse-z80-operands`.

**Scripts de test** — `run-tests.sh`, `run-tests-clisp.lisp`, `run-tests-ecl.lisp`
chargent désormais `src/backend/z80.lisp` et `tests/test-z80.lisp`.

### Tests

| Suite | 0.2.0 | 0.3.0 |
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
| 65816 | 104 | 104 |
| **z80** | — | **191** |
| **TOTAL** | **933** | **1124** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.2.0] — 2026-03-20

### Ajouté

**Backend WDC 65816** — nouveau fichier `src/backend/65816.lisp`
(package `cl-asm/backend.65816`) supportant le processeur WDC 65816 (SNES, Apple IIgs) :

- Origine par défaut `$8000` (SNES LoROM bank 0)
- Alias CLI : `65816`, `wdc65816`, `snes`, `apple2gs`
- 20+ modes d'adressage, dont :
  - `:absolute-long` / `:absolute-long-x` — adresses 24 bits (`$xxxxxx`)
  - `:dp-indirect-long` / `:dp-indirect-long-y` — `[$nn]`, `[$nn],Y`
  - `:stack-relative` / `:sr-indirect-y` — `$nn,S`, `($nn,S),Y`
  - `:relative-long` — branches 16 bits signées (BRL, PER)
  - `:block-move` — deux opérandes banque (MVN, MVP)
- **Accumulateur et index 16 bits** — immédiat variable selon les flags M/X :
  - `.al`/`.as` — bascule l'accumulateur entre 16 bits et 8 bits
  - `.xl`/`.xs` — bascule les index X/Y entre 16 bits et 8 bits
  - `REP`/`SEP` — instructions pour modifier les flags en dynamique
- `JSL`/`JML` — saut long 24 bits (4 et 3 octets)
- `BRL`/`PER` — branche longue / push effective relative address
- `MVN`/`MVP` — block move (deux opérandes banque séparés par une virgule)
- `PEA` — push effective address (toujours 16 bits)
- Toutes les instructions 6502 de base héritées

**Parser étendu** — `src/frontend/classic-parser.lisp` :
- Directives `.al`, `.as`, `.xl`, `.xs` ajoutées à `*directive-names*`
- Parsing multi-opérandes étendu (MVN/MVP) en parallèle des BBR/BBS R65C02

**Tests 65816** — `tests/test-65816.lisp` : 104 tests répartis en 12 groupes :
compatibilité 6502, instructions implied, absolute long, JSL/JML,
dp-indirect-long, JMP indirect long, stack-relative, BRL, REP/SEP,
directives de mode + immédiat 16 bits, block move, PEA, forward references,
erreurs, programme SNES minimal.

### Modifié

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

### Ajouté

**Registre extensible de backends** — nouveau module `src/core/backends.lisp`
(package `cl-asm/backends`) centralisant la déclaration des backends d'assemblage.
Chaque backend s'enregistre via `register-backend` en fin de son fichier source.
Ajouter une nouvelle architecture ne nécessite plus de modifier le script CLI.

- `register-backend keyword aliases package function desc-fr desc-en`
- `find-backend-by-alias alias` — résolution CLI string → keyword
- `all-backends` — liste ordonnée des backends enregistrés

### Modifié

**`cl-asm-script.lisp` refactorisé** — plus aucun `ecase` codé en dur :

- `assemble-source` délègue via le registre
- Parsing `--target` utilise `find-backend-by-alias` (insensible à la casse)
- `print-usage` génère dynamiquement la liste des alias CLI
- `detect-target` itère sur `all-backends`
- Alias supplémentaires : `mos6502`, `c64`, `mega65`, `65c02`, `commander-x16`, `rockwell`

**`src/backend/45gs02.lisp`** — ajout de `assemble-file-45gs02` (manquante)
et de son export.

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

### Ajouté

**Backend Rockwell R65C02** — nouveau backend `src/backend/r65c02.lisp`
supportant les 32 instructions spécifiques au R65C02 (variante Rockwell du WDC 65C02) :

- `RMB0`..`RMB7` — Reset Memory Bit (opcode `$n7`, 2 octets, zero-page)
- `SMB0`..`SMB7` — Set Memory Bit (opcode `$n7 + $80`, 2 octets, zero-page)
- `BBR0`..`BBR7` — Branch on Bit Reset (opcode `$nF`, 3 octets, zero-page + relatif)
- `BBS0`..`BBS7` — Branch on Bit Set (opcode `$nF + $80`, 3 octets, zero-page + relatif)

Le backend hérite de `cl-asm/backend.65c02`. Les instructions `BBRn`/`BBSn`
prennent deux opérandes séparés par une virgule : adresse zero-page et étiquette.

**Helpers Rockwell dans le parser** — nouvelles fonctions exportées depuis
`cl-asm/parser` : `rockwell-mnemonic-p`, `rockwell-bit-number`,
`rockwell-opcode`, `rockwell-two-operands-p`.

**Tests R65C02** — `tests/test-r65c02.lisp` : 10 suites de tests.

---

## [0.1.1] — 2026-03-15

Patch de corrections et outillage de régression.

### Corrigé

**Bug `define-label` vs constantes** — `define-label` déclenchait une erreur
"Label défini plusieurs fois" quand un label portait le même nom qu'une
constante déjà définie (ex : `COLOR = $D800` puis `color_lp:`). La table des
symboles distingue maintenant les kinds `:label`, `:constant` et `:equate`.

**Script `cl-asm`** — correction de la sélection de cible : remplacement des
variables booléennes `USE_45GS02`/`USE_X16` par un `ecase target` Lisp dans
un fichier temporaire, éliminant les problèmes de quoting shell dans `--eval`.

**Lexer** — octets nuls et caractères non-ASCII ignorés silencieusement hors
commentaires. Élimine les erreurs "Caractère inattendu : #\\Nul".

**`acme2clasm`** — `!cpu m65` → `; target: 45gs02`, `!cpu 65c02` →
`; target: x16`. Normalisation NFD des accents (Latin-1 → ASCII). Suppression
des octets nuls à la lecture.

### Ajouté

**Backend 65C02 (Commander X16)** — `BRA`, `STZ`, `TRB`, `TSB`,
`PHX`/`PLX`/`PHY`/`PLY`, `INC A`/`DEC A`, mode `:zero-page-indirect`,
`JMP ($addr,X)`, modes étendus pour `BIT` et les instructions ALU.

**`encode-instruction`** — paramètres `&key table resolve-fn` pour la
délégation propre entre backends.

**Versioning** — module `cl-asm/version` (`+version+`, `+version-patch+`…).

**Framework de régression** — `tests/regression/` avec :
- `run-regression.sh` — modes `--update`, `--clear`, `--verbose`
- `config.sh` — ACME et ca65/ld65, conversion automatique de syntaxe
- `c64/*.asm` — 7 fichiers de test C64
- `.acme-skip` / `.ca65-skip` — exclusions documentées

**Exemples X16** — `x16-hello.asm`, `x16-minimal.asm`, `x16-debug.asm`
fonctionnels sous émulateur, via `CHROUT`.

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

**Régression binaire** : 5/5 OK vs ACME, 6/6 OK vs ca65.

---

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
`README.md` du dossier de régression mis à jour en conséquence.

---

---

## [0.1.0] — 2026-03-15

Première version fonctionnelle. L'assembleur est utilisable en ligne de
commande et depuis un REPL Common Lisp. Testé sous SBCL 2.6.2, CLISP
2.49.95+ et SLIME sur Linux.

### Ajouté

**Infrastructure**
- IR (Représentation Intermédiaire) — pivot entre frontends et backends
- Évaluateur d'expressions — 28 opérateurs, forward-references, 2 passes
- Table des symboles — labels, constantes, équates, portées locales,
  labels numériques (style `1:` `1-` `1+`), relocations
- ASDF — chargement incrémental, `(asdf:test-system "cl-asm")`
- Quicklisp — `(ql:quickload "cl-asm")`
- Versioning — `cl-asm/version:+version+` → `"0.1.0"`

**Frontend classique (syntaxe ca65-like)**
- Lexer — littéraux `$FF` `%1010` `0xFF` `'A'`, labels, opérateurs
- Parser — tous les modes d'adressage 6502 et 45GS02, expressions
- Macros textuelles — `.macro`/`.endmacro`, paramètres, labels locaux
  uniques par invocation (préfixe `__`)
- Assemblage conditionnel — `.if`/`.else`/`.endif`, imbrication,
  constantes évaluées au parsing (pas de forward-references)

**Frontend .lasm (Lisp natif)**
- Fichiers source = Common Lisp valide exécuté dans `cl-asm/lasm`
- Toute la puissance de CL disponible : `dotimes`, `loop`, `defun`…
- Convention de modes : sans keyword = déduit, avec keyword = explicite
  (`:imm`, `:x`, `:y`, `:z`, `:ind`, `:ix`, `:iy`, `:abs`, `:zp`, `:a`)
- Directive `(target :45gs02)` pour la détection automatique de cible

**Backend 6502**
- 56 mnémoniques, tous les modes d'adressage
- Sélection automatique zero-page vs absolu
- 2 passes avec résolution des forward-references
- `assemble`, `assemble-string`, `assemble-file`

**Backend 45GS02 (Mega65)**
- Superset 6502 : registres Z, B, Q 32 bits
- Instructions : `LDZ`/`STZ`, `INZ`/`DEZ`, `TAZ`/`TZA`, `TAB`/`TBA`,
  `LDQ`/`STQ`, ALU Q, branches longues 16 bits (`LBNE`…)
- Modes : `($nn),Z`, `$nnnn,Z`, `[$nn]`, `[$nn],Z`, `($nn,SP),Y`
- Préfixes `$42`, `$42 $42`, `$EA`

**Backend 65C02 (Commander X16)**
- Superset 6502 : nouvelles instructions WDC
- `BRA` (branche inconditionnelle), `STZ`, `TRB`, `TSB`
- `PHX`/`PLX`/`PHY`/`PLY`, `INC A`/`DEC A`
- Mode `($nn)` indirect ZP sans index
- `JMP ($addr,X)` indirect absolu indexé X
- Modes étendus pour `BIT`, `ADC`/`SBC`/`AND`/`ORA`/`EOR`/`CMP`

**Émetteurs**
- BIN — binaire brut sans header
- PRG — format C64/Mega65 : 2 octets header LE + binaire
- Listing annoté — adresse | hex | source

**Outillage**
- `./cl-asm` — script ligne de commande avec détection automatique
  de cible (`; target: 45gs02`, `; target: x16`, `(target :45gs02)`)
- `./acme2clasm` — convertisseur ACME → cl-asm
  (`!addr`, `!byte`/`!8`, `!word`/`!16`, `!pet`, `!fill`, `!align`,
  `!macro`, `!if`, `!source`, `!cpu m65`→`; target: 45gs02`)

**Exemples**
- `examples/c64-raster.asm` — raster bar C64 avec macros et `.if DEBUG`
- `examples/mega65-hello.lasm` — hello world Mega65 en syntaxe .lasm
- `examples/mega65-minimal.lasm` — programme Mega65 minimaliste
- `examples/x16-hello.asm` — hello world X16 via CHROUT
- `examples/x16-minimal.asm` — programme X16 minimaliste via CHROUT
- `examples/x16-debug.asm` — programme de diagnostic X16 (BRK)

### Tests

| Suite | Tests |
|---|---|
| symbol-table | 59 |
| expression | 129 |
| lexer | 119 |
| parser | 84 |
| macros | 27 |
| conditionnel | 27 |
| lasm | 58 |
| 6502 | 82 |
| 65c02 | 41 |
| 45gs02 | 80 |
| **TOTAL** | **706** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, SLIME.

### Limitations connues

- Assemblage conditionnel : les forward-references ne sont pas supportées
  dans les expressions `.if` — seuls les symboles définis *avant* le `.if`
  sont visibles.
- Macros textuelles : les arguments sont des tokens uniques (pas
  d'expressions multi-tokens comme paramètres).
- Frontend .lasm : `(target :45gs02)` est une directive no-op à
  l'exécution — utilisée uniquement par le script `cl-asm`.
- Accès direct VERA (X16) : non testé sur hardware réel, les programmes
  d'exemple utilisent CHROUT par sécurité.

### Architectures non supportées

Z80, 68000, ARM32, ARM64, x86-64 — prévus pour des versions futures.

---
