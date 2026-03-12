#!/usr/bin/env bash
# hosts/github.sh
# Example: https://github.com/google/farmhash

detect_host() {
    local url="$1"
    if [[ "$url" =~ github\.com/ ]]; then  # Check if it's a GitHub URL
        HOST="github"
        OWNER_REPO="${url#*github.com/}" # Remove 'https://github.com/'
        OWNER_REPO="${OWNER_REPO%.git}"  # Remove trailing .git if present
        OWNER_REPO="${OWNER_REPO%/}"     # Remove trailing slash if present
        GIT_URL="https://github.com/$OWNER_REPO.git"
        return 0
    fi
    return 1  # not a GitHub URL
}

fetch_latest_github() {
    local owner_repo="$1"

    local api="https://api.github.com/repos/$owner_repo"
    vecho "Checking repository: $owner_repo"
    decho "API URL: $api"
    check_http "$api"
    vecho "Repository is reachable."
    decho "Fetching tags from GitHub API..."
    local tag
    tag=$(curl -s "$api/tags" | jq -r '.[0].name // empty')
    decho "Raw latest tag from API: '$tag'"

    if [ -n "$tag" ]; then
        TAG="$tag"
        ARCHIVE_URL="https://github.com/$owner_repo/archive/refs/tags/$tag.tar.gz"
        vecho "Constructed archive URL: $ARCHIVE_URL"
    else
        decho "No tags found, fetching default branch..."
        BRANCH=$(curl -s "$api" | jq -r '.default_branch')
        ARCHIVE_URL="https://github.com/$owner_repo/archive/refs/heads/$BRANCH.tar.gz"
        TAG=""
        vecho "Constructed archive URL for branch: $ARCHIVE_URL"
    fi

    DESCRIPTION=$(curl -s "$api" | jq -r '.description // ""')

    decho "TAG set to: $TAG"
    decho "ARCHIVE_URL set to: $ARCHIVE_URL"
    decho "DESCRIPTION  = '$DESCRIPTION'"
    decho "BRANCH       = '$BRANCH'"
    decho "ARCHIVE_URL  = '$ARCHIVE_URL'"
    decho "DESCRIPTION  = '$DESCRIPTION'"
}
