#!/usr/bin/env bash
# hosts/sourceforge.sh
set -e

SOURCEFORGE_URL=

# Only need to save ARCHIVE_URL when detect_host succeeds
detect_host() {
    local url="$1"

    iecho "Trying SourceForge host detection for URL: $url"

    if [[ "$url" =~ sourceforge\.net ]]; then
        # Ensure canonical downloads URL
        if [[ ! "$url" =~ ^https://downloads\.sourceforge\.net/ ]]; then
            eecho "Error: SourceForge URL must start with https://downloads.sourceforge.net/"
            return 1
        fi

        HOST="sourceforge"
        ARCHIVE_URL="$url"                    # Save for later use
        ARCHIVE_FILE="$(basename "$ARCHIVE_URL")"
        OWNER_REPO="$ARCHIVE_FILE"            # placeholder so main script doesn't fail
        GIT_URL=""                            # not used

        iecho "Detected SourceForge URL: $ARCHIVE_URL"

        # Validate URL exists
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" -L "$ARCHIVE_URL")
        if [[ "$code" != "200" ]]; then
            eecho "Error: SourceForge URL not reachable (HTTP $code): $ARCHIVE_URL"
            return 1
        fi

        SOURCEFORGE_URL=$ARCHIVE_URL
        iecho "SourceForge URL validated successfully."
        return 0
    fi

    return 1
}

resolve_archive() {
    if [[ -n "$SOURCEFORGE_URL" ]]; then
        ARCHIVE_URL="$SOURCEFORGE_URL"  # sync with main script for later steps
        iecho "SourceForge archive ready for download: $ARCHIVE_URL"
        return 0
    fi
    eecho "Error: No valid SourceForge URL provided."
    return 1
}

resolve_specific_ref() {
    eecho "--ref is not supported for SourceForge archives."
    iecho "  Use a direct download URL instead. Example:"
    iecho "  gsrc https://downloads.sourceforge.net/project/opencore-amr/fdk-aac/fdk-aac-2.0.0.tar.gz"
    exit 1
}

get_latest_release_tag() {
    eecho "get latest tag not supported for SourceForge"
    exit 1
}
