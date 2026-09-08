"""Parse the fenced vault contract and validate declared frontmatter types."""
import datetime
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    raise SystemExit('Install PyYAML: python3 -m pip install PyYAML')


class VaultLoader(yaml.SafeLoader):
    pass


# Keep dates as strings so an invalid calendar date becomes a field finding.
VaultLoader.yaml_implicit_resolvers = {
    key: [(tag, pattern) for tag, pattern in rules
          if tag != 'tag:yaml.org,2002:timestamp']
    for key, rules in yaml.SafeLoader.yaml_implicit_resolvers.items()
}


def parse_yaml(text):
    return yaml.load(text, Loader=VaultLoader)


def contract(path):
    sections = {}
    section = None
    fence = None
    lines = []
    for line in path.read_text(encoding='utf-8').splitlines():
        if fence is not None:
            if line.strip() == '```':
                data = parse_yaml('\n'.join(lines)) or {}
                if isinstance(data, dict):
                    sections.setdefault(section, {}).update(data)
                fence = None
            else:
                lines.append(line)
        elif line.startswith('## '):
            section = line[3:].strip()
        elif line.strip() == '```yaml':
            fence = True
            lines = []
    return sections


def fields(value):
    if isinstance(value, dict):
        return value
    result = {}
    for entry in value or []:
        if isinstance(entry, dict):
            result.update(entry)
        elif isinstance(entry, str):
            result[entry] = None
    return result


def frontmatter(path):
    text = path.read_text(encoding='utf-8')
    match = re.match(r'\A---\s*\n(.*?)\n---\s*(?:\n|$)', text, re.S)
    if not match:
        raise ValueError('missing or unclosed frontmatter block')
    data = parse_yaml(match[1])
    if not isinstance(data, dict):
        raise ValueError('frontmatter must be a mapping')
    return data


def in_path(rel, entry):
    entry = str(entry).removeprefix('./').rstrip('/')
    return rel == entry or rel.startswith(entry + '/') or Path(rel).match(entry)


def valid(value, declaration):
    if declaration is None:
        return True
    declaration = str(declaration).strip()
    if declaration.startswith('enum '):
        choices = parse_yaml(declaration[5:])
        return isinstance(value, str) and value in choices
    if declaration in ('string', 'path'):
        return isinstance(value, str)
    if declaration == 'list':
        return isinstance(value, list)
    if declaration == 'date':
        if type(value) is datetime.date:
            return True
        if isinstance(value, str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}', value):
            try:
                datetime.date.fromisoformat(value)
                return True
            except ValueError:
                pass
        return False
    raise ValueError('unsupported schema type: ' + declaration)


def validate(vault, rel, config):
    schema = config.get('Frontmatter Schema', {})
    required = fields(schema.get('required'))
    optional = fields(schema.get('optional'))
    # Narrower collection overrides replace only the named declarations.
    for override in sorted(schema.get('collection_overrides', []), key=lambda x: len(x['path'])):
        if in_path(rel, override['path']):
            required.update(fields(override.get('required')))
            optional.update(fields(override.get('optional')))
    if not required and not optional:
        return []
    try:
        data = frontmatter(vault / rel)
    except (ValueError, yaml.YAMLError):
        return [('frontmatter', 'missing or malformed frontmatter block')]
    findings = []
    missing = sorted(set(required) - set(data))
    if missing:
        findings.append(('frontmatter', 'missing required: ' + ' '.join(missing)))
    for name, declaration in {**optional, **required}.items():
        if name in data and not valid(data[name], declaration):
            findings.append(('frontmatter', f'{name}: expected {declaration}'))
    # Unknown properties are preserved, including collection-local keys.
    return findings


if __name__ == '__main__':
    vault = Path(sys.argv[1])
    config = contract(vault / 'VAULT.md') if (vault / 'VAULT.md').exists() else {}
    for rel in sys.argv[2:]:
        for category, detail in validate(vault, rel, config):
            print('\t'.join((category, rel, detail)))
