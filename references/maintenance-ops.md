# Maintenance Operations Reference

Detailed procedures for each Steward operation. The SKILL.md defines the what;
this file defines the how.

## Table of Contents

1. [Health Scan Procedure](#health-scan-procedure)
2. [Rename Operations](#rename-operations)
3. [Frontmatter Standardization](#frontmatter-standardization)
4. [Tag Cleanup](#tag-cleanup)
5. [Duplicate Detection and Merge](#duplicate-detection-and-merge)
6. [Link Maintenance](#link-maintenance)
7. [MOC Generation](#moc-generation)
8. [Formatting Normalization](#formatting-normalization)
9. [Folder Organization](#folder-organization)

---

## Health Scan Procedure

### Step 1 — Build the vault index

Walk the vault directory tree, excluding paths in VAULT.md `exclusions`.
For each `.md` file, extract:

- File path and name
- Frontmatter (parsed as YAML)
- All outbound wikilinks `[[target]]` and `[[target|alias]]`
- All tags (both frontmatter `tags:` and inline `#tag`)
- Word count of body content (excluding frontmatter)
- Last modified date (from the VAULT.md-declared modification-date field, else filesystem mtime)

Store this as a working index for all subsequent phases.

### Step 2 — Run diagnostic checks

**Orphan detection:**
- Build an inbound link map: for each note, count how many other notes link to it
- Orphans = notes with zero inbound links
- Exclude from orphan report: daily notes, templates, MOCs, VAULT.md, README
- Severity: low (resource notes can be orphans legitimately), medium (project/area notes)

**Broken link detection:**
- For each outbound wikilink, verify the target file exists
- Check both exact match and case-insensitive match
- Check aliases in frontmatter of all notes
- Report: source file, broken link text, closest match suggestion

**Duplicate detection:**
- Normalize titles: lowercase, strip date prefixes, strip special chars
- Flag pairs with Levenshtein distance < 3 or Jaccard similarity > 0.7
- For flagged pairs, compare first 200 words of body for content overlap
- Report: both files, similarity score, recommended primary (more links wins)

**Frontmatter violations:**
- Compare each note's frontmatter against VAULT.md `required` schema
- Report: file, missing fields, malformed fields (wrong type, invalid enum value)

**Naming violations:**
- Check each filename against VAULT.md naming conventions
- Report: current name, violation type, suggested corrected name

**Tag anomalies:**
- Collect all unique tags across the vault
- Compare against VAULT.md `valid_tags` taxonomy
- Fuzzy-match unrecognized tags to find typo variants (e.g., `#tech/ia` → `#tech/ai`)
- Report: unknown tag, occurrence count, suggested correction

**Empty/stub notes:**
- Body content < 20 chars = empty
- Body content < 100 words = stub
- Report with creation date (older stubs are more likely abandoned)

### Step 3 — Generate the report

Format as a Markdown summary with counts per category, then a collapsible
details section for each. Example:

```markdown
## Vault Health Report — 2026-08-06

| Category | Count | Severity |
|----------|-------|----------|
| Orphan notes | 23 | low |
| Broken links | 7 | high |
| Duplicate candidates | 4 | medium |
| Frontmatter violations | 31 | medium |
| Naming violations | 12 | low |
| Tag anomalies | 8 | low |
| Empty/stub notes | 15 | low |

Total notes scanned: 342
Vault health score: 78/100
```

---

## Rename Operations

Renaming is the highest-risk maintenance operation because it can break links.

### Procedure

1. Determine the correct name per VAULT.md conventions
2. Search the entire vault for wikilinks pointing to the old name:
   - `[[old-name]]`
   - `[[old-name|display text]]`
   - `[[old-name#heading]]`
   - Markdown links: `[text](old-name.md)`
3. Build the rename plan: original path → new path + list of files with
   inbound links to update
4. If >3 files affected, show preview table and wait for approval
5. Execute: rename file, then update all inbound links in a single pass
6. If the vault uses aliases, add the old name as an alias in the renamed
   file's frontmatter
7. Verify: re-scan for any remaining references to the old name

### Edge Cases

- **Daily notes**: never rename (they follow a date convention)
- **MOCs**: rename cautiously — they're high-link-count hubs
- **Files with embeddings** `![[old-name]]`: update these too
- **Canvas files**: if `.canvas` files reference the note, update those references

---

## Frontmatter Standardization

### Procedure

1. Read the required schema from VAULT.md
2. For each note with violations:
   - Add each field named in VAULT.md `required`, deriving values sensibly: a
     string field from the filename or first H1, a date field from file mtime, an
     enum field set to a valid VAULT.md value. Do not add `title`, `created`,
     `tags`, or any key the vault schema omits.
   - Fix type mismatches (string where list expected, etc.)
   - Preserve all existing valid fields — never strip unknown properties
   - Fix YAML syntax errors (unclosed quotes, bad indentation)
3. For notes with no frontmatter at all:
   - Insert a complete frontmatter block at the top
   - Use the first H1 as the `title` if present

### YAML Gotchas

- Strings containing colons need quoting: `title: "Note: A Subtitle"`
- Dates should be ISO 8601: `2026-08-06`
- Lists can be flow `[a, b]` or block (one per line) — match vault convention
- Boolean-like strings need quoting: `"yes"`, `"no"`, `"true"`
- Never use tabs in YAML — spaces only

---

## Tag Cleanup

### Procedure

1. Build tag frequency map across the vault
2. For each tag not in VAULT.md taxonomy:
   - If fuzzy match to a valid tag (edit distance ≤ 2): propose correction
   - If no match: propose adding to taxonomy or removing
3. Apply corrections in bulk (with preview if >3 files)
4. Update tag index/MOC if one exists

### Handling Nested Tags

Obsidian supports nested tags like `#tech/ai/agents`. When cleaning:
- Validate each level exists in the hierarchy
- Don't flatten valid nested tags
- Suggest nesting for flat tags that belong under a parent

---

## Duplicate Detection and Merge

### Merge Procedure

Before you merge: skip folder-note vs `00-Index` (or other hub) pairs — they are not
duplicates. Never select a hub note to be archived, and do not rely on raw inbound-link
count to pick the primary for hub notes (hubs show zero inbound links). Confirm more than
200 words of body overlap before you propose any merge, and check the merge against
VAULT.md structural invariants (for example, every folder keeps its hub).

1. Present both notes side by side with a diff view
2. Identify the "primary" note (more inbound links, richer content, better name)
3. Draft a merged version that:
   - Keeps the primary's frontmatter as base, merges unique tags/aliases
   - Combines body content with clear section attribution where origins differ
   - Preserves all source URLs from both notes
   - Takes the earlier `created` date
4. Show the merged draft for approval
5. On approval:
   - Write the merged content to the primary note
   - Replace the duplicate with a forwarding stub. Keep the vault's required keys
     (for example `type`, `updated`) and use an allowed status value:
     ```markdown
     ---
     # keep the vault's required keys (for example type, updated)
     status: <the vault's archive/retired status, if the enum defines one>
     aliases: ["<the duplicate's plain title>"]
     ---
     > [!info] This note has been merged into [[primary-note]].
     ```
   - Give the stub a collision-safe name in the archive folder (prefix with the
     source folder or the date, for example `_archive/CLI-Artist-Prompts--00-Index.md`),
     and check for an existing file before you move it
   - Update all inbound links that pointed to the duplicate

---

## Link Maintenance

### Broken Link Repair

For each broken link:
1. Search for notes with similar names (fuzzy match)
2. Search for notes containing the broken link text in their aliases
3. If a clear match exists (similarity > 0.85): propose the fix
4. If ambiguous: present options to the user
5. If no match: the link may reference a note that should exist — flag for
   Curator mode gap analysis

### Orphan Integration

For orphan notes that aren't daily notes or templates:
1. Read the orphan's content and tags
2. Find related notes via tag overlap and content similarity
3. Propose adding wikilinks from related notes to the orphan
4. Propose adding the orphan to relevant MOCs

---

## MOC Generation

Maps of Content are index notes that organize a topic area.

### Procedure

1. Identify the topic scope (from tag, folder, or user specification). Check VAULT.md
   for a hub-file convention first (for example a `00-Index.md` per folder): if one
   exists, the MOC IS that hub file — update it in place, and never create a parallel
   MOC note beside it. Otherwise use a MOC or index folder if VAULT.md defines one,
   else place the MOC next to the topic folder. A topic area is normally one top-level
   folder; where an `expansion_domain` spans several folders, make one MOC per folder
   and cross-link them.
2. Gather all notes matching the scope
3. Group by subtopic (using tags, folder, or content clustering)
4. Draft the MOC. Build the frontmatter from the VAULT.md schema; the block below is
   an illustrative example for a schema-less vault, so do not copy its keys verbatim
   when the vault defines a schema:

```markdown
---
title: "Map of Content — [Topic]"
type: moc
tags: [topic-tag]
created: [date]
status: active
---

# [Topic]

Brief description of what this topic covers in the vault.

## Subtopic A
- [[note-1]] — one-line summary
- [[note-2]] — one-line summary

## Subtopic B
- [[note-3]] — one-line summary

## Related
- [[other-moc]]

## Gaps
- [Topic X] — no notes yet, consider researching
```

5. Add the MOC to any parent MOCs or the vault's main index

### Update vs. Create

If a MOC already exists for the topic, update it rather than creating a new one:
- Add notes that were created since the MOC was last updated
- Remove links to notes that no longer exist
- Reorganize subtopics if the structure has shifted

---

## Formatting Normalization

### Procedure

Apply formatting rules from VAULT.md `formatting_rules` section. Defaults:

1. **Heading hierarchy**: Ensure no skipped levels (H1 → H3 without H2)
2. **Single H1**: Keep one H1 per note (the first, or the one that matches the
   filename). Demote extra H1s to H2 and flag the note for review.
3. **Bold normalization**: Keep a bold inline label ending in a colon inside a list
   item (for example `- **Note:** ...`). Convert a bold-only line that sits directly
   above a paragraph into a heading at the `heading_start` level. Leave inline
   emphasis inside prose unchanged.
4. **Whitespace**: Collapse blank-line runs to the VAULT.md `blank_lines` value
   (default 1)
5. **Lists**: Normalize to configured style (dash/asterisk/plus)
6. **Code blocks**: Add language tags to bare fenced blocks where detectable
7. **Callouts**: Normalize to Obsidian callout syntax `> [!type]`
8. **Trailing whitespace**: Strip from all lines
9. **Final newline**: Ensure file ends with exactly one newline

### Conversion-artifact cleanup (gated)

Notes converted from PDF, HTML, or DOCX often carry scrape cruft. This step rewrites
body text, so treat it as a bulk change: show a preview and wait for approval. Remove
or repair:

- Navigation and chrome: cookie banners, nav breadcrumbs, "skip to content",
  share/print widgets, video-player labels, footer boilerplate
- Broken structure: split list numbers (a `1.` alone on the line above the item text),
  drop-cap artifacts (a lone capital letter as a false heading), and heading text
  merged into the previous paragraph
- Garbled tables: word-art or decorative graphics the converter turned into tables —
  delete them, or rebuild the table if it holds real data
- Dead link fragments: `[back to text](#anchorNNNN)` return links and similar

Do not delete content you cannot classify — flag it for review instead.

### What NOT to Touch

- Do not reflow paragraphs (people have intentional line breaks)
- Do not change heading text (only structure)
- Do not modify content inside code blocks
- Do not alter content inside `> [!quote]` callouts (they may be exact quotes)
- Do not modify embedded content `![[embed]]`

---

## Folder Organization

### Misplacement Detection

Compare each note's current folder against its `type` or `status` frontmatter:

| type | expected folder |
|------|----------------|
| daily | Daily Notes/ (or vault convention) |
| project | projects/ |
| moc | wherever MOCs live |
| reference | resources/ |
| archived | archive/ |

Also check: does the note's tags suggest it belongs to a different area?

### Move Procedure

1. Propose the move with reason
2. On approval: move the file
3. Update all inbound links to use the new path (if vault uses full paths)
4. If vault uses shortest-path wikilinks, no link updates needed (Obsidian
   resolves these automatically)
5. Verify no broken links resulted from the move
