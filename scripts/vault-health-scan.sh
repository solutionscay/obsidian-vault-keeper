#!/usr/bin/env bash
# vault-health-scan.sh - Quick vault health diagnostics
# Usage: bash vault-health-scan.sh /path/to/vault

set -euo pipefail

VAULT_DIR="${1:-.}"

if [ ! -d "$VAULT_DIR" ]; then
    echo "Error: $VAULT_DIR is not a directory"
    exit 1
fi

VAULT_DIR=$(cd "$VAULT_DIR" && pwd -P)
VAULT_CONFIG="$VAULT_DIR/VAULT.md"

if [ ! -d "$VAULT_DIR/.obsidian" ]; then
    echo "Warning: No .obsidian/ directory found. This might not be an Obsidian vault."
fi

read_config_paths() {
    local key=$1

    [ -f "$VAULT_CONFIG" ] || return 0

    awk -v wanted="$key" '
        /^##[[:space:]]+Exclusions[[:space:]]*$/ { in_section=1; in_yaml=0; current=""; next }
        in_section && /^##[[:space:]]/ { exit }
        !in_section { next }
        /^```yaml[[:space:]]*$/ { in_yaml=1; next }
        in_yaml && /^```[[:space:]]*$/ { in_yaml=0; current=""; next }
        !in_yaml { next }
        /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/ {
            current=$0
            sub(/^[[:space:]]*/, "", current)
            sub(/:.*/, "", current)
            next
        }
        current == wanted && /^[[:space:]]*-[[:space:]]+/ {
            value=$0
            sub(/^[[:space:]]*-[[:space:]]+/, "", value)
            sub(/[[:space:]]+#.*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            if ((value ~ /^".*"$/) || (value ~ /^\047.*\047$/)) {
                value=substr(value, 2, length(value)-2)
            }
            if (value != "") print value
        }
    ' "$VAULT_CONFIG"
}

add_scan_exclusion() {
    local path=$1

    path=${path#./}
    path=${path%/}

    if [ -z "$path" ] || [ "$path" = "." ] || [[ "$path" = /* ]] ||
       [[ "/$path/" = *"/../"* ]]; then
        echo "Warning: Ignore unsafe exclusion path: $1" >&2
        return
    fi

    SCAN_EXCLUSIONS+=("$path")
}

SCAN_EXCLUSIONS=()
for path in .obsidian .git .trash node_modules; do
    add_scan_exclusion "$path"
done

mapfile -t CONFIG_EXCLUDED_PATHS < <(read_config_paths excluded_paths)
if [ "${#CONFIG_EXCLUDED_PATHS[@]}" -eq 0 ]; then
    mapfile -t CONFIG_EXCLUDED_PATHS < <(read_config_paths exclusions)
fi
mapfile -t CONFIG_READ_ONLY_PATHS < <(read_config_paths read_only_paths)

for path in "${CONFIG_EXCLUDED_PATHS[@]}" "${CONFIG_READ_ONLY_PATHS[@]}"; do
    add_scan_exclusion "$path"
done

FIND_PRUNE=()
for path in "${SCAN_EXCLUSIONS[@]}"; do
    full_path="$VAULT_DIR/$path"
    if [ "${#FIND_PRUNE[@]}" -gt 0 ]; then
        FIND_PRUNE+=( -o )
    fi
    FIND_PRUNE+=( -path "$full_path" )
done

NOTE_FILES=()
if [ "${#FIND_PRUNE[@]}" -gt 0 ]; then
    mapfile -d '' -t NOTE_FILES < <(
        find "$VAULT_DIR" \( "${FIND_PRUNE[@]}" \) -prune -o \
            -type f -name "*.md" -print0 | sort -z
    )
else
    mapfile -d '' -t NOTE_FILES < <(
        find "$VAULT_DIR" -type f -name "*.md" -print0 | sort -z
    )
fi

note_body() {
    awk '
        NR == 1 && $0 == "---" { in_frontmatter=1; next }
        in_frontmatter && $0 == "---" { in_frontmatter=0; next }
        in_frontmatter { next }
        { print }
    ' "$1"
}

echo "=== Vault Health Scan ==="
echo "Vault: $VAULT_DIR"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

TOTAL_NOTES=${#NOTE_FILES[@]}
echo "Total notes: $TOTAL_NOTES"

echo ""
echo "=== Notes by Folder ==="
declare -A FOLDER_COUNTS=()
ROOT_NOTES=0
for file in "${NOTE_FILES[@]}"; do
    relative_path=${file#"$VAULT_DIR"/}
    if [[ "$relative_path" == */* ]]; then
        folder=${relative_path%%/*}
        FOLDER_COUNTS["$folder"]=$(( ${FOLDER_COUNTS["$folder"]:-0} + 1 ))
    else
        ROOT_NOTES=$((ROOT_NOTES + 1))
    fi
done

if [ "${#FOLDER_COUNTS[@]}" -gt 0 ]; then
    while IFS= read -r folder; do
        echo "  $folder/: ${FOLDER_COUNTS[$folder]}"
    done < <(printf '%s\n' "${!FOLDER_COUNTS[@]}" | sort)
fi
echo "  (root): $ROOT_NOTES"

echo ""
echo "=== Frontmatter Check ==="
NO_FM=0
HAS_FM=0
for file in "${NOTE_FILES[@]}"; do
    if head -n 1 "$file" 2>/dev/null | grep -q '^---$'; then
        HAS_FM=$((HAS_FM + 1))
    else
        NO_FM=$((NO_FM + 1))
    fi
done
echo "  With frontmatter: $HAS_FM"
echo "  Without frontmatter: $NO_FM"

echo ""
echo "=== Content Check ==="
EMPTY=0
STUB=0
for file in "${NOTE_FILES[@]}"; do
    body_chars=$(note_body "$file" | tr -d '[:space:]' | wc -m)
    body_words=$(note_body "$file" | wc -w)
    if [ "$body_chars" -lt 20 ]; then
        EMPTY=$((EMPTY + 1))
    elif [ "$body_words" -lt 100 ]; then
        STUB=$((STUB + 1))
    fi
done
echo "  Empty notes (<20 non-whitespace body characters): $EMPTY"
echo "  Stub notes (<100 body words, excluding empty notes): $STUB"

echo ""
echo "=== Link Count (baseline; no broken-link detection) ==="
ALL_LINKS=$(
    for file in "${NOTE_FILES[@]}"; do
        grep -oh '\[\[[^]]*\]\]' -- "$file" 2>/dev/null || true
    done | sed 's/\[\[//;s/\]\]//;s/|.*//' | sort -u | sed '/^$/d' | wc -l
)
echo "  Unique wikilink targets: $ALL_LINKS"

echo ""
echo "=== Tag Count (baseline; raw #hashtag strings, may include anchors) ==="
ALL_TAGS=$(
    for file in "${NOTE_FILES[@]}"; do
        grep -oh '#[a-zA-Z][a-zA-Z0-9_/\-]*' -- "$file" 2>/dev/null || true
    done | sort -u | sed '/^$/d' | wc -l
)
echo "  Unique tags: $ALL_TAGS"

echo ""
echo "=== Configuration ==="
if [ -f "$VAULT_CONFIG" ]; then
    echo "  VAULT.md: found"
else
    echo "  VAULT.md: MISSING (run Vault Keeper to generate one)"
fi

if [ -d "$VAULT_DIR/.git" ]; then
    LAST_COMMIT=$(cd "$VAULT_DIR" && git log -1 --format="%ar" 2>/dev/null || echo "unknown")
    echo "  Git: initialized (last commit: $LAST_COMMIT)"
else
    echo "  Git: not initialized (a no-git vault can use external_archive for snapshots)"
fi

echo ""
echo "=== Scan Complete ==="
