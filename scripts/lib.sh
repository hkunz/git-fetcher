#!/usr/bin/env bash
# lib.sh — shared helper functions for git-fetcher

# =============================================
# Optional GitHub token header for API requests
# Optional GitHub authentication and headers
# =============================================
set -e

GITHUB_HEADERS=(-A "git-fetcher-script")  # default User-Agent

if [[ -n "$GITHUB_TOKEN" ]]; then
    GITHUB_HEADERS+=(-H "Authorization: token $GITHUB_TOKEN")
fi

curl_headers() {
    return  # early exit; does nothing for now

    # --- real logic for later ---
    local url="$1"
    local headers=()
    if [[ "$url" =~ github\.com ]]; then
        headers=("${GITHUB_HEADERS[@]}")
    fi
    echo "${headers[@]}"
}

# =============================================
# Check HTTP status of a URL
# Arguments: $1 - URL
# Exits if not 200
# =============================================
check_http() {
    local url="$1"
    local code
    local headers
    # store headers in an array
    headers=($(curl_headers "$url"))
    code=$(curl -s -o /dev/null -w "%{http_code}" "${headers[@]}" "$url")
    if [ "$code" -ne 200 ]; then
        eecho "Cannot access $url (HTTP $code)"
        exit 1
    fi
    vecho "URL $url is accessible (HTTP $code)"
}

# =============================================
# Detect archive type
# =============================================
detect_archive_type() {
    local file="$1"

    case "$file" in
        *.tar.gz|*.tgz)   echo "tar.gz" ;;
        *.tar.xz|*.txz)   echo "tar.xz" ;;
        *.tar.bz2|*.tbz2) echo "tar.bz2" ;;
        *.tar)            echo "tar" ;;
        *.zip)            echo "zip" ;;
        *.tar.lz)         echo "tar.lz" ;;
        *)                echo "unknown" ;;
    esac
}

# =============================================
# Extract archive type
# =============================================
extract_archive() {
    local file="$1"
    local type
    type=$(detect_archive_type "$file")

    case "$type" in
        tar.gz)   tar -xzf "$file" ;;
        tar.xz)   tar -xJf "$file" ;;
        tar.bz2)  tar -xjf "$file" ;;
        tar)      tar -xf "$file" ;;
        zip)      unzip "$file" ;;
        *)
            eecho "Unsupported archive type: $file"
            return 1
            ;;
    esac
}

# =============================================
# Download an archive
# Arguments:
#   $1 - URL
#   $2 - target file path
# =============================================
download_archive() {
    local url="$1"
    local file="$2"

    mkdir -p "$(dirname "$file")"
    iecho "Downloading from URL: $url"
    iecho "Saving to local file: $file"

    # ==============================
    # Download with HTTP validation
    # ==============================
    headers=($(curl_headers "$url"))
    local http_code=$(curl -L --retry 3 --retry-delay 2 "${headers[@]}" -w "%{http_code}" -o "$file" "$url")

    # Fail on bad HTTP status
    if ! [[ "$http_code" =~ ^2 ]]; then
        rm -f "$file"
        eecho "Download failed: HTTP $http_code for $url"
        return 1
    fi

    # ==============================
    # Validate file content
    # ==============================
    local filetype
    filetype=$(file -b "$file")

    # Reject HTML (common failure case)
    if [[ "$filetype" == *HTML* ]]; then
        rm -f "$file"
        eecho "Download failed: received HTML instead of archive (likely bad URL)"
        return 1
    fi

    # Optional: warn if suspiciously small
    local filesize
    filesize=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file")
    if [[ "$filesize" -lt 1024 ]]; then
        wecho "Warning: downloaded file is very small ($filesize bytes)"
    fi

    # ==============================
    # Detect archive type
    # ==============================
    local tflag detected
    case "$filetype" in
        *gzip*)  tflag="z"; detected="gzip" ;;
        *bzip2*) tflag="j"; detected="bzip2" ;;
        *XZ*)    tflag="J"; detected="xz" ;;
        *tar*)   tflag="";  detected="tar" ;;
        *)
            vecho "Not a tar archive ($filetype), skipping flat check"
            vecho "Download finished successfully: $file"
            return 0
            ;;
    esac

    # ==============================
    # Extension sanity check
    # ==============================
    local ext="${file##*.}"
    if [[ "$ext" == "gz" && "$detected" != "gzip" ]]; then
        wecho "Notice: extension says .gz but actual format is: $filetype"
    else
        vecho "File extension '$ext' matches ($filetype)"
    fi

    # ==============================
    # Detect flat tarball
    # ==============================
    local first_dirs
    first_dirs=$(tar -t${tflag}f "$file" | cut -d/ -f1 | sort -u)

    if [ "$(echo "$first_dirs" | wc -l)" -ne 1 ]; then
        iecho "Flat tarball detected, wrapping contents"

        local tmpdir
        tmpdir=$(mktemp -d)

        tar -x${tflag}f "$file" -C "$tmpdir"

        local name
        name=$(basename "$file")
        # Remove compression extensions so folder matches tar name without extension
        name="${name%.tar.gz}"
        name="${name%.tar.bz2}"
        name="${name%.tar.xz}"
        name="${name%.tgz}"
        name="${name%.tbz2}"
        name="${name%.txz}"

        mkdir "$tmpdir/$name"
        mv "$tmpdir"/{.,}* "$tmpdir/$name" 2>/dev/null || true
        tar -c${tflag}f "$file" -C "$tmpdir" "$name"
        rm -rf "$tmpdir"
    fi
    vecho "Download finished successfully: $file"
}

# =============================================
# Compute SHA256 checksum
# Arguments: $1 - file path
# =============================================
compute_sha256() {
    local file="$1"
    sha256sum "$file" | awk '{print $1}'
}

# =============================================
# URL encode string (Python fallback)
# Arguments: $1 - string
# =============================================
url_encode() {
    local str="$1"
    python3 -c "import urllib.parse; print(urllib.parse.quote('''$str''', safe=''))"
}

# =============================================
# Determine GitHub mode from ARCHIVE_URL
# Sets GH_MODE to 'releases', 'tags', 'branches', or 'unknown'
# Arguments:
#   $1 - URL to analyze
# =============================================
deduce_gh_mode() {
    local url="$1"
    local mode="unknown"

    if [[ "$url" == *"/releases/"* ]]; then
        mode="releases"
    elif [[ "$url" == *"/tags/"* ]]; then
        mode="tags"
    elif [[ "$url" == *"/heads/"* ]]; then
        mode="branches"
    fi
    echo "$mode"
}

# =============================================
# General message printer with optional prefix and conditional printing
# Arguments:
#   $1 - variable name to check (VERBOSE, DEBUG, INFO, WARNING, or ALWAYS)
#   $2 - prefix (e.g., "[VERBOSE]", "[DEBUG]", "[INFO]", "[WARNING]", "[ERROR]")
#   $3..$n - message
#   optional flag: --no-prefix
# =============================================
_msg() {
    local var_name="$1"
    local prefix="$2"
    shift 2

    local no_prefix=false
    [[ "$1" == "--no-prefix" ]] && { no_prefix=true; shift; }

    local out=2
    [[ "$var_name" == "INFO" ]] && out=1

    local should_print=false

    case "$var_name" in
        ALWAYS|INFO)
            should_print=true
            ;;
        DEBUG)
            [[ "$DEBUG" == "true" ]] && should_print=true
            ;;
        VERBOSE)
            [[ "$VERBOSE" == "true" || "$DEBUG" == "true" ]] && should_print=true
            ;;
    esac

    if [[ "$should_print" == true ]]; then
        if [[ "$no_prefix" == true ]]; then
            echo "$*" >&$out
        else
            echo "$prefix $*" >&$out
        fi
    fi
}

# =============================================
# Convenience wrappers
# =============================================
iecho() { _msg INFO "[INFO]" "$@"; }        # prints to stdout
vecho() { _msg VERBOSE "[VERBOSE]" "$@"; }  # prints to stderr if VERBOSE=true
decho() { _msg DEBUG "[DEBUG]" "$@"; }      # prints to stderr if DEBUG=true
wecho() { _msg ALWAYS "[WARNING]" "$@"; }   # always stderr
eecho() { _msg ALWAYS "[ERROR]" "$@"; }     # always stderr
