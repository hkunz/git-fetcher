#!/usr/bin/env bash
set -e

# =============================================
# generate_mxe.sh
# Generates MXE .mk file from a downloaded archive
# =============================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." &>/dev/null && pwd)"
SCRIPT_DIR="$ROOT_DIR/scripts"
TMP_DIR="$ROOT_DIR/tmp"

source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/lib-color.sh"

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
        --owner_repo) OWNER_REPO="$2"; shift 2 ;;
        --archive) ARCHIVE_FILE="$2"; shift 2 ;;
        --pkg) PACKAGE_NAME="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --archive_url) ARCHIVE_URL="$2"; shift 2 ;;
        --checksum) CHECKSUM="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --website) GIT_URL="$2"; shift 2 ;;
        --debug) DEBUG=true; shift ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1"; print_usage; exit 1 ;;
    esac
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
PC_FILE=$(echo "$JSON_OUTPUT" | jq -r '.pc_file')

decho "Build Detection JSON Output: $JSON_OUTPUT"
iecho "Main Build System File: $(bold_bright_cyan "$MAIN_FILE")"

[[ -n "$OPTIONS_FILE" ]] && iecho "Options File: $(bold_bright_cyan "$OPTIONS_FILE")"

mkdir -p "$TMP_DIR"

# =============================================
# Extract main + other files
# =============================================
FOUND_FILES=("$MAIN_FILE")
[[ -n "$OPTIONS_FILE" ]] && FOUND_FILES+=("$OPTIONS_FILE") 
[[ -n "$PC_FILE" ]] && FOUND_FILES+=("$PC_FILE")   # <-- add this
while IFS= read -r f; do
    FOUND_FILES+=("$f")
done <<< "$OTHER_FILES"

for f in "${FOUND_FILES[@]}"; do
    if tar -tf "$ARCHIVE_FILE" | grep -q "^$f\$"; then
        tar -xf "$ARCHIVE_FILE" -C "$TMP_DIR" --overwrite "$f"
    else
        wecho "$f not found in archive"
    fi
done

# =============================================
# Parse build options from a single file
# =============================================
parse_build_options() {
    local full_path="$1"

    # OPTION(...) statements
    while read -r line; do
        name=$(echo "$line" | awk '{print $1}')
        default=$(echo "$line" | awk '{print $NF}')
        BUILD_OPTIONS+=" ${name}=${default}"  # preserve original CMake parsing
    done < <(grep -Po '^\s*(OPTION|option)\s*\(\s*\K[A-Za-z0-9_]+\s+"[^"]*"\s+[A-Za-z0-9_]+' "$full_path")

    # set_aom_*_var(...) statements
    while read -r line; do
        name=$(echo "$line" | awk '{print $1}')
        default=$(echo "$line" | awk '{print $2}')
        BUILD_OPTIONS+=" ${name}=${default}"
    done < <(grep -Po '^\s*set_aom_(config|option|detect)_var\(\s*\K[A-Z0-9_]+\s+[0-9ONF]+' "$full_path")
}

# =============================================
# Parse important files for build options
# =============================================
parse_all_files() {
    BUILD_OPTIONS=""

    if [[ "$BUILD_SYSTEM" == "CMake" ]]; then
        for FILE in "${FOUND_FILES[@]}"; do
            FULL_PATH="$TMP_DIR/$FILE"
            parse_build_options "$FULL_PATH"
        done

    elif [[ "$BUILD_SYSTEM" == "Meson" && -n "$OPTIONS_FILE" ]]; then
        FULL_PATH="$TMP_DIR/$OPTIONS_FILE"
        COLLAPSED=$(awk 'BEGIN { ORS=""; inblock=0 } {gsub(/[[:space:]]+/, " ") } /^option\(/ {inblock=1; printf "%s", $0; next} inblock {printf " %s", $0} /\)/ && inblock {print ""; inblock=0}' "$FULL_PATH")
        decho "Raw Options: ${COLLAPSED:0:100}"
        BUILD_OPTIONS=$(echo "$COLLAPSED" | sed 's/option(/\noption(/g' | sed -En "s/option\('([^']+)',[^)]*value:[[:space:]]*(true|false)[^)]*\)/\1=\2/p" | tr '\n' ' ')
    else
        wecho "Build system '$BUILD_SYSTEM' not handled automatically"
    fi

    decho "Build options: {"
    for opt in $BUILD_OPTIONS; do
        decho --no-prefix "  $opt"
    done
    decho --no-prefix "}"
}

parse_all_files

# =============================================
# Cleanup temporary extraction
# =============================================
# rm -rf "$TMP_DIR"

# =============================================
# Defaults
# =============================================
MXE_ROOT="$ROOT_DIR/contrib/mxe"
OUTPUT_DIR="$MXE_ROOT/generated"
mkdir -p "$OUTPUT_DIR"

TEST_LANG="${TEST_LANG:-cpp}"  # default to cpp if not set

# =============================================
# Generate .mk file
# =============================================
TEMPLATE="$MXE_ROOT/templates/mxe-template.mk"
OUTPUT_FILE="$OUTPUT_DIR/$PACKAGE_NAME.mk"
IGNORE=""

BUILD_OPTIONS_MULTILINE=""
for opt in $BUILD_OPTIONS; do
    BUILD_OPTIONS_MULTILINE+=$'\t\t-D'"$opt"$' \\\n'
done

if [[ "$GIT_URL" == *"github.com"* ]]; then
    DELETE_BLOCK='/# BEGIN_NON_GITHUB/,/# END_NON_GITHUB/d'  # Remove non-GitHub block
else
    DELETE_BLOCK='/# BEGIN_GITHUB/,/# END_GITHUB/d'  # Remove GitHub block
fi

# Remove build system blocks
case "$BUILD_SYSTEM" in
    CMake)
        BUILD_OPTIONS_MULTILINE+="\t\t-DCMAKE_BUILD_TYPE=Release"
        DELETE_BUILD='/# BEGIN_MESON/,/# END_MESON/d; /# BEGIN_OTHER_BUILD_SYSTEM/,/# END_OTHER_BUILD_SYSTEM/d'
        ;;
    Meson)
        BUILD_OPTIONS_MULTILINE+="\t\t--buildtype=release \\"
        DELETE_BUILD='/# BEGIN_CMAKE/,/# END_CMAKE/d; /# BEGIN_OTHER_BUILD_SYSTEM/,/# END_OTHER_BUILD_SYSTEM/d'
        ;;
    *)
        DELETE_BUILD='/# BEGIN_CMAKE/,/# END_CMAKE/d; /# BEGIN_MESON/,/# END_MESON/d'
        ;;
esac

if [[ -n "$PC_FILE" && -s "$TMP_DIR/$PC_FILE" ]]; then
    vecho "PC file exists and is not empty: $PC_FILE"
    DELETE_PC_BLOCK='/^[[:space:]]*# BEGIN_PC_FILE/,/^[[:space:]]*# END_PC_FILE/d'  # Remove PC file generation block
    DELETE_INCLUDE_BLOCK='/^[[:space:]]*# BEGIN_INCLUDE/,/^[[:space:]]*# END_INCLUDE/d'
fi

sed \
${DELETE_BLOCK:+-e "$DELETE_BLOCK"} \
${DELETE_BUILD:+-e "$DELETE_BUILD"} \
${DELETE_PC_BLOCK:+-e "$DELETE_PC_BLOCK"} \
${DELETE_PC_BLOCK:+-e "$DELETE_INCLUDE_BLOCK"} \
-e "s|\${OWNER_REPO}|$OWNER_REPO|g" \
-e "s|\${PACKAGE}|$PACKAGE_NAME|g" \
-e "s|\${WEBSITE}|$GIT_URL|g" \
-e "s|\${VERSION}|$VERSION|g" \
-e "s|\${DESCRIPTION}|$DESCRIPTION|g" \
-e "s|\${ARCHIVE_URL}|$ARCHIVE_URL|g" \
-e "s|\${IGNORE}|$IGNORE|g" \
-e "s|\${CHECKSUM}|$CHECKSUM|g" \
-e "/# BEGIN_GITHUB/d" \
-e "/# END_GITHUB/d" \
-e "/# BEGIN_NON_GITHUB/d" \
-e "/# END_NON_GITHUB/d" \
-e "/# BEGIN_CMAKE/d" \
-e "/# END_CMAKE/d" \
-e "/# BEGIN_MESON/d" \
-e "/# END_MESON/d" \
-e "/# BEGIN_OTHER_BUILD_SYSTEM/d" \
-e "/# END_OTHER_BUILD_SYSTEM/d" \
-e "/# BEGIN_INCLUDE/d" \
-e "/# END_INCLUDE/d" \
-e "/# BEGIN_PC_FILE/d" \
-e "/# END_PC_FILE/d" \
"$TEMPLATE" > "$OUTPUT_FILE"

# inserting a multiline block of build options via temporary file to work around sed's inability to handle multiline replacements
TMP=$(mktemp)
echo -e "$BUILD_OPTIONS_MULTILINE" > "$TMP"
sed -i "/\${BUILD_OPTIONS_MULTILINE}/{
    r $TMP
    d
}" "$OUTPUT_FILE"
rm "$TMP"

iecho "Generated MXE .mk file: $OUTPUT_FILE"

# =============================================
# Generate test file
# =============================================
TEST_TEMPLATE="$MXE_ROOT/templates/test.lang.template"
TEST_FILE="$OUTPUT_DIR/${PACKAGE_NAME}-test.$TEST_LANG"

export TEST_LANG
export PACKAGE_NAME
export COMPILER=$([[ "$TEST_LANG" == "cpp" ]] && echo g++ || echo gcc)
export TARGET=x86_64-w64-mingw32.static
export DEPENDENCIES="-l$PACKAGE_NAME"

if [[ "$TEST_LANG" == "cpp" ]]; then
    export INCLUDES="#include <cstdio>
#include <cstddef>
#include <cstdint>
#include <cstring>"
else
    export INCLUDES="#include <stdio.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>"
fi

envsubst < "$TEST_TEMPLATE" > "$TEST_FILE"
iecho "Generated test file: $TEST_FILE"
