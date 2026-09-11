# Wine locale restoration and BLU spell freezes

Build 27 packages a correction to Wine's UCRT locale selection. It keeps the
existing cx-26.3.0-1 runtime, x87 acceleration, renderer, and launch preparation.
Only the 32-bit and 64-bit `ucrtbase.dll` files change.

## Failure and correction

The original runtime resolves `English_United States.1252` to neutral `en`
(LCID 0x9), even though selecting the system default produces `en-US` (0x409).
MSVCP saves the locale, temporarily selects C, and restores the saved name while
XIAPI initializes. This therefore changes the process's effective locale.

Font rendering subsequently enters locale-sensitive case conversion. For the
neutral locale, Wine's sort lookup queries the registry. Sandbox's registry hook
itself uses locale-sensitive comparisons and reenters that lookup until the
stack overflows. The main Windows thread exits, leaving a frozen window.

The patch excludes neutral enumeration candidates when a locale request includes
an explicit country. Explicit neutral names such as `en`, `fr`, `tr`, and
`sr-Latn` remain supported. It does not force a global C locale or modify XIAPI,
Sandbox, addon settings, or exception handling.

Sandbox's recursive comparison remains a separate weakness if another caller
deliberately selects a neutral locale. This fix corrects the demonstrated Wine
locale-restoration bug; it is not a guarantee against every possible freeze.

## Provenance

- Wine source: `athei/wine` commit `16aac07e6fe9815ffb51efe0e736ba6a3dc97a9c`.
- Verified from the source-checkout step in release build
  [32250417447](https://github.com/athei/wine-build/actions/runs/32250417447),
  which produced `cx-26.3.0-1`.
- Compiler: `llvm-mingw-20260616-ucrt-macos-universal`, matching that release.
- Patch and regression: `patches/wine-ucrt-country-locale.patch`.
- Binary hashes and original hashes: `vendor/wine-locale-fix/build.json`.
- PE DLLs are rebuilt against that source. The existing Unix runtime and other
  CRT DLLs are preserved. Optional Unix-driver dependencies are disabled in the
  focused build because those drivers are not built or deployed.

## Validation on this Mac

2026-09-11, M2 Max, macOS 26.5. All gameplay tests use **Hxitest, character ID 1,
on local Docker LSB**. No Horizon account is used.

| Check | Original runtime | Patched runtime |
| --- | --- | --- |
| Save/default/C/restore probe | Restores neutral en / 0x9 | Preserves en-US / 0x409 |
| UCRT locale regression, 32-bit and 64-bit | 14 failures per architecture | 57 checks per architecture, no failures |
| Existing UCRT string and misc suites, both architectures | No unexpected failures | No unexpected failures; same existing misc todo |
| XIAPI 1.46, diagnostics 2, repeated Cocoon | First cast froze in earlier matched reproduction | Eight successful applications, scenario completed |
| Original installed XIAPI, mixed BLU spells | Not rerun for this sequence | Four each of Cocoon, Metallic Body, and Refueling; all 12 applied successfully |
| Installed build 27 from `/Applications` | Not applicable | One of each of the three spells; all applied, scenario completed |

The original reproduction also froze with XIAPI diagnostics disabled and under
narrow locale relay logging. Its XIAPI-unloaded control completed eight casts.
The patched run loaded the exact same diagnostic XIAPI DLL as the failing runs.
The live module paths/hashes confirm the corrected UCRT and unchanged MSVCP and
mtld3d. Text and the minimap render in the captured local world.
Across the three successful runs, 23 spells applied and frames continued after
each completed scenario. The installed smoke-test screenshot also shows the
original XIAPI v1.45 listening successfully. The installed runtime's complete
file audit differs from the original only in the two intended UCRT DLLs.

The launcher installer passes four checks using its actual production Swift:
installation with preserved originals, a second application with no rewrites,
corrupt-resource rejection, unknown-runtime preservation, and invalid-backup
rejection (installation and idempotence share one case). `swift test` cannot run
on this Command Line Tools-only Mac because XCTest is absent; the focused tests
below do not require XCTest. Native Windows runtime tests have not been run.

Private captures and full build logs remain outside Git under
`ximac/benchmarks/20260911-wine-locale-fix`. Gameplay runs are limited to five or
seven minutes and restore their profiles, DLLs, preferences, and launchd flags.

The guarded `scripts/harness/wine-locale-game-run.py` wraps the existing renderer harness, preserving
the local-account checks, OCR verification, and configuration rollback. The
`scripts/harness/fixtures/wine-locale-blu.patch` fixture uses the tested Cocoon action-packet validation for all
three self buffs, learns/equips them on BLU99 Hxitest, and clears each buff,
restores MP, and resets recasts before casting. Successful casts require the
server's category-4 spell response with message 230, followed by advancing frames
and the completed-scenario marker. `PERFSCENE_ROUNDS` selects one to four rounds.
The relocation check applies this patch to the repository's existing addon and
verifies that every resulting file matches the fixture used in the installed-app
test. The diagnostic XIAPI DLL and private boot profile are supplied locally.
The script checks the known XIAPI hashes before changing anything.

```sh
python3 scripts/harness/wine-locale-game-run.py \
  --output /absolute/new/capture-directory --installed-mtld3d \
  --boot-file /absolute/private/boot-control.txt \
  --draw-distance 10 --menu-sample 0 --scenario effects \
  --env PERFSCENE_LATE_XIAPI=1 --env XIAPI_DIAGNOSTICS=0 \
  --no-network --limit 420 --capture-seconds 400
```

This defaults to the original installed XIAPI. For the known diagnostic build,
add `--diagnostic-xiapi /path/to/xiapi.dll` and select diagnostics mode 2. To test
a staged bundle, add `--candidate-app /path/to/FFXI-on-Mac.app`.

The summarized results are retained in
[`benchmarks/2026-09-11-wine-locale.json`](benchmarks/2026-09-11-wine-locale.json).

## Rebuilding and checking

```sh
python3 scripts/build-wine-locale-fix.py /absolute/new/build-directory
```

The script verifies pinned source/compiler archives, applies the patch, builds
both DLLs and Wine's UCRT test executable, and creates `BUILD/package`. Configure
has a ten-minute bound and compilation a fifteen-minute bound. These are build
limits, not profiling captures. The script does not install its result.

Run the locale, string, and miscellaneous tests on both architectures with:

```sh
python3 scripts/harness/wine-locale-crt-test.py \
  --runtime /absolute/candidate-runtime/wine \
  --build /absolute/new/build-directory/build \
  --output /absolute/new/crt-results
```

This creates an isolated prefix, limits each invocation to 90 seconds, and stops
only that prefix's wineserver afterward. Compare against the original runtime
first. The original runtime should fail the new locale checks. The command exits
nonzero for any failed, missing, or timed-out test.

The installation checks compile directly with Command Line Tools:

```sh
swiftc app/Sources/HorizonXILauncher/WineRuntime.swift \
  app/Sources/HorizonXILauncher/WineLocaleFix.swift \
  scripts/harness/wine-locale-install-test.swift -o /tmp/wine-locale-install-test
/tmp/wine-locale-install-test
```

## Installation and rollback

The app bundles both DLLs. Launch preparation validates their hashes and the
installed originals before replacing either. Runtime installation applies the
same correction before publishing an unpacked runtime. A repeated launch with
the correct hashes performs no writes. Unknown custom DLLs are preserved and
reported, rather than overwritten.

Original DLLs are retained under the versioned runtime's
`locale-fix-v1-originals/ARCH-windows/ucrtbase.dll`. To roll back, close the game,
restore the previous app bundle, and restore those files to
`wine/lib/wine/ARCH-windows/ucrtbase.dll`. Both the app and DLLs must be restored:
build 27 will otherwise reinstall its bundled fix at the next launch.

This Mac also retains the complete original app and runtime at
`~/Library/Application Support/HorizonXI-on-Mac/backups/20260911-1710-wine-locale-build26/`.
