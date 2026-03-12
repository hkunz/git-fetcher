#!/usr/bin/env bash
# uninstall.sh — Remove git-source installation using manifest

set -e

PREFIX="/usr/local"

# ========================================
# Parse options
# ========================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Usage: $0 [--prefix /install/path]"
            exit 1
            ;;
        *)
            shift
            ;;
    esac
done

MANIFEST="$PREFIX/git-source.install-manifest"

# ========================================
# Check for manifest
# ========================================
if [ ! -f "$MANIFEST" ]; then
    echo "Error: No installation manifest found at $MANIFEST"
    echo "Cannot uninstall without knowing installed files."
    exit 1
fi

# ========================================
# Remove installed files
# ========================================
echo "Removing installed files listed in: $MANIFEST"
while IFS= read -r file; do
    if [ -f "$file" ]; then
        rm -f "$file"
        echo "Removed: $file"
    else
        echo "Skipped (not found): $file"
    fi
done < "$MANIFEST"

rm -f "$MANIFEST"
echo "Removed manifest: $MANIFEST"

# ========================================
# Optional: update man database
# ========================================
if command -v mandb >/dev/null 2>&1; then
    echo "Updating man database..."
    mandb >/dev/null 2>&1 || true
fi

# ========================================
# Summary
# ========================================
echo
echo "Uninstallation complete!"
echo "If you added $PREFIX/bin to your PATH manually, you can remove it if desired."
echo "If you added $PREFIX/share/man to MANPATH, you can remove that as well."
