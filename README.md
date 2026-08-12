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

## Research depth

The expansion workflow has a separate research-preference page for deep, non-superficial source work: [`docs/research-depth-standard.md`](docs/research-depth-standard.md). It defines corpus mining, primary-source discovery, article/newsletter/PDF retrieval, source manifests, minimum evidence, and closeout tests.

The skill remains responsible for execution and safety. The wiki page records the research preference and can evolve without turning every preference into a hard-coded skill behavior.

## How to use it

1. Make sure the vault has a `VAULT.md` at its root. If it does not, ask the skill to
   generate one.
2. Tell the agent what you want. For maintenance, use words such as "clean up my
   vault" or "audit my vault". For expansion, use words such as "find gaps in my
   vault" or "grow my knowledge base".
3. The skill completes maintenance and curation autonomously. Ask for preview-only
   mode when you do not want it to write.
4. Read the session summary at the end. It lists the files that changed and gives a
   command to review the changes.

## Safety

The skill obeys these rules.

- It does not delete a note. It moves the note to the archive folder.
- It records bulk changes in a reviewable table.
- It keeps wikilinks and frontmatter correct.
- It marks agent-written content with an `[!ai-generated]` callout.
- It gives a source for each new claim.

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
    curator-domain-select.sh   Curator domain rotation (bash)
    root-note-organize.sh      root note plan and moves (bash)
    vault-health-scan.sh       baseline health metrics (bash)
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
