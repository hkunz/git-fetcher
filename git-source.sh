#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SCRIPT_DIR="$ROOT_DIR/scripts"

source "$ROOT_DIR/hosts/common.sh"
source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/lib-db.sh"
source "$SCRIPT_DIR/lib-color.sh"

LIST_BRANCHES=false
LIST_TAGS=false
VERBOSE=false
DEBUG=false
GENERATE_MXE_MAKEFILE=false
GENERATE_MXE_TESTFILE=false
FORCE_DOWNLOAD=false
GH_MODE="tags"
INPUT=""
ARCHIVE_NAME=
ARCHIVE_SUBDIR=
VERSION=  # if possible, is the numeric normalized version in X.Y.Z format
ARCHIVE_VERSION=  # is the full version after the package name of a tarball name after the - packagen-archiveversion.tar.gz


# =============================================
# Usage function
# =============================================
print_usage() {
    echo "Usage: $0 [OPTIONS] <repo_url_or_owner/repo>"
    echo
    echo "Options:"
    echo "  -b, --list-branches          List all branches of the repository"
    echo "  -t, --list-tags              List all tags of the repository"
    echo "  -v, --verbose                Enable verbose output"
    echo "  --debug                      Enable debug output"
    echo "  --ref=<name>                 Download a specific branch, tag, or commit"
    echo "  --generate-mxe-makefile      Generate MXE .mk file after download"
    echo "  --generate-mxe-testfile      Generate MXE test file for .mk"
    echo "  --force                      Redownload archive even if it exists"
    echo "  -h, --help                   Show this help message"
}

# =============================================
# Parse arguments
# =============================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--list-branches) LIST_BRANCHES=true ;;
        -t|--list-tags) LIST_TAGS=true ;;
        -v|--verbose) export VERBOSE=true ;;
        --debug) export DEBUG=true ;;
        --generate-mxe-makefile=*)
            export GENERATE_MXE_MAKEFILE=true
            MXE_ARGS="${1#*=}"
            ;;
        --generate-mxe-makefile)
            export GENERATE_MXE_MAKEFILE=true
            MXE_ARGS="default"
            ;;
        --generate-mxe-testfile)
            export GENERATE_MXE_TESTFILE=true
            ;;
        --ref=*)
            REQUESTED_REF_NAME="${1#*=}"
            ;;
        --ref)
            if [[ -z "$2" || "$2" == -* ]]; then
                eecho "Error: --ref requires a branch, tag, or commit"
                exit 1
            fi
            REQUESTED_REF_NAME="$2"
            shift
            ;;
        --force) FORCE_DOWNLOAD=true ;;
        -h|--help) print_usage; exit 0 ;;
        -*) eecho "Unknown option: $1"; exit 1 ;;
        *) INPUT="$1" ;;
    esac
    shift
done

[ -n "$INPUT" ] || { print_usage; exit 1; }

# =============================================
# Host detection
# =============================================
HOST=""
OWNER_REPO=""
GIT_URL=""

for domain in $(get_known_domains); do
    vecho "Checking if URL '$INPUT' contains domain: '$domain'"
    if [[ "$INPUT" == *"$domain"* ]]; then
        HOST="${domain%%.*}"  # strip .com/.org/etc
        break
    fi
done

HOST_SCRIPT="$ROOT_DIR/hosts/$HOST.sh"

if [[ -n "$HOST" && -f "$HOST_SCRIPT" ]]; then
    source "$HOST_SCRIPT"
    detect_host "$INPUT"
else
    eecho "Unsupported host in URL '$INPUT'"
    exit 1
fi

vecho "Detected host: $HOST"
vecho "Repository (owner/name): $OWNER_REPO"
vecho "Git URL: $GIT_URL"
PACKAGE_NAME="${OWNER_REPO##*/}"
vecho "Package name: $PACKAGE_NAME"

# =============================================
# List branches/tags if requested
# =============================================
if $LIST_BRANCHES; then
    iecho "Branches for $OWNER_REPO:"
    git ls-remote --heads "$GIT_URL" | awk '{print $2}' | sed 's#refs/heads/##'
    exit 0
fi

if $LIST_TAGS; then
    iecho "Tags for $OWNER_REPO:"
    git ls-remote --tags "$GIT_URL" \
        | awk '{print $2}' \
        | sed 's#refs/tags/##' \
        | sed 's/\^{}//' \
        | sort -u
    exit 0
fi

# =============================================
# Load archive info from DB
# =============================================
init_db
entry=$(get_db_entry "$GIT_URL")
get_entry_field() { echo "$entry" | jq -r "$1 // empty"; }

load_from_db() {
    ARCHIVE_URL=$(get_entry_field '.archive_url')
    ARCHIVE_FILE=$(get_entry_field '.archive')
    ARCHIVE_NAME=$(basename "$ARCHIVE_FILE")
    DESCRIPTION=$(get_entry_field '.description')
    TAG=$(get_entry_field '.latest_tag')
    BRANCH=$(get_entry_field '.default_branch')
    REF_NAME=$(get_entry_field '.ref_name')
    CHECKSUM=$(get_entry_field '.sha256')
    BUILD_SYSTEM=$(get_entry_field '.build_system')
}

# =============================================
# Determine type of requested ref
# =============================================
get_ref_type() {
    local ref="$1"
    if [[ -z "$ref" ]]; then
        echo ""
    elif [[ "$ref" =~ ^[0-9a-f]{7,40}$ ]]; then
        echo "commit"
    elif [[ "$ref" =~ ^v?[0-9]+([._-][0-9]+)*$ ]]; then
        echo "tag"
    else
        echo "branch"
    fi
}

# =============================================
# Decide whether we need to redownload
# =============================================
should_redownload() {
    # Force download always overrides cache
    [[ "$FORCE_DOWNLOAD" == true ]] && return 0

    # If no DB entry or archive file missing → redownload
    [[ -z "$entry" || -z "$ARCHIVE_FILE_DB" || ! -f "$ARCHIVE_FILE_DB" ]] && return 0

    # Load DB values
    local tag_db branch_db ref_db
    tag_db=$(get_entry_field '.latest_tag')
    branch_db=$(get_entry_field '.default_branch')
    ref_db=$(get_entry_field '.ref_name')

    # If ALL ref identifiers are empty → invalid cache → redownload
    if [[ -z "$tag_db" && -z "$branch_db" && -z "$ref_db" ]]; then
        return 0
    fi
    # No specific ref requested → DB copy is fine
    if [[ -z "$REQUESTED_REF_NAME" ]]; then
        return 1
    fi
    local ref="$REQUESTED_REF_NAME"
    # Match only against NON-empty DB fields
    if [[ -n "$ref" && (
            ( -n "$tag_db" && "$ref" == "$tag_db" ) ||
            ( -n "$branch_db" && "$ref" == "$branch_db" ) ||
            ( -n "$ref_db" && "$ref" == "$ref_db" )
        ) ]]; then
        return 1  # Already cached
    fi
    return 0  # Otherwise → need to redownload
}

# =============================================
# Download archive if needed
# =============================================
download_archive_if_needed() {
    ARCHIVE_VERSION="${TAG:-${BRANCH:-${REF_NAME}}}"
    ARCHIVE_NAME="$(basename "$OWNER_REPO")-$ARCHIVE_VERSION.tar.gz"
    ARCHIVE_FILE="$ROOT_DIR/downloads/$ARCHIVE_NAME"

    mkdir -p "$ROOT_DIR/downloads/"
    download_archive "$ARCHIVE_URL" "$ARCHIVE_FILE"
    CHECKSUM=$(compute_sha256 "$ARCHIVE_FILE")
    JSON_OUTPUT=$(bash "$SCRIPT_DIR/detect-build.sh" "$ARCHIVE_FILE")
    BUILD_SYSTEM=$(echo "$JSON_OUTPUT" | jq -r '.build_system')

    if [[ -z "$DESCRIPTION" ]]; then
        decho "No description available."
        DESCRIPTION=$(get_description_from_tar "$ARCHIVE_FILE")
    fi

    if [[ -n "$REF_NAME" ]]; then
        update_db "$GIT_URL" "" "" "$REF_NAME" "$ARCHIVE_URL" "$ARCHIVE_FILE" "$CHECKSUM" "$PACKAGE_NAME" "$DESCRIPTION" "$BUILD_SYSTEM"
    else
        update_db "$GIT_URL" "$TAG" "$BRANCH" "" "$ARCHIVE_URL" "$ARCHIVE_FILE" "$CHECKSUM" "$PACKAGE_NAME" "$DESCRIPTION" "$BUILD_SYSTEM"
    fi
}

# =============================================
# Load DB and check if we need download
# =============================================
TAG=
BRANCH=
REF_NAME=
VERSION=
ARCHIVE_VERSION=

ARCHIVE_FILE_DB=$(get_entry_field '.archive')
load_from_db
normalize_version

if should_redownload; then
    if [[ -n "$REQUESTED_REF_NAME" ]]; then
        resolve_specific_ref "$OWNER_REPO" "$REQUESTED_REF_NAME"
    else
        resolve_archive "$OWNER_REPO"
    fi
    normalize_version
    download_archive_if_needed
    iecho "Downloaded archive: $ARCHIVE_FILE"
else
    iecho "Download URL: $ARCHIVE_URL"
    iecho "Using archive from DB: $ARCHIVE_FILE"
fi

# Detect top-level folder(s) inside the tar
top_level_dirs=$(tar -tf "$ARCHIVE_FILE" | cut -d/ -f1 | sort -u)
num_dirs=$(echo "$top_level_dirs" | wc -l)

if [ "$num_dirs" -eq 1 ]; then
    ARCHIVE_SUBDIR="$top_level_dirs"
    iecho "Archive subdirectory detected: $ARCHIVE_SUBDIR"
else
    eecho "Archive contains $num_dirs top-level entries: $top_level_dirs"
    eecho "Expected exactly one top-level folder in the tarball. Aborting."
    exit 1
fi

# Show tag, branch, or commit
if [[ -n "$TAG" ]]; then
    iecho "Latest Tag: $(bold_bright_green "$TAG")"
elif [[ -n "$BRANCH" ]]; then
    iecho "Default Branch: $(bold_bright_green "$BRANCH")"
elif [[ -n "$REF_NAME" ]]; then
    iecho "Commit/Custom Ref: $(bold_bright_green "$REF_NAME")"
fi

# =============================================
# Display summary
# =============================================
iecho "Downloaded file: $(bold_bright_cyan "$ARCHIVE_NAME")"
iecho "Package name: $(bold_bright_green "$PACKAGE_NAME")"
[ -n "$DESCRIPTION" ] && iecho "Package description: $([[ "$DEBUG" = true ]] && echo "$DESCRIPTION" || echo "${DESCRIPTION:0:40}...")"

# If description is empty (custom ref, branch, tag, or commit), set placeholder
if [[ -z "$DESCRIPTION" ]]; then
    DESCRIPTION="No description available"
fi

iecho "Version: $(bold_bright_cyan "$VERSION")"  # normalized version to X.Y.Z format
iecho "SHA256 checksum: $(bold_bright_cyan "$CHECKSUM")"
iecho "Detected build system: $(bold_bright_cyan "$BUILD_SYSTEM")"

# =============================================
# Optional: generate MXE .mk file
# =============================================
if [[ "$GENERATE_MXE_MAKEFILE" == true || "$GENERATE_MXE_TESTFILE" == true ]]; then
    bash "$ROOT_DIR/contrib/mxe/scripts/generate_mxe_mk.sh" \
        --mxe_args "$MXE_ARGS" \
        --owner_repo "$OWNER_REPO" \
        --archive "$ARCHIVE_FILE" \
        --pkg "$PACKAGE_NAME" \
        --tag "$TAG" \
        --version "$VERSION" \
        --archive_url "$ARCHIVE_URL" \
        --checksum "$CHECKSUM" \
        --description "$DESCRIPTION" \
        --website "$GIT_URL" \
        $( [[ "$DEBUG" == true ]] && echo --debug )
fi

iecho "Done"
