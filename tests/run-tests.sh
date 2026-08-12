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

echo 'All tests passed.'
