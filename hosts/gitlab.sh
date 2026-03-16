#!/usr/bin/env bash
# hosts/gitlab.sh
# Example: https://gitlab.com/gitlab-org/gitlab-runner

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

detect_host() {
    detect_host_generic "$1" "gitlab.com"
}

resolve_archive() {
    local owner_repo="$1"

    vecho "Encoding repo path for API: $owner_repo"
    local encoded_repo
    encoded_repo=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$owner_repo''', safe=''))")
    decho "Encoded repo: $encoded_repo"

    local api="https://gitlab.com/api/v4/projects/$encoded_repo"

    check_repo_access "$api" || return 1
    iecho "Repository is reachable."

    # Fetch tags
    local tags_json tags
    tags_json=$(curl -s "$(curl_headers "$api")" "$api/repository/tags?per_page=100")
    tags=$(echo "$tags_json" | jq -r '.[].name')
    decho "Raw tags: $tags"

    # Determine latest tag or fallback
    local tag
    tag=$(get_latest_tag_or_branch "$tags" "main")

    if [[ -n "$tag" ]]; then
        TAG="$tag"
        BRANCH=""
    else
        TAG=""
        BRANCH=$(curl -s "$(curl_headers "$api")" "$api" | jq -r '.default_branch // "main"')
        wecho "Warning: no tags found — using branch '$BRANCH'"
        tag="$BRANCH"
    fi

    ARCHIVE_URL=$(construct_archive_url "$HOST" "$owner_repo" "$tag")
    set_archive_info "$owner_repo" "$tag"

    DESCRIPTION=$(curl -s "$(curl_headers "$api")" "$api" | jq -r '.description // ""')

    decho "TAG          = '$TAG'"
    decho "BRANCH       = '$BRANCH'"
    decho "ARCHIVE_URL  = '$ARCHIVE_URL'"
    decho "ARCHIVE_FILE = '$ARCHIVE_FILE'"
    decho "DESCRIPTION  = '$DESCRIPTION'"
}
