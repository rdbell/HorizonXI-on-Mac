#!/usr/bin/env python3
"""Compare fused readback modes within each fixed stress phase.

The diagnostic renderer switches every eight seconds. Exclude boundary frames:
renderer log timestamps have one-second precision, so mode windows start two
seconds after the logged switch and end one second before the next switch.
"""
import argparse
import csv
from datetime import datetime
import json
from pathlib import Path
import re
import statistics

SWITCH = re.compile(r'\[([^ ]+) INFO .*readback_ab block=(\d+) fused=(true|false)')


def compare(frames, phases, switches):
    result = []
    for phase in phases:
        modes = {}
        for enabled in (False, True):
            windows = []
            collected = []
            for switch, following in zip(switches, switches[1:]):
                if switch['fused'] != enabled:
                    continue
                lo = max(phase['start'] + 1, switch['epoch'] + 2)
                hi = min(phase['end'] - 1, following['epoch'] - 1)
                if hi - lo < 1:
                    continue
                values = [row['frame_ms'] for row in frames
                          if row['epoch'] - row['frame_ms'] / 1000 >= lo
                          and row['epoch'] < hi]
                if not values:
                    continue
                duration = sum(values) / 1000
                windows.append({'block': switch['block'], 'frames': len(values),
                                'seconds': duration, 'fps': len(values) / duration})
                collected += values
            collected.sort()
            seconds = sum(collected) / 1000
            modes[str(enabled).lower()] = {
                'windows': windows, 'frames': len(collected), 'seconds': seconds,
                'fps': len(collected) / seconds if seconds else None,
                'p50_ms': statistics.median(collected) if collected else None,
                'p99_ms': collected[min(len(collected)-1, int(len(collected)*.99))] if collected else None,
            }
        off, on = modes['false']['fps'], modes['true']['fps']
        result.append({'phase': phase['name'], 'modes': modes,
                       'valid': all(len(v['windows']) >= 2 for v in modes.values()),
                       'fps_change_percent': 100 * (on / off - 1) if off and on else None})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path, help='stress suite root with crowd-report.json')
    args = parser.parse_args()
    report = json.loads((args.run / 'crowd-report.json').read_text())
    session = Path(json.loads((args.run / 'crowd/active.json').read_text())['session'])
    switches = []
    for path in session.glob('horizon-loader-*.log'):
        for line in path.read_text(errors='replace').splitlines():
            match = SWITCH.search(line)
            if match:
                switches.append({'epoch': datetime.fromisoformat(match[1].replace('Z', '+00:00')).timestamp(),
                                 'block': int(match[2]), 'fused': match[3] == 'true'})
    switches.sort(key=lambda item: item['epoch'])
    with (session / 'frame-times.csv').open() as source:
        frames = [{key: float(value) for key, value in row.items()} for row in csv.DictReader(source)]
    phases = compare(frames, report['phases'], switches)
    print(json.dumps({'valid': report['valid'] and all(p['valid'] for p in phases),
                      'switch_count': len(switches), 'phases': phases}, indent=2))


if __name__ == '__main__':
    main()
