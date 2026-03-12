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

    vecho "Checking repository: $owner_repo"
    decho "API URL: https://api.github.com/repos/$owner_repo"
    check_http "https://api.github.com/repos/$owner_repo"
    vecho "Repository is reachable."
    decho "Fetching tags from GitHub API..."
    local tag
    tag=$(curl -s "https://api.github.com/repos/$owner_repo/tags" | jq -r '.[0].name // empty')
    decho "Raw latest tag from API: '$tag'"

    if [ -n "$tag" ]; then
        TAG="$tag"
        ARCHIVE_URL="https://github.com/$owner_repo/archive/refs/tags/$tag.tar.gz"
        iecho "Latest tag: $tag"
        vecho "Constructed archive URL: $ARCHIVE_URL"
    else
        decho "No tags found, fetching default branch..."
        local branch
        branch=$(curl -s "https://api.github.com/repos/$owner_repo" | jq -r '.default_branch')
        BRANCH="$branch"                     # ← STORE IN BRANCH, NOT TAG
        ARCHIVE_URL="https://github.com/$owner_repo/archive/refs/heads/$branch.tar.gz"
        TAG=""                               # ← CLEAR TAG
        iecho "$(bright_red "No tags found")."
        iecho "Using default branch: $(bold_bright_cyan "$branch")"
        vecho "Constructed archive URL for branch: $ARCHIVE_URL"
    fi

    decho "TAG set to: $TAG"
    decho "ARCHIVE_URL set to: $ARCHIVE_URL"
}
