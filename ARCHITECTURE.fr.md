# Architecture de cl-asm

## Vue d'ensemble

cl-asm est structuré en trois couches indépendantes :

```
┌─────────────────────────────────────────────┐
│  Frontends (syntaxes pluggables)            │
│  classic (ca65-like) · .lasm (Lisp natif)  │
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
│  Backends (architectures cibles)                                   │
│  6502 · 65C02 · R65C02 · 45GS02 · 65816 · Z80 · M68K · 8080 · 8086│
└──────────────┬──────────────────────────────┘
               │ produit un vecteur d'octets (fichier unique)
               │ ou alimenté au linker (multi-fichiers)
               ▼
┌─────────────────────────────────────────────┐
│  Linker (optionnel, famille 6502)           │
│  cl-asm/linker        — link-unit / link    │
│  cl-asm/linker-script — layout multi-segs  │
└──────────────┬──────────────────────────────┘
               │ vecteur(s) d'octets fusionné(s)
               ▼
┌─────────────────────────────────────────────┐
│  Simulateur (optionnel, indépendant)        │
│  cl-asm/simulator.6502                      │
└──────────────┬──────────────────────────────┘
               │ prend un vecteur d'octets + mémoire
        ┌──────┴────────────────────────────────────┐
        ▼                                           ▼
┌──────────────────────────┐  ┌───────────────────────────────────────┐
│  Émetteurs (formats)     │  │  Débogueur (optionnel, interactif)    │
│  BIN · PRG · listing     │  │  cl-asm/debugger.6502                 │
└──────────────────────────┘  │  ← cl-asm/disassembler.6502           │
                               │  ← cl-asm/debug-map (addr→source-loc)│
                               └───────────────────────────────────────┘
┌─────────────────────────────────────────────┐
│  Profiler/Tracer (optionnel, 6502/6510)     │
│  cl-asm/profiler.6502                       │
│  ← cl-asm/simulator.6502 (step-cpu)         │
│  ← cl-asm/disassembler.6502 (disasm-one)   │
└─────────────────────────────────────────────┘
```

---

## Packages Common Lisp

| Package | Fichier | Rôle |
|---|---|---|
| `cl-asm/version` | `src/core/version.lisp` | Numéro de version |
| `cl-asm/backends` | `src/core/backends.lisp` | Registre extensible de backends |
| `cl-asm/disassemblers` | `src/core/disassemblers.lisp` | Registre extensible de désassembleurs |
| `cl-asm/linker` | `src/core/linker.lisp` | Linker modulaire en mémoire (famille 6502) |
| `cl-asm/linker-script` | `src/core/linker-script.lisp` | Linker script multi-segments |
| `cl-asm/ir` | `src/core/ir.lisp` | Structures IR et conditions |
| `cl-asm/expression` | `src/core/expression.lisp` | Évaluateur d'expressions |
| `cl-asm/symbol-table` | `src/core/symbol-table.lisp` | Table des symboles |
| `cl-asm/lexer` | `src/frontend/classic-lexer.lisp` | Tokeniseur |
| `cl-asm/parser` | `src/frontend/classic-parser.lisp` | Parser → IR |
| `cl-asm/backend.6502` | `src/backend/6502.lisp` | Backend 6502 |
| `cl-asm/backend.45gs02` | `src/backend/45gs02.lisp` | Backend 45GS02 |
| `cl-asm/backend.65c02` | `src/backend/65c02.lisp` | Backend 65C02 (X16) |
| `cl-asm/backend.r65c02` | `src/backend/r65c02.lisp` | Backend R65C02 (Rockwell) |
| `cl-asm/backend.65816` | `src/backend/65816.lisp` | Backend WDC 65816 (SNES/Apple IIgs) |
| `cl-asm/backend.z80` | `src/backend/z80.lisp` | Backend Z80 (ZX Spectrum, MSX, CPC, ZX81) |
| `cl-asm/backend.m68k` | `src/backend/m68k.lisp` | Backend M68K (Amiga, Atari ST, Mac 68k) |
| `cl-asm/backend.i8080` | `src/backend/i8080.lisp` | Backend Intel 8080 (CP/M, Altair) |
| `cl-asm/backend.i8086` | `src/backend/i8086.lisp` | Backend Intel 8086/8088 (IBM PC, MS-DOS) |
| `cl-asm/lasm` | `src/frontend/lasm.lisp` | Frontend Lisp natif (.lasm) |
| `cl-asm/emit` | `src/emit/output.lisp` | Émetteurs de fichiers |
| `cl-asm/simulator.6502` | `src/simulator/6502.lisp` | Simulateur CPU 6502 |
| `cl-asm/disassembler.6502` | `src/disassembler/6502.lisp` | Désassembleur 6502 |
| `cl-asm/disassembler.45gs02` | `src/disassembler/45gs02.lisp` | Désassembleur 45GS02 |
| `cl-asm/disassembler.65c02` | `src/disassembler/65c02.lisp` | Désassembleur 65C02 / X16 |
| `cl-asm/debug-map` | `src/core/debug-map.lisp` | Table adresse→source-loc |
| `cl-asm/debugger.6502` | `src/debugger/6502.lisp` | Débogueur 6502 interactif |
| `cl-asm/profiler.6502` | `src/profiler/6502.lisp` | Profiler et tracer 6502/6510 |
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

### Mode Z80

Le parser est partagé entre le 6502 et le Z80. Une variable dynamique
contrôle l'ensemble de mnémoniques actif :

```lisp
cl-asm/parser:*z80-mode*   ; NIL par défaut (mode 6502)
```

`assemble-string-z80` et `assemble-file-z80` lient `*z80-mode*` à T
avant de parser. Cela évite que les mnémoniques communs (`INC`, `DEC`,
`AND`, `ADC`, `BIT`…) soient mal interprétés dans du code 6502.

Les opérandes Z80 utilisent `:direct "A"` pour les registres (pas `:register`),
`:indirect "HL"` pour `(HL)`, et `:indirect (:+ "IX" d)` pour `(IX+d)`.

### Mode Intel 8080

Le même mécanisme s'applique à l'Intel 8080 :

```lisp
cl-asm/parser:*i8080-mode*   ; NIL par défaut (mode 6502)
```

`assemble-string-i8080` et `assemble-file-i8080` lient `*i8080-mode*` à T
avant de parser. Le parsing des opérandes séparés par virgule réutilise
le chemin Z80 quand `*i8080-mode*` est T.

### Mode Intel 8086

```lisp
cl-asm/parser:*i8086-mode*   ; NIL par défaut
```

`assemble-string-i8086` et `assemble-file-i8086` lient `*i8086-mode*` à T.
Les opérandes mémoire utilisent la syntaxe `[base+index+disp]` ; `BYTE/WORD PTR [...]`
fixe l'indication de taille ; `SHORT expr` génère un opérande `JMP SHORT`.

---

## Module `cl-asm/backends`

Registre extensible de backends. Chaque backend s'enregistre via
`register-backend` en fin de son fichier source. Le script CLI et tout
autre outil interrogent le registre plutôt que de coder les cibles en dur.

### API exportée

```lisp
(cl-asm/backends:register-backend
  :6502                          ; keyword — identifiant interne
  '("6502" "mos6502" "c64")      ; alias CLI (insensibles à la casse)
  "CL-ASM/BACKEND.6502"          ; nom du package (chaîne)
  "ASSEMBLE-FILE"                ; nom de la fonction (chaîne)
  "MOS 6502 / Commodore 64"      ; description française
  "MOS 6502 / Commodore 64")     ; description anglaise

(cl-asm/backends:find-backend-by-alias "c64")   ; → entrée pour :6502
(cl-asm/backends:all-backends)                  ; → liste de toutes les entrées
(cl-asm/backends:backend-keyword entry)         ; → :6502
(cl-asm/backends:backend-aliases  entry)        ; → ("6502" "mos6502" "c64")
(cl-asm/backends:backend-package  entry)        ; → "CL-ASM/BACKEND.6502"
(cl-asm/backends:backend-function entry)        ; → "ASSEMBLE-FILE"
```

### Ajouter un nouveau backend

Créer `src/backend/monarch.lisp`, implémenter `assemble-file-monarch`, puis
ajouter en fin de fichier :

```lisp
(cl-asm/backends:register-backend
  :monarch '("monarch") "CL-ASM/BACKEND.MONARCH" "ASSEMBLE-FILE-MONARCH"
  "Mon architecture" "My architecture")
```

Ajouter le fichier dans `cl-asm.asd` et les trois scripts de test. Aucun
autre fichier n'a besoin d'être modifié.

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

## Module `cl-asm/backend.r65c02`

Superset du backend 65C02 pour le Rockwell R65C02.
Origine par défaut : `$0801`.

### Interface

```lisp
(cl-asm/backend.r65c02:assemble-r65c02        PROGRAM &key origin)
(cl-asm/backend.r65c02:assemble-string-r65c02 SOURCE  &key origin)
(cl-asm/backend.r65c02:assemble-file-r65c02   PATH    &key origin)
```

### Nouvelles instructions (32 instructions Rockwell)

| Groupe | Instructions | Opcode | Octets |
|---|---|---|---|
| Reset bit | `RMB0`…`RMB7` | `$n7` | 2 (ZP) |
| Set bit | `SMB0`…`SMB7` | `$n7+$80` | 2 (ZP) |
| Branche si bit à 0 | `BBR0`…`BBR7` | `$nF` | 3 (ZP + rel) |
| Branche si bit à 1 | `BBS0`…`BBS7` | `$nF+$80` | 3 (ZP + rel) |

`BBRn`/`BBSn` prennent **deux opérandes** séparés par une virgule : adresse
zero-page et cible de branche. Le parser les reconnaît via `rockwell-two-operands-p`.

---

## Module `cl-asm/backend.65816`

Backend WDC 65816 complet (SNES, Apple IIgs). Origine par défaut : `$8000`
(SNES LoROM bank 0).

### Interface

```lisp
(cl-asm/backend.65816:assemble-65816        PROGRAM &key origin)
(cl-asm/backend.65816:assemble-string-65816 SOURCE  &key origin)
(cl-asm/backend.65816:assemble-file-65816   PATH    &key origin)
```

### Modes d'adressage (en plus du 6502 de base)

| Mode | Syntaxe | Octets |
|---|---|---|
| `:absolute-long` | `LDA $123456` | 4 |
| `:absolute-long-x` | `LDA $123456,X` | 4 |
| `:dp-indirect-long` | `LDA [$10]` | 2 |
| `:dp-indirect-long-y` | `LDA [$10],Y` | 2 |
| `:stack-relative` | `LDA $10,S` | 2 |
| `:sr-indirect-y` | `LDA ($10,S),Y` | 2 |
| `:relative-long` | `BRL label` | 3 |
| `:block-move` | `MVN $7E,$7F` | 3 (deux octets banque) |

### Immédiat variable

L'accumulateur et les registres d'index peuvent opérer en mode 8 ou 16 bits,
contrôlé par les flags M et X du registre status.

| Flag | Instructions concernées | 8 bits | 16 bits |
|---|---|---|---|
| M (bit 5) | `LDA/STA/ADC/SBC/AND/ORA/EOR/CMP/BIT` | immédiat = 2 octets | immédiat = 3 octets |
| X (bit 4) | `LDX/LDY/CPX/CPY` | immédiat = 2 octets | immédiat = 3 octets |

### Directives de mode

| Directive | Effet |
|---|---|
| `.al` | Efface M — accumulateur 16 bits |
| `.as` | Met M — accumulateur 8 bits |
| `.xl` | Efface X — registres d'index 16 bits |
| `.xs` | Met X — registres d'index 8 bits |

L'état est suivi sur les deux passes via un cons mutable `(list m-long x-long)`.

### Instructions notables

| Instruction | Description | Octets |
|---|---|---|
| `JSL addr24` | Saut sous-routine long | 4 |
| `JML addr24` | Saut long | 4 |
| `RTL` | Retour de sous-routine long | 1 |
| `BRL label` | Branche longue (±32 Ko, offset 16 bits signé) | 3 |
| `PER label` | Push effective relative address | 3 |
| `PEA #nn` | Push effective absolute address (toujours 16 bits) | 3 |
| `MVN dst,src` | Block move negative (octets banque) | 3 |
| `MVP dst,src` | Block move positive (octets banque) | 3 |
| `REP #nn` | Reset bits du registre status | 2 |
| `SEP #nn` | Set bits du registre status | 2 |

---

## Module `cl-asm/backend.z80`

Backend Zilog Z80 complet (ZX Spectrum, MSX, CPC, ZX81). Origine par défaut : `$8000`.

### Interface

```lisp
(cl-asm/backend.z80:assemble-z80        PROGRAM &key origin)
(cl-asm/backend.z80:assemble-string-z80 SOURCE  &key origin)
(cl-asm/backend.z80:assemble-file-z80   PATH    &key origin)
```

### Préfixes d'instructions

| Préfixe | Instructions |
|---|---|
| (aucun) | Jeu principal : LD, ADD, ADC, SUB, SBC, AND, OR, XOR, CP, INC, DEC, JR, JP, CALL, RET, PUSH, POP, EX, DJNZ, RST, IN, OUT, IM, ops bloc |
| `$CB` | Rotations (RLC/RRC/RL/RR/SLA/SRA/SLL/SRL) + BIT/SET/RES |
| `$DD` | Opérations sur le registre IX |
| `$ED` | Étendu : ADD 16 bits, ops bloc (LDIR/LDDR/CPIR/CPDR…), groupes IN/OUT, IM |
| `$FD` | Opérations sur le registre IY |
| `$DD $CB` | Ops bit sur (IX+d) |
| `$FD $CB` | Ops bit sur (IY+d) |

### Modes d'adressage

| Mode | Syntaxe | Exemple |
|---|---|---|
| Implicite | — | `NOP`, `LDIR` |
| Registre direct | `A`, `B`, `HL`… | `LD A, B` |
| Immédiat octet | `n` | `LD A, $42` |
| Immédiat mot | `nn` | `LD HL, $1234` |
| Indirect registre | `(HL)`, `(BC)`, `(DE)` | `LD A, (HL)` |
| Indexé | `(IX+d)`, `(IY+d)` | `LD A, (IX+2)` |
| Mémoire directe | `(nn)` | `LD A, ($8000)` |
| Relatif | `e` (offset signé 8 bits) | `JR NZ, label` |
| Bit + registre | `n, r` | `BIT 3, A` |

---

## Module `cl-asm/backend.m68k`

Backend complet Motorola 68000 (Amiga, Atari ST, Mac 68k). Origine par défaut : `$0000`.

### Interface

```lisp
(cl-asm/backend.m68k:assemble-m68k        PROGRAM &key origin)
(cl-asm/backend.m68k:assemble-string-m68k SOURCE  &key origin)
(cl-asm/backend.m68k:assemble-file-m68k   PATH    &key origin)
```

### Encodage du champ EA

Le champ EA sur 6 bits vaut `(mode << 3) | reg`, intégré dans le mot opcode.

| Mode | Encodage | Syntaxe |
|---|---|---|
| Registre de données | `000 rrr` | `Dn` |
| Registre d'adresse | `001 rrr` | `An` |
| Indirect | `010 rrr` | `(An)` |
| Post-incrément | `011 rrr` | `(An)+` |
| Pré-décrément | `100 rrr` | `-(An)` |
| Déplacement | `101 rrr` | `d(An)` |
| Indexé | `110 rrr` | `d(An,Xi)` |
| Abs.W | `111 000` | `$nnnn.W` |
| Abs.L | `111 001` | `$nnnnnn` |
| Dépl. PC | `111 010` | `d(PC)` |
| Indexé PC | `111 011` | `d(PC,Xi)` |
| Immédiat | `111 100` | `#n` |

### Particularité de MOVE

MOVE inverse les bits EA destination dans le mot opcode :
bits 11-9 = dst_reg, bits 8-6 = dst_mode (contrairement à toutes les autres instructions).
Champ taille MOVE (bits 13-12) : `.B`→1, `.W`→3, `.L`→2.

### Sortie big-endian

`words->bytes` convertit une liste de mots 16 bits en octets big-endian.
Tous les mots d'extension (immédiats, déplacements, adresses) suivent le mot opcode.

---

## Module `cl-asm/backend.i8080`

Backend Intel 8080 complet (CP/M, Altair). Origine par défaut : `$0100`.

### Interface

```lisp
(cl-asm/backend.i8080:assemble-i8080        PROGRAM &key origin)
(cl-asm/backend.i8080:assemble-string-i8080 SOURCE  &key origin)
(cl-asm/backend.i8080:assemble-file-i8080   PATH    &key origin)
```

### Encodage des registres

| Registre 8 bits | Code | Paire | Code |
|---|---|---|---|
| B | 0 | BC (B) | 0 |
| C | 1 | DE (D) | 1 |
| D | 2 | HL (H) | 2 |
| E | 3 | SP | 3 |
| H | 4 | PSW (PUSH/POP seulement) | 3 |
| L | 5 | | |
| M (indirect HL) | 6 | | |
| A | 7 | | |

### Encodages clés

| Instruction | Encodage |
|---|---|
| `MOV d, s` | `$40 \| (d << 3) \| s` |
| `MVI r, n` | `$06 \| (r << 3)` + imm8 |
| `LXI rp, nn` | `$01 \| (rp << 4)` + imm16-LE |
| `INR r` | `$04 \| (r << 3)` |
| `DCR r` | `$05 \| (r << 3)` |
| `ADD/ADC/SUB/SBB/ANA/XRA/ORA/CMP r` | base + r |
| `JMP/CALL/Jcc/Ccc nn` | opcode + addr16-LE |
| `RST n` | `$C7 \| (n << 3)` |

### Tailles d'instruction

| Taille | Mnémoniques |
|---|---|
| 3 octets | LXI, LDA, STA, LHLD, SHLD, JMP, CALL, JNZ, JZ, JNC, JC, JPO, JPE, JP, JM, CNZ, CZ, CNC, CC, CPO, CPE, CP, CM |
| 2 octets | MVI, ADI, ACI, SUI, SBI, ANI, XRI, ORI, CPI, IN, OUT |
| 1 octet | tous les autres |

---

## Module `cl-asm/backend.i8086`

Backend Intel 8086/8088 mode réel complet (IBM PC, MS-DOS). Origine par défaut : `$0000`.

### Interface

```lisp
(cl-asm/backend.i8086:assemble-i8086        PROGRAM &key origin)
(cl-asm/backend.i8086:assemble-string-i8086 SOURCE  &key origin)
(cl-asm/backend.i8086:assemble-file-i8086   PATH    &key origin)
```

### Encodage des registres

| 16 bits | Code | 8 bits | Code | Segment | Code |
|---------|------|--------|------|---------|------|
| AX | 0 | AL | 0 | ES | 0 |
| CX | 1 | CL | 1 | CS | 1 |
| DX | 2 | DL | 2 | SS | 2 |
| BX | 3 | BL | 3 | DS | 3 |
| SP | 4 | AH | 4 | | |
| BP | 5 | CH | 5 | | |
| SI | 6 | DH | 6 | | |
| DI | 7 | BH | 7 | | |

### Modes d'adressage ModRM (mod≠11)

| rm | Adressage | Note |
|----|-----------|------|
| 000 | [BX+SI] | |
| 001 | [BX+DI] | |
| 010 | [BP+SI] | |
| 011 | [BP+DI] | |
| 100 | [SI] | |
| 101 | [DI] | |
| 110 | [BP] / adresse directe | mod=00 → adresse directe 16 bits |
| 111 | [BX] | |

Déplacements : mod=00 → aucun (sauf rm=110 = adresse directe), mod=01 → 8 bits, mod=10 → 16 bits.
Ce backend utilise toujours mod=10 pour tout déplacement non nul (stabilité des tailles passe-1).

---

## Module `cl-asm/lasm`

Frontend Lisp natif. Les fichiers `.lasm` sont du Common Lisp valide
qui s'exécute dans un contexte où chaque mnémonique est une fonction.
Toute la puissance de CL est disponible : `let`, `dotimes`, `loop`,
`defun`, `defmacro`, etc.

**Cibles supportées :** toutes les architectures — `:6502` (défaut),
`:45gs02`/`:mega65`, `:65c02`/`:x16`, `:r65c02`,
`:65816`/`:snes`/`:apple2gs`, `:z80`/`:spectrum`/`:msx`/`:cpc`,
`:m68k`/`:amiga`/`:atari`, `:i8080`/`:8080`/`:cpm`/`:altair`,
`:i8086`/`:8086`/`:8088`/`:ibmpc`/`:msdos`/`:x86-16`.

**Symboles CL redéfinis :** `fill`, `bit`, `sec`, `and`, `map` sont
masqués par des instructions assembleur dans le package `cl-asm/lasm`.
Utilisez `cl:fill`, `cl:and`, etc. pour accéder aux fonctions CL
d'origine si nécessaire.

### Interface

```lisp
(cl-asm/lasm:assemble-lasm-string SOURCE &key origin target)
(cl-asm/lasm:assemble-lasm        PATH   &key origin target)
(cl-asm/lasm:load-lasm-string     SOURCE)  ; → IR-PROGRAM
(cl-asm/lasm:load-lasm            PATH)    ; → IR-PROGRAM
```

`target` : `:6502` (défaut), `:45gs02`/`:mega65`, `:65c02`/`:x16`,
`:r65c02`, `:65816`/`:snes`, `:z80`/`:spectrum`/`:msx`/`:cpc`,
`:m68k`/`:amiga`/`:atari`, `:i8080`/`:8080`/`:cpm`/`:altair`.

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
(text "HELLO")        ; .text (sans octet nul)
(ascii-z "HELLO")     ; .asciiz — chaîne + octet nul final
(pascal-str "HELLO")  ; .pascalstr — octet de longueur + chaîne
(align 256)           ; .align
(pad-to #xC000)       ; .padto — remplit jusqu'à l'adresse cible
(assert-pc #x0900)    ; .assertpc — erreur si PC ≠ adresse
(defstruct-asm s :x (:hp 2)) ; offsets auto → S.X=0, S.HP=1, S.SIZE=3
(defenum color :black :white) ; → COLOR.BLACK=0, COLOR.WHITE=1, COLOR.COUNT=2
(include-binary "spr.bin")   ; inclut un fichier binaire brut (offset/count optionnels)
(section :data)       ; .section
```

### Macros d'aide

```lisp
(genlabel)                               ; → keyword de label anonyme unique
(with-label nom &body)                   ; place le label nom, puis émet le corps
(lasm-if cond-fn t-lbl f-lbl &body)     ; structure if/else conditionnelle
```

`(lasm-if cond-fn ...)` émet un label de fin généré automatiquement et
appelle `cond-fn` avec ce label pour émettre la branche conditionnelle.
`t-label` et `f-label` sont des paramètres de documentation, non utilisés
à l'exécution dans la version actuelle.

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

## Module `cl-asm/simulator.6502`

Simulateur CPU MOS 6502. Prend un vecteur d'octets assemblé en entrée,
exécute les instructions pas à pas dans un espace mémoire virtuel de 64 Ko.

### Interface

```lisp
;; Construction
(make-cpu)                              ; → CPU avec 64 Ko de mémoire à zéro
(reset-cpu CPU &key origin)             ; réinitialise les registres, PC ← origin
(load-program CPU BYTES &key origin)    ; copie les octets en mémoire, PC ← origin

;; Mémoire
(mem-read  CPU ADDR)                    ; → (unsigned-byte 8)
(mem-write CPU ADDR VAL)
(mem-read16 CPU ADDR)                   ; → mot 16 bits little-endian

;; Exécution
(step-cpu CPU)                          ; exécute une instruction → CPU
(run-cpu  CPU &key max-steps)           ; → (values CPU :brk|:step-limit)

;; Accesseurs de registres
(cpu-a CPU)  (cpu-x CPU)  (cpu-y CPU)
(cpu-pc CPU) (cpu-sp CPU) (cpu-p CPU)  (cpu-cycles CPU)

;; Lecteurs de flags (retournent T/NIL)
(flag-c CPU) (flag-z CPU) (flag-i CPU) (flag-d CPU)
(flag-b CPU) (flag-v CPU) (flag-n CPU)

;; Constantes de flags
+flag-c+ +flag-z+ +flag-i+ +flag-d+ +flag-b+ +flag-5+ +flag-v+ +flag-n+
```

### Conditions

| Condition | Déclenchée quand |
|---|---|
| `cpu-break` | Instruction BRK exécutée |
| `cpu-illegal-opcode` | Opcode inconnu |
| `cpu-step-limit` | `max-steps` atteint sans BRK |

### Couverture du jeu d'instructions

| Groupe | Nombre | Instructions |
|---|---|---|
| Implicites | 23 | NOP BRK TAX TXA TAY TYA TSX TXS PHA PLA PHP PLP INX INY DEX DEY CLC SEC CLI SEI CLV CLD SED |
| Load/Store | 31 | LDA×8 LDX×5 LDY×5 STA×7 STX×3 STY×3 |
| ALU | 56 | ADC×8 SBC×8 AND×8 ORA×8 EOR×8 CMP×8 CPX×3 CPY×3 BIT×2 |
| Décalages/Rotations | 28 | ASL×5 LSR×5 ROL×5 ROR×5 INC×4 DEC×4 |
| Sauts | 14 | JMP abs, JMP(ind)*, JSR, RTS, RTI, BCC BCS BEQ BNE BMI BPL BVC BVS |
| **Total** | **152** | |

*JMP indirect reproduit le bug de traversée de page du 6502 original.

### Comptage des cycles

- Pénalité de traversée de page : +1 cycle pour les instructions de lecture indexées (LDA/LDX/LDY abs,X/Y, ADC/SBC/etc. abs,X/Y)
- Instructions d'écriture (STA abs,X/Y, STA (ind),Y) : nombre de cycles fixe
- Branches : 2 cycles non prises, 3 cycles prises même page, 4 cycles prises page différente

---

## Module `cl-asm/linker`

Linker modulaire en mémoire pour la famille 6502. Plusieurs fichiers sources
peuvent être assemblés en un seul binaire avec une table de symboles partagée —
les labels définis dans un fichier sont résolus dans tous les autres.

### Interface

```lisp
;; Emballer un IR-PROGRAM dans un link-unit
(link-unit-from-program "main" (parse-file "main.asm") :6502) ; → link-unit

;; Fusionner les units → vecteur d'octets unique
(link (list u1 u2) :origin #x0800) ; → (vector (unsigned-byte 8))

;; Enregistrement d'un backend (une fois par backend)
(register-linker-backend :6502 '("6502" "mos6502")
  #'pass-1 #'pass-2 "MOS 6502")

;; Requêtes de registre
(find-linker-backend :6502)   ; → linker-backend-entry ou NIL
(all-linker-backends)         ; → liste de toutes les entrées

;; Accesseurs
(link-unit-name     u)        ; → string
(link-unit-target   u)        ; → :6502 | :6510 | :65c02 | :45gs02
(link-unit-sections u)        ; → liste de ir-section
```

### Backends enregistrés

| Mot-clé | Alias |
|---|---|
| `:6502` | `"6502"` `"mos6502"` |
| `:6510` | `"6510"` `"mos6510"` `"c64"` |
| `:65c02` | `"65c02"` `"x16"` |
| `:45gs02` | `"45gs02"` `"mega65"` |

---

## Module `cl-asm/linker-script`

Linker script multi-segments. Place des segments à des adresses distinctes
avec une table de symboles partagée — les références croisées inter-segments
(JSR, branchements, constantes `.equ`) sont résolues automatiquement.

### Interface

```lisp
;; Décrire un segment
(make-script-segment :name "main" :at #x0800 :units (list u1 u2))
;; → script-segment

;; Assembler les segments → liste de résultats
(link-segments (list seg1 seg2) :target :6502) ; → (list script-result …)

;; Aplatir en binaire contigu
(multiple-value-bind (bytes base)
    (segments->flat-binary results :fill #x00)
  ...)
;; bytes → (vector (unsigned-byte 8))
;; base  → adresse la plus basse parmi tous les résultats

;; Accesseurs — script-segment
(script-segment-name  s)  ; → string
(script-segment-at    s)  ; → entier (adresse de chargement)
(script-segment-units s)  ; → liste de link-unit
(script-segment-fill  s)  ; → (unsigned-byte 8)

;; Accesseurs — script-result
(script-result-name    r) ; → string
(script-result-address r) ; → entier
(script-result-bytes   r) ; → (vector (unsigned-byte 8))
```

### Fonctionnement

```
link-segments :
  1. Pour chaque segment (dans l'ordre) :
       PC ← segment.at
       appel pass-1(segment.sections, symtable-partagée, segment.at)
       → les labels de tous les segments sont enregistrés dans la table commune
  2. begin-pass-2(symtable-partagée)
  3. Pour chaque segment (dans l'ordre) :
       PC ← segment.at
       appel pass-2(segment.sections, symtable-partagée, segment.at)
       → vecteur d'octets pour ce segment
  Retourne : liste de script-result, un par segment

segments->flat-binary :
  base = min(result.address)
  buf  = vecteur de taille (max(result.address + len) − base) rempli de fill
  Pour chaque result : replace(buf, result.bytes, offset = result.address − base)
  Retourne : (values buf base)
```

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
- **Compatibilité SBCL/CLISP/ECL** : tester sur les trois à chaque session.
  CLISP est plus strict sur certains points du standard ANSI.
