#!/bin/bash
# tests/regression/config-i8086.sh
#
# Configuration du compilateur de référence pour l'Intel 8086.
# Cibles gérées : i8086
#
# Compilateur de référence : nasm
#   Site    : https://nasm.us/
#   Arch    : pacman -S nasm
#   Debian  : apt install nasm
#
# Différences de comportement NASM vs cl-asm (cas EXCLUS des tests) :
#   - Reg-reg ALU/MOV : NASM choisit le bit de direction opposé
#     (p.ex. ADD AX, BX → NASM: 01 D8, cl-asm: 03 C3 — équivalents)
#   - Adresse directe [imm16] vers/depuis AX/AL : NASM utilise A0-A3,
#     cl-asm utilise la forme ModRM 8B/89
#   - Déplacements mémoire : NASM utilise mod=01 (8-bit) quand c'est
#     suffisant, cl-asm utilise toujours mod=10 (16-bit) pour la
#     stabilité de taille en passe 1
#   - [BP] seul : NASM mod=01 disp8=0 (3 oct), cl-asm mod=10 disp16=0 (4 oct)
#   - Décalage par imm > 1 : NASM utilise C1 (80286), cl-asm répète D1 (8086)
# Ces cas sont volontairement absents des fichiers de régression.
#
# NASM est invoqué avec -O0 pour désactiver l'optimisation des immédiats
# (sans -O0, NASM utilise 6A pour PUSH petite valeur, 83 pour ALU+petite valeur,
# alors que cl-asm utilise systématiquement les formes 68/81 pleine longueur).

REF_COMPILER="nasm"

# --------------------------------------------------------------------------
#  Conversion syntaxe cl-asm → NASM
# --------------------------------------------------------------------------

clasm_to_nasm() {
    local src="$1"
    local dst="$2"
    # BITS 16 en en-tête, puis conversion des directives et littéraux
    echo 'BITS 16' > "$dst"
    sed \
        -e 's/\$\([0-9A-Fa-f][0-9A-Fa-f]*\)/0x\1/g' \
        -e 's/^\([[:space:]]*\)\.org[[:space:]]/\1ORG /g' \
        -e 's/^\([[:space:]]*\)\.byte[[:space:]]/\1db /g' \
        -e 's/^\([[:space:]]*\)\.word[[:space:]]/\1dw /g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\), \(.*\)/\1times \2 db \3/g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\)$/\1times \2 db 0/g' \
        -e 's/BYTE PTR/byte/g' \
        -e 's/WORD PTR/word/g' \
        "$src" >> "$dst"
}

# --------------------------------------------------------------------------
#  Assemblage avec le compilateur de référence
#
#  NASM produit un binaire plat (-f bin).
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
        nasm)
            tmp_dir=$(mktemp -d /tmp/cl-asm-nasm-XXXXXX)
            base="ref8086"
            tmp_src="$tmp_dir/${base}.asm"
            clasm_to_nasm "$source" "$tmp_src"
            # -O0 : désactive l'optimisation des immédiats (force formes pleine longueur)
            nasm -O0 -f bin -o "$tmp_dir/${base}.bin" "$tmp_src" >/dev/null 2>&1
            result=$?
            local tmp_bin="$tmp_dir/${base}.bin"
            if [[ $result -eq 0 && -s "$tmp_bin" ]]; then
                add_prg_header "$origin" "$tmp_bin" "$output"
            else
                result=1
            fi
            rm -rf "$tmp_dir"
            ;;
        *)
            echo "config-i8086.sh: compilateur '$REF_COMPILER' inconnu" >&2
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
        nasm) command -v nasm >/dev/null 2>&1 ;;
        *)    return 1 ;;
    esac
}

# --------------------------------------------------------------------------
#  Cibles gérées
# --------------------------------------------------------------------------

config_handles_target() {
    case "$1" in
        i8086) return 0 ;;
        *)     return 1 ;;
    esac
}
