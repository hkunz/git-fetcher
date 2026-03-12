#!/usr/bin/env bash
set -e

ARCHIVE="$1"

if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
    echo "Usage: $0 <source-archive>" >&2
    exit 1
fi

# =============================================
# Get file list from archive (no extraction)
# =============================================

case "$ARCHIVE" in
    *.tar.gz|*.tgz)
        FILE_LIST=$(tar -tzf "$ARCHIVE")
        ;;
    *.tar.xz)
        FILE_LIST=$(tar -tJf "$ARCHIVE")
        ;;
    *.tar.bz2)
        FILE_LIST=$(tar -tjf "$ARCHIVE")
        ;;
    *.zip)
        FILE_LIST=$(unzip -Z1 "$ARCHIVE")
        ;;
    *)
        echo "Unknown"
        exit 0
        ;;
esac

# =============================================
# Remove the top-level directory (GitHub tarballs)
# =============================================

FILE_LIST=$(echo "$FILE_LIST" | sed 's|^[^/]*/||')

# =============================================
# Detect build system (root or depth 1)
# =============================================

if grep -Eq '^(meson\.build|[^/]+/meson\.build)$' <<< "$FILE_LIST"; then
    BUILD_SYSTEM="Meson"

elif grep -Eq '^(CMakeLists\.txt|[^/]+/CMakeLists\.txt)$' <<< "$FILE_LIST"; then
    BUILD_SYSTEM="CMake"

elif grep -Eq '^(configure|[^/]+/configure)$' <<< "$FILE_LIST"; then
    BUILD_SYSTEM="Autotools"

elif grep -Eq '^(Makefile|[^/]+/Makefile)$' <<< "$FILE_LIST"; then
    BUILD_SYSTEM="Makefile"

elif grep -Eq '^(pyproject\.toml|[^/]+/pyproject\.toml)$' <<< "$FILE_LIST"; then
    BUILD_SYSTEM="Python"

elif grep -Eq '^(Cargo\.toml|[^/]+/Cargo\.toml)$' <<< "$FILE_LIST"; then
    BUILD_SYSTEM="Rust"

elif grep -Eq '^(go\.mod|[^/]+/go\.mod)$' <<< "$FILE_LIST"; then
    BUILD_SYSTEM="Go"

else
    BUILD_SYSTEM="Unknown"
fi

echo "$BUILD_SYSTEM"
