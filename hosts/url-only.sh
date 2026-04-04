#!/usr/bin/env bash
# hosts/url-only.sh
# Generic handler for direct archive URLs
# Example: gsrc https://downloads.sourceforge.net/project/opencore-amr/fdk-aac/fdk-aac-2.0.3.tar.gz
# Example: gsrc https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz

set -e

GENERIC_DOWNLOAD_URL=
ARCHIVE_URL=
ARCHIVE_FILE=

# =============================================
# Generic host detection
# =============================================
detect_host_url_only() {
    local url="$1"

    # Only accept direct archive URLs
    if [[ "$url" =~ ^https?:// ]]; then  # if [[ "$url" =~ ^https?:// ]] && [[ "$url" =~ \.(tar\.gz|tgz|zip|tar\.bz2|tar\.xz)$ ]]; then
        GENERIC_DOWNLOAD_URL="$url"
        ARCHIVE_URL="$url"
        ARCHIVE_FILE="$(basename "$url")"

        GIT_URL="$url"
        OWNER_REPO="$ARCHIVE_FILE"
        HOST="url-only"

        iecho "Detected generic URL archive: $GENERIC_DOWNLOAD_URL"
        return 0
    fi

    return 1
}

# =============================================
# Resolve archive (generic)
# =============================================
resolve_archive() {

    # Use cache if same URL
    if [[ -n "$ARCHIVE_FILE_DB" && -f "$ARCHIVE_FILE_DB" && -n "$ARCHIVE_URL_DB" ]]; then
        if [[ "$ARCHIVE_URL_DB" == "$GENERIC_DOWNLOAD_URL" ]]; then
            ARCHIVE_FILE="$ARCHIVE_FILE_DB"
            ARCHIVE_URL="$ARCHIVE_FILE_DB"
            iecho "Using cached archive: $ARCHIVE_FILE"
            return 0
        else
            iecho "Cached URL differs → redownloading"
        fi
    fi

    validate_url_only "$GENERIC_DOWNLOAD_URL" || return 1

    ARCHIVE_URL="$GENERIC_DOWNLOAD_URL"
    ARCHIVE_FILE="$(basename "$ARCHIVE_URL")"

    if [[ "$HOST" == "url-only" || "$HOST" == "sourceforge" ]]; then
        # e.g., fdk-aac-2.0.3.tar.gz → 2.0.3
        if [[ "$ARCHIVE_FILE" =~ ([0-9]+([._-][0-9]+)+) ]]; then
            TAG="${BASH_REMATCH[1]}"
        else
            TAG="unknown"
        fi
    fi

    normalize_version

    iecho "Archive ready for download: $ARCHIVE_URL"

    echo
    wecho "Note: Some URLs generate tarballs dynamically when downloaded."
    wecho "The SHA256 checksum may differ between downloads even if the code has not changed."
    echo

    return 0
}

# =============================================
# Validate URL
# =============================================
validate_url_only() {
    local url="$1"

    iecho "Validating URL..."

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -L "$url")

    handle_http_status "$code" "$url" || return 1
    iecho "URL validated successfully."
}

# =============================================
# Not supported for generic URLs
# =============================================
resolve_specific_ref() {
    eecho "--ref is not supported for direct archive URLs."
    exit 1
}

get_latest_release_tag() {
    eecho "Latest tag not supported for direct archive URLs."
    exit 1
}

get_archive_name() {
    local owner_repo="$1"
    local version="$2"
    local host="$3"

    # Just return filename
    echo "$(basename "$owner_repo")"
}
