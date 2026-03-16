#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SCRIPT_DIR="$ROOT_DIR/scripts"

source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/lib-db.sh"
source "$SCRIPT_DIR/lib-color.sh"

LIST_BRANCHES=false
VERBOSE=false
DEBUG=false
GENERATE_MXE=false
FORCE_DOWNLOAD=false
INPUT=""

# =============================================
# Usage function
# =============================================
print_usage() {
    echo "Usage: $0 [OPTIONS] <repo_url_or_owner/repo>"
    echo
    echo "Options:"
    echo "  -b, --list-branches          List all branches of the repository"
    echo "  -v, --verbose                Enable verbose output"
    echo "  --debug                      Enable debug output"
    echo "  --generate-mxe-makefile      Generate MXE .mk file after download"
    echo "  --force                      Redownload archive even if it exists"
    echo "  -h, --help                   Show this help message"
}

# =============================================
# Parse arguments
# =============================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--list-branches) LIST_BRANCHES=true ;;
        -v|--verbose) export VERBOSE=true ;;
        --debug) export DEBUG=true ;;
        --generate-mxe-makefile=*)
            GENERATE_MXE=true
            MXE_ARGS="${1#*=}"
            ;;
        --generate-mxe-makefile)
            GENERATE_MXE=true
            MXE_ARGS="default"
            ;;
        --force) FORCE_DOWNLOAD=true ;;
        -h|--help) print_usage; exit 0 ;;
        -*) eecho "Unknown option: $1"; exit 1 ;;
        *) INPUT="$1" ;;
    esac
    shift
done

[ -n "$INPUT" ] || { print_usage; exit 1; }

# =============================================
# Host detection
# =============================================
HOST=""
OWNER_REPO=""
GIT_URL=""
for module in "$ROOT_DIR"/hosts/*.sh; do
    source "$module"
    if declare -f detect_host >/dev/null && detect_host "$INPUT"; then
        break
    fi
done

[ -n "$HOST" ] || { eecho "Unsupported host in URL '$INPUT'"; exit 1; }

vecho "Detected host: $HOST"
vecho "Repository (owner/name): $OWNER_REPO"
vecho "Git URL: $GIT_URL"

# =============================================
# List branches if requested
# =============================================
if $LIST_BRANCHES; then
    iecho "Branches for $OWNER_REPO:"
    git ls-remote --heads "$GIT_URL" | awk '{print $2}' | sed 's#refs/heads/##'
    exit 0
fi

# =============================================
# Load archive info from DB
# =============================================
init_db
entry=$(get_db_entry "$GIT_URL")
get_entry_field() { echo "$entry" | jq -r "$1 // empty"; }

load_from_db() {
    ARCHIVE_URL=$(get_entry_field '.archive_url')
    ARCHIVE_FILE=$(get_entry_field '.archive')
    ARCHIVE_NAME=$(basename "$ARCHIVE_FILE")
    PACKAGE_NAME=$(get_entry_field '.package')
    DESCRIPTION=$(get_entry_field '.description')
    TAG=$(get_entry_field '.latest_tag')
    BRANCH=$(get_entry_field '.default_branch')
    CHECKSUM=$(get_entry_field '.sha256')
    BUILD_SYSTEM=$(get_entry_field '.build_system')
}

download_archive_if_needed() {
    GH_MODE="tags"
    FETCH_FUNC="fetch_latest_$HOST"
    [ "$(declare -f $FETCH_FUNC)" ] || { eecho "Fetch function '$FETCH_FUNC' not found!"; exit 1; }

    "$FETCH_FUNC" "$OWNER_REPO"  # sets TAG and BRANCH

    ARCHIVE_VERSION="${TAG:-$BRANCH}"
    ARCHIVE_NAME="$(basename "$OWNER_REPO")-$ARCHIVE_VERSION.tar.gz"
    ARCHIVE_FILE="$ROOT_DIR/downloads/$ARCHIVE_NAME"
    PACKAGE_NAME="$(basename "$OWNER_REPO")"

    mkdir -p "$ROOT_DIR/downloads/"
    download_archive "$ARCHIVE_URL" "$ARCHIVE_FILE"
    CHECKSUM=$(compute_sha256 "$ARCHIVE_FILE")
    JSON_OUTPUT=$(bash "$SCRIPT_DIR/detect-build.sh" "$ARCHIVE_FILE")
    BUILD_SYSTEM=$(echo "$JSON_OUTPUT" | jq -r '.build_system')
    update_db "$GIT_URL" "$TAG" "$BRANCH" "$ARCHIVE_URL" "$ARCHIVE_FILE" "$CHECKSUM" "$PACKAGE_NAME" "$DESCRIPTION" "$BUILD_SYSTEM"
}

# Decide whether to use DB or download
ARCHIVE_FILE_DB=$(get_entry_field '.archive')
if [[ -n "$entry" && -f "$ARCHIVE_FILE_DB" && "$FORCE_DOWNLOAD" == false ]]; then
    load_from_db
    iecho "Download URL: $ARCHIVE_URL"
    iecho "Using archive from DB: $ARCHIVE_FILE"
else
    download_archive_if_needed
    iecho "Downloaded archive: $ARCHIVE_FILE"
fi

# Show tag or branch
if [ -n "$TAG" ]; then
    iecho "Latest Tag: $(bold_bright_green "$TAG")"
else
    iecho "Default Branch: $(bold_bright_green "$BRANCH") (No tag found)"
fi

# =============================================
# Display summary
# =============================================
iecho "Downloaded file: $(bold_bright_cyan "$ARCHIVE_NAME")"
iecho "Package name: $(bold_bright_green "$PACKAGE_NAME")"
[ -n "$DESCRIPTION" ] && iecho "Package description: $(if [ "$DEBUG" = true ]; then echo "$DESCRIPTION"; else echo "${DESCRIPTION:0:40}..."; fi)"

# Determine version: Extract version from tag robustly (dots, underscores, or dashes)
if [ -n "$TAG" ]; then
    if [[ "$TAG" =~ ([0-9]+([._-][0-9]+)+) ]]; then
        VERSION="${BASH_REMATCH[1]}"
        VERSION="${VERSION//[_-]/.}"  # normalize separators to dots
    else
        VERSION="$TAG"
    fi
else
    VERSION="$BRANCH"
fi

iecho "Version: $(bold_bright_cyan "$VERSION")"
iecho "SHA256 checksum: $(bold_bright_cyan "$CHECKSUM")"
iecho "Detected build system: $(bold_bright_cyan "$BUILD_SYSTEM")"

# =============================================
# Optional: generate MXE .mk file
# =============================================
if [[ "$GENERATE_MXE" == true ]]; then
    bash "$ROOT_DIR/contrib/mxe/scripts/generate_mxe_mk.sh" \
        --mxe_args "$MXE_ARGS" \
        --owner_repo "$OWNER_REPO" \
        --archive "$ARCHIVE_FILE" \
        --pkg "$PACKAGE_NAME" \
        --tag "$TAG" \
        --version "$VERSION" \
        --archive_url "$ARCHIVE_URL" \
        --checksum "$CHECKSUM" \
        --description "$DESCRIPTION" \
        --website "$GIT_URL" \
        $( [[ "$DEBUG" == true ]] && echo --debug )
fi
