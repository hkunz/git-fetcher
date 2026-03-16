#!/usr/bin/env bash
# hosts/bitbucket.sh
# Example: https://bitbucket.org/atlassian/amps https://bitbucket.org/atlassian/aui/

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

detect_host() {
    detect_host_generic "$1" "bitbucket.org"
}

resolve_archive() {
    local owner_repo="$1"
    vecho "Checking repository: $owner_repo"

    local owner="${owner_repo%%/*}"
    local repo="${owner_repo##*/}"
    local api="https://api.bitbucket.org/2.0/repositories/$owner/$repo"

    check_repo_access "$api" || return 1
    iecho "Repository is reachable."

    # Fetch all tags (handle pagination)
    local page=1 tags all_tags
    while :; do
        local tags_json
        tags_json=$(curl -s "$(curl_headers "$api")" "$api/refs/tags?pagelen=100&page=$page")
        local page_tags
        page_tags=$(echo "$tags_json" | jq -r '.values[].name // empty')
        all_tags+="$page_tags"$'\n'

        # Exit if no next page
        if [[ "$(echo "$tags_json" | jq -r '.next // empty')" == "" ]]; then
            break
        fi
        ((page++))
    done

    vecho "Fetched tags:"
    decho "$all_tags"

    # Get latest tag or fallback
    local latest
    latest=$(get_latest_tag_or_branch "$all_tags" "")

    if [[ -n "$latest" ]]; then
        TAG="$latest"
        BRANCH=""
    else
        TAG=""
        # fallback to mainbranch
        BRANCH=$(curl -s "$(curl_headers "$api")" "$api" | jq -r '.mainbranch.name // empty')
        wecho "No tags found — using branch '$BRANCH'"
        latest="$BRANCH"
    fi

    ARCHIVE_URL=$(construct_archive_url "$HOST" "$owner_repo" "$latest")
    set_archive_info "$owner_repo" "$latest"

    DESCRIPTION=$(curl -s "$(curl_headers "$api")" "$api" | jq -r '.description // ""')

    decho "TAG          = '$TAG'"
    decho "BRANCH       = '$BRANCH'"
    decho "ARCHIVE_URL  = '$ARCHIVE_URL'"
    decho "ARCHIVE_FILE = '$ARCHIVE_FILE'"
    decho "DESCRIPTION  = '$DESCRIPTION'"
}
