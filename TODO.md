# TODO — cl-asm

## Améliorations

- [ ] **Extension .lasm à toutes les architectures** : `assemble-lasm-string` et
      `assemble-lasm` ne supportent actuellement que `:6502` et `:45gs02`. Il faut :
      1. Ajouter les cibles `:65c02`, `:r65c02`, `:65816`, `:z80`, `:m68k` dans le
         `ecase` de `assemble-lasm-string` / `assemble-lasm`.
      2. Exposer les mnémoniques de chaque architecture comme fonctions dans le
         package `cl-asm/lasm` (avec gestion des conflits de noms, comme `*z80-mode*`
         pour le Z80).
      3. Mettre à jour la doc (supprimer la restriction "6502 et 45GS02 uniquement").

- [x] Tests de régression mega65 et x16 : générer les fichiers `.ref.prg`
      de référence. *(fichiers de test créés, validés avec ACME et ca65)*
- [x] Backend M68K : bug `EOR.W #imm, Dn` — crash "N is not a string designator".
      Corrigé : EOR #imm → EORI, AND/OR #imm → AND/OR avec EA=imm (comme vasm).
- [ ] Conversion clasm→acme/ca65 : gérer les lignes `label: .directive`
      (label et directive sur la même ligne). Implémenter en bash ou en Lisp,
      sans dépendances externes (pas Python).

## Outils de développement

- [ ] **Simulateur CPU** : exécuter les instructions une par une dans un environnement
      mémoire virtuel. Commencer par le 6502 (jeu d'instructions limité, bien documenté),
      puis étendre aux autres architectures. Base nécessaire avant tout débogueur.
- [ ] **Débogueur** : breakpoints, step/next, affichage registres/mémoire, liaison
      adresse PC ↔ ligne source (via SOURCE-LOC déjà présent dans l'IR).
      Nécessite le simulateur.

## Idées de directives .lasm

Fonctionnalités propres au frontend natif Lisp (pas de contrainte de compatibilité
avec ca65/ACME — on peut innover librement).

### Structures et enums
- `(defstruct-asm player :x :y :hp :state)` — calcul automatique des offsets de champs
  (ex. `player.x = 0`, `player.y = 1`, `player.hp = 2`…)
- `(defenum color :black :white :red :green :blue)` — constantes auto-numérotées

### Assertions de layout
- `(assert-pc #x0900)` — erreur si le PC n'est pas exactement à cette adresse
- `(assert-size 16 ...)` — erreur si le bloc n'émet pas exactement N octets

### Tables mathématiques
- `(sine-table 'sin-tbl 256 127 128)` — table sinus (256 entrées, amplitude 127, offset 128)
- `(cosine-table 'cos-tbl 256 127 128)` — idem pour cosinus
- `(linear-ramp 'ramp 0 255 256)` — rampe linéaire de from à to en N pas

### Chaînes de caractères
- `(ascii-z "hello")` — chaîne ASCII avec octet nul final
- `(petscii "hello")` — chaîne avec conversion PETSCII (majuscules/minuscules)
- `(pascal-str "hello")` — chaîne précédée d'un octet de longueur

### Données binaires externes
- `(include-binary "sprite.bin")` — inclure un fichier binaire comme données brutes

### Alignement / remplissage
- `(pad-to #xBFFF)` — remplir jusqu'à une adresse absolue (avec $00 ou valeur choisie)

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
