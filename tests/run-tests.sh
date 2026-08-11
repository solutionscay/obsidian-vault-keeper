#!/usr/bin/env bash

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
SCAN="$REPO_DIR/scripts/vault-health-scan.sh"
SELECT="$REPO_DIR/scripts/curator-domain-select.sh"
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

ROTATION_OUTPUT=$("$SELECT" 'Domain A' 3 '' 'Domain A' 'Domain B')
assert_contains "$ROTATION_OUTPUT" 'Domain: Domain B'
assert_contains "$ROTATION_OUTPUT" 'Decision: rotate-after-three'

if "$SELECT" 'Domain A' 3 '' 'Domain A' >/dev/null 2>&1; then
    fail 'The selector permitted a fourth autonomous run in Domain A.'
fi

RENEWAL_OUTPUT=$("$SELECT" 'Domain A' 3 'Domain A' 'Domain A' 'Domain B')
assert_contains "$RENEWAL_OUTPUT" 'Domain: Domain A'
assert_contains "$RENEWAL_OUTPUT" 'Decision: operator-renewal'

grep -A3 '^## Expansion Domains$' "$REPO_DIR/assets/vault-md-template.md" |
    grep -q '^```yaml$' || fail 'The starter template has no Expansion Domains YAML block.'
grep -A5 '^## Expansion Domains$' "$REPO_DIR/assets/vault-md-template.md" |
    grep -q '^domains:$' || fail 'The starter template has no canonical domains key.'

echo 'All tests passed.'
