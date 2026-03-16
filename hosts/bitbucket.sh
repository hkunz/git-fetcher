#!/usr/bin/env bash
# hosts/bitbucket.sh
# Example: https://bitbucket.org/atlassian/amps

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
    local owner_repo="$1"

    vecho "Checking repository: $owner_repo"

    local owner repo
    owner="${owner_repo%%/*}"
    repo="${owner_repo##*/}"

    local api="https://api.bitbucket.org/2.0/repositories/$owner/$repo"

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "$api")
    if [ "$status" -ne 200 ]; then
        eecho "Cannot access $owner_repo on Bitbucket (HTTP $status)"
        exit 1
    fi
    iecho "Repository is reachable (HTTP $status)"
    decho "Fetching all tags from Bitbucket API..."

    local tags_json tags tag
    tags_json=$(curl -s "$api/refs/tags?pagelen=100")   # fetch first 100 tags
    tags=$(echo "$tags_json" | jq -r '.values[].name')

    if [[ -n "$tags" ]]; then
        tag=$(echo "$tags" | sort -V | tail -n1)  # semantically latest
        decho "All tags fetched: $(echo "$tags" | tr '\n' ' ')"
        decho "Latest semantic tag: '$tag'"

        TAG="$tag"
        BRANCH=""
        ARCHIVE_URL="https://bitbucket.org/$owner_repo/get/$tag.tar.gz"
        vecho "Constructed archive URL for tag: $ARCHIVE_URL"
    else
        decho "No tags found, using main branch..."
        TAG=""
        BRANCH=$(curl -s "$api" | jq -r '.mainbranch.name // "main"')
        ARCHIVE_URL="https://bitbucket.org/$owner_repo/get/$BRANCH.tar.gz"
        wecho "No tags found for $owner_repo — using branch '$BRANCH'"
    fi

    ARCHIVE_FILE="$(basename "$repo")-${TAG:-$BRANCH}.tar.gz"
    DESCRIPTION=$(curl -s "$api" | jq -r '.description // ""')

    decho "TAG          = '$TAG'"
    decho "BRANCH       = '$BRANCH'"
    decho "ARCHIVE_FILE = '$ARCHIVE_FILE'"
    decho "ARCHIVE_URL  = '$ARCHIVE_URL'"
    decho "DESCRIPTION  = '$DESCRIPTION'"
}
