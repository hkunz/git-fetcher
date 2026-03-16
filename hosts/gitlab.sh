#!/usr/bin/env bash
# hosts/gitlab.sh
# Example: https://gitlab.com/gitlab-org/gitlab-runner

detect_host() {
    local url="$1"
    if [[ "$url" =~ gitlab\.com/ ]]; then
        HOST="gitlab"
        OWNER_REPO="${url#*gitlab.com/}"
        GIT_URL="https://gitlab.com/$OWNER_REPO.git"
        return 0
    fi
    return 1  # not a GitLab URL
}

fetch_latest_gitlab() {
    local owner_repo="$1"

    vecho "Encoding repo path for API: $owner_repo"
    local encoded_repo
    encoded_repo=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$owner_repo''', safe=''))")
    decho "Encoded repo: $encoded_repo"

    local api="https://gitlab.com/api/v4/projects/$encoded_repo"
    vecho "GitLab API URL: $api"

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "$api")
    if [ "$status" -ne 200 ]; then
        eecho "Cannot access $owner_repo on GitLab (HTTP $status)"
        exit 1
    fi
    iecho "Repository is reachable."
    decho "Fetching all tags..."

    local tags
    tags=$(curl -s "$api/repository/tags?per_page=100" | jq -r '.[].name')
    decho "Raw tags: $tags"

    local tag=""
    if [[ -n "$tags" ]]; then
        tag=$(echo "$tags" | grep -E '[0-9]' | sort -V | tail -n1)
        decho "Latest sorted tag: '$tag'"
    else
        decho "No tags returned by API"
    fi

    if [[ -n "$tag" ]]; then
        TAG="$tag"
        BRANCH=""
        ARCHIVE_URL="https://gitlab.com/$owner_repo/-/archive/$tag/$(basename "$owner_repo")-$tag.tar.gz"
    else
        decho "No valid tags found, using default branch..."
        TAG=""
        BRANCH=$(curl -s "$api" | jq -r '.default_branch // "main"')
        ARCHIVE_URL="https://gitlab.com/$owner_repo/-/archive/$BRANCH/$(basename "$owner_repo")-$BRANCH.tar.gz"
        wecho "Warning: no tags found — using branch '$BRANCH'"
    fi

    ARCHIVE_FILE="$(basename "$owner_repo")-${TAG:-$BRANCH}.tar.gz"
    DESCRIPTION=$(curl -s "$api" | jq -r '.description // ""')

    iecho "TAG          = '${TAG}'"
    iecho "BRANCH       = '${BRANCH}'"
    iecho "ARCHIVE_FILE = '$ARCHIVE_FILE'"
    iecho "ARCHIVE_URL  = '$ARCHIVE_URL'"
    iecho "DESCRIPTION  = '$DESCRIPTION'"
}
