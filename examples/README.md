# Exemples cl-asm

Programmes de démonstration illustrant les capacités de cl-asm.
Les fichiers `.lasm` utilisent la syntaxe Lisp native ; les `.asm` la syntaxe classique ca65.

---

## Fichiers `.lasm` — syntaxe Lisp native

> **Assemblage simplifié :** chaque fichier `.lasm` commence par `(target :xyz)`.
> Le script `cl-asm` lit les 10 premières lignes et détecte la cible automatiquement.
> La commande `./cl-asm examples/fichier.lasm` suffit — `--target` est facultatif.

### `c64-hello.lasm` — Hello World Commodore 64 (6502)

Affiche "HELLO, WORLD!" centré sur l'écran avec un arc-en-ciel de couleurs.

**Fonctionnalités illustrées :**
- `defparameter` pour les constantes matériel (adresses, couleurs)
- `defun` pour la conversion caractère → code écran PETSCII
- `dotimes` pour les boucles d'écriture en RAM vidéo
- Génération de palettes et de positions par Lisp pur (zéro octet émis)

```bash
./cl-asm examples/c64-hello.lasm
```

---

### `x16-hello.lasm` — Hello World Commander X16 (65C02)

Affiche plusieurs lignes de texte via l'appel KERNAL CHROUT.

**Fonctionnalités illustrées :**
- `defun` qui génère des séquences PETSCII à l'assemblage
- `format nil` pour créer du texte dynamique (numéro de build, etc.)
- `BRA` — branchement relatif, instruction spécifique au 65C02
- Lisp génère tous les `LDA/JSR` en un seul `dotimes`

```bash
./cl-asm examples/x16-hello.lasm
```

---

### `mega65-hello.lasm` — Hello World Mega65 (45GS02)

Affiche "HELLO, MEGA65!" avec animation de bordure arc-en-ciel.

**Fonctionnalités illustrées :**
- Instructions 45GS02 : `LDZ`, `INZ`, `TAZ`
- Calculs de positions écran par Lisp
- Boucle de clignotement avec `dolist` et délai imbriqué

```bash
./cl-asm examples/mega65-hello.lasm
```

---

### `mega65-minimal.lasm` — Minimal Mega65 (45GS02)

Programme minimaliste : affiche "HELLO WORLD" sans animation.

---

### `z80-spectrum.lasm` — Hello World ZX Spectrum (Z80)

Affiche plusieurs lignes via RST $10 (PRINT_CHAR ROM), avec une table de sinus.

**Fonctionnalités illustrées :**
- `zi` — émettre une instruction Z80 générique
- `z80r` — opérande registre (`:direct "A"`)
- `z80ind` — opérande indirect (`:indirect "HL"`)
- `make-dir` — référence à un label comme opérande
- `DJNZ` — boucle Z80 avec registre B comme compteur
- `sine-table` — table de sinus calculée à l'assemblage

```bash
./cl-asm examples/z80-spectrum.lasm
```

---

### `m68k-tables.lasm` — Tables de lookup Motorola 68000

Génère des tables mathématiques par Lisp, puis les traite avec une boucle 68000.

**Fonctionnalités illustrées :**
- `mi` — émettre une instruction M68K avec taille (`.B`/`.W`/`.L`)
- `dn` / `an` — registres de données et d'adresse
- `m68k-imm` / `make-imm` — immédiats et labels
- `post-an` — mode post-increment `(An)+`
- `DBRA` — boucle 68000 à compteur décroissant
- `sine-table`, `cosine-table`, `linear-ramp` — tables prêtes à l'emploi
- Tables de parité et nibble calculées en Lisp pur

```bash
./cl-asm examples/m68k-tables.lasm
```

---

### `i8080-cpm.lasm` — Hello World CP/M (Intel 8080)

Appels BDOS 9 (print string) avec texte généré par `format` à l'assemblage.

**Fonctionnalités illustrées :**
- `i8080` — émettre une instruction 8080 générique
- `i8080r` / `i8080rp` — registres 8 bits et paires de registres
- `make-imm` — valeur immédiate ou adresse de label
- `defun` comme macro d'assemblage (`bdos-call`)
- `format nil` pour inclure des valeurs calculées dans les chaînes de données

```bash
./cl-asm examples/i8080-cpm.lasm
```

---

## Fichiers `.asm` — syntaxe assembleur classique

### `c64-raster.asm` — Raster bar Commodore 64

Effet raster animé : interruption synchronisée au faisceau VIC-II.

**Fonctionnalités illustrées :**
- Macros textuelles (`.macro WAIT_RASTER`)
- Assemblage conditionnel (`.if DEBUG`)
- Labels numériques (`1:`, `1-`)
- Expressions dans les opérandes (`IRQ_VECTOR + 1`)

```bash
./cl-asm examples/c64-raster.asm
```

### `x16-hello.asm`, `x16-minimal.asm`, `x16-debug.asm` — Commander X16

Exemples variés en syntaxe classique pour le Commander X16.

---

## Assemblage via le REPL

Depuis un REPL (SBCL, SLIME, SLY…), `assemble-lasm` ne fait pas l'auto-détection
de cible : il faut passer `:target` explicitement.

`write-prg` ajoute un en-tête 2 octets (adresse de chargement C64/X16) ;
utiliser `write-bin` pour un binaire brut (Z80, M68K, 8080).

```lisp
(ql:quickload "cl-asm")

;; C64 (6502) — format PRG avec en-tête $0801
(let ((bytes (cl-asm/lasm:assemble-lasm "examples/c64-hello.lasm" :target :6502)))
  (cl-asm/emit:write-prg bytes "examples/c64-hello.prg" :load-address #x0801))

;; Commander X16 (65C02) — format PRG avec en-tête $0801
(let ((bytes (cl-asm/lasm:assemble-lasm "examples/x16-hello.lasm" :target :x16)))
  (cl-asm/emit:write-prg bytes "examples/x16-hello.prg" :load-address #x0801))

;; ZX Spectrum (Z80) — binaire brut à $8000
(let ((bytes (cl-asm/lasm:assemble-lasm "examples/z80-spectrum.lasm" :target :z80)))
  (cl-asm/emit:write-bin bytes "examples/z80-spectrum.bin"))

;; CP/M (Intel 8080) — binaire brut à $0100
(let ((bytes (cl-asm/lasm:assemble-lasm "examples/i8080-cpm.lasm" :target :i8080)))
  (cl-asm/emit:write-bin bytes "examples/i8080-cpm.com"))

;; Amiga/Atari ST (M68K) — binaire brut à $0000
(let ((bytes (cl-asm/lasm:assemble-lasm "examples/m68k-tables.lasm" :target :m68k)))
  (cl-asm/emit:write-bin bytes "examples/m68k-tables.bin"))
```

---

## Structure des fichiers

```
examples/
├── c64-hello.lasm       6502  — Hello World C64
├── c64-raster.asm       6502  — Raster bar C64 (syntaxe classique)
├── x16-hello.lasm       65C02 — Hello World Commander X16
├── x16-hello.asm        65C02 — idem, syntaxe classique
├── x16-minimal.asm      65C02 — version minimale
├── x16-debug.asm        65C02 — version avec debug
├── mega65-hello.lasm    45GS02 — Hello World Mega65 (animation)
├── mega65-minimal.lasm  45GS02 — Hello World Mega65 (minimal)
├── z80-spectrum.lasm    Z80   — Hello World ZX Spectrum
├── m68k-tables.lasm     M68K  — Tables de lookup Amiga/Atari ST
├── i8080-cpm.lasm       8080  — Hello World CP/M
└── README.md            ce fichier
```
