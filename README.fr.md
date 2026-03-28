# cl-asm — Assembleur multi-architecture en Common Lisp

Assembleur modulaire écrit en Common Lisp. Cibles actuelles : **6502**
(Apple II…), **6510** (Commodore 64, avec opcodes illégaux stables),
**45GS02** (Mega65), **65C02** (Commander X16), **R65C02** (Rockwell),
**WDC 65816** (SNES, Apple IIgs), **Z80** (ZX Spectrum, MSX, CPC, ZX81),
**M68K** (Amiga, Atari ST, Mac 68k), **Intel 8080** (CP/M, Altair) et **Intel 8086/8088** (IBM PC, MS-DOS).
L'architecture est pensée pour accueillir d'autres backends
sans modifier le cœur du projet.

## Version

**Version courante : 0.17.0**

```
cl-asm/version:+version+         ; → "0.17.0"
cl-asm/version:+version-major+   ; → 0
cl-asm/version:+version-minor+   ; → 17
cl-asm/version:+version-patch+   ; → 0
(cl-asm/version:version-string)  ; → "0.17.0"
```

---

## État du projet

| Module | État | Tests |
| --- | --- | --- |
| IR (Représentation intermédiaire) | ✓ | — |
| Évaluateur d'expressions | ✓ | 129 |
| Table des symboles | ✓ | 65 |
| Lexer classique | ✓ | 119 |
| Parser classique (ca65-like) | ✓ | 84 |
| Backend 6502 | ✓ | 108 |
| Backend 6510 (C64, opcodes illégaux) | ✓ | 66 |
| Backend 45GS02 | ✓ | 80 |
| Backend 65C02 (X16) | ✓ | 86 |
| Backend R65C02 (Rockwell) | ✓ | 117 |
| Backend WDC 65816 (SNES/Apple IIgs) | ✓ | 104 |
| Backend Z80 (ZX Spectrum, MSX, CPC, ZX81) | ✓ | 191 |
| Parser M68K | ✓ | 85 |
| Backend M68K (Amiga, Atari ST, Mac 68k) | ✓ | 144 |
| Backend Intel 8080 (CP/M, Altair) | ✓ | 144 |
| Backend Intel 8086/8088 (IBM PC, MS-DOS) | ✓ | 236 |
| Simulateur 6502 | ✓ | 294 |
| Programmes simulateur 6502 | ✓ | 73 |
| Désassembleur 6502 | ✓ | 121 |
| Désassembleur 45GS02 | ✓ | 97 |
| Désassembleur 65C02 (X16) | ✓ | 44 |
| Débogueur 6502 (REPL interactif) | ✓ | 80 |
| Émetteurs BIN / PRG / listing | ✓ | — |
| Émetteurs Intel HEX / Motorola S-record | ✓ | 32 |
| Macros textuelles | ✓ | 27 |
| Assemblage conditionnel | ✓ | 27 |
| Frontend .lasm (Lisp natif) | ✓ | 97 |
| Convertisseur acme2clasm | ✓ | 20 |
| Linker modulaire en mémoire (famille 6502) | ✓ | 26 |
| Optimiseur peephole (6502/6510/65C02/45GS02) | ✓ | 28 |
| Conditions & Restarts | ✓ | 14 |

**Total : 2778 tests, 0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+ et ECL 21.x+**

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
│   │   ├── disassemblers.lisp  registre extensible de désassembleurs
│   │   ├── ir.lisp             représentation intermédiaire
│   │   ├── expression.lisp     évaluateur d'expressions
│   │   ├── debug-map.lisp      table adresse→source-loc (pour le débogueur)
│   │   ├── symbol-table.lisp   table des symboles, 2 passes
│   │   ├── linker.lisp         linker modulaire en mémoire (famille 6502)
│   │   ├── optimizer.lisp      registre extensible d'optimiseurs peephole
│   │   └── restarts.lisp       protocole de restarts CL pour les erreurs d'assemblage
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
│   │   ├── m68k.lisp           encodeur M68K (Amiga, Atari ST, Mac 68k)
│   │   ├── i8080.lisp          encodeur Intel 8080 (CP/M, Altair)
│   │   └── i8086.lisp          encodeur Intel 8086/8088 (IBM PC, MS-DOS)
│   ├── simulator/
│   │   └── 6502.lisp           simulateur CPU 6502 (152 opcodes, cycle-accurate)
│   ├── disassembler/
│   │   ├── 6502.lisp           désassembleur 6502 (151 opcodes officiels)
│   │   ├── 45gs02.lisp         désassembleur 45GS02 (dispatcher de préfixes)
│   │   └── 65c02.lisp          désassembleur 65C02 / X16 (table plate)
│   ├── debugger/
│   │   └── 6502.lisp           débogueur 6502 interactif (REPL)
│   ├── optimizer/
│   │   ├── 6502.lisp           règles peephole A+B pour 6502/6510
│   │   └── 65c02.lisp          règles peephole A+B+C pour 65C02/45GS02
│   └── emit/
│       ├── output.lisp         émetteurs BIN, PRG, listing
│       ├── ihex.lisp           émetteur Intel HEX
│       └── srec.lisp           émetteur Motorola S-record
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
│   ├── test-m68k.lisp
│   ├── test-8080.lisp
│   ├── test-8086.lisp
│   ├── test-sim-6502.lisp
│   ├── test-sim-programs.lisp
│   ├── test-disasm-6502.lisp
│   ├── test-disasm-45gs02.lisp
│   ├── test-disasm-65c02.lisp
│   ├── test-debugger-6502.lisp
│   ├── test-acme2clasm.lisp
│   ├── test-linker-6502.lisp
│   ├── test-optimizer-6502.lisp
│   └── test-restarts.lisp
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
=== symbol-table :  65 OK, 0 KO
=== expression   : 129 OK, 0 KO
--- Frontend ---
=== lexer        : 119 OK, 0 KO
=== parser       :  84 OK, 0 KO
=== macros       :  27 OK, 0 KO
=== conditionnel :  27 OK, 0 KO
=== lasm         :  97 OK, 0 KO
--- Backends ---
=== 6502         : 108 OK, 0 KO
=== 65c02        :  86 OK, 0 KO
=== r65c02       : 117 OK, 0 KO
=== 45gs02       :  80 OK, 0 KO
=== 65816        : 104 OK, 0 KO
=== z80          : 191 OK, 0 KO
--- Parsers architectures ---
=== m68k-parser  :  85 OK, 0 KO
=== m68k         : 144 OK, 0 KO
--- Intel 8080 ---
=== i8080        : 144 OK, 0 KO
--- Intel 8086 ---
=== i8086        : 236 OK, 0 KO
--- Simulateur ---
=== sim-6502     : 294 OK, 0 KO
--- Outils ---
=== acme2clasm   :  20 OK, 0 KO
-------------------------------
=== TOTAL        : 2778 OK, 0 KO sur 2778 tests
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

;; Écrire un fichier Intel HEX
(cl-asm/emit.ihex:write-ihex bytes "/tmp/demo.hex" :origin #x0801)

;; Écrire un fichier Motorola S-record
(cl-asm/emit.srec:write-srec bytes "/tmp/demo.srec" :origin #x0801)
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

### Linker — assemblage multi-fichiers avec références croisées

Package `cl-asm/linker`. Lie plusieurs fichiers sources en un seul binaire ;
les labels définis dans un fichier sont visibles par les autres.

```lisp
;; Deux unités partageant une table de symboles
(let* ((u1 (cl-asm/linker:link-unit-from-program
             "main"
             (cl-asm/parser:parse-string
               "main: JSR helper
                      RTS")
             :6502))
       (u2 (cl-asm/linker:link-unit-from-program
             "utils"
             (cl-asm/parser:parse-string
               "helper: LDA #$42
                        RTS")
             :6502))
       (bytes (cl-asm/linker:link (list u1 u2) :origin #x0200)))
  bytes)
;; => #(#x20 #x04 #x02   ; JSR $0204 (helper)
;;       #x60             ; RTS
;;       #xA9 #x42        ; LDA #$42
;;       #x60)            ; RTS

;; Cibles supportées : :6502  :6510  :65c02  :45gs02
```

### Conditions & Restarts

Les erreurs d'assemblage exposent des restarts CL pour une récupération programmatique :

```lisp
;; Résoudre tous les labels indéfinis à 0 (utile pour les passes de layout)
(cl-asm/restarts:with-asm-use-zero
  (cl-asm/backend.6502:assemble-string "LDA unknown_fn\nRTS"))
; → #(165 0 96)  ; LDA $00, RTS

;; Ignorer les mnémoniques inconnus (mode tolérant)
(cl-asm/restarts:with-asm-skip-errors
  (cl-asm/backend.6502:assemble-string "FUTURE_OP\nNOP"))
; → #(234)       ; NOP seulement

;; Contrôle fin avec handler-bind
(handler-bind
  ((cl-asm/ir:asm-undefined-label
    (lambda (c)
      (format t "Résolution de ~A vers $0300~%" (cl-asm/ir:asm-error-label c))
      (invoke-restart 'cl-asm/restarts:use-value #x0300))))
  (cl-asm/backend.6502:assemble-string "JSR missing_fn\nRTS"))
```

---

## Simulateur 6502

Package `cl-asm/simulator.6502` — simulateur CPU 6502 cycle-accurate avec mémoire de 64 Ko.

### Démarrage rapide

```lisp
(ql:quickload "cl-asm")

(let* ((cpu (cl-asm/simulator.6502:make-cpu))
       (program #(#xa9 #x42   ; LDA #$42
                  #x85 #x00   ; STA $00
                  #x00))      ; BRK
       (cpu (cl-asm/simulator.6502:load-program cpu program #x0300)))
  (multiple-value-bind (cpu reason)
      (cl-asm/simulator.6502:run-cpu cpu :origin #x0300)
    (format t "A=~2,'0X  raison=~A~%" (cl-asm/simulator.6502:cpu-a cpu) reason)))
;; A=42  raison=:BRK
```

### Exports clés

| Symbole | Description |
| --- | --- |
| `make-cpu` | Crée un nouveau CPU avec mémoire et registres à zéro |
| `reset-cpu` | Réinitialise les registres (PC/SP/P) sans effacer la mémoire |
| `load-program cpu bytes addr` | Copie un vecteur d'octets en mémoire à `addr`, retourne le cpu mis à jour |
| `step-cpu cpu` | Exécute une instruction ; signale `cpu-break` sur BRK, `cpu-illegal-opcode` sur opcode inconnu |
| `run-cpu cpu &key origin max-steps` | Boucle jusqu'à BRK ou `max-steps` ; retourne `(values cpu :brk\|:step-limit)` |
| `mem-read cpu addr` | Lit un octet en mémoire |
| `mem-write cpu addr val` | Écrit un octet en mémoire |
| `cpu-a`, `cpu-x`, `cpu-y` | Accesseurs accumulateur / registres index |
| `cpu-pc`, `cpu-sp`, `cpu-p` | Accesseurs compteur de programme / pointeur de pile / flags processeur |
| `cpu-cycles` | Accesseur compteur de cycles |
| `flag-c`, `flag-z`, `flag-i`, `flag-d`, `flag-b`, `flag-v`, `flag-n` | Lecture des flags individuels (0 ou 1) depuis un cpu |
| `+flag-c+`, `+flag-z+`, `+flag-i+`, `+flag-d+`, `+flag-b+`, `+flag-v+`, `+flag-n+` | Constantes de masque de bit pour chaque flag |

### Couverture des instructions

152 opcodes couvrant le jeu d'instructions 6502 complet :

- **Implicites (23) :** NOP BRK TAX TXA TAY TYA TSX TXS PHA PLA PHP PLP INX INY DEX DEY CLC SEC CLI SEI CLV CLD SED
- **Load/store :** LDA×8, LDX×5, LDY×5, STA×7, STX×3, STY×3
- **ALU :** ADC×8, SBC×8, AND×8, ORA×8, EOR×8, CMP×8, CPX×3, CPY×3, BIT×2
- **Décalages/rotations :** ASL×5, LSR×5, ROL×5, ROR×5
- **Incréments mémoire :** INC×4, DEC×4
- **Sauts/branches :** JMP abs, JMP (ind) avec bug de page du 6502 original, JSR, RTS, RTI, BCC BCS BEQ BNE BMI BPL BVC BVS

La pénalité de cycle sur franchissement de page est appliquée (+1 pour les lectures ; coût fixe pour les écritures). Les comptages de cycles correspondent au 6502 NMOS original.

---

## Désassembleur 6502

Package `cl-asm/disassembler.6502` — désassemble du code machine 6502 en mnémoniques lisibles. 151 opcodes officiels, tous les modes d'adressage.

```lisp
(let ((mem (make-array 65536 :element-type '(unsigned-byte 8) :initial-element 0)))
  (setf (aref mem #x0200) #xA9  ; LDA
        (aref mem #x0201) #x42  ;   #$42
        (aref mem #x0202) #x85  ; STA
        (aref mem #x0203) #x00  ;   $00
        (aref mem #x0204) #x00) ; BRK
  (cl-asm/disassembler.6502:print-disasm mem #x0200 :count 3))
;; $0200  A9 42     LDA #$42
;; $0202  85 00     STA $00
;; $0204  00        BRK
```

| Symbole | Description |
| --- | --- |
| `disasm-one mem addr` | Désassemble une instruction → `(values mnémonique opérande taille)` |
| `disasm mem addr &key count` | Désassemble `count` instructions → liste de `(addr hex mnémonique opérande)` |
| `disasm-string mem addr &key count` | Retourne un listing formaté sous forme de chaîne |
| `print-disasm mem addr &key count stream` | Affiche le désassemblage sur `stream` |

---

## Débogueur 6502

Package `cl-asm/debugger.6502` — débogueur interactif pas-à-pas construit sur le simulateur 6502.

### Session interactive

```lisp
(ql:quickload "cl-asm")

(let* ((prog  (cl-asm/parser:parse-string "
.org $0200
  LDA #$01
  CLC
  ADC #$02
  BRK"))
       (dm    (cl-asm/debug-map:make-debug-map))  ; optionnel : table ligne source
       (bytes (cl-asm/backend.6502:assemble prog :origin #x0200 :debug-map dm))
       (cpu   (cl-asm/simulator.6502:make-cpu))
       (dbg   (cl-asm/debugger.6502:make-debugger cpu :debug-map dm)))
  (cl-asm/simulator.6502:load-program cpu bytes :origin #x0200)
  (cl-asm/debugger.6502:debugger-repl dbg))
```

Exemple de session :

```
=== Débogueur 6502 — cl-asm v0.14.0 ===
Tapez 'h' pour l'aide.

$0200  A9 01     LDA #$01  ; :3:3
 A=$00 X=$00 Y=$00 SP=$FF P=nv-bdIzc  cyc=0

dbg> s
$0202  18        CLC  ; :4:3
 A=$01 X=$00 Y=$00 SP=$FF P=nv-bdIzc  cyc=2

dbg> b $0205
Breakpoint posé à $0205

dbg> c
[BREAKPOINT] à $0205
$0205  00        BRK  ; :6:3
 A=$03 X=$00 Y=$00 SP=$FF P=nv-bdIzc  cyc=8

dbg> m $00 8
$0000  00 00 00 00 00 00 00 00

dbg> q
Au revoir.
```

Quand le programme est assemblé depuis un fichier, les localisations source s'affichent sous la forme `fichier.asm:ligne:col`.

### Commandes REPL

| Commande | Description |
| --- | --- |
| `s` / `step` | Exécuter une instruction |
| `n` / `next` | Step-over : saute le corps d'un JSR |
| `c` / `continue` | Continuer jusqu'au breakpoint, watchpoint ou BRK |
| `b $ADDR [expr]` | Poser un breakpoint ; condition Lisp optionnelle `(lambda (cpu) expr)`, `cpu` lié à la struct CPU |
| `d $ADDR` | Supprimer un breakpoint |
| `lb` | Lister les breakpoints actifs |
| `w $ADDR [read\|write\|rw]` | Poser un watchpoint mémoire (défaut `write`) |
| `dw $ADDR` | Supprimer un watchpoint |
| `lw` | Lister les watchpoints actifs |
| `r` / `regs` | Afficher les registres et les flags (NV-BDIZC) |
| `m $ADDR [N]` | Dump hex de N octets à partir de l'adresse (défaut 16) |
| `x [$ADDR] [N]` | Désassembler N instructions (défaut 8, défaut = PC courant) |
| `h` / `help` | Aide |
| `q` / `quit` | Quitter le débogueur |
| _(ligne vide)_ | Répéter la dernière commande |

### API programmatique

```lisp
;; Créer une session
(let* ((dm    (cl-asm/debug-map:make-debug-map))
       (bytes (cl-asm/backend.6502:assemble prog :origin #x0200 :debug-map dm))
       (cpu   (cl-asm/simulator.6502:make-cpu))
       (dbg   (cl-asm/debugger.6502:make-debugger cpu :debug-map dm)))
  (cl-asm/simulator.6502:load-program cpu bytes :origin #x0200)

  ;; Breakpoints
  (cl-asm/debugger.6502:set-breakpoint dbg #x0204)
  (cl-asm/debugger.6502:set-breakpoint dbg #x0210
    :condition (lambda (cpu) (= (cl-asm/simulator.6502:cpu-a cpu) 0)))

  ;; Watchpoints
  (cl-asm/debugger.6502:set-watchpoint dbg #x00F0 :kind :write)  ; arrêt sur écriture à $00F0
  (cl-asm/debugger.6502:set-watchpoint dbg #x00F1 :kind :rw)     ; arrêt en lecture ET écriture
  (cl-asm/debugger.6502:list-watchpoints dbg)
  (cl-asm/debugger.6502:clear-watchpoint dbg #x00F0)

  ;; Exécution
  (cl-asm/debugger.6502:debugger-step dbg)      ; → :ok | :brk | :breakpoint | :watchpoint | :illegal
  (cl-asm/debugger.6502:debugger-next dbg)      ; step-over JSR
  (cl-asm/debugger.6502:debugger-continue dbg)  ; → :brk | :breakpoint | :watchpoint | :illegal

  ;; Table source (nécessite :debug-map à l'assemblage)
  (cl-asm/debug-map:debug-map-get dm #x0200))   ; → source-loc ou NIL
```

| Symbole | Description |
| --- | --- |
| `make-debugger cpu &key debug-map` | Créer une session débogueur |
| `debugger-repl dbg &key input output` | Lancer le REPL interactif |
| `debugger-step dbg [stream]` | Exécuter une instruction, afficher l'état |
| `debugger-next dbg [stream]` | Step-over (saute les corps JSR) |
| `debugger-continue dbg [stream]` | Exécuter jusqu'au breakpoint ou BRK |
| `set-breakpoint dbg addr &key condition` | Poser un breakpoint ; `condition` = `nil` (inconditionnel) ou `(lambda (cpu) → bool)` |
| `clear-breakpoint dbg addr` | Supprimer le breakpoint |
| `list-breakpoints dbg` | Lister les breakpoints triés par adresse |
| `set-watchpoint dbg addr &key kind` | Poser un watchpoint ; `kind` = `:read` \| `:write` \| `:rw` (défaut `:write`) |
| `clear-watchpoint dbg addr` | Supprimer le watchpoint |
| `list-watchpoints dbg` | Lister les watchpoints triés par adresse |
| `debugger-last-watchpoint dbg` | `(adresse kind)` du dernier watchpoint déclenché |
| `show-registers cpu [stream]` | Afficher les registres (`A=$XX … P=NV-BDIZC cyc=N`) |
| `assemble-file path &key origin debug-map` | Parser et assembler un fichier (debug-map désormais supporté) |
| `show-current dbg [stream]` | Afficher l'instruction courante + registres (avec source-loc si disponible) |
| `show-memory cpu addr [count stream]` | Dump hexadécimal |
| `show-disasm cpu addr [count stream]` | Désassembler depuis une adresse |
| `make-debug-map` | Créer une table adresse→source-loc (package `cl-asm/debug-map`) |

---

## Formats de sortie

| Format | Fonction | Description |
| --- | --- | --- |
| BIN | `write-bin` | Binaire brut, sans header |
| PRG | `write-prg` | Format C64 : 2 octets header LE + binaire |
| HEX | `write-ihex` | Intel HEX (microcontrôleurs, flasheurs) |
| SREC | `write-srec` | Motorola S-record (68k, flasheurs embarqués) |
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
./cl-asm programme.asm --format ihex   # Intel HEX → programme.hex
./cl-asm programme.asm --format srec   # Motorola S-record → programme.srec
./cl-asm programme.asm --origin 0xC000
./cl-asm mega65.lasm --target 45gs02
./cl-asm prog.asm --target x16
./cl-asm prog.asm --target r65c02
./cl-asm snes.asm --target 65816     # WDC 65816 / SNES
./cl-asm prog.asm --target z80       # Z80 / ZX Spectrum / MSX
./cl-asm prog.asm --target 8080      # Intel 8080 / CP/M
./cl-asm prog.asm --target 8086      # Intel 8086 / MS-DOS
# Assembler un fichier source ACME directement (sans conversion)
./cl-asm terminal.asm --target x16
./cl-asm programme.asm -v            # mode verbose
./cl-asm --help
```

### Options

| Option | Description | Défaut |
| --- | --- | --- |
| `-o FILE` | Fichier de sortie | même nom, ext .prg |
| `-f FORMAT` | `prg`, `bin`, `ihex` (Intel HEX → `.hex`), `srec` (Motorola S-record → `.srec`) | `prg` |
| `--origin ADDR` | Adresse d'origine (ex: `0x0801`) | `0x0801` |
| `-t TARGET` | `6502` (aussi `mos6502`), `6510` (aussi `mos6510`, `c64`), `45gs02` (aussi `mega65`), `x16` (aussi `65c02`, `commander-x16`), `r65c02` (aussi `rockwell`), `65816` (aussi `wdc65816`, `snes`, `apple2gs`), `z80` (aussi `z80cpu`, `zxspectrum`, `spectrum`, `cpc`, `msx`), `i8080` (aussi `8080`, `cpm`, `altair`, `intel8080`), `i8086` (aussi `8086`, `8088`, `i8088`, `ibmpc`, `msdos`, `x86-16`) | `6502` |
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
`:z80`/`:spectrum`/`:msx`/`:cpc`, `:m68k`/`:amiga`/`:atari`,
`:i8080`/`:8080`/`:cpm`/`:altair`, `:i8086`/`:8086`/`:8088`/`:ibmpc`/`:msdos`/`:x86-16`.

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
