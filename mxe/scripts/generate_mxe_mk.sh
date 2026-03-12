#!/usr/bin/env bash
set -e

# =============================================
# Arguments
# =============================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pkg) PACKAGE="$2"; shift 2;;
        --version) VERSION="$2"; shift 2;;
        --archive) ARCHIVE="$2"; shift 2;;
        --checksum) CHECKSUM="$2"; shift 2;;
        --test-lang) TEST_LANG="$2"; shift 2;;
        --description) DESCRIPTION="$2"; shift 2;;
        *)
            echo "[ERROR] Unknown option: $1"
            echo "Usage: $0 --pkg <package> --version <version> --archive <file> --checksum <sha256> [--test-lang <c|cpp>] [--description <text>]"
            exit 1
            ;;
    esac
done

# =============================================
# Required arguments check
# =============================================
if [ -z "$PACKAGE" ] || [ -z "$VERSION" ] || [ -z "$ARCHIVE" ] || [ -z "$CHECKSUM" ]; then
    echo "Usage: $0 --pkg <package> --version <version> --archive <file> --checksum <sha256> [--test-lang <c|cpp>] [--description <text>] [--dependencies <list>]"
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
TEMPLATE="$MXE_ROOT/templates/cmake.template.mk"
OUTPUT_FILE="$OUTPUT_DIR/$PACKAGE.mk"
IGNORE=""

sed \
    -e "s|\${PACKAGE}|$PACKAGE|g" \
    -e "s|\${VERSION}|$VERSION|g" \
    -e "s|\${DESCRIPTION}|$DESCRIPTION|g" \
    -e "s|\${ARCHIVE}|$ARCHIVE|g" \
    -e "s|\${IGNORE}|$IGNORE|g" \
    -e "s|\${CHECKSUM}|$CHECKSUM|g" \
    "$TEMPLATE" > "$OUTPUT_FILE"

echo "[INFO] Generated MXE .mk file: $OUTPUT_FILE"

# =============================================
# Generate test file
# =============================================
TEST_TEMPLATE="$MXE_ROOT/templates/test.lang.template"
TEST_FILE="$OUTPUT_DIR/${PACKAGE}-test.$TEST_LANG"


envsubst < "$TEST_TEMPLATE" > "$TEST_FILE"
echo "[INFO] Generated test file: $TEST_FILE"
