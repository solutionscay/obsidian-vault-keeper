#!/usr/bin/env bash
# open-items-scan.sh - Deterministic open-items tracker diagnostics
# Usage: bash open-items-scan.sh [--json] [--report] [--strict] /path/to/vault
#
# Reads the vault's open-items tracker (VAULT.md `open_items_tracker`), parses
# its table rows, and reports: open items ranked by urgency series and age,
# quick wins (rows carrying the `quick_win_marker`), stale urgent items, the
# next free ID per series, and tracker integrity findings (duplicate IDs,
# malformed rows, missing mandatory fields).
#
# Modes match vault-health-scan.sh:
#   (default)  human-readable report on stdout, exit 0
#   --json     machine-readable JSON on stdout instead of the human report
#   --report   also write open-items-latest.md + open-items-latest.json into
#              <vault>/<reports_folder>/, plus a timestamped archive copy only
#              when status is WARN/FAIL and findings changed since the previous
#              run (clean runs leave no residue)
#   --strict   exit 2 when any error-severity finding exists (default stays
#              exit 0 so autonomous sessions are never blocked by a report)
#
# Severity model: errors are integrity breaks that make the tracker lie
# (duplicate IDs); warnings are hygiene debt (stale urgent items, rows missing
# Opened/Owner, malformed ID cells). The scan never modifies the tracker.

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

read_config_scalar() {
    local section=$1
    local key=$2

    [ -f "$VAULT_CONFIG" ] || return 0

    awk -v wanted_section="$section" -v wanted="$key" '
        { sub(/\r$/, "") }
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

read_config_values() {
    local section=$1
    local key=$2

    [ -f "$VAULT_CONFIG" ] || return 0

    awk -v wanted_section="$section" -v wanted="$key" '
        { sub(/\r$/, "") }
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

safe_relative_path() {
    local path=$1
    path=${path#./}
    path=${path%/}
    if [ -z "$path" ] || [ "$path" = "." ] || [[ "$path" = /* ]] ||
       [[ "/$path/" = *"/../"* ]]; then
        return 1
    fi
    printf '%s' "$path"
}

# --- Findings model (same record shape as vault-health-scan.sh) ---------------
FINDINGS=()

add_finding() {
    FINDINGS+=("$1"$'\t'"$2"$'\t'"$3"$'\t'"$4")
}

# --- Config -------------------------------------------------------------------
TRACKER_REL_RAW=$(read_config_scalar "Agent Behavior" open_items_tracker)
[ -n "$TRACKER_REL_RAW" ] || TRACKER_REL_RAW="90-system/open-items.md"
QUICK_MARKER=$(read_config_scalar "Agent Behavior" quick_win_marker)
[ -n "$QUICK_MARKER" ] || QUICK_MARKER="(quick)"
URGENT_STALE_DAYS=$(read_config_scalar "Agent Behavior" urgent_stale_days)
[[ "$URGENT_STALE_DAYS" =~ ^[0-9]+$ ]] || URGENT_STALE_DAYS=2

# Series priority: first entry is most urgent. Unlisted series rank after
# listed ones, alphabetically, so a vault can invent series without breaking
# the ranking.
mapfile -t SERIES_PRIORITY < <(read_config_values "Agent Behavior" id_series_priority)
if [ "${#SERIES_PRIORITY[@]}" -eq 0 ]; then
    SERIES_PRIORITY=(U D W B)
fi

series_rank() {
    local series=$1 i
    for i in "${!SERIES_PRIORITY[@]}"; do
        if [ "${SERIES_PRIORITY[$i]}" = "$series" ]; then
            printf '%02d' "$i"
            return
        fi
    done
    printf '99%s' "$series"
}

REPORTS_FOLDER=$(read_config_scalar "Agent Behavior" reports_folder)
if reports_safe=$(safe_relative_path "${REPORTS_FOLDER:-_reports/}"); then
    REPORTS_FOLDER="$reports_safe/"
else
    echo "Warning: Ignore unsafe reports_folder: $REPORTS_FOLDER; use _reports/" >&2
    REPORTS_FOLDER="_reports/"
fi

TRACKER_CONFIGURED=1
if ! TRACKER_REL=$(safe_relative_path "$TRACKER_REL_RAW"); then
    add_finding warning tracker-config "VAULT.md" "unsafe open_items_tracker path ignored: $TRACKER_REL_RAW"
    TRACKER_CONFIGURED=0
fi

# A tracker nested in a read-only path could never be updated by the skill, so
# treat that configuration as broken rather than silently scanning a file the
# Steward is forbidden to maintain.
if [ "$TRACKER_CONFIGURED" -eq 1 ]; then
    mapfile -t READ_ONLY_PATHS < <(read_config_values Exclusions read_only_paths)
    for path in "${READ_ONLY_PATHS[@]}"; do
        ro=$(safe_relative_path "$path") || continue
        if [ "$TRACKER_REL" = "$ro" ] || [[ "$TRACKER_REL" == "$ro/"* ]]; then
            add_finding warning tracker-config "VAULT.md" "open_items_tracker sits inside read_only_paths: $TRACKER_REL"
            TRACKER_CONFIGURED=0
            break
        fi
    done
fi

TRACKER_FILE="$VAULT_DIR/${TRACKER_REL:-}"

# --- Parse the tracker --------------------------------------------------------
# Row anatomy (documented in references/vault-config-spec.md):
#   | <ID> 🆕 | **<title>** | <AREA> | Opened YYYY-MM-DD. Owner: **<name>**. <details> |
# Struck (completed) rows wrap the ID in ~~strikethrough~~. IDs are a series
# letter block plus a number (U12, B3). Header and separator rows are skipped.
OPEN_IDS=()
declare -A OPEN_ROW_TITLE=() OPEN_ROW_AGE=() OPEN_ROW_LINE=() OPEN_ROW_QUICK=()
declare -A SEEN_IDS=() SERIES_MAX=()
STRUCK_COUNT=0
TRACKER_PRESENT=0

if [ "$TRACKER_CONFIGURED" -eq 1 ] && [ -f "$TRACKER_FILE" ]; then
    TRACKER_PRESENT=1
    TODAY_EPOCH=$(date -u +%s)
    line_no=0
    while IFS= read -r line || [ -n "$line" ]; do
        line_no=$((line_no + 1))
        line=${line%$'\r'}
        [[ "$line" == \|* ]] || continue

        id_cell=$(printf '%s' "$line" | awk -F'|' '{print $2}')
        id_cell=$(printf '%s' "$id_cell" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$id_cell" ] || continue

        struck=0
        if [[ "$id_cell" == '~~'* ]]; then
            struck=1
        fi
        id=$(printf '%s' "$id_cell" | sed 's/~~//g' | grep -oE '^[A-Z]+[0-9]+' || true)

        if [ -z "$id" ]; then
            # Header ("ID"), separator ("---"), and prose rows are structure,
            # not data; only cells that *look like* an ID but fail to parse are
            # worth a warning.
            case "$id_cell" in
                ID|---*|:--*) continue ;;
                *[A-Za-z0-9]*)
                    add_finding warning malformed-row "$TRACKER_REL" "line $line_no: unparseable ID cell: $id_cell"
                    ;;
            esac
            continue
        fi

        series=$(printf '%s' "$id" | grep -oE '^[A-Z]+')
        number=$(printf '%s' "$id" | grep -oE '[0-9]+$')
        if [ -z "${SERIES_MAX[$series]:-}" ] || [ "$number" -gt "${SERIES_MAX[$series]}" ]; then
            SERIES_MAX[$series]=$number
        fi

        if [ -n "${SEEN_IDS[$id]:-}" ]; then
            add_finding error duplicate-id "$TRACKER_REL" "line $line_no: ID $id already used on line ${SEEN_IDS[$id]} — IDs are never reused"
            continue
        fi
        SEEN_IDS[$id]=$line_no

        if [ "$struck" -eq 1 ]; then
            STRUCK_COUNT=$((STRUCK_COUNT + 1))
            continue
        fi

        title=$(printf '%s' "$line" | awk -F'|' '{print $3}' |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/\*\*//g')
        details=$(printf '%s' "$line" | awk -F'|' '{ for (i=4; i<=NF; i++) printf "%s ", $i }')

        opened=$(printf '%s' "$details" | grep -oE 'Opened [0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n 1 || true)
        age_days=""
        if [ -n "$opened" ]; then
            opened_date=${opened#Opened }
            if opened_epoch=$(date -u -d "$opened_date" +%s 2>/dev/null) ||
               opened_epoch=$(date -u -j -f '%Y-%m-%d' "$opened_date" +%s 2>/dev/null); then
                age_days=$(( (TODAY_EPOCH - opened_epoch) / 86400 ))
            fi
        else
            add_finding warning missing-field "$TRACKER_REL" "line $line_no: $id has no 'Opened YYYY-MM-DD' — open date is mandatory"
        fi
        if ! printf '%s' "$details" | grep -q 'Owner:'; then
            add_finding warning missing-field "$TRACKER_REL" "line $line_no: $id has no 'Owner:' — every item needs an owner"
        fi

        quick=0
        if [[ "$line" == *"$QUICK_MARKER"* ]]; then
            quick=1
        fi

        OPEN_IDS+=("$id")
        OPEN_ROW_TITLE[$id]="$title"
        OPEN_ROW_AGE[$id]="$age_days"
        OPEN_ROW_LINE[$id]="$line_no"
        OPEN_ROW_QUICK[$id]="$quick"

        if [ -n "$age_days" ]; then
            first_series=${SERIES_PRIORITY[0]}
            if [ "$series" = "$first_series" ] && [ "$age_days" -gt "$URGENT_STALE_DAYS" ]; then
                add_finding warning stale-urgent "$TRACKER_REL" "$id (\"$title\") opened $age_days days ago — '$first_series' items should close within $URGENT_STALE_DAYS days"
            fi
        fi
    done < "$TRACKER_FILE"
elif [ "$TRACKER_CONFIGURED" -eq 1 ]; then
    # Absence is a valid starting state (the skill creates the tracker on first
    # session close), so a missing file is informational, not a finding.
    :
fi

# --- Ranked views -------------------------------------------------------------
RANKED_IDS=()
if [ "${#OPEN_IDS[@]}" -gt 0 ]; then
    mapfile -t RANKED_IDS < <(
        for id in "${OPEN_IDS[@]}"; do
            series=$(printf '%s' "$id" | grep -oE '^[A-Z]+')
            age=${OPEN_ROW_AGE[$id]}
            [ -n "$age" ] || age=-1
            printf '%s\t%05d\t%s\n' "$(series_rank "$series")" $((99999 - (age + 1))) "$id"
        done | sort | awk -F'\t' '{print $3}'
    )
fi

QUICK_IDS=()
for id in "${RANKED_IDS[@]}"; do
    [ "${OPEN_ROW_QUICK[$id]}" = "1" ] && QUICK_IDS+=("$id")
done

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
FINDINGS_FINGERPRINT=$(
    { printf '%s\n' "${FINDINGS[@]}"; printf '%s\n' "${RANKED_IDS[@]}"; } |
        sort | cksum | awk '{print $1}'
)

describe_item() {
    local id=$1
    local age=${OPEN_ROW_AGE[$id]}
    local age_text="age unknown"
    [ -n "$age" ] && age_text="${age}d old"
    printf '%s — %s (%s)' "$id" "${OPEN_ROW_TITLE[$id]}" "$age_text"
}

# --- JSON ---------------------------------------------------------------------
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
    printf '  "tracker": "%s",\n' "$(json_escape "${TRACKER_REL:-}")"
    printf '  "tracker_present": %s,\n' "$TRACKER_PRESENT"
    printf '  "date": "%s",\n' "$SCAN_DATE"
    printf '  "status": "%s",\n' "$STATUS"
    printf '  "fingerprint": "%s",\n' "$FINDINGS_FINGERPRINT"
    printf '  "counts": {\n'
    printf '    "open": %s,\n' "${#OPEN_IDS[@]}"
    printf '    "struck": %s,\n' "$STRUCK_COUNT"
    printf '    "quick_wins": %s,\n' "${#QUICK_IDS[@]}"
    printf '    "errors": %s,\n' "$ERROR_TOTAL"
    printf '    "warnings": %s\n' "$WARN_TOTAL"
    printf '  },\n'
    printf '  "next_ids": {'
    local first=1 series
    while IFS= read -r series; do
        [ -n "$series" ] || continue
        [ "$first" -eq 1 ] || printf ','
        first=0
        printf '"%s": "%s%s"' "$series" "$series" "$(( ${SERIES_MAX[$series]} + 1 ))"
    done < <(printf '%s\n' "${!SERIES_MAX[@]}" | sort)
    printf '},\n'
    printf '  "open_ranked": ['
    first=1
    local id
    for id in "${RANKED_IDS[@]}"; do
        [ "$first" -eq 1 ] || printf ', '
        first=0
        printf '{"id": "%s", "title": "%s", "age_days": %s, "quick_win": %s}' \
            "$(json_escape "$id")" "$(json_escape "${OPEN_ROW_TITLE[$id]}")" \
            "${OPEN_ROW_AGE[$id]:-null}" "${OPEN_ROW_QUICK[$id]}"
    done
    printf '],\n'
    printf '  "findings": [\n'
    first=1
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
    printf '# Open Items Report — %s\n\n' "$SCAN_DATE"
    if [ "$TRACKER_PRESENT" -eq 0 ]; then
        if [ "$TRACKER_CONFIGURED" -eq 0 ]; then
            printf 'Tracker configuration invalid.\n'
        else
            printf 'No tracker at `%s` yet — the first session close creates it.\n' "${TRACKER_REL:-unconfigured}"
        fi
        if [ "${#FINDINGS[@]}" -gt 0 ]; then
            printf '\n## Findings\n\n'
            local severity category file detail
            for finding in "${FINDINGS[@]}"; do
                IFS=$'\t' read -r severity category file detail <<<"$finding"
                printf -- '- `[%s]` `[%s]` %s — %s\n' "$severity" "$category" "$file" "$detail"
            done
        fi
        return
    fi
    printf '## Counts\n\n'
    printf -- '- Open items: %s\n' "${#OPEN_IDS[@]}"
    printf -- '- Struck (completed, kept as history): %s\n' "$STRUCK_COUNT"
    printf -- '- Quick wins available: %s\n' "${#QUICK_IDS[@]}"
    printf -- '- Integrity errors: %s · Hygiene warnings: %s\n' "$ERROR_TOTAL" "$WARN_TOTAL"

    printf '\n## Quick wins (marked %s)\n\n' "$QUICK_MARKER"
    if [ "${#QUICK_IDS[@]}" -gt 0 ]; then
        local id
        for id in "${QUICK_IDS[@]}"; do
            printf -- '- %s\n' "$(describe_item "$id")"
        done
    else
        printf -- '- none marked\n'
    fi

    printf '\n## Open items (by urgency, then age)\n\n'
    if [ "${#RANKED_IDS[@]}" -gt 0 ]; then
        local shown=0 id
        for id in "${RANKED_IDS[@]}"; do
            if [ "$shown" -ge 50 ]; then
                printf -- '- … and %s more (see open-items-latest.json)\n' "$(( ${#RANKED_IDS[@]} - shown ))"
                break
            fi
            printf -- '- %s\n' "$(describe_item "$id")"
            shown=$((shown + 1))
        done
    else
        printf -- '- none — the tracker is clear\n'
    fi

    printf '\n## Next free IDs\n\n'
    local series
    while IFS= read -r series; do
        [ -n "$series" ] || continue
        printf -- '- %s: %s%s\n' "$series" "$series" "$(( ${SERIES_MAX[$series]} + 1 ))"
    done < <(printf '%s\n' "${!SERIES_MAX[@]}" | sort)

    printf '\n## Findings\n\n'
    if [ "${#FINDINGS[@]}" -gt 0 ]; then
        local severity category file detail
        for finding in "${FINDINGS[@]}"; do
            IFS=$'\t' read -r severity category file detail <<<"$finding"
            printf -- '- `[%s]` `[%s]` %s — %s\n' "$severity" "$category" "$file" "$detail"
        done
    else
        printf -- '- none\n'
    fi
}

write_report_envelope() {
    local reports_rel=${REPORTS_FOLDER%/}
    local reports_dir="$VAULT_DIR/$reports_rel"
    local previous_fingerprint=""

    mkdir -p "$reports_dir"

    if [ -f "$reports_dir/open-items-latest.json" ]; then
        previous_fingerprint=$(
            grep -o '"fingerprint": "[^"]*"' "$reports_dir/open-items-latest.json" |
                head -n 1 | sed 's/.*: "//;s/"//'
        )
    fi

    render_json > "$reports_dir/open-items-latest.json"
    render_report_md > "$reports_dir/open-items-latest.md"

    # Archive only incidents whose findings changed, matching the health scan:
    # the archive is a history of events, not of executions.
    if [ "$STATUS" != "OK" ] && [ "$FINDINGS_FINGERPRINT" != "$previous_fingerprint" ]; then
        mkdir -p "$reports_dir/archive"
        cp "$reports_dir/open-items-latest.md" \
            "$reports_dir/archive/open-items-$(date -u +%Y%m%dT%H%M%SZ).md"
    fi

    if [ "$JSON_MODE" -eq 0 ]; then
        echo ""
        echo "Report: $reports_rel/open-items-latest.md (status: $STATUS)"
    fi
}

# --- Output -------------------------------------------------------------------
if [ "$JSON_MODE" -eq 1 ]; then
    render_json
else
    echo "=== Open Items Scan ==="
    echo "Vault: $VAULT_DIR"
    echo "Tracker: ${TRACKER_REL:-unconfigured}"
    echo "Date: $SCAN_DATE"
    echo ""
    if [ "$TRACKER_PRESENT" -eq 0 ]; then
        if [ "$TRACKER_CONFIGURED" -eq 0 ]; then
            echo "Tracker configuration invalid — see findings below."
        else
            echo "No tracker file found (a valid starting state — the first session close creates it)."
        fi
    else
        echo "Open items: ${#OPEN_IDS[@]}"
        echo "Struck items: $STRUCK_COUNT"
        echo "Quick wins: ${#QUICK_IDS[@]}"
        echo ""
        echo "=== Quick wins ==="
        if [ "${#QUICK_IDS[@]}" -gt 0 ]; then
            for id in "${QUICK_IDS[@]}"; do
                echo "  $(describe_item "$id")"
            done
        else
            echo "  none marked"
        fi
        echo ""
        echo "=== Open (by urgency, then age) ==="
        for id in "${RANKED_IDS[@]}"; do
            echo "  $(describe_item "$id")"
        done
        echo ""
        echo "=== Next free IDs ==="
        while IFS= read -r series; do
            [ -n "$series" ] || continue
            echo "  $series: $series$(( ${SERIES_MAX[$series]} + 1 ))"
        done < <(printf '%s\n' "${!SERIES_MAX[@]}" | sort)
    fi
    if [ "${#FINDINGS[@]}" -gt 0 ]; then
        echo ""
        echo "=== Findings ==="
        for finding in "${FINDINGS[@]}"; do
            IFS=$'\t' read -r severity category file detail <<<"$finding"
            echo "  [$severity] [$category] $file — $detail"
        done
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
