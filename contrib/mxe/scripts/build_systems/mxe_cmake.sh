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
}

mxe_generate_pc_file_vars() {
    # TODO
    LIBS=$(printf ' -l%s' "${DEPENDENCIES[@]}" | sed -E 's/lib//Ig' | cut -c2-)
}
