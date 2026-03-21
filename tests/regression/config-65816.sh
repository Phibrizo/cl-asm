#!/bin/bash
# tests/regression/config-65816.sh
#
# Configuration du compilateur de référence pour le WDC 65816.
# Cibles gérées : 65816
#
# Compilateur de référence : ca65 (cc65 suite)
#   Installation : pacman -S cc65  (Arch AUR)
#                  apt install cc65  (Debian/Ubuntu)
#
# Pour changer : modifier REF_COMPILER.
# Valeurs supportées : ca65

REF_COMPILER="ca65"

# --------------------------------------------------------------------------
#  Conversion syntaxe cl-asm → ca65 (65816)
#
#  Différences principales :
#    - .as → .a8    (A sur 8 bits)
#    - .al → .a16   (A sur 16 bits)
#    - .xs → .i8    (X/Y sur 8 bits)
#    - .xl → .i16   (X/Y sur 16 bits)
#    - .text → .byte  (ca65 utilise .byte pour les chaînes)
#    - .fill N, V → .res N, V
# --------------------------------------------------------------------------

clasm_to_ca65_816() {
    local src="$1"
    local dst="$2"
    sed \
        -e 's/^\([[:space:]]*\)\.as[[:space:]]*$/\1.a8/g' \
        -e 's/^\([[:space:]]*\)\.al[[:space:]]*$/\1.a16/g' \
        -e 's/^\([[:space:]]*\)\.xs[[:space:]]*$/\1.i8/g' \
        -e 's/^\([[:space:]]*\)\.xl[[:space:]]*$/\1.i16/g' \
        -e 's/^\([[:space:]]*\)\.text \(.*\)/\1.byte \2/g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\), \(.*\)/\1.res \2, \3/g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\)$/\1.res \2/g' \
        -e 's/^\([[:space:]]*\)pea #/\1pea /g' \
        -e 's/^\([[:space:]]*\)PEA #/\1PEA /g' \
        -e 's/^\([[:space:]]*\)[Mm][Vv][Nn] \$\([0-9A-Fa-f]*\), \$\([0-9A-Fa-f]*\)/\1mvn #$\3, #$\2/g' \
        -e 's/^\([[:space:]]*\)[Mm][Vv][Pp] \$\([0-9A-Fa-f]*\), \$\([0-9A-Fa-f]*\)/\1mvp #$\3, #$\2/g' \
        "$src" > "$dst"
}

# --------------------------------------------------------------------------
#  Fichier de configuration ld65 pour 65816
#  Produit un fichier binaire avec header 2 octets (format .prg)
# --------------------------------------------------------------------------

CA65_816_CFG_TEMPLATE='MEMORY {
    ROM: start = %ORIGIN%, size = $10000 - %ORIGIN%, type = ro, file = %O;
}
SEGMENTS {
    CODE: load = ROM, type = ro;
    RODATA: load = ROM, type = ro;
    DATA: load = ROM, type = ro;
}'

make_ca65_816_cfg() {
    local origin_dec="$1"
    local origin_hex
    origin_hex=$(printf '$%04X' "$origin_dec")
    echo "$CA65_816_CFG_TEMPLATE" \
        | sed "s/%ORIGIN%/$origin_hex/g" \
        | sed 's/%O/\%O/g'
}

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
    local tmp_src tmp_cfg tmp_obj tmp_bin

    case "$REF_COMPILER" in
        ca65)
            tmp_src=$(mktemp /tmp/cl-asm-ca65816-XXXXXX.asm)
            tmp_cfg=$(mktemp /tmp/cl-asm-ca65816-XXXXXX.cfg)
            tmp_obj=$(mktemp /tmp/cl-asm-ca65816-XXXXXX.o)
            tmp_bin=$(mktemp /tmp/cl-asm-ca65816-XXXXXX.bin)

            clasm_to_ca65_816 "$source" "$tmp_src"
            make_ca65_816_cfg "$origin" > "$tmp_cfg"

            ca65 --cpu 65816 -o "$tmp_obj" "$tmp_src" 2>/dev/null
            result=$?
            if [[ $result -eq 0 ]]; then
                ld65 -C "$tmp_cfg" -o "$tmp_bin" "$tmp_obj" 2>/dev/null
                result=$?
            fi
            if [[ $result -eq 0 && -f "$tmp_bin" ]]; then
                add_prg_header "$origin" "$tmp_bin" "$output"
            fi
            rm -f "$tmp_src" "$tmp_cfg" "$tmp_obj" "$tmp_bin"
            ;;
        *)
            echo "config-65816.sh: compilateur '$REF_COMPILER' inconnu" >&2
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
        ca65) command -v ca65 >/dev/null 2>&1 && command -v ld65 >/dev/null 2>&1 ;;
        *)    return 1 ;;
    esac
}

# --------------------------------------------------------------------------
#  Cibles gérées
# --------------------------------------------------------------------------

config_handles_target() {
    case "$1" in
        65816) return 0 ;;
        *)     return 1 ;;
    esac
}
