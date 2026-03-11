#!/usr/bin/env bash
# hosts/github.sh

fetch_latest_github() {
    local owner_repo="$1"

    vecho "Checking repository: $owner_repo"
    decho "API URL: https://api.github.com/repos/$owner_repo"

    # Ensure the repo is accessible
    check_http "https://api.github.com/repos/$owner_repo"
    vecho "Repository is reachable."

    # Try to get the latest tag
    decho "Fetching tags from GitHub API..."
    local tag
    tag=$(curl -s "https://api.github.com/repos/$owner_repo/tags" | jq -r '.[0].name // empty')
    decho "Raw latest tag from API: '$tag'"

    if [ -n "$tag" ]; then
        VERSION="$tag"
        ARCHIVE_URL="https://github.com/$owner_repo/archive/refs/tags/$tag.tar.gz"
        iecho "Latest tag: $tag"
        vecho "Constructed archive URL: $ARCHIVE_URL"
    else
        decho "No tags found, fetching default branch..."
        local branch
        branch=$(curl -s "https://api.github.com/repos/$owner_repo" | jq -r '.default_branch')
        VERSION="$branch"
        ARCHIVE_URL="https://github.com/$owner_repo/archive/refs/heads/$branch.tar.gz"
        iecho "No tags found. Using default branch: $branch"
        vecho "Constructed archive URL for branch: $ARCHIVE_URL"
    fi

    decho "VERSION set to: $VERSION"
    decho "ARCHIVE_URL set to: $ARCHIVE_URL"
}
