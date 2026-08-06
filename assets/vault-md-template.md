# VAULT.md — Operating Contract

> This file is the front door for both humans and AI agents. It describes what
> this vault is, how it's organized, and what rules any agent must follow.
> Customize every section below for your vault.

## Purpose

<!-- One paragraph: what is this vault for? What domains does it cover? -->
This vault is a personal knowledge base for [describe your focus areas].
It captures research, decisions, project context, and reference material
to support [your goals].

## Structure

```
vault-root/
  00-inbox/              # Unsorted captures, quick thoughts, clippings
  10-projects/           # Active projects with defined outcomes and deadlines
  20-areas/              # Ongoing responsibilities with no end date
  30-resources/          # Reference material organized by topic
  40-archive/            # Completed, retired, or merged material
    review-needed/       # Items pending human review before full archive
  90-system/             # Vault infrastructure
    templates/           # Note templates
    skills/              # Agent skills
    indexes/             # Tag indexes, MOC indexes
    session-log/         # Agent session summaries
  daily/                 # Daily notes (YYYY-MM-DD.md)
```

## Naming Conventions

```yaml
style: kebab-case
date_prefix: false
max_length: 60
daily_notes: "YYYY-MM-DD"
people_prefix: ""           # use people/ folder instead of prefix
```

## Frontmatter Schema

```yaml
required:
  - title: string
  - created: date
  - tags: list
  - status: enum [draft, active, review, archive]

optional:
  - aliases: list
  - source: url
  - date_modified: date
  - project: string
  - type: enum [note, moc, daily, meeting, decision, reference, person]
  - confidence: enum [high, medium, low, unverified]
  - ai_generated: boolean
```

## Tag Taxonomy

```yaml
domains:
  # Add your top-level tag domains here
  - topic/
  - project/
  - type/
  - status/

# Add your valid tags here. Tags outside this list will be flagged.
valid_tags:
  - topic/example
  - project/example
  - type/note
  - type/moc
  - type/reference
  - type/meeting
  - type/decision
  - status/active
  - status/draft
  - status/stale
  - status/stub
```

## Link Conventions

```yaml
style: wikilink
aliases: true
shortest_path: true
```

## Templates

```yaml
location: 90-system/templates/
templates:
  - name: note.md
    use_when: "default new note"
  - name: meeting.md
    use_when: "meeting notes"
  - name: decision.md
    use_when: "recording a decision"
  - name: project.md
    use_when: "starting a new project"
  - name: person.md
    use_when: "a page for a person or contact"
  - name: moc.md
    use_when: "creating a Map of Content"
  - name: research.md
    use_when: "capturing web research"
```

## Exclusions

```yaml
excluded_paths:
  - .obsidian/
  - .git/
  - .trash/
  - 90-system/private/

read_only_paths:
  - 90-system/templates/
  - 90-system/skills/
```

## Expansion Domains

<!-- Define what your vault should cover and how deeply -->
```yaml
domains:
  - name: "Your Domain 1"
    depth: deep              # deep | moderate | surface
    subtopics:
      - "Subtopic A"
      - "Subtopic B"
    freshness: 3_months

  - name: "Your Domain 2"
    depth: moderate
    subtopics:
      - "Subtopic C"
      - "Subtopic D"
    freshness: 6_months
```

## Archive Policy

```yaml
archive_folder: 40-archive/
review_subfolder: 40-archive/review-needed/
auto_archive_after: never
preserve_links: true
forwarding_note: true
external_archive: ~/backups/vault-snapshots/  # optional: recovery snapshot path; used before writes when git_aware is false
```

## Formatting Rules

```yaml
heading_start: h2
list_style: dash
code_blocks: fenced
max_line_length: none
blank_lines_between_sections: 1
callout_style: obsidian
```

## Agent Behavior

```yaml
approval_required_above: 3
git_aware: true
provenance: strict
ai_content_marking: callout
session_log_folder: 90-system/session-log/
```
