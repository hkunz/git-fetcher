#!/usr/bin/env bash
# lib.sh — shared helper functions for git-fetcher

# ---------------------------------------
# Check HTTP status of a URL
# Arguments:
#   $1 - URL to check
# Exits if HTTP status is not 200
# ---------------------------------------
check_http() {
    local url="$1"
    local code

    code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    if [ "$code" -ne 200 ]; then
        echo "Error: Cannot access $url (HTTP $code)"
        exit 1
    fi
}

# ---------------------------------------
# Download an archive from a URL
# Arguments:
#   $1 - Archive URL
#   $2 - Version/branch/tag for naming
# Sets global variable FILE
# ---------------------------------------
download_archive() {
    local url="$1"
    local file="$2"

    echo "Downloading $file..."
    curl -L "$url" -o "$file"
}

# ---------------------------------------
# Compute SHA256 checksum of a file
# Arguments:
#   $1 - File path
# Sets global variable CHECKSUM
# ---------------------------------------
compute_sha256() {
    local file="$1"
    CHECKSUM=$(sha256sum "$file" | awk '{print $1}')

    echo
    echo "Archive: $file"
    echo "SHA256: $CHECKSUM"
}

# ---------------------------------------
# URL-encode a string (Python fallback)
# Arguments:
#   $1 - String to encode
# Prints encoded string
# ---------------------------------------
url_encode() {
    local str="$1"
    python3 -c "import urllib.parse; print(urllib.parse.quote('''$str''', safe=''))"
}