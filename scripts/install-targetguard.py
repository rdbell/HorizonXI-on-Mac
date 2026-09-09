#!/usr/bin/env python3
"""Install the client targeting guard without replacing any existing addon/configuration."""
import argparse
from pathlib import Path
import shutil


def install(game: Path, source: Path, backup: Path) -> None:
    if not (source / 'targetguard.dll').is_file():
        raise SystemExit('Build first with scripts/build-targetguard.sh')
    scripts = [game / 'scripts' / 'default.txt']
    # The local test profile can use its separate copy of the startup script.
    local = game / 'scripts' / 'perfscene.txt'
    if local.is_file():
        scripts.append(local)
    if not scripts[0].is_file():
        raise SystemExit('Missing scripts/default.txt; refusing to invent a startup layout')
    target = game / 'addons' / 'targetguard'
    backup.mkdir(parents=True, exist_ok=False)
    backup.chmod(0o700)
    for script in scripts:
        shutil.copy2(script, backup / script.name)
    if target.exists():
        shutil.copytree(target, backup / 'targetguard')
    target.mkdir(parents=True, exist_ok=True)
    for name in ('targetguard.lua', 'targetguard.dll'):
        shutil.copy2(source / name, target / name)
    for script in scripts:
        data = script.read_bytes()
        if any(line.strip().lower() == b'/addon load targetguard' for line in data.splitlines()):
            continue
        newline = b'\r\n' if b'\r\n' in data else b'\n'
        data += (b'' if data.endswith(b'\n') else newline) + b'/addon load targetguard' + newline
        script.write_bytes(data)
    print(f'Installed targetguard. Rollback copies: {backup}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('game', type=Path)
    parser.add_argument('--backup', type=Path, required=True)
    args = parser.parse_args()
    install(args.game, Path(__file__).resolve().parents[1] / 'addons' / 'targetguard', args.backup)
