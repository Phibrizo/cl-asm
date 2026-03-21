#!/bin/bash
# tests/regression/config-r65c02.sh
#
# Configuration du compilateur de référence pour le Rockwell 65C02 (R65C02).
# Cibles gérées : r65c02
#
# Compilateur de référence : acme (--cpu r65c02)
#
# Pour changer de compilateur : modifier REF_COMPILER.
# Valeurs supportées : acme

REF_COMPILER="acme"

# --------------------------------------------------------------------------
#  Conversion syntaxe cl-asm → ACME
#  Identique à config-6502.sh : même famille, mêmes directives.
#  Les mnémoniques Rockwell (RMB/SMB/BBR/BBS) sont natifs des deux syntaxes.
# --------------------------------------------------------------------------

clasm_to_acme() {
    local src="$1"
    local dst="$2"
    sed \
        -e 's/^\([[:space:]]*\)\.org \(.*\)/\1* = \2/g' \
        -e 's/^\([[:space:]]*\)\.byte /\1!byte /g' \
        -e 's/^\([[:space:]]*\)\.word /\1!word /g' \
        -e 's/^\([[:space:]]*\)\.text /\1!text /g' \
        -e 's/^\([[:space:]]*\)\.fill /\1!fill /g' \
        -e 's/^\([[:space:]]*\)\.align /\1!align /g' \
        -e 's/^\([[:space:]]*\)\.macro \(.*\)/\1!macro \2 {/g' \
        -e 's/^\([[:space:]]*\)\.endmacro/\1}/g' \
        -e 's/^\([[:space:]]*\)\.if /\1!if /g' \
        -e 's/^\([[:space:]]*\)\.else/\1!else/g' \
        -e 's/^\([[:space:]]*\)\.endif/\1!endif/g' \
        -e 's/^\([[:space:]]*\)\(asl\|lsr\|rol\|ror\|inc\|dec\) A[[:space:]]*$/\1\2/g' \
        "$src" > "$dst"
}

# --------------------------------------------------------------------------
#  Assemblage avec le compilateur de référence
# --------------------------------------------------------------------------

# ref_assemble SOURCE OUTPUT ORIGIN TARGET
ref_assemble() {
    local source="$1"
    local output="$2"
    local origin="$3"
    local target="$4"
    local result=0
    local tmp_src

    case "$REF_COMPILER" in
        acme)
            tmp_src=$(mktemp /tmp/cl-asm-acme-XXXXXX.asm)
            clasm_to_acme "$source" "$tmp_src"
            acme --cpu r65c02 \
                 --outfile "$output" \
                 --format cbm \
                 "$tmp_src"
            result=$?
            rm -f "$tmp_src"
            ;;
        *)
            echo "config-r65c02.sh: compilateur '$REF_COMPILER' inconnu" >&2
            result=1
            ;;
    esac
    return $result
}

# --------------------------------------------------------------------------
#  Vérification de disponibilité
# --------------------------------------------------------------------------

ref_check_available() {
    case "$REF_COMPILER" in
        acme) command -v acme >/dev/null 2>&1 ;;
        *)    return 1 ;;
    esac
}

# --------------------------------------------------------------------------
#  Cibles gérées
# --------------------------------------------------------------------------

config_handles_target() {
    case "$1" in
        r65c02) return 0 ;;
        *)      return 1 ;;
    esac
}
