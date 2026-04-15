#!/usr/bin/env bash
# hosts/common.sh
# Shared helpers for GitHub, GitLab, Bitbucket, GoogleSource
set -e

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
        000) eecho "Cannot reach URL: $url (server unreachable, DNS failure, or network issue)"; return 1 ;;
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
    [sourceforge]="sourceforge.net"
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
        HOST="${domain%%.*}"  
        OWNER_REPO="${url#*${domain}/}"
        OWNER_REPO="${OWNER_REPO%.git}"
        OWNER_REPO="${OWNER_REPO%/}"

        # -------------------------------
        # Warn if user used a direct archive URL for a known host
        # -------------------------------
        if [[ "$url" =~ \.(tar\.gz|tgz|zip|tar\.bz2|tar\.xz)$ ]]; then
            # Extract just owner/repo
            IFS='/' read -r owner repo _ <<< "$OWNER_REPO"
            project_path="$owner/$repo"

            eecho "You provided a direct archive URL for a known host ($HOST)."
            eecho "    Use the proper project URL and specify --ref for branch/tag/commit instead."
            eecho "    Example: gsrc https://${HOST_MAP[$HOST]}/$project_path --ref <branch|tag|commit>"
            return 2  # fatal
        fi

        # Construct default Git URL
        case "$HOST" in
            github)       GIT_URL="https://github.com/$OWNER_REPO.git" ;;
            gitlab)       GIT_URL="https://gitlab.com/$OWNER_REPO.git" ;;
            bitbucket)    GIT_URL="https://bitbucket.org/$OWNER_REPO.git" ;;
            googlesource) GIT_URL="$url" ;;
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
        clean_tags=$(echo "$tags" \
            | tr -d '\r' \
            | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # 1. Semver: optionally prefixed with "v" or "V"
        tag=$(echo "$clean_tags" \
            | grep -E '^v?[0-9]+\.[0-9]+(\.[0-9]+)?$' \
            | sort -V \
            | tail -n1)

        # 2. Fallback: numbers anywhere in the tag
        if [[ -z "$tag" ]]; then
            tag=$(echo "$clean_tags" \
                | grep -E '[0-9]+' \
                | sort -V \
                | tail -n1)
        fi
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
        sourceforge)
            echo "https://downloads.sourceforge.net/project/$owner_repo/$version"
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

    decho "Final ref chosen: '$ref' (TAG='$TAG', BRANCH='$BRANCH', REF='$REF_NAME')"

    if [[ -n "$TAG" ]]; then
        ARCHIVE_URL=$(construct_archive_url "$HOST" "$repo" "$TAG" "tags")

    elif [[ -n "$BRANCH" ]]; then
        ARCHIVE_URL=$(construct_archive_url "$HOST" "$repo" "$BRANCH" "heads")

    elif [[ -n "$REF_NAME" ]]; then
        # commit or custom ref
        ARCHIVE_URL=$(construct_archive_url "$HOST" "$repo" "$REF_NAME" "")

    else
        eecho "Error: No valid ref (TAG/BRANCH/REF_NAME all empty)"
        exit 1
    fi

    readarray -t curl_args < <(curl_header "$HOST")
    ARCHIVE_FILE="$(basename "$repo")-${ref}.tar.gz"
    DESCRIPTION=$(curl -s "${curl_args[@]}" "$api" | jq -r '.description // empty')
}

get_archive_name() {
    local owner_repo="$1"
    local version="$2"
    local host="$3"
    echo "$(basename "$owner_repo")-$version.tar.gz"
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

normalize_version() {
    # Determine version: Extract version from tag robustly (dots, underscores, or dashes)
    if [[ -n "$TAG" ]]; then
        # extract version from tag
        if [[ "$TAG" =~ ([0-9]+([._-][0-9]+)+) ]]; then
            VERSION="${BASH_REMATCH[1]}"
            VERSION="${VERSION//[_-]/.}"
        else
            VERSION="$TAG"
        fi
        ARCHIVE_VERSION="$TAG"
    elif [[ -n "$BRANCH" ]]; then
        VERSION="$BRANCH"
        ARCHIVE_VERSION="$BRANCH"
    elif [[ -n "$REF_NAME" ]]; then
        # commit SHA or custom ref → use first 7 chars
        VERSION="${REF_NAME:0:7}"
        ARCHIVE_VERSION="$REF_NAME"
    else
        VERSION="unknown"
        ARCHIVE_VERSION="$VERSION"
    fi
    decho "Normalized version: $VERSION"
    decho "Archive version: $ARCHIVE_VERSION"
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
    normalize_version
}

detect_ref_type() {
    local host="$1"
    local owner_repo="$2"
    local ref="$3"
    local git_url

    case "$host" in
        github)
            if [[ "$owner_repo" =~ ^https?:// ]]; then
                git_url="$owner_repo.git"
            else
                git_url="https://github.com/$owner_repo.git"
            fi
            ;;
        gitlab)
            if [[ "$owner_repo" =~ ^https?:// ]]; then
                git_url="$owner_repo.git"
            else
                git_url="https://gitlab.com/$owner_repo.git"
            fi
            ;;
        bitbucket)
            if [[ "$owner_repo" =~ ^https?:// ]]; then
                git_url="$owner_repo.git"
            else
                git_url="https://bitbucket.org/$owner_repo.git"
            fi
            ;;
        googlesource)
            # Strip https:// if present
            owner_repo="${owner_repo#https://}"
            git_url="https://$owner_repo.git"
            ;;
        *)
            eecho "Unknown host: $host"
            return 1
            ;;
    esac

    if git ls-remote --heads "$git_url" "$ref" | grep -q "$ref"; then
        echo "branch"
        return 0
    fi
    if git ls-remote --tags "$git_url" "$ref" | grep -q "$ref"; then
        echo "tag"
        return 0
    fi
    if [[ "$ref" =~ ^[0-9a-f]{7,40}$ ]]; then
        if git ls-remote "$git_url" | grep -q "$ref"; then
            echo "commit"
            return 0
        fi
    fi
    return 1
}

resolve_specific_ref_generic() {
    local host="$1"
    local owner_repo="$2"
    local ref_name="$3"
    local commit_url_template="$4"  # optional

    vecho "Resolving specific ref: $ref_name"

    local ref_type
    ref_type=$(detect_ref_type "$host" "$owner_repo" "$ref_name") || {
        eecho "The ref '$ref_name' not found in $owner_repo"
        return 1
    }

    case "$ref_type" in
        branch)
            BRANCH="$ref_name"; TAG=""; REF_NAME=""
            ARCHIVE_URL=$(construct_archive_url "$host" "$owner_repo" "$BRANCH" "heads")
            ;;
        tag)
            TAG="$ref_name"; BRANCH=""; REF_NAME=""
            ARCHIVE_URL=$(construct_archive_url "$host" "$owner_repo" "$TAG" "tags")
            ;;
        commit)
            TAG=""; BRANCH=""; REF_NAME="$ref_name"
            if [[ -n "$commit_url_template" ]]; then
                ARCHIVE_URL=$(printf "$commit_url_template" "$owner_repo" "$REF_NAME")
            else
                ARCHIVE_URL=$(construct_archive_url "$host" "$owner_repo" "$REF_NAME")
            fi
            ;;
    esac
    normalize_version
}

get_description_from_tar() {
    local archive_file="$1"
    local first_dir
    local description=""
    decho "Parsing description in any README file within $archive_file"

    first_dir=$(tar -tzf "$archive_file" | cut -d/ -f1 | sort -u | head -n1)

    local readme_file
    for f in README.md README.rst README.txt README; do
        if tar -tzf "$archive_file" | grep -q "^$first_dir/$f$"; then
            readme_file="$first_dir/$f"
            decho "Found file: $readme_file"
            break
        fi
    done

    if [[ -n "$readme_file" ]]; then
        # Get first line that starts with #
        description=$(tar -xOzf "$archive_file" "$readme_file" \
            | grep '^#' \
            | head -n1 \
            | sed 's/^#\+ *//'  # remove leading # symbols and spaces
        )
        description="${description:-Custom ref ${REF_NAME:-$BRANCH:-$TAG} (no upstream description)}"
    else
        decho "No README file found"
        description="Custom ref ${REF_NAME:-$BRANCH:-$TAG} (no README found)"
    fi

    echo "$description"
}

get_repo_homepage() {
    echo ""
}
