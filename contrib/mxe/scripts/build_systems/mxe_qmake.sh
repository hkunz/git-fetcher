set -e
source "$(dirname "$0")/build_systems/mxe_common.sh"

# =============================================
# mxe_qmake.sh
# Functions for querying QMake build options and dependencies
# for MXE cross-build environment.
# To be sourced by generate_mxe_mk.sh
# =============================================

mxe_query_build() {
    TMP_BUILD_DIR="$SOURCE_ROOT/build-qmake"
    # check_qmake_version "$SOURCE_ROOT"
    # TODO
    decho "qmake build folder: $TMP_BUILD_DIR"
    detect_qmake_subfolder "$SOURCE_ROOT"
    decho "qmake subfolder: '${PKG_SUBFOLDER}'"
    query_build_options "$SOURCE_ROOT" "$TMP_BUILD_DIR"
    query_dependencies "$SOURCE_ROOT" "$TMP_BUILD_DIR"
    MXE_DEPENDENCIES=("qtbase" "${DEPENDENCIES[@]}")
}

# =============================================
# Query all real options
# =============================================
query_build_options() {
    local src_dir="$1"
    local build_dir="$2"  # unused but kept for consistency
    BUILD_OPTIONS=()
    decho "Query qmake build options ..."  # TODO
}

# =============================================
# Query qmake for all dependencies
# =============================================
query_dependencies() {
    local src_dir="$1"
    local build_dir="$2"  # e.g., $TMP_BUILD_DIR
    DEPENDENCIES=("qtsvg") # TODO
    MXE_DEPENDENCIES=($(alias_to_pkg "${DEPENDENCIES[@]}"))
}

# =============================================
# qmake: Determine the source subfolder inside the extracted archive containing qmake.build if it's not in the source root
# Example should be PKG_SUBFOLDER="" for libxml++5.mk and PKG_SUBFOLDER='/libvmaf' for vmaf.mk
# =============================================
detect_qmake_subfolder() {
    local src_root="$1"
    local main_file="$2"
    decho "detect qmake subfolder: src_root='$src_root', main_file='$main_file'"
    # TODO
}

# ===================================================
# Generate values needed for GENERATE_PC
# ===================================================
mxe_generate_pc_file_vars() {
    REQUIRES=($(printf "%s " "${DEPENDENCIES[@]}" | tr ' ' '\n' | grep -v '^qmake-wrapper$' | sort -u))
    REQUIRES="${REQUIRES[*]}"
    # TODO
}

check_qmake_version() {
    local src_dir="$1"
    # TODO
}
