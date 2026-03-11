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
    iecho "Downloading $file from $url..."
    curl -L "$url" -o "$file"
    vecho "Download finished: $file"
}

# =============================================
# Compute SHA256 checksum
# Arguments: $1 - file path
# =============================================
compute_sha256() {
    local file="$1"
    CHECKSUM=$(sha256sum "$file" | awk '{print $1}')
    iecho "Checksum computed for $file"
    iecho
    iecho "Archive: $file"
    iecho "SHA256: $CHECKSUM"
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
# Print verbose messages
# Arguments: $* - message
# =============================================
vecho() {
    if [ "$VERBOSE" = true ]; then
        echo "[VERBOSE] $*"
    fi
}

# =============================================
# Print debug messages
# Arguments: $* - message
# =============================================
decho() {
    if [ "$DEBUG" = true ]; then
        echo "[DEBUG] $*"
    fi
}

# =============================================
# Print error messages
# Arguments: $* - message
# =============================================
eecho() {
    echo "[ERROR] $*" >&2
}
