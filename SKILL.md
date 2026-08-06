---
name: obsidian-vault-keeper
description: >-
  Maintain, organize, and expand Obsidian vaults autonomously. Use this skill
  whenever the user asks to clean up, standardize, audit, reorganize, consolidate,
  rename, format, or health-check their Obsidian vault — or when they want to find
  knowledge gaps, research topics, and expand their knowledge base. Also trigger
  when the user mentions vault maintenance, note hygiene, orphan notes, broken links,
  tag cleanup, frontmatter standardization, MOC generation, or knowledge base expansion.
  Works across any vault by reading a VAULT.md config at the vault root.
---

# Obsidian Vault Keeper

An agent skill for maintaining and expanding Obsidian knowledge bases. Operates in
two modes — **Steward** (maintenance) and **Curator** (expansion) — and adapts to
any vault by reading its configuration from a `VAULT.md` file at the vault root.

## First: Read the Vault Contract

Before ANY operation, read `VAULT.md` at the vault root. This file defines:

- Folder structure and what each folder means
- Naming conventions (kebab-case, date prefixes, etc.)
- Frontmatter schema (required/optional properties)
- Tag taxonomy and hierarchy
- Template locations and when to use them
- Exclusion zones (folders/files the agent must not touch)
- Expansion domains (topics the vault covers, where to grow)
- Link conventions (wikilinks vs markdown links, alias rules)
- Archive policy (where retired notes go)

If `VAULT.md` does not exist, offer to generate one by scanning the vault's current
structure. Read `references/vault-config-spec.md` for the full config schema and
a starter template.

## Safety Rules (non-negotiable)

1. **Never delete notes.** Move candidates to the archive folder defined in VAULT.md.
2. **Preview before bulk changes.** For any operation touching >3 files, show the
   planned changes as a table (file, action, reason) and wait for approval.
3. **Preserve existing wikilinks.** When renaming, update all inbound links.
4. **Preserve frontmatter.** Never strip valid YAML properties. Add missing ones;
   fix malformed ones.
5. **Distinguish evidence from interpretation.** When expanding notes, mark
   agent-generated content with a `> [!ai-generated]` callout block.
6. **Source everything.** New claims must include a source URL or be labeled
   `[unsourced — verify]`.
7. **End every session with a change summary.** List files changed, actions taken,
   and the git diff command to review.
8. **Respect exclusion zones.** Never read or modify paths listed under
   `exclusions` in VAULT.md.

## Mode 1: Steward (Maintenance)

Trigger phrases: "clean up my vault", "standardize my notes", "fix my vault",
"vault health check", "organize my notes", "audit my vault", "rename and consolidate"

Run the maintenance sweep in this order. Each phase can be invoked independently.

### Phase 1 — Health Scan

Produce a diagnostic report covering:

- **Orphan notes**: files with zero inbound links (excluding daily notes, templates)
- **Broken links**: wikilinks pointing to nonexistent files
- **Duplicate candidates**: files with >70% title similarity or overlapping content
- **Frontmatter violations**: notes missing required properties per VAULT.md schema
- **Naming violations**: files not matching the convention in VAULT.md
- **Tag anomalies**: typo variants, unused tags, tags outside the taxonomy
- **Empty notes**: files with <20 characters of body content
- **Misplaced notes**: files in folders that don't match their type/status

Present the report as a summary table with counts per category, then offer to
drill into any category.

### Phase 2 — Standardize

For each issue class, apply the fix defined in VAULT.md or use these defaults:

| Issue | Default action |
|-------|---------------|
| Missing frontmatter | Add required fields with sensible defaults, mark `status: draft` |
| Naming violations | Propose rename following convention, update all inbound links |
| Tag typos | Replace with closest valid tag from taxonomy |
| Malformed YAML | Fix syntax, preserve all existing key-value pairs |
| Empty notes | Flag for review, do not archive automatically |

Read `references/maintenance-ops.md` for detailed procedures on each operation.

### Phase 3 — Consolidate

Identify and merge duplicates:

1. Show the two (or more) candidate notes side by side
2. Propose a merged version that preserves all unique content
3. Keep the note with more inbound links as the primary
4. Redirect the other(s) to an alias in the primary's frontmatter
5. Move the duplicate(s) to archive with a forwarding note

### Phase 4 — Organize

- Generate or update **Maps of Content (MOCs)** for each major topic area
- Suggest folder moves for misplaced notes (per VAULT.md structure)
- Propose new links between related but unconnected notes
- Update the tag index if VAULT.md defines one

### Phase 5 — Format

Apply consistent formatting per VAULT.md conventions (or defaults):

- Heading hierarchy (H1 = title only, H2+ for sections)
- Callout style for warnings, tips, references
- Code block language tags
- Consistent list style (bullets vs numbers)
- Normalize whitespace (no triple+ blank lines)

## Mode 2: Curator (Expansion)

Trigger phrases: "find gaps in my vault", "what's missing from my KB",
"research and expand", "grow my knowledge base", "add to my vault",
"what should I know more about"

The Curator analyzes the vault's coverage and autonomously researches + fills gaps.

### Phase 1 — Gap Analysis

Read the `expansion_domains` section of VAULT.md to understand what the vault
*should* cover. Then:

1. **Map existing coverage**: Build a topic inventory from folder structure,
   tags, MOCs, and note titles
2. **Identify thin areas**: Topics with fewer than 3 notes, or notes that are
   mostly stubs (<100 words)
3. **Find missing connections**: Topics referenced in notes but lacking their
   own dedicated note
4. **Detect staleness**: Notes with `date_modified` older than the threshold
   in VAULT.md (default: 6 months) on fast-moving topics
5. **Surface implicit gaps**: Topics that adjacent notes imply but no note covers

Present findings as a prioritized gap report: topic, gap type, priority
(based on how central the topic is to the vault's domains), and suggested action.

### Phase 2 — Research & Draft

For each approved gap:

1. **Search the web** for current, authoritative sources on the topic
2. **Draft a new note** following the vault's templates and conventions:
   - Proper frontmatter per VAULT.md schema
   - Correct folder placement
   - Wikilinks to existing related notes
   - Source URLs for every factual claim
   - `> [!ai-generated]` callout at the top explaining this was agent-drafted
3. **Propose links** from existing notes to the new note
4. **Update relevant MOCs** to include the new note

Read `references/expansion-ops.md` for research methodology, source quality
rules, and note drafting procedures.

### Phase 3 — Freshness Sweep

For notes flagged as stale:

1. Search the web for updated information on the note's topic
2. Propose specific additions or corrections as a diff
3. Update the `date_modified` property
4. Add new sources alongside existing ones (never remove old sources)

## Generating a VAULT.md

If the vault lacks a `VAULT.md`, scan the vault and generate one:

1. Inventory the folder structure and infer purpose of each folder
2. Sample 20-30 notes to detect naming conventions, frontmatter patterns,
   tag usage, and link style
3. Identify the most common templates
4. Draft a VAULT.md following the schema in `references/vault-config-spec.md`
5. Present it to the user for review and approval before writing

This makes the skill immediately usable on any existing vault — the agent
bootstraps its own configuration from what's already there.

## Session Close

Every Vault Keeper session ends with:

```markdown
## Vault Keeper Session Summary — [date]

### Changes Made
| File | Action | Reason |
|------|--------|--------|
| ... | ... | ... |

### Deferred Items
- Items that need human review before proceeding

### Vault Health Delta
- Before: [counts]
- After: [counts]

### Review Command
`git diff --stat` or `git diff` for full changes
```

## File Structure

```
obsidian-vault-keeper/
├── SKILL.md                      # This file
├── references/
│   ├── vault-config-spec.md      # VAULT.md schema and starter template
│   ├── maintenance-ops.md        # Detailed maintenance procedures
│   └── expansion-ops.md          # Research and expansion procedures
├── scripts/
│   └── vault-health-scan.sh      # Automated health scan (bash)
└── assets/
    └── vault-md-template.md      # Copy-paste VAULT.md starter
```

Read the reference files when you need the detailed procedure for a specific
operation. The SKILL.md body covers the what and when; the references cover the how.
