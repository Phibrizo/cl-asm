# TODO — cl-asm

## Améliorations

- [ ] Tests de régression mega65 et x16 : générer les fichiers `.ref.prg`
      de référence (nécessite un compilateur de référence pour ces cibles).

## Nouvelles architectures

- [x] Refactoriser `cl-asm-script.lisp` : remplacer le `ecase` codé en dur
      par un registre de backends extensible, pour faciliter l'ajout de
      nouvelles architectures sans modifier le script. *(v0.1.3)*
- [ ] Backend WDC 65816 : support SNES / Apple IIgs. Points clés : modes
      8/16 bits switchables, ~20 modes d'adressage, adresses 24 bits,
      directives `.mx`/`.al`/`.as`/`.xl`/`.xs`.
