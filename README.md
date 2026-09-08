![Obsidian Vault Keeper banner](obsidian-vault-keeper-banner.png)

# Obsidian Vault Keeper

Obsidian Vault Keeper is an agent skill. It maintains, organizes, and expands an
Obsidian vault. It reads a `VAULT.md` file at the vault root and obeys the rules in
that file. One skill can therefore work on vaults that use different folders,
schemas, and conventions.

## Two modes

The skill works in two modes.

- **Steward** does maintenance. It runs a health scan, standardizes notes, merges
  duplicates, builds Maps of Content, and normalizes formatting.
- **Curator** does expansion. It finds knowledge gaps, researches topics on the web,
  and drafts new notes with sources.

## The vault contract

`VAULT.md` is the contract between you and the skill. It lives at the vault root. It
defines the folder structure, the naming rules, the frontmatter schema, the tag
taxonomy, the exclusion zones, the expansion domains, the link rules, and the archive
policy.

`VAULT.md` is authoritative for configuration. Where a value in `VAULT.md` differs
from a default in this skill, the `VAULT.md` value wins.

If the vault has no `VAULT.md`, the skill scans the vault, detects the current
conventions, writes a conservative draft, and marks it for review.

## How to use it

1. Make sure the vault has a `VAULT.md` at its root. If it does not, ask the skill to
   generate one.
2. Tell the agent what you want. For maintenance, use words such as "clean up my
   vault" or "audit my vault". For expansion, use words such as "find gaps in my
   vault" or "grow my knowledge base".
3. The skill completes maintenance and curation autonomously. There is no preview
   mode; review changes afterward with git or the snapshot.
4. Read the session summary at the end. It lists the files that changed and gives a
   command to review the changes.

## Steward audit command

Run `scripts/steward-audit.sh --json <vault>` for a read-only audit. Add `--report`
to persist the JSON and Markdown reports. Add `--strict` to return exit code 2 when
error findings exist. The envelope covers health, frontmatter, tags, root placement,
formatting, and structure. Each finding has a stable ID and a classification.
See [the audit reference](references/steward-audit.md) for its fields and limits.

The scripts need Python 3 and PyYAML in addition to Bash and the existing shell tools.
Install PyYAML with `python3 -m pip install PyYAML` if it is absent.

## Safety

The skill obeys these rules.

- It does not delete a note. It moves the note to the archive folder.
- It records bulk changes in a reviewable table.
- It keeps wikilinks and frontmatter correct.
- It marks agent-written content with an `[!ai-generated]` callout.
- It gives a source for each new claim.

The health scan detects the mechanically decidable problems deterministically —
broken wikilinks, orphans (immune to generated-index masking), required-frontmatter
violations, duplicate basenames, stale active notes, and secret-shaped strings —
and can write a stable report envelope (`_reports/health-latest.md` + `.json`,
with archive copies only for incidents). Scripts produce guarantees; the model's
judgment is spent on interpreting and fixing findings, not on re-deriving them.
`--strict` gives automation a real exit code; the default exit never blocks a
session on a report.

Every session ends by settling the open-items tracker: each unfinished or
follow-up-pending thread gets a self-contained row with a never-reused ID, an
open date, and an owner; completed rows are struck, never deleted. The
open-items scan ranks what's open by urgency and age, surfaces rows marked
`(quick)` as quick wins for tight scheduled runs, flags stale urgent items, and
hands the next session its starting queue — so nothing depends on reading the
right session summary, and no thread silently drops.

Interactive, unattended, and scheduled sessions use autonomy by default. The skill
can move, rename, merge, and format notes after it creates the required recovery point.
It defers only ambiguous or unsafe work. The Curator changes its primary domain after
three consecutive runs unless the operator renews that domain.

The Steward keeps ordinary notes out of the vault root. VAULT.md defines the allowed
root files, the inbox folder, and optional placement rules. The Steward applies clear
root-note moves and updates affected links.

For a vault with no git, set `git_aware: false` in `VAULT.md` and give a snapshot path
in `external_archive`. The skill makes a snapshot before the first write. It uses that
snapshot as the recovery point.

## Files

```
obsidian-vault-keeper/
  SKILL.md                     the main instructions (what and when)
  references/
    vault-config-spec.md       the VAULT.md schema and a starter
    maintenance-ops.md         Steward procedures (how)
    expansion-ops.md           Curator procedures (how)
  scripts/
    steward-audit.sh          combined Steward audit and JSON envelope
    curator-domain-select.sh   Curator domain rotation (bash)
    root-note-organize.sh      root note plan and moves (bash)
    vault-health-scan.sh       deterministic health diagnostics + report envelope (bash)
    open-items-scan.sh         open-items tracker: ranking, quick wins, integrity (bash)
  assets/
    vault-md-template.md       a copy-and-edit VAULT.md starter
  tests/
    run-tests.sh               deterministic contract tests
```

`SKILL.md` gives the what and the when. The reference files give the how.

## Install

Put this folder in your agent skills directory, for example
`~/.agents/skills/obsidian-vault-keeper/`. The agent loads the skill when your request
matches its triggers.

## License

MIT. See `LICENSE`.
