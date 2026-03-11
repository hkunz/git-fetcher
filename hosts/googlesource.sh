#!/usr/bin/env bash
# hosts/googlesource.sh
# Example: https://aomedia.googlesource.com/aom/

detect_host() {
    local url="$1"
    if [[ "$url" =~ googlesource\.com/ ]]; then
        HOST="googlesource"
        OWNER_REPO="${url%/}"  # strip trailing slash
        GIT_URL="$OWNER_REPO"
        return 0
    fi
    return 1  # not a Googlesource URL
}

fetch_latest_googlesource() {
    local repo_url="$1"
    repo_url="${repo_url%/}"   # strip trailing slash

    vecho "Fetching tags from GoogleSource repository: $repo_url"

    # --- Determine latest version ---
    local raw_tags
    raw_tags=$(git ls-remote --tags "$repo_url" 2>/dev/null | awk '{print $2}')
    decho "Raw tags from ls-remote:"
    decho "$raw_tags"

    VERSION=$(echo "$raw_tags" \
        | grep -v '{}' \
        | sed 's#refs/tags/##' \
        | sort -V \
        | tail -n1)

    if [ -z "$VERSION" ]; then
        VERSION=$(git ls-remote --symref "$repo_url" HEAD 2>/dev/null \
            | awk '/ref:/ {print $2}' \
            | sed 's#refs/heads/##')
        iecho "No tags found. Using default branch: $VERSION"
    else
        iecho "Using latest tag: $VERSION"
    fi

    # --- Construct archive information ---
    local base
    base="$(basename "$repo_url")"
    ARCHIVE_URL="$repo_url/+archive/$VERSION.tar.gz"
    ARCHIVE_FILE="$base-$VERSION.tar.gz"
    decho "Constructed ARCHIVE_URL: $ARCHIVE_URL"
    decho "Archive filename will be: $ARCHIVE_FILE"

    # --- Inform user about reproducibility ---
    iecho
    iecho "Note: Googlesource generates tarballs dynamically."
    iecho "The SHA256 checksum may differ between downloads"
    iecho "even when the source code has not changed."
    iecho
}
