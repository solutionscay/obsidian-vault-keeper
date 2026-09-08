#!/usr/bin/env python3
"""Record move operations and render their session-summary table."""
import json
from pathlib import Path
import sys


def table(envelope):
    def cell(value):
        return str(value).replace('|', '&#124;').replace('\n', '<br>')
    lines = ['| File | Action | Reason |', '| --- | --- | --- |']
    for operation in envelope['operations']:
        path = operation['source']
        if operation['destination']:
            path += ' → ' + operation['destination']
        reason = operation['reason'] or operation['rule']
        if operation['inbound_link_files']:
            reason += '; links updated: ' if operation['status'] == 'moved' else '; inbound links: '
            reason += ', '.join(operation['inbound_link_files'])
        lines.append('| ' + ' | '.join(map(cell, [path, operation['status'], reason])) + ' |')
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    command, filename = sys.argv[1:3]
    if command == 'append':
        status, source, destination, rule, reason, *links = sys.argv[3:]
        with open(filename, 'a', encoding='utf-8') as stream:
            stream.write(json.dumps(dict(status=status, source=source, destination=destination,
                                         rule=rule, reason=reason, inbound_link_files=sorted(set(links)))) + '\n')
    elif command == 'envelope':
        operations = [json.loads(line) for line in Path(filename).read_text().splitlines()]
        print(json.dumps({'schema_version': 1, 'operations': operations}, indent=2))
    elif command == 'table':
        print(table(json.loads(Path(filename).read_text())), end='')
    else:
        raise SystemExit('Usage: move_manifest.py table <manifest.json>')
