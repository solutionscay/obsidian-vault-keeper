import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class AuditTests(unittest.TestCase):
    def test_envelope_and_persistence(self):
        with tempfile.TemporaryDirectory() as temporary:
            vault = Path(temporary) / 'vault'
            vault.mkdir()
            (vault / 'notes').mkdir()
            (vault / 'locked').mkdir()
            (vault / 'locked/hidden.md').write_text('# One\n# Two\n')
            (vault / 'VAULT.md').write_text(f'''## Agent Behavior
```yaml
git_aware: false
reports_folder: reports/
inbox_folder: notes/
```
## Archive Policy
```yaml
external_archive: {temporary}/backup
```
## Frontmatter Schema
```yaml
required:
  - status: enum [draft]
```
## Tag Taxonomy
```yaml
domain_tags: [alpha]
topic_tags: [topic]
```
## Naming Conventions
```yaml
hub_file: 00-Index.md
```
## Exclusions
```yaml
read_only_paths:
  - locked/
```
''')
            (vault / 'notes/note.md').write_text('---\nstatus: invalid\ntags: [alpha, unknown]\n---\n# One\n# Two\n[[missing]] [[missing]]\n')
            command = [str(ROOT / 'scripts/steward-audit.sh'), '--json', str(vault)]
            before = {p.relative_to(vault).as_posix(): (p.read_bytes(), p.stat().st_mtime_ns) for p in vault.rglob('*') if p.is_file()}
            first = json.loads(subprocess.check_output(command))
            second = json.loads(subprocess.check_output(command))
            self.assertEqual(first, second)
            self.assertEqual(first['schema_version'], 1)
            self.assertEqual(set(first['sections']), {'health', 'frontmatter', 'tag', 'root-placement', 'formatting', 'structure'})
            findings = [f for section in first['sections'].values() for f in section['findings']]
            self.assertTrue({'multiple-h1', 'missing-hub', 'unknown-tag', 'frontmatter', 'broken-link'} <= {f['category'] for f in findings})
            self.assertEqual({f['classification'] for f in findings}, {'deterministic', 'judgment-required'})
            self.assertEqual(len({f['id'] for f in findings}), len(findings))
            self.assertEqual(next(f['occurrences'] for f in findings if f['category'] == 'broken-link'), 2)
            self.assertFalse(any(f['file'].startswith('locked/') for f in findings))
            self.assertEqual(before, {p.relative_to(vault).as_posix(): (p.read_bytes(), p.stat().st_mtime_ns) for p in vault.rglob('*') if p.is_file()})
            subprocess.run(command + ['--report'], check=True, capture_output=True)
            persisted = json.loads((vault / 'reports/steward-latest.json').read_text())
            self.assertEqual(first, persisted)
            self.assertTrue(list((Path(temporary) / 'backup').glob('*.tar.gz')))
            self.assertEqual(first, json.loads(subprocess.check_output(command)))

    def test_formatting_rules_skip_code_and_strict_errors(self):
        with tempfile.TemporaryDirectory() as temporary:
            vault = Path(temporary)
            (vault / 'notes').mkdir()
            (vault / 'VAULT.md').write_text("""## Formatting Rules
```yaml
blank_lines_between_sections: 2
```
## Frontmatter Schema
```yaml
required:
  - status: enum [draft]
```
""")
            (vault / 'notes/good.md').write_text('---\nstatus: draft\n---\n# Title\n\n\nText\n```markdown\n# Code one\n# Code two\n```\n')
            command = [str(ROOT / 'scripts/steward-audit.sh'), '--json', '--strict', str(vault)]
            good = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(good.returncode, 0)
            self.assertEqual(json.loads(good.stdout)['sections']['formatting']['findings'], [])
            (vault / 'notes/bad.md').write_text('---\nstatus: invalid\n---\n# One\n# Two\n\n\n\nText\n')
            bad = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(bad.returncode, 2)
            self.assertEqual({f['category'] for f in json.loads(bad.stdout)['sections']['formatting']['findings']},
                             {'multiple-h1', 'blank-lines'})

if __name__ == '__main__':
    unittest.main()
