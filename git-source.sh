#!/usr/bin/env bash
set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SCRIPT_DIR="$ROOT_DIR"
source "$SCRIPT_DIR/lib.sh"

LIST_BRANCHES=false
INPUT=""
VERBOSE=false
DEBUG=false

# =============================================
# Argument parsing
# =============================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--list-branches) LIST_BRANCHES=true ;;
        -v|--verbose) VERBOSE=true ;;
        --debug) DEBUG=true ;;
        --generate-mxe-makefile) GENERATE_MXE=true ;;  # <-- new flag
        -h|--help)
            echo "Usage: $0 [OPTIONS] <repo_url_or_owner/repo>"
            echo
            echo "Options:"
            echo "  -b, --list-branches          List all branches of the repository"
            echo "  -v, --verbose                Enable verbose output"
            echo "  --debug                      Enable debug output"
            echo "  --generate-mxe-makefile      Generate MXE .mk file after download"
            echo "  -h, --help                   Show this help message"
            exit 0
            ;;
        -*)
            eecho "Unknown option: $1"
            exit 1
            ;;
        *) INPUT="$1" ;;
    esac
    shift
done

if [ -z "$INPUT" ]; then
    echo "Usage:"
    echo "  $0 [OPTIONS] <repo_url_or_owner/repo>"
    echo
    echo "Options:"
    echo "  -b, --list-branches    List all branches of the repository"
    echo "  -v, --verbose          Show verbose output"
    echo "      --debug            Show debug output"
    exit 1
fi

# =============================================
# Source host modules dynamically and detect host
# =============================================
HOST=""
OWNER_REPO=""
GIT_URL=""
for module in "$SCRIPT_DIR"/hosts/*.sh; do
    source "$module"
    if declare -f detect_host >/dev/null; then
        if detect_host "$INPUT"; then
            break
        fi
    fi
done

if [ -z "$HOST" ]; then
    eecho "Unsupported host in URL '$INPUT'"
    exit 1
fi

vecho "Host detected: $HOST"
vecho "OWNER_REPO: $OWNER_REPO"
vecho "GIT_URL: $GIT_URL"

# =============================================
# List branches if requested
# =============================================
if $LIST_BRANCHES; then
    iecho "Branches for $OWNER_REPO:"
    git ls-remote --heads "$GIT_URL" | awk '{print $2}' | sed 's#refs/heads/##'
    exit 0
fi

# =============================================
# Call host-specific fetch function
# =============================================
FETCH_FUNC="fetch_latest_$HOST"
if ! declare -f "$FETCH_FUNC" >/dev/null; then
    eecho "Fetch function '$FETCH_FUNC' not found!"
    exit 1
fi
"$FETCH_FUNC" "$OWNER_REPO"

# =============================================
# Download archive and compute checksum
# =============================================
mkdir -p "$ROOT_DIR/downloads"
ARCHIVE_FILE="$ROOT_DIR/downloads/$(basename "$OWNER_REPO")-$VERSION.tar.gz"
download_archive "$ARCHIVE_URL" "$ARCHIVE_FILE"
compute_sha256 "$ARCHIVE_FILE"

# =============================================
# Optional: generate MXE .mk file
# =============================================
if $GENERATE_MXE; then
    vecho "Generating MXE .mk file..."
    bash "$ROOT_DIR/mxe/scripts/generate_mxe_mk.sh" \
        --pkg "$OWNER_REPO" \
        --version "$VERSION" \
        --archive "$ARCHIVE_FILE" \
        --checksum "$(compute_sha256 "$ARCHIVE_FILE")"
fi
