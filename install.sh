#!/usr/bin/env bash
# install.sh — Install git-source as a wrapper pointing to repo

set -e

# ========================================
# Default install prefix
# ========================================
PREFIX="/usr/local"
MANIFEST=""

# ========================================
# Parse options
# ========================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--prefix /install/path]"
            exit 1
            ;;
    esac
done

BIN_DIR="$PREFIX/bin"
MAN_DIR="$PREFIX/share/man/man1"
MANIFEST="$PREFIX/git-source.install-manifest"

REPO_ROOT="$(pwd)"  # The original git-fetcher repository root
SCRIPT_SRC="$REPO_ROOT/git-source.sh"

# ========================================
# Check that we are in project root
# ========================================
if [ ! -f "$SCRIPT_SRC" ]; then
    echo "Error: git-source.sh not found in current directory. Run from repo root."
    exit 1
fi

# ========================================
# Create directories if missing
# ========================================
mkdir -p "$BIN_DIR"
mkdir -p "$MAN_DIR"

# ========================================
# Install wrapper for git-source
# ========================================
WRAPPER="$BIN_DIR/git-source"

cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
# Wrapper to run git-source from the original repository
ROOT_DIR="$REPO_ROOT"
SCRIPT="\$ROOT_DIR/git-source.sh"
if [ ! -f "\$SCRIPT" ]; then
    echo "Error: git-source.sh not found in original repo at \$ROOT_DIR"
    exit 1
fi
exec "\$SCRIPT" "\$@"
EOF

chmod +x "$WRAPPER"
echo "$WRAPPER" > "$MANIFEST"
echo "Installed wrapper: $WRAPPER -> $SCRIPT_SRC"

# ========================================
# Install wrapper for gsrc
# ========================================
GSRC_WRAPPER="$BIN_DIR/gsrc"
ln -sf "$WRAPPER" "$GSRC_WRAPPER"
echo "$GSRC_WRAPPER" >> "$MANIFEST"
echo "Installed wrapper: $GSRC_WRAPPER -> $WRAPPER"

# ========================================
# Install man page
# ========================================
if [ -f man/git-source.1 ]; then
    install -m 644 man/git-source.1 "$MAN_DIR/git-source.1"
    echo "$MAN_DIR/git-source.1" >> "$MANIFEST"
    echo "Installed man page: $MAN_DIR/git-source.1"
else
    echo "Warning: man/git-source.1 not found. Skipping man page installation."
fi

# ========================================
# Optional: Update man database
# ========================================
if command -v mandb >/dev/null 2>&1; then
    echo "Updating man database..."
    mandb >/dev/null 2>&1 || true
fi

# ========================================
# Summary
# ========================================
echo
echo "Installation complete! Installed files recorded in: $MANIFEST"
echo "Add $BIN_DIR to your PATH if not already included:"
echo "  export PATH=\"$BIN_DIR:\$PATH\""
echo
echo "You can now run:"
echo "  gsrc -h"
echo "  git-source -h"
echo "  man git-source"

# Optional MXE integration tip
MXE_SUGGESTED="/path/to/your/mxe"  # fallback generic path

# Base locations to search for MXE
likely_dirs=(
    "$HOME/mxe"
    "$HOME/workspace/mxe"
    "$HOME/projects/mxe"
    "$HOME/source/mxe"
    "$HOME/dev/mxe"
    "$HOME/code/mxe"
    "/opt/mxe"
    "/dev/mxe"
    "/usr/local/mxe"
)

# Detect existing MXE installation
for base in "${likely_dirs[@]}"; do
    for dir in "$base"*; do
        if [[ -d "$dir/src" ]]; then
            MXE_SUGGESTED="$dir"
            break 2  # stop both loops after first match
        fi
    done
done

echo
echo "Optional: to copy generated .mk files into your MXE project, set MXE_ROOT"
echo "to your MXE root directory before running the generator:"
echo
echo "  export MXE_ROOT=\"$MXE_SUGGESTED\""
echo "  export MXE_TARGET=\"x86_64-w64-mingw32.static\"  # optional override"
echo "  export GITHUB_TOKEN=\"<your_token_here>\"  # optional, avoids API rate limits"
echo
echo "Then run the generator script with:"
echo "  gsrc <repository> --generate-mxe-makefile"
echo "This will copy the generated .mk files into \$MXE_ROOT/src/ automatically."
