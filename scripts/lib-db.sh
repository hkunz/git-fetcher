#!/usr/bin/env bash
set -e

DB_FILE="$ROOT_DIR/downloads/git_fetcher_db.json"

# Ensure DB exists
init_db() {
    mkdir -p "$(dirname "$DB_FILE")"
    if [[ ! -f "$DB_FILE" ]]; then
        echo "{}" > "$DB_FILE"
    fi
}

# Get an entry by URL
get_db_entry() {
    local url="$1"
    init_db
    jq -r --arg url "$url" '.[$url] // empty' "$DB_FILE"
}

# Update/add an entry
update_db() {
    local url="$1"; shift
    local tag="$1"; shift
    local branch="$1"; shift
    local ref_name="$1"; shift
    local archive_url="$1"; shift
    local archive="$1"; shift
    local sha="$1"; shift
    local package="$1"; shift
    local description="$1"; shift
    local build_system="$1"; shift
    local language="$1"

    init_db
    local tmp
    tmp=$(mktemp)
    jq --arg url "$url" \
       --arg tag "$tag" \
       --arg branch "$branch" \
       --arg ref_name "$ref_name" \
       --arg archive_url "$archive_url" \
       --arg archive "$archive" \
       --arg sha "$sha" \
       --arg package "$package" \
       --arg description "$description" \
       --arg build_system "$build_system" \
       --arg language "$language" \
       '.[$url] = {latest_tag: $tag, default_branch: $branch, ref_name: $ref_name, archive_url: $archive_url, archive: $archive, sha256: $sha, package: $package, description: $description, build_system: $build_system, language: $language}' \
       "$DB_FILE" > "$tmp"
    mv "$tmp" "$DB_FILE"
}

# Remove an entry (optional)
remove_db_entry() {
    local url="$1"
    init_db
    tmp=$(mktemp)
    jq "del(.\"$url\")" "$DB_FILE" > "$tmp"
    mv "$tmp" "$DB_FILE"
}
