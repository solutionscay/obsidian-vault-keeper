#!/usr/bin/env python3
"""Create an external recovery snapshot before a no-git vault write."""
import datetime
import os
from pathlib import Path
import sys
import tarfile
import tempfile

from vault_schema import contract, in_path


def prepare(vault):
    vault = Path(vault).resolve()
    config = contract(vault / 'VAULT.md') if (vault / 'VAULT.md').exists() else {}
    if config.get('Agent Behavior', {}).get('git_aware', True) is not False:
        return None
    destination = config.get('Archive Policy', {}).get('external_archive')
    destination = Path(destination).expanduser() if destination else Path.home() / '.vault-keeper/snapshots'
    if not destination.is_absolute():
        raise ValueError('external_archive must be an absolute external path')
    destination = destination.resolve()
    if destination == vault or vault in destination.parents:
        raise ValueError('recovery snapshots must be outside the vault')
    excluded = config.get('Exclusions', {}).get('excluded_paths',
               config.get('Exclusions', {}).get('exclusions', []))
    excluded = ['.git', '.obsidian', '.trash', 'node_modules', *excluded]
    destination.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S')
    fd, name = tempfile.mkstemp(prefix=f'{vault.name}-{stamp}-', suffix='.tar.gz', dir=destination)
    os.close(fd)
    snapshot = Path(name)
    try:
        with tarfile.open(snapshot, 'w:gz', dereference=False) as archive:
            for root, dirs, files in os.walk(vault, followlinks=False):
                relative = Path(root).relative_to(vault)
                dirs[:] = sorted(d for d in dirs if not any(in_path((relative / d).as_posix(), p) for p in excluded))
                for filename in sorted(files):
                    rel = relative / filename
                    if not any(in_path(rel.as_posix(), p) for p in excluded):
                        archive.add(vault / rel, arcname=rel.as_posix(), recursive=False)
        with tarfile.open(snapshot) as archive:
            archive.getmembers()
    except BaseException:
        snapshot.unlink(missing_ok=True)
        raise
    return snapshot


if __name__ == '__main__':
    snapshot = prepare(sys.argv[1])
    if snapshot:
        print(snapshot)
