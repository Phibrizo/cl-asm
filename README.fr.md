# cl-asm — Assembleur multi-architecture en Common Lisp

Assembleur modulaire écrit en Common Lisp. Cibles actuelles : **6502**
(Commodore 64, Apple II…), **45GS02** (Mega65) et **65C02**
(Commander X16). L'architecture est pensée pour accueillir d'autres
backends (Z80, 68000…) sans modifier le cœur du projet.

## Version

**Version courante : 0.1.3**

```
cl-asm/version:+version+         ; → "0.1.3"
cl-asm/version:+version-major+   ; → 0
cl-asm/version:+version-minor+   ; → 1
cl-asm/version:+version-patch+   ; → 2
(cl-asm/version:version-string)  ; → "0.1.3"
```

---

## État du projet

| Module | État | Tests |
| --- | --- | --- |
| IR (Représentation intermédiaire) | ✓ | — |
| Évaluateur d'expressions | ✓ | 129 |
| Table des symboles | ✓ | 59 |
| Lexer classique | ✓ | 119 |
| Parser classique (ca65-like) | ✓ | 84 |
| Backend 6502 | ✓ | 82 |
| Backend 45GS02 | ✓ | 80 |
| Backend 65C02 (X16) | ✓ | 41 |
| Backend R65C02 (Rockwell) | ✓ | 117 |
| Émetteurs BIN / PRG / listing | ✓ | — |
| Macros textuelles | ✓ | 27 |
| Assemblage conditionnel | ✓ | 27 |
| Frontend .lasm (Lisp natif) | ✓ | 58 |

**Total : 829 tests, 0 KO, 0 warnings — SBCL 2.6.2 et CLISP 2.49.95+**

---

## Prérequis

* **SBCL** 2.x (recommandé), **CLISP** 2.49.95+, ou **ECL** 21.x+
* **ASDF** 3.x (inclus dans SBCL)
* **Quicklisp** (optionnel, recommandé)

Installation de SBCL :

```
sudo pacman -S sbcl      # Arch / Manjaro
sudo apt install sbcl    # Debian / Ubuntu
sudo dnf install sbcl    # Fedora
brew install sbcl        # macOS
```

Installation de ECL :

```
sudo pacman -S ecl       # Arch / Manjaro
sudo apt install ecl     # Debian / Ubuntu
sudo dnf install ecl     # Fedora
brew install ecl         # macOS
```

---

## Structure du projet

```
cl-asm/
├── cl-asm.asd              définition ASDF du système
├── bootstrap.lisp          chargement manuel (sans ASDF)
├── run-tests.sh            script de tests SBCL
├── run-tests-clisp.sh      script de tests CLISP
├── cl-asm                  script ligne de commande
├── acme2clasm              convertisseur ACME → cl-asm (wrapper shell)
├── acme2clasm.lisp         convertisseur ACME → cl-asm (moteur Common Lisp)
├── src/
│   ├── core/
│   │   ├── version.lisp        numéro de version
│   │   ├── backends.lisp       registre extensible de backends
│   │   ├── ir.lisp             représentation intermédiaire
│   │   ├── expression.lisp     évaluateur d'expressions
│   │   └── symbol-table.lisp   table des symboles, 2 passes
│   ├── frontend/
│   │   ├── classic-lexer.lisp  tokeniseur (ca65-like)
│   │   ├── classic-parser.lisp parser → IR, macros, conditionnel
│   │   └── lasm.lisp           frontend Lisp natif (.lasm)
│   ├── backend/
│   │   ├── 6502.lisp           encodeur 6502 (56 mnémoniques)
│   │   ├── 45gs02.lisp         encodeur 45GS02 (superset 6502)
│   │   ├── 65c02.lisp          encodeur 65C02 (superset 6502, X16)
│   │   └── r65c02.lisp         encodeur R65C02 (Rockwell, superset 65C02)
│   └── emit/
│       └── output.lisp         émetteurs BIN, PRG, listing
├── tests/
│   ├── run-tests.lisp
│   ├── test-expression.lisp
│   ├── test-symbol-table.lisp
│   ├── test-lexer.lisp
│   ├── test-parser.lisp
│   ├── test-6502.lisp
│   ├── test-65c02.lisp
│   ├── test-r65c02.lisp
│   ├── test-45gs02.lisp
│   ├── test-macros.lisp
│   ├── test-conditional.lisp
│   └── test-lasm.lisp
└── examples/
    ├── c64-raster.asm          raster bar C64 (syntaxe classique)
    ├── mega65-hello.lasm       hello world Mega65 (syntaxe .lasm)
    ├── mega65-minimal.lasm     programme Mega65 minimaliste
    ├── x16-hello.asm           hello world Commander X16 (65C02)
    ├── x16-minimal.asm         programme X16 minimaliste
    ├── x16-debug.asm           programme de diagnostic X16 (BRK)
    └── README.md               guide d'assemblage des exemples
```

---

## Lancer les tests

Trois méthodes coexistent — elles produisent toutes la même sortie.

### Méthode 1 — scripts shell (sans ASDF)

```
cd cl-asm/
./run-tests.sh          # SBCL
./run-tests-clisp.sh    # CLISP
```

### Méthode 2 — ASDF depuis un REPL

```
;; Lance les tests en une commande
(asdf:test-system "cl-asm")
```

Pour forcer la recompilation complète :

```
(asdf:load-system "cl-asm" :force t)
(asdf:test-system "cl-asm")
```

### Méthode 3 — chargement et test séparés (recommandé en développement)

```
(ql:quickload "cl-asm/tests")
(cl-asm/test:run-all-tests)
```

Résultat attendu :

```
--- Core ---
=== symbol-table :  59 OK, 0 KO
=== expression   : 129 OK, 0 KO
--- Frontend ---
=== lexer        : 119 OK, 0 KO
=== parser       :  84 OK, 0 KO
=== macros       :  27 OK, 0 KO
=== conditionnel :  27 OK, 0 KO
=== lasm         :  58 OK, 0 KO
--- Backends ---
=== 6502         :  82 OK, 0 KO
=== 65c02        :  41 OK, 0 KO
=== r65c02       : 117 OK, 0 KO
=== 45gs02       :  80 OK, 0 KO
-------------------------------
=== TOTAL        : 829 OK, 0 KO sur 829 tests
```

---

## Installation avec Quicklisp

### Installer Quicklisp (une seule fois)

```
curl -O https://beta.quicklisp.org/quicklisp.lisp
sbcl --load quicklisp.lisp \
     --eval "(quicklisp-quickstart:install)" \
     --eval "(ql:add-to-init-file)" \
     --quit
```

### Enregistrer cl-asm dans Quicklisp

```
ln -s /chemin/vers/cl-asm ~/quicklisp/local-projects/cl-asm
```

Puis dans le REPL :

```
(ql:register-local-projects)
```

### Charger et tester depuis n'importe quel REPL

```
(ql:quickload "cl-asm")           ; charger
(ql:quickload "cl-asm/tests")     ; charger avec les tests
(cl-asm/test:run-all-tests)       ; lancer les tests
(asdf:test-system "cl-asm")       ; tout en une commande
```

### Workflow de développement typique

```
(ql:quickload "cl-asm/tests")
(cl-asm/test:run-all-tests)

;; Après modification de src/backend/6502.lisp :
(asdf:load-system "cl-asm")       ; recharge uniquement ce qui a changé
(cl-asm/test:run-all-tests)
```

---

## Utilisation programmatique

### Assembler du code 6502

```
(ql:quickload "cl-asm")

;; Assembler → vecteur d'octets
(cl-asm/backend.6502:assemble-string
  ".org $0801
   LDA #$00
   STA $D020
   RTS")
;; => #(169 0 141 32 208 96)

;; Assembler un fichier
(cl-asm/backend.6502:assemble-file "programme.asm" :origin #x0801)

;; Écrire un fichier PRG (Commodore 64)
(let ((bytes (cl-asm/backend.6502:assemble-string
               ".org $0801
                LDA #$00
                STA $D020
                RTS")))
  (cl-asm/emit:write-prg bytes "/tmp/demo.prg" :load-address #x0801))

;; Écrire un fichier BIN (binaire brut, sans header)
(cl-asm/emit:write-bin bytes "/tmp/demo.bin")
```

### Assembler du code 45GS02 (Mega65)

```
(cl-asm/backend.45gs02:assemble-string-45gs02
  ".org $2001
   LDZ #$00
   LDQ ($20),Z
   STQ ($30),Z
   RTS")
```

### Assembler du code 65C02 (Commander X16)

```
(cl-asm/backend.65c02:assemble-string-65c02
  ".org $0801
   BRA start
   start:
   STZ $10
   PHY
   PLY
   RTS")
```

### Assembler du code R65C02 (Rockwell — manipulation de bits)

```
(cl-asm/backend.r65c02:assemble-string-r65c02
  ".org $1000
   SMB3 $10        ; mettre le bit 3 de l'adresse $10 à 1
   BBR3 $10, skip  ; branche si le bit 3 est à 0 (non pris ici)
   RMB3 $10        ; remettre le bit 3 à 0
   skip:
   RTS")
```

### Pipeline complet : parse puis assemble

```
(let* ((program (cl-asm/parser:parse-string
                  "start:
                   LDA #$00
                   BNE start"))
       (bytes (cl-asm/backend.6502:assemble program :origin #x0801)))
  (format t "~D octets~%" (length bytes)))
```

---

## Formats de sortie

| Format | Fonction | Description |
| --- | --- | --- |
| BIN | `write-bin` | Binaire brut, sans header |
| PRG | `write-prg` | Format C64 : 2 octets header LE + binaire |
| LST | `write-listing` | Listing annoté : adresse |

---

## Syntaxe assembleur supportée

```
; Commentaires avec ;  ou  // (style C)

SCREEN  = $0400            ; constante
COLS    = 40

        .org  $0801        ; origine
        .byte $0B, $08     ; octets littéraux
        .word $C000        ; mots 16 bits (little-endian)
        .text "HELLO"      ; chaîne ASCII
        .fill 10, $00      ; remplissage
        .align 256         ; alignement

start:                     ; label local
main::                     ; label global (ca65-style)
1:      bne 1-             ; label numérique + ref backward
        bne 1+             ; ref forward

; Modes 6502
        lda #$FF           ; immédiat
        lda $10            ; zero-page
        lda $10,X          ; zero-page,X
        lda $1234          ; absolu
        lda ($00,X)        ; (indirect,X)
        lda ($00),Y        ; (indirect),Y
        lsr A              ; accumulateur
        jmp ($FFFC)        ; indirect

; Modes 65C02 supplémentaires
        bra label          ; branche inconditionnelle
        stz $10            ; store zero
        phx                ; push X
        inc A              ; incrément accumulateur
        lda ($10)          ; indirect ZP sans index

; Instructions R65C02 supplémentaires (Rockwell, manipulation de bits)
        rmb3 $10           ; reset bit 3 de $10
        smb3 $10           ; set bit 3 de $10
        bbr3 $10, label    ; branche si bit 3 de $10 est à 0
        bbs3 $10, label    ; branche si bit 3 de $10 est à 1

; Modes 45GS02 supplémentaires
        lda ($00),Z        ; (indirect),Z
        lda $1234,Z        ; absolu,Z
        lda [$00]          ; [indirect 32 bits]
        ldq ($20),Z        ; registre Q 32 bits

; Macros textuelles
.macro PUSH_AXY
    PHA
    TXA
    PHA
    TYA
    PHA
.endmacro

; Assemblage conditionnel
; Note : les forward-references ne sont PAS supportées dans .if
DEBUG    = 1
PLATFORM = 64

.if DEBUG
    LDA #$01
    STA $0400
.endif

.if PLATFORM = 64
    LDA #<C64_SCREEN
.else
    LDA #<M65_SCREEN
.endif

; Expressions
        lda #<VEC          ; octet bas
        lda #>VEC          ; octet haut
        lda BASE+1
        lda #(COLS * 2 + 1)
```

---

## Ligne de commande

```
./cl-asm programme.asm               # → programme.prg (6502, $0801)
./cl-asm programme.asm -o demo.prg   # fichier de sortie explicite
./cl-asm programme.asm -o demo.bin --format bin
./cl-asm programme.asm --origin 0xC000
./cl-asm mega65.lasm --target 45gs02
./cl-asm prog.asm --target x16
./cl-asm prog.asm --target r65c02
./cl-asm programme.asm -v            # mode verbose
./cl-asm --help
```

### Options

| Option | Description | Défaut |
| --- | --- | --- |
| `-o FILE` | Fichier de sortie | même nom, ext .prg |
| `-f FORMAT` | `prg` ou `bin` | `prg` |
| `--origin ADDR` | Adresse d'origine (ex: `0x0801`) | `0x0801` |
| `-t TARGET` | `6502` (aussi `mos6502`, `c64`), `45gs02` (aussi `mega65`), `x16` (aussi `65c02`, `commander-x16`), `r65c02` (aussi `rockwell`) | `6502` |
| `-v` | Mode verbose | — |

La cible est détectée automatiquement depuis les premières lignes du source :

* `.asm` : `; target: 45gs02` ou `; target: x16`
* `.lasm` : `(target :45gs02)`

---

## Frontend .lasm — syntaxe Lisp native

```
(ql:quickload "cl-asm")

(cl-asm/lasm:assemble-lasm-string
  "(org #x0801)
   (lda :imm 0)
   (sta #xD020)
   (rts)"
  :origin #x0801)

(cl-asm/lasm:assemble-lasm "/path/to/prog.lasm" :origin #x0801)
(cl-asm/lasm:assemble-lasm-string src :target :45gs02 :origin #x2001)
```

### Convention des modes d'adressage

Sans keyword — mode déduit de la valeur :

```
(lda #x10)        ; LDA $10   (zero-page, valeur ≤ 255)
(lda #x1234)      ; LDA $1234 (absolu, valeur > 255)
(lda 'screen)     ; LDA SCREEN (symbole)
```

Avec keyword — mode explicite :

```
(lda :imm #xFF)   ; LDA #$FF  (immédiat)
(lda :x   #x10)   ; LDA $10,X (indexé X)
(lda :ind #xFFFC) ; JMP ($FFFC) (indirect)
(lda :ix  #x00)   ; LDA ($00,X)
(lda :iy  #xB0)   ; LDA ($B0),Y
(lda :abs #x10)   ; LDA $0010 (absolu forcé)
(lda :zp  #x10)   ; LDA $10   (zero-page forcée)
(lsr :a)          ; LSR A     (accumulateur)
```

### Exemples avec Lisp natif

```
(dotimes (i 8)
  (lda :imm i)
  (sta (+ #xD800 i)))

(defun set-border (col)
  (lda :imm col)
  (sta #xD020))
```

---

## Convertisseur ACME

Le convertisseur `acme2clasm` est écrit en Common Lisp pur — aucune
dépendance à Python. Il fonctionne avec SBCL, CLISP ou ECL, selon ce
qui est disponible sur votre système.

```
./acme2clasm source.s              # → source.asm
./acme2clasm source.s -o out.asm
./acme2clasm source.s --report     # affiche les avertissements
```

Conversions : `!addr` → constante, `!byte`/`!8` → `.byte`,
`!word`/`!16` → `.word`, `!pet` → `.byte` avec codes explicites,
`!fill` → `.fill`, `!macro`/`!if` → `.macro`/`.if`,
`!cpu m65` → `; target: 45gs02`, `!cpu 65c02` → `; target: x16`.
Les caractères non-ASCII des commentaires sont normalisés en ASCII.

Le convertisseur se compose de deux fichiers :

* `acme2clasm` — wrapper shell, détecte automatiquement SBCL / CLISP / ECL
* `acme2clasm.lisp` — moteur de conversion (Common Lisp ANSI standard)

---

## Note sur les fichiers `.fasl`

SBCL compile les sources en `.fasl` lors du premier chargement ASDF.
En cas d'erreur après modification des déclarations de packages :

```
find cl-asm/ -name "*.fasl" -delete
```

---

## Note sur l'encodage

Tous les fichiers source utilisent UTF-8. La ligne `; -*- coding: utf-8 -*-`
en tête de chaque fichier est nécessaire pour SBCL et les éditeurs
(Emacs/SLIME, VS Code/SLY).

---

## Licence

MIT — voir [LICENSE](https://github.com/Phibrizo/cl-asm/blob/main/LICENSE).
