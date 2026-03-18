#!/usr/bin/env bash
# hosts/bitbucket.sh
# Example: https://bitbucket.org/atlassian/amps https://bitbucket.org/atlassian/aui/

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

detect_host() {
    detect_host_generic "$1" "bitbucket.org"
}

resolve_archive() {
    local owner_repo="$1"
    local owner="${owner_repo%%/*}"
    local repo="${owner_repo##*/}"
    local api="https://api.bitbucket.org/2.0/repositories/$owner/$repo"
    check_repo_access "$api" "$owner_repo" || return 1

    readarray -t curl_args < <(curl_header "$HOST")
    local page=1 all_tags=""
    while :; do
        local tags_json=$(curl -s "${curl_args[@]}" "$api/refs/tags?pagelen=100&page=$page")
        local page_tags=$(echo "$tags_json" | jq -r '.values[].name // empty')
        all_tags+="$page_tags"$'\n'
        [[ -z "$(echo "$tags_json" | jq -r '.next // empty')" ]] && break
        ((page++))
    done

    local default_branch=$(curl -s "${curl_args[@]}" "$api" | jq -r '.mainbranch.name // "master"')
    local proposed_latest=$(get_latest_tag_or_branch "$all_tags" "$default_branch" | tr -d '\r\n')

    resolve_latest_tag_or_branch "$proposed_latest" "$default_branch"
    local final_ref="${TAG:-$BRANCH}"

    set_archive_info "$owner_repo" "$final_ref" "$api"
    summarize_archive
}

resolve_specific_ref() {
    local owner_repo="$1"
    local ref_name="$2"

    eecho "Error: --ref is only supported for GitHub at the moment (host='$HOST')"
    return 1
}
