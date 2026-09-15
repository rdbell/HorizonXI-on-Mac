#!/usr/bin/env python3
"""Report whole frames after a fixed settling exclusion in a validated stress run.

Keeps the workload report intact. Three seconds at phase start exclude the marker
screenshot; one second at the end excludes transitions. Separate launches can
still drift, so repeat controls and do not treat small differences as causal proof.
"""
import argparse
import csv
import json
import math
from pathlib import Path


def summarize(frames, phase, settle=3):
    lo, hi = phase['start'] + settle, phase['end'] - 1
    values = sorted(row['frame_ms'] for row in frames
                    if row['epoch'] - row['frame_ms'] / 1000 >= lo and row['epoch'] < hi)
    seconds = sum(values) / 1000
    result = {'name': phase['name'], 'frames': len(values), 'measured_seconds': seconds,
              'fps': len(values) / seconds if seconds else None}
    for label, fraction in [('p50_ms', .5), ('p95_ms', .95), ('p99_ms', .99), ('max_ms', 1)]:
        result[label] = values[math.ceil(len(values) * fraction) - 1] if values else None
    for threshold in (50, 100, 500):
        result[f'frames_over_{threshold}ms'] = sum(value > threshold for value in values)
    result['valid'] = phase['valid'] and len(values) >= 30 and seconds >= max(1, .9 * (hi - lo))
    return result


def report(run, settle=3):
    workload = json.loads((run / 'stress-report.json').read_text())
    restore = json.loads((run / 'restoration.json').read_text())
    session = Path(json.loads((run / 'active.json').read_text())['session'])
    with (session / 'frame-times.csv').open() as source:
        frames = [{key: float(value) for key, value in row.items()} for row in csv.DictReader(source)]
    phases = [summarize(frames, phase, settle) for phase in workload['phases']]
    restored = (restore['preferences_restored'] and restore['docker_unchanged']
                and not restore['related_processes'])
    return {'valid': workload['valid'] and restored and bool(phases) and all(p['valid'] for p in phases),
            'scenario': workload['scenario'], 'settle_seconds': settle,
            'phases': phases, 'note': __doc__}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('--settle', type=float, default=3)
    args = parser.parse_args()
    if not math.isfinite(args.settle) or args.settle < 0:
        parser.error('settle must be a finite nonnegative number')
    print(json.dumps(report(args.run, args.settle), indent=2))
