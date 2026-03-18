#!/usr/bin/env bash
# hosts/common.sh
# Shared helpers for GitHub, GitLab, Bitbucket, GoogleSource

curl_header() {
    local host="$1"
    local -a headers=()

    case "$host" in
        github)
            if [[ -n "${GITHUB_TOKEN:-}" ]]; then
                vecho "Making authenticated request to GitHub API" >&2
                headers+=("-H" "Authorization: Bearer $GITHUB_TOKEN")
                headers+=("-H" "X-GitHub-Api-Version: 2026-03-10")
            else
                vecho "GITHUB_TOKEN not set; requests unauthenticated" >&2
            fi
            ;;
        gitlab)
            if [[ -n "${GITLAB_TOKEN:-}" ]]; then
                headers+=("-H" "PRIVATE-TOKEN: $GITLAB_TOKEN")
            else
                vecho "GITLAB_TOKEN not set; requests unauthenticated" >&2
            fi
            ;;
        bitbucket|googlesource)
            # Tokens rarely needed, do nothing
            ;;
        *)
            eecho "Unknown host: $host"
            return 1
            ;;
    esac

    if [[ "${#headers[@]}" -eq 0 ]]; then
        vecho "No token provided; sending unauthenticated request to $host API. Rate limits may apply." >&2
        return 0
    fi

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

    local response=$(curl -sSL -w "\n%{http_code}" -I "${curl_args[@]}" "$url")
    local status=$(echo "$response" | tail -n1)

    if ! [[ "$status" =~ ^[0-9]+$ ]]; then
        eecho "Unexpected response when accessing $url: $status"
        return 1
    fi
    handle_http_status "$status" "$url" || return 1
}

handle_http_status() {
    local status="$1"
    local url="$2"
    case "$status" in
        200) iecho "Repository is reachable."; return 0 ;;
        429|403) eecho "Repository not reachable: rate limit exceeded or access forbidden (HTTP $status)"; return 1 ;;
        404) eecho "Repository not found (HTTP 404)"; return 1 ;;
        *) eecho "Cannot access $url (HTTP $status)"; return 1 ;;
    esac
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
    local encoded=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$repo_path")
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
