#!/usr/bin/env bash

fetch_latest_github() {
    local owner_repo="$1"
    check_http "https://api.github.com/repos/$owner_repo"
    local tag
    tag=$(curl -s "https://api.github.com/repos/$owner_repo/tags" | jq -r '.[0].name // empty')
    if [ -n "$tag" ]; then
        VERSION="$tag"
        ARCHIVE_URL="https://github.com/$owner_repo/archive/refs/tags/$tag.tar.gz"
        echo "Latest tag: $tag"
    else
        local branch
        branch=$(curl -s "https://api.github.com/repos/$owner_repo" | jq -r '.default_branch')
        VERSION="$branch"
        ARCHIVE_URL="https://github.com/$owner_repo/archive/refs/heads/$branch.tar.gz"
        echo "No tags found. Using default branch: $branch"
    fi
}
