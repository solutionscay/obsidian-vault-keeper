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
    "$ORGANIZE_VAULT/notes" "$ORGANIZE_VAULT/read-only"
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
    '  - generated/' \
    'link_allowlist:' \
    '  - external-thing' \
    'accepted_orphan_zones:' \
    '  - daily/' \
    '```' > "$HEALTH_VAULT/VAULT.md"
printf '%s\n' '---' 'title: Alpha' '---' \
    '[[beta]] [[missing-note]] [[external-thing]] [[creds]]' > "$HEALTH_VAULT/notes/alpha.md"
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
assert_contains "$HEALTH_OUTPUT" 'Broken links: 1 (error)'
assert_contains "$HEALTH_OUTPUT" 'Frontmatter violations: 1 (error)'
assert_contains "$HEALTH_OUTPUT" 'Secret-shaped strings: 1 (error)'
assert_contains "$HEALTH_OUTPUT" 'Orphans: 2 (warning)'
assert_contains "$HEALTH_OUTPUT" 'Duplicate basenames: 1 (warning)'
assert_contains "$HEALTH_OUTPUT" 'Status: FAIL'
assert_contains "$HEALTH_OUTPUT" 'target does not resolve: [[missing-note]]'
assert_contains "$HEALTH_OUTPUT" '[warning] [orphan] notes/lost.md'
assert_contains "$HEALTH_OUTPUT" '[error] [secret] notes/creds.md'

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

grep -q 'generated_files:' "$REPO_DIR/assets/vault-md-template.md" ||
    fail 'The starter template has no generated_files key.'
grep -q 'reports_folder:' "$REPO_DIR/assets/vault-md-template.md" ||
    fail 'The starter template has no reports_folder key.'

echo 'All tests passed.'
