# Steward audit

Run `scripts/steward-audit.sh --json <vault>` to get JSON on stdout without vault
writes. Without `--json`, stdout contains Markdown. The `--report` option separately
persists `steward-latest.json` and `steward-latest.md` in `reports_folder`.
For `git_aware: false`, persistence first creates an external recovery snapshot.
`--strict` returns 2 when error findings exist. Other findings leave the exit code at 0.

The envelope has `schema_version: 1`, `vault`, `date`, `status`, `fingerprint`, and
`sections`. Each section has `findings` and `inputs`.

| Section | Checks and inputs |
| --- | --- |
| health | Existing health findings, counts, and duplicate-content review target |
| frontmatter | Required and optional type checks, enum checks, and configured schema |
| tag | Domain count, closed vocabulary, tag-assignment targets, and taxonomy |
| root-placement | Misplaced root findings and the complete move-plan manifest |
| formatting | Multiple H1 headings, excess blank lines, and formatting rules |
| structure | Missing configured hubs, placement rules, naming review targets, and note inventory |

Each finding has `id`, `category`, `file`, `detail`, `severity`, `classification`, and
`occurrences`. Repeated identical findings share one ID and an occurrence count.
Classification is either `deterministic` or `judgment-required`. IDs derive from the
finding category, path, and discriminator. An unchanged finding retains its ID across
runs; findings on a renamed file receive new IDs. The fingerprint excludes the run date.

The note inventory provides paths, headings, tags, word counts, and body hashes.
Use it to select notes for semantic comparison. Read eligible notes before deciding
whether their claims overlap. A body hash does not establish semantic equivalence.
Naming checks need the note's role and therefore remain judgment-required.
Only folders with eligible notes enter the configured hub check. Generated files and
protected paths do not enter these additional checks.

The focused health, open-items, and root-note commands remain available for direct use.
The audit invokes the focused health and root-note commands in read-only mode.
