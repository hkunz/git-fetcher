#!/usr/bin/env bash
# hosts/googlesource.sh
# Example: https://aomedia.googlesource.com/aom/ https://go.googlesource.com/scratch

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

detect_host() {
    detect_host_googlesource "$1"
}

resolve_archive() {
    local repo_url="$1"
    repo_url="${repo_url%/}"

    vecho "Fetching repository info from GoogleSource: $repo_url"
    vecho "Fetching tags via git ls-remote..."

    local raw_tags tags
    raw_tags=$(git ls-remote --tags "$repo_url" 2>/dev/null | awk '{print $2}')
    decho "Raw tags:"
    decho "$raw_tags"

    tags=$(echo "$raw_tags" | grep -v '{}' | sed 's#refs/tags/##')
    decho "Filtered tags:"
    decho "$tags"

    local default_branch
    default_branch=$(git ls-remote --symref "$repo_url" HEAD 2>/dev/null | awk '/ref:/ {print $2}' | sed 's#refs/heads/##')
    default_branch="${default_branch:-main}"
    decho "Default branch: $default_branch"

    local proposed_latest
    proposed_latest=$(get_latest_tag_or_branch "$tags" "$default_branch")

    if [[ -n "$tags" && "$proposed_latest" != "$default_branch" ]]; then
        TAG="$proposed_latest"
        BRANCH=""
        iecho "Using latest tag: $TAG"
    else
        TAG=""
        BRANCH="$default_branch"
        wecho "No tags found — using branch '$BRANCH'"
    fi

    local latest="${TAG:-$BRANCH}"
    local repo_path="${repo_url#https://}"
    repo_path="${repo_path#http://}"

    ARCHIVE_URL=$(construct_archive_url "$HOST" "$repo_path" "$latest")
    set_archive_info "$repo_path" "$latest" ""
    DESCRIPTION="GoogleSource doesn’t provide a description via HTTP API"

    iecho
    iecho "Note: GoogleSource generates tarballs dynamically."
    iecho "SHA256 checksum may differ between downloads even if the code is unchanged."
    iecho

    summarize_archive
}

resolve_specific_ref() {
    local owner_repo="$1"
    local ref_name="$2"

    eecho "Error: --ref is only supported for GitHub at the moment (host='$HOST')"
    return 1
}

detect_host_googlesource() {
    local url="$1"
    if [[ "$url" =~ googlesource\.com/ ]]; then
        HOST="googlesource"
        OWNER_REPO="${url%/}"  # strip trailing slash
        GIT_URL="$OWNER_REPO"
        return 0
    fi
    return 1  # not a Googlesource URL
}
