#!/bin/bash
# tests/regression/config-i8080.sh
#
# Configuration du compilateur de référence pour l'Intel 8080.
# Cibles gérées : i8080
#
# Compilateur de référence : zmac
#   Site    : http://48k.ca/zmac.html
#   Arch AUR: yay -S zmac
#
# Pour changer : modifier REF_COMPILER.
# Valeurs supportées : zmac

REF_COMPILER="zmac"

# --------------------------------------------------------------------------
#  Conversion syntaxe cl-asm → zmac
#
#  Différences :
#    - .org    → org      (zmac n'utilise pas le préfixe '.')
#    - .byte   → db
#    - .word   → dw
#    - .fill N → ds N     (zmac ne supporte pas la valeur de remplissage)
#    - .fill N, V → ds N  (valeur ignorée — utiliser .fill sans valeur dans
#                           les tests de régression pour éviter les écarts)
#  Mnémoniques, labels, commentaires (;) : identiques.
# --------------------------------------------------------------------------

clasm_to_zmac() {
    local src="$1"
    local dst="$2"
    sed \
        -e 's/^\([[:space:]]*\)\.org /\1org /g' \
        -e 's/^\([[:space:]]*\)\.byte /\1db /g' \
        -e 's/^\([[:space:]]*\)\.word /\1dw /g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\)$/\1ds \2/g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\),.*$/\1ds \2/g' \
        "$src" > "$dst"
}

# --------------------------------------------------------------------------
#  Assemblage avec le compilateur de référence
#
#  zmac produit un binaire plat (.cim).
#  On ajoute le header 2 octets (adresse little-endian) pour le format .prg.
# --------------------------------------------------------------------------

add_prg_header() {
    local origin="$1"
    local binary="$2"
    local output="$3"
    local lo=$(( origin & 0xFF ))
    local hi=$(( (origin >> 8) & 0xFF ))
    printf "\\x$(printf '%02x' $lo)\\x$(printf '%02x' $hi)" > "$output"
    cat "$binary" >> "$output"
}

# ref_assemble SOURCE OUTPUT ORIGIN TARGET
ref_assemble() {
    local source="$1"
    local output="$2"
    local origin="$3"
    local target="$4"
    local result=0
    local tmp_dir tmp_src base

    case "$REF_COMPILER" in
        zmac)
            # zmac nomme la sortie d'après le fichier source :
            # zmac -8 --od DIR --oo cim FILE.asm → DIR/FILE.cim
            tmp_dir=$(mktemp -d /tmp/cl-asm-zmac-XXXXXX)
            base="ref8080"
            tmp_src="$tmp_dir/${base}.asm"
            clasm_to_zmac "$source" "$tmp_src"
            zmac -8 --od "$tmp_dir" --oo cim "$tmp_src" >/dev/null 2>&1
            result=$?
            local tmp_cim="$tmp_dir/${base}.cim"
            if [[ $result -eq 0 && -s "$tmp_cim" ]]; then
                add_prg_header "$origin" "$tmp_cim" "$output"
            else
                result=1
            fi
            rm -rf "$tmp_dir"
            ;;
        *)
            echo "config-i8080.sh: compilateur '$REF_COMPILER' inconnu" >&2
            return 1
            ;;
    esac
    return $result
}

# --------------------------------------------------------------------------
#  Vérification de disponibilité
# --------------------------------------------------------------------------

ref_check_available() {
    case "$REF_COMPILER" in
        zmac) command -v zmac >/dev/null 2>&1 ;;
        *)    return 1 ;;
    esac
}

# --------------------------------------------------------------------------
#  Cibles gérées
# --------------------------------------------------------------------------

config_handles_target() {
    case "$1" in
        i8080) return 0 ;;
        *)     return 1 ;;
    esac
}
