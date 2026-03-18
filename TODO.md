# TODO — cl-asm

## Bugs

- [ ] `acme2clasm.lisp` : les labels `::` (globaux ACME) sont mal convertis —
      le `::` est découpé en `label:` + `:` orphelin sur la ligne suivante.
      Exemple : `main::` → `main:` + `:` au lieu de `main:`.

## Améliorations

- [ ] i18n `acme2clasm.lisp` : ajouter la détection de `LANG` et les messages
      en français/anglais (même système que `cl-asm-script.lisp`).
- [ ] i18n `tests/run-tests.lisp` : traduire les messages de sortie des tests.
- [ ] Tests de régression mega65 et x16 : générer les fichiers `.ref.prg`
      de référence (nécessite un compilateur de référence pour ces cibles).

## Idées

- [ ] Script `run-tests-ecl.sh` pour lancer les tests avec ECL.
