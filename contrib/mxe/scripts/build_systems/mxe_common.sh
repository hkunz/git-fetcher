#!/usr/bin/env bash
# mxe_common.sh

MXE_ALIASES_JSON="$(dirname "$0")/../mappings/mxe-aliases.json"
HOST_TOOLS=("python" "cmake" "meson" "ninja" "pkg-config")

alias_to_pkg() {
    local input_array=("$@")
    local resolved=()
    local dep lower dep_resolved

    for dep in "${input_array[@]}"; do
        lower=$(echo "$dep" | tr '[:upper:]' '[:lower:]')
        # Skip host-only tools
        local skip=false
        for tool in "${HOST_TOOLS[@]}"; do
            [[ "$lower" == "$tool" ]] && skip=true && break
        done
        $skip && continue

        # jq looks for lowercase key, returns canonical name if exists, otherwise original dep
        dep_resolved=$(jq -r --arg a "$lower" '.[$a] // $a' "$MXE_ALIASES_JSON")
        resolved+=("$dep_resolved")
    done
    echo "${resolved[@]}"
}
