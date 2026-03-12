#!/usr/bin/env bash
set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SCRIPT_DIR="$ROOT_DIR"
source "$SCRIPT_DIR/scripts/lib.sh"
source "$SCRIPT_DIR/scripts/lib-db.sh"

LIST_BRANCHES=false
INPUT=""
VERBOSE=false
DEBUG=false

# =============================================
# Argument parsing
# =============================================
FORCE_DOWNLOAD=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--list-branches) LIST_BRANCHES=true ;;
        -v|--verbose) VERBOSE=true ;;
        --debug) DEBUG=true ;;
        --generate-mxe-makefile) GENERATE_MXE=true ;;
        --force) FORCE_DOWNLOAD=true ;;  # <-- new force download flag
        -h|--help)
            echo "Usage: $0 [OPTIONS] <repo_url_or_owner/repo>"
            echo
            echo "Options:"
            echo "  -b, --list-branches          List all branches of the repository"
            echo "  -v, --verbose                Enable verbose output"
            echo "  --debug                      Enable debug output"
            echo "  --generate-mxe-makefile      Generate MXE .mk file after download"
            echo "  --force                      Redownload archive even if it exists"
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
# Download archive and compute checksum with DB
# =============================================
init_db  # ensure DB exists

entry=$(get_db_entry "$GIT_URL")

# Check to use DB entry if available
if [[ -n "$entry" && -f $(echo "$entry" | jq -r '.archive') && "$FORCE_DOWNLOAD" == false ]]; then

    ARCHIVE_FILE=$(echo "$entry" | jq -r '.archive')
    VERSION=$(echo "$entry" | jq -r '.latest_tag')
    CHECKSUM=$(echo "$entry" | jq -r '.sha256')
    iecho "Using archive from DB: $ARCHIVE_FILE"

else # 🛑 DB missing or no entry: must download to create DB entry
    FETCH_FUNC="fetch_latest_$HOST"
    if ! declare -f "$FETCH_FUNC" >/dev/null; then
        eecho "Fetch function '$FETCH_FUNC' not found!"
        exit 1
    fi

    "$FETCH_FUNC" "$OWNER_REPO"

    ARCHIVE_FILE="$ROOT_DIR/downloads/$(basename "$OWNER_REPO")-$VERSION.tar.gz"
    vecho "Downloading archive..."
    download_archive "$ARCHIVE_URL" "$ARCHIVE_FILE"
    CHECKSUM=$(compute_sha256 "$ARCHIVE_FILE")
    update_db "$GIT_URL" "$VERSION" "$ARCHIVE_FILE" "$CHECKSUM"
    iecho "Downloaded file: $(basename "$ARCHIVE_FILE")"
    iecho "Downloaded archive: $ARCHIVE_FILE"
fi

iecho "SHA256 checksum: $CHECKSUM"

# =============================================
# Optional: generate MXE .mk file
# =============================================
if [[ "$GENERATE_MXE" == true ]]; then
    vecho "Generating MXE .mk file..."
    bash "$ROOT_DIR/mxe/scripts/generate_mxe_mk.sh" \
        --pkg "$OWNER_REPO" \
        --version "$VERSION" \
        --archive "$ARCHIVE_FILE" \
        --checksum "$CHECKSUM"
fi
