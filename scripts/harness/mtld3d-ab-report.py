#!/usr/bin/env python3
"""Within-run ABBA report for diagnostic mtld3d builds that log `mtld3d::ab` block markers.

python3 ab-report.py RUN_DIR
Uses the harness's conservative window selector (inverse-ab-report.py); requires contiguous
markers from 16 s before through 16 s after the measured phases. Prints a compact summary.
"""
from datetime import datetime
import importlib.util, json, re, sys
from pathlib import Path

H = Path(__file__).resolve().parent
s = importlib.util.spec_from_file_location('r', H / 'inverse-ab-report.py')
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
m.SWITCH = re.compile(r'\[([^ ]+) INFO .*mtld3d::ab\] ab block=(\d+) optimized=(true|false)')
run = Path(sys.argv[1]).resolve()
phases = json.loads((run / 'stress-report.json').read_text())['phases']
start = min(p['start'] for p in phases) - 16
end = max(p['end'] for p in phases) + 16
original = m.parse_switches
def parse(lines):
    selected = []
    for line in lines:
        match = m.SWITCH.search(line)
        if match and start <= datetime.fromisoformat(match[1].replace('Z', '+00:00')).timestamp() <= end:
            selected.append(line)
    return original(selected)
m.parse_switches = parse
report = m.report(run, ('crowdsteady', 'lightsteady'))
(run / 'ab-report.json').write_text(json.dumps(report, indent=2) + '\n')
print('valid', report['valid'], 'switches', report['switch_count'])
for p in report['phases']:
    b, o = p['baseline'], p['optimized']
    keys = [k for k in b if not isinstance(b[k], (list, dict))]
    print(p.get('name'), 'valid', p['valid'])
    for k in keys:
        bv, ov = b[k], o[k]
        if isinstance(bv, (int, float)) and isinstance(ov, (int, float)) and bv:
            print(f'  {k:14s} baseline {bv:10.3f}  optimized {ov:10.3f}  ({(ov - bv) / bv * 100:+.2f}%)')
