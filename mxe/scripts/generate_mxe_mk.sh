#!/usr/bin/env bash
set -e

# =============================================
# Arguments
# =============================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --owner-repo) OWNER_REPO="$2"; shift 2;;
        --pkg) PACKAGE="$2"; shift 2;;
        --version) VERSION="$2"; shift 2;;
        --archive) ARCHIVE="$2"; shift 2;;
        --archive_url) ARCHIVE_URL="$2"; shift 2;;
        --checksum) CHECKSUM="$2"; shift 2;;
        --test-lang) TEST_LANG="$2"; shift 2;;
        --description) DESCRIPTION="$2"; shift 2;;
        --website) WEBSITE="$2"; shift 2;;
        --build-system) BUILD_SYSTEM="$2"; shift 2;;
        --build-options) BUILD_OPTIONS="$2"; shift 2;;
        *)
            echo "[ERROR] Unknown option: $1"
            echo "Usage: $0 --owner-repo <owner/repo> --pkg <package> --version <version> --archive <file> --checksum <sha256> [--test-lang <c|cpp>] [--description <text>]"
            exit 1
            ;;
    esac
done

# =============================================
# Required arguments check
# =============================================
if [ -z "$PACKAGE" ] || [ -z "$VERSION" ] || [ -z "$ARCHIVE" ] || [ -z "$CHECKSUM" ]; then
    echo "Usage: $0 --pkg <package> --version <version> --archive_url <url> --archive <file> --checksum <sha256> [--test-lang <c|cpp>] [--description <text>] [--dependencies <list>]"
    exit 1
fi

# =============================================
# Defaults
# =============================================
MXE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$MXE_ROOT/generated"
mkdir -p "$OUTPUT_DIR"

TEST_LANG="${TEST_LANG:-cpp}"  # default to cpp if not set

# =============================================
# Generate .mk file
# =============================================
TEMPLATE="$MXE_ROOT/templates/mxe-template.mk"
OUTPUT_FILE="$OUTPUT_DIR/$PACKAGE.mk"
IGNORE=""

BUILD_OPTIONS_MULTILINE=""
for opt in $BUILD_OPTIONS; do
    BUILD_OPTIONS_MULTILINE+=$'\t\t-D'"$opt"$' \\\n'
done

TMP=$(mktemp)

if [[ "$WEBSITE" == *"github.com"* ]]; then
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
        BUILD_OPTIONS_MULTILINE+="\t\t--buildtype=release"
        DELETE_BUILD='/# BEGIN_CMAKE/,/# END_CMAKE/d; /# BEGIN_OTHER_BUILD_SYSTEM/,/# END_OTHER_BUILD_SYSTEM/d'
        ;;
    *)
        DELETE_BUILD='/# BEGIN_CMAKE/,/# END_CMAKE/d; /# BEGIN_MESON/,/# END_MESON/d'
        ;;
esac

sed \
${DELETE_BLOCK:+-e "$DELETE_BLOCK"} \
${DELETE_BUILD:+-e "$DELETE_BUILD"} \
-e "s|\${OWNER_REPO}|$OWNER_REPO|g" \
-e "s|\${PACKAGE}|$PACKAGE|g" \
-e "s|\${WEBSITE}|$WEBSITE|g" \
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
"$TEMPLATE" > "$OUTPUT_FILE"

# inserting a multiline block of build optiond via temporary file to work around sed's inability to handle multiline replacements
echo -e "$BUILD_OPTIONS_MULTILINE" > "$TMP"
sed -i "/\${BUILD_OPTIONS_MULTILINE}/{
    r $TMP
    d
}" "$OUTPUT_FILE"

rm "$TMP"

echo "[INFO] Generated MXE .mk file: $OUTPUT_FILE"

# =============================================
# Generate test file
# =============================================
TEST_TEMPLATE="$MXE_ROOT/templates/test.lang.template"
TEST_FILE="$OUTPUT_DIR/${PACKAGE}-test.$TEST_LANG"


envsubst < "$TEST_TEMPLATE" > "$TEST_FILE"
echo "[INFO] Generated test file: $TEST_FILE"
