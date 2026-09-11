#!/usr/bin/env python3
"""Build only the corrected UCRT DLLs and their tests from the installed Wine's source.

Usage: python3 scripts/build-wine-locale-fix.py /absolute/new/build-directory
Requires macOS Command Line Tools, Rosetta, Python 3, and Homebrew bison 3+.
Outputs a package in BUILD/package; does not change the app or installed runtime.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import urllib.request

SOURCE = '16aac07e6fe9815ffb51efe0e736ba6a3dc97a9c'
COMPILER = 'llvm-mingw-20260616-ucrt-macos-universal'
DOWNLOADS = {
    'source': (f'https://codeload.github.com/athei/wine/tar.gz/{SOURCE}',
               '99393a2ce22a0b848f71d41c16558d67b59867b1d3eeefe4a04cd8d7e4791bea'),
    'toolchain': (f'https://github.com/mstorsjo/llvm-mingw/releases/download/20260616/{COMPILER}.tar.xz',
                  '2cab02a2e964bd4aae981150a45985d07c657cfa8d244959eb9e2dcc5eedd7b1'),
}
REPO = Path(__file__).resolve().parent.parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(args, cwd, log, timeout, env=None):
    with log.open('w') as output:
        proc = subprocess.Popen(args, cwd=cwd, env=env, stdout=output,
                                stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGTERM)
            try: proc.wait(timeout=10)
            except subprocess.TimeoutExpired: os.killpg(proc.pid, signal.SIGKILL); proc.wait()
            raise RuntimeError(f'Time limit reached; see {log}')
    if code:
        raise RuntimeError(f'Command exited {code}; see {log}')


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    work = Path(sys.argv[1]).expanduser().resolve()
    work.mkdir(parents=True, exist_ok=False)
    bison = Path('/opt/homebrew/opt/bison/bin/bison')
    if not bison.is_file():
        raise SystemExit('Install bison 3+ with Homebrew before building.')
    for name, (url, expected) in DOWNLOADS.items():
        archive = work / (name + '.tar')
        with urllib.request.urlopen(url, timeout=60) as response, archive.open('wb') as output:
            shutil.copyfileobj(response, output)
        if digest(archive) != expected:
            raise SystemExit(f'Checksum mismatch: {archive}')
        destination = work / name
        destination.mkdir()
        command(['/usr/bin/tar', '-xf', str(archive), '-C', str(destination), '--strip-components=1'],
                work, work / f'{name}-extract.log', 120)

    patch = REPO / 'patches/wine-ucrt-country-locale.patch'
    command(['/usr/bin/patch', '-p1', '--batch', '-i', str(patch)],
            work / 'source', work / 'patch.log', 15)
    build = work / 'build'
    build.mkdir()
    # Only PE DLLs are deployed. Unix drivers and their optional dependencies are not built.
    packages = ('alsa capi coreaudio cups dbus ffmpeg fontconfig freetype gettext gphoto gnutls '
                'gssapi gstreamer hwloc inotify krb5 netapi opencl opengl oss pcap pcsclite pulse '
                'sane sdl udev unwind usb v4l2 vulkan wayland x').split()
    env = dict(os.environ, PATH='/usr/bin:/bin:' + str(work / 'toolchain/bin') + ':' + os.environ['PATH'])
    configure = [str(work / 'source/configure'), '--enable-archs=i386,x86_64', '--with-mingw',
                 '--host=x86_64-apple-darwin', '--build=x86_64-apple-darwin',
                 'CC=/usr/bin/clang -arch x86_64', 'CROSSCC=/usr/bin/clang -arch x86_64',
                 'BISON=' + str(bison)] + ['--without-' + p for p in packages]
    (work / 'configure-command.json').write_text(json.dumps(configure, indent=2) + '\n')
    command(configure, build, work / 'configure.log', 600, env)
    targets = [f'dlls/ucrtbase/{arch}-windows/ucrtbase.dll' for arch in ['i386', 'x86_64']]
    command(['/usr/bin/make', '-j12', *targets, 'dlls/ucrtbase/tests/all'],
            build, work / 'build.log', 900, env)

    manifest = json.loads((REPO / 'vendor/wine-locale-fix/build.json').read_text())
    manifest.update(source_commit=SOURCE, compiler=COMPILER, patch_sha256=digest(patch))
    for name in manifest['files']:
        target = work / 'package' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(build / 'dlls/ucrtbase' / name, target)
        command([str(work / 'toolchain/bin/llvm-strip'), '--strip-debug', str(target)],
                work, work / (name.split('/')[0] + '-strip.log'), 15)
        manifest['files'][name] = digest(target)
    (work / 'package/build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    shutil.copy2(patch, work / 'package/source.patch')
    shutil.copy2(work / 'source/COPYING.LIB', work / 'package/COPYING.LIB')
    print(f'Built {work / "package"}; validate with the Wine test executables before packaging.')


if __name__ == '__main__':
    main()
