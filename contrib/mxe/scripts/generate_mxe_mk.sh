#!/usr/bin/env bash
set -e

# =============================================
# generate_mxe.sh
# Generates MXE .mk file from a downloaded archive
# =============================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." &>/dev/null && pwd)"
SCRIPT_DIR="$ROOT_DIR/scripts"
MXE_SCRIPT_DIR="$ROOT_DIR/contrib/mxe/scripts"
TMP_DIR="$ROOT_DIR/tmp"

source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/lib-color.sh"

if [[ -f "Makefile" && -d "src" && $(grep -o 'MXE' Makefile | wc -l) -ge 40 ]]; then
    vecho "Running inside of MXE root detected: $(pwd)"
    if [[ -z "$MXE_ROOT" ]]; then
        export MXE_ROOT="$(pwd)"
        vecho "MXE_ROOT environment variable set to $MXE_ROOT"
    else
        vecho "MXE_ROOT already set: $MXE_ROOT"
    fi
else
    vecho "Currently not running inside MXE root: $(pwd)"
fi

iecho "Preparing MXE Makefile for the target library..."

ARCHIVE_FILE=""
PACKAGE_NAME=""
PACKAGE_NAME_MXE=""
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
    echo "  --archive_subdir <dir>        Local archive file's sub-directory"
    echo "  --pkg <name>                  Package name"
    echo "  --tag <tag>                   Git tag (optional)"
    echo "  --version <version>           Package version"
    echo "  --archive_url <url>           URL to download archive"
    echo "  --checksum <sha256>           SHA256 checksum of archive"
    echo "  --description <desc>          Package description"
    echo "  --website <url>               Package website"
    echo "  --language <lang>             Primary language used in package"
    echo "  --debug                       Enable debug output"
    echo "  -h, --help                    Show this help message"
    echo
    echo "Example: No example"
}

# =============================================
# Parse arguments
# =============================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mxe_args) MXE_ARGS="$2"; shift 2 ;;
        --owner_repo) OWNER_REPO="$2"; shift 2 ;;
        --archive) ARCHIVE_FILE="$2"; shift 2 ;;
        --archive_subdir) SUBDIR_NAME="$2"; shift 2 ;;
        --pkg) PACKAGE_NAME="$2"; shift 2 ;;
        --tag) TAG="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --archive_url) ARCHIVE_URL="$2"; shift 2 ;;
        --checksum) CHECKSUM="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --website) GIT_URL="$2"; shift 2 ;;
        --language) LANGUAGE="$2"; shift 2 ;;
        --debug) DEBUG=true; shift ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

# Check required variables
for var in ARCHIVE_FILE SUBDIR_NAME PACKAGE_NAME VERSION ARCHIVE_URL CHECKSUM DESCRIPTION GIT_URL; do
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
    PACKAGE_NAME_MXE=$PACKAGE_NAME
else
    PACKAGE_NAME_MXE="${MXE_ARGS%%,*}"  # everything before first comma
    PACKAGE_NAME_MXE="${PACKAGE_NAME_MXE%.mk}"
    iecho "Using package name: $(bold_bright_green "$PACKAGE_NAME_MXE")"
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
if file "$ARCHIVE_FILE" | grep -qE 'gzip|tar archive'; then
    decho "Extracting archive: $ARCHIVE_FILE into $TMP_DIR"
    tar -xf "$ARCHIVE_FILE" -C "$TMP_DIR"
else
    eecho "$(bold_bright_red "Downloaded file is not a valid tar.gz archive: $ARCHIVE_FILE")"
    exit 1
fi

TOP_DIR=$(tar -tf "$ARCHIVE_FILE" | head -1 | cut -d/ -f1)  # Detect top-level folder (source root)
export SOURCE_ROOT="$TMP_DIR/$TOP_DIR"

# =============================================
# Query for build options (e.g. CMake vars)
# =============================================
BUILD_SYSTEM_LOWER=$(echo "$BUILD_SYSTEM" | tr '[:upper:]' '[:lower:]')
BUILD_SYSTEM_FILE="$MXE_SCRIPT_DIR/build_systems/mxe_${BUILD_SYSTEM_LOWER}.sh"

is_pc_missing_in_src() {
    if [[ -z "$PC_FILE" ]]; then
        return 0  # missing
    fi
    if [[ "$PC_FILE" = /* ]]; then
        [[ ! -s "$PC_FILE" ]]
    else
        [[ ! -s "$TMP_DIR/$PC_FILE" ]]
    fi
}

BUILD_SYSTEM_SUPPORT=true
MXE_DEPENDENCIES=()
# Source the appropriate file
if [[ -f "$BUILD_SYSTEM_FILE" ]]; then
    source "$BUILD_SYSTEM_FILE"
    mxe_query_build
    if is_pc_missing_in_src; then
        decho "Missing .pc file at '$TMP_DIR/$PC_FILE'. Generating fallback pkg-config variables..."
        mxe_generate_pc_file_vars
    fi
else
    BUILD_SYSTEM_SUPPORT=false
    echo
    wecho "$(bold_bright_yellow "Warning: No support for build system"): $(bold_bright_cyan "$BUILD_SYSTEM")"
    echo
fi

MXE_DEPENDENCIES=("cc" "${MXE_DEPENDENCIES[@]}")
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
TEST_LANG=$([ "$LANGUAGE" = "C" ] && echo "c" || echo "cpp")
TEMPLATE="$GEN_MXE_ROOT/templates/mxe-template.mk"
OUTPUT_MAKEFILE="$OUTPUT_DIR/$PACKAGE_NAME_MXE.mk"
MAKE_CMD="MAKE"
IGNORE=""

mkdir -p "$OUTPUT_DIR"

if [[ "$GIT_URL" == *"github.com"* ]]; then
    GH_MODE=$(deduce_gh_mode "$ARCHIVE_URL")
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
        MAKE_CMD="MXE_NINJA"
        ;;
    *)
        DELETE_BUILD='/# BEGIN_CMAKE/,/# END_CMAKE/d; /# BEGIN_MESON/,/# END_MESON/d'
        ;;
esac

export TARGET="${MXE_TARGET:-x86_64-w64-mingw32.static}"

# =============================================
# When this script is run again after MXE's `make <package>`, it checks whether
# a .pc file was generated in usr/<target>/lib/pkgconfig/.
# =============================================
IS_PC_GENERATED=false
if [[ -n "$MXE_ROOT" ]]; then
    PKGCONFIG_DIR="$MXE_ROOT/usr/$TARGET/lib/pkgconfig"
    mapfile -t pc_files < <(
        find "$PKGCONFIG_DIR" -iname "*.pc" \
            | grep -i "$PACKAGE_NAME_MXE"
    )
    # Filter out MXE auto-generated files
    real_pc_files=()
    for pc in "${pc_files[@]}"; do
        if ! head -n1 "$pc" | grep -q "MXE"; then
            real_pc_files+=("$pc")
        fi
    done
    if [[ ${#real_pc_files[@]} -gt 0 ]]; then
        decho "Detected possible .pc files for '$PACKAGE_NAME_MXE':"
        for pc in "${real_pc_files[@]}"; do
            decho "--  $pc"
        done
        decho "Current .pc name: '$PC_FILE_NAME'"
        PC_FILE="${real_pc_files[0]}"
        PC_FILE_NAME="$(basename "${real_pc_files[0]}")"
        PC_FILE_NAME="${PC_FILE_NAME%.pc}"
        decho "Replace .pc name: '$PC_FILE_NAME'"
        IS_PC_GENERATED=true
    fi
fi

if is_pc_missing_in_src && [[ "$IS_PC_GENERATED" != true ]]; then
    PC_FILE_NAME='\$(PKG)'
else
    vecho "PC file exists and is not empty: $PC_FILE"
    DELETE_PC_BLOCK='/^$/ { N; /^[[:space:]]*\n[[:space:]]*# BEGIN_PC_FILE$/ { N; /# END_PC_FILE/d } } ; /^[[:space:]]*# BEGIN_PC_FILE/,/^[[:space:]]*# END_PC_FILE/d'  # Remove PC file generation block
    DELETE_INCLUDE_BLOCK='/^$/ { N; /^[[:space:]]*\n[[:space:]]*# BEGIN_INCLUDE$/ { N; /# END_INCLUDE/d } } ; /^[[:space:]]*# BEGIN_INCLUDE/,/^[[:space:]]*# END_INCLUDE/d'
    PC_FILE_NAME=$(basename "$PC_FILE")
    PC_FILE_NAME="${PC_FILE_NAME%.pc.in}"
    PC_FILE_NAME="${PC_FILE_NAME%.pc}"
fi

TAG_PREFIX="${TAG%%[0-9]*}"
ARCHIVE_FORMAT=""
if [[ -n "$TAG_PREFIX" ]]; then
    ARCHIVE_FORMAT=",${TAG_PREFIX}"
fi

iecho "---------------------------------------------------------------"

GH_MODE="tags"  # Always use tags; even branches like master/main are handled as tags, because releases may contain binaries instead of source
TAR_NAME="$SUBDIR_NAME.tar.gz"

sed \
${DELETE_BLOCK:+-e "$DELETE_BLOCK"} \
${DELETE_BUILD:+-e "$DELETE_BUILD"} \
${DELETE_PC_BLOCK:+-e "$DELETE_PC_BLOCK"} \
${DELETE_INCLUDE_BLOCK:+-e "$DELETE_INCLUDE_BLOCK"} \
-e "s|\${OWNER_REPO}|$OWNER_REPO|g" \
-e "s|\${GH_MODE}|$GH_MODE|g" \
-e "s|\${ARCHIVE_FORMAT}|$ARCHIVE_FORMAT|g" \
-e "s|\${PACKAGE}|$PACKAGE_NAME_MXE|g" \
-e "s|\${WEBSITE}|$GIT_URL|g" \
-e "s|\${VERSION}|$VERSION|g" \
-e "s|\${DESCRIPTION}|$DESCRIPTION|g" \
-e "s|\${ARCHIVE_URL}|$ARCHIVE_URL|g" \
-e "s|\([[:space:]]*\)\${IGNORE}|${IGNORE:+\1$IGNORE}|g" \
-e "s|\${CHECKSUM}|$CHECKSUM|g" \
-e "s|\${DEPENDENCIES}|$MXE_DEPENDENCIES|g" \
-e "s|\${PKG_SUBFOLDER}|$PKG_SUBFOLDER|g" \
-e "s|\${REQUIRES_PRIVATE}|$REQUIRES_PRIVATE|g" \
-e "s|\${REQUIRES}|$REQUIRES|g" \
-e "s|\${LIBS_PRIVATE}|$LIBS_PRIVATE|g" \
-e "s|\${LIBS}|$LIBS|g" \
-e "s|\${CFLAGS_PRIVATE}|$CFLAGS_PRIVATE|g" \
-e "s|\${CFLAGS}|$CFLAGS|g" \
-e "s|\${MAKE_CMD}|$MAKE_CMD|g" \
-e "s|\${PC_FILE_NAME}|$PC_FILE_NAME|g" \
-e "s|\${SUBDIR_NAME}|$SUBDIR_NAME|g" \
-e "s|\${TAR_NAME}|$TAR_NAME|g" \
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
"$TEMPLATE" > "$OUTPUT_MAKEFILE"

# inserting a multiline block of build options via temporary file to work around sed's inability to handle multiline replacements
TMP=$(mktemp)
echo -e "$BUILD_OPTIONS_MULTILINE" > "$TMP"
sed -i "/\${BUILD_OPTIONS_MULTILINE}/{
    r $TMP
    d
}" "$OUTPUT_MAKEFILE"
rm "$TMP"

# Escape dots for sed
ESC_VERSION="${VERSION//./\\.}"
ESC_PACKAGE="${PACKAGE_NAME_MXE//./\\.}"
# reduce hardcoded redundancy for package name and version
sed -i "/_URL\|_SUBDIR\|_FILE\|pkg-config/{
    s|$ESC_PACKAGE|\\\$(PKG)|g
    s|$ESC_VERSION|\\\$\\(\$(PKG)_VERSION\\)|g
}" "$OUTPUT_MAKEFILE"

iecho "Generated MXE .mk file: $OUTPUT_MAKEFILE"

# =============================================
# Generate test file
# =============================================
TEST_TEMPLATE="$GEN_MXE_ROOT/templates/test.lang.template"
TEST_FILE="$OUTPUT_DIR/${PACKAGE_NAME_MXE}-test.$TEST_LANG"

export TEST_LANG
export PACKAGE_NAME_MXE
export COMPILER=$([[ "$TEST_LANG" == "cpp" ]] && echo g++ || echo gcc)
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

if is_pc_missing_in_src && [ "$BUILD_SYSTEM_SUPPORT" = true ]; then
    echo
    echo "[$(bold_bright_green "NOTE")] The generated '$PACKAGE_NAME.mk' may have incomplete variables for GENERATE_PC,"
    echo "       or even the package may dynamically generate a .pc file after building,"
    echo "       so manual generation may be unnecessary. For accurate values, build the MXE package"
    echo "       with 'make $PACKAGE_NAME MXE_KEEP_TMP=1' and re-run this script to populate the missing .pc variables."
fi

# =============================================
# Copy generated files to MXE_ROOT/src with overwrite prompt
# =============================================
echo
overwrite_confirmed=false
FILES=()

if [[ "$GENERATE_MXE_MAKEFILE" == true ]]; then
    FILES+=("$OUTPUT_MAKEFILE")
fi

if [[ "$GENERATE_MXE_TESTFILE" == true ]]; then
    FILES+=("$TEST_FILE")
fi

if [[ -n "$MXE_ROOT" && -d "$MXE_ROOT/src" ]]; then
    if ! grep -q '^[[:space:]]*MXE_KEEP_TMP' "$MXE_ROOT/Makefile"; then
        # remove the line that deletes the per-package temporary build directory (TMP_DIR, e.g. tmp-<pkg>-<target>) so it is preserved after successful builds for inspection/debugging (e.g. analyzing build artifacts or dependencies)
        sed -i "/rm -rfv[[:space:]]*'\$(2)'/d" "$MXE_ROOT/Makefile"
    fi
    # replace the MXE_TARGETS line with MXE_TARGETS=$TARGET
    sed -i -E "0,/MXE_TARGETS/{s/^[[:space:]]*MXE_TARGETS[[:space:]]*[:]?=[[:space:]]*.*/MXE_TARGETS        := $TARGET/}" "$MXE_ROOT/Makefile"

    for file in "${FILES[@]}"; do
        dest="$MXE_ROOT/src/$(basename "$file")"
        if [[ -e "$dest" ]]; then
            iecho "Copying generated file to $MXE_ROOT/src/"
            echo -e "$(bright_red "[PROMPT]") File exists: $(bright_yellow $dest)"
            read -p "$(bright_red "[?]") Overwrite? $(bright_yellow "[y/N]") " answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                cp "$file" "$dest"
                iecho "Overwritten $dest"
                overwrite_confirmed=true
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
