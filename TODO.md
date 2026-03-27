# TODO — cl-asm

## Améliorations

- [x] **Extension .lasm à toutes les architectures** : `assemble-lasm-string` et
      `assemble-lasm` supportent désormais toutes les cibles : `:6502`, `:45gs02`,
      `:65c02`, `:r65c02`, `:65816`, `:z80`, `:m68k` (et leurs aliases).
      Helpers Z80 (`z80r`, `z80ind`, `zi`) et M68K (`dn`, `an`, `ind-an`, `mi`)
      exposés dans le package `cl-asm/lasm`. *(v0.4.2)*

- [x] Tests de régression mega65 et x16 : générer les fichiers `.ref.prg`
      de référence. *(fichiers de test créés, validés avec ACME et ca65)*
- [x] Backend M68K : bug `EOR.W #imm, Dn` — crash "N is not a string designator".
      Corrigé : EOR #imm → EORI, AND/OR #imm → AND/OR avec EA=imm (comme vasm).
- [x] Conversion clasm→acme/ca65 : gérer les lignes `label: .directive`
      (label et directive sur la même ligne). Implémenter en bash ou en Lisp,
      sans dépendances externes (pas Python). *(v0.4.4)*

## Outils de développement

- [x] **Simulateur CPU 6502** : struct `cpu`, `step-cpu` (152 opcodes, ISA 6502 complète),
      cycle-accurate, page-crossing penalty, conditions d'erreur. *(v0.6.0)*
- [x] **Désassembleur 6502** : 151 opcodes officiels, 121 tests. *(v0.6.0)*
- [x] **Débogueur** : REPL interactif (step/next/continue), breakpoints inconditionnels
      et conditionnels (expr Lisp), watchpoints (:read/:write/:rw), affichage
      registres/mémoire/désassemblage, affichage ligne source depuis fichier,
      debug-map adresse↔source-loc. *(v0.7.0→v0.9.0)*

## Idées de directives .lasm

Fonctionnalités propres au frontend natif Lisp (pas de contrainte de compatibilité
avec ca65/ACME — on peut innover librement).

### Structures et enums
- [x] `(defstruct-asm player :x :y (:hp 2) :state)` — calcul automatique des offsets de champs ;
  `.defstruct`/`.field`/`.endstruct` dans `.asm` ; champs multibytes ; `STRUCT.SIZE` *(v0.4.2)*
- [x] `(defenum color :black :white :red)` — constantes séquentielles à partir de 0 ;
  `.defenum`/`.val`/`.endenum` dans `.asm` ; `ENUM.COUNT` auto *(v0.4.2)*

### Assertions de layout
- [x] `(assert-pc #x0900)` — erreur si le PC n'est pas exactement à cette adresse *(v0.4.2)*
- [x] `(assert-size 16 ...)` — erreur si le bloc n'émet pas exactement N octets *(v0.4.3)*

### Tables mathématiques
- [x] `(sine-table 'sin-tbl 256 127 128)` — table sinus (256 entrées, amplitude 127, offset 128) *(v0.4.3)*
- [x] `(cosine-table 'cos-tbl 256 127 128)` — idem pour cosinus *(v0.4.3)*
- [x] `(linear-ramp 'ramp 0 255 256)` — rampe linéaire de from à to en N pas *(v0.4.3)*

### Chaînes de caractères
- [x] `(ascii-z "hello")` — chaîne ASCII avec octet nul final *(v0.4.2)*
- [x] `(petscii "hello")` — chaîne avec conversion PETSCII (majuscules/minuscules) *(v0.4.3)*
- [x] `(pascal-str "hello")` — chaîne précédée d'un octet de longueur *(v0.4.2)*

### Données binaires externes
- [x] `(include-binary "sprite.bin")` — inclure un fichier binaire comme données brutes ;
  `.incbin "file"[, offset[, count]]` dans `.asm` ; offset et count optionnels *(v0.4.2)*

### Alignement / remplissage
- [x] `(pad-to #xBFFF)` — remplir jusqu'à une adresse absolue (avec $00 ou valeur choisie) *(v0.4.2)*

## Nouvelles architectures

- [x] Refactoriser `cl-asm-script.lisp` : remplacer le `ecase` codé en dur
      par un registre de backends extensible, pour faciliter l'ajout de
      nouvelles architectures sans modifier le script. *(v0.1.3)*
- [x] Backend WDC 65816 : support SNES / Apple IIgs. Modes 8/16 bits
      switchables (.al/.as/.xl/.xs), adresses 24 bits, indirect long,
      block move (MVN/MVP), branche longue (BRL). *(v0.2.0)*
- [x] Backend Zilog Z80 : ZX Spectrum, MSX, CPC, ZX81. Jeu complet avec
      préfixes CB/DD/ED/FD/DD·CB/FD·CB, variable `*z80-mode*` pour éviter
      les conflits de mnémoniques avec le 6502. *(v0.3.0)*

## Améliorations spécifiques à Common Lisp

Idées qui tirent parti des forces propres de CL (2026-03-27).

### Optimiseur peephole ★ prioritaire

Pattern-matching sur les séquences de nœuds IR pour remplacer des
combinaisons d'instructions par des équivalents plus efficaces.

Exemples 65C02 :
- `LDA #$00 / STA $zp` → `STZ $zp`
- `TAX / TXA` ou `TAY / TYA` → suppression si inutile
- `LDA $zp / STA $zp` → suppression (opération nulle)

Implémentation naturelle en Lisp : `destructuring-bind` ou
pattern-matching (trivia/optima) sur la liste IR-SECTION-NODES.
Aucun autre langage ne le ferait aussi proprement sur sa propre IR.

### Système de conditions/restarts pour les erreurs d'assemblage

Remplacer les `error` simples par des conditions CL avec restarts :
- `use-value` — fournir une valeur de substitution pour un symbole inconnu
- `skip-instruction` — ignorer l'instruction fautive et continuer
- `retry` — ré-essayer après correction interactive

Utile pour un REPL d'assemblage interactif : résoudre des références
indéfinies sans relancer tout l'assemblage.

### Tables d'instructions générées déclarativement

Remplacer les `defparameter` de listes écrites à la main par un DSL
Lisp + `defmacro` :

```lisp
(define-instruction "LDA"
  (:immediate  #xA9 2)
  (:zero-page  #xA5 2)
  (:absolute   #xAD 3) ...)
```

Le macro génèrerait les entrées, les fonctions `lookup-*` et des tests
de cohérence à la compilation. Moins de duplication, plus robuste.

### Évaluation Lisp complète à l'assemblage (.lasm)

Exposer explicitement la puissance de CL pour générer des données à
l'assemblage : tables de lookup, boucles déroulées, compression RLE,
calculs trigonométriques, etc. — sans code d'exécution supplémentaire.

```lisp
;; Table sinus précalculée à l'assemblage (256 entrées)
(dotimes (i 256)
  (byte (round (* 127 (sin (* 2 pi (/ i 256)))))))
```

### Assemblage incrémental au REPL

API pour construire un programme instruction par instruction dans le
REPL, avec inspection de l'état binaire à chaque étape :

```lisp
(with-asm (:target :6502 :origin #x0200)
  (lda :imm #x42)
  (sta :zp  #x10)
  (inspect-pc)   ; → $0204
  (rts))
