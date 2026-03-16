#!/usr/bin/env bash
# hosts/common.sh
# Shared helpers for GitHub, GitLab, Bitbucket, GoogleSource

# ==============================
# HTTP check
# ==============================
check_repo_access() {
    local url="$1"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    if [[ "$status" -ne 200 ]]; then
        eecho "Cannot access $url (HTTP $status)"
        return 1
    fi
    return 0
}

# Optional: fetch curl headers (for API auth or logging)
curl_headers() {
    local url="$1"
    # Example: you can add -H "Authorization: token $GITHUB_TOKEN" here if needed
    echo "-s"
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
    local default_branch="$2"
    local tag
    if [[ -n "$tags" ]]; then
        tag=$(echo "$tags" \
            | grep -E '^[vV]?[0-9]+(\.[0-9]+)*$' \
            | sort -V \
            | tail -n1)

        [[ -n "$tag" ]] && echo "$tag" && return 0
    fi
    # fallback
    echo "$default_branch"
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
            echo "$owner_repo/+archive/$version.tar.gz"
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
    local version="$2"
    ARCHIVE_FILE="$(basename "$repo")-${version}.tar.gz"
    DESCRIPTION="${DESCRIPTION:-No description available}"
}

# ==============================
# Validate if commit exists
# ==============================
check_commit_exists() {
    local url="$1"
    local headers
    headers=($(curl_headers "$url"))

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "${headers[@]}" -L -I "$url")

    if [[ "$code" =~ ^2 ]]; then
        return 0  # commit exists
    else
        return 1  # commit does not exist
    fi
}
