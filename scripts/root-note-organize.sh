#!/usr/bin/env bash
# Report root-note moves or apply them.
# Usage: root-note-organize.sh [--apply] /path/to/vault

set -euo pipefail

APPLY=false
if [ "${1:-}" = "--apply" ]; then
    APPLY=true
    shift
fi

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 [--apply] /path/to/vault" >&2
    exit 2
fi

VAULT_DIR=$(cd "$1" && pwd -P)
VAULT_CONFIG="$VAULT_DIR/VAULT.md"

if [ ! -f "$VAULT_CONFIG" ]; then
    echo "Error: VAULT.md is missing." >&2
    exit 1
fi

read_config_values() {
    local section=$1
    local key=$2

    awk -v wanted_section="$section" -v wanted="$key" '
        $0 == "## " wanted_section { in_section=1; in_yaml=0; current=""; next }
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

read_config_scalar() {
    local key=$1

    awk -v wanted="$key" '
        /^##[[:space:]]+Agent Behavior[[:space:]]*$/ { in_section=1; in_yaml=0; next }
        in_section && /^##[[:space:]]/ { exit }
        !in_section { next }
        /^```yaml[[:space:]]*$/ { in_yaml=1; next }
        in_yaml && /^```[[:space:]]*$/ { exit }
        !in_yaml { next }
        $0 ~ "^[[:space:]]*" wanted ":[[:space:]]*" {
            value=$0
            sub("^[[:space:]]*" wanted ":[[:space:]]*", "", value)
            sub(/[[:space:]]+#.*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            if ((value ~ /^".*"$/) || (value ~ /^\047.*\047$/)) {
                value=substr(value, 2, length(value)-2)
            }
            print value
            exit
        }
    ' "$VAULT_CONFIG"
}

config_scalar_defined() {
    local key=$1

    awk -v wanted="$key" '
        /^##[[:space:]]+Agent Behavior[[:space:]]*$/ { in_section=1; in_yaml=0; next }
        in_section && /^##[[:space:]]/ { exit }
        !in_section { next }
        /^```yaml[[:space:]]*$/ { in_yaml=1; next }
        in_yaml && /^```[[:space:]]*$/ { exit }
        in_yaml && $0 ~ "^[[:space:]]*" wanted ":[[:space:]]*" { found=1; exit }
        END { exit(found ? 0 : 1) }
    ' "$VAULT_CONFIG"
}

read_placement_rules() {
    awk '
        /^##[[:space:]]+Agent Behavior[[:space:]]*$/ { in_section=1; in_yaml=0; in_rules=0; next }
        in_section && /^##[[:space:]]/ { exit }
        !in_section { next }
        /^```yaml[[:space:]]*$/ { in_yaml=1; next }
        in_yaml && /^```[[:space:]]*$/ { exit }
        !in_yaml { next }
        /^[[:space:]]*placement_rules:[[:space:]]*$/ { in_rules=1; next }
        in_rules && /^[^[:space:]]/ { exit }
        in_rules && /^[[:space:]]{2}[^[:space:]][^:]*:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]+/, "", line)
            key=line
            sub(/:.*/, "", key)
            value=line
            sub(/^[^:]*:[[:space:]]*/, "", value)
            sub(/[[:space:]]+#.*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            if ((value ~ /^".*"$/) || (value ~ /^\047.*\047$/)) {
                value=substr(value, 2, length(value)-2)
            }
            if (key != "" && value != "") print key "\t" value
        }
    ' "$VAULT_CONFIG"
}

frontmatter_value() {
    local file=$1
    local key=$2

    awk -v wanted="$key" '
        NR == 1 && $0 == "---" { in_frontmatter=1; next }
        in_frontmatter && $0 == "---" { exit }
        !in_frontmatter { exit }
        $0 ~ "^" wanted ":[[:space:]]*" {
            value=$0
            sub("^" wanted ":[[:space:]]*", "", value)
            gsub(/^[\047"]|[\047"]$/, "", value)
            print value
            exit
        }
    ' "$file"
}

update_inbound_links() {
    local old_relative=$1
    local new_relative=$2
    local source_relative
    local old_link
    local new_link

    while IFS= read -r -d '' source; do
        [ "$source" = "$VAULT_DIR/$new_relative" ] && continue
        source_relative=${source#"$VAULT_DIR"/}
        is_protected_path "$source_relative" && continue
        old_link=$(realpath -m --relative-to="$(dirname "$source")" "$VAULT_DIR/$old_relative")
        new_link=$(realpath -m --relative-to="$(dirname "$source")" "$VAULT_DIR/$new_relative")
        # Read first: Perl in-place mode replaces files even without a match.
        if ! OLD_RELATIVE="$old_relative" OLD_LINK="$old_link" perl -0ne '
            $found=1 if /\[\[\Q$ENV{"OLD_RELATIVE"}\E(?=[|#\]])/;
            $found=1 if /\]\(\Q$ENV{"OLD_LINK"}\E(?=[ #)])/;
            END { exit($found ? 0 : 1) }
        ' "$source"; then
            continue
        fi
        OLD_RELATIVE="$old_relative" NEW_RELATIVE="$new_relative" \
        OLD_LINK="$old_link" NEW_LINK="$new_link" perl -0pi -e '
            my $old_relative=$ENV{"OLD_RELATIVE"};
            my $new_relative=$ENV{"NEW_RELATIVE"};
            my $old_link=$ENV{"OLD_LINK"};
            my $new_link=$ENV{"NEW_LINK"};
            s/\[\[\Q$old_relative\E(?=[|#\]])/[[$new_relative/g;
            s/\]\(\Q$old_link\E(?=[ #)])/]($new_link/g;
        ' "$source"
        if OLD_RELATIVE="$old_relative" OLD_LINK="$old_link" perl -0ne '
            $found=1 if /\[\[\Q$ENV{"OLD_RELATIVE"}\E(?=[|#\]])/;
            $found=1 if /\]\(\Q$ENV{"OLD_LINK"}\E(?=[ #)])/;
            END { exit($found ? 0 : 1) }
        ' "$source"; then
            echo "Error: An old path-qualified link remains in $source_relative" >&2
            return 1
        fi
    done < <(find_editable_notes)
}

ROOT_ALLOWED_FILES=(VAULT.md README.md)
mapfile -t CONFIG_ROOT_ALLOWED_FILES < <(
    read_config_values "Agent Behavior" root_allowed_files
)
ROOT_ALLOWED_FILES+=("${CONFIG_ROOT_ALLOWED_FILES[@]}")
declare -A ALLOWED=()
for file in "${ROOT_ALLOWED_FILES[@]}"; do
    ALLOWED["$file"]=1
done

PROTECTED_PATHS=(.obsidian .git .trash node_modules)
mapfile -t EXCLUDED_PATHS < <(read_config_values Exclusions excluded_paths)
if [ "${#EXCLUDED_PATHS[@]}" -eq 0 ]; then
    mapfile -t EXCLUDED_PATHS < <(read_config_values Exclusions exclusions)
fi
mapfile -t READ_ONLY_PATHS < <(read_config_values Exclusions read_only_paths)
REPORTS_FOLDER=$(read_config_scalar reports_folder)
if [ -z "$REPORTS_FOLDER" ]; then
    if config_scalar_defined reports_folder; then
        echo "Warning: Ignore unsafe reports_folder: empty value; use _reports/" >&2
    fi
    REPORTS_FOLDER=_reports/
else
    reports_candidate=${REPORTS_FOLDER#./}
    reports_candidate=${reports_candidate%/}
    reports_unsafe=0
    if [ -z "$reports_candidate" ] || [ "$reports_candidate" = "." ] ||
       [[ "$reports_candidate" = /* ]] || [[ "/$reports_candidate/" = *"/../"* ]]; then
        reports_unsafe=1
    else
        for protected in "${READ_ONLY_PATHS[@]}"; do
            protected=${protected#./}
            protected=${protected%/}
            [ -n "$protected" ] || continue
            if [ "$reports_candidate" = "$protected" ] ||
               [[ "$reports_candidate" == "$protected/"* ]]; then
                reports_unsafe=1
                break
            fi
        done
    fi
    if [ "$reports_unsafe" -eq 1 ]; then
        echo "Warning: Ignore unsafe reports_folder: $REPORTS_FOLDER; use _reports/" >&2
        REPORTS_FOLDER=_reports/
    else
        REPORTS_FOLDER="$reports_candidate/"
    fi
fi
PROTECTED_PATHS+=("${EXCLUDED_PATHS[@]}" "${READ_ONLY_PATHS[@]}" "$REPORTS_FOLDER")

FIND_PRUNE=()
for protected in "${PROTECTED_PATHS[@]}"; do
    protected=${protected#./}
    protected=${protected%/}
    [ -z "$protected" ] && continue
    if [[ "$protected" = /* ]] || [[ "/$protected/" = *"/../"* ]]; then
        echo "Warning: Ignore unsafe protected path: $protected" >&2
        continue
    fi
    if [ "${#FIND_PRUNE[@]}" -gt 0 ]; then
        FIND_PRUNE+=( -o )
    fi
    FIND_PRUNE+=( -path "$VAULT_DIR/$protected" )
done

find_editable_notes() {
    if [ "${#FIND_PRUNE[@]}" -gt 0 ]; then
        find "$VAULT_DIR" \( "${FIND_PRUNE[@]}" \) -prune -o \
            -type f -name '*.md' -print0
    else
        find "$VAULT_DIR" -type f -name '*.md' -print0
    fi
}

is_protected_path() {
    local relative_path=${1#./}
    local protected

    for protected in "${PROTECTED_PATHS[@]}"; do
        protected=${protected#./}
        protected=${protected%/}
        [ -z "$protected" ] && continue
        if [ "$relative_path" = "$protected" ] || [[ "$relative_path" == "$protected/"* ]]; then
            return 0
        fi
    done
    return 1
}

INBOX_FOLDER=$(read_config_scalar inbox_folder)
if [ -z "$INBOX_FOLDER" ] && [ -d "$VAULT_DIR/00-inbox" ]; then
    INBOX_FOLDER=00-inbox/
fi
INBOX_FOLDER=${INBOX_FOLDER#./}
INBOX_FOLDER=${INBOX_FOLDER%/}

declare -A PLACEMENT=()
while IFS=$'\t' read -r key value; do
    PLACEMENT["$key"]=${value%/}
done < <(read_placement_rules)

MOVED=0
DEFERRED=0
while IFS= read -r -d '' source; do
    name=$(basename "$source")
    [ -n "${ALLOWED[$name]:-}" ] && continue

    type=$(frontmatter_value "$source" type)
    status=$(frontmatter_value "$source" status)
    type_destination=${PLACEMENT["type/$type"]:-}
    status_destination=${PLACEMENT["status/$status"]:-}

    if [ -n "$type_destination" ] && [ -n "$status_destination" ] &&
       [ "$type_destination" != "$status_destination" ]; then
        echo "DEFER: $name | ambiguous placement"
        DEFERRED=$((DEFERRED + 1))
        continue
    fi

    if [ -n "$type_destination" ]; then
        destination_folder=$type_destination
        placement_reason="placement rule: type/$type"
    elif [ -n "$status_destination" ]; then
        destination_folder=$status_destination
        placement_reason="placement rule: status/$status"
    else
        destination_folder=$INBOX_FOLDER
        placement_reason="inbox fallback"
    fi
    if [ -z "$destination_folder" ]; then
        echo "DEFER: $name | inbox_folder is missing"
        DEFERRED=$((DEFERRED + 1))
        continue
    fi
    destination_folder=${destination_folder#./}
    destination_folder=${destination_folder%/}
    if [ "$destination_folder" = "." ] || [[ "$destination_folder" = /* ]] ||
       [[ "/$destination_folder/" = *"/../"* ]]; then
        echo "DEFER: $name | destination path is unsafe: $destination_folder"
        DEFERRED=$((DEFERRED + 1))
        continue
    fi
    if [ ! -d "$VAULT_DIR/$destination_folder" ]; then
        echo "DEFER: $name | destination folder is missing: $destination_folder/"
        DEFERRED=$((DEFERRED + 1))
        continue
    fi

    destination="$VAULT_DIR/$destination_folder/$name"
    if is_protected_path "$destination_folder/$name"; then
        echo "DEFER: $name | destination is protected: $destination_folder/"
        DEFERRED=$((DEFERRED + 1))
        continue
    fi
    if [ -e "$destination" ]; then
        echo "DEFER: $name | destination exists: $destination_folder/$name"
        DEFERRED=$((DEFERRED + 1))
        continue
    fi

    if [ "$APPLY" = false ]; then
        echo "PLAN: $name -> $destination_folder/$name | reason: $placement_reason"
        continue
    fi

    mv -- "$source" "$destination"
    update_inbound_links "$name" "$destination_folder/$name"
    echo "MOVE: $name -> $destination_folder/$name | reason: $placement_reason"
    MOVED=$((MOVED + 1))
done < <(find "$VAULT_DIR" -maxdepth 1 -type f -name '*.md' -print0 | sort -z)

echo "Moved notes: $MOVED"
echo "Deferred notes: $DEFERRED"
