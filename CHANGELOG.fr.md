# Changelog cl-asm

Toutes les modifications notables de ce projet sont documentées ici.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/).

---

## [0.21.0] — 2026-04-02

### Ajouté
- **Détecteur de code mort** (`src/core/dead-code.lisp`) : analyse de joignabilité du graphe de flot de contrôle (CFG) sur l'IR, par BFS depuis des points d'entrée déclarés. Les labels non atteignables sont signalés sous forme de `dead-code-warning` (nom de label + source-loc). Pattern registre extensible — même conception que l'optimiseur peephole et le registre des désassembleurs. Package `cl-asm/dead-code`.
  - `register-dead-code-analyzer target &key branch-mnemonics jump-mnemonics call-mnemonics return-mnemonics classify-fn target-operand-fn description` — enregistre un analyseur pour une architecture cible.
  - `find-dead-code-analyzer target` / `all-dead-code-analyzers` — consultation du registre.
  - `analyze-dead-code sections target &key entry-points` — exécute le BFS ; retourne une liste de `dead-code-warning`. Retourne `NIL` pour les architectures non enregistrées (pas d'erreur).
  - Les slots `classify-fn` / `target-operand-fn` gèrent les architectures aux mnémoniques ambigus (Z80 : `JR`/`JP`/`CALL`/`RET` peuvent être conditionnels ou non selon le nombre d'opérandes ; les variantes conditionnelles ajoutent les deux chemins au worklist).
  - Limites connues : les sauts indirects (`JMP (addr)`, `JP (HL)`…) n'ont pas de cible connue — traités comme terminaux (pas de fall-through, pas de cible). Les gestionnaires d'interruptions doivent être déclarés explicitement. Le code auto-modifiant est invisible à l'analyse statique.
- **Tables de mnémoniques par architecture** (`src/dead-code/`) :
  - `6502.lisp` — couvre 6502, 6510 (+KIL), 65C02/R65C02 (+BRA comme saut), 45GS02 (+LBEQ…LBVS, LBRA, JSQ, RTQ), 65816 (+BRL, JML, JSL, RTL, COP).
  - `z80.lisp` — Z80 avec `classify-fn` : `JR`/`JP` à 1 opérande → `:jump` ; à 2 opérandes → `:branch` ; `JP (HL)/(IX)/(IY)` → `:return` (indirect) ; `RET` seul → `:return`, `RET cond` → `:normal` ; `CALL` seul → `:call`, `CALL cond` → `:branch`.
  - `m68k.lisp` — M68K : Bcc/DBcc → `:branch`, BRA/JMP → `:jump`, BSR/JSR → `:call`, RTS/RTR/RTE → `:return`. Pas de `classify-fn` nécessaire (conditions encodées dans le mnémonique).
  - `i8080.lisp` — Intel 8080 : sauts/appels conditionnels (JC/JNC/JZ/JNZ/CC/CNC…) → `:branch`, retours conditionnels (RC/RNC…) → `:normal`, JMP → `:jump`, CALL → `:call`, RET/HLT → `:return`.
  - `i8086.lisp` — Intel 8086 : tous les Jcc + famille LOOP → `:branch`, JMP/JMPF → `:jump`, CALL/CALLF → `:call`, RET/RETF/IRET/HLT → `:return`.
- **Intégration dans `cl-asm/backend.6502:assemble`** : nouveaux paramètres `:detect-dead-code` et `:dead-code-entry-points` ; la fonction retourne désormais `(values bytes warnings)`. `assemble-string` et `assemble-file` propagent les deux paramètres. Les autres backends utilisent `analyze-dead-code` directement (API standalone).
- 47 tests dans `tests/test-dead-code.lisp` : registre (10 architectures + cible inconnue), aucun code mort (programme linéaire, JSR, branches), labels morts (fonction jamais appelée, deux fonctions mortes, code après JMP, code après RTS), points d'entrée explicites (handlers d'interruption, entrée inconnue ignorée silencieusement), sauts indirects (conservatif), cible inconnue → liste vide, intégration avec `assemble-string`, flot de contrôle Z80 (JR inconditionnel, JR NZ conditionnel, CALL).

### Tests

| Suite | Tests |
|-------|-------|
| test-dead-code (+47) | 47 |
| **Total** | **2966** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.20.0] — 2026-03-28

### Ajouté
- **Directive `.include "fichier.asm"`** (`src/frontend/classic-parser.lisp`) : inclut un fichier source externe au moment du parsing. Les nœuds IR du fichier inclus (labels, instructions, directives, macros, constantes) sont injectés dans la section courante comme s'ils étaient écrits inline. Les chemins relatifs sont résolus par rapport au répertoire du fichier incluant. La détection de cycles signale une `asm-error`. Fonctionne avec tous les backends.
- **Fonction `(include-source "fichier.lasm")`** (`src/frontend/lasm.lisp`) : équivalent pour les fichiers `.lasm`. Le fichier inclus s'exécute dans le même contexte d'assemblage (`*ctx*`). Chemins relatifs résolus depuis le répertoire du fichier incluant. Détection de cycles.
- Variables dynamiques `*include-stack*` / `*base-dir*` (parser) et `*lasm-include-stack*` / `*lasm-base-dir*` (lasm) pour la résolution des chemins et la détection de cycles.
- `parse-file` utilise désormais `truename` pour que les chemins relatifs des `.include` soient résolus correctement.
- 13 tests répartis dans `tests/test-parser.lisp` (8 tests : injection IR, octets assemblés, include imbriqué, macro dans include, erreurs) et `tests/test-lasm.lisp` (5 tests : octets, include imbriqué, erreurs).
- Exemples : `examples/include-main.asm` + `examples/include-utils.asm` et `examples/include-main.lasm` + `examples/include-utils.lasm`.

### Notes
- Les labels anonymes (`@`) et scopés (`@nom`) des fichiers inclus sont renumérotés indépendamment. Éviter de réutiliser les mêmes noms de labels locaux dans plusieurs fichiers inclus depuis le même parent — utiliser des noms uniques ou la syntaxe de labels globaux `::`.

### Tests

| Suite | Tests |
|-------|-------|
| test-parser (+8) | 92 |
| test-lasm (+5) | 102 |
| **Total** | **2919** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.19.0] — 2026-03-28

### Ajouté
- **Profiler et tracer 6502/6510** (`src/profiler/6502.lisp`) : construit au-dessus du simulateur 6502 existant. Package `cl-asm/profiler.6502`.
  - **Profiler** : tableaux fixnum 65536 entrées (`hit-count`, `cycle-count`) ; compteurs incrémentiels `total-hits` / `total-cycles`. `make-profiler`, `profiler-reset`, `profile-step cpu profiler` (sûr même si BRK ou opcode illégal est signalé), `run-with-profiler cpu profiler &key max-steps`, `print-profile profiler &key (stream t) (top 20)`.
  - **Tracer** : tampon circulaire de structs `trace-entry` (PC, A, X, Y, SP, P, delta-cycles, mnémonique, opérande). `make-tracer &key (max-size 1000)`, `tracer-reset`, `trace-step cpu tracer`, `run-with-tracer cpu tracer &key max-steps`, `tracer-entries-in-order &optional last`, `tracer-count`, `tracer-total`, `print-trace tracer &key (stream t) (last 20)`.
  - Les deux utilisent `handler-bind` (sans déroulement de pile) pour garantir l'enregistrement même lorsque le `handler-case` externe dans `run-with-profiler`/`run-with-tracer` capte `cpu-break`/`cpu-illegal-opcode` et remonte la pile.
- 78 tests dans `tests/test-profiler-6502.lisp` : profiler make/reset, hit count (simple, boucle), cycle count, accumulation sur plusieurs runs, valeurs de retour de `run-with-profiler`, smoke test `print-profile` ; tracer make/reset, entrée unique, snapshot registres, entrées multiples, dépassement circulaire, tampon non plein, dernières N entrées, cycles, valeurs de retour de `run-with-tracer`, smoke test `print-trace` ; tests unitaires `profile-step`/`trace-step` ; cohérence total-hits/tracer-count.

### Tests

| Suite | Tests |
|-------|-------|
| test-profiler-6502 | 78 |
| **Total** | **2906** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.18.0] — 2026-03-28

### Ajouté
- **Linker script multi-segments** (`src/core/linker-script.lisp`) : placement de plusieurs segments à des adresses distinctes avec table de symboles partagée, permettant les références croisées inter-segments (JSR, branches, constantes `.equ`). Structures `script-segment` (`:name`, `:at`, `:units`, `:fill`) et `script-result` (`:name`, `:address`, `:bytes`). Package `cl-asm/linker-script`.
- **`link-segments segments &key target`** : passe 1 sur tous les segments (dans l'ordre, chacun avec son adresse), puis passe 2 — retourne une liste de `script-result`. Backends supportés : tous ceux du linker (`:6502`, `:6510`, `:65c02`, `:45gs02`).
- **`segments->flat-binary results &key (fill #x00)`** : assemble les résultats en un vecteur contigu, remplissant les trous entre segments avec l'octet `fill`. Retourne `(values bytes base-address)`.
- 50 tests dans `tests/test-linker-script.lisp` : segment unique, deux segments indépendants, références croisées (JSR, branchement, `.equ`), segment multi-units, trois segments, backend 65C02, `segments->flat-binary` (vide, gap, octet de remplissage, adjacent, intégration), accesseurs, gestion d'erreurs.

### Tests

| Suite | Tests |
|-------|-------|
| test-linker-script | 50 |
| **Total** | **2828** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.17.0] — 2026-03-28

### Ajouté
- **Registre extensible d'émetteurs** (`src/core/emitters.lisp`) : `register-emitter keyword aliases extension fn desc-fr desc-en`, `find-emitter-by-keyword`, `find-emitter-by-alias`, `all-emitters`. Même architecture que `backends.lisp` et `disassemblers.lisp`. Ajouter un format de sortie = un fichier + un appel à `register-emitter`, sans modifier le CLI ni `output.lisp`. Package `cl-asm/emitters`.
- **Émetteur Intel HEX** (`src/emit/ihex.lisp`) : enregistrements `:LLAAAATT...CC` (16 octets/record), checksum complément à 2, enregistrement de fin `:00000001FF`. CLI : `--format ihex` → `.hex`. Package `cl-asm/emit.ihex`.
- **Émetteur Motorola S-record** (`src/emit/srec.lisp`) : S0 header (`cl-asm`), enregistrements de données S1 (16 octets/record), enregistrement de fin S9. Checksum complément à 1. CLI : `--format srec` → `.srec`. Package `cl-asm/emit.srec`.

### Modifié
- `src/emit/output.lisp` : `:bin` et `:prg` s'enregistrent maintenant dans le registre des émetteurs.
- `cl-asm-script.lisp` : `--format` utilise le registre (`find-emitter-by-alias`) au lieu d'un `ecase` codé en dur ; `default-output` lit l'extension depuis le registre (`:ihex` → `.hex`, `:srec` → `.srec`).

### Tests

| Suite | Tests |
|-------|-------|
| test-emitters | 32 |
| **Total** | **2778** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.16.0] — 2026-03-28

### Ajouté
- **Listing annoté avec cycles CPU** (`src/emit/output.lisp`) : nouvelle option `--listing` dans la CLI — génère un fichier `.lst` avec adresse, octets hex, mnémonique, opérande et nombre de cycles par instruction.
- **Table de cycles 6502** (`*cycles-6502*`) : 151 opcodes officiels. Chaque entrée `(base-cycles . extra-flag)` avec flag `0` (fixe), `1` (+1 si page-crossing), `2` (branche : +1 prise, +2 prise+page). Valide aussi pour le MOS 6510 (C64).
- **Table de cycles 65C02** (`*cycles-65c02*`) : hérite du 6502 et ajoute/corrige les opcodes 65C02 — BRA, STZ, PHX/PLX/PHY/PLY, TSB/TRB, zero-page-indirect, JMP(ind)=6cy (bug page-crossing corrigé). Valide pour Commander X16 et 45GS02 (approximatif).
- Correction du calcul de taille des instructions dans `emit-listing` : utilisation du désassembleur enregistré (6502/65C02/45GS02) pour avancer le PC correctement — le bug retournait systématiquement 1 octet par instruction.
- `emit-listing` / `write-listing` acceptent `&key target` (`:6502` `:6510` `:65c02` `:r65c02` `:45gs02`) pour activer les cycles et la taille correcte. Rétro-compatible : sans `target`, comportement identique à avant.
- Fallbacks désassembleur : `:6510` → `:6502`, `:r65c02` → `:65c02`.
- 40 tests dans `tests/test-listing.lisp`.

### Modifié
- `cl-asm-script.lisp` : nouvelle option `--listing` — génère `source.lst` dans le même répertoire que la source.
- `run-tests.sh` : ajout de `src/emit/output.lisp` après les désassembleurs (order correct pour les imports dynamiques).

### Tests

| Suite | Tests |
|-------|-------|
| test-listing | 40 |
| **Total** | **2746** |

### Correctifs (post-release)
- `tests/test-disasm-6502.lisp` : ajout de `(declare (ignore ...))` pour les liaisons `size`/`op` inutilisées dans les `multiple-value-bind` — supprime les STYLE-WARNINGs SBCL.
- `src/debugger/6502.lisp` : liaison de `*package*` à `cl-asm/debugger.6502` dans `read-from-string` pour les breakpoints conditionnels — supprime le warning `undefined variable: COMMON-LISP-USER::CPU`.
- `src/backend/6502.lisp` : ajout de la clause `:interactive` au restart `USE-VALUE` de `encode-relative` — supprime le warning `RESTART-CASE` de CLISP.
- `cl-asm-script.lisp` : suppression d'une parenthèse fermante superflue dans le bloc `--listing` — provoquait un crash `INPUT-ERROR-IN-LOAD` au démarrage (tous les tests de régression KO).
- `run-tests-clisp.lisp` / `run-tests-ecl.lisp` : mêmes corrections d'ordre de chargement et ajout de `test-listing`.

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.15.0] — 2026-03-28

### Ajouté
- **Backend Intel 8086/8088** (`src/backend/i8086.lisp`) : encodeur x86 16-bit mode réel complet. MOV (toutes formes), XCHG, LEA, LDS, LES, ALU (ADD/SUB/AND/OR/XOR/CMP + immédiats, formes courtes accumulateur), ADC/SBB, INC/DEC, NEG/NOT/MUL/IMUL/DIV/IDIV, décalages/rotations (ROL/ROR/RCL/RCR/SHL/SAL/SHR/SAR × 1/CL/imm8), PUSH/POP (reg/seg/imm), tous les Jcc (rel8), LOOP/LOOPE/LOOPNE/JCXZ, JMP (short/near/far/reg/mém), CALL (near/far/reg/mém), RET/RETF/IRET, INT/INTO/BOUND, IN/OUT, toutes les instructions implicites 1 octet (CLC/STC/CLI/STI/CLD/STD/CBW/CWD/XLAT/NOP/HLT/WAIT/LOCK/PUSHF/POPF/LAHF/SAHF/AAA/AAS/AAM/AAD/DAA/DAS/SALC/XLATB).
- Encodage octet ModRM : tous les modes d'adressage 8086 — `[BX+SI]`, `[BX+DI]`, `[BP+SI]`, `[BP+DI]`, `[SI]`, `[DI]`, `[BP]`, `[BX]`, adresse directe, avec déplacement 16 bits.
- Variable `*i8086-mode*` et hook `i8086-mnemonic-p` dans le parser classique — même schéma que Z80/M68K/8080 pour éviter les conflits de mnémoniques.
- `parse-i8086-operands`/`parse-i8086-mem-ref` dans `classic-parser.lisp` : références mémoire `[base+index+disp]`, `BYTE/WORD PTR [...]`, `SHORT expr` pour `JMP SHORT`.
- Backend enregistré sous les alias : `"8086"` `"i8086"` `"8088"` `"i8088"` `"ibmpc"` `"msdos"` `"x86-16"`.
- 236 tests dans `tests/test-8086.lisp`.

### Tests

| Suite | Tests |
|-------|-------|
| test-8086 | 236 |
| **Total** | **2706** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.14.0] — 2026-03-27

### Ajouté
- **Conditions/Restarts** (`src/core/restarts.lisp`) : protocole de restarts CL sur les erreurs d'assemblage — `use-value`, `use-zero` pour `asm-undefined-label` ; `skip-instruction` pour `asm-unknown-mnemonic`/`asm-syntax-error` ; `clamp-value`/`use-value` pour `asm-range-error` (branches hors portée).
- Macro `with-asm-use-zero` : résolution automatique des labels indéfinis à 0.
- Macro `with-asm-skip-errors` : ignore silencieusement les mnémoniques inconnus et les modes d'adressage non supportés.

### Modifié
- `symbol-table.lisp` : le helper `%signal-undefined-label` encapsule `asm-undefined-label` dans un `restart-case`.
- `6502.lisp` : `encode-instruction` ajoute le restart `skip-instruction` ; `encode-relative` ajoute les restarts `clamp-value` et `use-value`. Tout le comportement existant reste inchangé en l'absence de handler.

### Tests

| Suite | Tests |
|-------|-------|
| test-restarts | 14 |
| **Total** | **2470** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.13.0] — 2026-03-27

### Ajouté
- **Optimiseur peephole** (`src/core/optimizer.lisp`) : registre extensible — `register-peephole-optimizer`, `find-peephole-optimizer`, `optimize-sections`. Appelé avant la passe 1 quand `assemble` est invoqué avec `&key optimize t`.
- **Règles 6502/6510** (`src/optimizer/6502.lisp`) : règle A (élimination de JMP vers le label suivant), règle B (transformation JSR/RTS → JMP tail-call). Exportées sous le nom `*rules-6502*`.
- **Règles 65C02/45GS02** (`src/optimizer/65c02.lisp`) : règles A+B+C pour `:65c02` ; règles A+B seulement pour `:45gs02`. Règle C : `LDA #0 / STA :direct` → `STZ :direct` (index nil ou :x). Note : STZ sur 45GS02 signifie « Store Z register », la règle C est donc exclue pour cette cible.

### Tests

| Suite | Tests |
|-------|-------|
| optimizer-6502 (nouveau) | 28 |
| **Total** | **2456** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.12.0] — 2026-03-27

### Ajouté

**Linker modulaire en mémoire** (`src/core/linker.lisp`) — nouveau module :
- `link-unit` struct : encapsule les sections IR d'un fichier source parsé + cible architecturale
- `link-unit-from-program name program &optional target` : constructeur de commodité depuis un IR-PROGRAM
- `link units &key origin` : fusionne les sections de toutes les unités, crée une table de symboles partagée, exécute les deux passes → vecteur `(unsigned-byte 8)`
- Registre extensible : `register-linker-backend` / `find-linker-backend` / `all-linker-backends`
- Backends enregistrés : `:6502`, `:6510`, `:65c02`, `:45gs02`
- Références croisées de labels entre fichiers : chaque label défini dans une unité est résolu par les autres
- Validation : erreur si la liste est vide, si le backend est inconnu, ou si les cibles sont mixtes

### Tests

| Suite | 0.11.0 | 0.12.0 |
|---|---|---|
| linker-6502 (nouveau) | — | 26 |
| **TOTAL** | **2402** | **2428** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.11.0] — 2026-03-26

### Ajouté

**Registre extensible des désassembleurs** (`src/core/disassemblers.lisp`) — nouveau module :
- `register-disassembler` / `find-disassembler-by-keyword` / `all-disassemblers`
- Même conception que le registre des backends ; chaque désassembleur s'enregistre au chargement

**Désassembleur 45GS02** (`src/disassembler/45gs02.lisp`) — nouveau module :
- Dispatcher de préfixes complet : `$EA` (indirect-32), `$42` (branches longues), `$42 $42` (registre Q), `$42 $42 $EA` (Q indirect-32)
- Opcodes non-préfixés spécifiques 45GS02 : LDZ, STZ (registre Z), INZ, DEZ, PHZ, PLZ, TAZ, TZA, TBA, TAB, TSY, TYS, MAP, EOM, ASR, INW, DEW, ROW, NEG
- Hérite de la table de base 6502, remplace STZ ($84/$94 stocke le registre Z)
- Calcul de cible pour les branches longues (offset signé 16 bits, relatif à PC+4)
- Enregistré comme `:45gs02` avec les alias `"45gs02"` / `"mega65"`

**Désassembleur 65C02** (`src/disassembler/65c02.lisp`) — nouveau module :
- Table plate sans préfixe (même structure que le désassembleur 6502)
- Nouvelles instructions : BRA, STZ, TRB, TSB, PHX/PLX/PHY/PLY, INC A, DEC A
- Nouveaux modes : `:zero-page-indirect` → `($nn)`, `:indirect-absolute-x` → `($nnnn,X)`
- Modes étendus : LDA/STA/ADC/SBC/AND/ORA/EOR/CMP `($nn)`, JMP `($nnnn,X)`, BIT `#imm`/`zp,X`/`abs,X`
- Enregistré comme `:65c02` avec les alias `"65c02"` / `"x16"` / `"commander-x16"`

**Désassembleur pluggable dans le débogueur** (`src/debugger/6502.lisp`) :
- Nouveau slot `disasm-fn` dans la struct `debugger` (défaut : `#'cl-asm/disassembler.6502:disasm-one`)
- `make-debugger` accepte le mot-clé `:disasm-fn` ; `show-current`, `show-disasm`, `debugger-next` l'utilisent
- Le débogueur est maintenant indépendant de l'architecture pour l'affichage du désassemblage

### Tests

| Suite | 0.10.0 | 0.11.0 |
|---|---|---|
| disasm-45gs02 (nouveau) | — | 97 |
| disasm-65c02 (nouveau) | — | 44 |
| **TOTAL** | **2261** | **2402** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.10.0] — 2026-03-26

### Ajouté

**Backend MOS 6510** (`src/backend/6510.lisp`) — nouveau module :
- Étend le backend 6502 avec les **opcodes illégaux stables** utilisés dans les démos et jeux C64
- 14 nouveaux mnémoniques, 58 nouvelles entrées d'opcodes :
  - `LAX` — charge A et X simultanément (6 modes : zp / zp,Y / abs / abs,Y / (ind,X) / (ind),Y)
  - `SAX` — stocke A AND X (4 modes : zp / zp,Y / abs / (ind,X))
  - `SLO` — ASL mémoire puis ORA A (7 modes, alias ASO)
  - `RLA` — ROL mémoire puis AND A (7 modes)
  - `SRE` — LSR mémoire puis EOR A (7 modes, alias LSE)
  - `RRA` — ROR mémoire puis ADC A (7 modes)
  - `DCP` — DEC mémoire puis CMP A (7 modes, alias DCM)
  - `ISC` — INC mémoire puis SBC A (7 modes, alias ISB/INS)
  - `ALR` — AND #imm puis LSR A (1 mode, alias ASR)
  - `ANC` — AND #imm, bit 7 → C (1 mode)
  - `ARR` — AND #imm puis ROR A (1 mode, flags V/C non-standard)
  - `AXS` — (A AND X) − #imm → X, NZC mis à jour (1 mode, alias SBX)
  - `LAS` — (abs,Y) AND SP → A/X/SP (1 mode)
  - `KIL` — gèle le CPU / JAM (implied, opcode $02)
- Opcodes instables exclus (XAA/ANE, AHX/SHA, TAS/SHS, SHY, SHX)
- `assemble-6510` / `assemble-string-6510` / `assemble-file-6510` (avec `&key debug-map`)
- Aliases cible : `"6510"`, `"mos6510"`, `"c64"`

### Modifié

- `src/backend/6502.lisp` — alias `"c64"` déplacé vers le backend 6510 ; le 6502 n'enregistre plus que `"6502"` / `"mos6502"`
- `cl-asm.asd` — 6510 ajouté entre 6502 et 45gs02 dans le graphe de dépendances

### Tests

| Suite | 0.9.0 | 0.10.0 |
|---|---|---|
| 6510 (nouveau) | — | 66 |
| **TOTAL** | **2195** | **2261** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.9.0] — 2026-03-25

### Ajouté

**Débogueur 6502 — affichage ligne source** (`src/debugger/6502.lisp`) :
- `show-current` lit le fichier source réel quand `source-loc-file` est non-nil (rempli par `assemble-file`)
- Affiche `; fichier:ligne | texte source` au-dessus de la ligne désassemblée
- `source-cache` (hash filename → vecteur-de-lignes) dans la struct `debugger` — chaque fichier est lu une seule fois par session
- Surcoût nul quand aucun fichier n'est disponible (chemin `parse-string` ou pas de debug-map)

**Débogueur 6502 — breakpoints conditionnels dans le REPL** :
- Commande REPL `b $ADDR <expr-lisp>` compile une condition via `eval` : `(lambda (cpu) <expr>)`
- `cpu` est lié à la struct CPU ; utiliser le préfixe de package complet, ex. `(cl-asm/simulator.6502:cpu-a cpu)`
- Exemple : `b $0210 (= (cl-asm/simulator.6502:cpu-a cpu) #xFF)`
- Expression invalide : affiche un message d'erreur sans planter le REPL
- `b $ADDR` sans condition reste inconditionnel (comportement inchangé)

### Modifié

- `src/backend/6502.lisp` — `assemble-file` accepte désormais `&key debug-map` et le transmet à `assemble`

### Tests

| Suite | 0.8.0 | 0.9.0 |
|---|---|---|
| debugger-6502 | 68 | 80 |
| **TOTAL** | **2183** | **2195** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.8.0] — 2026-03-25

### Ajouté

**Watchpoints** — surveillance mémoire dans le débogueur 6502 :
- `set-watchpoint dbg addr &key kind` — `:read` | `:write` | `:rw` (défaut `:write`)
- `clear-watchpoint dbg addr`, `list-watchpoints dbg`
- Raccordés au simulateur via `cpu-watch-table` (hash-table addr → kind dans la struct `cpu`)
- Condition `cpu-watchpoint` (adresse, kind) signalée par `mem-read`/`mem-write` quand une entrée correspond
- `%step-one` capture `cpu-watchpoint` et retourne `:watchpoint` ; `debugger-last-watchpoint` stocke `(address kind)`
- Toutes les fonctions d'exécution (`step`, `next`, `continue`) retournent/gèrent `:watchpoint`
- Commandes REPL : `w $ADDR [read|write|rw]`, `dw $ADDR`, `lw`

### Modifié

- `src/simulator/6502.lisp` : struct `cpu` gagne un slot `watch-table` (nil par défaut — surcoût nul si non utilisé) ; `mem-read`/`mem-write` vérifient la table ; condition `cpu-watchpoint` définie
- `src/debugger/6502.lisp` : watchpoints entièrement raccordés ; struct `debugger` gagne le slot `last-watchpoint` ; aide REPL mise à jour

### Tests

| Suite | 0.7.0 | 0.8.0 |
|---|---|---|
| debugger-6502 | 56 | 68 |
| **TOTAL** | **2171** | **2183** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.7.0] — 2026-03-25

### Ajouté

**Débogueur 6502 interactif** (`src/debugger/6502.lisp`) — nouveau module :
- `make-debugger cpu &key debug-map` — créer une session débogueur
- `debugger-repl dbg &key input output` — REPL interactif avec support des string-streams (testable)
- `debugger-step` / `debugger-next` / `debugger-continue` — primitives d'exécution atomique
  - `next` implémente le step-over : saute entièrement le corps des sous-routines JSR
  - Retournent tous `:ok` | `:brk` | `:breakpoint` | `:illegal`
- `set-breakpoint dbg addr &key condition` — breakpoints inconditionnels (v0.7.0) ou conditionnels
  - Slot `condition` déjà présent pour les futurs `(lambda (cpu) → bool)`
- `clear-breakpoint`, `list-breakpoints` — gestion des breakpoints
- Struct `watchpoint` définie (raccordement simulateur : scope étendu)
- Helpers d'affichage : `show-registers`, `show-current`, `show-memory`, `show-disasm`
- `format-flags` — rendu du registre P sous la forme `NV-BDIZC` (majuscule = actif)
- Commandes REPL : `s`/`step`, `n`/`next`, `c`/`continue`, `b`/`d`/`lb`, `r`/`regs`, `m`/`mem`, `x`/`disasm`, `h`/`help`, `q`/`quit`, ligne vide = répéter

**Table adresse→source** (`src/core/debug-map.lisp`) — nouveau module :
- Struct `debug-map` : vecteur de 65536 entrées (adresse → source-loc)
- `make-debug-map`, `debug-map-get`, `debug-map-set`
- Défini dans `cl-asm/debug-map` (couche core) pour éviter toute dépendance circulaire entre backend et débogueur

### Modifié

**`src/backend/6502.lisp`** — `assemble` et `pass-2` acceptent `&key debug-map` :
- Si fournie, `pass-2` enregistre `adresse → source-loc` pour chaque instruction assemblée
- Surcoût nul quand `debug-map` est `nil` (défaut)

### Tests

| Suite | 0.6.0 | 0.7.0 |
|---|---|---|
| debugger-6502 (nouveau) | — | 56 |
| **TOTAL** | **2115** | **2171** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.6.0] — 2026-03-22

### Ajouté

**Simulateur CPU 6502** (`src/simulator/6502.lisp`) — nouveau module :
- Struct `cpu` avec registres A/X/Y/PC/SP/P et mémoire 64 Ko
- `make-cpu`, `reset-cpu`, `load-program`
- `mem-read`, `mem-write`, `mem-read16` (inline)
- `fetch`, `fetch16` — helpers inline de lecture d'opérandes au PC
- Helpers de mode d'adressage : `addr-zp`, `addr-zpx`, `addr-zpy`, `addr-abs`, `addr-absx*`, `addr-absy*`, `addr-indx`, `addr-indy*`
- Helpers flags : `set-flag`, `update-nz`, `flag-c/z/i/d/b/v/n`, 8 constantes de masque
- Pile : `stack-push`, `stack-pull`
- Helpers ALU : `do-adc` (avec flag V), `do-sbc`, `do-and`, `do-ora`, `do-eor`, `do-cmp`, `do-bit`, `do-asl`, `do-lsr`, `do-rol`, `do-ror`
- `step-cpu` : 152 opcodes couvrant le jeu d'instructions 6502 complet :
  - 23 implicites (NOP BRK TAX TXA TAY TYA TSX TXS PHA PLA PHP PLP INX INY DEX DEY CLC SEC CLI SEI CLV CLD SED)
  - Load/store : LDA×8, LDX×5, LDY×5, STA×7, STX×3, STY×3
  - ALU : ADC×8, SBC×8, AND×8, ORA×8, EOR×8, CMP×8, CPX×3, CPY×3, BIT×2
  - Décalages/rotations : ASL×5, LSR×5, ROL×5, ROR×5
  - Incréments mémoire : INC×4, DEC×4
  - Sauts/branches : JMP abs, JMP (ind) avec bug de page du 6502 original, JSR, RTS, RTI, BCC BCS BEQ BNE BMI BPL BVC BVS
- Pénalité de cycle sur franchissement de page (+1 lecture, fixe pour écritures)
- Conditions : `cpu-break`, `cpu-illegal-opcode`, `cpu-step-limit`
- `run-cpu` boucle jusqu'à BRK ou `max-steps`, retourne `(values cpu :brk|:step-limit)`

### Tests

| Suite | 0.5.0 | 0.6.0 |
|---|---|---|
| sim-6502 (nouveau) | — | 294 |
| **TOTAL** | **1627** | **1921** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.5.0] — 2026-03-22

### Ajouté

**Backend Intel 8080** (`src/backend/i8080.lisp`) — nouvelle architecture :
- Jeu d'instructions Intel 8080 complet (~78 mnémoniques) : MOV, MVI, LXI, LDA, STA, LHLD, SHLD, LDAX, STAX, INR, DCR, INX, DCX, DAD, ADD, ADC, SUB, SBB, ANA, XRA, ORA, CMP, ADI/ACI/SUI/SBI/ANI/XRI/ORI/CPI, JMP, CALL, RET, Jcc, Ccc, Rcc, PUSH, POP, IN, OUT, RST, NOP, HLT, XCHG, XTHL, PCHL, SPHL, DI, EI, RLC, RRC, RAL, RAR, DAA, CMA, STC, CMC
- Toutes les directives héritées du patron Z80 : `.org`, `.byte`, `.word`, `.dword`, `.fill`, `.padto`, `.assertpc`, `assert-size`, `.incbin`, `.defstruct`, `.defenum`, `.asciiz`, `.pascalstr`, `.petscii`
- Assemblage deux passes, table des symboles, références en avant
- Variable `*i8080-mode*` dans `cl-asm/parser` (même patron que `*z80-mode*`) — évite les conflits de mnémoniques avec le parser 6502
- API : `assemble-i8080`, `assemble-string-i8080`, `assemble-file-i8080`
- Alias du backend : `"i8080"`, `"8080"`, `"cpm"`, `"altair"`, `"intel8080"`

**Frontend `.lasm` — helpers Intel 8080 :**
- `(i8080r "A")` — opérande registre 8 bits (B C D E H L M A)
- `(i8080rp "H")` — opérande paire de registres (B D H SP PSW)
- `(i8080 "MOV" op1 op2)` — émet une instruction 8080 générique
- Dispatch cible : `(assemble-lasm-string src :target :i8080)`

**Ajouts dans `cl-asm/parser` :**
- `*i8080-mode*` defvar (NIL par défaut)
- `*i8080-mnemonics*` liste de tous les mnémoniques 8080
- `i8080-mnemonic-p` prédicat
- Le parser d'opérandes séparés par virgules réutilise le parser Z80 quand `*i8080-mode* = T`

### Tests

| Suite | 0.4.4 | 0.5.0 |
|---|---|---|
| i8080 (nouveau) | — | 144 |
| **TOTAL** | **1483** | **1627** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.4.4] — 2026-03-22

### Corrigé

**Convertisseur `acme2clasm` — lignes `label: !directive`** — les lignes combinant
un label et une directive ACME sur la même ligne (ex. `my_data: !byte $01, $02`)
étaient précédemment émises avec le texte brut de la directive au lieu d'être
converties. La partie directive est maintenant re-convertie récursivement en
syntaxe `.asm`.

### Tests

| Suite | 0.4.3 | 0.4.4 |
|---|---|---|
| acme2clasm | — | 20 |
| **TOTAL** | **1463** | **1483** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.4.3] — 2026-03-22

### Ajouté

**Directive `(petscii "str")`** — émet une chaîne avec conversion ASCII→PETSCII :
- Frontend Lisp (`.lasm`) : `(petscii "hello")`
- Frontend classique (`.asm`) : `.petscii "hello"` (alias → `:pet`)
- Minuscules a-z → PETSCII majuscules (A-Z) ; majuscules A-Z → jeu PETSCII shifted
- Supporté sur toutes les architectures : 6502, 65C02, R65C02, 45GS02, 65816, Z80, M68K

**Macro `(assert-size N body…)`** — vérifie qu'un bloc émet exactement N octets :
- Frontend Lisp (`.lasm`) : `(assert-size 16 (lda :imm 0) …)`
- Génère un label caché + directive `:assertsize` ; erreur si la taille réelle ≠ N
- Supporté sur toutes les architectures : 6502, 65C02, R65C02, 45GS02, 65816, Z80, M68K

**Directive `(sine-table label n amplitude offset)`** — table de lookup sinus :
- Émet N octets : `round(sin(2π·i/N) × amplitude + offset)` pour i dans [0, N)
- Exemple : `(sine-table 'sin-tbl 256 127 128)` → table 256 entrées, plage [1, 255]

**Directive `(cosine-table label n amplitude offset)`** — table de lookup cosinus :
- Identique à `sine-table` mais avec cosinus
- Exemple : `(cosine-table 'cos-tbl 256 127 128)`

**Directive `(linear-ramp label from to n)`** — table de rampe linéaire :
- Émet N octets interpolés linéairement de `from` à `to`
- Exemple : `(linear-ramp 'ramp 0 255 256)` → rampe 256 entrées de 0 à 255

### Tests

| Suite | 0.4.2 | 0.4.3 |
|---|---|---|
| lasm | 82 | 100 |
| **TOTAL** | **1445** | **1463** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.4.2] — 2026-03-22

### Ajouté

**Directive `.padto`** — remplit du PC courant jusqu'à une adresse absolue cible :
- Frontend classique (`.asm`) : `.padto ADDR` ou `.padto ADDR, VAL`
- Frontend Lisp (`.lasm`) : `(pad-to addr)` ou `(pad-to addr fill-val)`
- Supporté sur toutes les architectures : 6502, 65C02, R65C02, 45GS02, 65816, Z80, M68K
- Émet l'octet `VAL` (défaut `$00`) du PC courant jusqu'à `ADDR` ; erreur si PC > ADDR
- Si PC == ADDR : aucun octet émis

**Directive `.assertpc`** — assertion de layout : erreur si PC courant ≠ adresse attendue :
- Frontend classique (`.asm`) : `.assertpc ADDR`
- Frontend Lisp (`.lasm`) : `(assert-pc addr)`
- Supporté sur toutes les architectures : 6502, 65C02, R65C02, 45GS02, 65816, Z80, M68K
- Aucun octet émis ; le message d'erreur indique les valeurs attendue et réelle du PC

**Directive `.asciiz`** — émet une chaîne ASCII suivie d'un octet nul :
- Frontend classique (`.asm`) : `.asciiz "chaine"`
- Frontend Lisp (`.lasm`) : `(ascii-z "chaine")`
- Supporté sur toutes les architectures

**Directive `.pascalstr`** — émet une chaîne précédée d'un octet de longueur (style Pascal) :
- Frontend classique (`.asm`) : `.pascalstr "chaine"`
- Frontend Lisp (`.lasm`) : `(pascal-str "chaine")`
- Octet de longueur (max 255) suivi des octets de la chaîne ; supporté sur toutes les architectures

**Directive `defenum` / `.defenum`** — constantes nommées séquentielles :
- Frontend Lisp (`.lasm`) : `(defenum color :black :white :red)`
- Frontend classique (`.asm`) : bloc `.defenum`/`.val`/`.endenum`
- Valeurs numérotées à partir de 0 ; `ENUM.COUNT` défini automatiquement
- Supporté sur toutes les architectures

**Directive `include-binary` / `.incbin`** — inclut un fichier binaire comme données brutes :
- Frontend Lisp (`.lasm`) : `(include-binary "sprite.bin")` ou `(include-binary "fich" offset count)`
- Frontend classique (`.asm`) : `.incbin "fich"` ou `.incbin "fich", offset` ou `.incbin "fich", offset, count`
- Supporté sur toutes les architectures
- `offset` optionnel (saute les N premiers octets) et `count` (émet N octets) ; défaut = fichier entier
- Le listing affiche le nom du fichier et le nombre d'octets

**Directive `defstruct-asm` / `.defstruct`** — structure avec calcul automatique des offsets :
- Frontend Lisp (`.lasm`) : `(defstruct-asm player :x :y (:hp 2) :state)`
- Frontend classique (`.asm`) : bloc `.defstruct`/`.field`/`.endstruct`
- Champs : keyword = 1 octet ; `(keyword taille)` = N octets
- Définit les constantes `STRUCT.CHAMP` pour chaque champ + `STRUCT.SIZE` pour la taille totale
- Supporté sur toutes les architectures (6502, 65C02, R65C02, 45GS02, 65816, Z80, M68K)
- Listing développé : en-tête `.DEFSTRUCT` + une ligne `CHAMP = offset` par champ

**Frontend `.lasm` étendu à toutes les architectures** — `assemble-lasm-string` et `assemble-lasm`
supportent désormais toutes les cibles :
- `:6502` (défaut), `:45gs02`/`:mega65`, `:65c02`/`:x16`, `:r65c02`
- `:65816`/`:snes`/`:apple2gs`
- `:z80`/`:spectrum`/`:msx`/`:cpc` — helpers `(z80r)`, `(z80ind)`, `(zi)`
- `:m68k`/`:amiga`/`:atari`/`:mac68k` — helpers `(dn)`, `(an)`, `(ind-an)`, `(mi)`
- Nouveaux mnémoniques `.lasm` : 65C02 (`bra`, `stz`, `trb`, `tsb`, `phx/phy/plx/ply`) ;
  R65C02 (`rmb0-7`, `smb0-7`, `bbr0-7`, `bbs0-7`) ;
  65816 (`xba`, `xce`, `jsl`, `jml`, `brl`, `sep`, `rep`, `mvn`, `mvp`, `pea`, etc.)

### Tests

| Suite | 0.4.1 | 0.4.2 |
|---|---|---|
| 6502 | 82 | 94 |
| lasm | 58 | 82 |
| 6502 | 94 | 105 |
| m68k | 139 | 144 |
| **TOTAL** | **1398** | **1445** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.4.1] — 2026-03-22

### Ajouté

**Support natif de la syntaxe ACME** — le frontend classique de cl-asm accepte désormais
les fichiers source ACME directement sans conversion :
- `*=ADDR` — org style ACME (équivalent à `.org ADDR`)
- `!BYTE` / `!WORD` / `!FILL` — alias directs pour `.byte`/`.word`/`.fill`
- `!PET "str",n,...` — émission PETSCII : a-z → 0x41-0x5A (−0x20), A-Z → 0xC1-0xDA (+0x80) ; args numériques passés tels quels ; formes mixtes supportées (`!PET 147,"str",13,0`)
- `!to "file",cbm` — ignoré (nom de sortie géré par `--target`)
- `!cpu 65c02` — ignoré (CPU fixé par `--target`)

**Labels anonymes ca65** — `:` seul en début de ligne définit un label anonyme ;
`:-` / `:--` / `:---` référencent les 1er/2e/3e précédents ; `:+` / `:++` référencent
les 1er/2e suivants.

**Labels `@`-scopés ca65** — `@nom:` définit un label local à l'espace du dernier label
global ; `@nom` le référence. Deux routines peuvent chacune avoir leur propre `@loop:`
sans conflit.

**Directive `.res N`** — alias pour `.fill N` (réserve N octets, compatibilité ca65).

**`tests/regression/x16/06-bank-byte-operator.asm`** — test de régression pour `^` (opérateur octet de banque).

**`tests/regression/x16/07-anon-scoped-labels.asm`** — test de régression : labels anonymes, labels `@`-scopés, `.res`, `.byte "string"` inline, forward-ref immédiat.

**`tests/regression/x16/08-acme-directives.asm`** — test de régression : `!to`, `!cpu`, `*=`, `!BYTE`, `!PET` (conversion PETSCII vérifiée contre la sortie de l'assembleur ACME).

**Listes d'exclusion** — `tests/regression/x16/.ca65-skip` et `.acme-skip` pour gérer les fichiers spécifiques à une syntaxe.

### Corrigé

**Taille forward-ref immédiat en passe 1** — `ldx #<forward_label` estimait 3 octets (max pour LDX) au lieu de 2 en passe 1, décalant toutes les adresses suivantes. Désormais estime correctement 2 octets en mode immédiat quelle que soit la résolution.

**`ASL`/`LSR`/`ROL`/`ROR` sans opérande** — `:implied` bascule maintenant vers `:accumulator` lorsqu'aucune clause `:implied` n'existe (ex. `ASL` seul = `ASL A`).

**`.byte "string"` inline** — les arguments chaîne de `.byte` étaient incorrectement transmis à l'évaluateur d'expressions. Désormais traités séparément en passe 1 (estimation taille) et passe 2 (émission d'octets).

**`acme2clasm` — conversion `!PET`** — les formes à arguments mixtes (`"str",13,0` et `147,"str",0`) sont désormais correctement gérées ; conversion PETSCII appliquée (a-z → A-Z, A-Z → shifted).

### Tests

| Suite | 0.4.0 | 0.4.1 |
|---|---|---|
| symbol-table | 65 | 65 |
| expression | 129 | 129 |
| lexer | 119 | 119 |
| parser | 84 | 84 |
| macros | 27 | 27 |
| conditional | 27 | 27 |
| lasm | 58 | 58 |
| 6502 | 82 | 82 |
| **65c02** | **41** | **86** |
| r65c02 | 117 | 117 |
| 45gs02 | 80 | 80 |
| 65816 | 104 | 104 |
| z80 | 191 | 191 |
| m68k-parser | 85 | 85 |
| m68k | 144 | 144 |
| **TOTAL** | **1353** | **1398** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.4.0] — 2026-03-21

### Ajouté

**Backend Motorola 68000** — nouveau fichier `src/backend/m68k.lisp`
(package `cl-asm/backend.m68k`) supportant le processeur M68K (Amiga, Atari ST, Mac 68k) :

- Alias CLI : `m68k`, `68000`, `68k`, `amiga`, `atari`, `mac68k`, `atarist`
- Origine par défaut `$0000`
- Jeu d'instructions complet M68K :
  - Transfert de données : `MOVE`, `MOVEA`, `MOVEQ`, `MOVEM`, `MOVEP`, `LEA`, `PEA`, `EXG`, `SWAP`
  - Arithmétique : `ADD`, `ADDI`, `ADDQ`, `ADDA`, `SUB`, `SUBI`, `SUBQ`, `SUBA`, `MULS`, `MULU`, `DIVS`, `DIVU`, `ABCD`, `SBCD`, `NBCD`
  - Logique : `AND`, `ANDI`, `OR`, `ORI`, `EOR`, `EORI`, `NOT`
  - Comparaison : `CMP`, `CMPI`, `CMPA`, `CMPM`, `TST`
  - Décalages : `ASL`, `ASR`, `LSL`, `LSR`, `ROL`, `ROR`, `ROXL`, `ROXR` (immédiat, registre, mémoire)
  - Manipulation de bits : `BTST`, `BSET`, `BCLR`, `BCHG`
  - Unaires : `CLR`, `NEG`, `NEGX`, `EXT`, `EXTB`
  - Branchements/sauts : `BRA`, `BSR`, `Bcc` (14 conditions), `DBcc`, `JMP`, `JSR`, `RTS`, `RTR`, `RTE`
  - Système : `TRAP`, `TRAPV`, `LINK`, `UNLK`, `NOP`, `STOP`, `RESET`, `ILLEGAL`, `CHK`
  - Tous les modes d'adressage : Dn, An, (An), (An)+, -(An), d(An), d(An,Xi), abs.W, abs.L, d(PC), d(PC,Xi), #imm
- Encodage big-endian via `words->bytes`

**Tests parser M68K** — `tests/test-m68k-parser.lisp` : 85 tests couvrant le parsing des opérandes M68K, modes EA, suffixes de taille, syntaxe des registres.

**Tests backend M68K** — `tests/test-m68k.lisp` : 139 tests répartis en 17 groupes :
implied, MOVE, MOVEA, MOVEQ, ADD/ADDI/ADDQ/ADDA, SUB/SUBI/SUBQ/SUBA,
AND/ANDI, OR/ORI, EOR/EORI, CMP/CMPI/CMPA, MULDIV, décalages, unaires (CLR/NEG/etc.),
EXT/SWAP, JMP/JSR/LEA, branchements/DBcc, divers (LINK/UNLK/TRAP/EXG/BCD), bit ops,
labels, modes d'adressage.

### Modifié

**`src/core/version.lisp`** — version incrémentée : `0.3.0` → `0.4.0`

**Scripts de test** — `run-tests.sh`, `run-tests-clisp.lisp`, `run-tests-ecl.lisp`
chargent désormais `src/backend/m68k.lisp`, `tests/test-m68k-parser.lisp` et `tests/test-m68k.lisp`.

**`tests/run-tests.lisp`** — ajout de `run-suite cl-asm/test.m68k-parser` et `run-suite cl-asm/test.m68k` ; nouvelle section « Parsers architectures » dans le bilan.

### Tests

| Suite | 0.3.0 | 0.4.0 |
|---|---|---|
| symbol-table | 65 | 65 |
| expression | 129 | 129 |
| lexer | 119 | 119 |
| parser | 84 | 84 |
| macros | 27 | 27 |
| conditionnel | 27 | 27 |
| lasm | 58 | 58 |
| 6502 | 82 | 82 |
| 65c02 | 41 | 41 |
| r65c02 | 117 | 117 |
| 45gs02 | 80 | 80 |
| 65816 | 104 | 104 |
| z80 | 191 | 191 |
| **m68k-parser** | — | **85** |
| **m68k** | — | **139** |
| **TOTAL** | **1124** | **1348** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.3.0] — 2026-03-21

### Ajouté

**Backend Zilog Z80** — nouveau fichier `src/backend/z80.lisp`
(package `cl-asm/backend.z80`) supportant le processeur Z80 (ZX Spectrum, MSX, CPC, ZX81) :

- Alias CLI : `z80`, `z80cpu`, `zx80`, `zx81`, `zxspectrum`, `spectrum`, `cpc`, `msx`
- Origine par défaut `$0000`
- Jeu d'instructions complet Z80 :
  - Instructions implied, LD complet (44 formes), ALU (ADD/ADC/SUB/SBC/AND/OR/XOR/CP)
  - INC/DEC registres 8/16 bits et indirects
  - PUSH/POP BC/DE/HL/AF/IX/IY
  - EX DE,HL / EX (SP),HL/IX/IY / EXX
  - Rotations/shifts CB : RLC/RRC/RL/RR/SLA/SRA/SRL/SLL
  - BIT/SET/RES (CB prefix) + formes (IX+d)/(IY+d) (DD CB/FD CB)
  - JP/JR conditionnel et inconditionnel, CALL/RET conditionnel
  - DJNZ (branche relative avec décrément B)
  - IN r,(C) / IN A,(n) / OUT (C),r / OUT (n),A
  - Instructions étendues ED : NEG, RETN, RETI, RLD, RRD, IM 0/1/2
  - Opérations sur blocs : LDI/LDIR/LDD/LDDR/CPI/CPIR/CPD/CPDR/INI/INIR/IND/INDR/OUTI/OTIR/OUTD/OTDR
  - RST $00-$38

**Gestion des conflits de mnémoniques** — variable `cl-asm/parser:*z80-mode*` :
  - Certains mnémoniques Z80 (`INC`, `DEC`, `AND`, `BIT`, `ADC`…) existent aussi en 6502.
  - `*z80-mode*` est NIL par défaut ; mis à T par `assemble-string-z80` / `assemble-file-z80` pendant le parsing.
  - Évite tout conflit de parsing entre backends sans modifier le parser 6502.

**Tests Z80** — `tests/test-z80.lisp` : 191 tests répartis en 19 groupes :
instructions implied, LD r/r' et n, LD indirect, LD 16 bits, LD mémoire,
PUSH/POP, INC/DEC, ALU, rotations CB, BIT/SET/RES, JP/JR/CALL/RET/DJNZ,
EX/EXX, IN/OUT, ADD IX/IY, divers (IM/blocs), directives, forward references,
programme ZX Spectrum minimal, erreurs attendues.

### Modifié

**`src/core/version.lisp`** — version incrémentée : `0.2.0` → `0.3.0`

**`src/frontend/classic-parser.lisp`** — ajout du dispatch Z80 dans `parse-line`
et des helpers : `*z80-mode*`, `*z80-mnemonics*`, `z80-mnemonic-p`,
`z80-comma-is-6502-index-p`, `parse-z80-operand-raw`, `parse-z80-operands`.

**Scripts de test** — `run-tests.sh`, `run-tests-clisp.lisp`, `run-tests-ecl.lisp`
chargent désormais `src/backend/z80.lisp` et `tests/test-z80.lisp`.

### Tests

| Suite | 0.2.0 | 0.3.0 |
|---|---|---|
| symbol-table | 65 | 65 |
| expression | 129 | 129 |
| lexer | 119 | 119 |
| parser | 84 | 84 |
| macros | 27 | 27 |
| conditionnel | 27 | 27 |
| lasm | 58 | 58 |
| 6502 | 82 | 82 |
| 65c02 | 41 | 41 |
| r65c02 | 117 | 117 |
| 45gs02 | 80 | 80 |
| 65816 | 104 | 104 |
| **z80** | — | **191** |
| **TOTAL** | **933** | **1124** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, ECL.

---

## [0.2.0] — 2026-03-20

### Ajouté

**Backend WDC 65816** — nouveau fichier `src/backend/65816.lisp`
(package `cl-asm/backend.65816`) supportant le processeur WDC 65816 (SNES, Apple IIgs) :

- Origine par défaut `$8000` (SNES LoROM bank 0)
- Alias CLI : `65816`, `wdc65816`, `snes`, `apple2gs`
- 20+ modes d'adressage, dont :
  - `:absolute-long` / `:absolute-long-x` — adresses 24 bits (`$xxxxxx`)
  - `:dp-indirect-long` / `:dp-indirect-long-y` — `[$nn]`, `[$nn],Y`
  - `:stack-relative` / `:sr-indirect-y` — `$nn,S`, `($nn,S),Y`
  - `:relative-long` — branches 16 bits signées (BRL, PER)
  - `:block-move` — deux opérandes banque (MVN, MVP)
- **Accumulateur et index 16 bits** — immédiat variable selon les flags M/X :
  - `.al`/`.as` — bascule l'accumulateur entre 16 bits et 8 bits
  - `.xl`/`.xs` — bascule les index X/Y entre 16 bits et 8 bits
  - `REP`/`SEP` — instructions pour modifier les flags en dynamique
- `JSL`/`JML` — saut long 24 bits (4 et 3 octets)
- `BRL`/`PER` — branche longue / push effective relative address
- `MVN`/`MVP` — block move (deux opérandes banque séparés par une virgule)
- `PEA` — push effective address (toujours 16 bits)
- Toutes les instructions 6502 de base héritées

**Parser étendu** — `src/frontend/classic-parser.lisp` :
- Directives `.al`, `.as`, `.xl`, `.xs` ajoutées à `*directive-names*`
- Parsing multi-opérandes étendu (MVN/MVP) en parallèle des BBR/BBS R65C02

**Tests 65816** — `tests/test-65816.lisp` : 104 tests répartis en 12 groupes :
compatibilité 6502, instructions implied, absolute long, JSL/JML,
dp-indirect-long, JMP indirect long, stack-relative, BRL, REP/SEP,
directives de mode + immédiat 16 bits, block move, PEA, forward references,
erreurs, programme SNES minimal.

### Modifié

**`src/core/version.lisp`** — version incrémentée : `0.1.3` → `0.2.0`

**Scripts de test** — `run-tests.sh`, `run-tests-clisp.lisp`, `run-tests-ecl.lisp`
chargent désormais `src/backend/65816.lisp` et `tests/test-65816.lisp`.

### Tests

| Suite | 0.1.3 | 0.2.0 |
|---|---|---|
| symbol-table | 65 | 65 |
| expression | 129 | 129 |
| lexer | 119 | 119 |
| parser | 84 | 84 |
| macros | 27 | 27 |
| conditionnel | 27 | 27 |
| lasm | 58 | 58 |
| 6502 | 82 | 82 |
| 65c02 | 41 | 41 |
| r65c02 | 117 | 117 |
| 45gs02 | 80 | 80 |
| **65816** | — | **104** |
| **TOTAL** | **829** | **933** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+.

---

## [0.1.3] — 2026-03-20

### Ajouté

**Registre extensible de backends** — nouveau module `src/core/backends.lisp`
(package `cl-asm/backends`) centralisant la déclaration des backends d'assemblage.
Chaque backend s'enregistre via `register-backend` en fin de son fichier source.
Ajouter une nouvelle architecture ne nécessite plus de modifier le script CLI.

- `register-backend keyword aliases package function desc-fr desc-en`
- `find-backend-by-alias alias` — résolution CLI string → keyword
- `all-backends` — liste ordonnée des backends enregistrés

### Modifié

**`cl-asm-script.lisp` refactorisé** — plus aucun `ecase` codé en dur :

- `assemble-source` délègue via le registre
- Parsing `--target` utilise `find-backend-by-alias` (insensible à la casse)
- `print-usage` génère dynamiquement la liste des alias CLI
- `detect-target` itère sur `all-backends`
- Alias supplémentaires : `mos6502`, `c64`, `mega65`, `65c02`, `commander-x16`, `rockwell`

**`src/backend/45gs02.lisp`** — ajout de `assemble-file-45gs02` (manquante)
et de son export.

**Scripts de test** — `run-tests.sh`, `run-tests-clisp.lisp`, `run-tests-ecl.lisp`
chargent désormais `src/core/backends.lisp` après `version.lisp`.

### Tests

| Suite | 0.1.2 | 0.1.3 |
|---|---|---|
| Toutes suites | 829 | 829 |
| **TOTAL** | **829** | **829** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+.

---

## [0.1.2] — 2026-03-17

### Ajouté

**Backend Rockwell R65C02** — nouveau backend `src/backend/r65c02.lisp`
supportant les 32 instructions spécifiques au R65C02 (variante Rockwell du WDC 65C02) :

- `RMB0`..`RMB7` — Reset Memory Bit (opcode `$n7`, 2 octets, zero-page)
- `SMB0`..`SMB7` — Set Memory Bit (opcode `$n7 + $80`, 2 octets, zero-page)
- `BBR0`..`BBR7` — Branch on Bit Reset (opcode `$nF`, 3 octets, zero-page + relatif)
- `BBS0`..`BBS7` — Branch on Bit Set (opcode `$nF + $80`, 3 octets, zero-page + relatif)

Le backend hérite de `cl-asm/backend.65c02`. Les instructions `BBRn`/`BBSn`
prennent deux opérandes séparés par une virgule : adresse zero-page et étiquette.

**Helpers Rockwell dans le parser** — nouvelles fonctions exportées depuis
`cl-asm/parser` : `rockwell-mnemonic-p`, `rockwell-bit-number`,
`rockwell-opcode`, `rockwell-two-operands-p`.

**Tests R65C02** — `tests/test-r65c02.lisp` : 10 suites de tests.

---

## [0.1.1] — 2026-03-15

Patch de corrections et outillage de régression.

### Corrigé

**Bug `define-label` vs constantes** — `define-label` déclenchait une erreur
"Label défini plusieurs fois" quand un label portait le même nom qu'une
constante déjà définie (ex : `COLOR = $D800` puis `color_lp:`). La table des
symboles distingue maintenant les kinds `:label`, `:constant` et `:equate`.

**Script `cl-asm`** — correction de la sélection de cible : remplacement des
variables booléennes `USE_45GS02`/`USE_X16` par un `ecase target` Lisp dans
un fichier temporaire, éliminant les problèmes de quoting shell dans `--eval`.

**Lexer** — octets nuls et caractères non-ASCII ignorés silencieusement hors
commentaires. Élimine les erreurs "Caractère inattendu : #\\Nul".

**`acme2clasm`** — `!cpu m65` → `; target: 45gs02`, `!cpu 65c02` →
`; target: x16`. Normalisation NFD des accents (Latin-1 → ASCII). Suppression
des octets nuls à la lecture.

### Ajouté

**Backend 65C02 (Commander X16)** — `BRA`, `STZ`, `TRB`, `TSB`,
`PHX`/`PLX`/`PHY`/`PLY`, `INC A`/`DEC A`, mode `:zero-page-indirect`,
`JMP ($addr,X)`, modes étendus pour `BIT` et les instructions ALU.

**`encode-instruction`** — paramètres `&key table resolve-fn` pour la
délégation propre entre backends.

**Versioning** — module `cl-asm/version` (`+version+`, `+version-patch+`…).

**Framework de régression** — `tests/regression/` avec :
- `run-regression.sh` — modes `--update`, `--clear`, `--verbose`
- `config.sh` — ACME et ca65/ld65, conversion automatique de syntaxe
- `c64/*.asm` — 7 fichiers de test C64
- `.acme-skip` / `.ca65-skip` — exclusions documentées

**Exemples X16** — `x16-hello.asm`, `x16-minimal.asm`, `x16-debug.asm`
fonctionnels sous émulateur, via `CHROUT`.

### Tests

| Suite | 0.1.0 | 0.1.1 | 0.1.2 | 0.1.3 |
|---|---|---|---|---|
| symbol-table | 59 | 61 | 65 | 65 |
| expression | — | — | 129 | 129 |
| lexer | — | — | 119 | 119 |
| parser | — | — | 84 | 84 |
| macros | — | — | 27 | 27 |
| conditionnel | — | — | 27 | 27 |
| lasm | — | — | 58 | 58 |
| 6502 | — | — | 82 | 82 |
| 65c02 | — | 41 | 41 | 41 |
| r65c02 | — | — | 117 | 117 |
| 45gs02 | — | — | 80 | 80 |
| **TOTAL** | **647** | **706** | **829** | **829** |

**Régression binaire** : 5/5 OK vs ACME, 6/6 OK vs ca65.

---

### Modifié

**Framework de régression — config par famille d'architectures** —
`config.sh` renommé en `config-6502.sh` et étendu avec `config_handles_target()`
pour déclarer les cibles qu'il gère (`c64`, `mega65`, `x16`).
`run-regression.sh` charge désormais dynamiquement le bon `config-<arch>.sh`
selon la cible traitée, via `find_config_for_target()` / `load_config_for_target()`.
Chaque cible charge son propre config indépendamment dans les boucles `--update`
et test. L'en-tête de section affiche le compilateur actif (`=== c64 (acme) ===`).
Ajouter le support d'une nouvelle architecture (Z80, 68000…) ne nécessite
plus de modifier `run-regression.sh` — il suffit de créer `config-z80.sh`
avec `ref_assemble()`, `ref_check_available()` et `config_handles_target()`.
`README.md` du dossier de régression mis à jour en conséquence.

---

---

## [0.1.0] — 2026-03-15

Première version fonctionnelle. L'assembleur est utilisable en ligne de
commande et depuis un REPL Common Lisp. Testé sous SBCL 2.6.2, CLISP
2.49.95+ et SLIME sur Linux.

### Ajouté

**Infrastructure**
- IR (Représentation Intermédiaire) — pivot entre frontends et backends
- Évaluateur d'expressions — 28 opérateurs, forward-references, 2 passes
- Table des symboles — labels, constantes, équates, portées locales,
  labels numériques (style `1:` `1-` `1+`), relocations
- ASDF — chargement incrémental, `(asdf:test-system "cl-asm")`
- Quicklisp — `(ql:quickload "cl-asm")`
- Versioning — `cl-asm/version:+version+` → `"0.1.0"`

**Frontend classique (syntaxe ca65-like)**
- Lexer — littéraux `$FF` `%1010` `0xFF` `'A'`, labels, opérateurs
- Parser — tous les modes d'adressage 6502 et 45GS02, expressions
- Macros textuelles — `.macro`/`.endmacro`, paramètres, labels locaux
  uniques par invocation (préfixe `__`)
- Assemblage conditionnel — `.if`/`.else`/`.endif`, imbrication,
  constantes évaluées au parsing (pas de forward-references)

**Frontend .lasm (Lisp natif)**
- Fichiers source = Common Lisp valide exécuté dans `cl-asm/lasm`
- Toute la puissance de CL disponible : `dotimes`, `loop`, `defun`…
- Convention de modes : sans keyword = déduit, avec keyword = explicite
  (`:imm`, `:x`, `:y`, `:z`, `:ind`, `:ix`, `:iy`, `:abs`, `:zp`, `:a`)
- Directive `(target :45gs02)` pour la détection automatique de cible

**Backend 6502**
- 56 mnémoniques, tous les modes d'adressage
- Sélection automatique zero-page vs absolu
- 2 passes avec résolution des forward-references
- `assemble`, `assemble-string`, `assemble-file`

**Backend 45GS02 (Mega65)**
- Superset 6502 : registres Z, B, Q 32 bits
- Instructions : `LDZ`/`STZ`, `INZ`/`DEZ`, `TAZ`/`TZA`, `TAB`/`TBA`,
  `LDQ`/`STQ`, ALU Q, branches longues 16 bits (`LBNE`…)
- Modes : `($nn),Z`, `$nnnn,Z`, `[$nn]`, `[$nn],Z`, `($nn,SP),Y`
- Préfixes `$42`, `$42 $42`, `$EA`

**Backend 65C02 (Commander X16)**
- Superset 6502 : nouvelles instructions WDC
- `BRA` (branche inconditionnelle), `STZ`, `TRB`, `TSB`
- `PHX`/`PLX`/`PHY`/`PLY`, `INC A`/`DEC A`
- Mode `($nn)` indirect ZP sans index
- `JMP ($addr,X)` indirect absolu indexé X
- Modes étendus pour `BIT`, `ADC`/`SBC`/`AND`/`ORA`/`EOR`/`CMP`

**Émetteurs**
- BIN — binaire brut sans header
- PRG — format C64/Mega65 : 2 octets header LE + binaire
- Listing annoté — adresse | hex | source

**Outillage**
- `./cl-asm` — script ligne de commande avec détection automatique
  de cible (`; target: 45gs02`, `; target: x16`, `(target :45gs02)`)
- `./acme2clasm` — convertisseur ACME → cl-asm
  (`!addr`, `!byte`/`!8`, `!word`/`!16`, `!pet`, `!fill`, `!align`,
  `!macro`, `!if`, `!source`, `!cpu m65`→`; target: 45gs02`)

**Exemples**
- `examples/c64-raster.asm` — raster bar C64 avec macros et `.if DEBUG`
- `examples/mega65-hello.lasm` — hello world Mega65 en syntaxe .lasm
- `examples/mega65-minimal.lasm` — programme Mega65 minimaliste
- `examples/x16-hello.asm` — hello world X16 via CHROUT
- `examples/x16-minimal.asm` — programme X16 minimaliste via CHROUT
- `examples/x16-debug.asm` — programme de diagnostic X16 (BRK)

### Tests

| Suite | Tests |
|---|---|
| symbol-table | 59 |
| expression | 129 |
| lexer | 119 |
| parser | 84 |
| macros | 27 |
| conditionnel | 27 |
| lasm | 58 |
| 6502 | 82 |
| 65c02 | 41 |
| 45gs02 | 80 |
| **TOTAL** | **706** |

0 KO, 0 warnings — SBCL 2.6.2, CLISP 2.49.95+, SLIME.

### Limitations connues

- Assemblage conditionnel : les forward-references ne sont pas supportées
  dans les expressions `.if` — seuls les symboles définis *avant* le `.if`
  sont visibles.
- Macros textuelles : les arguments sont des tokens uniques (pas
  d'expressions multi-tokens comme paramètres).
- Frontend .lasm : `(target :45gs02)` est une directive no-op à
  l'exécution — utilisée uniquement par le script `cl-asm`.
- Accès direct VERA (X16) : non testé sur hardware réel, les programmes
  d'exemple utilisent CHROUT par sécurité.

### Architectures non supportées

Z80, 68000, ARM32, ARM64, x86-64 — prévus pour des versions futures.

---
