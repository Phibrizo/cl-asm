#!/bin/bash
# tests/regression/config-m68k.sh
#
# Configuration du compilateur de référence pour le Motorola 68000.
# Cibles gérées : m68k
#
# Compilateur de référence : vasm (vasmm68k_mot)
#   Installation : https://sun.hasenbraten.de/vasm/
#   Arch AUR : paru -S vasm
#
# Alternative : m68k-linux-gnu-as (GNU binutils cross)
#   Installation : pacman -S m68k-linux-gnu-binutils
#   Note : syntaxe AT&T, conversion complexe — non implémentée ici.
#
# Pour changer : modifier REF_COMPILER.
# Valeurs supportées : vasm

REF_COMPILER="vasm"

# --------------------------------------------------------------------------
#  Conversion syntaxe cl-asm → vasm (Motorola)
#
#  cl-asm et vasm partagent la syntaxe Motorola 68000.
#  Différences :
#    - .org → ORG
#    - .byte → DC.B
#    - .word → DC.W
#    - .long → DC.L
#    - .text → DC.B  (chaînes)
#    - .fill N, V → DS.B N  (vasm ignore la valeur de remplissage)
#    - Les commentaires ; sont communs aux deux
# --------------------------------------------------------------------------

clasm_to_vasm() {
    local src="$1"
    local dst="$2"
    sed \
        -e 's/^\([[:space:]]*\)\.org \(.*\)/\1ORG \2/g' \
        -e 's/^\([[:space:]]*\)\.byte /\1DC.B /g' \
        -e 's/^\([[:space:]]*\)\.word /\1DC.W /g' \
        -e 's/^\([[:space:]]*\)\.long /\1DC.L /g' \
        -e 's/^\([[:space:]]*\)\.text /\1DC.B /g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\).*$/\1DS.B \2/g' \
        "$src" > "$dst"
}

# --------------------------------------------------------------------------
#  Assemblage avec le compilateur de référence
#
#  vasm produit un binaire plat. On ajoute le header 2 octets
#  (adresse de chargement little-endian) pour le format .prg.
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

    case "$REF_COMPILER" in
        vasm)
            tmp_src=$(mktemp /tmp/cl-asm-vasm-XXXXXX.asm)
            tmp_bin=$(mktemp /tmp/cl-asm-vasm-XXXXXX.bin)
            clasm_to_vasm "$source" "$tmp_src"
            vasmm68k_mot -Fbin -o "$tmp_bin" "$tmp_src" 2>/dev/null
            result=$?
            if [[ $result -eq 0 && -f "$tmp_bin" ]]; then
                add_prg_header "$origin" "$tmp_bin" "$output"
            fi
            rm -f "$tmp_src" "$tmp_bin"
            ;;
        *)
            echo "config-m68k.sh: compilateur '$REF_COMPILER' inconnu" >&2
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
        vasm) command -v vasmm68k_mot >/dev/null 2>&1 ;;
        *)    return 1 ;;
    esac
}

# --------------------------------------------------------------------------
#  Cibles gérées
# --------------------------------------------------------------------------

config_handles_target() {
    case "$1" in
        m68k) return 0 ;;
        *)    return 1 ;;
    esac
}
