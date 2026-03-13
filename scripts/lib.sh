#!/usr/bin/env bash
# lib.sh — shared helper functions for git-fetcher

# =============================================
# Check HTTP status of a URL
# Arguments: $1 - URL
# Exits if not 200
# =============================================
check_http() {
    local url="$1"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
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
    curl -L "$url" -o "$file"
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
# Print info messages
# Arguments: $* - message
# =============================================
iecho() {
    echo "[INFO] $*"
}

# =============================================
# General message printer with optional prefix and conditional printing
# Arguments:
#   $1 - variable name to check (VERBOSE, DEBUG, or special "ALWAYS")
#   $2 - prefix (e.g., "[VERBOSE]", "[DEBUG]", "[ERROR]")
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

    if [[ "$var_name" == "ALWAYS" ]] || [[ "${!var_name}" == true ]]; then
        [[ "$no_prefix" == true ]] && echo "$*" >&2 || echo "$prefix $*" >&2
    fi
}

# =============================================
# Verbose message
vecho() { _msg VERBOSE "[VERBOSE]" "$@"; }

# Debug message
decho() { _msg DEBUG "[DEBUG]" "$@"; }

# Error message (always prints, to stderr)
eecho() { _msg ALWAYS "[ERROR]" "$@"; }
