#!/usr/bin/env bash
# hosts/googlesource.sh
# Example: https://aomedia.googlesource.com/aom/ https://go.googlesource.com/scratch

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

    # --- Get all tags ---
    local raw_tags
    raw_tags=$(git ls-remote --tags "$repo_url" 2>/dev/null | awk '{print $2}')
    decho "Raw tags from ls-remote:"
    decho "$raw_tags"

    # --- Determine latest tag ---
    local tag
    tag=$(echo "$raw_tags" \
        | grep -v '{}' \
        | sed 's#refs/tags/##' \
        | sort -V \
        | tail -n1)

    if [ -n "$tag" ]; then
        TAG="$tag"
        BRANCH=""
        VERSION="$TAG"
        iecho "Using latest tag: $TAG"
    else
        TAG=""
        BRANCH=$(git ls-remote --symref "$repo_url" HEAD 2>/dev/null \
            | awk '/ref:/ {print $2}' \
            | sed 's#refs/heads/##')
        VERSION="$BRANCH"
        iecho "No tags found. Using default branch: $BRANCH"
    fi

    # --- Construct archive info ---
    local base
    base="$(basename "$repo_url")"
    ARCHIVE_URL="$repo_url/+archive/$VERSION.tar.gz"
    ARCHIVE_FILE="$base-$VERSION.tar.gz"
    decho "ARCHIVE_URL: $ARCHIVE_URL"
    decho "ARCHIVE_FILE: $ARCHIVE_FILE"

    # GoogleSource doesn’t provide a description via HTTP API. You’d need to extract info from the README.md in the repo if you want a description.
    DESCRIPTION="No description available"  

    # --- Warning about dynamic tarballs ---
    iecho
    iecho "Note: Googlesource generates tarballs dynamically."
    iecho "SHA256 checksum may differ between downloads even if the code is unchanged."
    iecho
}
