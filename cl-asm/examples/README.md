# Exemples cl-asm

Deux programmes de démonstration illustrant les capacités de cl-asm :
un raster bar C64 en syntaxe assembleur classique, et un programme
Mega65 en syntaxe `.lasm` (Common Lisp natif).

---

## `c64-raster.asm` — Raster bar Commodore 64

Un effet de démonstration classique : le faisceau électron du VIC-II
est synchronisé via une interruption raster pour changer la couleur de
bordure ligne par ligne, créant un arc-en-ciel animé.

**Fonctionnalités cl-asm illustrées :**
- Macros textuelles (`.macro WAIT_RASTER`, `.macro SET_BORDER`)
- Assemblage conditionnel (`.if DEBUG`)
- Labels numériques (`1:`, `1-`)
- Expressions dans les opérandes (`IRQ_VECTOR + 1`)
- Directives `.byte`, `.org`, `.equ`

### Assemblage

Depuis le répertoire racine du projet :

```lisp
(ql:quickload "cl-asm")

(let ((bytes (cl-asm/backend.6502:assemble-file
               "examples/c64-raster.asm"
               :origin #x0801)))
  (cl-asm/emit:write-prg bytes "examples/c64-raster.prg"
                          :load-address #x0801))
```

Ou via le script shell :

```bash
sbcl --load bootstrap.lisp \
     --eval "(let ((b (cl-asm/backend.6502:assemble-file
                        \"examples/c64-raster.asm\" :origin #x0801)))
               (cl-asm/emit:write-prg b \"examples/c64-raster.prg\"
                 :load-address #x0801))" \
     --quit
```

### Chargement

**Sur vrai C64 :**
```
LOAD "C64-RASTER.PRG",8,1
RUN
```

**Avec VICE (émulateur) :**
```bash
x64 examples/c64-raster.prg
```

### Options

Modifier `DEBUG = 0` en `DEBUG = 1` pour afficher un compteur
d'interruptions à l'écran (utile pour vérifier que les IRQ raster
se déclenchent correctement).

---

## `mega65-hello.lasm` — Hello World Mega65

Programme `.lasm` qui affiche "HELLO, MEGA65!" centré à l'écran avec
des couleurs différentes pour chaque lettre, suivi d'une animation de
bordure clignotante.

**Fonctionnalités cl-asm/lasm illustrées :**
- Directives `(org ...)`, `(label ...)`, `(equ ...)`
- Mode immédiat : `(lda :imm 'blue)`
- Mode déduit automatique : `(sta #xD020)`
- Instructions 45GS02 : `LDZ`, `INZ`, `TAZ`
- Puissance de Lisp : `dotimes`, `dolist`, `let`, `defun`, `defparameter`
- Calculs à l'assemblage : positions d'écran, codes PETSCII

### Assemblage

```lisp
(ql:quickload "cl-asm")

(let ((bytes (cl-asm/lasm:assemble-lasm
               "examples/mega65-hello.lasm"
               :origin #x2001
               :target :45gs02)))
  (cl-asm/emit:write-prg bytes "examples/mega65-hello.prg"
                          :load-address #x2001))
```

### Chargement

**Sur vrai Mega65 :**
```
LOAD "MEGA65-HELLO.PRG"
RUN
```

**Via mega65_ftp :**
```bash
mega65_ftp -c "put examples/mega65-hello.prg"
```

**Avec le simulateur XEMU :**
```bash
xmega65 -prg examples/mega65-hello.prg
```

### Notes techniques

Le programme utilise le registre Z du 45GS02 comme index 8 bits
supplémentaire pour adresser la mémoire vidéo. L'instruction `INZ`
(Increment Z) permet d'itérer octet par octet sur la mémoire écran
sans modifier X ou Y. La boucle de clignotement utilise `dolist`
Lisp pour parcourir une liste de couleurs.

---

## Structure des fichiers produits

```
examples/
├── c64-raster.asm      source assembleur classique
├── c64-raster.prg      binaire C64 (généré)
├── mega65-hello.lasm   source .lasm (Lisp natif)
├── mega65-hello.prg    binaire Mega65 (généré)
└── README.md           ce fichier
```
