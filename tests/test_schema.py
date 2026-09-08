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

if __name__ == '__main__':
    unittest.main()
