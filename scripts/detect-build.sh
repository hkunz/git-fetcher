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
    *.tar.gz|*.tgz) FILE_LIST=$(tar -tzf "$ARCHIVE") ;;
    *.tar.xz)       FILE_LIST=$(tar -tJf "$ARCHIVE") ;;
    *.tar.bz2)      FILE_LIST=$(tar -tjf "$ARCHIVE") ;;
    *.zip)          FILE_LIST=$(unzip -Z1 "$ARCHIVE") ;;
    *) echo "Unknown archive format" >&2; exit 1 ;;
esac

# ------------------------------
# Detect build system and collect paths
# ------------------------------
BUILD_SYSTEM="Unknown"
FOUND_PATHS=""

if FOUND_PATHS=$(grep 'meson\.build$' <<< "$FILE_LIST"); then
    BUILD_SYSTEM="Meson"
    MESON_HELPERS=$(grep 'meson_options\.txt$' <<< "$FILE_LIST" || true)
    FOUND_PATHS=$(printf "%s\n%s" "$FOUND_PATHS" "$MESON_HELPERS" | sed '/^$/d')

elif FOUND_PATHS=$(grep 'CMakeLists\.txt$' <<< "$FILE_LIST"); then
    BUILD_SYSTEM="CMake"
    CMAKE_HELPERS=$(grep '\.cmake$' <<< "$FILE_LIST" || true)
    FOUND_PATHS=$(printf "%s\n%s" "$FOUND_PATHS" "$CMAKE_HELPERS" | sed '/^$/d')

elif FOUND_PATHS=$(grep 'configure$' <<< "$FILE_LIST"); then
    BUILD_SYSTEM="Autotools"

elif FOUND_PATHS=$(grep 'Makefile$' <<< "$FILE_LIST"); then
    BUILD_SYSTEM="Makefile"

elif FOUND_PATHS=$(grep 'pyproject\.toml$' <<< "$FILE_LIST"); then
    BUILD_SYSTEM="Python"

elif FOUND_PATHS=$(grep 'Cargo\.toml$' <<< "$FILE_LIST"); then
    BUILD_SYSTEM="Rust"

elif FOUND_PATHS=$(grep 'go\.mod$' <<< "$FILE_LIST"); then
    BUILD_SYSTEM="Go"
fi

# ------------------------------
# Determine main file (shallowest path)
# ------------------------------
MAIN_FILE=""
OTHER_FILES=""

if [[ -n "$FOUND_PATHS" ]]; then
    # Sort by number of '/' (depth) and pick first as main
    MAIN_FILE=$(echo "$FOUND_PATHS" | awk -F/ '{print NF, $0}' | sort -n | cut -d' ' -f2- | head -n1)
    OTHER_FILES=$(echo "$FOUND_PATHS" | grep -vF "$MAIN_FILE" || true)
fi

# ------------------------------
# Output as JSON
# ------------------------------
jq -n \
    --arg build_system "$BUILD_SYSTEM" \
    --arg main_file "$MAIN_FILE" \
    --argjson other_files "$(printf '%s\n' "$OTHER_FILES" | jq -R -s -c 'split("\n")[:-1]')" \
    '{build_system: $build_system, main_file: $main_file, other_files: $other_files}'
