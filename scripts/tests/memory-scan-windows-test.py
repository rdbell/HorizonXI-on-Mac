#!/usr/bin/env python3
"""Run scanner differential and fault tests in a dedicated Wine prefix.

Requires a built vendor/memory-scan package, LLVM, and xwin's kernel32 import library.
The selected output directory owns the test prefix; no game prefix is accepted.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wine-sdk', type=Path, required=True)
    parser.add_argument('--xwin', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    search = '/opt/homebrew/opt/llvm/bin:' + os.environ.get('PATH', '')
    clang, link = (shutil.which(name, path=search) for name in ('clang', 'lld-link'))
    if not clang or not link:
        raise RuntimeError('LLVM clang and lld-link are required')
    subprocess.run(['python3', str(ROOT / 'scripts/build-memory-scan.py'), '--verify',
                    str(ROOT / 'vendor/memory-scan')], check=True, timeout=15)
    definition = output / 'scanner.def'
    definition.write_text('LIBRARY ximac-scan.dll\nEXPORTS\n ximac_scan\n')
    commands = [
        [clang, '--target=i686-pc-windows-msvc', '-O2', '-ffreestanding', '-fno-stack-protector',
         '-c', str(Path(__file__).with_name('memory-scan-win-test.c')), '-o', 'test.obj'],
        [link, '/lib', '/machine:x86', '/def:scanner.def', '/out:scanner.lib'],
        [link, '/entry:mainCRTStartup', '/subsystem:console', '/machine:x86', '/out:test.exe',
         'test.obj', 'scanner.lib', str(args.xwin.resolve() / 'sdk/lib/um/x86/kernel32.lib')],
    ]
    for command in commands:
        subprocess.run(command, cwd=output, check=True, timeout=30)
    dll = output / 'ximac-scan.dll'
    shutil.copy2(ROOT / 'vendor/memory-scan/ximac-scan.dll', dll)
    sdk = args.wine_sdk.resolve()
    env = os.environ.copy()
    env.update(WINEPREFIX=str(output / 'prefix'), WINEDEBUG='-all')
    try:
        result = subprocess.run([str(sdk / 'bin/wine'), str(output / 'test.exe')],
                                cwd=output, env=env, capture_output=True, text=True, timeout=60)
        (output / 'runtime.log').write_text(result.stdout + result.stderr)
        passed = result.returncode == 0 and 'PASS 36000' in result.stdout
        (output / 'result.json').write_text(json.dumps({
            'passed': passed, 'exit_code': result.returncode,
            'dll_sha256': hashlib.sha256(dll.read_bytes()).hexdigest(),
            'test_source_sha256': hashlib.sha256(Path(__file__).with_name('memory-scan-win-test.c').read_bytes()).hexdigest(),
        }, indent=2) + '\n')
        if not passed:
            raise RuntimeError('scanner runtime validation failed; see runtime.log')
        print(result.stdout.strip())
    finally:
        for flag in ('-k', '-w'):
            cleanup = subprocess.run([str(sdk / 'bin/wineserver'), flag], env=env, timeout=10,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            # -k returns 1 when the isolated server has already exited. -w must succeed.
            if cleanup.returncode not in ((0, 1) if flag == '-k' else (0,)):
                raise RuntimeError(f'isolated Wine cleanup failed: {cleanup.stderr.strip()}')


if __name__ == '__main__':
    main()
