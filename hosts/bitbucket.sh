#!/usr/bin/env bash
# hosts/bitbucket.sh — fetch latest tag or default branch from Bitbucket

fetch_latest_bitbucket() {
    local owner_repo="$1"  # e.g., "atlassian/python-bitbucket"

    vecho "Checking repository: $owner_repo"

    # Split owner and repo
    local owner repo
    owner="${owner_repo%%/*}"
    repo="${owner_repo##*/}"

    local api="https://api.bitbucket.org/2.0/repositories/$owner/$repo"

    # Ensure repository exists
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "$api")
    if [ "$status" -ne 200 ]; then
        iecho "Error: Cannot access $owner_repo on Bitbucket (HTTP $status)"
        exit 1
    fi
    vecho "Repository is reachable (HTTP $status)"

    # Try to get latest tag
    decho "Fetching tags from Bitbucket API..."
    local tag
    tag=$(curl -s "$api/refs/tags?pagelen=1&sort=-target.date" | jq -r '.values[0].name // empty')
    decho "Raw latest tag from API: '$tag'"

    if [ -n "$tag" ]; then
        VERSION="$tag"
        ARCHIVE_URL="https://bitbucket.org/$owner_repo/get/$tag.tar.gz"
        echo "Latest tag: $VERSION"
        vecho "Constructed archive URL: $ARCHIVE_URL"
    else
        # Fallback: default branch
        local branch
        branch=$(curl -s "$api" | jq -r '.mainbranch.name // empty')
        VERSION="$branch"
        ARCHIVE_URL="https://bitbucket.org/$owner_repo/get/$branch.tar.gz"
        echo "No tags found. Using default branch: $VERSION"
        vecho "Constructed archive URL for branch: $ARCHIVE_URL"
    fi

    ARCHIVE_FILE="$(basename "$repo")-$VERSION.tar.gz"
    decho "[DEBUG] Archive file will be: $ARCHIVE_FILE"
}
