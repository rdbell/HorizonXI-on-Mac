#!/usr/bin/env python3
"""Run locale/CRT checks in a dedicated prefix, bounded per executable."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--runtime', required=True, type=Path, help='Wine root containing bin/wine')
parser.add_argument('--build', required=True, type=Path, help='configured Wine build directory')
parser.add_argument('--output', required=True, type=Path, help='new directory for results and isolated prefix')
args = parser.parse_args()
wine = args.runtime.expanduser().resolve() / 'bin/wine'
server = wine.with_name('wineserver')
build = args.build.expanduser().resolve()
out = args.output.expanduser().resolve()
out.mkdir(parents=True, exist_ok=False)
prefix = out / 'prefix'
env = dict(os.environ, WINEPREFIX=str(prefix), WINEDEBUG='-all', WINEMSYNC='1',
           WINEDLLOVERRIDES='winemenubuilder.exe=d', WINETEST_DEBUG='1')
results = []
cases = []
for arch in ['i386', 'x86_64']:
    exe = build / f'dlls/ucrtbase/tests/{arch}-windows/ucrtbase_test.exe'
    for test in ['locale', 'string', 'misc']:
        cases.append((f'{arch}-{test}', exe, [test]))
try:
    for name, exe, arguments in cases:
        start = time.monotonic()
        with (out / f'{name}.txt').open('w') as log:
            proc = subprocess.Popen(['/usr/bin/arch', '-x86_64', str(wine), str(exe), *arguments],
                                    env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = proc.wait(timeout=90)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGTERM)
                try: proc.wait(timeout=5)
                except subprocess.TimeoutExpired: os.killpg(proc.pid, signal.SIGKILL); proc.wait()
                code = 'timeout'
        result = dict(test=name, exit=code, seconds=round(time.monotonic()-start, 3))
        results.append(result)
        print(json.dumps(result), flush=True)
        print((out / f'{name}.txt').read_text(errors='replace')[-1200:], flush=True)
        if code == 'timeout': break
finally:
    subprocess.run([str(server), '-k'], env=env, timeout=15, capture_output=True)
    (out / 'results.json').write_text(json.dumps(results, indent=2)+'\n')

raise SystemExit(0 if len(results) == len(cases) and all(row["exit"] == 0 for row in results) else 1)
