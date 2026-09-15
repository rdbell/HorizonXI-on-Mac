#!/usr/bin/env python3
"""Build the small x86 search helper, or verify its complete packaged identity."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'runtime/memory-scan'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(folder):
    manifest = json.loads((folder / 'build.json').read_text())
    if manifest.get('abi') != 1 or set(manifest['files']) != {'ximac-scan.dll', 'scan.lua'}:
        raise ValueError('incomplete memory scanner package')
    for name, expected in manifest['files'].items():
        if digest(folder / name) != expected:
            raise ValueError(f'memory scanner checksum mismatch: {name}')
    return manifest


def build(folder):
    search = '/opt/homebrew/opt/llvm/bin:' + os.environ.get('PATH', '')
    clang = shutil.which('clang', path=search)
    link = shutil.which('lld-link', path=search)
    if not clang or not link:
        raise RuntimeError('LLVM clang and lld-link are required to build the memory scanner')
    folder.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ximac-memory-scan-') as directory:
        stage = Path(directory)
        commands = [
            [clang, '--target=i686-pc-windows-msvc', '-O3', '-msse2', '-fms-extensions',
             '-ffreestanding', '-fno-stack-protector', '-Wall', '-Wextra', '-Werror',
             '-c', str(SOURCE / 'scan.c'), '-o', 'scan.obj'],
            [link, '/lib', '/machine:x86', '/out:msvcrt.lib', '/def:' + str(SOURCE / 'msvcrt.def')],
            [link, '/dll', '/noentry', '/machine:x86', '/timestamp:0', '/nodefaultlib',
             '/out:ximac-scan.dll', 'scan.obj', 'msvcrt.lib'],
        ]
        for command in commands:
            subprocess.run(command, cwd=stage, check=True, timeout=60)
        shutil.copy2(stage / 'ximac-scan.dll', folder / 'ximac-scan.dll')
        shutil.copy2(SOURCE / 'scan.lua', folder / 'scan.lua')
    manifest = {
        'abi': 1, 'target': 'i686-pc-windows-msvc',
        'compiler': subprocess.check_output([clang, '--version'], text=True, timeout=10).splitlines()[0],
        'source_files': {name: digest(SOURCE / name) for name in ('scan.c', 'scan.lua', 'msvcrt.def')},
        'files': {name: digest(folder / name) for name in ('ximac-scan.dll', 'scan.lua')},
    }
    (folder / 'build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    verify(folder)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'vendor/memory-scan')
    parser.add_argument('--verify', type=Path)
    options = parser.parse_args()
    if options.verify:
        verify(options.verify)
    else:
        build(options.output)
