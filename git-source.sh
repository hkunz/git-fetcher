#!/usr/bin/env bash
set -e

# -------------------------
# Argument parsing
# -------------------------
LIST_BRANCHES=false
INPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--list-branches)
            LIST_BRANCHES=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            INPUT="$1"
            shift
            ;;
    esac
done

if [ -z "$INPUT" ]; then
    echo "Usage:"
    echo "  $0 [OPTIONS] <repo_url_or_owner/repo>"
    echo
    echo "Options:"
    echo "  -b, --list-branches    List all branches of the repository"
    exit 1
fi

# -------------------------
# Normalize input
# -------------------------
REPO=$(echo "$INPUT" | sed -E 's#https?://##; s#\.git$##; s#/$##')

# -------------------------
# Supported hosts and host modules
# -------------------------
declare -A HOST_MODULES=(
    [github]="hosts/github.sh"
    [gitlab]="hosts/gitlab.sh"
    [bitbucket]="hosts/bitbucket.sh"
    [googlesource]="hosts/googlesource.sh"
)

HOST=""
OWNER_REPO=""
GIT_URL=""

# -------------------------
# Detect host and set OWNER_REPO and GIT_URL
# -------------------------
for h in "${!HOST_MODULES[@]}"; do
    case "$h" in
        github|gitlab|bitbucket)
            if [[ "$REPO" =~ $h\.com/ ]]; then
                HOST="$h"
                OWNER_REPO="${REPO#*${h}.com/}"           # for API
                GIT_URL="https://$h.com/$OWNER_REPO.git" # for git commands
                break
            fi
            ;;
        googlesource)
            if [[ "$REPO" =~ googlesource\.com/ ]]; then
                HOST="$h"
                OWNER_REPO="${INPUT%/}"      # Keep full URL for API/archive
                GIT_URL="$OWNER_REPO"        # Use same for git commands
                break
            fi
            ;;
    esac
done

if [ -z "$HOST" ]; then
    echo "Error: Unsupported host in URL '$INPUT'"
    exit 1
fi

# -------------------------
# List branches if requested
# -------------------------
if $LIST_BRANCHES; then
    echo "Branches:"
    git ls-remote --heads "$GIT_URL" | awk '{print $2}' | sed 's#refs/heads/##'
    exit 0
fi

# -------------------------
# Source helpers and host module
# -------------------------
source lib.sh
source "${HOST_MODULES[$HOST]}"

# -------------------------
# Call the host-specific fetch function
# -------------------------
FETCH_FUNC="fetch_latest_$HOST"
if ! declare -f "$FETCH_FUNC" >/dev/null; then
    echo "Error: Fetch function '$FETCH_FUNC' not found!"
    exit 1
fi

"$FETCH_FUNC" "$OWNER_REPO"

# -------------------------
# Download and compute checksum
# -------------------------
ARCHIVE_FILE="$(basename "$OWNER_REPO")-$VERSION.tar.gz"
download_archive "$ARCHIVE_URL" "$ARCHIVE_FILE"
compute_sha256 "$ARCHIVE_FILE"