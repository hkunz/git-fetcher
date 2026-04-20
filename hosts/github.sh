#!/usr/bin/env bash
# hosts/github.sh
# Example: https://github.com/google/farmhash

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

detect_host() {
    detect_host_generic "$1" "github.com"
    return $?
}

resolve_archive() {
    local owner_repo="$1"
    local api="https://api.github.com/repos/$owner_repo"
    check_repo_access "$api" "$owner_repo" || return 1

    local final_ref=$(get_latest_release_tag "$api")

    if [[ -z "$final_ref" ]]; then
        iecho "No release tag found for $owner_repo"
        readarray -t curl_args < <(curl_header "$HOST")
        local raw_tags=$(curl -s "${curl_args[@]}" "$api/tags?per_page=100" | jq -r '.[].name // empty')
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
    resolve_specific_ref_generic github "$1" "$2" "$3" "https://github.com/%s/archive/%s.tar.gz"
}

get_latest_release_tag() {
    local api="$1"
    readarray -t curl_args < <(curl_header "$HOST")
    # Query latest release via GitHub API
    local latest_tag=$(curl -s "${curl_args[@]}" "$api/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    echo "$latest_tag"
}

get_repo_homepage() {
    local owner_repo="$1"
    local api="https://api.github.com/repos/$owner_repo"
    readarray -t curl_args < <(curl_header "$HOST")
    local homepage=$(curl -s "${curl_args[@]}" "$api" | jq -r '.homepage // empty')
    if [[ -n "$homepage" && "$homepage" != "null" ]]; then
        echo "$homepage"
        return 0
    fi
    echo ""
}
