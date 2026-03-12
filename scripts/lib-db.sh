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
    local url="$1"
    local version="$2"
    local archive="$3"
    local sha="$4"

    init_db
    tmp=$(mktemp)
    jq --arg url "$url" \
       --arg version "$version" \
       --arg archive "$archive" \
       --arg sha "$sha" \
       '.[$url] = {latest_tag: $version, archive: $archive, sha256: $sha}' "$DB_FILE" > "$tmp"
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
