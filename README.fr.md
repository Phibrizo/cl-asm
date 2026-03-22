# cl-asm — Assembleur multi-architecture en Common Lisp

Assembleur modulaire écrit en Common Lisp. Cibles actuelles : **6502**
(Commodore 64, Apple II…), **45GS02** (Mega65), **65C02**
(Commander X16), **R65C02** (Rockwell), **WDC 65816**
(SNES, Apple IIgs), **Z80** (ZX Spectrum, MSX, CPC, ZX81)
et **M68K** (Amiga, Atari ST, Mac 68k).
L'architecture est pensée pour accueillir d'autres backends
sans modifier le cœur du projet.

## Version

**Version courante : 0.4.0**

```
cl-asm/version:+version+         ; → "0.4.0"
cl-asm/version:+version-major+   ; → 0
cl-asm/version:+version-minor+   ; → 4
cl-asm/version:+version-patch+   ; → 0
(cl-asm/version:version-string)  ; → "0.4.0"
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
| Backend WDC 65816 (SNES/Apple IIgs) | ✓ | 104 |
| Backend Z80 (ZX Spectrum, MSX, CPC, ZX81) | ✓ | 191 |
| Parser M68K | ✓ | 85 |
| Backend M68K (Amiga, Atari ST, Mac 68k) | ✓ | 139 |
| Émetteurs BIN / PRG / listing | ✓ | — |
| Macros textuelles | ✓ | 27 |
| Assemblage conditionnel | ✓ | 27 |
| Frontend .lasm (Lisp natif) | ✓ | 58 |

**Total : 1348 tests, 0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+ et ECL 21.x+**

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
├── run-tests-ecl.sh        script de tests ECL
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
│   │   ├── r65c02.lisp         encodeur R65C02 (Rockwell, superset 65C02)
│   │   ├── 65816.lisp          encodeur WDC 65816 (SNES/Apple IIgs, 24-bit)
│   │   ├── z80.lisp            encodeur Z80 (ZX Spectrum, MSX, CPC, ZX81)
│   │   └── m68k.lisp           encodeur M68K (Amiga, Atari ST, Mac 68k)
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
│   ├── test-lasm.lisp
│   ├── test-65816.lisp
│   ├── test-z80.lisp
│   ├── test-m68k-parser.lisp
│   └── test-m68k.lisp
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
./run-tests-ecl.sh      # ECL
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
=== 65816        : 104 OK, 0 KO
=== z80          : 191 OK, 0 KO
--- Parsers architectures ---
=== m68k-parser  :  85 OK, 0 KO
=== m68k         : 139 OK, 0 KO
-------------------------------
=== TOTAL        : 1348 OK, 0 KO sur 1348 tests
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

### Assembler du code WDC 65816 (SNES / Apple IIgs)

```
;; Origine par défaut : $8000 (SNES LoROM bank 0)
(cl-asm/backend.65816:assemble-string-65816
  ".org $8000
   .al             ; accumulateur en mode 16 bits
   LDA #$1234      ; immédiat 16 bits (3 octets)
   STA $7E0000     ; stockage à une adresse longue 24 bits
   JSL $008000     ; saut sous-routine long (24 bits)
   RTL")

;; Mode 8 bits (par défaut au reset)
(cl-asm/backend.65816:assemble-string-65816
  ".org $8000
   SEP #$30        ; flags M et X à 1 (mode 8 bits)
   LDA #$42        ; immédiat 8 bits
   STA $00,X       ; zero-page,X
   RTS")

;; Block move
(cl-asm/backend.65816:assemble-string-65816
  ".org $8000
   MVN $7E,$7F     ; copie de la banque $7F vers la banque $7E
   RTS")
```

### Assembler du code Z80 (ZX Spectrum / MSX / CPC)

```
(cl-asm/backend.z80:assemble-string-z80
  ".org $8000
   LD A, $42
   LD (HL), A
   INC HL
   DJNZ loop
   loop:
   RET")
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
        .padto $C000       ; remplit jusqu'à l'adresse absolue (avec $00)
        .padto $C000, $FF  ; remplit jusqu'à l'adresse absolue (avec $FF)
        .assertpc $C000    ; erreur si PC ≠ $C000
        .asciiz "HELLO"   ; chaîne ASCII + octet nul final
        .pascalstr "HI"   ; octet de longueur + chaîne

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

; Modes et instructions WDC 65816 supplémentaires
        lda $123456        ; absolu long (adresse 24 bits)
        lda $123456,X      ; absolu long,X
        lda [$10]          ; indirect long DP
        lda [$10],Y        ; indirect long DP,Y
        lda $10,S          ; stack-relative
        lda ($10,S),Y      ; (stack-relative indirect),Y
        jsl $008000        ; saut sous-routine long (24 bits)
        jml $008000        ; saut long (24 bits)
        brl label          ; branche longue (offset 16 bits)
        mvn $7e,$7f        ; block move negative (dst,src)
        mvp $7e,$7f        ; block move positive (dst,src)
        pea #$1234         ; push effective address (16 bits)
        rep #$30           ; reset bits du registre status
        sep #$30           ; set bits du registre status

; Directives de mode 65816
        .al                ; accumulateur 16 bits (efface M)
        .as                ; accumulateur 8 bits (met M)
        .xl                ; index 16 bits (efface X)
        .xs                ; index 8 bits (met X)

; Modes 45GS02 supplémentaires
        lda ($00),Z        ; (indirect),Z
        lda $1234,Z        ; absolu,Z
        lda [$00]          ; [indirect 32 bits]
        ldq ($20),Z        ; registre Q 32 bits

; Modes Z80 (utiliser --target z80)
        ld a, $42       ; immédiat
        ld (hl), a      ; indirect registre
        ld a, (ix+2)    ; indexé (IX+d) ou (IY+d)
        ld a, ($8000)   ; mémoire directe
        push bc         ; paire de registres
        bit 3, a        ; test bit (préfixe CB)
        set 3, a        ; mise à 1 d'un bit (préfixe CB)
        res 3, a        ; mise à 0 d'un bit (préfixe CB)
        jr nz, label    ; branche relative
        djnz loop       ; décrémente B, saute si non nul
        ldir            ; copie de bloc (préfixe ED)
        in a, ($FE)     ; lecture port E/S
        out ($FE), a    ; écriture port E/S

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
./cl-asm snes.asm --target 65816     # WDC 65816 / SNES
./cl-asm prog.asm --target z80       # Z80 / ZX Spectrum / MSX
# Assembler un fichier source ACME directement (sans conversion)
./cl-asm terminal.asm --target x16
./cl-asm programme.asm -v            # mode verbose
./cl-asm --help
```

### Options

| Option | Description | Défaut |
| --- | --- | --- |
| `-o FILE` | Fichier de sortie | même nom, ext .prg |
| `-f FORMAT` | `prg` ou `bin` | `prg` |
| `--origin ADDR` | Adresse d'origine (ex: `0x0801`) | `0x0801` |
| `-t TARGET` | `6502` (aussi `mos6502`, `c64`), `45gs02` (aussi `mega65`), `x16` (aussi `65c02`, `commander-x16`), `r65c02` (aussi `rockwell`), `65816` (aussi `wdc65816`, `snes`, `apple2gs`), `z80` (aussi `z80cpu`, `zxspectrum`, `spectrum`, `cpc`, `msx`) | `6502` |
| `-v` | Mode verbose | — |

La cible est détectée automatiquement depuis les premières lignes du source :

* `.asm` : `; target: 45gs02` ou `; target: x16`
* `.lasm` : `(target :45gs02)`

---

## Frontend .lasm — syntaxe Lisp native

Les fichiers `.lasm` sont du Common Lisp valide exécuté dans un
contexte où chaque mnémonique est une fonction. Toute la puissance de
CL est accessible : `let`, `dotimes`, `loop`, `defun`, `defmacro`, etc.

**Cibles supportées :** toutes les architectures — `:6502` (défaut),
`:45gs02`/`:mega65`, `:65c02`/`:x16`, `:r65c02`, `:65816`/`:snes`/`:apple2gs`,
`:z80`/`:spectrum`/`:msx`/`:cpc`, `:m68k`/`:amiga`/`:atari`.

> **Note Z80 et M68K :** utiliser `:origin 0` (le défaut `#x0801` est pour le 6502).
> Les instructions spécifiques utilisent les helpers `zi`/`mi` (voir ci-dessous).

> **Symboles CL redéfinis :** les noms CL standard suivants sont
> remplacés par des instructions assembleur dans les fichiers `.lasm` :
> `fill`, `bit`, `sec`, `and`, `map`. Utilisez `cl:fill`, `cl:and`,
> etc. si vous avez besoin de la fonction CL d'origine.

```lisp
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
(lda 'screen)     ; LDA SCREEN (symbole, résolu à l'assemblage)
```

Avec keyword — mode explicite :

| Keyword | Mode | Exemple |
|---------|------|---------|
| `:imm` | Immédiat | `(lda :imm #xFF)` → `LDA #$FF` |
| `:x` | Indexé X | `(lda :x #x10)` → `LDA $10,X` |
| `:y` | Indexé Y | `(lda :y #x1234)` → `LDA $1234,Y` |
| `:z` | Indexé Z (45GS02) | `(lda :z #x10)` → `LDA $10,Z` |
| `:ind` | Indirect | `(jmp :ind #xFFFC)` → `JMP ($FFFC)` |
| `:ix` | Pré-indexé X | `(lda :ix #x00)` → `LDA ($00,X)` |
| `:iy` | Post-indexé Y | `(lda :iy #xB0)` → `LDA ($B0),Y` |
| `:iz` | Post-indexé Z (45GS02) | `(lda :iz #xB0)` → `LDA ($B0),Z` |
| `:abs` | Absolu forcé | `(lda :abs #x10)` → `LDA $0010` |
| `:zp` | Zero-page forcée | `(lda :zp #x100)` → `LDA $00` |
| `:a` | Accumulateur | `(lsr :a)` → `LSR A` |

### Directives disponibles

| Directive | Description |
|-----------|-------------|
| `(org n)` | Définit l'adresse d'origine |
| `(label 'nom)` | Place un label local |
| `(global-label 'nom)` | Place un label global (exporté) |
| `(equ 'nom val)` | Définit une constante : `(equ 'cols 40)` → `COLS = 40` |
| `(db v …)` | Émet des octets (`.byte`) |
| `(dw v …)` | Émet des mots 16 bits, little-endian (`.word`) |
| `(dd v …)` | Émet des mots 32 bits, little-endian (`.dword`) |
| `(text "str")` | Émet une chaîne ASCII sans octet nul final |
| `(fill n [v])` | Émet `n` octets de valeur `v` (défaut 0) |
| `(align n [v])` | Aligne le PC sur `n`, rembourrage avec `v` |
| `(pad-to addr [v])` | Remplit du PC jusqu'à `addr` avec `v` (défaut 0) ; erreur si PC > addr |
| `(assert-pc addr)` | Erreur si le PC courant ≠ `addr` (vérification de layout) |
| `(ascii-z "str")` | Émet la chaîne ASCII suivie d'un octet nul (`$00`) |
| `(pascal-str "str")` | Émet un octet de longueur (1 octet) suivi de la chaîne |
| `(defstruct-asm nom f…)` | Définit une structure avec calcul automatique des offsets (voir ci-dessous) |
| `(defenum nom v…)` | Définit un enum : constantes séquentielles à partir de 0 (voir ci-dessous) |
| `(include-binary "fich" [off [n]])` | Inclut un fichier binaire brut (offset et compteur optionnels) |
| `(petscii "str")` | Émet une chaîne avec conversion ASCII→PETSCII (a-z → A-Z PETSCII) |
| `(assert-size n body…)` | Erreur si `body` n'émet pas exactement `n` octets |
| `(sine-table 'lbl n amp off)` | Émet une table sinus N entrées (amplitude + offset) |
| `(cosine-table 'lbl n amp off)` | Émet une table cosinus N entrées |
| `(linear-ramp 'lbl from to n)` | Émet une rampe linéaire N entrées de `from` à `to` |
| `(section :nom)` | Change de section |
| `(target :arch)` | Indication d'architecture pour le CLI (no-op à l'exécution) |

### Macros d'aide

| Macro | Description |
|-------|-------------|
| `(genlabel)` | Génère un keyword de label unique anonyme |
| `(with-label nom &body)` | Place le label `nom`, puis exécute le corps |
| `(lasm-if cond-fn t-lbl f-lbl &body)` | Émet une structure if/else conditionnelle |

Exemple `lasm-if` :
```lisp
(lasm-if (lambda (l) (beq l)) 'done 'skip
  (lda :imm 0)
  (sta #xD020))
```

### `defstruct-asm` — structure avec offsets automatiques

Les champs sont soit un keyword (champ 1 octet) soit `(keyword taille)` pour les champs multibytes.
Supporté sur toutes les architectures.

```lisp
(defstruct-asm player :x :y (:hp 2) :state)
; → PLAYER.X=0, PLAYER.Y=1, PLAYER.HP=2, PLAYER.STATE=4, PLAYER.SIZE=5
```

Syntaxe classique `.asm` — bloc multi-lignes :
```asm
.defstruct player
  .field x
  .field y
  .field hp, 2
  .field state
.endstruct
; PLAYER.X=0  PLAYER.Y=1  PLAYER.HP=2  PLAYER.STATE=4  PLAYER.SIZE=5
```

### `defenum` — constantes séquentielles

Les valeurs sont numérotées à partir de 0. `ENUM.COUNT` est défini automatiquement.
Supporté sur toutes les architectures.

```lisp
(defenum color :black :white :red :green :blue)
; → COLOR.BLACK=0, COLOR.WHITE=1, COLOR.RED=2, COLOR.GREEN=3, COLOR.BLUE=4
;   COLOR.COUNT=5
```

Syntaxe classique `.asm` — bloc multi-lignes :
```asm
.defenum state
  .val idle
  .val running
  .val paused
.endenum
; STATE.IDLE=0  STATE.RUNNING=1  STATE.PAUSED=2  STATE.COUNT=3
```

### Instructions spécifiques 45GS02

Avec `:target :45gs02`, les mnémoniques suivants sont disponibles :

- **Registre Z :** `ldz  stz  inz  dez  phz  plz  taz  tza`
- **Registre B :** `tab  tba  tsy  tys`
- **Registre Q (32 bits) :** `ldq  stq  adcq  sbcq  andq  oraq  eorq  aslq  lsrq  rolq  rorq  asrq  bitq  cmpq`
- **Branches longues :** `lbcc  lbcs  lbeq  lbne  lbmi  lbpl  lbvc  lbvs`
- **Divers :** `map  eom  neg  asr  inw  dew`

### Helpers Z80

Avec `:target :z80` (ou `:spectrum`, `:msx`, `:cpc`), utiliser les fonctions helper
pour construire les opérandes Z80 :

| Fonction | Description |
|----------|-------------|
| `(z80r "HL")` | Opérande registre Z80 (`:direct "HL"`) |
| `(z80ind "HL")` | Opérande indirect Z80 `(HL)` |
| `(z80ind "IX" 5)` | Indirect indexé `(IX+5)` |
| `(zi "LD" op1 op2)` | Émet une instruction Z80 quelconque |

```lisp
(assemble-lasm-string
  "(zi \"LD\" (z80r \"A\") (z80r \"B\"))   ; LD A, B
   (zi \"PUSH\" (z80r \"HL\"))              ; PUSH HL
   (zi \"JP\" (make-dir 'start))"           ; JP start
  :target :z80 :origin 0)
```

### Helpers M68K

Avec `:target :m68k` (ou `:amiga`, `:atari`, `:mac68k`), utiliser les fonctions helper
pour construire les opérandes 68000 :

| Fonction | Description |
|----------|-------------|
| `(dn n)` | Registre de données Dn (`:direct "Dn"`) |
| `(an n)` | Registre d'adresse An (`:direct "An"`) |
| `(ind-an n)` | Indirect `(An)` |
| `(post-an n)` | Post-incrément `(An)+` |
| `(pre-an n)` | Pré-décrément `-(An)` |
| `(m68k-imm val)` | Immédiat `#val` |
| `(mi "MOVE" :word op1 op2)` | Émet une instruction M68K avec taille optionnelle |

```lisp
(assemble-lasm-string
  "(mi \"MOVE\" :word (dn 0) (dn 1))   ; MOVE.W D0, D1
   (mi \"CLR\"  :byte (dn 3))           ; CLR.B  D3
   (mi \"NOP\")"                        ; NOP
  :target :m68k :origin 0)
```

### Exemples avec Lisp natif

```lisp
; Constante locale
(let ((black 0))
  (lda :imm black)
  (sta #xD020))

; Génération de code avec dotimes
(dotimes (i 8)
  (lda :imm i)
  (sta (+ #xD800 i)))

; Sous-routine réutilisable
(defun set-border (col)
  (lda :imm col)
  (sta #xD020))

(set-border 0)
(set-border 14)

; Boucle avec label anonyme
(let ((loop-lbl (genlabel)))
  (label loop-lbl)
  (dex)
  (bne loop-lbl))
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
`!word`/`!16` → `.word`, `!pet` → `.byte` avec codes PETSCII explicites
(a-z → majuscules A-Z −0x20, A-Z → shifted +0x80 ; formes mixtes supportées),
`!fill` → `.fill`, `!macro`/`!if` → `.macro`/`.if`,
`!cpu m65` → `; target: 45gs02`, `!cpu 65c02` → `; target: x16`.
Les caractères non-ASCII des commentaires sont normalisés en ASCII.

Les fichiers ACME simples utilisant `!byte`, `!pet`, `*=addr`, `!to`, `!cpu`
peuvent aussi être assemblés directement sans conversion :

    ./cl-asm source.s --target x16

Utilisez `acme2clasm` pour les fichiers nécessitant `!source`, `!binary`,
`!pseudopc`, macros, ou d'autres fonctionnalités ACME avancées.

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
