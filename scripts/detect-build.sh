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
    [[ "$file" == */third_party/* ]] && continue
    case "$file" in
        # Meson
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
        # CMake
        */CMakeLists.txt|CMakeLists.txt)
            BUILD_SYSTEM="CMake"
            FOUND_PATHS+=("$file")
            depth=$(awk -F/ '{print NF}' <<< "$file")
            [[ -z "$MAIN_CANDIDATE" || $depth -lt $MIN_DEPTH ]] && MAIN_CANDIDATE="$file" MIN_DEPTH="$depth"
            ;;
        *.cmake)
            FOUND_PATHS+=("$file")
            ;;
        # Autotools
        */configure|configure)
            [[ "$BUILD_SYSTEM" == "Unknown" ]] && BUILD_SYSTEM="Autotools"
            ;;
        # Makefile
        */Makefile|Makefile)
            [[ "$BUILD_SYSTEM" == "Unknown" ]] && BUILD_SYSTEM="Makefile"
            ;;
        # Python
        */pyproject.toml|pyproject.toml)
            [[ "$BUILD_SYSTEM" == "Unknown" ]] && BUILD_SYSTEM="Python"
            ;;
        # Rust
        */Cargo.toml|Cargo.toml)
            [[ "$BUILD_SYSTEM" == "Unknown" ]] && BUILD_SYSTEM="Rust"
            ;;
        # Go
        */go.mod|go.mod)
            [[ "$BUILD_SYSTEM" == "Unknown" ]] && BUILD_SYSTEM="Go"
            ;;
        # pkg-config files
        *.pc|*.pc.in|*/*.pc|*/*.pc.in|*/*/*.pc|*/*/*.pc.in)
            [[ -z "$PC_FILE" ]] && PC_FILE="$file"
            ;;
        # Bazel detection
        WORKSPACE|*/WORKSPACE)
            [[ "$BUILD_SYSTEM" == "Unknown" ]] && BUILD_SYSTEM="Bazel"
            FOUND_PATHS+=("$file")
            [[ -z "$MAIN_CANDIDATE" ]] && MAIN_CANDIDATE="$file" MIN_DEPTH=$(awk -F/ '{print NF}' <<< "$file")
            ;;
        BUILD|BUILD.bazel|*/BUILD|*/BUILD.bazel)
            [[ "$BUILD_SYSTEM" == "Unknown" ]] && BUILD_SYSTEM="Bazel"
            FOUND_PATHS+=("$file")
            depth=$(awk -F/ '{print NF}' <<< "$file")
            [[ -z "$MAIN_CANDIDATE" || $depth -lt $MIN_DEPTH ]] && MAIN_CANDIDATE="$file" MIN_DEPTH="$depth"
            ;;
    esac
done < <("${CMD[@]}")

# ------------------------------
# MAIN_FILE is shallowest path
# ------------------------------
MAIN_FILE="$MAIN_CANDIDATE"

read_file_from_archive() {
    local archive="$1"
    local file="$2"

    case "$archive" in
        *.tar.gz|*.tgz)
            tar -xOzf "$archive" "$file" 2>/dev/null ;;
        *.tar.xz)
            tar -xOJf "$archive" "$file" 2>/dev/null ;;
        *.tar.bz2)
            tar -xOjf "$archive" "$file" 2>/dev/null ;;
        *.zip)
            unzip -p "$archive" "$file" 2>/dev/null ;;
        *)
            return 1 ;;
    esac
}

# ------------------------------
# Parse out other info
# ------------------------------
NOTE=""
LANGUAGE=""
langs=

collapse_file_content() {
    local file="$1"
    awk 'BEGIN {RS=""; ORS="\n"} {gsub(/\r/,""); gsub(/\n[ \t]*/," "); print}' "$file"
}

extract_project_langs() {
    local archive="$1"
    local file="$2"
    local cleanup="$3"  # optional: extra tr transformations
    local line
    line=$(read_file_from_archive "$archive" "$file" \
        | collapse_file_content \
        | grep -i -m1 'project[[:space:]]*(' || true)
    local langs
    langs=$(echo "$line" | sed -E "s/.*project[[:space:]]*\((.*)\).*/\1/")
    if [ -n "$cleanup" ]; then
        langs=$(echo "$langs" | eval "$cleanup")
    fi
    echo "$langs"
}

case "$BUILD_SYSTEM" in
    Bazel)
        NOTE="Note: Bazel projects are not supported by MXE because they attempt to access the network, which is not allowed. You will need to compile the project manually."
        ;;
    CMake)
        langs=$(extract_project_langs "$ARCHIVE" "$MAIN_FILE" "tr '[:lower:]' '[:upper:]'")
        ;;
    Meson)
        langs=$(extract_project_langs "$ARCHIVE" "$MAIN_FILE" "tr -d \"[]'\\\"\" | tr ',' ' '")
        ;;
    *)
        NOTE=""
        ;;
esac

if echo "$langs" | grep -qwE "(cpp|cxx|CXX)"; then
    LANGUAGE="C++"
elif echo "$langs" | grep -qwE "(^| )c( |$)|(^| )C( |$)"; then
    LANGUAGE="C"
elif [[ -n "$langs" ]]; then
    # fallback for projects like vvdec with no explicit LANGUAGES
    LANGUAGE="C/C++"
else
    LANGUAGE="Unknown"
fi

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
tmpfile=$(mktemp)

printf '%s\n' "${OTHER_FILES[@]}" | jq -R . | jq -s . > "$tmpfile"

jq -n \
  --slurpfile other_files "$tmpfile" \
  --arg build_system "$BUILD_SYSTEM" \
  --arg main_file "$MAIN_FILE" \
  --arg options_file "$OPTIONS_FILE" \
  --arg pc_file "$PC_FILE" \
  --arg language "$LANGUAGE" \
  --arg note "$NOTE" \
  '{
    build_system: $build_system,
    main_file: $main_file,
    options_file: $options_file,
    pc_file: $pc_file,
    language: $language,
    other_files: $other_files[0],
    note: $note
  }'

rm -f "$tmpfile"
