---
name: obsidian-vault-keeper
description: >-
  Maintain, organize, and expand Obsidian vaults autonomously. Use this skill
  whenever the user asks to clean up, standardize, audit, reorganize, consolidate,
  rename, format, or health-check their Obsidian vault — or when they want to find
  knowledge gaps, research topics, and expand their knowledge base. Also trigger
  when the user mentions vault maintenance, note hygiene, orphan notes, broken links,
  tag cleanup, frontmatter standardization, MOC generation, or knowledge base expansion.
  Also use for scheduled or unattended curation runs — a cron prompt, a recurring
  maintenance job, or a bare "run the skill" with nobody waiting to reply.
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

If `VAULT.md` does not exist, generate one by scanning the vault's current structure:
in an interactive session, present the draft for approval before writing; in an
unattended run, write it directly with conservative detected defaults, mark it with the
`> [!ai-generated]` callout, flag it for operator review, and continue the session.
Read `references/vault-config-spec.md` for the full config schema and a starter
template.

**VAULT.md is authoritative for configuration.** Where a value in VAULT.md — schema,
formatting rules, naming, tag taxonomy, thresholds (for example `approval_required_above`),
`git_aware`, template locations, archive paths — differs from a default, table, or
template in this skill or its reference files, the VAULT.md value wins. The skill's own
defaults and templates apply only to keys and behaviors that VAULT.md does not define.
This precedence covers configuration only; it does not relax the Safety Rules below.

## Safety Rules (non-negotiable)

1. **Never delete notes.** Move candidates to the archive folder defined in VAULT.md.
2. **Preview before bulk changes.** For any operation touching more files than
   VAULT.md `approval_required_above` (default 3), show the planned changes as a
   table (file, action, reason) and wait for approval.
3. **Preserve existing wikilinks.** When renaming, update all inbound links.
4. **Preserve frontmatter.** Never strip valid YAML properties. Add missing ones;
   fix malformed ones.
5. **Distinguish evidence from interpretation.** Mark agent-written content with a
   callout: a whole agent-drafted note gets `> [!ai-generated]`; agent-added facts
   inside an existing note get `> [!updated]` with inline citations. The callout is
   the canonical marking. Add provenance frontmatter keys (for example `ai_generated`,
   `source`, `confidence`) only when the VAULT.md schema and `ai_content_marking`
   setting call for them.
6. **Source everything.** New claims must include a source URL or be labeled
   `[unsourced — verify]`.
7. **End every session with a change summary.** List files changed, actions taken,
   and a review command: give `git diff` when VAULT.md `git_aware` is true (the
   default); on a no-git vault, give the snapshot path and a diff against it.
8. **Respect exclusion zones.** Never read or modify paths listed under
   `exclusions` in VAULT.md.
9. **Snapshot before writing on a no-git vault.** If VAULT.md sets `git_aware: false`,
   create a recovery snapshot before the first write, using the recovery path in
   VAULT.md Archive Policy (`external_archive`). If the vault declares neither git nor
   a snapshot path: in an interactive session, ask the operator to choose a recovery
   mechanism; in an unattended run, do not stop — write the snapshot to
   `~/.vault-keeper/snapshots/<vault-name>-<date>/`, report the path in the session
   summary, and continue. Snapshot creation is read-only on the vault and always safe.

## Autonomy

The skill runs under one of two authorization postures. Read which is in force from
the operator's most recent instruction; when in doubt, default to Gated.

- **Gated (default).** Present findings, then wait at each approval gate in the Safety
  Rules before writing.
- **Standing autonomy.** When the operator hands over open-ended control — "whatever
  you want", "you decide", "go ahead and expand it", "this is your KB", "run
  autonomously", or similar — proceed end-to-end through the active mode's phases
  without pausing for per-item approval. Prefer action over asking: pick the sensible
  default, do the work, and report it. Ask only when a choice is consequential AND
  hard to reverse.

Standing autonomy covers ONLY additive, reversible work: drafting new notes, adding
links, gap analysis, freshness updates, MOCs. It never extends to deletes, renames that
touch inbound links, merges, or bulk reformatting — those return to a Gated approval no
matter how broad the grant, because they are hard to undo.

Autonomy changes WHO approves, not WHAT is safe. Every Safety Rule still holds: snapshot
before the first write on a no-git vault, source every claim, mark agent content with the
callout, respect exclusion zones. Under autonomy, replace the per-item preview gate with
one batched change summary at session close. Fan work out to subagents when a batch is
large; keep cross-file edits (hubs, inbound links) central to avoid write races.

An unattended run has no operator to answer a gate. When the skill is invoked headlessly —
a scheduled job, a cron prompt, a channel command with nobody waiting to reply — treat the
invocation itself as standing autonomy over the additive scope above. Do the safe work.
Record anything that would need a Gated approval (deletes, renames, merges, bulk
reformatting) under Deferred Items in the session summary instead of waiting for a reply
that cannot come. Waiting is not the safe choice in an unattended run; it converts the
whole session into a no-op.

**Gate vocabulary.** Where this skill or its reference files say "propose", "offer",
"show a preview", "present for approval", or "wait for approval", that marks a Gated
interaction point — not an unconditional instruction to pause. Under standing autonomy
(including every unattended run), resolve each one the same way: if the action is in
the additive scope, do it and record it in the change summary; if it is in the
restricted scope, skip it and record it under Deferred Items. Never let a gate written
for an interactive session stall an unattended run.

## Reporting Style

A session produces two artifacts for two different readers. Do not mix them.

**The chat report is a story about knowledge, not a log about files.** Tell the
operator what the vault learned: the gap that existed, what the research found, what
the vault can now answer that it could not before, and why that matters to the
operator's work (anchor "why it matters" in the VAULT.md Purpose and expansion
domains). Write it as three to six sentences of plain, calm prose — short sentences,
active voice, no hype, no invented color. Name new or changed notes inline where they
appear in the story. Close with one line: the most valuable thing the next session
should go learn.

Mechanics do not belong in the chat report. Counts, link repairs, snapshot paths,
frontmatter fixes, verification results, and health deltas go in the session summary
file (see Session Close); in chat, give that file's path in a single line at the end.
Mention a mechanical detail in chat only when the operator must act on it. The
skill's own tooling problems and config conflicts are Deferred Items footnotes, never
the story — a report whose news is about the janitor's tools instead of the vault's
knowledge is a failed report.

The coffee test: would a colleague say this to the operator's face? "I added
frontmatter to 14 files and verified 915 links" fails. "Your notes kept circling a
topic without ever explaining it — there is now a sourced note that answers it, and
here is when you will need it" passes. A report that reads like a build log is a
failed report even when the work was good.

Do not narrate process. No per-subagent play-by-play, no tool-by-tool commentary, no
restating these instructions, no progress ticks while work runs in the background.
Give the story, the one decision you need (if any), the summary path, and stop.

## A Full Run

An open-ended invocation — "run the skill", "curate the vault", "do a maintenance pass",
a scheduled prompt — means one complete session of BOTH modes: the Steward sweep
(Phases 1–5), then the Curator loop (Phases 1–3). The trigger phrases under each mode
select that mode alone only when the operator names that specific job.

The phase order describes a full sweep, not a fixed opening ritual. In a scheduled or
continuation session (see Session Continuity), do not start at Phase 1: read the
next-run queue, reuse the last health scan as the baseline, and go straight to the
highest-value target — often Curator work. Re-run the full health scan only when no
recent baseline exists (none from roughly the last day), the queue is empty, or the
vault changed outside the skill. The scan is a diagnostic to refresh periodically,
not a toll to pay before every improvement.

A scan is a phase, not a session. Do not stop after the health scan: its report is input
to the phases that follow, not the deliverable. Do not report a session complete unless
at least one of these happened:

- a safe repair was applied,
- a note was created or substantively updated and linked into its hub,
- a concrete blocker was found and is reported plainly.

"The vault needed nothing" is almost never true — Curator Phase 1 step 6 always yields
adjacent territory worth growing. If a session truly changed nothing, report what was
attempted and why nothing was safe to do. A scan-only pass presented as a completed
session is a failed run.

A blocked target does not complete a session. When the current target cannot be done
safely — bad tooling, ambiguous data, a config conflict — record the blocker under
Deferred Items and take the NEXT target. Hygiene blockers never block expansion: the
Curator loop stays open as long as the vault has a fillable gap. A session that ends
with no knowledge improvement must show why expansion specifically was impossible,
not why one hygiene task was.

## Session Continuity

This skill often runs on a schedule. Each run must extend the last one, not repeat it.

At session start, read the most recent session summary in the VAULT.md
`session_log_folder` (or wherever the operator keeps run state). Honor its Deferred
Items and next-run targets before choosing new work. Do not re-research a gap that a
prior session filled or marked unfillable; search for an existing note before drafting
one.

At session close, write the summary to the log folder with explicit next-run targets:
the top remaining gaps and any deferred repairs. On a tight schedule, one COMPLETED
target from the queue is a valid session — rotate focus across hygiene categories and
domains rather than forcing a full sweep into every tick. An attempted target is not a
completed one: if the queued target turns out to be blocked, defer it and take the next
target in the same session; an expansion gap is always a valid next target. Hygiene
work is idempotent; a clean re-scan is normal. Expansion work is not — never
manufacture a near-duplicate note to satisfy the completion gate.

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

Run `scripts/vault-health-scan.sh <vault>` first for baseline metrics (total notes,
per-folder counts, empty and stub notes, notes missing a frontmatter fence, unique
link-target and tag counts, VAULT.md and git presence). These are baseline signals,
not the full diagnostics: the script does not detect orphans, broken links, duplicates,
naming violations, tag anomalies, or misplaced notes. Compute those categories per
`references/maintenance-ops.md`, which builds the vault index, an inbound-link map,
and target-existence checks.

Present the report as a summary table with counts per category. In a Gated
interactive session, offer to drill into any category; in a full run, carry the
findings straight into Phase 2.

### Phase 2 — Standardize

For each issue class, apply the fix defined in VAULT.md or use these defaults:

| Issue | Default action |
|-------|---------------|
| Missing frontmatter | Add the fields named in VAULT.md `required`, values derived sensibly; set enum fields to a valid VAULT.md value. Do not add keys the vault schema omits. |
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

Do not treat a folder-note and its `00-Index` (or other hub) as duplicates, and never
archive a hub note. Hubs are reached by folder navigation and show zero inbound links,
so do not pick the primary by raw inbound count for hub notes. Before any merge, check
the candidate against VAULT.md structural invariants (for example, every folder keeps
its hub). A clean, already-deduped vault may have zero merge candidates — that is a
valid result, not a reason to force a merge.

### Phase 4 — Organize

- Generate or update **Maps of Content (MOCs)** for each major topic area
- Suggest folder moves for misplaced notes (per VAULT.md structure)
- Propose new links between related but unconnected notes
- Update the tag index if VAULT.md defines one

### Phase 5 — Format

Apply consistent formatting per VAULT.md conventions (or defaults):

- Heading hierarchy (H1 = title only, H2+ for sections)
- At most one H1 per note: keep the first (or filename-matching) H1, demote the rest,
  and flag the note for review
- Bold normalization: keep a bold inline label that ends in a colon inside a list item;
  convert a bold-only line that sits directly above a paragraph into a heading at the
  VAULT.md `heading_start` level; leave inline emphasis in prose alone
- Callout style for warnings, tips, references
- Code block language tags
- Consistent list style (bullets vs numbers)
- Normalize whitespace: collapse blank-line runs to the VAULT.md `blank_lines` value
  (default 1)

Notes converted from PDF, HTML, or DOCX often carry scrape cruft (cookie banners, nav
breadcrumbs, video-player labels, split list numbers, drop-cap artifacts, garbled
tables). That cleanup rewrites body text, so run it as a gated step behind the preview
and approval gate — see `references/maintenance-ops.md` "Conversion-artifact cleanup".

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
   mostly stubs (<100 words). First subtract VAULT.md `excluded_paths`,
   `read_only_paths`, and `accepted_orphan_zones`, and skip structural files (folder
   `00-Index` hubs, numbered report sections, auto-generated notes) so they do not
   inflate the thin-area count
3. **Find missing connections**: Topics referenced in notes but lacking their
   own dedicated note
4. **Detect staleness**: Notes whose modification-date field — the one declared in
   the VAULT.md frontmatter schema (for example `updated`, `date_modified`, `modified`;
   fall back to filesystem mtime if none) — is older than the VAULT.md threshold
   (default: 6 months) on fast-moving topics
5. **Surface implicit gaps**: Topics that adjacent notes imply but no note covers
6. **Explore adjacent territory**: Do not stop at the declared `expansion_domains`.
   Propose genuinely new topics that neighbor the vault's interests — a subfield the
   domains only touch, a thinker or tool the notes keep circling, an emerging area a
   deep domain will soon need. Treat the vault as a living KB to grow, not a fixed
   checklist to complete. Mark these as `new-territory` in the gap report so they are
   easy to tell from in-domain fills. When a new-territory cluster proves substantial,
   offer to register it as a new domain in VAULT.md `expansion_domains` (a VAULT.md edit
   is a normal write, not a restricted structural change).

Present findings as a prioritized gap report: topic, gap type (in-domain / connection /
implicit / `new-territory`), priority (how central to the vault's interests), and
suggested action. Under **standing autonomy** (see Autonomy), do not stop at the report —
select the strongest gaps yourself and continue into Phase 2.

### Phase 2 — Research & Draft

For each gap approved by the operator — or, under standing autonomy, each gap the skill
selects:

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
3. Update the vault's modification-date field (per VAULT.md schema) in place; never introduce a field the schema does not define
4. Add new sources alongside existing ones (never remove old sources)

## Generating a VAULT.md

If the vault lacks a `VAULT.md`, scan the vault and generate one:

1. Inventory the folder structure and infer purpose of each folder
2. Sample 20-30 notes to detect naming conventions, frontmatter patterns,
   tag usage, and link style
3. Identify the most common templates
4. Draft a VAULT.md following the schema in `references/vault-config-spec.md`
5. In an interactive session, present it for review and approval before writing.
   In an unattended run, write it now: keep detected values, choose conservative
   defaults for the rest (`approval_required_above: 3`, detected exclusions kept),
   add the `> [!ai-generated]` callout, and list it first in the session summary
   so the operator reviews it.

This makes the skill immediately usable on any existing vault — the agent
bootstraps its own configuration from what's already there.

## Session Close

Before writing the summary, verify the session's own work: every link you added
resolves, every new note's frontmatter parses and matches the VAULT.md schema, every
new factual claim carries a source, every new note is linked from its hub, and no
excluded path changed. Fix what fails verification before reporting it.

This template is the session summary FILE — the full mechanical record, written to
the log folder. It is not the chat report; the chat gets the narrative described in
Reporting Style, with a one-line pointer to this file.

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
When VAULT.md `git_aware` is true (the default): `git diff --stat` or `git diff`.
On a no-git vault: extract the snapshot, then `diff -r <extracted-snapshot> <vault>`; the change table above is the authoritative record.

### Next-Run Targets
- Ranked queue for the next session (see Session Continuity)
```

When VAULT.md defines `session_log_folder`, also write this summary there — the next
session reads it before choosing work. If `session_log_folder` is unset, or resolves
inside an excluded or read-only path, that is not a policy question: fall back to
`external_archive` (or the snapshot location), note the fallback once in the summary,
and continue.

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
