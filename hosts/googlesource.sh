#!/usr/bin/env bash
# hosts/sourceforge.sh
set -e
source "$(dirname "${BASH_SOURCE[0]}")/url-only.sh"

SOURCEFORGE_URL=

# Override detect_host to add SF-specific check
detect_host() {
    local url="$1"
    if [[ "$url" =~ sourceforge\.net ]]; then
        if [[ ! "$url" =~ ^https://downloads\.sourceforge\.net/ ]]; then
            eecho "Error: SourceForge URL must start with https://downloads.sourceforge.net/"
            return 1
        fi
        SOURCEFORGE_URL="$url"
        ARCHIVE_FILE="$(basename "$url")"
        GIT_URL="$url"        # Unique DB identifier
        OWNER_REPO="$ARCHIVE_FILE"
        HOST="sourceforge"
        iecho "Detected SourceForge URL: $SOURCEFORGE_URL"
        return 0
    fi
    return 1
}

# Can still reuse generic functions for SF
construct_sourceforge_archive() { construct_url_only_archive "$1"; }
validate_sourceforge_url() { validate_url_only "$1"; }

# SF does not support --ref or latest tag
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
