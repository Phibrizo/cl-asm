# Changelog cl-asm

Toutes les modifications notables de ce projet sont documentées ici.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/).


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

| Suite | 0.1.0 | 0.1.1 |
|---|---|---|
| symbol-table | 59 | 61 (+2) |
| 65c02 | — | 41 |
| Autres | 588 | 588 |
| **TOTAL** | **647** | **706** |

**Régression binaire** : 5/5 OK vs ACME, 6/6 OK vs ca65.


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

## [Unreleased]

- Émetteur ROM Mega65
- Programme de démonstration C64/Mega65 sur hardware réel
- Support Z80 (Amstrad CPC, MSX, ZX Spectrum)
- Support 68000 (Amiga, Atari ST)
- Accès direct VERA pour X16
