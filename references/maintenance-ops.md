# Maintenance Operations Reference

Detailed procedures for each Steward operation. The SKILL.md defines the what;
this file defines the how.

Vault Keeper operates autonomously by default. Execute clear repairs, renames, merges,
moves, formatting, and conversion cleanup after the required snapshot. Record bulk
changes in the session summary. There is no preview mode: recording a change never
means waiting on it. Defer only ambiguous or unsafe actions, then continue with the
next target.

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

Walk the vault directory tree. Skip paths in VAULT.md `excluded_paths` and
`read_only_paths`.
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
- Exclude paths in VAULT.md `accepted_orphan_zones`
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

**Under-tagged notes:**
- Count taxonomy tags per note (frontmatter `tags:` plus inline `#tag`)
- Flag notes below the VAULT.md `tag_floor` (default 1), including empty or absent `tags`
- Exclude daily notes, templates, and structural hubs (`00-Index`, numbered sections)
- Report: file, current tag count, candidate tags from content

**Sparse frontmatter:**
- For each note, list schema-defined optional properties that are empty or absent
- Flag only those with a derivable value in the note (a body source URL for `source`,
  an alternate title for `aliases`, a clear subject for `topic`)
- Report: file, empty properties that could be populated

**Empty/stub notes:**
- Body content with fewer than 20 non-whitespace characters is empty
- A non-empty body with fewer than 100 words is a stub
- Report with creation date (older stubs are more likely abandoned)

**Root folder:**
- List all root Markdown files
- Remove files in VAULT.md `root_allowed_files` from the list
- Classify each remaining file as a misplaced root note
- Report the total, allowed, and misplaced counts
- Report each misplaced root note path

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
| Sparse frontmatter | 44 | low |
| Naming violations | 12 | low |
| Tag anomalies | 8 | low |
| Under-tagged notes | 58 | medium |
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
4. If more files are affected than `bulk_report_above`, record a change table
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

1. Read the required and optional schema from VAULT.md
2. For each note with violations:
   - Add each field named in VAULT.md `required`, deriving values sensibly: a
     string field from the filename or first H1, a date field from file mtime, an
     enum field set to a valid VAULT.md value. Do not add any key the vault schema
     does not define.
   - Fix type mismatches (string where list expected, etc.)
   - Preserve all existing valid fields — never strip unknown properties
   - Fix YAML syntax errors (unclosed quotes, bad indentation)
3. For notes with no frontmatter at all:
   - Insert a complete frontmatter block at the top
   - Use the first H1 as the `title` if present

### Enrichment — populating empty properties

Standardization fixes required-field violations; enrichment fills schema-defined
properties that are present-but-empty or absent-but-optional. Run it on every note the
scan flags as sparse or under-tagged, not only on notes with violations.

1. For each schema-defined optional property that is empty or absent, derive a value
   only from what the note already supports:
   - `topic` / `type`: from the note's dominant subject or the folder it sits in
   - `aliases`: from an obvious alternate title the body uses (acronym, full form)
   - `source`: from a source URL already present in the body
   - `updated` / modification-date field: from the last real edit (file mtime)
   - `tags`: see Tag Cleanup and Assignment below
2. Never invent a value to fill a slot. If the note does not support a confident value,
   leave the property empty and move on — a wrong property is worse than an empty one.
3. Add only keys the schema defines. Enrichment never introduces new frontmatter keys,
   and never overwrites a non-empty property.
4. Record bulk enrichment in the session summary.

### YAML Gotchas

- Strings containing colons need quoting: `title: "Note: A Subtitle"`
- Dates should be ISO 8601: `2026-08-06`
- Lists can be flow `[a, b]` or block (one per line) — match vault convention
- Boolean-like strings need quoting: `"yes"`, `"no"`, `"true"`
- Never use tabs in YAML — spaces only

---

## Tag Cleanup and Assignment

Two jobs share the taxonomy: cleanup fixes wrong tags, assignment adds missing ones.
A note with an empty or absent `tags` property is under-tagged, not merely untidy —
tags are how the vault's notes find each other, so an untagged note is effectively
invisible to tag-driven navigation and MOCs.

### Cleanup procedure

1. Build tag frequency map across the vault
2. For each tag not in VAULT.md taxonomy:
   - If fuzzy match to a valid tag (edit distance ≤ 2): apply the correction
   - If no match and the vault genuinely uses the tag: add it to the VAULT.md
     taxonomy and record the edit in the session summary
   - If no match and the tag is noise (a typo with no target, a one-off): remove it
3. Apply corrections in bulk and record them in the change table
4. Update tag index/MOC if one exists

### Assignment procedure

Run this on every note the scan flags as under-tagged (empty/absent `tags`, or fewer
tags than the VAULT.md `tag_floor`, default 1).

1. Read the note's title, headings, and body to determine its dominant subjects.
2. Match those subjects to existing taxonomy tags. Prefer the most specific tag the
   content justifies (`tech/ai/agents` over `tech/ai` over `tech`), and prefer tags
   already used on sibling notes in the same folder.
3. Assign enough tags to reach the `tag_floor`, but only tags the content genuinely
   supports — do not pad to the floor with weak matches. A single accurate tag beats
   three vague ones.
4. If the note's subject has no home in the taxonomy, do not invent an off-taxonomy
   tag: add the new entry to the VAULT.md taxonomy (a normal write), tag the note with
   it, and record the taxonomy edit in the session summary.
5. Never remove or replace an existing valid tag during assignment — assignment only
   adds. Cleanup handles corrections.

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
200 words of body overlap before you merge, and check the merge against
VAULT.md structural invariants (for example, every folder keeps its hub).

1. Compare both notes side by side
2. Identify the "primary" note (more inbound links, richer content, better name)
3. Draft a merged version that:
   - Keeps the primary's frontmatter as base, merges unique tags/aliases
   - Combines body content with clear section attribution where origins differ
   - Preserves all source URLs from both notes
   - Takes the earlier `created` date
4. Verify that the merged draft preserves all unique content and sources
5. Apply the merge:
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
     source folder or the date, for example `<archive>/Source-Folder--00-Index.md`),
     and check for an existing file before you move it
   - Update all inbound links that pointed to the duplicate

---

## Link Maintenance

### Broken Link Repair

For each broken link:
1. Search for notes with similar names (fuzzy match)
2. Search for notes containing the broken link text in their aliases
3. If a clear match exists (similarity > 0.85), apply the fix
4. If ambiguous, leave the link unchanged and list the candidates under Deferred Items
5. If no match: the link may reference a note that should exist — flag for
   Curator mode gap analysis

### Orphan Integration

For orphan notes that aren't daily notes or templates:
1. Read the orphan's content and tags
2. Find related notes via tag overlap and content similarity
3. Add wikilinks from related notes to the orphan at the relevant mention points
4. Add the orphan to relevant MOCs

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
   filename). Demote extra H1s to H2 and record the note in the change table.
3. **Bold normalization**: Keep a bold inline label ending in a colon inside a list
   item (for example `- **Note:** ...`). Convert a bold-only line that sits directly
   above a paragraph into a heading at the `heading_start` level. Leave inline
   emphasis inside prose unchanged.
4. **Whitespace**: Collapse blank-line runs to the VAULT.md
   `blank_lines_between_sections` value
   (default 1)
5. **Lists**: Normalize to configured style (dash/asterisk/plus)
6. **Code blocks**: Add language tags to bare fenced blocks where detectable
7. **Callouts**: Normalize to Obsidian callout syntax `> [!type]`
8. **Trailing whitespace**: Strip from all lines
9. **Final newline**: Ensure file ends with exactly one newline

### Conversion-artifact cleanup

Notes converted from PDF, HTML, or DOCX often carry scrape cruft. This step rewrites
body text. Take the required snapshot, remove or repair clear artifacts, and verify the
diff:

- Navigation and chrome: cookie banners, nav breadcrumbs, "skip to content",
  share/print widgets, video-player labels, footer boilerplate
- Broken structure: split list numbers (a `1.` alone on the line above the item text),
  drop-cap artifacts (a lone capital letter as a false heading), and heading text
  merged into the previous paragraph
- Garbled tables: word-art or decorative graphics the converter turned into tables —
  delete them, or rebuild the table if it holds real data
- Dead link fragments: `[back to text](#anchorNNNN)` return links and similar

Do not delete content you cannot classify — leave it in place and record it under
Deferred Items.

### What NOT to Touch

- Do not reflow paragraphs (people have intentional line breaks)
- Do not change heading text (only structure)
- Do not modify content inside code blocks
- Do not alter content inside `> [!quote]` callouts (they may be exact quotes)
- Do not modify embedded content `![[embed]]`

---

## Folder Organization

### Root folder

Keep only files in VAULT.md `root_allowed_files` at the vault root. The defaults are
`VAULT.md` and `README.md`. Do not create an ordinary note at the vault root.

Run `scripts/root-note-organize.sh <vault>` to get the move plan. The script uses the
first destination that these rules supply:

1. Use a matching VAULT.md `placement_rules` entry.
2. If no rule matches, use VAULT.md `inbox_folder`.
3. If the inbox key is absent, use `00-inbox/` only when that folder exists.
4. If no destination exists, defer the note.

Do not use the note title to make a folder. Do not create a folder during the health
scan. Defer the note if its type and status give different destinations.

Run `scripts/root-note-organize.sh <vault>` to inspect source, destination, and reason.
Then run `scripts/root-note-organize.sh --apply <vault>` in the same session. Root-note
moves are part of normal autonomous maintenance.

Before each move, make sure that the destination does not exist. After each move,
update path-qualified inbound links. Then check all affected links. Never move an
allowed root file or a note with an ambiguous destination.

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

1. Select the destination from VAULT.md and record the reason
2. Move the file
3. Update all inbound links to use the new path (if vault uses full paths)
4. If vault uses shortest-path wikilinks, no link updates needed (Obsidian
   resolves these automatically)
5. Verify no broken links resulted from the move
