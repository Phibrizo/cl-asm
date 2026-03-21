# TODO — cl-asm

## Améliorations

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
