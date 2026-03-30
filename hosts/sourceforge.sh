#!/usr/bin/env bash
# hosts/sourceforge.sh
# SourceForge = strict validator + reuse url-only logic
# Example: gsrc https://downloads.sourceforge.net/project/opencore-amr/fdk-aac/fdk-aac-2.0.3.tar.gz

set -e

source "$(dirname "${BASH_SOURCE[0]}")/url-only.sh"

# =============================================
# Detect SourceForge URL
# =============================================
detect_host() {
    local url="$1"

    # Only handle SourceForge URLs
    if [[ "$url" =~ sourceforge\.net ]]; then

        # Enforce correct download URL format
        if [[ ! "$url" =~ ^https://downloads\.sourceforge\.net/ ]]; then
            eecho "Error: SourceForge URL must start with:"
            eecho "       https://downloads.sourceforge.net/"
            return 2
        fi

        iecho "Detected SourceForge URL"

        # Delegate to generic handler
        detect_host_url_only "$url" || return 1

        # Override host name (for logging / future behavior)
        HOST="sourceforge"

        return 0
    fi

    return 1
}
