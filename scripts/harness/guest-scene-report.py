#!/usr/bin/env python3
"""Attribute complete guest-sampler windows to benchmark scenes after renderer restoration.

Renderer symbols are used only from a binary matching the captured SHA-256. Supply the
immutable --renderer-bundle to recover symbols when the installed renderer has changed.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path


def load(name: str):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'),
                                                Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


capture = load('capture-performance')
renderer = load('renderer-report')


def resolve_renderer_symbols(records: list[dict], identities: list[dict],
                             bundle: Path | None) -> dict:
    expected: dict[str, set[str]] = {}
    for identity in identities:
        if identity.get('sha256'):
            expected.setdefault(Path(identity['path']).name.lower(), set()).add(identity['sha256'])
    resolved = {}
    for record in records:
        for module in record['modules']:
            name = module['path'].replace('\\', '/').split('/')[-1].lower()
            if name not in expected:
                continue
            if name not in resolved:
                candidates = [Path(module['path'])]
                if bundle:
                    candidates.extend(bundle.rglob(name))
                # Multiple loaded copies with different contents need a more precise mapping.
                matches = [p for p in candidates if p.is_file()
                           and len(expected[name]) == 1 and capture.sha256(p) in expected[name]]
                resolved[name] = str(matches[0]) if matches else None
            module['symbol_path'] = resolved[name]
    return resolved


def complete_windows(records: list[dict], epoch: float, start: float, end: float) -> list[dict]:
    return [r for r in records if epoch + r['header']['window_start_s'] >= start
            and epoch + r['header']['window_end_s'] <= end]


def report(output: Path, bundle: Path | None) -> dict:
    fps = renderer.report(output)
    session = Path(json.loads((output / 'active.json').read_text())['session'])
    menu = json.loads((session / 'menu-run.json').read_text())
    pid = menu['game_pid']
    profile = session / f'x87-sample-{pid}.prof'
    final_record = capture.parse_x87_record(profile.read_text())
    epoch = capture.x87_profile_start_epoch(final_record)
    if epoch is None:
        raise ValueError('profile has no usable clock origin')
    windows = capture.read_x87_windows(Path(str(profile) + '.windows'))
    identities = json.loads((session / 'renderer-loaded-files.json').read_text())
    resolved = resolve_renderer_symbols(windows, identities, bundle)
    scenes = []
    for phase in fps['scenes']:
        selected = complete_windows(windows, epoch, phase['start'], phase['end'])
        scenes.append({'name': phase['name'], 'fps': phase.get('fps'),
                       'fps_valid': phase['valid'], 'profile_windows': len(selected),
                       'profile': capture.x87_record_summary(capture.merge_x87_records(selected))
                                  if selected else None})
    return {'run': output.name, 'problems': fps['problems'], 'renderer_symbols': resolved,
            'symbol_note': 'Null paths retain module offsets; restored binaries are not used.',
            'scenes': scenes}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('--renderer-bundle', type=Path)
    args = parser.parse_args()
    print(json.dumps(report(args.run, args.renderer_bundle), indent=2))


if __name__ == '__main__':
    main()
