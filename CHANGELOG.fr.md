# Changelog cl-asm

Toutes les modifications notables de ce projet sont documentées ici.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/).

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
