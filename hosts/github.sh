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
    GH_MODE="tags"

    if [[ -n "$tag" ]]; then
        # Try GitHub release asset first
        release_url=$(curl -s "$api/releases/tags/$tag" | jq -r '.assets[0].browser_download_url // empty')
        if [[ -n "$release_url" ]]; then
            # urls+=("$release_url")  # don't add because releases sometimes are or contain binaries
            GH_MODE="releases"
        fi
        # Fallback to tag archive if no release asset
        urls+=("https://github.com/$owner_repo/archive/refs/tags/$tag.tar.gz")

    else
        # No tag found, fallback to default branch
        branch=$(curl -s "$api" | jq -r '.default_branch // "main"')
        urls+=("https://github.com/$owner_repo/archive/refs/heads/$branch.tar.gz")
        # GH_MODE="branches"  # tags also worked in MXE when the branch was master/main
        wecho "Warning: no releases or tags found for $owner_repo — using branch '$branch'"
    fi

    # Pick first valid URL
    for u in "${urls[@]}"; do
        if [[ -n "$u" ]] && curl --head --silent --fail "$u" >/dev/null; then
            ARCHIVE_URL="$u"
            [[ "$u" == *"/heads/"* ]] && TAG="" && BRANCH="$branch"
            break
        fi
    done

    DESCRIPTION=$(curl -s "$api" | jq -r '.description // ""')
    GH_MODE="tags"  # Always use tags; even branches like master/main are handled as tags, because releases may contain binaries instead of source

    decho "TAG set to: $TAG"
    decho "Using GitHub API mode: $GH_MODE"
    decho "ARCHIVE_URL set to: $ARCHIVE_URL"
    decho "DESCRIPTION  = '$DESCRIPTION'"
    decho "BRANCH       = '$BRANCH'"
    decho "ARCHIVE_URL  = '$ARCHIVE_URL'"
    decho "DESCRIPTION  = '$DESCRIPTION'"
}
