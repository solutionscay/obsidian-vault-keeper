import json
import subprocess
import tempfile
import tarfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class SchemaTests(unittest.TestCase):
    def test_types_enums_and_collection_override(self):
        with tempfile.TemporaryDirectory() as directory:
            vault = Path(directory)
            (vault / 'VAULT.md').write_text('''## Frontmatter Schema
```yaml
required:
  - status: enum [draft, reference, authoritative]
  - updated: date
  - type: string
  - tags: list
collection_overrides:
  - path: special/
    required:
      - status: enum [complete]
```
''')
            notes = {
                'valid.md': 'status: reference\nupdated: 2026-09-08\ntype: note\ntags: [a]',
                'bad.md': 'status: active\nupdated: 2026-02-30\ntype: [note]\ntags: topic',
                'special/local.md': 'status: complete\nupdated: "2026-09-08"\ntype: note\ntags:\n  - a\nlocal_key: valid',
            }
            for name, data in notes.items():
                path = vault / name
                path.parent.mkdir(exist_ok=True)
                path.write_text('---\n' + data + '\n---\nBody\n')
            result = json.loads(subprocess.check_output([str(ROOT / 'scripts/vault-health-scan.sh'), '--json', str(vault)]))
            findings = [f for f in result['findings'] if f['category'] == 'frontmatter']
            self.assertEqual(len(findings), 4)
            self.assertEqual({f['file'] for f in findings}, {'bad.md'})

    def test_domain_tags_and_exceptions(self):
        with tempfile.TemporaryDirectory() as directory:
            vault = Path(directory)
            (vault / 'VAULT.md').write_text("""## Tag Taxonomy
```yaml
domain_tags: [alpha, beta]
topic_tags: [topic]
domain_tag_exceptions: [notes/00-Index.md]
```
## Exclusions
```yaml
excluded_paths:
  - private/
read_only_paths:
  - locked/
generated_files:
  - generated.md
```
""")
            notes = {'flow.md': '[alpha, topic]', 'block.md': '\n  - beta\n  - topic',
                     'zero.md': '[topic]', 'many.md': '[alpha, beta, topic]',
                     'notes/00-Index.md': '[]', 'private/secret.md': '[]',
                     'locked/locked.md': '[]', 'generated.md': '[]'}
            for name, tags in notes.items():
                path = vault / name
                path.parent.mkdir(exist_ok=True)
                path.write_text('---\ntags: ' + tags + '\n---\nBody\n')
            result = json.loads(subprocess.check_output([str(ROOT / 'scripts/vault-health-scan.sh'), '--json', str(vault)]))
            findings = [f for f in result['findings'] if f['category'].startswith('domain-tag')]
            self.assertEqual({(f['file'], f['category']) for f in findings},
                             {('zero.md', 'domain-tag-missing'), ('many.md', 'domain-tag-multiple')})
            self.assertIn('["alpha", "beta"]', next(f['detail'] for f in findings if f['file'] == 'many.md'))

    def test_nested_hub_links(self):
        with tempfile.TemporaryDirectory() as directory:
            vault = Path(directory)
            (vault / 'VAULT.md').write_text("""## Exclusions
```yaml
generated_files:
  - generated.md
```
""")
            notes = {
                'B2C/00-Index.md': '[[Product/00-Index#Overview|Product]]',
                'B2C/Product/00-Index.md': 'Product body',
                'K-12/00-Index.md': '[[K-12/Daily/00-Index]]',
                'K-12/Daily/00-Index.md': 'Daily body',
                'notes/source.md': '[[Unique]] [[Alias#Heading|label]]',
                'deep/Unique.md': 'Unique body',
                'deep/aliased.md': '---\naliases: [Alias]\n---\nAlias body',
                'generated.md': '[[generated-only]]',
                'generated-only.md': 'Generated-only body',
            }
            for name, body in notes.items():
                path = vault / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(body + '\n')
            result = json.loads(subprocess.check_output([str(ROOT / 'scripts/vault-health-scan.sh'), '--json', str(vault)]))
            self.assertFalse([f for f in result['findings'] if f['category'] == 'broken-link'])
            orphans = {f['file']: f['detail'] for f in result['findings'] if f['category'] == 'orphan'}
            for target in ['B2C/Product/00-Index.md', 'K-12/Daily/00-Index.md', 'deep/Unique.md', 'deep/aliased.md']:
                self.assertNotIn(target, orphans)
            self.assertIn('ignored generated sources: generated.md', orphans['generated-only.md'])

    def test_no_git_report_snapshot_order(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            vault = base / 'vault'
            vault.mkdir()
            backup = base / 'snapshots'
            (vault / 'VAULT.md').write_text(f"""## Agent Behavior
```yaml
git_aware: false
reports_folder: reports/
```
## Archive Policy
```yaml
external_archive: {backup}
```
""")
            (vault / 'note.md').write_text('Original content\n')
            before = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in vault.iterdir()}
            for script in ['vault-health-scan.sh', 'open-items-scan.sh']:
                subprocess.run([str(ROOT / 'scripts' / script), '--json', str(vault)], check=True, capture_output=True)
            self.assertEqual(before, {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in vault.iterdir()})
            self.assertFalse(backup.exists())
            for script, report in [('vault-health-scan.sh', 'health'), ('open-items-scan.sh', 'open-items')]:
                run = subprocess.run([str(ROOT / 'scripts' / script), '--report', str(vault)], check=True, capture_output=True, text=True)
                snapshot = Path(run.stderr.split('Recovery snapshot: ')[1].splitlines()[0])
                with tarfile.open(snapshot) as archive:
                    self.assertNotIn('reports/' + report + '-latest.json', archive.getnames())
                    self.assertEqual(archive.extractfile('note.md').read(), b'Original content\n')
                self.assertTrue((vault / 'reports' / (report + '-latest.json')).exists())

    def test_move_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            vault = Path(directory)
            (vault / 'inbox').mkdir()
            (vault / 'VAULT.md').write_text("""## Agent Behavior
```yaml
inbox_folder: inbox/
```
""")
            (vault / 'move.md').write_text('Body')
            (vault / 'collision.md').write_text('Body')
            (vault / 'inbox/collision.md').write_text('Existing')
            (vault / 'README.md').write_text('[[move.md#Heading|Label]] [Move](move.md)')
            command = [str(ROOT / 'scripts/root-note-organize.sh'), '--json']
            plan = json.loads(subprocess.check_output(command + [str(vault)]))
            self.assertTrue((vault / 'move.md').exists())
            planned = next(o for o in plan['operations'] if o['status'] == 'planned')
            self.assertEqual(planned['inbound_link_files'], ['README.md'])
            result = json.loads(subprocess.check_output(command + ['--apply', str(vault)]))
            self.assertEqual({o['status'] for o in result['operations']}, {'moved', 'collision'})
            moved = next(o for o in result['operations'] if o['status'] == 'moved')
            self.assertEqual((moved['source'], moved['destination'], moved['rule']), ('move.md', 'inbox/move.md', 'inbox fallback'))
            self.assertEqual(moved['inbound_link_files'], ['README.md'])
            manifest = vault / 'manifest.json'
            manifest.write_text(json.dumps(result))
            output = subprocess.check_output(['python3', str(ROOT / 'scripts/move_manifest.py'), 'table', str(manifest)], text=True)
            self.assertIn('move.md → inbox/move.md', output)
            self.assertIn('links updated: README.md', output)
            self.assertEqual(output.count('| moved |'), 1)

if __name__ == '__main__':
    unittest.main()
