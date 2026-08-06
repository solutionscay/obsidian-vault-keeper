# VAULT.md Configuration Specification

The `VAULT.md` file lives at the vault root and serves as the operating contract
between the vault owner and any agent skill that interacts with the vault. It is
both human-readable documentation and machine-parseable configuration.

## Why VAULT.md

Every vault is different. Folder names, naming conventions, tag taxonomies,
frontmatter schemas, and organizational philosophies vary widely. Rather than
hardcoding assumptions, the Vault Keeper reads VAULT.md to learn the vault's
rules before touching anything.

This pattern was popularized by the FrankX Starlight Second Brain architecture
and is now a common convention across agent skill ecosystems. The idea: the vault
itself carries its own operating manual.

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
```

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
Paths the agent must never read or modify:

```yaml
excluded_paths:
  - .obsidian/               # Obsidian config
  - 90-system/private/       # Personal/sensitive material
  - .git/                    # Version control internals
  - .trash/                  # Obsidian trash

read_only_paths:
  - 90-system/templates/     # Templates are referenced, not modified
  - 90-system/skills/        # Skills are used, not rewritten
```

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

#### `## Archive Policy`
```yaml
archive_folder: 40-archive/
review_subfolder: 40-archive/review-needed/
auto_archive_after: never    # never | 6_months | 12_months
preserve_links: true         # keep wikilinks valid after archiving
forwarding_note: true        # leave a stub in the original location
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
approval_required_above: 3   # file count threshold for bulk preview
git_aware: true              # end sessions with git diff commands
provenance: strict            # strict | relaxed — how much sourcing is required
ai_content_marking: callout   # callout | frontmatter | none
session_log_folder: 90-system/session-log/
```

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
5. Draft VAULT.md with detected patterns as defaults
6. Present to user with `[detected]` annotations so they can correct
7. Write only after explicit approval
