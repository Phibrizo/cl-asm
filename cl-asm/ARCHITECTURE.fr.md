# Architecture de cl-asm

## Vue d'ensemble

cl-asm est structuré en trois couches indépendantes :

```
┌─────────────────────────────────────────────┐
│  Frontends (syntaxes pluggables)            │
│  classic (ca65-like) · .lasm (futur)        │
└──────────────┬──────────────────────────────┘
               │ produit un IR-PROGRAM
               ▼
┌─────────────────────────────────────────────┐
│  Représentation intermédiaire (IR)          │
│  ir-label · ir-instruction · ir-directive   │
└──────────────┬──────────────────────────────┘
               │ consommé par
               ▼
┌─────────────────────────────────────────────┐
│  Backends (architectures cibles)            │
│  6502 · 45GS02 · x86 (futur)               │
└──────────────┬──────────────────────────────┘
               │ produit un vecteur d'octets
               ▼
┌─────────────────────────────────────────────┐
│  Émetteurs (formats de fichiers)            │
│  BIN · PRG (C64) · listing · ROM (futur)   │
└─────────────────────────────────────────────┘
```

---

## Packages Common Lisp

| Package | Fichier | Rôle |
|---|---|---|
| `cl-asm/ir` | `src/core/ir.lisp` | Structures IR et conditions |
| `cl-asm/expression` | `src/core/expression.lisp` | Évaluateur d'expressions |
| `cl-asm/symbol-table` | `src/core/symbol-table.lisp` | Table des symboles |
| `cl-asm/lexer` | `src/frontend/classic-lexer.lisp` | Tokeniseur |
| `cl-asm/parser` | `src/frontend/classic-parser.lisp` | Parser → IR |
| `cl-asm/backend.6502` | `src/backend/6502.lisp` | Backend 6502 |
| `cl-asm/backend.45gs02` | `src/backend/45gs02.lisp` | Backend 45GS02 |
| `cl-asm/backend.65c02` | `src/backend/65c02.lisp` | Backend 65C02 (X16) |
| `cl-asm/lasm` | `src/frontend/lasm.lisp` | Frontend Lisp natif (.lasm) |
| `cl-asm/test.*` | `tests/test-*.lisp` | Suites de tests |

---

## Module `cl-asm/ir`

Définit toutes les structures de données partagées entre frontends
et backends.

### Structures principales

```lisp
;; Nœuds de l'IR
(ir-label      :name STRING :kind (:local|:global|:numeric) :number INT :loc)
(ir-instruction :mnemonic STRING :operands LIST :loc)
(ir-directive  :name KEYWORD :args LIST :loc)

;; Opérande d'instruction
(ir-operand :kind KIND :value EXPR :index-reg KEYWORD :size-hint KEYWORD :loc)
```

### Kinds d'opérande

| Kind | Syntaxe | Description |
|---|---|---|
| `:immediate` | `#expr` | Valeur immédiate |
| `:direct` | `addr` ou `addr,X/Y/Z` | Adresse directe |
| `:indirect` | `(addr)` | Indirect classique |
| `:indirect-x` | `(addr,X)` | Pre-indexé X |
| `:indirect-y` | `(addr),Y` ou `(addr),Z` | Post-indexé |
| `:indirect-sp-y` | `(addr,SP),Y` | Pile 45GS02 |
| `:indirect-32` | `[addr]` | Indirect 32 bits 45GS02 |
| `:indirect-32-z` | `[addr],Z` | Indirect 32 bits + Z |
| `:register` | `A`, `X`, `Y`… | Registre seul (accumulateur) |

### Conteneurs

```lisp
(ir-section :name KEYWORD :origin INT :nodes LIST :binary VECTOR)
(ir-program :sections LIST :entry-point STRING)
```

---

## Module `cl-asm/expression`

Évalue des expressions arithmétiques représentées comme des arbres
préfixés (listes Common Lisp).

### Interface

```lisp
(eval-expr EXPR ENV)          ; → (values VALEUR RESOLVEDP)
(eval-expr/byte  EXPR ENV)    ; → entier [0,255] ou erreur de plage
(eval-expr/sbyte EXPR ENV)    ; → entier [-128,127]
(eval-expr/word  EXPR ENV)    ; → entier [0,65535]

(make-env :symbol-table ST :pc ADDR)
(constant-expr-p EXPR)        ; → BOOLEAN
```

### Opérateurs

| Famille | Opérateurs |
|---|---|
| Arithmétique | `:+` `:-` `:*` `:/` `:mod` `:neg` `:abs` `:min` `:max` |
| Bit-à-bit | `:&` `:bitor` `:^` `:~` |
| Décalages | `:>>` `:<<` |
| Extraction | `:lo` `:hi` `:bank` `:highest` `:word` |
| Comparaison | `:=` `:/=` `:<` `:<=` `:>` `:>=` |
| Logique | `:and` `:or` `:not` |
| Spéciaux | `:neg` `:current-pc` `:defined` `:if` |

### Forward-references

En passe 1, `eval-expr` retourne `(values :unresolved nil)` pour
un symbole absent — sans signaler d'erreur.
En passe 2, tout symbole absent déclenche `asm-undefined-label`.

---

## Module `cl-asm/symbol-table`

Maintient la table des labels, constantes et équates. Implémente la
résolution en deux passes classique des assembleurs.

### Interface

```lisp
(make-symbol-table)

(define-label    ST NOM &key source-loc)
(define-constant ST NOM VALEUR &key source-loc)
(define-equate   ST NOM EXPRESSION &key source-loc)

(define-numeric-label  ST NUMERO)
(resolve-numeric-label ST NUMERO :backward|:forward)

(resolve-symbol   ST NOM &key source-loc)  ; → (values VALEUR RESOLVEDP)
(symbol-defined-p ST NOM)

(with-local-scope (ST) &body BODY)
(begin-pass-2 ST)

(dump-symbol-table   ST)
(list-symbols        ST &key kind global-only)
(warn-unused-symbols ST)
```

### Deux passes

```
Passe 1 : parcourt l'IR → enregistre les labels → estime les tailles
           (les forward-refs retournent :unresolved sans erreur)

(begin-pass-2 ST) → remet PC à 0, vide les labels numériques

Passe 2 : parcourt l'IR → encode → tous les symboles doivent être résolus
```

---

## Module `cl-asm/lexer`

Tokenise le source en une liste de `TOKEN`.

### Tokens produits

```
:integer     42  $FF  0xFF  %1010  0b1010  'A'
:string      "hello"
:identifier  lda  .byte  @loop  start
:label-def   loop:  main::  (avec :global si ::)
:numeric-label-def  1:  2:
:comma :colon :hash :lparen :rparen :lbracket :rbracket
:plus :minus :star :slash :percent :ampersand :pipe :caret :tilde
:lt :gt :lshift :rshift :equals
:newline :eof
```

### Interface

```lisp
(tokenize-string SOURCE &key file)  ; → liste de TOKEN
(tokenize-file   PATH)
```

---

## Module `cl-asm/parser`

Parser à descente récursive. Consomme les tokens et produit un `IR-PROGRAM`.

### Interface

```lisp
(parse-string SOURCE &key file section)  ; → IR-PROGRAM
(parse-tokens TOKENS &key file section)
(parse-file   PATH   &key section)
```

### Expressions parsées

Le parser construit des arbres préfixés compatibles avec `eval-expr` :

```
BASE+1      → (:+ "BASE" 1)
<VEC        → (:lo "VEC")
>VEC        → (:hi "VEC")
(A|B)&$FF   → (:& (:bitor "A" "B") 255)
*-2         → (:- :* 2)
```

---

## Module `cl-asm/backend.6502`

Encode les instructions 6502 en octets. Deux passes.

### Interface

```lisp
(assemble        PROGRAM &key origin section)  ; → vecteur d'octets
(assemble-string SOURCE  &key origin)
(assemble-file   PATH    &key origin)

;; Bas niveau (utilisé aussi par le backend 45GS02)
(encode-instruction INSTR SYMTABLE PC PASS)  ; → (values OCTETS TAILLE)
(resolve-mode       OPERAND ADDR-VALUE)      ; → mode keyword
(eval-operand-value OPERAND SYMTABLE PC)     ; → (values VALEUR RESOLVEDP)
```

### Modes d'adressage 6502

| Mode | Syntaxe | Octets |
|---|---|---|
| `:implied` | `NOP` | 1 |
| `:accumulator` | `LSR A` | 1 |
| `:immediate` | `LDA #$FF` | 2 |
| `:zero-page` | `LDA $10` | 2 |
| `:zero-page-x/y` | `LDA $10,X` | 2 |
| `:absolute` | `LDA $1234` | 3 |
| `:absolute-x/y` | `LDA $1234,X` | 3 |
| `:indirect` | `JMP ($FFFC)` | 3 |
| `:indirect-x` | `LDA ($00,X)` | 2 |
| `:indirect-y` | `LDA ($00),Y` | 2 |
| `:relative` | `BNE label` | 2 |

### Sélection zero-page vs absolu

Si une adresse tient dans `[0..255]` et qu'il n'y a pas de hint `:word`,
le backend choisit automatiquement le mode zero-page (2 octets au lieu de 3).
Pour forcer le mode absolu : utiliser une expression comme `addr+0` ou un
futur hint de taille (`:word`).

---

## Module `cl-asm/backend.45gs02`

Superset du backend 6502. La table d'instructions est construite en
copiant la table 6502 puis en y ajoutant les extensions.

### Nouvelles instructions

| Groupe | Instructions |
|---|---|
| Registre Z | `LDZ` `STZ` `INZ` `DEZ` `PHZ` `PLZ` `TAZ` `TZA` |
| Registre B | `TAB` `TBA` `TSY` `TYS` |
| Mémoire 16 bits | `INW` `DEW` `ASW` `ROW` |
| Décalages | `NEG` `ASR` |
| Spéciales | `MAP` `EOM` |
| Branches longues | `LBCC` `LBCS` `LBEQ` `LBNE` `LBMI` `LBPL` `LBVC` `LBVS` |
| Q 32 bits | `LDQ` `STQ` `ADCQ` `SBCQ` `ANDQ` `ORAQ` `EORQ` `ASLQ` `LSRQ` `ROLQ` `RORQ` `ASRQ` `BITQ` `CMPQ` |

### Encodage avec préfixes

| Préfixe | Usage |
|---|---|
| `$EA` | Active l'indirect 32 bits `[$nn]` |
| `$42` | Branche longue 16 bits (`LBNE` etc.) |
| `$42 $42` | Instruction Q 32 bits (`LDQ`, `STQ`…) |

```
LDQ ($20),Z  →  $42 $42 $B2 $20   (4 octets)
LBNE label   →  $42 $D0 lo hi     (4 octets)
LDA [$20]    →  $EA $B1 $20       (3 octets)
```

---

## Module `cl-asm/lasm`

Frontend Lisp natif. Les fichiers `.lasm` sont du Common Lisp valide
qui s'exécute dans un contexte où chaque mnémonique est une fonction.
Toute la puissance de CL est disponible : `let`, `dotimes`, `loop`,
`defun`, `defmacro`, etc.

### Interface

```lisp
(cl-asm/lasm:assemble-lasm-string SOURCE &key origin target)
(cl-asm/lasm:assemble-lasm        PATH   &key origin target)
(cl-asm/lasm:load-lasm-string     SOURCE)  ; → IR-PROGRAM
(cl-asm/lasm:load-lasm            PATH)    ; → IR-PROGRAM
```

`target` : `:6502` (défaut) ou `:45gs02`.

### Directive de cible

```lisp
(target :45gs02)  ; en tête du fichier .lasm
```

Fonction no-op à l'exécution — sert uniquement de marqueur pour le
script `cl-asm` en ligne de commande qui la détecte via `grep` avant
de charger le fichier. Sans effet si le fichier est chargé directement
dans un REPL.

### Convention des modes d'adressage

**Sans keyword** — mode déduit de la valeur :

| Appel | Résultat | Condition |
|---|---|---|
| `(lda #x10)` | `LDA $10` (zero-page) | valeur ≤ 255 |
| `(lda #x1234)` | `LDA $1234` (absolu) | valeur > 255 |
| `(lda 'screen)` | `LDA SCREEN` | symbole → absolu |

**Avec keyword** — mode explicite :

| Keyword | Mode | Exemple |
|---|---|---|
| `:imm` | Immédiat | `(lda :imm #xFF)` → `LDA #$FF` |
| `:x` | Indexé X | `(lda :x #x10)` → `LDA $10,X` |
| `:y` | Indexé Y | `(lda :y #x1234)` → `LDA $1234,Y` |
| `:z` | Indexé Z (45GS02) | `(lda :z #x1234)` → `LDA $1234,Z` |
| `:ind` | Indirect | `(jmp :ind #xFFFC)` → `JMP ($FFFC)` |
| `:ix` | Indirect pré-indexé X | `(lda :ix #x00)` → `LDA ($00,X)` |
| `:iy` | Indirect post-indexé Y | `(lda :iy #xB0)` → `LDA ($B0),Y` |
| `:iz` | Indirect post-indexé Z | `(lda :iz #xB0)` → `LDA ($B0),Z` |
| `:abs` | Absolu forcé | `(lda :abs #x10)` → `LDA $0010` |
| `:zp` | Zero-page forcée | `(lda :zp #x10)` → `LDA $10` |
| `:a` | Accumulateur | `(lsr :a)` → `LSR A` |

### Directives disponibles

```lisp
(org #x0801)          ; .org
(label 'start)        ; label local
(global-label 'main)  ; label global
(equ 'cols 40)        ; constante
(db #x01 #x02)        ; .byte
(dw #x1234)           ; .word (little-endian)
(dd #x12345678)       ; .dword (little-endian)
(fill 10 #x00)        ; .fill
(text "HELLO")        ; .text
(align 256)           ; .align
(section :data)       ; .section
```

### Mécanisme d'exécution

`load-lasm-string` lie `*package*` au package `cl-asm/lasm` puis
évalue le source forme par forme avec `read`/`eval`. Toutes les
fonctions mnémoniques, directives et le contexte `*ctx*` sont
accessibles dans ce package. L'IR est construit progressivement
au fil de l'exécution.

---

## Module `cl-asm/backend.65c02`

Superset du backend 6502 pour le WDC 65C02 (Commander X16).

### Interface

```lisp
(cl-asm/backend.65c02:assemble-65c02        PROGRAM &key origin)
(cl-asm/backend.65c02:assemble-string-65c02 SOURCE  &key origin)
(cl-asm/backend.65c02:assemble-file-65c02   PATH    &key origin)
```

Origine par défaut : `$0801` (identique au C64).

### Nouvelles instructions 65C02

| Instruction | Mode | Opcode | Octets |
|---|---|---|---|
| `BRA rel` | Relatif | `$80` | 2 |
| `STZ addr` | ZP / ZP,X / Abs / Abs,X | `$64/$74/$9C/$9E` | 2-3 |
| `TRB addr` | ZP / Abs | `$14/$1C` | 2-3 |
| `TSB addr` | ZP / Abs | `$04/$0C` | 2-3 |
| `PHX` | Implied | `$DA` | 1 |
| `PLX` | Implied | `$FA` | 1 |
| `PHY` | Implied | `$5A` | 1 |
| `PLY` | Implied | `$7A` | 1 |
| `INC A` | Accumulateur | `$1A` | 1 |
| `DEC A` | Accumulateur | `$3A` | 1 |

### Nouveau mode d'adressage

| Mode | Syntaxe | Opcodes |
|---|---|---|
| `:zero-page-indirect` | `LDA ($nn)` | `$B2` (LDA), `$92` (STA)… |

Ce mode indirect sans index (ZP seulement) est absent du 6502 original.

### Modes étendus sur instructions existantes

- `BIT` : modes `:immediate`, `:zero-page-x`, `:absolute-x`
- `JMP` : mode `:indirect-x` (`$7C`)
- `ADC/SBC/AND/ORA/EOR/CMP/LDA/STA` : mode `:zero-page-indirect`


---

## Module `cl-asm/emit`

Émetteurs de fichiers de sortie.

### Interface

```lisp
(write-bin  BYTES PATH)
(write-prg  BYTES PATH &key load-address)   ; défaut : $0801
(write-listing PROGRAM BYTES PATH &key origin)
```

### Format PRG (C64)

```
Offset 0 : adresse de chargement, octet bas
Offset 1 : adresse de chargement, octet haut
Offset 2 : début du code/données binaires
```

Exemple : pour charger à `$0801`, le header est `$01 $08`.

---

## Conditions (erreurs)

Toutes héritent de `cl-asm/ir:asm-error` qui affiche le message
avec la localisation source si disponible.

| Condition | Déclenchée par |
|---|---|
| `asm-syntax-error` | Parser : token inattendu |
| `asm-undefined-label` | Passe 2 : symbole absent |
| `asm-range-error` | Valeur hors plage (branche, byte overflow…) |
| `asm-unknown-mnemonic` | Mnémonique inconnu dans la table |
| `lexer-error` | Caractère invalide, chaîne non fermée… |

---

## Conventions de code

- **Encodage** : UTF-8, avec `; -*- coding: utf-8 -*-` en première ligne.
- **Packages** : un package par fichier, nommé `cl-asm/module`.
- **Exports** : tout symbole public est dans `:export` du `defpackage`.
- **Récursions mutuelles** : `declaim ftype` en tête de fichier pour
  toutes les fonctions qui se rappellent mutuellement.
- **`otherwise` dans `case`** : toujours utiliser `(t ...)` ou `otherwise`
  comme dernière clause, jamais suivi d'un `declare`. SBCL refuse
  un `declare` après `otherwise`.
- **Tests** : chaque module a `tests/test-<module>.lisp`. Les tests sont
  des fonctions `deftest` autonomes, lancées par `run-all-tests`.
- **Compatibilité SBCL/CLISP** : tester sur les deux à chaque session.
  CLISP est plus strict sur certains points du standard ANSI.
