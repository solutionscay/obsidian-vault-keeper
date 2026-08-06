#!/usr/bin/env bash
# vault-health-scan.sh — Quick vault health diagnostics
# Usage: bash vault-health-scan.sh /path/to/vault
#
# Produces a summary report of vault health metrics.
# Designed to be run by an agent or manually from the terminal.

set -euo pipefail

VAULT_DIR="${1:-.}"

if [ ! -d "$VAULT_DIR" ]; then
    echo "Error: $VAULT_DIR is not a directory"
    exit 1
fi

if [ ! -d "$VAULT_DIR/.obsidian" ]; then
    echo "Warning: No .obsidian/ directory found. This may not be an Obsidian vault."
fi

echo "=== Vault Health Scan ==="
echo "Vault: $VAULT_DIR"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Count total notes
TOTAL_NOTES=$(find "$VAULT_DIR" -name "*.md" \
    -not -path "*/.obsidian/*" \
    -not -path "*/.git/*" \
    -not -path "*/.trash/*" \
    -not -path "*/node_modules/*" | wc -l)
echo "Total notes: $TOTAL_NOTES"

# Count notes by folder (top-level)
echo ""
echo "=== Notes by Folder ==="
find "$VAULT_DIR" -maxdepth 1 -type d -not -name ".*" -not -path "$VAULT_DIR" | sort | while read -r dir; do
    count=$(find "$dir" -name "*.md" 2>/dev/null | wc -l)
    dirname=$(basename "$dir")
    if [ "$count" -gt 0 ]; then
        echo "  $dirname/: $count"
    fi
done

# Root-level notes
ROOT_NOTES=$(find "$VAULT_DIR" -maxdepth 1 -name "*.md" | wc -l)
echo "  (root): $ROOT_NOTES"

# Notes without frontmatter
echo ""
echo "=== Frontmatter Check ==="
NO_FM=0
HAS_FM=0
while IFS= read -r file; do
    if head -1 "$file" 2>/dev/null | grep -q "^---$"; then
        HAS_FM=$((HAS_FM + 1))
    else
        NO_FM=$((NO_FM + 1))
    fi
done < <(find "$VAULT_DIR" -name "*.md" \
    -not -path "*/.obsidian/*" \
    -not -path "*/.git/*" \
    -not -path "*/.trash/*")
echo "  With frontmatter: $HAS_FM"
echo "  Without frontmatter: $NO_FM"

# Empty or near-empty notes
echo ""
echo "=== Content Check ==="
EMPTY=0
STUB=0
while IFS= read -r file; do
    # Count words excluding frontmatter
    body_words=$(awk '/^---$/{if(++c==2) next; if(c==1) next} c>=2{print}' "$file" 2>/dev/null | wc -w)
    if [ "$body_words" -lt 5 ]; then
        EMPTY=$((EMPTY + 1))
    elif [ "$body_words" -lt 50 ]; then
        STUB=$((STUB + 1))
    fi
done < <(find "$VAULT_DIR" -name "*.md" \
    -not -path "*/.obsidian/*" \
    -not -path "*/.git/*" \
    -not -path "*/.trash/*")
echo "  Empty notes (<5 words): $EMPTY"
echo "  Stub notes (<50 words): $STUB"

# Collect all wikilinks and check for broken ones
echo ""
echo "=== Link Count (baseline; no broken-link detection) ==="
ALL_LINKS=$(grep -roh '\[\[[^]]*\]\]' "$VAULT_DIR" \
    --include="*.md" \
    --exclude-dir=".obsidian" \
    --exclude-dir=".git" \
    --exclude-dir=".trash" 2>/dev/null | \
    sed 's/\[\[//;s/\]\]//;s/|.*//' | \
    sort -u | wc -l)
echo "  Unique wikilink targets: $ALL_LINKS"

# Count all unique tags
echo ""
echo "=== Tag Count (baseline; raw #hashtag strings, may include anchors) ==="
ALL_TAGS=$(grep -roh '#[a-zA-Z][a-zA-Z0-9_/\-]*' "$VAULT_DIR" \
    --include="*.md" \
    --exclude-dir=".obsidian" \
    --exclude-dir=".git" \
    --exclude-dir=".trash" 2>/dev/null | \
    sort -u | wc -l)
echo "  Unique tags: $ALL_TAGS"

# Check for VAULT.md
echo ""
echo "=== Configuration ==="
if [ -f "$VAULT_DIR/VAULT.md" ]; then
    echo "  VAULT.md: found"
else
    echo "  VAULT.md: MISSING (run Vault Keeper to generate one)"
fi

# Check for git
if [ -d "$VAULT_DIR/.git" ]; then
    LAST_COMMIT=$(cd "$VAULT_DIR" && git log -1 --format="%ar" 2>/dev/null || echo "unknown")
    echo "  Git: initialized (last commit: $LAST_COMMIT)"
else
    echo "  Git: not initialized (a no-git vault may define snapshot-based recovery in VAULT.md external_archive)"
fi

echo ""
echo "=== Scan Complete ==="
