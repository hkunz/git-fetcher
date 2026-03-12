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
    local tag="$2"
    local branch="$3"
    local archive_url="$4"
    local archive="$5"
    local sha="$6"
    local package="$7"
    local description="$8"

    init_db
    local tmp
    tmp=$(mktemp)
    jq --arg url "$url" \
       --arg tag "$tag" \
       --arg branch "$branch" \
       --arg archive_url "$archive_url" \
       --arg archive "$archive" \
       --arg sha "$sha" \
       --arg package "$package" \
       --arg description "$description" \
       '.[$url] = {latest_tag: $tag, default_branch: $branch, archive_url: $archive_url, archive: $archive, sha256: $sha, package: $package, description: $description}' \
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
