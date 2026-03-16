# Tests de régression cl-asm

Compare les binaires produits par cl-asm avec ceux d'un compilateur
de référence (ACME par défaut).

## Utilisation rapide

```bash
cd tests/regression/

# 1. Générer les binaires de référence (une seule fois)
./run-regression.sh --update c64

# 2. Lancer les tests
./run-regression.sh c64

# 3. Tester un seul fichier
./run-regression.sh c64 01-basic
```

## Workflow complet

```bash
# Générer toutes les références
./run-regression.sh --update

# Tester toutes les architectures
./run-regression.sh

# Mode verbose (montre les offsets en cas d'erreur)
./run-regression.sh --verbose c64
```

## Changer de compilateur de référence

Éditer `config.sh` et modifier `REF_COMPILER` :

```bash
REF_COMPILER="acme"    # ACME (défaut)
REF_COMPILER="ca65"    # cc65 (à implémenter)
```

## Structure des fichiers

```
tests/regression/
├── run-regression.sh       script principal
├── config.sh               compilateur de référence
├── README.md               ce fichier
├── c64/
│   ├── 01-basic.asm        instructions implied/accumulator/immédiat
│   ├── 02-addressing.asm   tous les modes d'adressage 6502
│   ├── 03-branches.asm     branches conditionnelles et labels
│   ├── 04-directives.asm   .byte .word .text .fill .align
│   ├── 05-macros.asm       macros textuelles
│   ├── 06-c64-program.asm  programme C64 complet
│   └── *.ref.prg           binaires de référence (générés, non versionnés)
├── mega65/                 (à compléter)
└── x16/                    (à compléter)
```

## Ajouter un test

Créer un fichier `.asm` dans le dossier de l'architecture, puis
régénérer la référence :

```bash
# Après avoir créé tests/regression/c64/07-mon-test.asm :
./run-regression.sh --update c64 07-mon-test
./run-regression.sh c64 07-mon-test
```

## Codes de retour

- `0` : tous les tests passent
- `1` : au moins un test échoue ou une erreur d'assemblage

## Prérequis

- ACME installé (`sudo apt install acme` ou `sudo pacman -S acme`)
- cl-asm compilable (SBCL)
- `xxd` pour l'affichage des diffs (inclus dans `vim`)
- `python3` pour le calcul des origines

## Changer de compilateur de référence

Éditer `config.sh` et modifier `REF_COMPILER` :

```bash
REF_COMPILER="acme"   # ACME (défaut)
REF_COMPILER="ca65"   # ca65 du projet cc65 (nécessite ca65 + ld65)
```

Après avoir changé de compilateur, régénérer les références :

```bash
./run-regression.sh --clear c64      # supprimer les anciennes références
./run-regression.sh --update c64     # générer avec le nouveau compilateur
./run-regression.sh c64              # tester
```

## Supprimer les binaires de référence

```bash
./run-regression.sh --clear          # tous
./run-regression.sh --clear c64      # architecture spécifique
./run-regression.sh --clear c64 01-basic  # fichier spécifique
```

## Fichiers .skip

Chaque architecture peut avoir un fichier `.{compilateur}-skip` listant
les tests incompatibles avec ce compilateur :

```
c64/.acme-skip   # tests ignorés avec ACME
c64/.ca65-skip   # tests ignorés avec ca65 (vide pour l'instant)
```
