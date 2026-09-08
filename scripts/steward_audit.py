#!/usr/bin/env python3
"""Combine deterministic Steward checks and judgment inputs in one envelope."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from prepare_recovery import prepare
from vault_schema import contract, frontmatter, in_path, yaml

SCRIPTS = Path(__file__).resolve().parent
SECTION_NAMES = ('health', 'frontmatter', 'tag', 'root-placement', 'formatting', 'structure')


def identity(category, file, key=''):
    return hashlib.sha256(json.dumps([category, file, key], ensure_ascii=False).encode()).hexdigest()[:20]


def report_path(vault, config):
    behavior = config.get('Agent Behavior', {})
    raw = behavior.get('reports_folder', '_reports/')
    relative = Path(str(raw))
    protected = config.get('Exclusions', {}).get('read_only_paths', [])
    # Excluded reports are normal generated surfaces, but read-only paths are not writable.
    def safe(path):
        return (str(path) not in ('', '.') and not path.is_absolute() and '..' not in path.parts
                and not any(in_path(path.as_posix(), p) for p in protected)
                and not any(part.is_symlink() for part in [vault / path, *(vault / path).parents] if part != vault.parent))
    if not safe(relative):
        relative = Path('_reports')
    if not safe(relative):
        raise ValueError('No safe reports folder is available')
    return vault / relative


def note_paths(vault, config, reports):
    exclusions = config.get('Exclusions', {})
    protected = ['.git', '.obsidian', '.trash', 'node_modules', reports.relative_to(vault).as_posix(),
                 *exclusions.get('excluded_paths', exclusions.get('exclusions', [])),
                 *exclusions.get('read_only_paths', [])]
    for root, dirs, files in os.walk(vault, followlinks=False):
        relroot = Path(root).relative_to(vault)
        dirs[:] = sorted(d for d in dirs if not (Path(root) / d).is_symlink()
                         and not any(in_path((relroot / d).as_posix(), p) for p in protected))
        for name in sorted(files):
            rel = relroot / name
            if name.endswith('.md') and not (vault / rel).is_symlink() and not any(in_path(rel.as_posix(), p) for p in protected):
                yield rel.as_posix()


def body_lines(text):
    lines = text.splitlines()
    if lines and lines[0] == '---':
        end = next((i for i in range(1, len(lines)) if lines[i] == '---'), len(lines) - 1)
        lines = lines[end + 1:]
    # Keep code contents out of heading and whitespace diagnostics.
    fence = None
    for line in lines:
        match = re.match(r'^\s{0,3}(`{3,}|~{3,})', line)
        if match:
            token = match[1]
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence):
                fence = None
            yield ''
        elif fence is None:
            yield line


def audit(vault):
    config = contract(vault / 'VAULT.md') if (vault / 'VAULT.md').exists() else {}
    reports = report_path(vault, config)
    health = json.loads(subprocess.check_output([str(SCRIPTS / 'vault-health-scan.sh'), '--json', str(vault)], text=True))
    moves = json.loads(subprocess.check_output([str(SCRIPTS / 'root-note-organize.sh'), '--json', str(vault)], text=True))
    sections = {name: {'findings': [], 'inputs': {}} for name in SECTION_NAMES}

    def add(section, category, file, detail, classification='deterministic', severity='warning', key=''):
        finding_id = identity(category, file, key)
        for existing in sections[section]['findings']:
            if existing['id'] == finding_id:
                existing['occurrences'] += 1
                return
        sections[section]['findings'].append(dict(id=finding_id, category=category,
            file=file, detail=detail, classification=classification, severity=severity, occurrences=1))

    for finding in health['findings']:
        category = finding['category']
        section = ('frontmatter' if category == 'frontmatter' else 'tag' if category.startswith('domain-tag')
                   else 'root-placement' if category == 'misplaced-root' else 'health')
        add(section, category, finding['file'], finding['detail'], severity=finding['severity'], key=finding['detail'])
    sections['health']['inputs']['counts'] = health['counts']
    sections['root-placement']['inputs']['move_manifest'] = moves
    sections['frontmatter']['inputs']['schema'] = config.get('Frontmatter Schema', {})
    taxonomy = config.get('Tag Taxonomy', {})
    sections['tag']['inputs']['taxonomy'] = taxonomy
    naming = config.get('Naming Conventions', {})
    formatting = config.get('Formatting Rules', {})
    sections['formatting']['inputs']['rules'] = formatting
    sections['structure']['inputs']['naming_rules'] = naming
    sections['structure']['inputs']['placement_rules'] = config.get('Agent Behavior', {}).get('placement_rules', {})
    vocabulary = set(taxonomy.get('valid_tags', []) + taxonomy.get('domain_tags', []) + taxonomy.get('topic_tags', []))
    generated = config.get('Exclusions', {}).get('generated_files', [])
    root_allowed = {'VAULT.md', 'README.md', *config.get('Agent Behavior', {}).get('root_allowed_files', [])}
    inventory = []
    directories = set()
    for rel in note_paths(vault, config, reports):
        if rel in root_allowed or any(in_path(rel, p) for p in generated):
            continue
        path = vault / rel
        text = path.read_text(encoding='utf-8')
        lines = list(body_lines(text))
        try:
            fm = frontmatter(path)
        except (ValueError, yaml.YAMLError):
            fm = {}
        tags = fm.get('tags', [])
        tags = tags if isinstance(tags, list) else []
        tags = [t for t in tags if isinstance(t, str)]
        inventory.append({'file': rel, 'tags': tags, 'headings': [line for line in lines if re.match(r'^#{1,6} ', line)],
                          'word_count': len(' '.join(lines).split()),
                          'content_hash': hashlib.sha256('\n'.join(lines).encode()).hexdigest()})
        if Path(rel).parent != Path('.'):
            directories.add(Path(rel).parent.as_posix())
        if vocabulary:
            unknown = sorted(set(tags) - vocabulary)
            if unknown:
                add('tag', 'unknown-tag', rel, 'outside configured vocabulary: ' + ', '.join(unknown))
        if not tags and vocabulary:
            add('tag', 'tag-assignment', rel, 'Select tags from note content and the configured taxonomy.', 'judgment-required')
        if sum(bool(re.match(r'^# ', line)) for line in lines) > 1:
            add('formatting', 'multiple-h1', rel, 'More than one H1 heading.')
        blank_limit = formatting.get('blank_lines_between_sections', 1)
        blank_runs = re.findall(r'\n(?:[ \t]*\n){2,}', '\n'.join(lines))
        if any(run.count('\n') - 1 > blank_limit for run in blank_runs):
            add('formatting', 'blank-lines', rel, f'Blank-line run exceeds {blank_limit}.')
        if naming:
            add('structure', 'naming-review', rel, 'Check the filename against its role and configured naming rules.', 'judgment-required')
        rules = config.get('Agent Behavior', {}).get('placement_rules', {})
        destinations = {str(rules[f'{key}/{fm[key]}']).strip('/') for key in ('type', 'status')
                        if key in fm and f'{key}/{fm[key]}' in rules}
        if destinations and Path(rel).parent.as_posix() not in destinations:
            add('structure', 'placement-review', rel, 'Configured destinations: ' + ', '.join(sorted(destinations)),
                'judgment-required' if len(destinations) > 1 else 'deterministic')
    hub = naming.get('hub_file')
    if hub:
        for directory in sorted(directories):
            if not (vault / directory / hub).is_file():
                add('structure', 'missing-hub', directory, 'Missing configured hub: ' + hub)
    sections['structure']['inputs']['notes'] = inventory
    sections['structure']['inputs']['folders'] = sorted(directories)
    if inventory:
        add('health', 'content-duplicate-review', '', 'Compare note headings and content for overlapping claims; use the note inventory.', 'judgment-required')
    for section in sections.values():
        section['findings'].sort(key=lambda f: (f['file'], f['category'], f['id']))
    findings = [f for section in sections.values() for f in section['findings']]
    status = 'FAIL' if any(f['severity'] == 'error' for f in findings) else 'WARN' if findings else 'OK'
    return dict(schema_version=1, vault=str(vault), date=datetime.date.today().isoformat(), status=status,
                fingerprint=hashlib.sha256(json.dumps(sections, sort_keys=True).encode()).hexdigest(), sections=sections), reports


def render(envelope):
    lines = [f"# Steward Audit: {envelope['status']}", '']
    for name, section in envelope['sections'].items():
        lines.extend([f'## {name}', ''])
        for finding in section['findings']:
            lines.append(f"- [{finding['classification']}] {finding['file']}: {finding['detail']} ({finding['id']})")
        if not section['findings']:
            lines.append('No findings.')
        lines.append('')
    return '\n'.join(lines)


def atomic_write(path, text):
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(text)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json', action='store_true', help='Write JSON to stdout (read-only unless --report is set)')
    parser.add_argument('--report', action='store_true', help='Persist JSON and Markdown in reports_folder')
    parser.add_argument('--strict', action='store_true', help='Exit 2 on error findings')
    parser.add_argument('vault', type=Path)
    args = parser.parse_args()
    vault = args.vault.resolve()
    envelope, reports = audit(vault)
    serialized = json.dumps(envelope, ensure_ascii=False, indent=2) + '\n'
    if args.report:
        snapshot = prepare(vault)
        if snapshot:
            import sys
            print('Recovery snapshot: ' + str(snapshot), file=sys.stderr)
        reports.mkdir(parents=True, exist_ok=True)
        atomic_write(reports / 'steward-latest.json', serialized)
        atomic_write(reports / 'steward-latest.md', render(envelope))
    print(serialized if args.json else render(envelope), end='')
    raise SystemExit(2 if args.strict and envelope['status'] == 'FAIL' else 0)
