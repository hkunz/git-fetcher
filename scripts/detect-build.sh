#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

ARCHIVE=""

# ------------------------------
# Parse flags
# ------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) VERBOSE=true ;;
        *) ARCHIVE="$1" ;;
    esac
    shift
done

if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
    echo "Usage: $0 [--verbose] <source-archive>" >&2
    exit 1
fi

# ------------------------------
# Get file list from archive (no extraction)
# ------------------------------
case "$ARCHIVE" in
    *.tar.gz|*.tgz) CMD=(tar -tzf "$ARCHIVE") ;;
    *.tar.xz)       CMD=(tar -tJf "$ARCHIVE") ;;
    *.tar.bz2)      CMD=(tar -tjf "$ARCHIVE") ;;
    *.zip)          CMD=(unzip -Z1 "$ARCHIVE") ;;
    *) echo "Unknown archive format" >&2; exit 1 ;;
esac

# ------------------------------
# Detect build system and collect paths
# ------------------------------
BUILD_SYSTEM="Unknown"
FOUND_PATHS=()
OPTIONS_FILE=""
PC_FILE=""
MAIN_CANDIDATE=""
MIN_DEPTH=999   # Track shallowest depth

while IFS= read -r file; do
    case "$file" in
       */meson.build|meson.build)
            BUILD_SYSTEM="Meson"
            FOUND_PATHS+=("$file")
            depth=$(awk -F/ '{print NF}' <<< "$file")
            [[ -z "$MAIN_CANDIDATE" || $depth -lt $MIN_DEPTH ]] && MAIN_CANDIDATE="$file" MIN_DEPTH="$depth"
            ;;
        */meson_options.txt|meson_options.txt)
            OPTIONS_FILE="$file"
            FOUND_PATHS+=("$file")
            ;;
        */CMakeLists.txt|CMakeLists.txt)
            BUILD_SYSTEM="CMake"
            FOUND_PATHS+=("$file")
            depth=$(awk -F/ '{print NF}' <<< "$file")
            [[ -z "$MAIN_CANDIDATE" || $depth -lt $MIN_DEPTH ]] && MAIN_CANDIDATE="$file" MIN_DEPTH="$depth"
            ;;
        *.cmake)
            FOUND_PATHS+=("$file")
            ;;
        */configure|configure)
            [[ "$BUILD_SYSTEM" == "Unknown" ]] && BUILD_SYSTEM="Autotools"
            ;;
        */Makefile|Makefile)
            [[ "$BUILD_SYSTEM" == "Unknown" ]] && BUILD_SYSTEM="Makefile"
            ;;
        */pyproject.toml|pyproject.toml)
            [[ "$BUILD_SYSTEM" == "Unknown" ]] && BUILD_SYSTEM="Python"
            ;;
        */Cargo.toml|Cargo.toml)
            [[ "$BUILD_SYSTEM" == "Unknown" ]] && BUILD_SYSTEM="Rust"
            ;;
        */go.mod|go.mod)
            [[ "$BUILD_SYSTEM" == "Unknown" ]] && BUILD_SYSTEM="Go"
            ;;
        *.pc|*.pc.in)
            [[ -z "$PC_FILE" ]] && PC_FILE="$file"
            ;;
    esac
done < <("${CMD[@]}")

# ------------------------------
# MAIN_FILE is shallowest path
# ------------------------------
MAIN_FILE="$MAIN_CANDIDATE"

# ------------------------------
# Sort other files by depth (excluding MAIN_FILE)
# ------------------------------
OTHER_FILES=()
if [[ ${#FOUND_PATHS[@]} -gt 0 ]]; then
    mapfile -t sorted < <(
        printf "%s\n" "${FOUND_PATHS[@]}" |
        grep -vF "$MAIN_FILE" |
        awk -F/ '{print NF, $0}' |
        sort -n |
        cut -d' ' -f2-
    )
    OTHER_FILES=("${sorted[@]}")
fi

# ------------------------------
# Output as JSON
# ------------------------------
jq -n \
    --arg build_system "$BUILD_SYSTEM" \
    --arg main_file "$MAIN_FILE" \
    --arg options_file "$OPTIONS_FILE" \
    --arg pc_file "$PC_FILE" \
    --argjson other_files "$(printf '%s\n' "${OTHER_FILES[@]}" | jq -R -s -c 'split("\n")[:-1]')" \
    '{build_system: $build_system, main_file: $main_file, options_file: $options_file, pc_file: $pc_file, other_files: $other_files}'
