#!/usr/bin/env bash
# hosts/googlesource.sh

fetch_latest_googlesource() {
    local repo_url="$1"
    repo_url="${repo_url%/}"   # strip trailing slash

    # --- Determine latest version ---
    local raw_tags
    raw_tags=$(git ls-remote --tags "$repo_url" 2>/dev/null | awk '{print $2}')

    VERSION=$(echo "$raw_tags" \
        | grep -v '{}' \
        | sed 's#refs/tags/##' \
        | sort -V \
        | tail -n1)

    if [ -z "$VERSION" ]; then
        VERSION=$(git ls-remote --symref "$repo_url" HEAD 2>/dev/null \
            | awk '/ref:/ {print $2}' \
            | sed 's#refs/heads/##')

        echo "No tags found. Using default branch: $VERSION"
    else
        echo "Using latest tag: $VERSION"
    fi

    # --- Construct archive information ---
    local base
    base="$(basename "$repo_url")"

    ARCHIVE_URL="$repo_url/+archive/$VERSION.tar.gz"
    ARCHIVE_FILE="$base-$VERSION.tar.gz"

    # --- Inform user about reproducibility ---
    echo
    echo "Note:"
    echo "Googlesource generates tarballs dynamically."
    echo "The SHA256 checksum may differ between downloads"
    echo "even when the source code has not changed."
    echo
}