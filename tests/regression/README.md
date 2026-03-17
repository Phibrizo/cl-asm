# Tests de régression cl-asm

Compare les binaires produits par cl-asm avec ceux d'un compilateur
de référence (ACME par défaut pour la famille 6502).

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
# Générer toutes les références (toutes les architectures)
./run-regression.sh --update

# Tester toutes les architectures
./run-regression.sh

# Mode verbose (montre les offsets en cas d'erreur)
./run-regression.sh --verbose c64
```

## Structure des fichiers

```
tests/regression/
├── run-regression.sh       script principal (générique, toutes architectures)
├── config-6502.sh          config compilateur de référence — famille 6502
│                           (cibles : c64, mega65, x16)
├── README.md               ce fichier
├── c64/
│   ├── 01-basic.asm        instructions implied/accumulator/immédiat
│   ├── 02-addressing.asm   tous les modes d'adressage 6502
│   ├── 03-branches.asm     branches conditionnelles et labels
│   ├── 04-directives.asm   .byte .word .text .fill .align
│   ├── 05-macros.asm       macros textuelles
│   ├── 06-c64-program.asm  programme C64 complet
│   ├── .acme-skip          tests ignorés avec ACME
│   ├── .ca65-skip          tests ignorés avec ca65
│   └── *.ref.prg           binaires de référence (générés, non versionnés)
├── mega65/                 (à compléter)
└── x16/                    (à compléter)
```

## Architecture : un config par famille

Chaque famille d'architectures dispose de son propre `config-<arch>.sh`.
`run-regression.sh` charge automatiquement le bon fichier selon la cible
traitée — aucune intervention manuelle.

| Fichier de config   | Cibles gérées     | Compilateurs supportés |
|---------------------|-------------------|------------------------|
| `config-6502.sh`    | c64, mega65, x16  | acme, ca65             |
| `config-z80.sh`     | *(à créer)*       | nasm, z80asm…          |
| `config-68000.sh`   | *(à créer)*       | vasm, gas…             |

### Changer de compilateur de référence (famille 6502)

Éditer `config-6502.sh` et modifier `REF_COMPILER` :

```bash
REF_COMPILER="acme"    # ACME (défaut)
REF_COMPILER="ca65"    # cc65 (nécessite ca65 + ld65)
```

Après avoir changé de compilateur, régénérer les références :

```bash
./run-regression.sh --clear c64      # supprimer les anciennes références
./run-regression.sh --update c64     # générer avec le nouveau compilateur
./run-regression.sh c64              # tester
```

## Ajouter une nouvelle architecture

1. Créer le dossier de tests : `tests/regression/z80/`
2. Y placer des fichiers `.asm` dans la syntaxe cl-asm
3. Créer `config-z80.sh` en suivant le modèle de `config-6502.sh` :
   - Déclarer `REF_COMPILER`
   - Implémenter `ref_assemble()`, `ref_check_available()`, `config_handles_target()`
4. Lancer `./run-regression.sh --update z80`

```bash
# Exemple de config-z80.sh minimal
REF_COMPILER="nasm"

config_handles_target() {
    case "$1" in
        z80|cpc|msx) return 0 ;;
        *)            return 1 ;;
    esac
}

ref_check_available() { command -v nasm >/dev/null 2>&1 ; }

ref_assemble() {
    local source="$1" output="$2" origin="$3" target="$4"
    # ... conversion syntaxe + appel nasm ...
}
```

## Ajouter un test dans une architecture existante

```bash
# Après avoir créé tests/regression/c64/07-mon-test.asm :
./run-regression.sh --update c64 07-mon-test
./run-regression.sh c64 07-mon-test
```

## Fichiers .skip

Chaque dossier cible peut contenir un fichier `.{compilateur}-skip` listant
les tests incompatibles avec ce compilateur (un nom de base par ligne) :

```
# c64/.acme-skip
05-macros-nolabel   # syntaxe de macro non supportée par ACME
```

## Supprimer les binaires de référence

```bash
./run-regression.sh --clear          # tous
./run-regression.sh --clear c64      # architecture spécifique
./run-regression.sh --clear c64 01-basic  # fichier spécifique
```

## Codes de retour

- `0` : tous les tests passent
- `1` : au moins un test échoue ou une erreur d'assemblage

## Prérequis

- **ACME** installé (`sudo apt install acme` ou `sudo pacman -S acme`)
  — ou **ca65 + ld65** (`sudo apt install cc65`)
- **cl-asm** compilable (SBCL)
- `xxd` pour l'affichage des diffs (inclus dans `vim`)
- `python3` pour le calcul des origines
