#!/usr/bin/env bash
# hosts/googlesource.sh
# Example: https://aomedia.googlesource.com/aom/ https://go.googlesource.com/scratch
# Example: https://storage.googleapis.com/aom-releases/libaom-3.13.3.tar.gz
# Example: https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz

set -e
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

    ARCHIVE_URL=$(construct_archive_url_googlesource "$repo_path" "$final_ref")
    # set_archive_info "$repo_path" "$final_ref" ""
    if [[ "$ARCHIVE_URL" == *"googlesource.com"* ]]; then
        echo
        wecho "Note: GoogleSource generates tarballs dynamically when downloading from googlesource.com domain"
        wecho "SHA256 checksum may differ between downloads even if the code is unchanged."
        echo
    fi
}

get_tarname() {
    local package="$1"
    local version="$2"

    curl -s "https://storage.googleapis.com/${package}-releases/" \
    | grep -oE "<Key>[^<]*${version}\.tar\.gz</Key>" \
    | grep -v '\.asc' \
    | sed -E 's#<Key>(.*)</Key>#\1#' \
    | head -n1
}

construct_archive_url() {
    construct_archive_url_googlesource "$@"
}

construct_archive_url_googlesource() {
    local repo_path="$1"
    local ref="$2"

    decho "Googlesource package name: '$PACKAGE_NAME' with ref '$ref'"

    if [[ -z "$ref" ]]; then
        eecho "Googlesource: No ref set"
        exit 1
    fi

    local tarname
    normalize_version
    tarname=$(get_tarname "$PACKAGE_NAME" "$VERSION")

    decho "Downloading tarball: $tarname"

    if [[ -n "$tarname" ]]; then
        echo "https://storage.googleapis.com/${PACKAGE_NAME}-releases/$tarname"
    else
        # Direct archive by ref (branch/tag/commit)
        echo "https://$repo_path/+archive/$ref.tar.gz"
    fi
}

resolve_specific_ref() {
    local owner_repo="$1"
    local ref_name="$2"
    owner_repo="${owner_repo#https://}"  # Remove https:// if the user passed a full URL
    resolve_specific_ref_generic googlesource "$owner_repo" "$ref_name" "https://%s/+archive/%s.tar.gz"
}

get_latest_release_tag() {
    # GoogleSource repositories do not have a "latest release" concept like GitHub or GitLab.
    # Only tags and branches exist, so use get_latest_tag_or_branch()
    # to select the most appropriate tag.
    :
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

get_repo_homepage() {
    echo ""
}
