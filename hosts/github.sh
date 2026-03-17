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
    check_repo_access "$api" "$owner_repo" || return 1

    readarray -t curl_args < <(curl_header "$HOST")
    local raw_tags=$(curl -s "${curl_args[@]}" "$api/tags?per_page=100" | jq -r '.[].name // empty')
    local filtered_tags=$(echo "$raw_tags" | grep -v -E '^(main|master)$')
    local default_branch=$(curl -s "${curl_args[@]}" "$api" | jq -r '.default_branch // "main"')
    local proposed_latest=$(get_latest_tag_or_branch "$filtered_tags" "$default_branch" | tr -d '\r\n')

    resolve_latest_tag_or_branch "$proposed_latest" "$default_branch"
    final_ref="${TAG:-$BRANCH}"

    set_archive_info "$owner_repo" "$final_ref" "$api"
    summarize_archive
}

resolve_specific_ref() {
    local owner_repo="$1"
    local ref_name="$2"

    local git_url="https://github.com/$owner_repo.git"
    DESCRIPTION="Custom ref ${ref_name:0:7} (no upstream description)"

    vecho "Resolving specific ref: $ref_name"
    # Branch
    if git ls-remote --heads "$git_url" "$ref_name" | grep -q "$ref_name"; then
        BRANCH="$ref_name"
        TAG=""
        REF_NAME=""
        ARCHIVE_URL="https://github.com/$owner_repo/archive/refs/heads/$BRANCH.tar.gz"
        return 0
    fi

    # Tag
    if git ls-remote --tags "$git_url" "$ref_name" | grep -q "$ref_name"; then
        TAG="$ref_name"
        BRANCH=""
        REF_NAME=""
        ARCHIVE_URL="https://github.com/$owner_repo/archive/refs/tags/$TAG.tar.gz"
        return 0
    fi

    # Commit hash
    if [[ "$ref_name" =~ ^[0-9a-f]{7,40}$ ]]; then
        commit_url="https://github.com/$owner_repo/commit/$ref_name"
        if ! check_commit_exists "$commit_url"; then
            eecho "The commit '$ref_name' does not exist in $owner_repo"
            return 1
        fi
        TAG=""
        BRANCH=""
        REF_NAME="$ref_name"
        ARCHIVE_URL="https://github.com/$owner_repo/archive/$ref_name.tar.gz"
        return 0
    fi
    eecho "The ref '$ref_name' not found in $owner_repo"
    return 1
}
