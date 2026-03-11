#!/usr/bin/env bash
# hosts/gitlab.sh
# Example:  https://gitlab.com/simnavi/shapespyer

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

    # URL-encode the repo path for GitLab API
    vecho "Encoding repo path for API: $owner_repo"
    local encoded_repo
    encoded_repo=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$owner_repo''', safe=''))")
    decho "Encoded repo: $encoded_repo"

    local api="https://gitlab.com/api/v4/projects/$encoded_repo"
    vecho "GitLab API URL: $api"

    # Check that the repo exists
    vecho "Checking HTTP status for repo..."
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "$api")
    if [ "$status" -ne 200 ]; then
        eecho "Cannot access $owner_repo on GitLab (HTTP $status)"
        exit 1
    fi
    iecho "Repository is reachable."

    # Get latest tag
    vecho "Fetching tags from GitLab API..."
    local tag
    tag=$(curl -s "$api/repository/tags" | jq -r '.[0].name // empty')
    decho "Raw tag response: $tag"

    if [ -n "$tag" ]; then
        VERSION="$tag"
        ARCHIVE_URL="https://gitlab.com/$owner_repo/-/archive/$tag/$(basename "$owner_repo")-$tag.tar.gz"
        iecho "Latest tag: $VERSION"
    else
        # Fallback: default branch
        vecho "No tags found, fetching default branch..."
        VERSION=$(curl -s "$api" | jq -r '.default_branch')
        ARCHIVE_URL="https://gitlab.com/$owner_repo/-/archive/$VERSION/$(basename "$owner_repo")-$VERSION.tar.gz"
        iecho "No tags found. Using default branch: $VERSION"
    fi

    ARCHIVE_FILE="$(basename "$owner_repo")-$VERSION.tar.gz"
    decho "[DEBUG] Archive file: $ARCHIVE_FILE"
    decho "[DEBUG] Archive URL: $ARCHIVE_URL"
}
