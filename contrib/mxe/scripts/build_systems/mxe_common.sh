#!/usr/bin/env bash
# mxe_common.sh

MXE_ALIASES_JSON="$(dirname "$0")/../mappings/mxe-aliases.json"
HOST_TOOLS=(python cmake meson ninja pkgconf pkg-config doxygen sphinx git perl pythoninterp wxwidgets jni java nuke apputils imageioapphelpers ocioarchive ociobakelut ociocheck ociochecklut ocioconvert ociolutimage ociomakeclf ociomergeconfigs ocioperf ociowrite ofxplugin oglapphelpers)

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

find_pc_file() {
    local pkg_name="$1"
    local dir="$2"
    decho "Trying to find .pc file for package '$pkg_name' in $dir..."
    local pc_file=""
    if [[ -d "$dir" ]]; then
        while IFS= read -r pc; do
            [[ -f "$pc" ]] || continue
            # Only accept .pc files that contain the package name
            if [[ $(basename "$pc") == *"$pkg_name"*".pc"* ]]; then
                # Read just the first line and skip if it contains "MXE" then we know it's MXE generated and the package didn't provide any
                read -r first_line < "$pc"
                if [[ ! "$first_line" =~ MXE ]]; then
                    pc_file="$pc"
                    break
                fi
            fi
        done < <(find "$dir" -type f \( -name "*.pc" -o -name "*.pc.in" \))
    fi
    echo "$pc_file"
}
