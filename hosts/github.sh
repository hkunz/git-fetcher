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

    # ---------------------------------------
    # 1. Try latest GitHub release
    # ---------------------------------------
    decho "Checking latest release..."
    tag=$(curl -s "$api/releases/latest" | jq -r '.tag_name // empty')
    decho "Release tag: '$tag'"

    # ---------------------------------------
    # 2. Fallback to tags
    # ---------------------------------------
    if [[ -z "$tag" || "$tag" == "null" ]]; then
        decho "No releases found, checking tags..."

        tag=$(
            curl -s "$api/tags?per_page=100" \
            | jq -r '.[].name' \
            | grep -E '[0-9]' \
            | sort -V \
            | tail -n1
        )
        decho "Latest sorted tag: '$tag'"
    fi

    TAG="$tag"
    urls=()

    if [[ -n "$tag" ]]; then
        # Try GitHub release asset first
        release_url=$(curl -s "$api/releases/tags/$tag" | jq -r '.assets[0].browser_download_url // empty')
        [[ -n "$release_url" ]] && urls+=("$release_url")

        # Fallback to tag archive
        urls+=("https://github.com/$owner_repo/archive/refs/tags/$tag.tar.gz")
    else
        wecho "Warning: no releases or tags found for $owner_repo — falling back to default branch"
        branch=$(curl -s "$api" | jq -r '.default_branch // "main"')
        urls+=("https://github.com/$owner_repo/archive/refs/heads/$branch.tar.gz")
    fi

    # Pick the first URL that actually exists
    for u in "${urls[@]}"; do
        if [[ -n "$u" ]] && curl --head --silent --fail "$u" >/dev/null; then
            ARCHIVE_URL="$u"
            [[ "$u" == *"/heads/"* ]] && TAG="" && BRANCH="$branch"
            break
        fi
    done

    DESCRIPTION=$(curl -s "$api" | jq -r '.description // ""')

    decho "TAG set to: $TAG"
    decho "ARCHIVE_URL set to: $ARCHIVE_URL"
    decho "DESCRIPTION  = '$DESCRIPTION'"
    decho "BRANCH       = '$BRANCH'"
    decho "ARCHIVE_URL  = '$ARCHIVE_URL'"
    decho "DESCRIPTION  = '$DESCRIPTION'"
}
