#!/usr/bin/env python3
"""Compare the diagnostic inverse-view ABBA variant in one fixed crowd run.

Uses the existing conservative mode-window exclusions. The diagnostic binary
alternates baseline/optimized/optimized/baseline in eight-second blocks. Neither
mode changes visible clipping behavior. This is not a production renderer option.
"""
import argparse
import csv
from datetime import datetime
import importlib.util
import json
from pathlib import Path
import re

SPEC = importlib.util.spec_from_file_location(
    'readback_ab', Path(__file__).with_name('readback-ab-report.py'))
windows = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(windows)
SWITCH = re.compile(r'\[([^ ]+) INFO .*inverse_ab block=(\d+) optimized=(true|false)')


def parse_switches(lines):
    result = []
    for line in lines:
        match = SWITCH.search(line)
        if not match:
            continue
        epoch = datetime.fromisoformat(match[1].replace('Z', '+00:00')).timestamp()
        block, optimized = int(match[2]), match[3] == 'true'
        if optimized != (block % 4 in (1, 2)):
            raise ValueError('mode does not match the diagnostic ABBA schedule')
        if result and (block != result[-1]['block'] + 1 or epoch <= result[-1]['epoch']):
            raise ValueError('missing, duplicate, or reordered mode boundary')
        # The shared window selector calls its generic boolean field "fused".
        result.append({'epoch': epoch, 'block': block, 'fused': optimized})
    return result


def report(run, scenarios=('crowdsteady',)):
    workload = json.loads((run / 'stress-report.json').read_text())
    session = Path(json.loads((run / 'active.json').read_text())['session'])
    logs = sorted(session.glob('horizon-loader-*.log'))
    if len(logs) != 1:
        raise ValueError('expected exactly one game log')
    switches = parse_switches(logs[0].read_text(errors='replace').splitlines())
    with (session / 'frame-times.csv').open() as source:
        frames = [{k: float(v) for k, v in row.items()} for row in csv.DictReader(source)]
    # Leave three seconds after the phase marker for its screenshot to finish.
    selected_phases = [{**p, 'start': p['start'] + 2} for p in workload['phases']]
    phases = windows.compare(frames, selected_phases, switches)
    for phase in phases:
        modes = phase.pop('modes')
        phase['baseline'], phase['optimized'] = modes['false'], modes['true']
        phase['valid'] = all(len(phase[key]['windows']) >= 4 for key in ('baseline', 'optimized'))
    return {
        'valid': workload['valid'] and workload['scenario'] in scenarios
                 and bool(phases) and all(p['valid'] for p in phases),
        'switch_count': len(switches), 'phases': phases,
        'note': 'Whole frames only; first two seconds after each log boundary and last second before '
                'the next are excluded, plus the first three seconds of the phase. '
                'At least four usable windows per mode required. '
                'Within-run comparison reduces drift but does not establish universal FPS gains.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    print(json.dumps(report(parser.parse_args().run), indent=2))
