#!/usr/bin/env bash
# lib.sh — shared helper functions for git-fetcher

# =============================================
# Optional GitHub token header for API requests
# Optional GitHub authentication and headers
# =============================================

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

    headers=($(curl_headers "$url"))
    curl -L "${headers[@]}" "$url" -o "$file"

   # detect archive type
    local filetype
    filetype=$(file -b "$file")

    local tflag detected
    case "$filetype" in
        *gzip*)  tflag="z"; detected="gzip" ;;
        *bzip2*) tflag="j"; detected="bzip2" ;;
        *XZ*)    tflag="J"; detected="xz" ;;
        *tar*)   tflag="";  detected="tar" ;;
        *)
            vecho "Not a tar archive ($filetype), skipping flat check"
            return
            ;;
    esac

    # check if filename extension matches detected type
    local ext="${file##*.}"
    if [[ "$ext" == "gz" && "$detected" != "gzip" ]]; then
        wecho "Notice: file extension suggests gzip but actual archive format is: $filetype"
    else
        iecho "File extension '$ext' matches ($filetype)"
    fi

    # check if flat tarball
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
        shopt -s dotglob
        mv "$tmpdir"/* "$tmpdir/$name" 2>/dev/null || true

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
    if [[ "$1" == "--no-prefix" ]]; then
        no_prefix=true
        shift
    fi

    # Decide output stream
    local out=2  # default stderr
    [[ "$var_name" == "INFO" ]] && out=1   # INFO goes to stdout

    # Check if message should print
    if [[ "$var_name" == "ALWAYS" ]] || [[ "${!var_name}" == true ]] || [[ "$var_name" == "INFO" ]]; then
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
