set -e
source "$(dirname "$0")/build_systems/mxe_common.sh"

# =============================================
# mxe_cmake.sh
# Functions for querying CMake build options and dependencies
# for MXE cross-build environment.
# To be sourced by generate_mxe_mk.sh
# =============================================

CMAKE="$(command -v cmake)"
SOURCE_DIR=$SOURCE_ROOT
BUILD_DIR="$SOURCE_DIR/build"

decho "Cmake Source folder: $SOURCE_DIR"
decho "CMake build folder: $BUILD_DIR"

vecho "Using CMake: $CMAKE"

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

    check_cmake_version "$src_dir"

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
    local internal_targets_with_sources=()

    decho "Query CMake dependencies ..."
    iecho "Parsing ${#files[@]} CMake files for dependencies..."

    for file in "${files[@]}"; do
        [[ -z "$file" || ! -f "$file" ]] && continue

        # Collapse multi-line commands to a single line
        local content
        content=$(awk 'BEGIN {RS=""; ORS="\n"} {gsub(/\r/,""); gsub(/\n[ \t]*/," "); print}' "$file")

        # 1) Detect internal targets that contain source files (.c, .cpp, .cc)
        while read -r t; do
            # Extract everything inside parentheses
            line=$(echo "$content" | grep -ioE "(add_library|add_executable|add_.*_plugin)[[:space:]]*\([[:space:]]*$t[^\)]*\)")
            if [[ $line =~ \.c(pp)?|\.cc ]]; then
                internal_targets_with_sources+=("$t")
            fi
        done < <(echo "$content" \
            | grep -ioE '(add_library|add_executable|add_.*_plugin)[[:space:]]*\([[:space:]]*([A-Za-z0-9_]+)' \
            | sed -E 's/(add_library|add_executable|add_.*_plugin)[[:space:]]*\([[:space:]]*//I')

        # 2) Extract find_package/find_dependency
        while read -r dep; do
            dep_list+=("$dep")
        done < <(echo "$content" \
            | grep -ioE 'find_(package|dependency)[[:space:]]*\([[:space:]]*([A-Za-z0-9_:]+)' \
            | sed -E 's/find_(package|dependency)[[:space:]]*\([[:space:]]*//I')

        # 3) Extract target_link_libraries but skip internal targets with sources
        while read -r lib; do
            local skip=false
            for t in "${internal_targets_with_sources[@]}"; do
                [[ "$lib" == "$t" ]] && skip=true && break
            done
            $skip || dep_list+=("$lib")
        done < <(echo "$content" \
            | grep -ioE 'target_link_libraries[[:space:]]*\([[:space:]]*([A-Za-z0-9_:]+)' \
            | sed -E 's/target_link_libraries[[:space:]]*\([[:space:]]*//I')
    done

    # Clean up: remove variables, duplicates, empty lines
    DEPENDENCIES=($(printf '%s\n' "${dep_list[@]}" | sed 's/\${[^}]*}//g' | awk 'NF' | sort -u))

    final_deps=()
    for dep in "${DEPENDENCIES[@]}"; do
        # Look for source files in the project directory
        if ! find "$SOURCE_ROOT" -type f \( -iname "${dep}.cpp" -o -iname "${dep}.c" -o -iname "${dep}.cc" \) | grep -q .; then
            final_deps+=("$dep")
        fi
    done
    DEPENDENCIES=("${final_deps[@]}")

    MXE_DEPENDENCIES=($(alias_to_pkg "${DEPENDENCIES[@]}"))

    decho "Detected external CMake dependencies: ${DEPENDENCIES[*]}"
    decho "Detected external CMake dependencies (alias_to_pkg): ${MXE_DEPENDENCIES[*]}"
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

check_cmake_version() {
    local src_dir="$1"
    local required=$(grep -i 'CMAKE_MINIMUM_REQUIRED' "$src_dir/CMakeLists.txt" | head -n1 | sed -E 's/.*VERSION[[:space:]]+([0-9]+\.[0-9]+).*/\1/I')
    if [[ -n "$required" ]]; then
        local current=$(cmake --version | head -n1 | awk '{print $3}')
        # Simple comparison: convert versions to zero-padded numbers for numeric comparison
        vercomp() { printf '%03d%03d%03d\n' $(echo "$1" | tr '.' ' '); }
        if [[ $(vercomp "$current") -lt $(vercomp "$required") ]]; then
            eecho "$(bold_bright_red "Error: Project requires CMake $required or higher. You have $current.")"
            exit 1
        fi
    fi
}
