#!/usr/bin/env python3
"""Use the guarded local harness; restore XIAPI and runtime DLLs after each run."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import subprocess
import tempfile

root = Path(__file__).resolve().parent
repo = root.parent.parent
parser = argparse.ArgumentParser(add_help=False)
parser.add_argument('--diagnostic-xiapi', type=Path,
                    help='optional external XIAPI 1.46 diagnostic DLL; otherwise preserve installed XIAPI')
parser.add_argument('--candidate-app', type=Path,
                    help='optional candidate app; defaults to /Applications/FFXI-on-Mac.app')
options, forwarded = parser.parse_known_args()
sys.argv = [sys.argv[0], *forwarded]
source = root / 'renderer-run.py'
spec = importlib.util.spec_from_file_location('renderer_run', source)
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
if r.menu.matching(r.menu.RELATED_SUFFIXES):
    raise SystemExit('Close existing game/Wine/launcher before this local test')
if options.candidate_app:
    r.menu.APP = options.candidate_app.expanduser().resolve()
# Copy the existing addon and apply only the tested BLU scenario changes.
fixture = tempfile.TemporaryDirectory(prefix='wine-locale-blu-')
addon = Path(fixture.name) / 'perfscene'
shutil.copytree(root / 'addons/perfscene', addon)
subprocess.run(['/usr/bin/patch', '-p1', '--batch', '-i',
                str(root / 'fixtures/wine-locale-blu.patch')], cwd=addon, check=True, timeout=15)
r.menu.ADDON_SOURCE = addon
r.menu.OVERRIDE_PREFIXES += ('XIAPI_DIAGNOSTICS',)
plugin = r.menu.DEFAULT_GAME / 'plugins/xiapi.dll'
original_plugin = plugin.read_bytes()
if hashlib.sha256(original_plugin).hexdigest() != 'e7396a9a9548ad5144e87f4d88a95ccba148e1bfc472ff6154635a87a79a8f42':
    raise SystemExit('Original XIAPI has changed; preserve and inspect before testing')
manifest = json.loads((repo/'vendor/wine-locale-fix/build.json').read_text())
runtime = r.menu.RUNTIMES / manifest['runtime']
original_runtime = {}
for name in manifest['files']:
    target = runtime / 'wine/lib/wine' / name
    data = target.read_bytes()
    if hashlib.sha256(data).hexdigest() not in (manifest['originals'][name], manifest['files'][name]):
        raise SystemExit('Unrecognized installed runtime: '+str(target))
    original_runtime[target] = data

base_snapshot = r.Snapshot
class CaptureSnapshot(base_snapshot):
    def restore(self):
        trace = r.menu.DEFAULT_GAME / 'config/xiapi/flight.bin'
        if trace.exists(): shutil.copy2(trace, self.output / 'flight.bin')
        (self.output/'runtime-at-cleanup.json').write_text(json.dumps({
            str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in original_runtime
        }, indent=2)+'\n')
        super().restore()
r.Snapshot = CaptureSnapshot
if options.diagnostic_xiapi:
    diagnostic = options.diagnostic_xiapi.read_bytes()
    if hashlib.sha256(diagnostic).hexdigest() != '44ae0c4b8b0ca316dbe2ebf7fda4aee7aa0da966d09a069d0f5f585b2ff8ebf3':
        raise SystemExit('Diagnostic XIAPI mismatch')
    plugin.write_bytes(diagnostic)
try:
    result = r.main()
finally:
    if r.menu.matching(r.menu.RELATED_SUFFIXES):
        print('Processes remain; retain evidence and restore only after owned cleanup', flush=True)
    else:
        plugin.write_bytes(original_plugin)
        for target, data in original_runtime.items():
            temp = target.with_name(target.name+'.locale-test-restore')
            temp.write_bytes(data)
            temp.replace(target)
        print('Restored original XIAPI and pre-test runtime DLLs', flush=True)
fixture.cleanup()
raise SystemExit(result)
