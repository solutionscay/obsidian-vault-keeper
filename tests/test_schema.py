import json
import subprocess
import tempfile
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

if __name__ == '__main__':
    unittest.main()
