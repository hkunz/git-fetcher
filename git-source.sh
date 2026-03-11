#!/usr/bin/env bash
set -e
source lib.sh

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

REPO=$(echo "$INPUT" | sed -E 's#https?://##; s#\.git$##; s#/$##')  # Normalize

# =============================================
# Supported hosts
# =============================================
declare -A HOST_MODULES=(
    [github]="hosts/github.sh"
    [gitlab]="hosts/gitlab.sh"
    [bitbucket]="hosts/bitbucket.sh"
    [googlesource]="hosts/googlesource.sh"
)

HOST=""
OWNER_REPO=""
GIT_URL=""

# =============================================
# Detect host and set OWNER_REPO / GIT_URL
# =============================================
for h in "${!HOST_MODULES[@]}"; do
    case "$h" in
        github|gitlab|bitbucket)
            if [[ "$REPO" =~ $h\.com/ ]]; then
                HOST="$h"
                OWNER_REPO="${REPO#*${h}.com/}"
                GIT_URL="https://$h.com/$OWNER_REPO.git"
                break
            fi
            ;;
        googlesource)
            if [[ "$REPO" =~ googlesource\.com/ ]]; then
                HOST="$h"
                OWNER_REPO="${INPUT%/}"
                GIT_URL="$OWNER_REPO"
                break
            fi
            ;;
    esac
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
# Source host module
# =============================================
source "${HOST_MODULES[$HOST]}"

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
# Download and checksum
# =============================================
mkdir -p downloads
ARCHIVE_FILE="downloads/$(basename "$OWNER_REPO")-$VERSION.tar.gz"
download_archive "$ARCHIVE_URL" "$ARCHIVE_FILE"
compute_sha256 "$ARCHIVE_FILE"
