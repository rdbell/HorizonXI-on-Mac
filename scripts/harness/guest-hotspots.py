#!/usr/bin/env python3
"""Guest-PC hot spots for one stress phase of a `--level standard` run.

  guest-hotspots.py RUN                       per-module leaf shares, wait syscalls
  guest-hotspots.py RUN --module Addons.dll   hot offsets inside one module (--bucket 0x100)
  guest-hotspots.py RUN --module ucrtbase.dll --lo 0x5c900 --hi 0x5cb00 --callers 2
                                              callers N frames above leaves in an offset range
  guest-hotspots.py RUN --module d3d9.dll --pdb d3d9.pdb --dll d3d9.dll
                                              per-function shares through llvm-symbolizer

Only complete sampler windows inside the phase are used. Stack unwinding under Rosetta is
unreliable for frameless leaves (a return address can be a stack address); treat callers as leads.
"""
import argparse
import collections
import importlib.util
import json
import subprocess
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('guest_scene_report', Path(__file__).with_name('guest-scene-report.py'))
scene = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scene)
capture = scene.capture
SYMBOLIZER = '/opt/homebrew/opt/llvm/bin/llvm-symbolizer'


def phase_profile(run: Path, phase: str | None):
    session = Path(json.loads((run / 'active.json').read_text())['session'])
    markers = [json.loads(line) for line in (session / 'perfscene-markers.jsonl').read_text().splitlines()]
    starts = {m['phase']: m['epoch'] for m in markers if m['label'] == 'stress phase start'}
    ends = {m['phase']: m['epoch'] for m in markers if m['label'] == 'stress phase end'}
    phase = phase or next(iter(starts))
    pid = json.loads((session / 'menu-run.json').read_text())['game_pid']
    path = capture.x87_profile_path(session, 'sample', pid)
    records = capture.read_x87_windows(path.with_name(path.name + '.windows'))
    epoch = capture.x87_profile_start_epoch(records[0])
    windows = scene.complete_windows(records, epoch, starts[phase], ends[phase])
    merged = capture.merge_x87_records(windows)
    return phase, len(windows), merged, capture.x87_locator(merged)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('run', type=Path)
    parser.add_argument('--phase')
    parser.add_argument('--module')
    parser.add_argument('--bucket', type=lambda s: int(s, 0), default=0x100)
    parser.add_argument('--lo', type=lambda s: int(s, 0), default=0)
    parser.add_argument('--hi', type=lambda s: int(s, 0), default=1 << 32)
    parser.add_argument('--callers', type=int, default=0, help='frames above the leaf')
    parser.add_argument('--dll', type=Path, help='module image for --pdb symbolization')
    parser.add_argument('--pdb', type=Path)
    parser.add_argument('--top', type=int, default=25)
    options = parser.parse_args()
    phase, count, merged, locate = phase_profile(options.run.resolve(), options.phase)
    total = sum(row['count'] for row in merged['leaves']) + sum(row['count'] for row in merged['host_leaves'])
    print(f'phase {phase}: {count} complete windows, {total} samples')
    if not options.module:
        modules = collections.Counter()
        for row in merged['leaves']:
            modules[locate(row['pc']).get('module', '?')] += row['count']
        for name, n in modules.most_common(options.top):
            print(f'  {name:32s} {n / total * 100:6.2f}%')
        syscalls = collections.Counter()
        for row in merged['host_syscalls']:
            syscalls[row['svc']] += row['count']
        for svc, n in syscalls.most_common(4):
            name = capture.HOST_SYSCALL_NAMES.get(svc, f'syscall {svc}')
            print(f'  [host wait/syscall] {name:25s} {n / total * 100:6.2f}%')
        return
    if options.callers:
        callers = collections.Counter()
        inside = 0
        for stack in merged['stacks']:
            pcs = stack['pcs']
            leaf = locate(pcs[-1])
            offset = int(leaf.get('offset', '0x0'), 16)
            if leaf.get('module') != options.module or not options.lo <= offset < options.hi:
                continue
            inside += stack['count']
            if len(pcs) <= options.callers:
                callers['(no caller)'] += stack['count']
                continue
            frame = locate(pcs[-1 - options.callers])
            key = (f"{frame['module']}+{int(frame['offset'], 16) // options.bucket * options.bucket:#x}"
                   if frame.get('module') else hex(pcs[-1 - options.callers]))
            callers[key] += stack['count']
        stack_total = sum(s['count'] for s in merged['stacks'])
        print(f'  {inside / stack_total * 100:.2f}% of stacked samples end in the range')
        for key, n in callers.most_common(options.top):
            print(f'  {key:40s} {n / stack_total * 100:6.2f}%')
        return
    offsets = collections.Counter()
    for row in merged['leaves']:
        where = locate(row['pc'])
        if where.get('module') == options.module:
            offsets[int(where['offset'], 16)] += row['count']
    module_total = sum(offsets.values())
    print(f'  {options.module}: {module_total / total * 100:.2f}% of samples')
    if options.pdb:
        names = subprocess.run([SYMBOLIZER, f'--obj={options.dll}', f'--pdb={options.pdb}',
                                '--relative-address', '--no-inlines'],
                               input='\n'.join(hex(o) for o in offsets), capture_output=True,
                               text=True, check=True).stdout.split('\n\n')
        functions = collections.Counter()
        for (offset, n), block in zip(offsets.items(), names):
            functions[block.strip().split('\n')[0]] += n
        for name, n in functions.most_common(options.top):
            print(f'  {n / module_total * 100:6.2f}%  {name[:110]}')
        return
    buckets = collections.Counter()
    for offset, n in offsets.items():
        buckets[offset // options.bucket * options.bucket] += n
    for offset, n in buckets.most_common(options.top):
        print(f'  {offset:#010x} {n / total * 100:6.2f}% of all  {n / module_total * 100:6.2f}% of module')


if __name__ == '__main__':
    main()
