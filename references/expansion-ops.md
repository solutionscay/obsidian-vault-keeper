# Expansion Operations Reference

Detailed procedures for Curator mode — finding knowledge gaps, researching
topics, and autonomously expanding the vault.

Vault Keeper operates autonomously by default. Select gaps, research, draft, link, and
update notes without waiting for approval. There is no preview mode. Defer only
ambiguous or unsafe actions.

## Table of Contents

1. [Gap Analysis Procedure](#gap-analysis-procedure)
2. [Research Methodology](#research-methodology)
3. [Note Drafting Standards](#note-drafting-standards)
4. [Source Quality Rules](#source-quality-rules)
5. [Freshness Sweep](#freshness-sweep)
6. [Autonomous Expansion Workflow](#autonomous-expansion-workflow)

---

## Gap Analysis Procedure

### Step 1 — Build the coverage map

Read `domains` in the VAULT.md `Expansion Domains` section. Exclude
`excluded_paths` and `read_only_paths` from every count,
and skip structural files (folder `00-Index` hubs, numbered report sections, and
auto-generated notes) so they do not read as thin coverage. Then:

1. **Inventory by folder**: What topics live in each folder?
2. **Inventory by tag**: What tag clusters exist and how deep do they go?
3. **Inventory by MOC**: What do existing MOCs cover?
4. **Inventory by link graph**: What are the most-linked-to topics? What topics
   have outbound links to nonexistent notes (implicit gap)?

### Step 2 — Score coverage depth

For each domain in `Expansion Domains.domains`, score coverage:

| Score | Meaning | Criteria |
|-------|---------|----------|
| 5 | Deep | 10+ notes, MOC exists, subtopics covered, recent updates |
| 4 | Good | 5-10 notes, most subtopics touched |
| 3 | Moderate | 3-5 notes, some subtopics missing |
| 2 | Thin | 1-2 notes, mostly stubs |
| 1 | Gap | 0 notes, but referenced or implied by adjacent content |
| 0 | Blind spot | Not covered and not referenced — only visible from VAULT.md domains |

### Step 3 — Identify specific gaps

For every domain — not only low-scoring ones. A domain can score 4-5 in aggregate
yet still miss specific subtopics, so run the subtopic comparison in all cases.

**Missing subtopics**: Compare VAULT.md subtopic list against existing notes.
Any listed subtopic without a dedicated note (or meaningful coverage in a
broader note) is a gap.

**Over-coverage**: Flag any domain whose note volume materially exceeds its declared
`depth` (for example a `surface` domain with 30+ notes) as a pruning or
re-classification candidate.

**Dangling references**: Wikilinks like `[[topic-that-doesnt-exist]]` are
explicit gaps — someone thought the note should exist.

**Implied gaps**: Look for patterns like:
- A note discusses "alternatives to X" but X itself has no note
- A comparison note references a concept that's never defined
- A project note depends on a technology that has no reference page
- Meeting notes reference decisions that were never formally recorded

To run this without reading every note, grep the vault for cue phrases — "alternatives
to", "compared to", "as opposed to", "depends on", "successor to", "instead of" —
extract the referenced term from each hit, then check whether a dedicated note exists
for that term. Report the terms that have no note.

**Stale coverage**: Notes on fast-moving topics (per VAULT.md `freshness`
settings) that haven't been updated within the freshness window.

### Step 4 — Prioritize

Rank gaps by:

1. **Centrality**: How many existing notes link to or reference this topic? Compute it
   by extracting every `[[target]]`, resolving each to a note, and counting inbound
   links per note; the topic's centrality is the inbound count of its nearest note plus
   its raw mention frequency across the vault
2. **Domain priority**: Is this a `deep` or `surface` domain in VAULT.md?
3. **Actionability**: Can this gap be filled with web research, or does it
   require the user's personal knowledge?
4. **Freshness urgency**: Is existing coverage actively misleading due to age?

Record the gap report with priority rankings and actions, then continue into selection.

---

## Research Methodology

When filling a gap with web research:

### Source Selection

1. **Search broadly first**: 3-5 different search queries per topic to get
   diverse perspectives
2. **Prefer primary sources**: official documentation, peer-reviewed papers,
   company announcements, government data
3. **Use authoritative secondary sources**: established publications, recognized
   experts, reputable news organizations
4. **Avoid**: forums (unless citing community consensus), SEO content farms,
   undated content, sources with no clear authorship

### Research Depth by Domain Setting

| VAULT.md depth | Research approach |
|----------------|-------------------|
| deep | 8-15 searches, multiple sources per claim, include counterpoints |
| moderate | 4-8 searches, 2-3 sources for key claims |
| surface | 2-4 searches, capture the essentials |

### Information Extraction

For each source:

1. Extract factual claims (not opinions unless the opinion itself is notable)
2. Note the publication date
3. Note the author/organization
4. Capture the exact URL
5. Assess the claim's confidence level:
   - **high**: multiple authoritative sources agree
   - **medium**: single authoritative source, or multiple lesser sources agree
   - **low**: single source, or sources conflict
   - **unverified**: plausible but not independently confirmed

---

## Note Drafting Standards

### Structure

Every agent-drafted note follows this structure. Build the frontmatter from VAULT.md's
required and optional keys, using the vault's exact key names, value types, and status
enum. Add provenance keys (for example `source`, `confidence`, `ai_generated`) only as
the VAULT.md `provenance` and `ai_content_marking` settings direct. The YAML block below
is an illustrative example for a vault with no frontmatter schema — do not copy its keys
verbatim. Keep the body sections that follow as the general standard.

```markdown
---
title: "[Topic Title]"
created: [ISO date]
date_modified: [ISO date]
tags: [per taxonomy]
status: draft
type: [note type]
source: [primary source URL]
confidence: [high/medium/low]
ai_generated: true
---

> [!ai-generated]
> This note was drafted by the Vault Keeper agent on [date].
> Sources are cited inline. Review for accuracy before promoting to `active`.

# [Topic Title]

[Opening paragraph: what this topic is and why it matters to this vault]

## Key Concepts

[Core information organized by subtopic]

## Current State (as of [date])

[What's true right now — important for fast-moving topics]

## Relevance to This Vault

[How this topic connects to existing notes — with wikilinks]

## Sources

- [Source 1 title](URL) — accessed [date]
- [Source 2 title](URL) — accessed [date]

## Related Notes

- [[related-note-1]]
- [[related-note-2]]
```

### Writing Style

- Write in the vault owner's apparent style (detect from existing notes)
- If no clear style detected, default to concise, informational prose
- Use the vault's heading conventions
- Match the vault's callout style
- Keep notes atomic — one concept per note (Zettelkasten principle)
- For broad topics, create a MOC + multiple atomic notes rather than one
  massive note

### Draft state and AI marking

A fresh agent draft is unverified. If the VAULT.md status enum has a draft or
quarantine value (for example `draft`), use it. If it does not, do not file the draft
as a trusted value such as `reference` or `authoritative`. Add a `draft` value to the
VAULT.md status enum (a normal write), use it on the note, and record the schema edit
in the session summary. Do not stall the session over a schema decision.

The `> [!ai-generated]` callout is the canonical AI marking for a whole drafted note.
For a factual addition to an existing note, use `> [!updated]` with inline citations.
Add provenance frontmatter keys only when the VAULT.md schema includes them and the
`ai_content_marking` setting is `frontmatter`.

### Link Integration

After drafting:

1. Search the vault for notes that discuss the new note's topic
2. Add `[[new-note]]` links in those existing notes at the
   relevant mention points
3. Add backlinks from the new note to all related existing notes
4. Add the new note to relevant MOCs
5. If no MOC covers this topic and 3+ related notes exist, create one

---

## Source Quality Rules

### Provenance Requirements

Based on VAULT.md `provenance` setting:

**Strict (default):**
- Every factual claim must have a source URL
- Confidence level required for each claim
- No unsourced assertions except vault-internal observations
- Source publication date required

**Relaxed:**
- Key claims need sources
- General knowledge statements can be unsourced
- Confidence level optional

### Citation Format

Inline citations in the note body:

```markdown
The claim, stated in prose ([Author, YEAR](https://example.org/source)), with the
counterpoint noted where sources disagree ([Other Author, YEAR](https://example.org/counterpoint)).
```

Full source list in the `## Sources` section at the bottom.

### Handling Conflicting Sources

When sources disagree:

1. Present both perspectives
2. Note which source is more recent, more authoritative, or more widely cited
3. Set confidence to `low` for the contested claim
4. Do NOT pick a winner — let the vault owner decide

---

## Freshness Sweep

### Procedure

1. Read `domains` in VAULT.md `Expansion Domains` for each freshness threshold
2. Identify notes in each domain whose VAULT.md-declared modification-date field
   (fall back to filesystem mtime if the schema names none) is older than the
   threshold. If most notes in a domain share one recent value for that field
   (a sign of bulk import or auto-generation), treat the field as unreliable:
   fall back to the underlying source date, or flag the domain
   "freshness-unverifiable — needs manual review" rather than reporting zero stale
   notes.
3. For each stale note:
   a. Search the web for current information on the note's topic
   b. Compare findings against the note's existing content
   c. Categorize the update need:
      - **Outdated**: facts have changed, needs correction
      - **Incomplete**: new developments not covered
      - **Still accurate**: bump the modification-date field, no content change needed
4. For notes needing updates:
   a. Draft the specific additions/corrections as a diff
   b. Add new sources alongside existing ones (never remove old sources —
      they document the historical record)
   c. Update the modification-date field (per VAULT.md schema)
   d. If the update is substantial, add a `> [!updated]` callout noting what changed

### What Counts as Stale

| Domain freshness | Stale threshold |
|-----------------|-----------------|
| 1_month | Modification-date field (per VAULT.md) >30 days ago |
| 3_months | Last modified >90 days ago |
| 6_months | Last modified >180 days ago |
| 12_months | Last modified >365 days ago |
| evergreen | Never stale (but check if referenced facts have changed) |

---

## Autonomous Expansion Workflow

When the user says "expand my vault" or similar, run this full workflow:

### Step 1 — Gap Analysis
Run the full gap analysis procedure above. Record the gap report.

### Step 2 — Gap Selection
Select the gaps yourself from the top 5-10 recommendations. Apply the Curator rotation
rule in SKILL.md before the normal priority order. The session note cap still applies.

After three consecutive runs in one domain, select a different domain. Prefer an
under-covered domain. Select a `new-territory` gap if no declared domain qualifies.
Do not select an exhausted domain until the operator renews it. A queued target does
not renew a domain.

Record the domain, the prior count, and the decision in the session summary. Do not
wait for a selection that cannot come.

### Step 3 — Research Batch
For each selected gap:
1. Search the web (depth per domain setting)
2. Draft the note per standards above
3. Collect all drafted notes

### Step 4 — Review Batch
Review all drafted notes for placement, links, content, valid frontmatter, sourced
claims, and correct folders. Integrate what passes. Move uncertain drafts to the
VAULT.md `review_subfolder` instead of holding the session open.

### Step 5 — Integration
For each note that passed review:
1. Write the note to the vault
2. Add links from existing notes
3. Update MOCs
4. Update tag index if applicable

### Step 6 — Session Summary
Standard session close with full change log.

### Guardrails for Autonomous Operation

- Never create more than VAULT.md `max_new_notes_per_session` (default 10) notes in
  one session unless the operator explicitly requests a broader batch. Queue the rest.
- Keep every existing-note change reviewable through git or the pre-write snapshot,
  and list the file in the change summary.
- If a gap requires personal/proprietary knowledge (detected by: the topic
  is about the user's own projects, decisions, or experiences), flag it as
  "requires human input" rather than attempting to fill it
- If web research returns no quality sources, report the gap as "unfillable
  via research" rather than drafting a low-confidence note
