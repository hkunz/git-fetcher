#!/usr/bin/env bash
# hosts/googlesource.sh
# Example: https://aomedia.googlesource.com/aom/ https://go.googlesource.com/scratch

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

detect_host() {
    detect_host_googlesource "$1"
}

resolve_archive() {
    local repo_url="${1%/}"
    local owner_repo="${repo_url#https://googlesource.com/}"
    local api="https://googlesource.com/$owner_repo"

    if git ls-remote "$repo_url" &>/dev/null; then
        handle_http_status 200 "$repo_url"
    else
        handle_http_status 404 "$repo_url"
        return 1
    fi

    local raw_tags=$(git ls-remote --tags "$repo_url" 2>/dev/null | awk '{print $2}')
    local tags=$(echo "$raw_tags" | grep -v '{}' | sed 's#refs/tags/##')
    local default_branch=$(git ls-remote --symref "$repo_url" HEAD 2>/dev/null | awk '/ref:/ {print $2}' | sed 's#refs/heads/##')

    default_branch="${default_branch:-main}"
    decho "Default branch: $default_branch"

    local proposed_latest=$(get_latest_tag_or_branch "$tags" "$default_branch")
    resolve_latest_tag_or_branch "$proposed_latest" "$default_branch"

    local final_ref="${TAG:-$BRANCH}"
    local repo_path="${repo_url#https://}"
    repo_path="${repo_path#http://}"

    ARCHIVE_URL=$(construct_archive_url "$HOST" "$repo_path" "$final_ref")
    set_archive_info "$repo_path" "$final_ref" ""
    DESCRIPTION="GoogleSource doesn’t provide a description via HTTP API"

    iecho
    iecho "Note: GoogleSource generates tarballs dynamically."
    iecho "SHA256 checksum may differ between downloads even if the code is unchanged."
    iecho

    summarize_archive
}

resolve_specific_ref() {
    resolve_specific_ref_generic googlesource "$1" "$2" "https://%s/+archive/%s.tar.gz"
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
