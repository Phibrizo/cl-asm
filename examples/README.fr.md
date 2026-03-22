# Exemples cl-asm

Programmes de démonstration illustrant les capacités de cl-asm.
Les fichiers `.lasm` utilisent la syntaxe Lisp native ; les `.asm` la syntaxe classique ca65.
Les fichiers `.lisp` sont des scripts Common Lisp utilisant directement l'API programmatique.

---

## Fichiers `.lasm` — syntaxe Lisp native

> **Détection automatique de la cible :** chaque fichier `.lasm` commence par `(target :xyz)`.
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

### `sim-6502-loop.lasm` — Somme d'une table générée par Lisp (simulateur 6502)

Assemble un programme 6502 qui calcule la somme d'une table de puissances de 2.
La table `[1, 2, 4, 8, 16, 32, 64, 128]` est entièrement générée par `dotimes`
à l'assemblage — aucune valeur n'est codée en dur. Résultat attendu : A = 255 (`$FF`).

**Fonctionnalités illustrées :**
- `defparameter` pour paramétrer la taille de la table
- `dotimes` + `(expt 2 i)` pour émettre des octets par calcul Lisp
- Adressage indexé `:x` (ADC abs,X) pour le parcours du tableau
- `bpl` — branchement si positif, utilisé comme boucle « tant que X ≥ 0 »
- Assemblage puis exécution dans le simulateur 6502

```bash
# Assemblage vers binaire
./cl-asm examples/sim-6502-loop.lasm -o /tmp/loop.bin --format bin

# Simulation depuis le REPL (voir les commentaires dans le fichier)
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

## Fichiers `.lisp` — API programmatique

### `sim-6502-demo.lisp` — Démonstrations du simulateur 6502

Trois exemples progressifs utilisant directement l'API `cl-asm/simulator.6502`.
Charger le projet au préalable (`bootstrap.lisp` ou ASDF), puis charger ce fichier.

| Demo | Programme | Résultat attendu |
|------|-----------|-----------------|
| 1 | 5 × 6 par additions répétées | A = 30 (`$1E`) |
| 2 | Fibonacci F[0..9] en page zéro | `$00–$09` = 0 1 1 2 3 5 8 13 21 34 |
| 3 | Sous-programme `SQUARE(7)` (JSR/RTS) | A = 49 (`$31`) |

```bash
sbcl --eval '(asdf:load-system "cl-asm")' \
     --load examples/sim-6502-demo.lisp --quit
```

**Fonctionnalités de l'API illustrées :**
- `make-cpu` / `load-program` / `run-cpu`
- `run-cpu` retourne `(values cpu :brk)` quand BRK est atteint — pas de handler nécessaire
- `cpu-a`, `cpu-x`, `cpu-cycles` — accesseurs registres et compteur de cycles
- `mem-read` — lecture d'un octet dans les 64 Ko de mémoire virtuelle
- `assemble-string` — assemblage inline depuis une chaîne de caractères

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

;; Simulateur 6502 — assembler puis exécuter
(let* ((bytes (cl-asm/lasm:assemble-lasm "examples/sim-6502-loop.lasm" :target :6502))
       (cpu   (cl-asm/simulator.6502:make-cpu))
       (cpu   (cl-asm/simulator.6502:load-program cpu bytes :origin #x0300))
       (final (nth-value 0 (cl-asm/simulator.6502:run-cpu cpu))))
  (format t "A=~D  mem[$00]=~D  cycles=~D~%"
          (cl-asm/simulator.6502:cpu-a      final)
          (cl-asm/simulator.6502:mem-read   final 0)
          (cl-asm/simulator.6502:cpu-cycles final)))
```

---

## Structure des fichiers

```
examples/
├── c64-hello.lasm          6502   — Hello World C64
├── c64-raster.asm          6502   — Raster bar C64 (syntaxe classique)
├── x16-hello.lasm          65C02  — Hello World Commander X16
├── x16-hello.asm           65C02  — idem, syntaxe classique
├── x16-minimal.asm         65C02  — version minimale
├── x16-debug.asm           65C02  — version avec debug
├── mega65-hello.lasm       45GS02 — Hello World Mega65 (animation)
├── mega65-minimal.lasm     45GS02 — Hello World Mega65 (minimal)
├── z80-spectrum.lasm       Z80    — Hello World ZX Spectrum
├── m68k-tables.lasm        M68K   — Tables de lookup Amiga/Atari ST
├── i8080-cpm.lasm          8080   — Hello World CP/M
├── sim-6502-loop.lasm      6502   — Somme d'une table Lisp (simulateur)
├── sim-6502-demo.lisp      6502   — Démo API simulateur (3 exemples)
├── README.md               version anglaise
└── README.fr.md            ce fichier
```
