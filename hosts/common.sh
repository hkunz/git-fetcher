#!/usr/bin/env bash
# hosts/common.sh
# Shared helpers for GitHub, GitLab, Bitbucket, GoogleSource


curl_header() {
    local host="$1"
    local -a headers=()
    if [[ "$host" == "github" ]]; then
        if [[ -z "${GITHUB_TOKEN:-}" ]]; then
            wecho "GITHUB_TOKEN is not set; requests will be unauthenticated and may be rate-limited" >&2
            return 0
        fi
        vecho "Making authenticated request to $host API using token; requests will avoid rate limits and have full API access" >&2
        headers+=("-H" "Authorization: Bearer $GITHUB_TOKEN")
        headers+=("-H" "X-GitHub-Api-Version: 2026-03-10")

    elif [[ "$host" == "gitlab" ]]; then
        if [[ -z "${GITLAB_TOKEN:-}" ]]; then
            wecho "GITLAB_TOKEN is not set; requests may be rate-limited" >&2
            return 0
        fi
        headers+=("-H" "PRIVATE-TOKEN: $GITLAB_TOKEN")
    fi
    vecho "No token provided; sending unauthenticated request to $host API. Rate limits may apply." >&2
    printf '%s\n' "${headers[@]}"
}

# ==============================
# HTTP check
# ==============================
check_repo_access() {
    local url="$1"
    local owner_repo="$2"
    vecho "Checking repository: $owner_repo (API: $url)"
    readarray -t curl_args < <(curl_header "$HOST")

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "${curl_args[@]}" "$url")

    if [[ "$status" -ne 200 ]]; then
        eecho "Cannot access $url (HTTP $status)"
        return 1
    fi
    iecho "Repository is reachable."
    return 0
}

# ==============================
# Host mapping
# ==============================
declare -A HOST_MAP=(
    [github]="github.com"
    [gitlab]="gitlab.com"
    [bitbucket]="bitbucket.org"
    [googlesource]="googlesource.com"
)

get_known_hosts() {
    echo "${!HOST_MAP[@]}"
}

get_known_domains() {
    for domain in "${HOST_MAP[@]}"; do
        echo "$domain"
    done
}

# ==============================
# Generic host detection helper
# ==============================
detect_host_generic() {
    local url="$1"
    local domain="$2"   # e.g., github.com

    if [[ "$url" =~ $domain ]]; then
        # Extract host name from domain: 'github.com' -> 'github'
        HOST="${domain%%.*}"  

        OWNER_REPO="${url#*${domain}/}"  # strip domain prefix
        OWNER_REPO="${OWNER_REPO%.git}"  # remove trailing .git if present
        OWNER_REPO="${OWNER_REPO%/}"     # remove trailing slash if present

        # Construct default Git URL if needed
        case "$HOST" in
            github)       GIT_URL="https://github.com/$OWNER_REPO.git" ;;
            gitlab)       GIT_URL="https://gitlab.com/$OWNER_REPO.git" ;;
            bitbucket)    GIT_URL="https://bitbucket.org/$OWNER_REPO.git" ;;
            googlesource) GIT_URL="$url" ;;  # already full URL
        esac
        return 0
    fi
    return 1
}

# ==============================
# Get latest tag or branch
# ==============================
get_latest_tag_or_branch() {
    local tags="$1"  # newline-separated list
    local tag

    if [[ -n "$tags" ]]; then
        tag=$(echo "$tags" \
            | tr -d '\r' \
            | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
            | grep -E '^[vV]?[0-9]+(\.[0-9]+)*$' \
            | sort -V \
            | tail -n1)
    fi

    echo "$tag"
}

# ==============================
# Construct archive URL
# ==============================
construct_archive_url() {
    local host="$1"
    local owner_repo="$2"
    local version="$3"
    local type="${4:-tags}" # "tags" or "heads"

    case "$host" in
        github)
            echo "https://github.com/$owner_repo/archive/refs/$type/$version.tar.gz"
            ;;
        gitlab)
            echo "https://gitlab.com/$owner_repo/-/archive/$version/$(basename "$owner_repo")-$version.tar.gz"
            ;;
        bitbucket)
            echo "https://bitbucket.org/$owner_repo/get/$version.tar.gz"
            ;;
        googlesource)
            echo "https://$owner_repo/+archive/$version.tar.gz"
            ;;
        *)
            eecho "Unknown host: $host"
            return 1
            ;;
    esac
}

# ==============================
# Set archive info
# ==============================
set_archive_info() {
    local repo="$1"
    local ref="$2"
    local api="$3"

    decho "Final ref chosen: '$ref' (TAG='$TAG', BRANCH='$BRANCH')"
    if [[ -n "$TAG" ]]; then
        ARCHIVE_URL=$(construct_archive_url "$HOST" "$repo" "$TAG" "tags")
    else
        ARCHIVE_URL=$(construct_archive_url "$HOST" "$repo" "$BRANCH" "heads")
    fi
    readarray -t curl_args < <(curl_header "$HOST")
    ARCHIVE_FILE="$(basename "$repo")-${ref}.tar.gz"
    DESCRIPTION=$(curl -s "${curl_args[@]}" "$api" | jq -r '.description // empty')
    DESCRIPTION="${DESCRIPTION:-Custom ref ${safe_ref} (no upstream description)}"
}

# ==============================
# Validate if commit exists
# ==============================
check_commit_exists() {
    local url="$1"
    readarray -t curl_args < <(curl_header "$HOST")
    local code=$(curl -s -o /dev/null -w "%{http_code}" "${curl_args[@]}" -L -I "$url")
    [[ "$code" =~ ^2 ]] && return 0 || return 1
}

# ==============================
# Encode a repository path for use in an HTTP API URL
# ==============================
encode_repo_path_for_api() {
    local repo_path="$1"
    decho "Encoding repository path for API: $repo_path" >&2
    local encoded
    encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$repo_path''', safe=''))")
    decho "Encoded repository path: $encoded" >&2
    echo "$encoded"
}

# Decide whether to use the latest tag or fallback branch
resolve_latest_tag_or_branch() {
    local proposed_latest="$1"
    local default_branch="$2"
    vecho "Proposed latest tag: '$proposed_latest'"

    if [[ -n "$proposed_latest" ]]; then
        TAG="$proposed_latest"
        BRANCH=""
        iecho "Using latest tag '$TAG' for archive download"
    else
        TAG=""
        BRANCH="$default_branch"
        wecho "No tags found; falling back to default branch '$BRANCH' for archive download"
    fi
}

summarize_archive() {
    decho "TAG          = '${TAG}'"
    decho "BRANCH       = '${BRANCH}'"
    decho "ARCHIVE_URL  = '${ARCHIVE_URL}'"
    decho "ARCHIVE_FILE = '${ARCHIVE_FILE}'"
    decho "DESCRIPTION  = '${DESCRIPTION}'"
}
