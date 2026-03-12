#!/usr/bin/env bash
set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SCRIPT_DIR="$ROOT_DIR/scripts"

source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/lib-db.sh"
source "$SCRIPT_DIR/lib-color.sh"

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
for module in "$ROOT_DIR"/hosts/*.sh; do
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
init_db
entry=$(get_db_entry "$GIT_URL")

if [[ -n "$entry" && -f $(echo "$entry" | jq -r '.archive') && "$FORCE_DOWNLOAD" == false ]]; then
    # Use existing DB entry
    ARCHIVE_FILE=$(echo "$entry" | jq -r '.archive')
    ARCHIVE_NAME=$(basename "$ARCHIVE_FILE")
    TAG=$(echo "$entry" | jq -r '.latest_tag')
    [ "$TAG" == "null" ] && TAG=""
    BRANCH=$(echo "$entry" | jq -r '.default_branch')
    CHECKSUM=$(echo "$entry" | jq -r '.sha256')
    iecho "Using archive from DB: $ARCHIVE_FILE"

else
    # DB missing or force download → fetch host-specific info
    FETCH_FUNC="fetch_latest_$HOST"
    if ! declare -f "$FETCH_FUNC" >/dev/null; then
        eecho "Fetch function '$FETCH_FUNC' not found!"
        exit 1
    fi

    "$FETCH_FUNC" "$OWNER_REPO"  # fetch_latest_* should set TAG and BRANCH

    [ -z "$TAG" ] && TAG=""  # Ensure TAG is empty string if repo has no tags

    ARCHIVE_VERSION="${TAG:-$BRANCH}"  # Determine version to download (TAG if exists, otherwise BRANCH)
    ARCHIVE_FILE="$(basename "$OWNER_REPO")-$ARCHIVE_VERSION.tar.gz"
    ARCHIVE_URL="https://gitlab.com/$OWNER_REPO/-/archive/$ARCHIVE_VERSION/$ARCHIVE_FILE"

    # Download archive
    vecho "Downloading archive..."
    mkdir -p "$ROOT_DIR/downloads/"
    download_archive "$ARCHIVE_URL" "$ROOT_DIR/downloads/$ARCHIVE_FILE"
    ARCHIVE_FILE="$ROOT_DIR/downloads/$ARCHIVE_FILE"
    CHECKSUM=$(compute_sha256 "$ARCHIVE_FILE")

    # Store in DB with correct TAG and BRANCH
    update_db "$GIT_URL" "$TAG" "$BRANCH" "$ARCHIVE_FILE" "$CHECKSUM"
    iecho "Downloaded archive: $ARCHIVE_FILE"
fi

iecho "Downloaded file: $(bold_bright_cyan "$(basename "$ARCHIVE_FILE")")"
if [ -n "$TAG" ]; then
    iecho "Latest Tag: $(bold_bright_cyan "$TAG")"
else
    iecho "Default Branch: $(bold_bright_cyan "$BRANCH") (No tag available)"
fi
iecho "SHA256 checksum: $(bold_bright_cyan "$CHECKSUM")"

# =============================================
# Optional: generate MXE .mk file
# =============================================
if [[ "$GENERATE_MXE" == true ]]; then
    vecho "Generating MXE .mk file..."
    bash "$ROOT_DIR/mxe/scripts/generate_mxe_mk.sh" \
        --pkg "$OWNER_REPO" \
        --version "$VERSION" \
        --version "$TAG" \
        --archive "$ARCHIVE_FILE" \
        --checksum "$CHECKSUM"
fi
