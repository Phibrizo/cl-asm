#!/bin/bash
# tests/regression/run-regression.sh
#
# Tests de régression : compare les binaires produits par cl-asm
# avec ceux du compilateur de référence (acme par défaut).
#
# Usage :
#   ./run-regression.sh                  # tous les tests
#   ./run-regression.sh c64              # architecture spécifique
#   ./run-regression.sh c64 01-nop       # fichier spécifique (sans .asm)
#   ./run-regression.sh --verbose c64    # mode détaillé
#   ./run-regression.sh --update c64     # régénérer les binaires de référence
#   ./run-regression.sh --clear c64      # supprimer les binaires de référence
#   ./run-regression.sh --clear          # supprimer tous les binaires de référence
#
# Structure attendue :
#   tests/regression/<target>/*.asm      fichiers source
#   tests/regression/<target>/*.ref.prg  binaires de référence (générés)
#
# Codes de retour :
#   0 : tous les tests passent
#   1 : au moins un test échoue

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CL_ASM="$SCRIPT_DIR/../../cl-asm"

# --------------------------------------------------------------------------
#  Résolution du fichier de config selon la cible
#
#  Chaque architecture dispose de son propre config-<arch>.sh qui expose :
#    REF_COMPILER            — compilateur de référence
#    ref_assemble()          — assemble avec le compilateur de référence
#    ref_check_available()   — vérifie la disponibilité du compilateur
#    config_handles_target() — retourne 0 si ce config gère la cible
#
#  Quand TARGET_FILTER est vide (toutes les cibles), chaque dossier
#  cible est associé au premier config-*.sh dont config_handles_target
#  retourne 0.
# --------------------------------------------------------------------------

# Retourne le fichier config-*.sh qui gère TARGET, ou "" si aucun.
find_config_for_target() {
    local target="$1"
    for cfg in "$SCRIPT_DIR"/config-*.sh; do
        [[ ! -f "$cfg" ]] && continue
        # Sourcer dans un sous-shell pour isoler les variables
        if ( source "$cfg" 2>/dev/null && config_handles_target "$target" ); then
            echo "$cfg"
            return 0
        fi
    done
    return 1
}

# Charge le fichier de config approprié pour TARGET dans le shell courant.
# En cas d'échec, affiche un message et quitte.
load_config_for_target() {
    local target="$1"
    local cfg
    cfg=$(find_config_for_target "$target")
    if [[ -z "$cfg" ]]; then
        echo "Erreur : aucun fichier config-*.sh ne gère la cible '$target'." >&2
        echo "Créer tests/regression/config-<arch>.sh avec config_handles_target()." >&2
        exit 1
    fi
    source "$cfg"
}

# --------------------------------------------------------------------------
#  Options
# --------------------------------------------------------------------------

VERBOSE=0
UPDATE=0
CLEAR=0
TARGET_FILTER=""
FILE_FILTER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v) VERBOSE=1 ; shift ;;
        --update|-u)  UPDATE=1  ; shift ;;
        --clear|-c)   CLEAR=1   ; shift ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | grep "^#" | sed 's/^# \?//'
            exit 0
            ;;
        -*)
            echo "Option inconnue : $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "$TARGET_FILTER" ]]; then
                TARGET_FILTER="$1"
            else
                FILE_FILTER="$1"
            fi
            shift
            ;;
    esac
done

# --------------------------------------------------------------------------
#  Couleurs
# --------------------------------------------------------------------------

if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    RESET='\033[0m'
else
    GREEN='' RED='' YELLOW='' BLUE='' RESET=''
fi

# --------------------------------------------------------------------------
#  Fonctions utilitaires
# --------------------------------------------------------------------------

log()     { echo -e "$1" ; }
ok()      { echo -e "  ${GREEN}OK${RESET}  $1" ; }
fail()    { echo -e "  ${RED}KO${RESET}  $1" ; }
skip()    { echo -e "  ${YELLOW}[SKIP]${RESET}  $1" ; }
info()    { [[ $VERBOSE -eq 1 ]] && echo -e "      $1" ; }

# Comparaison binaire avec rapport de différences
compare_binaries() {
    local ref="$1"
    local out="$2"

    if cmp -s "$ref" "$out"; then
        return 0
    fi

    local diff_offset
    diff_offset=$(cmp -l "$ref" "$out" 2>/dev/null | head -1 | awk '{print $1}')
    if [[ -n "$diff_offset" ]]; then
        local ref_byte out_byte
        ref_byte=$(dd if="$ref" bs=1 skip=$((diff_offset-1)) count=1 2>/dev/null | xxd -p)
        out_byte=$(dd if="$out" bs=1 skip=$((diff_offset-1)) count=1 2>/dev/null | xxd -p)
        info "Premier octet différent à offset $diff_offset : ref=0x${ref_byte} got=0x${out_byte}"
    fi

    local ref_size out_size
    ref_size=$(wc -c < "$ref")
    out_size=$(wc -c < "$out")
    if [[ $ref_size -ne $out_size ]]; then
        info "Tailles différentes : ref=$ref_size octets, got=$out_size octets"
    fi

    return 1
}

# Charger la skip-list d'un répertoire pour le compilateur courant
# Usage : load_skip_list <target_dir>
# Résultat dans le tableau associatif global SKIP_LIST
load_skip_list() {
    unset SKIP_LIST
    declare -gA SKIP_LIST
    local skip_file="${1}/.${REF_COMPILER}-skip"
    if [[ -f "$skip_file" ]]; then
        while IFS= read -r entry; do
            [[ "$entry" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${entry// }" ]] && continue
            SKIP_LIST["$entry"]=1
        done < "$skip_file"
    fi
}

# --------------------------------------------------------------------------
#  Mode --clear : supprimer les binaires de référence
# --------------------------------------------------------------------------

if [[ $CLEAR -eq 1 ]]; then
    log "${YELLOW}Suppression des binaires de référence${RESET}"
    cleared=0

    for target_dir in "$SCRIPT_DIR"/*/; do
        target=$(basename "$target_dir")
        [[ -n "$TARGET_FILTER" && "$target" != "$TARGET_FILTER" ]] && continue
        [[ ! -d "$target_dir" ]] && continue

        for ref in "${target_dir}"/*.ref.prg; do
            [[ ! -f "$ref" ]] && continue
            base=$(basename "$ref" .ref.prg)
            [[ -n "$FILE_FILTER" && "$base" != "$FILE_FILTER" ]] && continue
            rm -f "$ref"
            log "  Supprimé : $target/$base.ref.prg"
            ((cleared++))
        done
    done

    log ""
    log "Supprimé : $cleared fichier(s)"
    exit 0
fi

# --------------------------------------------------------------------------
#  Mode --update : régénérer les binaires de référence
# --------------------------------------------------------------------------

if [[ $UPDATE -eq 1 ]]; then
    log "${BLUE}Régénération des binaires de référence${RESET}"
    updated=0
    errors=0

    for target_dir in "$SCRIPT_DIR"/*/; do
        target=$(basename "$target_dir")
        [[ -n "$TARGET_FILTER" && "$target" != "$TARGET_FILTER" ]] && continue
        [[ ! -d "$target_dir" ]] && continue

        # Charger le config approprié pour cette cible
        load_config_for_target "$target"

        if ! ref_check_available; then
            log "${YELLOW}  [SKIP] $target : compilateur '$REF_COMPILER' non trouvé.${RESET}"
            continue
        fi

        log ""
        log "${BLUE}--- $target ($REF_COMPILER) ---${RESET}"
        load_skip_list "$target_dir"

        for source in "${target_dir}"/*.asm; do
            [[ ! -f "$source" ]] && continue
            base=$(basename "$source" .asm)
            [[ -n "$FILE_FILTER" && "$base" != "$FILE_FILTER" ]] && continue

            if [[ -n "${SKIP_LIST[$base]}" ]]; then
                log "  ${YELLOW}[SKIP]${RESET}  $target/$base (incompatible $REF_COMPILER)"
                continue
            fi

            ref="${target_dir}/${base}.ref.prg"
            origin=$(grep -m1 '\.org' "$source" | grep -oP '\$[0-9A-Fa-f]+' | \
                     python3 -c "import sys; print(int(sys.stdin.read().strip()[1:],16))" 2>/dev/null \
                     || echo "2049")

            log "  Génération : $target/$base"
            if ref_assemble "$source" "$ref" "$origin" "$target"; then
                ((updated++))
                info "→ $ref ($(wc -c < "$ref") octets)"
            else
                log "  ${RED}Erreur${RESET} lors de l'assemblage de $base avec $REF_COMPILER"
                ((errors++))
            fi
        done
    done

    log ""
    log "Mis à jour : $updated fichier(s), $errors erreur(s)"
    exit $errors
fi

# --------------------------------------------------------------------------
#  Mode test : comparer cl-asm avec les binaires de référence
# --------------------------------------------------------------------------

PASS=0
FAIL=0
SKIP=0
FAILED_LIST=()

TMPDIR_REG=$(mktemp -d /tmp/cl-asm-regression-XXXXXX)
trap "rm -rf $TMPDIR_REG" EXIT

# Trouver les cibles à tester
if [[ -n "$TARGET_FILTER" ]]; then
    targets=("$TARGET_FILTER")
else
    targets=()
    for d in "$SCRIPT_DIR"/*/; do
        [[ -d "$d" ]] && targets+=("$(basename "$d")")
    done
fi

for target in "${targets[@]}"; do
    target_dir="$SCRIPT_DIR/$target"
    [[ ! -d "$target_dir" ]] && continue

    sources=("${target_dir}"/*.asm)
    [[ ! -f "${sources[0]}" ]] && continue

    # Charger le config approprié pour cette cible
    load_config_for_target "$target"

    log ""
    log "${BLUE}=== $target ($REF_COMPILER) ===${RESET}"

    if ! ref_check_available; then
        log "${YELLOW}  Avertissement : $REF_COMPILER non trouvé — utilisation des .ref.prg existants.${RESET}"
    fi

    load_skip_list "$target_dir"

    for source in "${sources[@]}"; do
        [[ ! -f "$source" ]] && continue
        base=$(basename "$source" .asm)
        [[ -n "$FILE_FILTER" && "$base" != "$FILE_FILTER" ]] && continue

        ref="${target_dir}/${base}.ref.prg"
        out="$TMPDIR_REG/${base}.prg"

        # Fichier dans la skip-list → ignorer avec message explicite
        if [[ -n "${SKIP_LIST[$base]}" ]]; then
            skip "$base (incompatible $REF_COMPILER — voir .${REF_COMPILER}-skip)"
            ((SKIP++))
            continue
        fi

        # Détecter l'adresse d'origine depuis la directive .org du source
        origin=$(grep -m1 '\.org' "$source" | grep -oP '\$[0-9A-Fa-f]+' | \
                 python3 -c "import sys; print(int(sys.stdin.read().strip()[1:],16))" 2>/dev/null \
                 || echo "2049")

        # Pas de référence → essayer de la générer à la volée
        if [[ ! -f "$ref" ]]; then
            if ref_check_available; then
                ref_assemble "$source" "$ref" "$origin" "$target" 2>/dev/null || true
            fi
        fi

        if [[ ! -f "$ref" ]]; then
            skip "$base (pas de référence — lancer avec --update)"
            ((SKIP++))
            continue
        fi

        # Assembler avec cl-asm
        cl_asm_opts="--origin $origin"
        case "$target" in
            mega65) cl_asm_opts="$cl_asm_opts --target 45gs02" ;;
            x16)    cl_asm_opts="$cl_asm_opts --target x16" ;;
            r65c02) cl_asm_opts="$cl_asm_opts --target r65c02" ;;
            65816)  cl_asm_opts="$cl_asm_opts --target 65816" ;;
            m68k)   cl_asm_opts="$cl_asm_opts --target m68k" ;;
            z80)    cl_asm_opts="$cl_asm_opts --target z80" ;;
        esac

        if ! "$CL_ASM" $cl_asm_opts "$source" -o "$out" 2>/dev/null; then
            fail "$base (erreur d'assemblage cl-asm)"
            info "Relancer avec : $CL_ASM $cl_asm_opts $source -o /tmp/test.prg"
            ((FAIL++))
            FAILED_LIST+=("$target/$base")
            continue
        fi

        # Comparer
        if compare_binaries "$ref" "$out"; then
            ok "$base"
            ((PASS++))
        else
            fail "$base"
            info "Référence : $ref"
            info "Produit   : $out"
            info "Diff      : diff <(xxd $ref) <(xxd $out) | head -20"
            ((FAIL++))
            FAILED_LIST+=("$target/$base")
        fi
    done
done

# --------------------------------------------------------------------------
#  Bilan
# --------------------------------------------------------------------------

log ""
log "-------------------------------"
log "TOTAL : ${GREEN}$PASS OK${RESET}  ${RED}$FAIL KO${RESET}  ${YELLOW}$SKIP [SKIP]${RESET}"

if [[ ${#FAILED_LIST[@]} -gt 0 ]]; then
    log ""
    log "Échecs :"
    for f in "${FAILED_LIST[@]}"; do
        log "  - $f"
    done
fi

[[ $FAIL -eq 0 ]]
