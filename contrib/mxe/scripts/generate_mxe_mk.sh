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

iecho "Preparing MXE Makefile for the target library..."

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
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --mxe_args <libname>          Optional: library name for MXE .mk generation"
    echo "                                If omitted, defaults to 'default' (generate defaults)"
    echo "  --owner_repo <owner/repo>     GitHub owner/repo"
    echo "  --archive <file>              Local archive file"
    echo "  --pkg <name>                  Package name"
    echo "  --tag <tag>                   Git tag (optional)"
    echo "  --version <version>           Package version"
    echo "  --archive_url <url>           URL to download archive"
    echo "  --checksum <sha256>           SHA256 checksum of archive"
    echo "  --description <desc>          Package description"
    echo "  --website <url>               Package website"
    echo "  --debug                       Enable debug output"
    echo "  -h, --help                    Show this help message"
    echo
    echo "Example:"
    echo "  $0 --mxe_args alembic --owner_repo hkunz/git-fetcher --archive alembic.tar.gz \\"
    echo "     --pkg alembic --version 1.0.0 --archive_url <url> --checksum <sha256> \\"
    echo "     --description 'Alembic library' --website https://example.com"
}

# =============================================
# Parse arguments
# =============================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mxe_args) MXE_ARGS="$2"; shift 2 ;;
        --owner_repo) OWNER_REPO="$2"; shift 2 ;;
        --archive) ARCHIVE_FILE="$2"; shift 2 ;;
        --pkg) PACKAGE_NAME="$2"; shift 2 ;;
        --tag) TAG="$2"; shift 2 ;;
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

iecho "======================= MXE Generation ======================="

# Load helper functions if they exist
[[ -f "$SCRIPT_DIR/lib.sh" ]] && source "$SCRIPT_DIR/lib.sh"

decho "Additional MXE args: $MXE_ARGS"
if [[ "$MXE_ARGS" == "default" || -z "$MXE_ARGS" ]]; then
    iecho "No package name provided; default generation with name $(bold_bright_green "$PACKAGE_NAME")"
else
    PACKAGE_NAME="${MXE_ARGS%%,*}"  # everything before first comma
    iecho "Using package name: $(bold_bright_green "$PACKAGE_NAME")"
fi

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

# =============================================
# Extract the entire archive
# =============================================
mkdir -p "$TMP_DIR"
tar -xf "$ARCHIVE_FILE" -C "$TMP_DIR"

TOP_DIR=$(tar -tf "$ARCHIVE_FILE" | head -1 | cut -d/ -f1)  # Detect top-level folder (source root)
SOURCE_ROOT="$TMP_DIR/$TOP_DIR"

# =============================================
# Query CMake for all real options
# =============================================
query_mxe_cmake_options() {
    local src_dir="$1"
    local build_dir="$2"

    mkdir -p "$build_dir"
    cd "$build_dir" || return 1
    if [[ "$DEBUG" == true ]]; then  # Configure to populate cache
        cmake "$src_dir" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON || true
    else
        cmake "$src_dir" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON > /dev/null 2>&1 || true
    fi
    # Only user-configurable options: BOOL and project-specific STRING/PATH
    if [[ "$DEBUG" == true ]]; then
        mapfile -t BUILD_OPTIONS < <(
            cmake -LAH "$build_dir" \
            | grep -E '^[A-Z0-9_]+:BOOL=' \
            | sed 's/:.*=/=/'
        )
    else
        mapfile -t BUILD_OPTIONS < <(
            cmake -LAH "$build_dir" 2>/dev/null \
            | grep -E '^[A-Z0-9_]+:BOOL=' \
            | sed 's/:.*=/=/'
        )
    fi
    BUILD_OPTIONS=($(printf '%s\n' "${BUILD_OPTIONS[@]}" | sort -u))  # Deduplicate
    iecho "MXE-relevant CMake options in $build_dir"
    for opt in "${BUILD_OPTIONS[@]}"; do
        decho --no-prefix "  $opt"
    done
    decho --no-prefix "}"
}

# =============================================
# Extract all CMake dependencies from CMakeLists.txt and .cmake files
# =============================================
extract_cmake_dependencies() {
    local files=("$@")
    local dep_list=()
    num_files=${#files[@]}
    iecho "[INFO] Parsing $num_files CMake files for dependencies..."

    for file in "${files[@]}"; do
        [[ -z "$file" || ! -f "$file" ]] && continue

        # Use grep + perl regex to extract the first argument of find_package/find_dependency
        while IFS= read -r dep; do
            dep_list+=("$dep")
        done < <(grep -i 'find_\(package\|dependency\)' "$file" | \
                 sed -E 's/^[[:space:]]*find_(package|dependency)[[:space:]]*\([[:space:]]*([^ )]+).*/\2/I')
    done

    # Deduplicate and sort
    DEPENDENCIES=($(printf '%s\n' "${dep_list[@]}" | sort -u))
}

# =============================================
# Query Meson for all real options
# =============================================
query_mxe_meson_options() {
    local src_dir="$1"
    local build_dir="$2"  # unused but kept for consistency
    BUILD_OPTIONS=()

    if [[ -n "$OPTIONS_FILE" ]]; then
        local full_path="$TMP_DIR/$OPTIONS_FILE"
        if [[ -f "$full_path" ]]; then
            # Collapse multiline 'option(...)' blocks into a single line
            local collapsed
            collapsed=$(awk 'BEGIN { ORS=""; inblock=0 }
                { gsub(/[[:space:]]+/, " ") }
                /^option\(/ { inblock=1; printf "%s", $0; next }
                inblock { printf " %s", $0 }
                /\)/ && inblock { print ""; inblock=0 }' "$full_path")
            decho "Raw Options: ${collapsed:0:100}"
            # Extract boolean options and set them as name=value
            BUILD_OPTIONS=$(echo "$collapsed" \
                | sed 's/option(/\noption(/g' \
                | sed -En "s/option\('([^']+)',[^)]*value:[[:space:]]*(true|false)[^)]*\)/\1=\2/p" \
                | tr '\n' ' ')
            BUILD_OPTIONS=($BUILD_OPTIONS)  # convert string to array
            iecho "Detected Meson build options from $OPTIONS_FILE"
            decho "Build options: {"
            for opt in "${BUILD_OPTIONS[@]}"; do
                decho --no-prefix "  $opt"
            done
            decho --no-prefix "}"
        else
            wecho "OPTIONS_FILE not found: $full_path"
        fi
    else
        wecho "No OPTIONS_FILE detected for Meson"
    fi
}

# =============================================
# Query for build options (e.g. CMake vars)
# =============================================
case "$BUILD_SYSTEM" in
    CMake)
        TMP_BUILD_DIR="$SOURCE_ROOT/build"
        decho "CMake build folder: $TMP_BUILD_DIR"
        query_mxe_cmake_options "$SOURCE_ROOT" "$TMP_BUILD_DIR"
        FILES_TO_PARSE=()
        [[ -n "$MAIN_FILE" ]] && FILES_TO_PARSE+=("$TMP_DIR/$MAIN_FILE")
        if [[ -n "$OTHER_FILES" ]]; then
            while IFS= read -r f; do
                [[ -n "$f" && -f "$TMP_DIR/$f" ]] && FILES_TO_PARSE+=("$TMP_DIR/$f")
            done <<< "$OTHER_FILES"
        fi
        extract_cmake_dependencies "${FILES_TO_PARSE[@]}"
        decho "Detected CMake dependencies:"
        for dep in "${DEPENDENCIES[@]}"; do
            decho --no-prefix "  $dep"
        done
        decho --no-prefix "}"
        ;;
    Meson)
        TMP_BUILD_DIR="$SOURCE_ROOT/build-meson"
        decho "Meson build folder: $TMP_BUILD_DIR"
        query_mxe_meson_options "$SOURCE_ROOT" "$TMP_BUILD_DIR" ;;
    *)
        iecho "Nothing to query for build system: $BUILD_SYSTEM"
        ;;
esac

PC_FILE_LIBS=$(printf ' -l%s' "${DEPENDENCIES[@]}" | sed -E 's/lib//Ig' | cut -c2-)
MXE_DEPENDENCIES=("cc" "${DEPENDENCIES[@]}")
MXE_DEPENDENCIES=$(echo "${MXE_DEPENDENCIES[*]}" | sed -E "s/\b(lib)?alembic\b//Ig" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')

BUILD_OPTIONS_MULTILINE=""
for opt in "${BUILD_OPTIONS[@]}"; do
    BUILD_OPTIONS_MULTILINE+=$'\t\t-D'"$opt"$' \\\n'
done

# =============================================
# Cleanup temporary extraction
# =============================================
if [[ "$DEBUG" != true ]]; then
    rm -rf "$TMP_DIR"
    iecho "Temporary directory removed: $TMP_DIR"
else
    decho "Keeping temporary directory: $TMP_DIR"
fi

# =============================================
# Generate .mk file
# =============================================
GEN_MXE_ROOT="$ROOT_DIR/contrib/mxe"
OUTPUT_DIR="$GEN_MXE_ROOT/generated"
TEST_LANG="${TEST_LANG:-cpp}"  # default to cpp if not set
TEMPLATE="$GEN_MXE_ROOT/templates/mxe-template.mk"
OUTPUT_FILE="$OUTPUT_DIR/$PACKAGE_NAME.mk"
IGNORE=""

mkdir -p "$OUTPUT_DIR"

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

TAG_PREFIX="${TAG%%[0-9]*}"
ARCHIVE_FORMAT=""
if [[ -n "$TAG_PREFIX" ]]; then
    ARCHIVE_FORMAT=",${TAG_PREFIX}"
fi

iecho "---------------------------------------------------------------"

sed \
${DELETE_BLOCK:+-e "$DELETE_BLOCK"} \
${DELETE_BUILD:+-e "$DELETE_BUILD"} \
${DELETE_PC_BLOCK:+-e "$DELETE_PC_BLOCK"} \
${DELETE_PC_BLOCK:+-e "$DELETE_INCLUDE_BLOCK"} \
-e "s|\${OWNER_REPO}|$OWNER_REPO|g" \
-e "s|\${ARCHIVE_FORMAT}|$ARCHIVE_FORMAT|g" \
-e "s|\${PACKAGE}|$PACKAGE_NAME|g" \
-e "s|\${WEBSITE}|$GIT_URL|g" \
-e "s|\${VERSION}|$VERSION|g" \
-e "s|\${DESCRIPTION}|$DESCRIPTION|g" \
-e "s|\${ARCHIVE_URL}|$ARCHIVE_URL|g" \
-e "s|\${IGNORE}|$IGNORE|g" \
-e "s|\${CHECKSUM}|$CHECKSUM|g" \
-e "s|\${DEPENDENCIES}|$MXE_DEPENDENCIES|g" \
-e "s|\${LIBS}|$PC_FILE_LIBS|g" \
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
TEST_TEMPLATE="$GEN_MXE_ROOT/templates/test.lang.template"
TEST_FILE="$OUTPUT_DIR/${PACKAGE_NAME}-test.$TEST_LANG"

export TEST_LANG
export PACKAGE_NAME
export COMPILER=$([[ "$TEST_LANG" == "cpp" ]] && echo g++ || echo gcc)
export TARGET="${MXE_TARGET:-x86_64-w64-mingw32.static}"
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


# =============================================
# Copy generated files to MXE_ROOT/src with overwrite prompt
# =============================================
if [[ -n "$MXE_ROOT" && -d "$MXE_ROOT/src" ]]; then
    for file in "$OUTPUT_FILE" "$TEST_FILE"; do
        dest="$MXE_ROOT/src/$(basename "$file")"
        if [[ -e "$dest" ]]; then
            echo -e "$(bright_red "[PROMPT]") File exists: $(bright_yellow $dest)"
            read -p "$(bright_red "[?]") Overwrite? $(bright_yellow "[y/N]") " answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                cp "$file" "$dest"
                iecho "Overwritten $dest"
            else
                iecho "Skipped $dest"
                break
            fi
        else
            cp "$file" "$dest"
            iecho "Copied $file to $dest"
        fi
    done
fi
