#!/usr/bin/env bash
# hosts/gitlab.sh
# Example: https://gitlab.com/gitlab-org/gitlab-runner

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

detect_host() {
    detect_host_generic "$1" "gitlab.com"
    return $?
}

resolve_archive() {
    local owner_repo="$1"
    local encoded=$(encode_repo_path_for_api "$owner_repo")
    local api="https://gitlab.com/api/v4/projects/$encoded"
    check_repo_access "$api" "$owner_repo" || return 1

    local final_ref=$(get_latest_release_tag "$api")

    if [[ -z "$final_ref" ]]; then
        iecho "No release tag found for $owner_repo"
        readarray -t curl_args < <(curl_header "$HOST")
        local raw_tags=$(curl -s "${curl_args[@]}" "$api/repository/tags?per_page=100" | jq -r '.[].name // empty')
        local filtered_tags=$(echo "$raw_tags" | grep -v -E '^(main|master)$')
        local default_branch=$(curl -s "${curl_args[@]}" "$api" | jq -r '.default_branch // "main"')
        local proposed_latest=$(get_latest_tag_or_branch "$filtered_tags" "$default_branch" | tr -d '\r\n')

        resolve_latest_tag_or_branch "$proposed_latest" "$default_branch"
        final_ref="${TAG:-$BRANCH}"
    else
        iecho "Release tag '$final_ref' found for $owner_repo"
        TAG="$final_ref"
    fi

    set_archive_info "$owner_repo" "$final_ref" "$api"
}

resolve_specific_ref() {
    resolve_specific_ref_generic gitlab "$1" "$2" "https://gitlab.com/%s/-/archive/%s/$(basename "$1")-%s.tar.gz"
}

get_latest_release_tag() {
    local api="$1"
    readarray -t curl_args < <(curl_header "$HOST")
    # Query the latest release from GitLab Releases API (sorted by release date descending)
    local latest_tag=$(curl -s "${curl_args[@]}" "$api/releases?per_page=1&order_by=released_at&sort=desc" | jq -r '.[0].tag_name // empty')
    echo "$latest_tag"
}
