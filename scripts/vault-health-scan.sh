#!/usr/bin/env bash
# vault-health-scan.sh - Deterministic vault health diagnostics
# Usage: bash vault-health-scan.sh [--json] [--report] [--strict] /path/to/vault
#
# Modes:
#   (default)  human-readable report on stdout, exit 0
#   --json     machine-readable JSON on stdout instead of the human report
#   --report   also write the report envelope into <vault>/<reports_folder>/:
#              health-latest.md + health-latest.json, plus a timestamped archive
#              copy only when status is WARN/FAIL and findings changed since the
#              previous run (clean runs leave no residue)
#   --strict   exit 2 when any error-severity finding exists (default stays
#              exit 0 so existing callers and autonomous sessions are unaffected)
#
# Severity model: errors block confidence (broken links, schema violations,
# secret-shaped strings); warnings accumulate as a visible backlog (orphans,
# duplicates, staleness, misplaced root notes). The scan never modifies notes.

set -euo pipefail

JSON_MODE=0
REPORT_MODE=0
STRICT_MODE=0
VAULT_DIR="."

for arg in "$@"; do
    case "$arg" in
        --json) JSON_MODE=1 ;;
        --report) REPORT_MODE=1 ;;
        --strict) STRICT_MODE=1 ;;
        -*)
            echo "Error: unknown option: $arg" >&2
            exit 1
            ;;
        *) VAULT_DIR="$arg" ;;
    esac
done

if [ ! -d "$VAULT_DIR" ]; then
    echo "Error: $VAULT_DIR is not a directory"
    exit 1
fi

VAULT_DIR=$(cd "$VAULT_DIR" && pwd -P)
VAULT_CONFIG="$VAULT_DIR/VAULT.md"

if [ ! -d "$VAULT_DIR/.obsidian" ] && [ "$JSON_MODE" -eq 0 ]; then
    echo "Warning: No .obsidian/ directory found. This might not be an Obsidian vault."
fi

read_config_values() {
    local section=$1
    local key=$2

    [ -f "$VAULT_CONFIG" ] || return 0

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
    local section=$1
    local key=$2

    [ -f "$VAULT_CONFIG" ] || return 0

    awk -v wanted_section="$section" -v wanted="$key" '
        $0 == "## " wanted_section { in_section=1; in_yaml=0; next }
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
    local section=$1
    local key=$2

    [ -f "$VAULT_CONFIG" ] || return 1

    awk -v wanted_section="$section" -v wanted="$key" '
        $0 == "## " wanted_section { in_section=1; in_yaml=0; next }
        in_section && /^##[[:space:]]/ { exit }
        !in_section { next }
        /^```yaml[[:space:]]*$/ { in_yaml=1; next }
        in_yaml && /^```[[:space:]]*$/ { exit }
        in_yaml && $0 ~ "^[[:space:]]*" wanted ":[[:space:]]*" { found=1; exit }
        END { exit(found ? 0 : 1) }
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

mapfile -t CONFIG_EXCLUDED_PATHS < <(read_config_values Exclusions excluded_paths)
if [ "${#CONFIG_EXCLUDED_PATHS[@]}" -eq 0 ]; then
    mapfile -t CONFIG_EXCLUDED_PATHS < <(read_config_values Exclusions exclusions)
fi
mapfile -t CONFIG_READ_ONLY_PATHS < <(read_config_values Exclusions read_only_paths)

for path in "${CONFIG_EXCLUDED_PATHS[@]}" "${CONFIG_READ_ONLY_PATHS[@]}"; do
    add_scan_exclusion "$path"
done

REPORTS_FOLDER=$(read_config_scalar "Agent Behavior" reports_folder)
if [ -z "$REPORTS_FOLDER" ]; then
    if config_scalar_defined "Agent Behavior" reports_folder; then
        echo "Warning: Ignore unsafe reports_folder: empty value; use _reports/" >&2
    fi
    REPORTS_FOLDER="_reports/"
else
    reports_candidate=${REPORTS_FOLDER#./}
    reports_candidate=${reports_candidate%/}
    reports_unsafe=0
    if [ -z "$reports_candidate" ] || [ "$reports_candidate" = "." ] ||
       [[ "$reports_candidate" = /* ]] || [[ "/$reports_candidate/" = *"/../"* ]]; then
        reports_unsafe=1
    else
        for path in "${CONFIG_READ_ONLY_PATHS[@]}"; do
            path=${path#./}
            path=${path%/}
            [ -n "$path" ] || continue
            if [ "$reports_candidate" = "$path" ] ||
               [[ "$reports_candidate" == "$path/"* ]]; then
                reports_unsafe=1
                break
            fi
        done
    fi
    if [ "$reports_unsafe" -eq 1 ]; then
        echo "Warning: Ignore unsafe reports_folder: $REPORTS_FOLDER; use _reports/" >&2
        REPORTS_FOLDER="_reports/"
    else
        REPORTS_FOLDER="$reports_candidate/"
    fi
fi
# The reports folder is a generated surface. Scanning our own reports would turn
# every finding into a self-referential finding on the next run, so it is always
# excluded from the scan.
add_scan_exclusion "$REPORTS_FOLDER"

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
        { sub(/\r$/, "") }
        NR == 1 && $0 == "---" { in_frontmatter=1; next }
        in_frontmatter && $0 == "---" { in_frontmatter=0; next }
        in_frontmatter { next }
        { print }
    ' "$1"
}

note_frontmatter() {
    awk '
        { sub(/\r$/, "") }
        NR == 1 && $0 == "---" { in_frontmatter=1; next }
        in_frontmatter && $0 == "---" { exit }
        in_frontmatter { print }
    ' "$1"
}

has_frontmatter() {
    head -n 1 "$1" 2>/dev/null | grep -q $'^---\r\\{0,1\\}$'
}

note_aliases() {
    note_frontmatter "$1" | awk '
        function emit(value, count, values, i) {
            sub(/[[:space:]]+#.*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            if (value ~ /^\[.*\]$/) {
                value=substr(value, 2, length(value)-2)
                count=split(value, values, ",")
                for (i=1; i<=count; i++) emit(values[i])
                return
            }
            if ((value ~ /^".*"$/) || (value ~ /^\047.*\047$/)) {
                value=substr(value, 2, length(value)-2)
            }
            if (value != "") print value
        }
        /^[[:space:]]*aliases[[:space:]]*:/ {
            in_aliases=1
            value=$0
            sub(/^[[:space:]]*aliases[[:space:]]*:[[:space:]]*/, "", value)
            if (value != "") {
                emit(value)
                in_aliases=0
            }
            next
        }
        in_aliases && /^[[:space:]]*-[[:space:]]+/ {
            value=$0
            sub(/^[[:space:]]*-[[:space:]]+/, "", value)
            emit(value)
            next
        }
        in_aliases && /^[^[:space:]]/ { in_aliases=0 }
    '
}

strip_code() {
    awk '
        function fence_ticks(line, probe, spaces, count) {
            probe=line
            spaces=0
            while (spaces < 3 && substr(probe, 1, 1) == " ") {
                probe=substr(probe, 2)
                spaces++
            }
            count=0
            while (substr(probe, count+1, 1) == "`") count++
            return count
        }
        function only_space_after_fence(line, count, probe) {
            probe=line
            sub(/^   /, "", probe)
            sub(/^  /, "", probe)
            sub(/^ /, "", probe)
            probe=substr(probe, count+1)
            return probe ~ /^[[:space:]]*$/
        }
        function strip_inline(line, out, delimiter, rest, close_at) {
            out=""
            while (match(line, /`+/)) {
                out=out substr(line, 1, RSTART-1)
                delimiter=substr(line, RSTART, RLENGTH)
                rest=substr(line, RSTART+RLENGTH)
                close_at=index(rest, delimiter)
                if (close_at == 0) return out delimiter rest
                line=substr(rest, close_at+length(delimiter))
            }
            return out line
        }
        {
            sub(/\r$/, "")
            ticks=fence_ticks($0)
            if (!in_fence && ticks >= 3) {
                in_fence=1
                fence_length=ticks
                next
            }
            if (in_fence) {
                if (ticks >= fence_length && only_space_after_fence($0, ticks)) {
                    in_fence=0
                    fence_length=0
                }
                next
            }
            print strip_inline($0)
        }
    '
}

lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# --- Findings model -----------------------------------------------------------
# Each finding is one record: severity <TAB> category <TAB> file <TAB> detail.
# Errors block confidence; warnings are backlog. Nothing here modifies the vault.
FINDINGS=()

add_finding() {
    local severity=$1
    local category=$2
    local file=$3
    local detail=$4
    FINDINGS+=("$severity"$'\t'"$category"$'\t'"$file"$'\t'"$detail")
}

# --- Config for the deterministic checks -------------------------------------
mapfile -t GENERATED_FILES < <(read_config_values Exclusions generated_files)
mapfile -t LINK_ALLOWLIST_RAW < <(read_config_values Exclusions link_allowlist)
mapfile -t ORPHAN_ZONES < <(read_config_values Exclusions accepted_orphan_zones)
mapfile -t DUPLICATE_ALLOWLIST_RAW < <(read_config_values Exclusions duplicate_allowlist)
TEMPLATES_LOCATION=$(read_config_scalar Templates location)
SESSION_LOG_FOLDER=$(read_config_scalar "Agent Behavior" session_log_folder)
STALE_AFTER_DAYS=$(read_config_scalar "Agent Behavior" stale_after_days)
[[ "$STALE_AFTER_DAYS" =~ ^[0-9]+$ ]] || STALE_AFTER_DAYS=0

declare -A LINK_ALLOWLIST=()
for target in "${LINK_ALLOWLIST_RAW[@]}"; do
    LINK_ALLOWLIST["$(lower "$target")"]=1
done

# Per-folder hub/navigation names are intentional duplicates, not merge
# candidates; flagging them produces a permanent false-positive backlog that
# drowns real duplicate signals. Vaults can extend the list via
# `duplicate_allowlist` in the Exclusions section.
declare -A DUPLICATE_ALLOWLIST=([index]=1 [00-index]=1 [readme]=1)
for name in "${DUPLICATE_ALLOWLIST_RAW[@]}"; do
    name=${name%.md}
    DUPLICATE_ALLOWLIST["$(lower "$name")"]=1
done

mapfile -t REQUIRED_FM_KEYS < <(
    read_config_values "Frontmatter Schema" required | sed 's/:.*//' |
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d'
)

is_generated() {
    local rel=$1
    local entry
    for entry in "${GENERATED_FILES[@]}"; do
        entry=${entry#./}
        entry=${entry%/}
        [ "$rel" = "$entry" ] && return 0
        [[ "$rel" == "$entry/"* ]] && return 0
    done
    return 1
}

in_orphan_exempt_zone() {
    local rel=$1
    local zone
    for zone in "${ORPHAN_ZONES[@]}"; do
        zone=${zone#./}
        [[ "$zone" == */ ]] || zone="$zone/"
        [[ "$rel" == "$zone"* ]] && return 0
    done
    if [ -n "$TEMPLATES_LOCATION" ]; then
        local tpl=${TEMPLATES_LOCATION#./}
        [[ "$tpl" == */ ]] || tpl="$tpl/"
        [[ "$rel" == "$tpl"* ]] && return 0
    fi
    # Session logs are records, not knowledge notes; nothing should link to them.
    if [ -n "$SESSION_LOG_FOLDER" ]; then
        local slf=${SESSION_LOG_FOLDER#./}
        [[ "$slf" == */ ]] || slf="$slf/"
        [[ "$rel" == "$slf"* ]] && return 0
    fi
    return 1
}

# --- Build the note index -----------------------------------------------------
declare -A NOTE_BY_REL=()       # lowercased relative path (with .md) -> canonical rel
declare -A NOTE_BY_BASE=()      # lowercased basename (no .md) -> canonical rel, or "!ambiguous"
declare -A BASE_PATHS=()        # lowercased basename -> newline-joined rel paths
declare -A ALIAS_BY_NAME=()     # lowercased frontmatter alias -> canonical rel, or "!ambiguous"
REL_PATHS=()

for file in "${NOTE_FILES[@]}"; do
    rel=${file#"$VAULT_DIR"/}
    REL_PATHS+=("$rel")
    rel_lower=$(lower "$rel")
    NOTE_BY_REL["$rel_lower"]="$rel"
    base=${rel##*/}
    base=${base%.md}
    base_lower=$(lower "$base")
    if [ -n "${NOTE_BY_BASE[$base_lower]:-}" ]; then
        NOTE_BY_BASE["$base_lower"]="!ambiguous"
        BASE_PATHS["$base_lower"]+=$'\n'"$rel"
    else
        NOTE_BY_BASE["$base_lower"]="$rel"
        BASE_PATHS["$base_lower"]="$rel"
    fi
    while IFS= read -r alias; do
        alias_lower=$(lower "$alias")
        [ -n "$alias_lower" ] || continue
        if [ -n "${ALIAS_BY_NAME[$alias_lower]:-}" ] &&
           [ "${ALIAS_BY_NAME[$alias_lower]}" != "$rel" ]; then
            ALIAS_BY_NAME["$alias_lower"]="!ambiguous"
        else
            ALIAS_BY_NAME["$alias_lower"]="$rel"
        fi
    done < <(note_aliases "$file")
done

# --- Link resolution: broken wikilinks (error) + inbound map for orphans ------
# Inbound links are counted only from non-generated notes and never from a note
# to itself: a generated index that links to everything would otherwise mask
# every real orphan in the vault.
declare -A INBOUND=()
BROKEN_LINK_COUNT=0

for idx in "${!NOTE_FILES[@]}"; do
    file=${NOTE_FILES[$idx]}
    rel=${REL_PATHS[$idx]}
    source_is_generated=0
    is_generated "$rel" && source_is_generated=1

    while IFS= read -r raw; do
        target=${raw#'[['}
        target=${target%']]'}
        target=${target%%|*}
        target=${target%%#*}
        target=$(printf '%s' "$target" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$target" ] || continue        # [[#heading]] self-reference

        target_lower=$(lower "$target")

        resolved=""
        case "$target_lower" in
            *.md) path_key="$target_lower" ;;
            *)    path_key="$target_lower.md" ;;
        esac
        if [ -n "${NOTE_BY_REL[$path_key]:-}" ]; then
            resolved=${NOTE_BY_REL[$path_key]}
        else
            base_key=${path_key##*/}
            base_key=${base_key%.md}
            candidate=${NOTE_BY_BASE[$base_key]:-}
            if [ -n "$candidate" ] && [ "$candidate" != "!ambiguous" ]; then
                resolved="$candidate"
            elif [ "$candidate" = "!ambiguous" ]; then
                # Ambiguous shortest-path link: it resolves in Obsidian, so it is
                # not broken; skip inbound credit rather than guess a target.
                continue
            else
                candidate=${ALIAS_BY_NAME[$base_key]:-}
                if [ -n "$candidate" ] && [ "$candidate" != "!ambiguous" ]; then
                    resolved="$candidate"
                elif [ "$candidate" = "!ambiguous" ]; then
                    continue
                fi
            fi
        fi

        if [ -z "$resolved" ]; then
            # Targets with a non-.md extension are attachments (images, PDFs);
            # only note links are validated here.
            case "$target_lower" in
                *.md) ;;
                *.*) continue ;;
            esac
            [ -n "${LINK_ALLOWLIST[$target_lower]:-}" ] && continue
            add_finding error broken-link "$rel" "target does not resolve: [[$target]]"
            BROKEN_LINK_COUNT=$((BROKEN_LINK_COUNT + 1))
            continue
        fi

        if [ "$source_is_generated" -eq 0 ] && [ "$resolved" != "$rel" ]; then
            INBOUND["$resolved"]=$(( ${INBOUND["$resolved"]:-0} + 1 ))
        fi
    done < <(note_body "$file" | strip_code | grep -oh '\[\[[^]]*\]\]' 2>/dev/null || true)
done

# --- Orphans (warning) --------------------------------------------------------
ROOT_ALLOWED_FILES=(VAULT.md README.md)
mapfile -t CONFIG_ROOT_ALLOWED_FILES < <(
    read_config_values "Agent Behavior" root_allowed_files
)
ROOT_ALLOWED_FILES+=("${CONFIG_ROOT_ALLOWED_FILES[@]}")

declare -A ROOT_ALLOWED_MAP=()
for file in "${ROOT_ALLOWED_FILES[@]}"; do
    ROOT_ALLOWED_MAP["$file"]=1
done

ORPHAN_COUNT=0
for rel in "${REL_PATHS[@]}"; do
    [ -n "${INBOUND[$rel]:-}" ] && continue
    [ -n "${ROOT_ALLOWED_MAP[$rel]:-}" ] && continue
    in_orphan_exempt_zone "$rel" && continue
    # Generated files are landing surfaces, not knowledge notes; being unlinked
    # is their normal state, so reporting them would be pure noise.
    is_generated "$rel" && continue
    # Hubs and MOCs legitimately show zero inbound links (they are entry points).
    fm=$(note_frontmatter "$VAULT_DIR/$rel")
    if printf '%s\n' "$fm" | grep -qiE "^type[[:space:]]*:[[:space:]]*['\"]?(moc|hub)['\"]?[[:space:]]*$"; then
        continue
    fi
    add_finding warning orphan "$rel" "no inbound links from any non-generated note"
    ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
done

# --- Required frontmatter validation (error) ----------------------------------
FM_VIOLATION_COUNT=0
if [ "${#REQUIRED_FM_KEYS[@]}" -gt 0 ]; then
    for idx in "${!NOTE_FILES[@]}"; do
        file=${NOTE_FILES[$idx]}
        rel=${REL_PATHS[$idx]}
        is_generated "$rel" && continue
        [ -n "${ROOT_ALLOWED_MAP[$rel]:-}" ] && continue
        if ! has_frontmatter "$file"; then
            add_finding error frontmatter "$rel" "missing frontmatter block (required: ${REQUIRED_FM_KEYS[*]})"
            FM_VIOLATION_COUNT=$((FM_VIOLATION_COUNT + 1))
            continue
        fi
        fm=$(note_frontmatter "$file")
        missing=()
        for key in "${REQUIRED_FM_KEYS[@]}"; do
            printf '%s\n' "$fm" | grep -qE "^${key}[[:space:]]*:" || missing+=("$key")
        done
        if [ "${#missing[@]}" -gt 0 ]; then
            add_finding error frontmatter "$rel" "missing required: ${missing[*]}"
            FM_VIOLATION_COUNT=$((FM_VIOLATION_COUNT + 1))
        fi
    done
fi

# --- Duplicate basenames (warning) --------------------------------------------
DUPLICATE_COUNT=0
for base_lower in "${!BASE_PATHS[@]}"; do
    [ "${NOTE_BY_BASE[$base_lower]}" = "!ambiguous" ] || continue
    [ -n "${DUPLICATE_ALLOWLIST[$base_lower]:-}" ] && continue
    paths=$(printf '%s' "${BASE_PATHS[$base_lower]}" | tr '\n' ';' | sed 's/;/; /g')
    add_finding warning duplicate-basename "$base_lower.md" "same basename in multiple folders: $paths"
    DUPLICATE_COUNT=$((DUPLICATE_COUNT + 1))
done

# --- Staleness (warning, opt-in via stale_after_days) -------------------------
STALE_COUNT=0
if [ "$STALE_AFTER_DAYS" -gt 0 ]; then
    for idx in "${!NOTE_FILES[@]}"; do
        file=${NOTE_FILES[$idx]}
        rel=${REL_PATHS[$idx]}
        is_generated "$rel" && continue
        fm=$(note_frontmatter "$file")
        printf '%s\n' "$fm" | grep -qiE "^status[[:space:]]*:[[:space:]]*['\"]?active['\"]?[[:space:]]*$" || continue
        if [ -n "$(find "$file" -mtime +"$STALE_AFTER_DAYS" -print 2>/dev/null)" ]; then
            add_finding warning stale "$rel" "status: active but not modified in over $STALE_AFTER_DAYS days"
            STALE_COUNT=$((STALE_COUNT + 1))
        fi
    done
fi

# --- Secret-shaped strings (error for high-confidence patterns) ---------------
# The finding reports file and line number only — never the matched value.
# Lines carrying redaction sentinels or obvious placeholders are skipped.
SECRET_COUNT=0
secret_line_is_placeholder() {
    case "$1" in
        *'[REDACTED]'*|*'${'*|*'{{'*) return 0 ;;
    esac
    printf '%s' "$1" | grep -qiE 'example|placeholder|your[-_]' && return 0
    return 1
}

for idx in "${!NOTE_FILES[@]}"; do
    file=${NOTE_FILES[$idx]}
    rel=${REL_PATHS[$idx]}
    while IFS=: read -r line_no line_text; do
        [ -n "$line_no" ] || continue
        secret_line_is_placeholder "$line_text" && continue
        add_finding error secret "$rel" "secret-shaped string at line $line_no (value not shown)"
        SECRET_COUNT=$((SECRET_COUNT + 1))
    done < <(grep -nE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|xox[baprs]-[0-9A-Za-z-]{10,}' "$file" 2>/dev/null || true)
done

# --- Existing baseline metrics (unchanged) ------------------------------------
TOTAL_NOTES=${#NOTE_FILES[@]}

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

ALLOWED_ROOT_NOTES=0
MISPLACED_ROOT_NOTES=()
for file in "${NOTE_FILES[@]}"; do
    relative_path=${file#"$VAULT_DIR"/}
    [[ "$relative_path" == */* ]] && continue
    if [ -n "${ROOT_ALLOWED_MAP[$relative_path]:-}" ]; then
        ALLOWED_ROOT_NOTES=$((ALLOWED_ROOT_NOTES + 1))
    else
        MISPLACED_ROOT_NOTES+=("$relative_path")
        add_finding warning misplaced-root "$relative_path" "root Markdown file not in root_allowed_files"
    fi
done

INBOX_FOLDER=$(read_config_scalar "Agent Behavior" inbox_folder)
if [ -z "$INBOX_FOLDER" ] && [ -d "$VAULT_DIR/00-inbox" ]; then
    INBOX_FOLDER=00-inbox/
fi

NO_FM=0
HAS_FM=0
for file in "${NOTE_FILES[@]}"; do
    if has_frontmatter "$file"; then
        HAS_FM=$((HAS_FM + 1))
    else
        NO_FM=$((NO_FM + 1))
    fi
done

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

ALL_LINKS=$(
    for file in "${NOTE_FILES[@]}"; do
        note_body "$file" | strip_code | grep -oh '\[\[[^]]*\]\]' 2>/dev/null || true
    done | sed 's/\[\[//;s/\]\]//;s/|.*//' | sort -u | sed '/^$/d' | wc -l
)

ALL_TAGS=$(
    for file in "${NOTE_FILES[@]}"; do
        grep -oh '#[a-zA-Z][a-zA-Z0-9_/\-]*' -- "$file" 2>/dev/null || true
    done | sort -u | sed '/^$/d' | wc -l
)

# --- Status -------------------------------------------------------------------
ERROR_TOTAL=0
WARN_TOTAL=0
for finding in "${FINDINGS[@]}"; do
    case "${finding%%$'\t'*}" in
        error) ERROR_TOTAL=$((ERROR_TOTAL + 1)) ;;
        warning) WARN_TOTAL=$((WARN_TOTAL + 1)) ;;
    esac
done

STATUS=OK
[ "$WARN_TOTAL" -gt 0 ] && STATUS=WARN
[ "$ERROR_TOTAL" -gt 0 ] && STATUS=FAIL

SCAN_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Fingerprint covers findings only (not the timestamp), so an unchanged vault
# produces an unchanged fingerprint and the envelope can skip the archive copy.
FINDINGS_FINGERPRINT=$(printf '%s\n' "${FINDINGS[@]}" | sort | cksum | awk '{print $1}')

# --- JSON rendering -----------------------------------------------------------
json_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\t'/\\t}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/}
    printf '%s' "$s"
}

render_json() {
    printf '{\n'
    printf '  "vault": "%s",\n' "$(json_escape "$VAULT_DIR")"
    printf '  "date": "%s",\n' "$SCAN_DATE"
    printf '  "status": "%s",\n' "$STATUS"
    printf '  "fingerprint": "%s",\n' "$FINDINGS_FINGERPRINT"
    printf '  "counts": {\n'
    printf '    "total_notes": %s,\n' "$TOTAL_NOTES"
    printf '    "root_notes": %s,\n' "$ROOT_NOTES"
    printf '    "misplaced_root_notes": %s,\n' "${#MISPLACED_ROOT_NOTES[@]}"
    printf '    "with_frontmatter": %s,\n' "$HAS_FM"
    printf '    "without_frontmatter": %s,\n' "$NO_FM"
    printf '    "empty_notes": %s,\n' "$EMPTY"
    printf '    "stub_notes": %s,\n' "$STUB"
    printf '    "unique_link_targets": %s,\n' "$ALL_LINKS"
    printf '    "unique_tags": %s,\n' "$ALL_TAGS"
    printf '    "broken_links": %s,\n' "$BROKEN_LINK_COUNT"
    printf '    "orphans": %s,\n' "$ORPHAN_COUNT"
    printf '    "frontmatter_violations": %s,\n' "$FM_VIOLATION_COUNT"
    printf '    "duplicate_basenames": %s,\n' "$DUPLICATE_COUNT"
    printf '    "stale_notes": %s,\n' "$STALE_COUNT"
    printf '    "secret_findings": %s,\n' "$SECRET_COUNT"
    printf '    "errors": %s,\n' "$ERROR_TOTAL"
    printf '    "warnings": %s\n' "$WARN_TOTAL"
    printf '  },\n'
    printf '  "findings": [\n'
    local first=1
    local severity category file detail
    for finding in "${FINDINGS[@]}"; do
        IFS=$'\t' read -r severity category file detail <<<"$finding"
        [ "$first" -eq 1 ] || printf ',\n'
        first=0
        printf '    {"severity": "%s", "category": "%s", "file": "%s", "detail": "%s"}' \
            "$(json_escape "$severity")" "$(json_escape "$category")" \
            "$(json_escape "$file")" "$(json_escape "$detail")"
    done
    [ "$first" -eq 1 ] || printf '\n'
    printf '  ]\n'
    printf '}\n'
}

# --- Report envelope ----------------------------------------------------------
render_report_md() {
    printf 'Status: **%s**\n\n' "$STATUS"
    printf '# Vault Health Report — %s\n\n' "$SCAN_DATE"
    printf '## Counts\n\n'
    printf -- '- Total notes: %s\n' "$TOTAL_NOTES"
    printf -- '- Broken links: %s (error)\n' "$BROKEN_LINK_COUNT"
    printf -- '- Frontmatter violations: %s (error)\n' "$FM_VIOLATION_COUNT"
    printf -- '- Secret-shaped strings: %s (error)\n' "$SECRET_COUNT"
    printf -- '- Orphans: %s (warning)\n' "$ORPHAN_COUNT"
    printf -- '- Duplicate basenames: %s (warning)\n' "$DUPLICATE_COUNT"
    printf -- '- Stale active notes: %s (warning)\n' "$STALE_COUNT"
    printf -- '- Misplaced root notes: %s (warning)\n' "${#MISPLACED_ROOT_NOTES[@]}"
    printf -- '- Empty notes: %s · Stub notes: %s\n' "$EMPTY" "$STUB"

    local shown severity category file detail
    for wanted in error warning; do
        local total=$ERROR_TOTAL
        [ "$wanted" = warning ] && total=$WARN_TOTAL
        printf '\n## %ss (%s)\n\n' "${wanted^}" "$total"
        if [ "$total" -eq 0 ]; then
            printf 'None.\n'
            continue
        fi
        shown=0
        for finding in "${FINDINGS[@]}"; do
            IFS=$'\t' read -r severity category file detail <<<"$finding"
            [ "$severity" = "$wanted" ] || continue
            if [ "$shown" -ge 50 ]; then
                printf -- '- … and %s more (see health-latest.json)\n' "$((total - shown))"
                break
            fi
            printf -- '- `[%s]` %s — %s\n' "$category" "$file" "$detail"
            shown=$((shown + 1))
        done
    done

    printf '\n## Recommendations\n\n'
    if [ "$ERROR_TOTAL" -gt 0 ]; then
        printf -- '- Resolve the %s error finding(s) first; they block confidence in the vault.\n' "$ERROR_TOTAL"
    fi
    if [ "$WARN_TOTAL" -gt 0 ]; then
        printf -- '- Work down the warning backlog during the next Steward session.\n'
    fi
    if [ "$ERROR_TOTAL" -eq 0 ] && [ "$WARN_TOTAL" -eq 0 ]; then
        printf -- '- No findings. No action needed.\n'
    fi
}

write_report_envelope() {
    local reports_rel=${REPORTS_FOLDER%/}
    local reports_dir="$VAULT_DIR/$reports_rel"
    local previous_fingerprint=""

    mkdir -p "$reports_dir"

    if [ -f "$reports_dir/health-latest.json" ]; then
        previous_fingerprint=$(
            grep -o '"fingerprint": "[^"]*"' "$reports_dir/health-latest.json" |
                head -n 1 | sed 's/.*: "//;s/"//' || true
        )
    fi

    render_json > "$reports_dir/health-latest.json"
    render_report_md > "$reports_dir/health-latest.md"

    # Archive only incidents and changes: a clean run (including the first ever)
    # leaves no residue, so the archive reads as a history of events, not runs.
    if [ "$STATUS" != "OK" ] &&
       [ "$FINDINGS_FINGERPRINT" != "$previous_fingerprint" ]; then
        mkdir -p "$reports_dir/archive"
        cp "$reports_dir/health-latest.md" \
            "$reports_dir/archive/health-$(date -u +%Y%m%dT%H%M%SZ).md"
    fi

    if [ "$JSON_MODE" -eq 0 ]; then
        echo ""
        echo "Report: $reports_rel/health-latest.md (status: $STATUS)"
    fi
}

# --- Output -------------------------------------------------------------------
if [ "$JSON_MODE" -eq 1 ]; then
    render_json
else
    echo "=== Vault Health Scan ==="
    echo "Vault: $VAULT_DIR"
    echo "Date: $SCAN_DATE"
    echo ""

    echo "Total notes: $TOTAL_NOTES"

    echo ""
    echo "=== Notes by Folder ==="
    if [ "${#FOLDER_COUNTS[@]}" -gt 0 ]; then
        while IFS= read -r folder; do
            echo "  $folder/: ${FOLDER_COUNTS[$folder]}"
        done < <(printf '%s\n' "${!FOLDER_COUNTS[@]}" | sort)
    fi
    echo "  (root): $ROOT_NOTES"

    echo ""
    echo "=== Root Folder ==="
    echo "  Total root Markdown files: $ROOT_NOTES"
    echo "  Allowed root files: $ALLOWED_ROOT_NOTES"
    echo "  Misplaced root notes: ${#MISPLACED_ROOT_NOTES[@]}"
    for file in "${MISPLACED_ROOT_NOTES[@]}"; do
        echo "    $file"
    done
    if [ -n "$INBOX_FOLDER" ]; then
        echo "  Inbox folder: $INBOX_FOLDER"
    else
        echo "  Inbox folder: MISSING"
    fi

    echo ""
    echo "=== Frontmatter Check ==="
    echo "  With frontmatter: $HAS_FM"
    echo "  Without frontmatter: $NO_FM"

    echo ""
    echo "=== Content Check ==="
    echo "  Empty notes (<20 non-whitespace body characters): $EMPTY"
    echo "  Stub notes (<100 body words, excluding empty notes): $STUB"

    echo ""
    echo "=== Link Count ==="
    echo "  Unique wikilink targets: $ALL_LINKS"

    echo ""
    echo "=== Tag Count (raw #hashtag strings, may include anchors) ==="
    echo "  Unique tags: $ALL_TAGS"

    echo ""
    echo "=== Deterministic Findings ==="
    echo "  Broken links: $BROKEN_LINK_COUNT (error)"
    echo "  Frontmatter violations: $FM_VIOLATION_COUNT (error)"
    echo "  Secret-shaped strings: $SECRET_COUNT (error)"
    echo "  Orphans: $ORPHAN_COUNT (warning)"
    echo "  Duplicate basenames: $DUPLICATE_COUNT (warning)"
    echo "  Stale active notes: $STALE_COUNT (warning)"
    if [ "${#FINDINGS[@]}" -gt 0 ]; then
        echo ""
        for finding in "${FINDINGS[@]}"; do
            IFS=$'\t' read -r severity category file detail <<<"$finding"
            echo "  [$severity] [$category] $file — $detail"
        done
    fi

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
    echo "Status: $STATUS"
    echo ""
    echo "=== Scan Complete ==="
fi

if [ "$REPORT_MODE" -eq 1 ]; then
    write_report_envelope
fi

if [ "$STRICT_MODE" -eq 1 ] && [ "$ERROR_TOTAL" -gt 0 ]; then
    exit 2
fi
exit 0
