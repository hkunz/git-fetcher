#!/usr/bin/env bash
# hosts/github.sh
# Example: https://github.com/google/farmhash

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

detect_host() {
    detect_host_generic "$1" "github.com"
}

resolve_archive() {
    local owner_repo="$1"
    local api="https://api.github.com/repos/$owner_repo"

    vecho "Checking repository: $owner_repo"
    check_repo_access "$api" || return 1
    iecho "Repository is reachable."

    # Try latest release first
    local tag
    # We skip GitHub releases to avoid downloading possible binaries; only tags are used
    # tag=$(curl -s "$(curl_headers "$api")" "$api/releases/latest" | jq -r '.tag_name // empty')
    # decho "Release tag: '$tag'"

    # Fallback to latest tag
    if [[ -z "$tag" || "$tag" == "null" ]]; then
        vecho "Checking tags..."  # vecho "No releases found, checking tags..."
        local tags
        tags=$(curl -s "$(curl_headers "$api")" "$api/tags?per_page=100" | jq -r '.[].name')
        if [[ -n "$tags" ]]; then
            tag=$(get_latest_tag_or_branch "$tags" "main")
            decho "Latest tag (sorted) = '$tag'"
        else
            vecho "No tags found, falling back to default branch"
            tag=""
        fi
    fi

    # Determine branch or tag
    local branch=""
    if [[ -z "$tag" ]]; then
        branch=$(curl -s "$api" | jq -r '.default_branch // "main"')
        ARCHIVE_URL="https://github.com/$owner_repo/archive/refs/heads/$branch.tar.gz"
        TAG=""
        BRANCH="$branch"
    else
        ARCHIVE_URL="https://github.com/$owner_repo/archive/refs/tags/$tag.tar.gz"
        TAG="$tag"
        BRANCH=""
    fi

    set_archive_info "$owner_repo" "${TAG:-$BRANCH}"

    DESCRIPTION=$(curl -s "$(curl_headers "$api")" "$api" | jq -r '.description // ""')

    decho "TAG          = '$TAG'"
    decho "BRANCH       = '$BRANCH'"
    decho "ARCHIVE_URL  = '$ARCHIVE_URL'"
    decho "ARCHIVE_FILE = '$ARCHIVE_FILE'"
    decho "DESCRIPTION  = '$DESCRIPTION'"
}
