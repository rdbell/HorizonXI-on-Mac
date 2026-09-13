#!/usr/bin/env python3
"""Build the native-host Wine display driver in a new isolated directory.

python3 scripts/build-wine-native-host.py BUILD --patch SOURCE.patch \
    --original ORIGINAL/winemac.so --original-sha256 SHA256
python3 scripts/build-wine-native-host.py --verify PACKAGE

Uses the pinned Wine source/toolchain from build-wine-locale-fix.py. No Wine
process is launched and no installed runtime or app is changed. Each subprocess
has a wall-clock timeout. Output is BUILD/package; gameplay validation is separate.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil

REPO = Path(__file__).resolve().parent.parent
RUNTIME = 'wine-cx-26.3.0-1'
_spec = importlib.util.spec_from_file_location('wine_locale_builder', REPO / 'scripts/build-wine-locale-fix.py')
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)


def verify(package):
    manifest = json.loads((package / 'build.json').read_text())
    if manifest['runtime'] != RUNTIME or manifest['source_commit'] != base.SOURCE:
        raise ValueError('Native host package does not match the pinned Wine source/runtime')
    for field, name in [('original', 'original/winemac.so'), ('replacement', 'winemac.so'),
                        ('patch_sha256', 'source.patch')]:
        if base.digest(package / name) != manifest[field]:
            raise ValueError(f'Native host checksum mismatch: {name}')
    if not (package / 'COPYING.LIB').is_file():
        raise ValueError('Native host package lacks its Wine license')
    return manifest


def acquire(name, work):
    url, expected = base.DOWNLOADS[name]
    archive = work / (name + '.tar')
    # The downloader itself runs separately, so the timeout bounds the entire
    # transfer rather than only individual socket reads.
    downloader = ('import shutil,sys,urllib.request; '
                  'response=urllib.request.urlopen(sys.argv[1],timeout=30); '
                  'output=open(sys.argv[2],"wb"); shutil.copyfileobj(response,output)')
    base.command(['/usr/bin/python3', '-c', downloader, url, str(archive)],
                 work, work / f'{name}-download.log', 600)
    if base.digest(archive) != expected:
        raise ValueError(f'Checksum mismatch: {archive}')
    destination = work / name
    destination.mkdir()
    base.command(['/usr/bin/tar', '-xf', str(archive), '-C', str(destination), '--strip-components=1'],
                 work, work / f'{name}-extract.log', 120)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build', type=Path, nargs='?')
    parser.add_argument('--patch', type=Path)
    parser.add_argument('--original', type=Path)
    parser.add_argument('--original-sha256')
    parser.add_argument('--verify', type=Path)
    args = parser.parse_args()
    if args.verify:
        verify(args.verify.resolve())
        print('Native host package verified')
        return
    if not all([args.build, args.patch, args.original, args.original_sha256]):
        parser.error('build requires BUILD, --patch, --original and --original-sha256')
    original = args.original.resolve()
    patch = args.patch.resolve()
    if base.digest(original) != args.original_sha256:
        parser.error('original driver does not match the supplied baseline identity')
    if not patch.is_file():
        parser.error('source patch is missing')
    bison = Path('/opt/homebrew/opt/bison/bin/bison')
    if not bison.is_file():
        parser.error('Homebrew bison 3+ is required')
    work = args.build.expanduser().resolve()
    work.mkdir(parents=True, exist_ok=False)
    for name in base.DOWNLOADS:
        acquire(name, work)
    base.command(['/usr/bin/patch', '-p1', '--batch', '--fuzz=0', '-i', str(patch)],
                 work / 'source', work / 'patch.log', 15)
    build = work / 'build'
    build.mkdir()
    packages = ('alsa capi coreaudio cups dbus ffmpeg fontconfig freetype gettext gphoto gnutls '
                'gssapi gstreamer hwloc inotify krb5 netapi opencl opengl oss pcap pcsclite pulse '
                'sane sdl udev usb v4l2 vulkan wayland x').split()
    env = dict(os.environ, PATH='/usr/bin:/bin:' + str(work / 'toolchain/bin') + ':' + os.environ['PATH'])
    configure = [str(work / 'source/configure'), '--enable-archs=i386,x86_64', '--with-mingw',
                 '--host=x86_64-apple-darwin', '--build=x86_64-apple-darwin',
                 'CC=/usr/bin/clang -arch x86_64', 'CROSSCC=/usr/bin/clang -arch x86_64',
                 'BISON=' + str(bison), '--with-unwind'] + ['--without-' + p for p in packages]
    (work / 'configure-command.json').write_text(json.dumps(configure, indent=2) + '\n')
    base.command(configure, build, work / 'configure.log', 600, env)
    base.command(['/usr/bin/make', '-j12', 'dlls/winemac.drv/winemac.so'],
                 build, work / 'build.log', 900, env)
    package = work / 'package'
    (package / 'original').mkdir(parents=True)
    shutil.copy2(original, package / 'original/winemac.so')
    shutil.copy2(build / 'dlls/winemac.drv/winemac.so', package / 'winemac.so')
    shutil.copy2(patch, package / 'source.patch')
    shutil.copy2(work / 'source/COPYING.LIB', package / 'COPYING.LIB')
    base.command(['/usr/bin/codesign', '--force', '-s', '-', str(package / 'winemac.so')],
                 work, work / 'sign.log', 30)
    manifest = dict(runtime=RUNTIME, source_repository='https://github.com/athei/wine',
                    source_commit=base.SOURCE, compiler=base.COMPILER,
                    original=base.digest(package / 'original/winemac.so'),
                    replacement=base.digest(package / 'winemac.so'),
                    patch_sha256=base.digest(package / 'source.patch'))
    (package / 'build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    verify(package)
    print(f'Built {package}; validate the exact driver with local-server gameplay before shipping.')


if __name__ == '__main__':
    main()
