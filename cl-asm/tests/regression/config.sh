#!/bin/bash
# tests/regression/config.sh
#
# Configuration du compilateur de référence pour les tests de régression.
# Modifier REF_COMPILER pour changer de compilateur.
#
# Valeurs supportées :
#   acme  — ACME assembler (https://sourceforge.net/projects/acme-crossass/)
#   ca65  — ca65 assembler du projet cc65 (https://cc65.github.io/)

REF_COMPILER="acme"

# --------------------------------------------------------------------------
#  Conversion syntaxe cl-asm → ACME
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
        -e 's/^\([[:space:]]*\)\(asl\|lsr\|rol\|ror\) A[[:space:]]*$/\1\2/g' \
        "$src" > "$dst"
}

# --------------------------------------------------------------------------
#  Conversion syntaxe cl-asm → ca65
#
#  ca65 est très proche de cl-asm (même inspiration), les conversions
#  sont minimales. Principales différences :
#    - ca65 utilise .proc/.endproc pour les zones locales
#    - ca65 requiert .segment "CODE" au lieu de .org dans certains modes
#    - Pour un .prg simple on utilise .org directement avec --cpu 6502
#    - Les macros sont identiques (.macro/.endmacro, invocation sans préfixe)
#    - Les labels locaux @ sont supportés nativement
# --------------------------------------------------------------------------

clasm_to_ca65() {
    local src="$1"
    local dst="$2"
    # ca65 est tres proche de cl-asm. Differences :
    #   .text "STR"  -> .byte "STR"   (ca65 utilise .byte pour les chaines)
    #   .fill N, V   -> .res N, V     (ca65 utilise .res pour le remplissage)
    #   __label:     -> @label:       (labels locaux)
    sed \
        -e 's/^\([[:space:]]*\)\.text \(.*\)/\1.byte \2/g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\), \(.*\)/\1.res \2, \3/g' \
        -e 's/^\([[:space:]]*\)\.fill \([0-9][0-9]*\)$/\1.res \2/g' \
        -e 's/__\([a-zA-Z_][a-zA-Z0-9_]*\)/@\1/g' \
        "$src" > "$dst"
}

# --------------------------------------------------------------------------
#  Fichier de configuration ld65 pour ca65
#  Produit un .prg C64 (header 2 octets + binaire)
# --------------------------------------------------------------------------

CA65_CFG_TEMPLATE='MEMORY {
    ZP:  start = $02,  size = $fe,  type = rw,  define = yes;
    RAM: start = %ORIGIN%, size = $10000 - %ORIGIN%, type = rw, file = %O;
}
SEGMENTS {
    ZEROPAGE: load = ZP,  type = zp;
    CODE:     load = RAM, type = rw;
    DATA:     load = RAM, type = rw;
    BSS:      load = RAM, type = bss, define = yes;
}'

# Génère le fichier .cfg pour ld65 avec l'origine correcte
make_ca65_cfg() {
    local origin_dec="$1"   # ex: 2049
    local origin_hex        # ex: $0801
    origin_hex=$(printf '$%04X' "$origin_dec")
    echo "$CA65_CFG_TEMPLATE" \
        | sed "s/%ORIGIN%/$origin_hex/g" \
        | sed 's/%O/\%O/g'
}

# --------------------------------------------------------------------------
#  Assemblage avec le compilateur de référence
# --------------------------------------------------------------------------

# ref_assemble SOURCE OUTPUT ORIGIN TARGET
#   SOURCE : fichier source .asm (syntaxe cl-asm)
#   OUTPUT : fichier de sortie .prg
#   ORIGIN : adresse de chargement en décimal (ex: 2049)
#   TARGET : architecture (c64, mega65, x16)

ref_assemble() {
    local source="$1"
    local output="$2"
    local origin="$3"
    local target="$4"
    local result=0
    local tmp_src tmp_cfg tmp_obj

    case "$REF_COMPILER" in

        # ----------------------------------------------------------------
        #  ACME
        # ----------------------------------------------------------------
        acme)
            tmp_src=$(mktemp /tmp/cl-asm-acme-XXXXXX.asm)
            clasm_to_acme "$source" "$tmp_src"

            case "$target" in
                c64)
                    acme --cpu 6510 \
                         --outfile "$output" \
                         --format cbm \
                         "$tmp_src"
                    result=$?
                    ;;
                mega65)
                    acme --cpu m65 \
                         --outfile "$output" \
                         --format cbm \
                         "$tmp_src"
                    result=$?
                    ;;
                x16)
                    acme --cpu 65c02 \
                         --outfile "$output" \
                         --format cbm \
                         "$tmp_src"
                    result=$?
                    ;;
                *)
                    echo "config.sh: cible '$target' inconnue pour acme" >&2
                    result=1
                    ;;
            esac

            rm -f "$tmp_src"
            ;;

        # ----------------------------------------------------------------
        #  ca65 + ld65
        #
        #  Pipeline : source.asm → ca65 → source.o → ld65 → source.prg
        #
        #  ca65 produit un fichier objet .o, ld65 le lie en .prg avec
        #  un fichier de configuration qui définit l'adresse de chargement.
        # ----------------------------------------------------------------
        ca65)
            tmp_src=$(mktemp /tmp/cl-asm-ca65-XXXXXX.s)
            tmp_obj=$(mktemp /tmp/cl-asm-ca65-XXXXXX.o)
            tmp_cfg=$(mktemp /tmp/cl-asm-ca65-XXXXXX.cfg)

            clasm_to_ca65 "$source" "$tmp_src"

            # Choisir le CPU ca65 selon la cible
            local ca65_cpu
            case "$target" in
                c64)    ca65_cpu="6502" ;;
                mega65) ca65_cpu="4510" ;;
                x16)    ca65_cpu="65C02" ;;
                *)
                    echo "config.sh: cible '$target' inconnue pour ca65" >&2
                    rm -f "$tmp_src" "$tmp_obj" "$tmp_cfg"
                    return 1
                    ;;
            esac

            # Assembler avec ca65
            if ! ca65 --cpu "$ca65_cpu" \
                      --target none \
                      -o "$tmp_obj" \
                      "$tmp_src" 2>/dev/null; then
                rm -f "$tmp_src" "$tmp_obj" "$tmp_cfg"
                return 1
            fi

            # Générer le fichier de configuration ld65
            make_ca65_cfg "$origin" > "$tmp_cfg"

            # Lier avec ld65 pour produire le .prg
            # Le header PRG (2 octets adresse) est géré par ld65 via le format bin
            # On ajoute le header manuellement après
            local tmp_bin
            tmp_bin=$(mktemp /tmp/cl-asm-ca65-XXXXXX.bin)

            if ld65 -C "$tmp_cfg" \
                    -o "$tmp_bin" \
                    "$tmp_obj" 2>/dev/null; then
                # Ajouter le header PRG (adresse de chargement en little-endian)
                local lo hi
                lo=$(( origin & 0xFF ))
                hi=$(( (origin >> 8) & 0xFF ))
                printf "\\x$(printf '%02x' $lo)\\x$(printf '%02x' $hi)" > "$output"
                cat "$tmp_bin" >> "$output"
                result=0
            else
                result=1
            fi

            rm -f "$tmp_src" "$tmp_obj" "$tmp_cfg" "$tmp_bin"
            ;;

        *)
            echo "config.sh: compilateur '$REF_COMPILER' inconnu" >&2
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
        ca65) command -v ca65 >/dev/null 2>&1 && command -v ld65 >/dev/null 2>&1 ;;
        *)    return 1 ;;
    esac
}
