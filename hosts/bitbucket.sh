#!/usr/bin/env bash
# hosts/bitbucket.sh
# Example: https://bitbucket.org/fargo3d/public

detect_host() {
    local url="$1"
    if [[ "$url" =~ bitbucket\.org/ ]]; then
        HOST="bitbucket"
        OWNER_REPO="${url#*bitbucket.org/}"
        GIT_URL="https://bitbucket.org/$OWNER_REPO.git"
        return 0
    fi
    return 1
}

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
        TAG="$tag"
        BRANCH=""   # clear branch
        ARCHIVE_URL="https://bitbucket.org/$owner_repo/get/$tag.tar.gz"
        iecho "Latest tag: $TAG"
        vecho "Constructed archive URL: $ARCHIVE_URL"
    else
        TAG=""      # no tags
        BRANCH=$(curl -s "$api" | jq -r '.mainbranch.name // empty')
        ARCHIVE_URL="https://bitbucket.org/$owner_repo/get/$BRANCH.tar.gz"
        iecho "No tags found. Using default branch: $BRANCH"
        vecho "Constructed archive URL for branch: $ARCHIVE_URL"
    fi

    ARCHIVE_FILE="$(basename "$repo")-${TAG:-$BRANCH}.tar.gz"
    decho "[DEBUG] TAG          = '$TAG'"
    decho "[DEBUG] BRANCH       = '$BRANCH'"
    decho "[DEBUG] ARCHIVE_FILE = '$ARCHIVE_FILE'"
    decho "[DEBUG] ARCHIVE_URL  = '$ARCHIVE_URL'"
}
