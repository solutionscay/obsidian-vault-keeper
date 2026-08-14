#!/usr/bin/env bash

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
SCAN="$REPO_DIR/scripts/vault-health-scan.sh"
SELECT="$REPO_DIR/scripts/curator-domain-select.sh"
ORGANIZE="$REPO_DIR/scripts/root-note-organize.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_contains() {
    local text=$1
    local expected=$2

    grep -Fq -- "$expected" <<<"$text" || fail "Missing output: $expected"
}

assert_not_contains() {
    local text=$1
    local unexpected=$2

    if grep -Fq -- "$unexpected" <<<"$text"; then
        fail "Unexpected output: $unexpected"
    fi
}

write_words() {
    local file=$1
    local count=$2
    local prefix=${3:-word}

    : > "$file"
    for ((i=1; i<=count; i++)); do
        printf '%s%s ' "$prefix" "$i" >> "$file"
    done
    printf '\n' >> "$file"
}

VAULT="$TEST_DIR/vault"
mkdir -p "$VAULT/.obsidian" "$VAULT/private" "$VAULT/read only"

printf '%s\n' \
    '## Exclusions' \
    '' \
    '```yaml' \
    'excluded_paths:' \
    '  - private/' \
    'read_only_paths:' \
    '  - "read only/"' \
    '```' > "$VAULT/VAULT.md"

printf 'abcdefghijklmnopqrs\n' > "$VAULT/empty.md"
printf 'abcdefghijklmnopqrst\n' > "$VAULT/no-frontmatter.md"
write_words "$VAULT/stub.md" 99
printf '%s\n' '---' 'title: Full' '---' > "$VAULT/full.md"
for ((i=1; i<=100; i++)); do
    printf 'full%s ' "$i" >> "$VAULT/full.md"
done
printf '[[visible-target]] #visible\n' >> "$VAULT/full.md"
printf '[[private-target]] #private\n' > "$VAULT/private/secret.md"
printf '[[readonly-target]] #readonly\n' > "$VAULT/read only/template.md"

SCAN_OUTPUT=$("$SCAN" "$VAULT")
assert_contains "$SCAN_OUTPUT" 'Total notes: 5'
assert_contains "$SCAN_OUTPUT" 'Empty notes (<20 non-whitespace body characters): 1'
assert_contains "$SCAN_OUTPUT" 'Stub notes (<100 body words, excluding empty notes): 3'
assert_contains "$SCAN_OUTPUT" 'Unique wikilink targets: 1'
assert_contains "$SCAN_OUTPUT" 'Unique tags: 1'
assert_contains "$SCAN_OUTPUT" 'Allowed root files: 1'
assert_contains "$SCAN_OUTPUT" 'Misplaced root notes: 4'

LEGACY_VAULT="$TEST_DIR/legacy-vault"
mkdir -p "$LEGACY_VAULT/.obsidian" "$LEGACY_VAULT/legacy-private"
printf '%s\n' \
    '## Exclusions' \
    '' \
    '```yaml' \
    'exclusions:' \
    '  - legacy-private/' \
    '```' > "$LEGACY_VAULT/VAULT.md"
printf 'visible content has more than twenty characters\n' > "$LEGACY_VAULT/visible.md"
printf 'hidden content has more than twenty characters\n' > "$LEGACY_VAULT/legacy-private/hidden.md"
LEGACY_OUTPUT=$("$SCAN" "$LEGACY_VAULT")
assert_contains "$LEGACY_OUTPUT" 'Total notes: 2'

CLEAN_ROOT_VAULT="$TEST_DIR/clean-root-vault"
mkdir -p "$CLEAN_ROOT_VAULT/.obsidian"
printf '%s\n' '## Agent Behavior' '' '```yaml' 'root_allowed_files:' \
    '  - VAULT.md' '  - README.md' '```' > "$CLEAN_ROOT_VAULT/VAULT.md"
printf 'readme body\n' > "$CLEAN_ROOT_VAULT/README.md"
CLEAN_ROOT_OUTPUT=$("$SCAN" "$CLEAN_ROOT_VAULT")
assert_contains "$CLEAN_ROOT_OUTPUT" 'Misplaced root notes: 0'

ROTATION_OUTPUT=$("$SELECT" 'Domain A' 3 '' 'Domain A' 'Domain B')
assert_contains "$ROTATION_OUTPUT" 'Domain: Domain B'
assert_contains "$ROTATION_OUTPUT" 'Decision: rotate-after-three'

if "$SELECT" 'Domain A' 3 '' 'Domain A' >/dev/null 2>&1; then
    fail 'The selector permitted a fourth autonomous run in Domain A.'
fi

RENEWAL_OUTPUT=$("$SELECT" 'Domain A' 3 'Domain A' 'Domain A' 'Domain B')
assert_contains "$RENEWAL_OUTPUT" 'Domain: Domain A'
assert_contains "$RENEWAL_OUTPUT" 'Decision: operator-renewal'

ORGANIZE_VAULT="$TEST_DIR/organize-vault"
mkdir -p "$ORGANIZE_VAULT/.obsidian" "$ORGANIZE_VAULT/00-inbox" \
    "$ORGANIZE_VAULT/10-projects" "$ORGANIZE_VAULT/40-archive" \
    "$ORGANIZE_VAULT/notes" "$ORGANIZE_VAULT/read-only" \
    "$ORGANIZE_VAULT/custom-reports/archive"
printf '%s\n' \
    '## Exclusions' \
    '' \
    '```yaml' \
    'read_only_paths:' \
    '  - read-only/' \
    '```' \
    '' \
    '## Agent Behavior' \
    '' \
    '```yaml' \
    'inbox_folder: 00-inbox/' \
    'reports_folder: custom-reports/' \
    'root_allowed_files:' \
    '  - VAULT.md' \
    '  - README.md' \
    '  - ROOT-NOTES.md' \
    'placement_rules:' \
    '  type/project: 10-projects/' \
    '  status/archive: 40-archive/' \
    '```' > "$ORGANIZE_VAULT/VAULT.md"
printf '[[project.md]] and [project](project.md)\n' > "$ORGANIZE_VAULT/README.md"
printf '[project](../project.md)\n' > "$ORGANIZE_VAULT/notes/links.md"
printf '[[project.md]]\n' > "$ORGANIZE_VAULT/read-only/links.md"
printf 'archived detail: [[project.md]]\n' > "$ORGANIZE_VAULT/custom-reports/archive/incident.md"
printf 'allowed root file\n' > "$ORGANIZE_VAULT/ROOT-NOTES.md"
printf '%s\n' '---' 'type: project' '---' 'project body' > "$ORGANIZE_VAULT/project.md"
printf 'loose body\n' > "$ORGANIZE_VAULT/loose.md"
printf 'collision body\n' > "$ORGANIZE_VAULT/collision.md"
printf 'existing body\n' > "$ORGANIZE_VAULT/00-inbox/collision.md"

PLAN_OUTPUT=$("$ORGANIZE" "$ORGANIZE_VAULT")
assert_contains "$PLAN_OUTPUT" 'PLAN: project.md -> 10-projects/project.md | reason: placement rule: type/project'
assert_contains "$PLAN_OUTPUT" 'PLAN: loose.md -> 00-inbox/loose.md | reason: inbox fallback'
[ -f "$ORGANIZE_VAULT/project.md" ] || fail 'The plan moved a root note.'

APPLY_OUTPUT=$("$ORGANIZE" --apply "$ORGANIZE_VAULT")
assert_contains "$APPLY_OUTPUT" 'MOVE: project.md -> 10-projects/project.md | reason: placement rule: type/project'
assert_contains "$APPLY_OUTPUT" 'MOVE: loose.md -> 00-inbox/loose.md | reason: inbox fallback'
assert_contains "$APPLY_OUTPUT" 'DEFER: collision.md | destination exists: 00-inbox/collision.md'
[ -f "$ORGANIZE_VAULT/10-projects/project.md" ] || fail 'The project note did not move.'
[ -f "$ORGANIZE_VAULT/00-inbox/loose.md" ] || fail 'The loose note did not move.'
[ -f "$ORGANIZE_VAULT/ROOT-NOTES.md" ] || fail 'The allowed root file moved.'
grep -Fq '[[10-projects/project.md]]' "$ORGANIZE_VAULT/README.md" ||
    fail 'The wikilink did not change after the move.'
grep -Fq '[project](10-projects/project.md)' "$ORGANIZE_VAULT/README.md" ||
    fail 'The Markdown link did not change after the move.'
grep -Fq '[project](../10-projects/project.md)' "$ORGANIZE_VAULT/notes/links.md" ||
    fail 'The relative Markdown link did not change after the move.'
grep -Fq '[[project.md]]' "$ORGANIZE_VAULT/read-only/links.md" ||
    fail 'The organizer changed a read-only file.'
grep -Fq '[[project.md]]' "$ORGANIZE_VAULT/custom-reports/archive/incident.md" ||
    fail 'The organizer changed an archived report.'

NO_INBOX_VAULT="$TEST_DIR/no-inbox-vault"
mkdir -p "$NO_INBOX_VAULT/.obsidian"
printf '%s\n' '## Agent Behavior' '' '```yaml' 'root_allowed_files:' \
    '  - VAULT.md' '```' > "$NO_INBOX_VAULT/VAULT.md"
printf 'root body\n' > "$NO_INBOX_VAULT/root-note.md"
NO_INBOX_OUTPUT=$("$ORGANIZE" --apply "$NO_INBOX_VAULT")
assert_contains "$NO_INBOX_OUTPUT" 'DEFER: root-note.md | inbox_folder is missing'
[ -f "$NO_INBOX_VAULT/root-note.md" ] || fail 'A note moved without an inbox configuration.'

grep -A3 '^## Expansion Domains$' "$REPO_DIR/assets/vault-md-template.md" |
    grep -q '^```yaml$' || fail 'The starter template has no Expansion Domains YAML block.'
grep -A5 '^## Expansion Domains$' "$REPO_DIR/assets/vault-md-template.md" |
    grep -q '^domains:$' || fail 'The starter template has no canonical domains key.'

# --- Health scan v2: deterministic findings, --strict, --json, --report -------

HEALTH_VAULT="$TEST_DIR/health-vault"
mkdir -p "$HEALTH_VAULT/.obsidian" "$HEALTH_VAULT/notes" \
    "$HEALTH_VAULT/generated" "$HEALTH_VAULT/daily"
printf '%s\n' \
    '## Frontmatter Schema' \
    '' \
    '```yaml' \
    'required:' \
    '  - title: string' \
    '```' \
    '' \
    '## Exclusions' \
    '' \
    '```yaml' \
    'generated_files:' \
    '  - generated' \
    'link_allowlist:' \
    '  - external-thing' \
    'accepted_orphan_zones:' \
    '  - daily/' \
    '```' > "$HEALTH_VAULT/VAULT.md"
printf '%s\n' '---' 'title: Alpha' '---' \
    '[[beta]] [[missing-note]] [[external-thing]] [[creds]]' \
    '`[[inline-code-link]]`' \
    '```markdown' '[[fenced-code-link]]' '```' \
    '````markdown' '[[outer-fenced-code-link]]' '```' \
    '[[nested-fenced-code-link]]' '```' '````' > "$HEALTH_VAULT/notes/alpha.md"
printf '%s\n' '---' 'title: Beta' '---' '[[alpha]] [[nofm]]' > "$HEALTH_VAULT/notes/beta.md"
printf '%s\n' '---' 'title: Creds' '---' \
    'key AKIAABCDEFGHIJKLMNOP end' \
    'documented sample AKIAIOSFODNN7EXAMPLE stays exempt' > "$HEALTH_VAULT/notes/creds.md"
printf 'no frontmatter here at all\n' > "$HEALTH_VAULT/notes/nofm.md"
printf '%s\n' '---' 'title: Lost' '---' 'lost content' > "$HEALTH_VAULT/notes/lost.md"
printf '%s\n' '---' 'title: Dup' '---' 'dup one' > "$HEALTH_VAULT/notes/dup.md"
printf '%s\n' '---' 'title: Dup Daily' '---' 'dup two' > "$HEALTH_VAULT/daily/dup.md"
printf '[[lost]] [[alpha]] [[beta]] [[dup]]\n' > "$HEALTH_VAULT/generated/index.md"

# Default mode keeps exit 0 even with findings (command substitution under
# set -e proves it) and reports every deterministic category.
HEALTH_OUTPUT=$("$SCAN" "$HEALTH_VAULT")
assert_contains "$HEALTH_OUTPUT" 'Total notes: 9'
assert_contains "$HEALTH_OUTPUT" 'Unique wikilink targets: 8'
assert_contains "$HEALTH_OUTPUT" 'Broken links: 1 (error)'
assert_contains "$HEALTH_OUTPUT" 'Frontmatter violations: 1 (error)'
assert_contains "$HEALTH_OUTPUT" 'Secret-shaped strings: 1 (error)'
assert_contains "$HEALTH_OUTPUT" 'Orphans: 2 (warning)'
assert_contains "$HEALTH_OUTPUT" 'Duplicate basenames: 1 (warning)'
assert_contains "$HEALTH_OUTPUT" 'Status: FAIL'
assert_contains "$HEALTH_OUTPUT" 'target does not resolve: [[missing-note]]'
assert_contains "$HEALTH_OUTPUT" '[warning] [orphan] notes/lost.md'
assert_contains "$HEALTH_OUTPUT" '[error] [secret] notes/creds.md'
assert_not_contains "$HEALTH_OUTPUT" 'inline-code-link'
assert_not_contains "$HEALTH_OUTPUT" 'fenced-code-link'

grep -Fq -- '[[external-thing]]' <<<"$HEALTH_OUTPUT" &&
    fail 'An allowlisted link target was reported as broken.'

set +e
"$SCAN" --strict "$HEALTH_VAULT" >/dev/null 2>&1
STRICT_RC=$?
set -e
[ "$STRICT_RC" -eq 2 ] || fail "--strict did not exit 2 on error findings (got $STRICT_RC)"

JSON_OUTPUT=$("$SCAN" --json "$HEALTH_VAULT")
assert_contains "$JSON_OUTPUT" '"status": "FAIL"'
assert_contains "$JSON_OUTPUT" '"broken_links": 1'
assert_contains "$JSON_OUTPUT" '"orphans": 2'
assert_contains "$JSON_OUTPUT" '"category": "orphan"'
assert_contains "$JSON_OUTPUT" '"category": "secret"'

"$SCAN" --report "$HEALTH_VAULT" >/dev/null
[ -f "$HEALTH_VAULT/_reports/health-latest.md" ] ||
    fail 'The report envelope did not write health-latest.md.'
[ -f "$HEALTH_VAULT/_reports/health-latest.json" ] ||
    fail 'The report envelope did not write health-latest.json.'
head -n 1 "$HEALTH_VAULT/_reports/health-latest.md" | grep -q 'Status: \*\*FAIL\*\*' ||
    fail 'The report envelope does not lead with the status line.'
ls "$HEALTH_VAULT/_reports/archive/" | grep -q '^health-' ||
    fail 'A FAIL run did not write an archive copy.'

# A damaged latest JSON file must not make --report fail permanently.
: > "$HEALTH_VAULT/_reports/health-latest.json"
"$SCAN" --report "$HEALTH_VAULT" >/dev/null
grep -q '"fingerprint":' "$HEALTH_VAULT/_reports/health-latest.json" ||
    fail 'The scan did not replace a damaged latest JSON report.'

# The reports folder is a generated surface: scanning must exclude it.
HEALTH_OUTPUT_2=$("$SCAN" "$HEALTH_VAULT")
assert_contains "$HEALTH_OUTPUT_2" 'Total notes: 9'

# A clean vault: status OK, and repeated clean --report runs leave no archive.
CLEAN_HEALTH_VAULT="$TEST_DIR/clean-health-vault"
mkdir -p "$CLEAN_HEALTH_VAULT/.obsidian" "$CLEAN_HEALTH_VAULT/notes"
printf '%s\n' '## Purpose' '' 'A minimal clean vault.' > "$CLEAN_HEALTH_VAULT/VAULT.md"
printf '[[b]]\n' > "$CLEAN_HEALTH_VAULT/notes/a.md"
printf '[[a]]\n' > "$CLEAN_HEALTH_VAULT/notes/b.md"
"$SCAN" --report "$CLEAN_HEALTH_VAULT" >/dev/null
"$SCAN" --report "$CLEAN_HEALTH_VAULT" >/dev/null
head -n 1 "$CLEAN_HEALTH_VAULT/_reports/health-latest.md" | grep -q 'Status: \*\*OK\*\*' ||
    fail 'A clean vault did not report OK.'
[ ! -d "$CLEAN_HEALTH_VAULT/_reports/archive" ] ||
    fail 'Clean runs left archive residue.'

# Frontmatter aliases resolve in both supported YAML forms and earn inbound credit.
ALIAS_VAULT="$TEST_DIR/alias-vault"
mkdir -p "$ALIAS_VAULT/.obsidian" "$ALIAS_VAULT/notes"
printf '%s\n' '## Purpose' '' 'Alias resolution fixture.' > "$ALIAS_VAULT/VAULT.md"
printf '%s\n' '[[ML]] [[Deep Practice]]' > "$ALIAS_VAULT/notes/source.md"
printf '%s\n' '---' 'aliases: [ML, Machine Learning]' '---' \
    'machine learning body' > "$ALIAS_VAULT/notes/machine-learning.md"
printf '%s\n' '---' 'aliases:' '  - "Deep Practice"' '  - DP' '---' \
    'practice body' > "$ALIAS_VAULT/notes/deep-practice.md"
ALIAS_OUTPUT=$("$SCAN" "$ALIAS_VAULT")
assert_contains "$ALIAS_OUTPUT" 'Broken links: 0 (error)'
assert_not_contains "$ALIAS_OUTPUT" '[warning] [orphan] notes/machine-learning.md'
assert_not_contains "$ALIAS_OUTPUT" '[warning] [orphan] notes/deep-practice.md'

# An allowlisted target earns inbound credit after the target note exists.
ALLOWLIST_VAULT="$TEST_DIR/allowlist-vault"
mkdir -p "$ALLOWLIST_VAULT/.obsidian" "$ALLOWLIST_VAULT/notes"
printf '%s\n' '## Exclusions' '' '```yaml' 'link_allowlist:' \
    '  - planned' '```' > "$ALLOWLIST_VAULT/VAULT.md"
printf '[[planned]]\n' > "$ALLOWLIST_VAULT/notes/source.md"
printf 'planned body\n' > "$ALLOWLIST_VAULT/notes/planned.md"
ALLOWLIST_OUTPUT=$("$SCAN" "$ALLOWLIST_VAULT")
assert_contains "$ALLOWLIST_OUTPUT" 'Broken links: 0 (error)'
assert_not_contains "$ALLOWLIST_OUTPUT" '[warning] [orphan] notes/planned.md'

# Root files allowed by configuration do not need the note frontmatter schema.
ROOT_FM_VAULT="$TEST_DIR/root-frontmatter-vault"
mkdir -p "$ROOT_FM_VAULT/.obsidian"
printf '%s\n' '## Frontmatter Schema' '' '```yaml' 'required:' \
    '  - title: string' '```' '' '## Agent Behavior' '' '```yaml' \
    'root_allowed_files:' '  - VAULT.md' '  - README.md' '```' > "$ROOT_FM_VAULT/VAULT.md"
printf 'readme body without frontmatter\n' > "$ROOT_FM_VAULT/README.md"
ROOT_FM_OUTPUT=$("$SCAN" "$ROOT_FM_VAULT")
assert_contains "$ROOT_FM_OUTPUT" 'Frontmatter violations: 0 (error)'

# CRLF fences and quoted values work in frontmatter checks and exemptions.
CRLF_VAULT="$TEST_DIR/crlf-vault"
mkdir -p "$CRLF_VAULT/.obsidian" "$CRLF_VAULT/notes"
printf '%s\n' '## Frontmatter Schema' '' '```yaml' 'required:' \
    '  - title: string' '```' '' '## Agent Behavior' '' '```yaml' \
    'stale_after_days: 1' '```' > "$CRLF_VAULT/VAULT.md"
printf '%s\r\n' '---' 'title: Windows Note' 'type: "moc"' \
    'status: "active"' '---' 'body text' > "$CRLF_VAULT/notes/windows-note.md"
touch -d '3 days ago' "$CRLF_VAULT/notes/windows-note.md"
CRLF_OUTPUT=$("$SCAN" "$CRLF_VAULT")
assert_contains "$CRLF_OUTPUT" 'Frontmatter violations: 0 (error)'
assert_contains "$CRLF_OUTPUT" 'With frontmatter: 1'
assert_contains "$CRLF_OUTPUT" 'Orphans: 0 (warning)'
assert_contains "$CRLF_OUTPUT" 'Stale active notes: 1 (warning)'

# Unsafe report paths fall back to _reports and never write outside the vault.
UNSAFE_REPORT_VAULT="$TEST_DIR/unsafe-report-vault"
mkdir -p "$UNSAFE_REPORT_VAULT/.obsidian"
printf '%s\n' '## Agent Behavior' '' '```yaml' \
    'reports_folder: ../outside-target/' '```' > "$UNSAFE_REPORT_VAULT/VAULT.md"
"$SCAN" --report "$UNSAFE_REPORT_VAULT" >/dev/null 2>&1
[ -f "$UNSAFE_REPORT_VAULT/_reports/health-latest.json" ] ||
    fail 'An unsafe reports_folder did not fall back to _reports/.'
[ ! -e "$TEST_DIR/outside-target/health-latest.json" ] ||
    fail 'An unsafe reports_folder wrote outside the vault.'

DOT_REPORT_VAULT="$TEST_DIR/dot-report-vault"
mkdir -p "$DOT_REPORT_VAULT/.obsidian"
printf '%s\n' '## Agent Behavior' '' '```yaml' \
    'reports_folder: .' '```' > "$DOT_REPORT_VAULT/VAULT.md"
"$SCAN" --report "$DOT_REPORT_VAULT" >/dev/null 2>&1
[ -f "$DOT_REPORT_VAULT/_reports/health-latest.md" ] ||
    fail 'A root reports_folder did not fall back to _reports/.'
[ ! -f "$DOT_REPORT_VAULT/health-latest.md" ] ||
    fail 'The scan wrote a report into the vault root.'

EMPTY_REPORT_VAULT="$TEST_DIR/empty-report-vault"
mkdir -p "$EMPTY_REPORT_VAULT/.obsidian"
printf '%s\n' '## Agent Behavior' '' '```yaml' \
    'reports_folder:' '```' > "$EMPTY_REPORT_VAULT/VAULT.md"
EMPTY_REPORT_WARNING=$("$SCAN" --report "$EMPTY_REPORT_VAULT" 2>&1 >/dev/null)
assert_contains "$EMPTY_REPORT_WARNING" 'Ignore unsafe reports_folder: empty value'
[ -f "$EMPTY_REPORT_VAULT/_reports/health-latest.md" ] ||
    fail 'An empty reports_folder did not fall back to _reports/.'

ABSOLUTE_REPORT_VAULT="$TEST_DIR/absolute-report-vault"
ABSOLUTE_REPORT_TARGET="$TEST_DIR/absolute-report-target"
mkdir -p "$ABSOLUTE_REPORT_VAULT/.obsidian"
printf '%s\n' '## Agent Behavior' '' '```yaml' \
    "reports_folder: $ABSOLUTE_REPORT_TARGET" '```' > "$ABSOLUTE_REPORT_VAULT/VAULT.md"
"$SCAN" --report "$ABSOLUTE_REPORT_VAULT" >/dev/null 2>&1
[ -f "$ABSOLUTE_REPORT_VAULT/_reports/health-latest.md" ] ||
    fail 'An absolute reports_folder did not fall back to _reports/.'
[ ! -e "$ABSOLUTE_REPORT_TARGET" ] ||
    fail 'An absolute reports_folder wrote outside the vault.'

READ_ONLY_REPORT_VAULT="$TEST_DIR/read-only-report-vault"
mkdir -p "$READ_ONLY_REPORT_VAULT/.obsidian" "$READ_ONLY_REPORT_VAULT/locked"
printf '%s\n' '## Exclusions' '' '```yaml' 'read_only_paths:' \
    '  - locked/' '```' '' '## Agent Behavior' '' '```yaml' \
    'reports_folder: locked/reports/' '```' > "$READ_ONLY_REPORT_VAULT/VAULT.md"
"$SCAN" --report "$READ_ONLY_REPORT_VAULT" >/dev/null 2>&1
[ -f "$READ_ONLY_REPORT_VAULT/_reports/health-latest.md" ] ||
    fail 'A read-only reports_folder did not fall back to _reports/.'
[ ! -e "$READ_ONLY_REPORT_VAULT/locked/reports" ] ||
    fail 'The scan wrote into a read-only path.'

# Repeated standing warnings produce one incident archive.
WARN_REPORT_VAULT="$TEST_DIR/warn-report-vault"
mkdir -p "$WARN_REPORT_VAULT/.obsidian" "$WARN_REPORT_VAULT/notes"
printf '%s\n' '## Purpose' '' 'Archive fixture.' > "$WARN_REPORT_VAULT/VAULT.md"
printf 'standing orphan\n' > "$WARN_REPORT_VAULT/notes/orphan.md"
"$SCAN" --report "$WARN_REPORT_VAULT" >/dev/null
FIRST_ARCHIVE_COUNT=$(find "$WARN_REPORT_VAULT/_reports/archive" -type f | wc -l)
sleep 1
"$SCAN" --report "$WARN_REPORT_VAULT" >/dev/null
SECOND_ARCHIVE_COUNT=$(find "$WARN_REPORT_VAULT/_reports/archive" -type f | wc -l)
[ "$FIRST_ARCHIVE_COUNT" -eq 1 ] && [ "$SECOND_ARCHIVE_COUNT" -eq 1 ] ||
    fail 'An unchanged warning produced another incident archive.'

grep -q 'generated_files:' "$REPO_DIR/assets/vault-md-template.md" ||
    fail 'The starter template has no generated_files key.'
grep -q 'reports_folder:' "$REPO_DIR/assets/vault-md-template.md" ||
    fail 'The starter template has no reports_folder key.'
grep -A8 '^excluded_paths:$' "$REPO_DIR/assets/vault-md-template.md" |
    grep -q '^  - _reports/$' || fail 'The starter template does not exclude _reports/.'

# --- Open-items scan: ranking, quick wins, integrity, envelope -----------------

ITEMS="$REPO_DIR/scripts/open-items-scan.sh"
[ -x "$ITEMS" ] || fail 'The open-items scanner is not executable.'
ITEMS_VAULT="$TEST_DIR/items-vault"
mkdir -p "$ITEMS_VAULT/.obsidian" "$ITEMS_VAULT/90-system"
printf '%s\n' \
    '## Agent Behavior' \
    '' \
    '```yaml' \
    'open_items_tracker: 90-system/open-items.md' \
    'urgent_stale_days: 2' \
    '```' > "$ITEMS_VAULT/VAULT.md"
OLD_DATE=$(date -u -d '10 days ago' +%Y-%m-%d 2>/dev/null ||
    date -u -v-10d +%Y-%m-%d)
TODAY=$(date -u +%Y-%m-%d)
{
    printf '| ID | Item | Area | Notes |\n'
    printf '| --- | --- | --- | --- |\n'
    printf '| U1 🆕 | **Repair broken MOC links** | hygiene | Opened %s. Owner: **operator**. Three links broken; next: run health scan. |\n' "$OLD_DATE"
    printf '| W2 | **Reorganize resources folder** | structure | Opened %s. Owner: **agent**. Plan drafted; next: apply moves. |\n' "$TODAY"
    printf '| D3 | **Choose archive policy** | policy | Opened %s. Decision pending. |\n' "$TODAY"
    printf '| B4 (quick) | **Tag the three untagged notes** | hygiene | Opened %s. Owner: **agent**. Next: assign taxonomy tags. |\n' "$TODAY"
    printf '| ~~B1~~ ✅ | **Draft research note** | research | Opened %s. Owner: **agent**. Resolved: drafted and linked. |\n' "$OLD_DATE"
    printf '| W2 | **Duplicate row** | structure | Opened %s. Owner: **agent**. |\n' "$TODAY"
} > "$ITEMS_VAULT/90-system/open-items.md"

ITEMS_OUTPUT=$("$ITEMS" "$ITEMS_VAULT")
assert_contains "$ITEMS_OUTPUT" 'Open items: 4'
assert_contains "$ITEMS_OUTPUT" 'Struck items: 1'
assert_contains "$ITEMS_OUTPUT" 'Quick wins: 1'
assert_contains "$ITEMS_OUTPUT" 'B4 — Tag the three untagged notes'
assert_contains "$ITEMS_OUTPUT" 'ID W2 already used'
assert_contains "$ITEMS_OUTPUT" "opened 10 days ago — 'U' items should close within 2 days"
assert_contains "$ITEMS_OUTPUT" 'D3 has no '"'"'Owner:'"'"''
assert_contains "$ITEMS_OUTPUT" 'Status: FAIL'
assert_contains "$ITEMS_OUTPUT" 'B: B5'
FIRST_OPEN_LINE=$(grep -A1 '=== Open (by urgency, then age) ===' <<<"$ITEMS_OUTPUT" |
    tail -n 1)
grep -Fq 'U1' <<<"$FIRST_OPEN_LINE" ||
    fail 'The most urgent item is not ranked first.'

set +e
"$ITEMS" --strict "$ITEMS_VAULT" >/dev/null 2>&1
ITEMS_STRICT_RC=$?
set -e
[ "$ITEMS_STRICT_RC" -eq 2 ] ||
    fail "--strict did not exit 2 on a duplicate ID (got $ITEMS_STRICT_RC)"

ITEMS_JSON=$("$ITEMS" --json "$ITEMS_VAULT")
assert_contains "$ITEMS_JSON" '"status": "FAIL"'
assert_contains "$ITEMS_JSON" '"open": 4'
assert_contains "$ITEMS_JSON" '"quick_win": 1'
assert_contains "$ITEMS_JSON" '"B": "B5"'

"$ITEMS" --report "$ITEMS_VAULT" >/dev/null
[ -f "$ITEMS_VAULT/_reports/open-items-latest.md" ] ||
    fail 'The open-items envelope did not write open-items-latest.md.'
[ -f "$ITEMS_VAULT/_reports/open-items-latest.json" ] ||
    fail 'The open-items envelope did not write open-items-latest.json.'
head -n 1 "$ITEMS_VAULT/_reports/open-items-latest.md" | grep -q 'Status: \*\*FAIL\*\*' ||
    fail 'The open-items envelope does not lead with the status line.'

# A vault with no tracker yet is a valid starting state, not a finding.
NO_TRACKER_VAULT="$TEST_DIR/no-tracker-vault"
mkdir -p "$NO_TRACKER_VAULT/.obsidian"
printf '%s\n' '## Purpose' '' 'Fresh vault.' > "$NO_TRACKER_VAULT/VAULT.md"
NO_TRACKER_OUTPUT=$("$ITEMS" "$NO_TRACKER_VAULT")
assert_contains "$NO_TRACKER_OUTPUT" 'No tracker file found'
assert_contains "$NO_TRACKER_OUTPUT" 'Status: OK'

# A tracker inside read_only_paths is a broken configuration, not scannable state.
RO_TRACKER_VAULT="$TEST_DIR/ro-tracker-vault"
mkdir -p "$RO_TRACKER_VAULT/.obsidian" "$RO_TRACKER_VAULT/locked"
printf '%s\n' \
    '## Exclusions' \
    '' \
    '```yaml' \
    'read_only_paths:' \
    '  - locked/' \
    '```' \
    '' \
    '## Agent Behavior' \
    '' \
    '```yaml' \
    'open_items_tracker: locked/open-items.md' \
    '```' > "$RO_TRACKER_VAULT/VAULT.md"
printf '| U1 | **x** | a | Opened 2026-01-01. Owner: **o**. |\n' > "$RO_TRACKER_VAULT/locked/open-items.md"
RO_TRACKER_OUTPUT=$("$ITEMS" "$RO_TRACKER_VAULT")
assert_contains "$RO_TRACKER_OUTPUT" 'open_items_tracker sits inside read_only_paths'
assert_not_contains "$RO_TRACKER_OUTPUT" 'Open items: 1'

# An excluded tracker must not be read or copied into scanner output.
EXCLUDED_TRACKER_VAULT="$TEST_DIR/excluded-tracker-vault"
mkdir -p "$EXCLUDED_TRACKER_VAULT/.obsidian" "$EXCLUDED_TRACKER_VAULT/private"
printf '%s\n' \
    '## Exclusions' \
    '' \
    '```yaml' \
    'excluded_paths:' \
    '  - private/' \
    '```' \
    '' \
    '## Agent Behavior' \
    '' \
    '```yaml' \
    'open_items_tracker: private/open-items.md' \
    '```' > "$EXCLUDED_TRACKER_VAULT/VAULT.md"
printf '| U1 | **private item title** | a | Opened %s. Owner: **o**. |\n' "$TODAY" \
    > "$EXCLUDED_TRACKER_VAULT/private/open-items.md"
EXCLUDED_TRACKER_OUTPUT=$("$ITEMS" "$EXCLUDED_TRACKER_VAULT")
assert_contains "$EXCLUDED_TRACKER_OUTPUT" 'open_items_tracker sits inside excluded_paths'
assert_not_contains "$EXCLUDED_TRACKER_OUTPUT" 'private item title'

# A read-only reports folder falls back to _reports without changing that path.
RO_REPORT_VAULT="$TEST_DIR/read-only-open-items-report-vault"
mkdir -p "$RO_REPORT_VAULT/.obsidian" "$RO_REPORT_VAULT/locked"
printf '%s\n' \
    '## Exclusions' \
    '' \
    '```yaml' \
    'read_only_paths:' \
    '  - locked/' \
    '```' \
    '' \
    '## Agent Behavior' \
    '' \
    '```yaml' \
    'reports_folder: locked/reports/' \
    '```' > "$RO_REPORT_VAULT/VAULT.md"
RO_REPORT_WARNING=$("$ITEMS" --report "$RO_REPORT_VAULT" 2>&1 >/dev/null)
assert_contains "$RO_REPORT_WARNING" 'Ignore read-only reports_folder: locked/reports/'
[ -f "$RO_REPORT_VAULT/_reports/open-items-latest.md" ] ||
    fail 'A read-only reports folder did not fall back to _reports/.'
[ ! -e "$RO_REPORT_VAULT/locked/reports" ] ||
    fail 'The open-items scanner wrote into a read-only path.'

# Configured ID series get a next ID even when no row uses the series yet.
EMPTY_TRACKER_VAULT="$TEST_DIR/empty-tracker-vault"
mkdir -p "$EMPTY_TRACKER_VAULT/.obsidian" "$EMPTY_TRACKER_VAULT/90-system"
printf '%s\n' '## Purpose' '' 'Empty tracker fixture.' > "$EMPTY_TRACKER_VAULT/VAULT.md"
printf '%s\n' '| ID | Item | Area | Notes |' '| --- | --- | --- | --- |' \
    > "$EMPTY_TRACKER_VAULT/90-system/open-items.md"
EMPTY_TRACKER_JSON=$("$ITEMS" --json "$EMPTY_TRACKER_VAULT")
assert_contains "$EMPTY_TRACKER_JSON" '"U": "U1"'
assert_contains "$EMPTY_TRACKER_JSON" '"D": "D1"'
assert_contains "$EMPTY_TRACKER_JSON" '"W": "W1"'
assert_contains "$EMPTY_TRACKER_JSON" '"B": "B1"'

# ID parsing must reject trailing characters that are part of the ID token.
MALFORMED_ID_VAULT="$TEST_DIR/malformed-id-vault"
mkdir -p "$MALFORMED_ID_VAULT/.obsidian" "$MALFORMED_ID_VAULT/90-system"
printf '%s\n' '## Purpose' '' 'Malformed ID fixture.' > "$MALFORMED_ID_VAULT/VAULT.md"
printf '| U1junk | **Malformed item** | a | Opened %s. Owner: **o**. |\n' "$TODAY" \
    > "$MALFORMED_ID_VAULT/90-system/open-items.md"
MALFORMED_ID_OUTPUT=$("$ITEMS" "$MALFORMED_ID_VAULT")
assert_contains "$MALFORMED_ID_OUTPUT" 'unparseable ID cell: U1junk'
assert_contains "$MALFORMED_ID_OUTPUT" 'Open items: 0'

# A change to the open queue does not change an unchanged findings fingerprint.
FINGERPRINT_VAULT="$TEST_DIR/open-items-fingerprint-vault"
mkdir -p "$FINGERPRINT_VAULT/.obsidian" "$FINGERPRINT_VAULT/90-system"
printf '%s\n' '## Purpose' '' 'Fingerprint fixture.' > "$FINGERPRINT_VAULT/VAULT.md"
printf '| W1 | **Needs owner** | a | Opened %s. |\n' "$TODAY" \
    > "$FINGERPRINT_VAULT/90-system/open-items.md"
"$ITEMS" --report "$FINGERPRINT_VAULT" >/dev/null
FIRST_ITEMS_FINGERPRINT=$(grep -o '"fingerprint": "[^"]*"' \
    "$FINGERPRINT_VAULT/_reports/open-items-latest.json")
printf '| B1 | **Unrelated valid item** | a | Opened %s. Owner: **agent**. |\n' "$TODAY" \
    >> "$FINGERPRINT_VAULT/90-system/open-items.md"
"$ITEMS" --report "$FINGERPRINT_VAULT" >/dev/null
SECOND_ITEMS_FINGERPRINT=$(grep -o '"fingerprint": "[^"]*"' \
    "$FINGERPRINT_VAULT/_reports/open-items-latest.json")
[ "$FIRST_ITEMS_FINGERPRINT" = "$SECOND_ITEMS_FINGERPRINT" ] ||
    fail 'An open-queue change altered an unchanged findings fingerprint.'
[ "$(find "$FINGERPRINT_VAULT/_reports/archive" -type f | wc -l)" -eq 1 ] ||
    fail 'An open-queue change produced another incident archive.'

grep -q 'open_items_tracker:' "$REPO_DIR/assets/vault-md-template.md" ||
    fail 'The starter template has no open_items_tracker key.'
grep -q 'quick_win_marker:' "$REPO_DIR/assets/vault-md-template.md" ||
    fail 'The starter template has no quick_win_marker key.'

echo 'All tests passed.'
