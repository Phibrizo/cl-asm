#!/bin/bash
# tests/regression/config-z80.sh
#
# Configuration du compilateur de référence pour le Zilog Z80.
# Cibles gérées : z80
#
# Compilateur de référence : z80asm
#   Installation : pacman -S z80asm  (Arch)
#                  apt install z80asm  (Debian/Ubuntu)
#
# Alternative : pasmo
#   Installation : pacman -S pasmo  (AUR)
#                  apt install pasmo  (Debian/Ubuntu)
#
# Pour changer : modifier REF_COMPILER.
# Valeurs supportées : z80asm, pasmo

REF_COMPILER="z80asm"

# --------------------------------------------------------------------------
#  Conversion syntaxe cl-asm → z80asm
#
#  cl-asm et z80asm utilisent tous deux la syntaxe Intel Z80 standard.
#  Différences minimales :
#    - .org → .org (identique)
#    - .byte → defb
#    - .word → defw
#    - .text → defm
#    - .fill N, V → defs N, V
# --------------------------------------------------------------------------

clasm_to_z80asm() {
    local src="$1"
    local dst="$2"
    sed \
        -e 's/^\([[:space:]]*\)\.org /\1\.org /g' \
        -e 's/^\([[:space:]]*\)\.byte /\1defb /g' \
        -e 's/^\([[:space:]]*\)\.word /\1defw /g' \
        -e 's/^\([[:space:]]*\)\.text /\1defm /g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\), \(.*\)/\1defs \2, \3/g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\)$/\1defs \2/g' \
        "$src" > "$dst"
}

# --------------------------------------------------------------------------
#  Conversion syntaxe cl-asm → pasmo
#
#  pasmo utilise ORG (majuscule), DB, DW, DM, DS.
# --------------------------------------------------------------------------

clasm_to_pasmo() {
    local src="$1"
    local dst="$2"
    sed \
        -e 's/^\([[:space:]]*\)\.org \(.*\)/\1ORG \2/g' \
        -e 's/^\([[:space:]]*\)\.byte /\1DB /g' \
        -e 's/^\([[:space:]]*\)\.word /\1DW /g' \
        -e 's/^\([[:space:]]*\)\.text /\1DM /g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\), \(.*\)/\1DS \2, \3/g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\)$/\1DS \2/g' \
        "$src" > "$dst"
}

# --------------------------------------------------------------------------
#  Assemblage avec le compilateur de référence
#
#  z80asm et pasmo produisent un binaire plat (pas de header .prg).
#  On ajoute manuellement le header 2 octets (adresse de chargement
#  little-endian) pour correspondre au format .prg de cl-asm.
# --------------------------------------------------------------------------

add_prg_header() {
    local origin="$1"    # adresse décimale
    local binary="$2"    # fichier binaire sans header
    local output="$3"    # fichier .prg avec header
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
        z80asm)
            tmp_src=$(mktemp /tmp/cl-asm-z80asm-XXXXXX.asm)
            clasm_to_z80asm "$source" "$tmp_src"
            z80asm -o "$tmp_bin" "$tmp_src"
            result=$?
            rm -f "$tmp_src"
            ;;
        pasmo)
            tmp_src=$(mktemp /tmp/cl-asm-pasmo-XXXXXX.asm)
            clasm_to_pasmo "$source" "$tmp_src"
            pasmo "$tmp_src" "$tmp_bin"
            result=$?
            rm -f "$tmp_src"
            ;;
        *)
            echo "config-z80.sh: compilateur '$REF_COMPILER' inconnu" >&2
            rm -f "$tmp_bin"
            return 1
            ;;
    esac

    if [[ $result -eq 0 && -f "$tmp_bin" ]]; then
        add_prg_header "$origin" "$tmp_bin" "$output"
    fi
    rm -f "$tmp_bin"
    return $result
}

# --------------------------------------------------------------------------
#  Vérification de disponibilité
# --------------------------------------------------------------------------

ref_check_available() {
    case "$REF_COMPILER" in
        z80asm) command -v z80asm >/dev/null 2>&1 ;;
        pasmo)  command -v pasmo  >/dev/null 2>&1 ;;
        *)      return 1 ;;
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
