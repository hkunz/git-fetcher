source "$(dirname "$0")/build_systems/mxe_common.sh"

# =============================================
# mxe_cmake.sh
# Functions for querying CMake build options and dependencies
# for MXE cross-build environment.
# To be sourced by generate_mxe_mk.sh
# =============================================

# =============================================
# Query CMake options and dependencies
# =============================================
mxe_query_build() {
    TMP_BUILD_DIR="$SOURCE_ROOT/build"
    decho "CMake build folder: $TMP_BUILD_DIR"
    query_build_options "$SOURCE_ROOT" "$TMP_BUILD_DIR"

    # Collect files to parse for dependencies
    FILES_TO_PARSE=()
    [[ -n "$MAIN_FILE" ]] && FILES_TO_PARSE+=("$TMP_DIR/$MAIN_FILE")
    if [[ -n "$OTHER_FILES" ]]; then
        while IFS= read -r f; do
            [[ -n "$f" && -f "$TMP_DIR/$f" ]] && FILES_TO_PARSE+=("$TMP_DIR/$f")
        done <<< "$OTHER_FILES"
    fi
    query_dependencies "${FILES_TO_PARSE[@]}"
    decho "Detected dependencies:"
    for dep in "${DEPENDENCIES[@]}"; do
        decho --no-prefix "  $dep"
    done
    decho --no-prefix "}"
}

# =============================================
# Query CMake for all real options
# =============================================
query_build_options() {
    local src_dir="$1"
    local build_dir="$2"

    mkdir -p "$build_dir"
    cd "$build_dir" || return 1

    decho "Query CMake build options ..."

    if [[ "$DEBUG" == true ]]; then  # Configure to populate cache
        cmake "$src_dir" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON || true
    else
        cmake "$src_dir" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON > /dev/null 2>&1 || true
    fi
    # Only user-configurable options: BOOL and project-specific STRING/PATH
    if [[ "$DEBUG" == true ]]; then
        mapfile -t BUILD_OPTIONS < <(
            cmake -LAH "$build_dir" \
            | grep -E '^[A-Z0-9_]+:BOOL=' \
            | sed 's/:.*=/=/'
        )
    else
        mapfile -t BUILD_OPTIONS < <(
            cmake -LAH "$build_dir" 2>/dev/null \
            | grep -E '^[A-Z0-9_]+:BOOL=' \
            | sed 's/:.*=/=/'
        )
    fi
    BUILD_OPTIONS=($(printf '%s\n' "${BUILD_OPTIONS[@]}" | sort -u))  # Deduplicate
    decho "MXE-relevant CMake options in $build_dir"
    for opt in "${BUILD_OPTIONS[@]}"; do
        decho --no-prefix "  $opt"
    done
    decho --no-prefix "}"
}

# =============================================
# Extract all CMake dependencies from CMakeLists.txt and .cmake files
# =============================================
query_dependencies() {
    local files=("$@")
    local dep_list=()
    num_files=${#files[@]}
    decho "Query CMake dependencies ..."
    iecho "Parsing $num_files CMake files for dependencies..."

    for file in "${files[@]}"; do
        [[ -z "$file" || ! -f "$file" ]] && continue

        # Use grep + perl regex to extract the first argument of find_package/find_dependency
        while IFS= read -r dep; do
            dep_list+=("$dep")
        done < <(grep -i 'find_\(package\|dependency\)' "$file" | \
                 sed -E 's/^[[:space:]]*find_(package|dependency)[[:space:]]*\([[:space:]]*([^ )]+).*/\2/I')
    done
    # Deduplicate and sort
    DEPENDENCIES=($(printf '%s\n' "${dep_list[@]}" | sed 's/\${[^}]*}//g' | awk 'NF' | sort -u))
    MXE_DEPENDENCIES=($(alias_to_pkg "${DEPENDENCIES[@]}"))
    decho "Detected CMake dependencies: ${DEPENDENCIES[*]}"
    decho "Detected CMake dependencies (alias_to_pkg): ${MXE_DEPENDENCIES[*]}"
}

mxe_generate_pc_file_vars() {
    decho "Missing .pc file so generating..."
    decho "Generating pkg-config variables from CMake files ..."

    REQUIRES=($(printf "%s\n" "${MXE_DEPENDENCIES[@]}" | grep -v '^meson-wrapper$' | sort -u))
    REQUIRES="${REQUIRES[*]}"
    REQUIRES_PRIVATE=""  

    decho "REQUIRES='$REQUIRES'"
    decho "REQUIRES_PRIVATE='$REQUIRES_PRIVATE'"

    LIBS=()
    LIBS_PRIVATE=()

    decho "Looking for tmp-$PACKAGE_NAME-* in $MXE_ROOT"
    tmp_dir=$(find "$MXE_ROOT" -maxdepth 1 -type d -name "tmp-$PACKAGE_NAME-*" | sort -r | head -1)
    
    if [[ -n "$tmp_dir" ]]; then
        decho "Found MXE tmp build dir: $tmp_dir"
        while IFS= read -r lib; do
            [[ -f "$lib" ]] || continue
            libname=$(basename "$lib")
            libname=${libname#lib}
            libname=${libname%%.*}
            decho "Found library file: $lib -> libname='$libname'"

            if [[ "$libname" == "$PACKAGE_NAME" ]]; then
                LIBS+=("-l$libname")
            else
                LIBS_PRIVATE+=("-l$libname")
            fi
        done < <(find "$tmp_dir" -type f -name "lib*.a" -o -name "lib*.so")
        PC_FILE="$(find_pc_file $PACKAGE_NAME "$MXE_ROOT/usr/$MXE_TARGET/lib")"
        decho "Detect in $MXE_ROOT/usr/$MXE_TARGET"
        decho "Detected PC_FILE=$PC_FILE"
    else
        decho "No MXE tmp build dir found, fallback to $PREFIX/$TARGET/lib/"
        shopt -s nullglob
        files=("$PREFIX/$TARGET/lib/"*.a "$PREFIX/$TARGET/lib/"*.so)
        decho "Found files in fallback lib dir: ${#files[@]}"
        for lib in "${files[@]}"; do
            [[ -f "$lib" ]] || continue
            libname=$(basename "$lib")
            libname=${libname#lib}
            libname=${libname%%.*}
            LIBS+=("-l$libname")
            decho "Adding fallback library: $libname"
        done
        shopt -u nullglob
    fi

    LIBS="${LIBS[*]}"
    LIBS_PRIVATE="${LIBS_PRIVATE[*]}"
    decho "LIBS=$LIBS"
    decho "LIBS_PRIVATE=$LIBS_PRIVATE"

    # CFLAGS
    CFLAGS=()
    CFLAGS_PRIVATE=()
    public_include="$SOURCE_ROOT/include"
    decho "Looking for public include dir: $public_include"
    if [[ -d "$public_include" ]]; then
        CFLAGS+=("\$(PREFIX)/\$(TARGET)/include")
        decho "Added public include: ${CFLAGS[*]}"
    else
        decho "No public include dir found at $public_include"
    fi

    CFLAGS="${CFLAGS[*]}"
    CFLAGS_PRIVATE="${CFLAGS_PRIVATE[*]}"
    if [[ -z "$CFLAGS" ]]; then
        CFLAGS="\$(PREFIX)/\$(TARGET)/include"
        decho "[DEBUG] CFLAGS was empty, using fallback: $CFLAGS"
    fi
    decho "Final CFLAGS=$CFLAGS"
    decho "Final CFLAGS_PRIVATE=$CFLAGS_PRIVATE"
}