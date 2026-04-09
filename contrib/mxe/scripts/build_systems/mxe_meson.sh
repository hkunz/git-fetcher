set -e
source "$(dirname "$0")/build_systems/mxe_common.sh"

# =============================================
# mxe_meson.sh
# Functions for querying Meson build options and dependencies
# for MXE cross-build environment.
# To be sourced by generate_mxe_mk.sh
# =============================================

mxe_query_build() {
    TMP_BUILD_DIR="$SOURCE_ROOT/build-meson"
    # check_meson_version "$SOURCE_ROOT"
    decho "Meson build folder: $TMP_BUILD_DIR"
    detect_meson_subfolder "$SOURCE_ROOT"
    decho "Meson subfolder: '${PKG_SUBFOLDER}'"
    query_build_options "$SOURCE_ROOT" "$TMP_BUILD_DIR"
    query_dependencies "$SOURCE_ROOT" "$TMP_BUILD_DIR"
    MXE_DEPENDENCIES=("meson-wrapper" "${DEPENDENCIES[@]}")
}

# =============================================
# Query all real options
# =============================================
query_build_options() {
    local src_dir="$1"
    local build_dir="$2"  # unused but kept for consistency
    BUILD_OPTIONS=()
    decho "Query Meson build options ..."

    if [[ -n "$OPTIONS_FILE" ]]; then
        local full_path="$TMP_DIR/$OPTIONS_FILE"
        if [[ -f "$full_path" ]]; then
            # Collapse multiline 'option(...)' blocks into a single line
            local collapsed
            collapsed=$(awk 'BEGIN { ORS=""; inblock=0 }
                { gsub(/[[:space:]]+/, " ") }
                /^option\(/ { inblock=1; printf "%s", $0; next }
                inblock { printf " %s", $0 }
                /\)/ && inblock { print ""; inblock=0 }' "$full_path")
            decho "Raw Options: ${collapsed:0:100}"
            # Extract boolean options and set them as name=value
            BUILD_OPTIONS=$(echo "$collapsed" \
                | sed 's/option(/\noption(/g' \
                | sed -En "s/option\('([^']+)',[^)]*value:[[:space:]]*(true|false)[^)]*\)/\1=\2/p" \
                | tr '\n' ' ')
            BUILD_OPTIONS=($BUILD_OPTIONS)  # convert string to array
            iecho "Detected Meson build options from $OPTIONS_FILE"
            decho "Build options: {"
            for opt in "${BUILD_OPTIONS[@]}"; do
                decho --no-prefix "  $opt"
            done
            decho --no-prefix "}"
        else
            wecho "OPTIONS_FILE not found: $full_path"
        fi
    else
        wecho "No OPTIONS_FILE detected for Meson"
    fi
}

# =============================================
# Query Meson for all dependencies
# =============================================
query_dependencies() {
    local src_dir="$1"
    local build_dir="$2"  # e.g., $TMP_BUILD_DIR
    DEPENDENCIES=()

    mkdir -p "$build_dir"
    # Configure Meson build directory (no install, silent)
    meson setup "$build_dir" "$src_dir" --backend=ninja > /dev/null 2>&1 || true

    if command -v meson >/dev/null 2>&1; then
        decho "Query Meson dependencies ..."
        local deps_json
        deps_json=$(meson introspect "$build_dir" --dependencies 2>/dev/null | sed -n '/^\[/,$p')   # Skip any warnings before JSON

        if [[ -n "$deps_json" ]]; then
            # Parse dependency names and filter out internal depXXX
            mapfile -t DEPENDENCIES < <(
                echo "$deps_json" | jq -r '.[].name' | grep -Ev '^dep[0-9]+$' || true
            )
            # Deduplicate
            DEPENDENCIES=($(printf '%s\n' "${DEPENDENCIES[@]}" | sort -u))
            MXE_DEPENDENCIES=($(alias_to_pkg "${DEPENDENCIES[@]}"))
        fi
        decho "Detected Meson dependencies: ${DEPENDENCIES[*]}"
        decho "Detected Meson dependencies (alias_to_pkg): ${MXE_DEPENDENCIES[*]}"
    else
        wecho "Meson not found; cannot query dependencies"
    fi
}

# =============================================
# Meson: Determine the source subfolder inside the extracted archive containing meson.build if it's not in the source root
# Example should be PKG_SUBFOLDER="" for libxml++5.mk and PKG_SUBFOLDER='/libvmaf' for vmaf.mk
# =============================================
detect_meson_subfolder() {
    local src_root="$1"
    local main_file="$2"
    decho "detect meson subfolder: src_root='$src_root', main_file='$main_file'"
    # If main_file is provided, use it
    if [[ -n "$main_file" && -f "$main_file" ]]; then
        PKG_SUBFOLDER="$(dirname "$main_file")"
    elif [[ -f "$src_root/meson.build" ]]; then
        PKG_SUBFOLDER=""  # meson.build in root → empty subfolder
    else
        # Find meson.build files only 1 level deep
        main_file=$(find "$src_root" -mindepth 1 -maxdepth 2 -type f -name "meson.build" | head -1)
        if [[ -n "$main_file" ]]; then
            PKG_SUBFOLDER="$(dirname "$main_file")"
        else
            wecho "Warning: no meson.build detected in $src_root"
            PKG_SUBFOLDER=""
        fi
    fi
    PKG_SUBFOLDER="${PKG_SUBFOLDER#$src_root}"  # Remove source root prefix
    [[ "$PKG_SUBFOLDER" == "" || "$PKG_SUBFOLDER" == "/" ]] && PKG_SUBFOLDER=""  # Root → empty
    [[ -n "$PKG_SUBFOLDER" && "${PKG_SUBFOLDER:0:1}" != "/" ]] && PKG_SUBFOLDER="/$PKG_SUBFOLDER"  # Ensure leading slash if non-empty
    decho "PKG_SUBFOLDER final='$PKG_SUBFOLDER'"
}

# ===================================================
# Generate values needed for GENERATE_PC
# ===================================================
mxe_generate_pc_file_vars() {

    REQUIRES=($(printf "%s " "${DEPENDENCIES[@]}" | tr ' ' '\n' | grep -v '^meson-wrapper$' | sort -u))
    REQUIRES="${REQUIRES[*]}"

    REQUIRES_PRIVATE=""  # empty unless known
    decho "REQUIRES='$REQUIRES'"
    decho "REQUIRES_PRIVATE='$REQUIRES_PRIVATE'"

    LIBS=()
    LIBS_PRIVATE=()

    decho "Looking for tmp-$PACKAGE_NAME-* in $MXE_ROOT"
    tmp_dir=$(find "$MXE_ROOT" -maxdepth 1 -type d -name "tmp-$PACKAGE_NAME-*" | sort -r | head -1)

    if [[ -n "$tmp_dir" ]]; then
        decho "Found MXE tmp build dir: $tmp_dir"
        # Scan all libs inside tmp_dir recursively
        while IFS= read -r lib; do
            [[ -f "$lib" ]] || continue
            libname=$(basename "$lib")
            libname=${libname#lib}      # remove lib prefix
            libname=${libname%%.*}      # remove extension

            # Heuristic: main library is public, rest private
            if [[ "$libname" == "vmaf" ]]; then
                LIBS+=("-l$libname")
            else
                LIBS_PRIVATE+=("-l$libname")
            fi
            decho "Found lib: $lib -> $([[ "$libname" == "vmaf" ]] && echo "public" || echo "private")"
        done < <(find "$tmp_dir" -type f -name "lib*.a" -o -name "lib*.so")
        PC_FILE="$(find_pc_file $PACKAGE_NAME "$MXE_ROOT/usr/$MXE_TARGET/lib")"
        decho "Detect in $MXE_ROOT/usr/$MXE_TARGET"
        decho "Detected PC_FILE=$PC_FILE"
    else
        decho "No MXE tmp build dir found, fallback to $PREFIX/$TARGET/lib/"
        for lib in "$PREFIX/$TARGET/lib/"*.a "$PREFIX/$TARGET/lib/"*.so; do
            [[ -f "$lib" ]] || continue
            libname=$(basename "$lib")
            libname=${libname#lib}
            libname=${libname%%.*}
            LIBS+=("-l$libname")
        done
    fi

    LIBS="${LIBS[*]}"
    LIBS_PRIVATE="${LIBS_PRIVATE[*]}"
    decho "LIBS=$LIBS"
    decho "LIBS_PRIVATE=$LIBS_PRIVATE"

    CFLAGS=()
    CFLAGS_PRIVATE=()

    public_include="$SOURCE_ROOT$PKG_SUBFOLDER/include"
    if [[ -d "$public_include" ]]; then
        CFLAGS+=("\$(PREFIX)/\$(TARGET)/$(basename "$public_include")")
        decho "Public include: \$(PREFIX)/\$(TARGET)/$(basename "$public_include")"
    fi

    CFLAGS=("\$(PREFIX)/\$(TARGET)/include")
    CFLAGS="${CFLAGS[*]}"
    CFLAGS_PRIVATE="${CFLAGS_PRIVATE[*]}"
    decho "Final CFLAGS=$CFLAGS"
    decho "Final CFLAGS_PRIVATE=$CFLAGS_PRIVATE"
}

check_meson_version() {
    local src_dir="$1"
    if ! command -v meson >/dev/null 2>&1; then
        echo "[ERROR] Meson not found; please install it."
        exit 1
    fi
    local required=$(grep -i 'meson_version' "$src_dir/meson.build" | head -n1 | sed -E "s/.*meson_version:[[:space:]]*'(>=|=)?([0-9\.]+)'.*/\2/I")
    if [[ -n "$required" ]]; then
        local current=$(meson --version)
        vercomp() { printf '%03d%03d%03d\n' $(echo "$1" | tr '.' ' '); }
        if [[ $(vercomp "$current") -lt $(vercomp "$required") ]]; then
            echo "[ERROR] Project requires Meson $required or higher. You have $current."
            exit 1
        fi
    fi
}
