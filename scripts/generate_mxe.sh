#!/usr/bin/env bash
set -e

# =============================================
# generate_mxe.sh
# Generates MXE .mk file from a downloaded archive
# =============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." &>/dev/null && pwd)"
TMP_DIR="$ROOT_DIR/tmp"

# =============================================
# Defaults / Options
# =============================================
ARCHIVE_FILE=""
PACKAGE_NAME=""
VERSION=""
ARCHIVE_URL=""
CHECKSUM=""
DESCRIPTION=""
GIT_URL=""
DEBUG=false

# =============================================
# Usage
# =============================================
print_usage() {
    echo "Usage: $0 --owner_repo <owner/repo> --archive <file> --pkg <name> --version <ver> --archive_url <url> --checksum <sha256> --description <desc> --website <url> [--debug]"
}

# =============================================
# Parse arguments
# =============================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --owner_repo) OWNER_REPO="$2"; shift ;;
        --archive) ARCHIVE_FILE="$2"; shift ;;
        --pkg) PACKAGE_NAME="$2"; shift ;;
        --version) VERSION="$2"; shift ;;
        --archive_url) ARCHIVE_URL="$2"; shift ;;
        --checksum) CHECKSUM="$2"; shift ;;
        --description) DESCRIPTION="$2"; shift ;;
        --website) GIT_URL="$2"; shift ;;
        --debug) DEBUG=true ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1"; print_usage; exit 1 ;;
    esac
    shift
done

# Check required variables
for var in ARCHIVE_FILE PACKAGE_NAME VERSION ARCHIVE_URL CHECKSUM DESCRIPTION GIT_URL; do
    if [[ -z "${!var}" ]]; then
        echo "Missing required argument: $var"
        print_usage
        exit 1
    fi
done

# Load helper functions if they exist
[[ -f "$SCRIPT_DIR/lib.sh" ]] && source "$SCRIPT_DIR/lib.sh"

# =============================================
# Detect build system and files
# =============================================
JSON_OUTPUT=$(bash "$SCRIPT_DIR/detect-build.sh" "$ARCHIVE_FILE")
BUILD_SYSTEM=$(echo "$JSON_OUTPUT" | jq -r '.build_system')
MAIN_FILE=$(echo "$JSON_OUTPUT" | jq -r '.main_file')
OPTIONS_FILE=$(echo "$JSON_OUTPUT" | jq -r '.options_file')
OTHER_FILES=$(echo "$JSON_OUTPUT" | jq -r '.other_files[]?')

decho "Build Detection JSON Output: $JSON_OUTPUT"
iecho "Main Build System File: $(bold_bright_cyan "$MAIN_FILE")"
[[ -n "$OPTIONS_FILE" ]] && decho "Options File: $(bold_bright_cyan "$OPTIONS_FILE")"

mkdir -p "$TMP_DIR"

# =============================================
# Extract main + other files
# =============================================
FOUND_FILES=("$MAIN_FILE")
while IFS= read -r f; do
    FOUND_FILES+=("$f")
done <<< "$OTHER_FILES"

for f in "${FOUND_FILES[@]}"; do
    if tar -tf "$ARCHIVE_FILE" | grep -q "^$f\$"; then
        tar -xf "$ARCHIVE_FILE" -C "$TMP_DIR" --overwrite "$f"
    else
        vecho "Warning: $f not found in archive"
    fi
done

# =============================================
# Parse build options
# =============================================
BUILD_OPTIONS=""
if [[ "$BUILD_SYSTEM" == "CMake" ]]; then
    for FILE in "${FOUND_FILES[@]}"; do
        FULL_PATH="$TMP_DIR/$FILE"
        while read -r line; do
            name=$(echo "$line" | awk '{print $1}')
            default=$(echo "$line" | awk '{print $NF}')
            BUILD_OPTIONS+=" ${name}=${default}"  # preserve original CMake parsing
        done < <(grep -Po '^\s*(OPTION|option)\s*\(\s*\K[A-Za-z0-9_]+\s+"[^"]*"\s+[A-Za-z0-9_]+' "$FULL_PATH")
    done
elif [[ "$BUILD_SYSTEM" == "Meson" && -n "$OPTIONS_FILE" ]]; then
    FULL_PATH="$TMP_DIR/$OPTIONS_FILE"
    COLLAPSED=$(awk 'BEGIN { ORS=""; inblock=0 } {gsub(/[[:space:]]+/, " ") } /^option\(/ {inblock=1; printf "%s", $0; next} inblock {printf " %s", $0} /\)/ && inblock {print ""; inblock=0}' "$FULL_PATH")
    decho "Raw Options: ${COLLAPSED:0:100}"
    BUILD_OPTIONS=$(echo "$COLLAPSED" | sed 's/option(/\noption(/g' | sed -En "s/option\('([^']+)',[^)]*value:[[:space:]]*(true|false)[^)]*\)/\1=\2/p" | tr '\n' ' ')
else
    vecho "Warning: Build system '$BUILD_SYSTEM' not handled automatically"
fi

decho "Build options: {"
for opt in $BUILD_OPTIONS; do
    decho --no-prefix "  $opt"
done
decho --no-prefix "}"

# =============================================
# Cleanup temporary extraction
# =============================================
rm -rf "$TMP_DIR"

# =============================================
# Call MXE .mk generator
# =============================================
bash "$ROOT_DIR/mxe/scripts/generate_mxe_mk.sh" \
    --owner-repo "$OWNER_REPO" \
    --pkg "$PACKAGE_NAME" \
    --version "$VERSION" \
    --archive_url "$ARCHIVE_URL" \
    --archive "$ARCHIVE_FILE" \
    --checksum "$CHECKSUM" \
    --description "$DESCRIPTION" \
    --website "$GIT_URL" \
    --build-system "$BUILD_SYSTEM" \
    --build-options "$BUILD_OPTIONS" \
    --test-lang "cpp"

iecho "MXE .mk generation complete."
