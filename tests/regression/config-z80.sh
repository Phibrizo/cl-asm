#!/bin/bash
# tests/regression/config-z80.sh
#
# Configuration du compilateur de référence pour le Zilog Z80.
# Cibles gérées : z80
#
# Compilateur de référence : sjasmplus
#   Sources : https://github.com/z00m128/sjasmplus
#
# Alternatives (non implémentées) : z80asm, pasmo
#
# Pour changer : modifier REF_COMPILER.
# Valeurs supportées : sjasmplus

REF_COMPILER="sjasmplus"

# --------------------------------------------------------------------------
#  Conversion syntaxe cl-asm → sjasmplus
#
#  Différences :
#    - .org → ORG
#    - .byte → DB
#    - .word → DW
#    - .text → DM
#    - .fill N, V → DEFS N, V
#    - .fill N → DEFS N
# --------------------------------------------------------------------------

clasm_to_sjasmplus() {
    local src="$1"
    local dst="$2"
    sed \
        -e 's/^\([[:space:]]*\)\.org \(.*\)/\1ORG \2/g' \
        -e 's/^\([[:space:]]*\)\.byte /\1DB /g' \
        -e 's/^\([[:space:]]*\)\.word /\1DW /g' \
        -e 's/^\([[:space:]]*\)\.text /\1DM /g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\), \(.*\)/\1DEFS \2, \3/g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\)$/\1DEFS \2/g' \
        "$src" > "$dst"
}

# --------------------------------------------------------------------------
#  Assemblage avec le compilateur de référence
#
#  sjasmplus produit un binaire plat (--raw).
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
    local tmp_src tmp_bin

    tmp_bin=$(mktemp /tmp/cl-asm-z80-XXXXXX.bin)

    case "$REF_COMPILER" in
        sjasmplus)
            tmp_src=$(mktemp /tmp/cl-asm-sjasmplus-XXXXXX.asm)
            clasm_to_sjasmplus "$source" "$tmp_src"
            sjasmplus --raw="$tmp_bin" "$tmp_src" >/dev/null 2>&1
            result=$?
            rm -f "$tmp_src"
            ;;
        *)
            echo "config-z80.sh: compilateur '$REF_COMPILER' inconnu" >&2
            rm -f "$tmp_bin"
            return 1
            ;;
    esac

    if [[ $result -eq 0 && -s "$tmp_bin" ]]; then
        add_prg_header "$origin" "$tmp_bin" "$output"
    else
        result=1
    fi
    rm -f "$tmp_bin"
    return $result
}

# --------------------------------------------------------------------------
#  Vérification de disponibilité
# --------------------------------------------------------------------------

ref_check_available() {
    case "$REF_COMPILER" in
        sjasmplus) command -v sjasmplus >/dev/null 2>&1 ;;
        *)         return 1 ;;
    esac
}

# --------------------------------------------------------------------------
#  Cibles gérées
# --------------------------------------------------------------------------

config_handles_target() {
    case "$1" in
        z80) return 0 ;;
        *)   return 1 ;;
    esac
}
