#!/usr/bin/env bash
# hosts/sourceforge.sh
set -e

SOURCEFORGE_URL=

# Only need to save ARCHIVE_URL when detect_host succeeds
detect_host() {
    local url="$1"

    #iecho "Trying SourceForge host detection for URL: $url"

    if [[ "$url" =~ sourceforge\.net ]]; then
        if [[ ! "$url" =~ ^https://downloads\.sourceforge\.net/ ]]; then
            eecho "Error: SourceForge URL must start with https://downloads.sourceforge.net/"
            return 1
        fi

        HOST="sourceforge"
        SOURCEFORGE_URL="$url"
        ARCHIVE_FILE="$(basename "$url")"
        OWNER_REPO="$ARCHIVE_FILE"
        GIT_URL=""

        iecho "Detected SourceForge URL: $SOURCEFORGE_URL"
        return 0
    fi

    return 1
}

validate_sourceforge_url() {
    local url="$1"

    iecho "Validating SourceForge URL..."

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -L "$url")

    if [[ "$code" != "200" ]]; then
        eecho "Error: SourceForge URL not reachable (HTTP $code): $url"
        return 1
    fi

    iecho "SourceForge URL validated successfully."
    return 0
}

get_archive_name() {
    local owner_repo="$1"
    local version="$2"
    local host="$3"
    echo "$(basename "$owner_repo")"
}

resolve_archive() {
    # If cached → use it, NO network
    if [[ -n "$ARCHIVE_FILE_DB" && -f "$ARCHIVE_FILE_DB" ]]; then
        ARCHIVE_FILE="$ARCHIVE_FILE_DB"
        ARCHIVE_URL="$ARCHIVE_FILE_DB"   # local path
        iecho "Using cached SourceForge archive: $ARCHIVE_FILE"
        return 0
    fi

    # Otherwise → use provided URL and validate
    if [[ -n "$SOURCEFORGE_URL" ]]; then
        validate_sourceforge_url "$SOURCEFORGE_URL" || return 1

        ARCHIVE_URL="$SOURCEFORGE_URL"
        iecho "SourceForge archive ready for download: $ARCHIVE_URL"
        return 0
    fi

    eecho "Error: No valid SourceForge URL provided."
    return 1
}

resolve_specific_ref() {
    eecho "--ref is not supported for SourceForge archives."
    iecho "   Use a direct download URL instead:"
    iecho "   Example: gsrc https://downloads.sourceforge.net/project/opencore-amr/fdk-aac/fdk-aac-2.0.0.tar.gz"
    exit 1
}

get_latest_release_tag() {
    eecho "get latest tag not supported for SourceForge"
    exit 1
}
