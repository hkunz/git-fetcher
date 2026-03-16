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

resolve_archive() {
    local repo_url="$1"
    repo_url="${repo_url%/}"  # strip trailing slash

    vecho "Fetching tags from GoogleSource repository: $repo_url"

    # Fetch all tags
    local raw_tags tags
    raw_tags=$(git ls-remote --tags "$repo_url" 2>/dev/null | awk '{print $2}')
    decho "Raw tags from ls-remote:"
    decho "$raw_tags"

    # Strip annotated tags and remove 'refs/tags/' prefix
    tags=$(echo "$raw_tags" | grep -v '{}' | sed 's#refs/tags/##')
    decho "Filtered tags:"
    decho "$tags"

    # Determine latest tag or default branch
    local default_branch
    default_branch=$(git ls-remote --symref "$repo_url" HEAD 2>/dev/null \
        | awk '/ref:/ {print $2}' \
        | sed 's#refs/heads/##')
    decho "Default branch: $default_branch"

    VERSION=$(get_latest_tag_or_branch "$tags" "$default_branch")
    if [[ "$VERSION" == "$default_branch" ]]; then
        TAG=""
        BRANCH="$default_branch"
        iecho "No tags found — using default branch: $BRANCH"
    else
        TAG="$VERSION"
        BRANCH=""
        iecho "Using latest tag: $TAG"
    fi

    ARCHIVE_URL=$(construct_archive_url "$HOST" "$repo_url" "$VERSION")
    set_archive_info "$repo_url" "$VERSION"

    DESCRIPTION="GoogleSource doesn’t provide a description via HTTP API"

    iecho
    iecho "Note: Googlesource generates tarballs dynamically."
    iecho "SHA256 checksum may differ between downloads even if the code is unchanged."
    iecho

    decho "TAG          = '$TAG'"
    decho "BRANCH       = '$BRANCH'"
    decho "ARCHIVE_URL  = '$ARCHIVE_URL'"
    decho "ARCHIVE_FILE = '$ARCHIVE_FILE'"
    decho "DESCRIPTION  = '$DESCRIPTION'"
}

resolve_specific_ref() {
    local owner_repo="$1"
    local ref_name="$2"

    eecho "Error: --ref is only supported for GitHub at the moment (host='$HOST')"
    return 1
}
