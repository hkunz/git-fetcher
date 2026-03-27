#!/usr/bin/env bash
# hosts/sourceforge.sh
# Example: https://sourceforge.net/projects/zlib/

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

detect_host() {
    local url="$1"
    if [[ "$url" =~ sourceforge\.net/projects/ ]]; then
        HOST="sourceforge"

        # Extract project name
        OWNER_REPO=$(echo "$url" | sed -E 's#.*/projects/([^/]+)/?.*#\1#')

        # Normalize Git URL (not always usable, but keep consistency)
        GIT_URL="https://git.code.sf.net/p/$OWNER_REPO/code"

        return 0
    fi
    return 1
}

# ==============================
# Resolve archive
# ==============================
resolve_archive() {
    local project="$OWNER_REPO"

    # ----------------------------------
    # Require version (no auto-detect)
    # ----------------------------------
    local version="${TAG:-${REF_NAME:-}}"

    if [[ -z "$version" ]]; then
        eecho "SourceForge requires a version (--ref)."
        eecho "Example:"
        eecho "  gsrc https://sourceforge.net/projects/$project --ref 1.2.13"
        return 1
    fi

    iecho "Resolving SourceForge project '$project' (version: $version)"

    # ----------------------------------
    # Normalize
    # ----------------------------------
    TAG="$version"
    BRANCH=""
    REF_NAME=""
    normalize_version

    # ----------------------------------
    # Try multiple filename extensions
    # ----------------------------------
    local filenames=(
        "${project}-${version}.tar.gz"
        "${project}-${version}.tar.bz2"
        "${project}-${version}.tar.xz"
        "${project}-${version}.zip"
    )

    # ----------------------------------
    # Try common SourceForge path patterns
    # ----------------------------------
    local base="https://downloads.sourceforge.net/project/$project"

    for file in "${filenames[@]}"; do
        local try_paths=(
            "$project/$version/$file"
            "$version/$file"
            "$project/$file"
            "${project}-src/$version/$file"
            "$file"
        )

        for path in "${try_paths[@]}"; do
            local url="$base/$path"
            decho "Trying: $url"

            if check_commit_exists "$url"; then
                ARCHIVE_URL="$url"
                ARCHIVE_FILE="$file"
                DESCRIPTION="SourceForge project: $project"

                iecho "Resolved SourceForge URL: $url"
                iecho "Archive file: $file"
                return 0
            fi
        done
    done

    # ----------------------------------
    # If nothing worked → fail cleanly
    # ----------------------------------
    eecho "Could not resolve SourceForge archive for:"
    eecho "  project: $project"
    eecho "  version: $version"
    eecho ""
    eecho "Try manually visiting:"
    eecho "  https://sourceforge.net/projects/$project/files/"
    return 1
}

# ==============================
# Resolve specific ref (limited support)
# ==============================
resolve_specific_ref() {
    local project="$1"
    local ref_name="$2"

    wecho "SourceForge does not support refs like GitHub (branch/tag/commit). Treating '$ref_name' as version string."

    OWNER_REPO="$project"

    ARCHIVE_FILE="${project}-${ref_name}.tar.gz"
    ARCHIVE_URL="https://downloads.sourceforge.net/project/$project/$ARCHIVE_FILE"

    TAG="$ref_name"
    BRANCH=""
    REF_NAME=""

    normalize_version
}

# ==============================
# No "latest release" API
# ==============================
get_latest_release_tag() {
    :
}
