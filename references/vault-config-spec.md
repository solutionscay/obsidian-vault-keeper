# VAULT.md Configuration Specification

The `VAULT.md` file lives at the vault root and serves as the operating contract
between the vault owner and any agent skill that interacts with the vault. It is
both human-readable documentation and machine-parseable configuration.

## Why VAULT.md

Every vault is different. Folder names, naming conventions, tag taxonomies,
frontmatter schemas, and organizational philosophies vary widely. Rather than
hardcoding assumptions, the Vault Keeper reads VAULT.md to learn the vault's
rules before touching anything.

The idea: the vault itself carries its own operating manual, so any agent can
adapt to any vault without hardcoded assumptions.

## Schema

VAULT.md uses Markdown with structured sections. Each section is optional —
the skill uses sensible defaults for anything not specified.

### Required Sections

#### `## Purpose`
One paragraph: what this vault is for. Helps the Curator understand scope.

#### `## Structure`
A code block showing the folder tree with one-line descriptions:

```
Second-Brain/
  00-inbox/          # Unsorted captures, clippings, quick thoughts
  10-projects/       # Active projects with defined outcomes
  20-areas/          # Ongoing responsibilities (no end date)
  30-resources/      # Reference material organized by topic
  40-archive/        # Completed or retired material
  90-system/         # Templates, skills, config, indexes
    templates/
    skills/
    indexes/
```

### Recommended Sections

#### `## Naming Conventions`
How files should be named. Examples:

```yaml
style: kebab-case           # kebab-case | snake_case | Title Case | free
date_prefix: false           # true = "2026-08-06-meeting-notes.md"
max_length: 60               # max filename length (chars, excluding .md)
daily_notes: "YYYY-MM-DD"    # daily note date format
people_prefix: "@"           # e.g., "@john-doe.md" or "people/" folder
project_prefix: "PRJ-"       # optional prefix for project notes
```

#### `## Frontmatter Schema`
Define required and optional YAML properties for notes:

```yaml
required:
  - title: string
  - created: date           # ISO 8601
  - tags: list
  - status: enum [draft, active, review, archive]

optional:
  - aliases: list
  - source: url
  - date_modified: date
  - project: string         # link to parent project
  - author: string
  - confidence: enum [high, medium, low, unverified]
  - type: enum [note, moc, daily, meeting, decision, reference, person]
  - topic: string
```

The keeper does more than enforce required properties. During the Steward sweep it
also **enriches** frontmatter: it populates optional properties listed here when a
value is derivable from the note, and it assigns `tags` from the taxonomy below. Only
properties named in this schema are ever added — enrichment never invents a new key,
and never overwrites a property that already holds a value.

#### `## Tag Taxonomy`
The approved tag hierarchy. Tags outside this list are flagged during health scans:

```yaml
# Top-level domains
domains:
  - tech/
  - business/
  - personal/
  - reference/

# Examples of valid tags
valid_tags:
  - tech/ai
  - tech/ai/agents
  - tech/ai/llm
  - tech/web
  - business/strategy
  - business/sales
  - personal/health
  - reference/book
  - reference/article
  - status/active
  - status/stale
  - status/stub
```

#### `## Link Conventions`
```yaml
style: wikilink              # wikilink | markdown
aliases: true                # use aliases in frontmatter for alternate names
shortest_path: true          # [[note]] vs [[folder/note]]
```

#### `## Templates`
Where templates live and when to use each:

```yaml
location: 90-system/templates/
templates:
  - name: note.md
    use_when: "default new note"
  - name: meeting.md
    use_when: "meeting notes, agendas, follow-ups"
  - name: decision.md
    use_when: "recording a decision with context and rationale"
  - name: person.md
    use_when: "creating a page for a person/contact"
  - name: project.md
    use_when: "starting a new project"
  - name: moc.md
    use_when: "creating a Map of Content index"
  - name: research.md
    use_when: "capturing research from web or sources"
```

#### `## Exclusions`
The agent must not read or modify `excluded_paths`. The agent can read
`read_only_paths`, but it must not modify them. The health scan skips both lists.

```yaml
excluded_paths:
  - .obsidian/               # Obsidian config
  - _reports/                # Vault Keeper health reports
  - 90-system/private/       # Personal/sensitive material
  - .git/                    # Version control internals
  - .trash/                  # Obsidian trash

read_only_paths:
  - 90-system/templates/     # Templates are referenced, not modified
  - 90-system/skills/        # Skills are used, not rewritten

accepted_orphan_zones:
  - daily/                   # Scan these notes, but omit them from orphan reports

generated_files:             # Auto-generated indexes/MOCs. Links FROM these files
  - 90-system/indexes/       # do not count as inbound links (a generated index that
                             # links to everything would otherwise mask every real
                             # orphan), and these files are never orphans themselves.

link_allowlist:              # Wikilink targets that intentionally point at nothing
  - some-planned-note        # (planned notes, external anchors). Not reported broken.

duplicate_allowlist:         # Extra basenames allowed to repeat across folders.
  - meeting-notes            # Hub names (00-Index, index, readme) are always allowed.
```

Use `excluded_paths` as the canonical key. If it is absent, the skill accepts the
old `exclusions` key as an alias.

#### `## Expansion Domains`
Topics the vault should cover. The Curator uses this to find gaps:

```yaml
domains:
  - name: "AI and Machine Learning"
    depth: deep              # deep | moderate | surface
    subtopics:
      - "Large Language Models"
      - "Agent architectures"
      - "Prompt engineering"
      - "Fine-tuning"
    freshness: 3_months      # how quickly content goes stale

  - name: "Business Strategy"
    depth: moderate
    subtopics:
      - "Go-to-market"
      - "Competitive analysis"
      - "Pricing models"
    freshness: 6_months

  - name: "Personal Development"
    depth: surface
    subtopics:
      - "Reading notes"
      - "Habits"
    freshness: 12_months
```

Use `domains` as the canonical key in this section. If it is absent, the skill
accepts the old `expansion_domains` key as an alias.

#### `## Archive Policy`
```yaml
archive_folder: 40-archive/
review_subfolder: 40-archive/review-needed/
auto_archive_after: never    # never | 6_months | 12_months
preserve_links: true         # keep wikilinks valid after archiving
forwarding_note: true        # leave a stub in the original location
external_archive: ~/backups/vault-snapshots/  # optional: recovery snapshot path; used before writes when git_aware is false
```

#### `## Formatting Rules`
```yaml
heading_start: h2            # h1 reserved for title (or frontmatter title)
list_style: dash             # dash | asterisk | plus
code_blocks: fenced          # fenced (```) always, with language tag
max_line_length: none        # none | 80 | 120
blank_lines_between_sections: 1
callout_style: obsidian      # > [!type] format
```

#### `## Agent Behavior`
Directives for how the agent should interact with this vault:

```yaml
bulk_report_above: 3         # file count threshold for a detailed change table
tag_floor: 1                 # min taxonomy tags per note; below this = under-tagged (0 disables)
max_new_notes_per_session: 10  # Curator cap; excess gaps queue as next-run targets
inbox_folder: 00-inbox/      # fallback destination for misplaced root notes
root_allowed_files:          # Markdown files that can stay at the vault root
  - VAULT.md
  - README.md
placement_rules:             # optional destinations for root notes
  type/daily: daily/
  type/project: 10-projects/
  type/moc: 90-system/indexes/
  type/reference: 30-resources/
  status/archive: 40-archive/
git_aware: true              # end sessions with git diff commands
provenance: strict            # strict | relaxed — how much sourcing is required
ai_content_marking: callout   # callout | frontmatter | none
session_log_folder: 90-system/session-log/  # must not sit inside excluded_paths or
                                            # read_only_paths; if it does, the skill
                                            # falls back to external_archive
reports_folder: _reports/    # where the health scan writes its report envelope
                             # (health-latest.md/.json + incident archive). Always
                             # excluded from scans — reports must not scan reports.
stale_after_days: 0          # flag notes with `status: active` whose file has not
                             # been modified in this many days; 0 disables the check
open_items_tracker: 90-system/open-items.md  # canonical open-work ledger (see below);
                             # created on first session close; must not sit inside
                             # excluded_paths or read_only_paths
quick_win_marker: "(quick)"  # rows carrying this marker are surfaced first
urgent_stale_days: 2         # top-urgency rows older than this are flagged stale
id_series_priority:          # tracker ID series, most urgent first; unlisted series
  - U                        # rank after listed ones alphabetically
  - D
  - W
  - B
```

### The health-scan report envelope

`scripts/vault-health-scan.sh --report <vault>` writes machine- and human-readable
reports to stable paths inside `reports_folder`:

- `health-latest.md` — human report, first line `Status: **OK|WARN|FAIL**`
- `health-latest.json` — the same findings as structured data (counts, findings
  list with severity/category/file/detail, and a findings fingerprint)
- `archive/health-<timestamp>.md` — written **only** when status is WARN/FAIL and
  the findings changed since the previous run. Clean and unchanged runs leave
  no residue, so the archive is a history of incidents, not of executions.

Consumers (sessions, dashboards, other scripts) should always read the
`-latest` paths and never chase timestamped filenames.

Severity model: **errors** (broken links, required-frontmatter violations,
secret-shaped strings) block confidence in the vault; **warnings** (orphans,
duplicate basenames, stale active notes, misplaced root notes) accumulate as a
visible backlog. `--strict` makes the scan exit 2 when any error exists — useful
for automation; the default exit stays 0 so autonomous sessions are never
blocked by a report.

### The open-items tracker

One markdown file (`open_items_tracker`) holds every open thread as a table row:

```markdown
| U7 🆕 | **Fix broken links in projects MOC** | hygiene | Opened 2026-08-14. Owner: **operator**. 3 links broken after rename; next: run health scan and repair. |
| ~~B4~~ ✅ | **Draft the pricing note** | research | Opened 2026-08-10. Owner: **agent**. Resolved 2026-08-14: note drafted and linked. |
```

Row anatomy, enforced by `scripts/open-items-scan.sh`:

- **ID** — a series letter block plus a number (`U7`, `B12`). IDs are **never
  reused**, including struck ones; the next ID in a series is max+1 across all
  rows. Duplicate IDs are an **error** — a tracker that lies is worse than none.
- **`Opened YYYY-MM-DD.` and `Owner:`** are mandatory; their absence is a warning.
  Rows must be self-contained: a future session acts on the row alone.
- **Struck rows** (`~~ID~~ ✅` + one-line resolution) are completed history —
  strike, never delete.
- **`(quick)`** (or the configured `quick_win_marker`) marks rows closable in
  minutes; the scan lists them first as default targets for tight scheduled runs.

`scripts/open-items-scan.sh --report <vault>` emits the ranked open list
(urgency series, then age), quick wins, stale urgent items
(older than `urgent_stale_days`), the next free ID per series, and integrity
findings, through the same report-envelope contract as the health scan
(`open-items-latest.md` / `.json`, incident-only archive, `--json`, `--strict`).

## Starter Template

A complete starter VAULT.md is available at `assets/vault-md-template.md`.
Copy it to your vault root and customize.

## Bootstrap Process

When a vault has no VAULT.md, the Vault Keeper can generate one:

1. Walk the folder tree (depth 3) and list all directories
2. Sample 30 random .md files and extract:
   - Frontmatter keys and value types
   - Naming patterns (case style, date prefixes, special prefixes)
   - Link style (wiki vs markdown)
   - Tag usage patterns
3. Check for existing templates folder
4. Check for `.obsidian/` to confirm it's an Obsidian vault
5. Detect an inbox folder and intentional root Markdown files
6. Write the detected values to `inbox_folder` and `root_allowed_files`
7. Draft VAULT.md with detected patterns as defaults
8. Write the draft with `[detected]` annotations, conservative defaults, and the
   `> [!ai-generated]` callout. List it first in the session summary, then continue
   with the run.
