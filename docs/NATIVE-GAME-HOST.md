# Native game window packaging

The launcher exposes an opt-in Native game window setting for mtld3d. It installs
a matching Wine display driver before launch and passes `present.nativeHost=true`
to the renderer. Turning the setting off restores the original Wine driver.
Settings apply on the next launch. This document covers packaging and recovery;
renderer lifecycle and gameplay acceptance are documented in mtld3d's
`docs/NATIVE-HOST.md`.

The package lives at `vendor/wine-native-host` and contains:

- `winemac.so`, the candidate Intel Wine display driver.
- `original/winemac.so`, the exact original driver from the pinned runtime.
- `source.patch` and `COPYING.LIB`.
- `build.json`, with runtime, source commit, original/replacement SHA-256 hashes,
  and the source patch SHA-256 hash.

Enabling verifies both binaries before any write, including when the candidate
is already installed. Unknown runtime driver hashes are preserved. A bounded ownership-intent file beside
`winemac.so` records the verified original identity and previous/intended candidate
hashes before replacement. Later app versions can recover either side of an
interrupted update and restore candidates installed by earlier versions. Unknown
custom files and malformed or mismatched records are never adopted. Disabling
requires a verified original but permits a damaged candidate package, so that
candidate damage does not block recovery. Atomic replacement preserves images
already mapped by running processes. This does not authorize changing a user's
active game or starting a second launch against its prefix.

The app resolves this package only from its own resources. Development tests
must pass an explicit package URL; missing bundled files cannot silently fall
back to the checkout used to compile the launcher.

## Rebuild

The package is built for `cx-26.3.0-6` from athei/wine `d82e36650b0`. That tree's makedep
rejects any include ahead of `config.h`, so `source.patch` imports `<objc/runtime.h>` after it;
the patch is otherwise unchanged from the `cx-26.3.0-1` build. See `WINE-CX6.md`.

Use macOS Command Line Tools, Rosetta and Homebrew bison 3+. The builder downloads
and verifies the source/toolchain pinned by `build-wine-locale-fix.py`, applies
the supplied patch without fuzz, and builds only the macOS display driver and
its required build dependencies. It does not run Wine or edit an installed app.

```sh
python3 scripts/build-wine-native-host.py /absolute/new/build-directory \
  --patch /absolute/reviewed/wine-native-host.patch \
  --original /absolute/baseline/winemac.so \
  --original-sha256 BASELINE_SHA256
python3 scripts/build-wine-native-host.py --verify /absolute/new/build-directory/package
```

Supply the original from the preserved pinned Wine runtime, not from a runtime
that has already received the native-host candidate. Download steps are limited
to 600 seconds each, extraction to 120, patching to 15, configure to 600, build to
900 and signing to 30. A timeout terminates the owned subprocess group.

After validating the exact build, copy the complete package to
`vendor/wine-native-host`. `app/bundle.sh` verifies the package before copying,
signs its candidate, records the new signed hash, verifies again, and seals the
app. It preserves the original rollback bytes. Source and compiler pinning
support reproducible investigation; identical hashes across SDK/compiler hosts
are not promised.

## Validation and release limits

The portable installer tests exercise idempotence, unknown runtime preservation,
damaged candidate and rollback files, recovery with a damaged candidate, absent
resources and a mismatched runtime manifest:

```sh
swiftc app/Sources/HorizonXILauncher/WineRuntime.swift \
  app/Sources/HorizonXILauncher/WineLocaleFix.swift \
  app/Sources/HorizonXILauncher/WineNativeHost.swift \
  scripts/tests/wine-native-host-test.swift -o /tmp/native-host-installer-tests
/tmp/native-host-installer-tests
python3 scripts/tests/wine-native-host-package-test.py
```

These checks do not establish input correctness, fullscreen transitions,
performance, or game compatibility. Those require the bounded renderer probe and
Hxitest on local Docker LSB with the final packaged artifacts.

Ad-hoc local packaging preserves the exact baseline rollback driver. Developer
ID notarization has not been validated with this package: re-signing the original
nested Mach-O would change its rollback identity. Do not claim notarization
readiness from the candidate signing checks alone.

## Preserving the installed performance baseline

The launcher vendors both sidecars from `rdbell/x87sidecar` commit
`7b4db46cc1ec3878192c82981e5948955bbd7e4b`. They match the preserved installed app
and final optimized 2026-09-12 x87-boundary benchmark binaries exactly. The
cumulative upstream patch and both hashes are recorded in
`vendor/x87sidecar-build.json`. This retains the native-state conversion
optimization and excludes the unsafe conversion-disabled experiment.

Ad-hoc packaging verifies and preserves both sidecar signatures. Developer ID
packaging records re-signed hashes alongside the tested vendor hashes, retaining
the baseline entitlement set. The entitled fallback carries get-task-allow;
notarization has not been validated. Native hosting introduces no changes to the
locale DLLs, audio helper, converter, existing fallback renderer, icons or
launch/repair scripts compared with the preserved installed baseline.


## Local acceptance, 2026-09-12

The production candidate passed the 18-stage native-window probe and local
Docker LSB gameplay with Hxitest. The game runs verified the effective toggle,
loaded renderer and Wine driver hashes, actual host attachment, and full
restoration of the 46 saved file states and launcher preferences. Native runs
also moved the game between the scale-1 TV and scale-2 Retina display after
measurement. The installed application was preserved during validation. After
acceptance the candidate was installed, with the previous app retained for
rollback. User preferences were preserved; the feature defaults off.

Three consecutive 4096-by-4096 background-resolution city runs used the same
production renderer, shader-cache input, game/menu geometry, fixed noon and
camera, uncapped FPS, and draw distances. Hosting disabled also restores the
original released Wine driver. Measurements exclude zoning, screenshots and
resize activity by selecting complete one-second samples starting two seconds
after each settled marker and ending before the next zone/done marker.

| Run order | Native host | Bastok Markets FPS | Bastok Mines FPS |
| --- | --- | ---: | ---: |
| 1 | On | 38.23 | 90.42 |
| 2 | Off | 40.59 | 97.79 |
| 3 | On | 41.42 | 100.40 |

The first on/off pair suggested a 6-8% penalty, which the unchanged native build
did not reproduce on the repeat. This is evidence of run variation and no
consistent penalty in these bounded samples. It is not a performance or latency
improvement claim. There were 36-37 complete samples per scene. Median per-sample
p95 frame times followed the same pattern; those are not aggregate frame p95s.
No additional profiling capture ran during these measurements.

Two adversarial reviewers' findings were addressed and the final source review
found no remaining concrete blocker. They reviewed lifecycle, focus, minimize
cancellation, device-reset rejection, ABI compatibility, package integrity and
upgrade/rollback ownership. The renderer document records the 2,155 passing
repository tests, subsequent 42 Reset tests, and the five unrelated audit findings.
The upstream device conformance comparison remains incomplete because both the
preserved baseline and candidate reached the 60-second bound. Long-session
compatibility and Developer ID notarization remain unvalidated.

This candidate is suitable for opt-in local play testing. It supplies native
window ownership and a live frame-limit panel; further graphical effects need
separate implementation and validation.

## Display changes, 2026-09-28

A monitor powering off and on left the game drawn into part of the native window (white area
beside a smaller picture) until the window was dragged. mtld3d 5aeb468 makes Wine re-read the
window's frame after a display change when the game view no longer fills the window, the same
thing a drag does. Confirmed by the user with a monitor power cycle; see mtld3d
`docs/NATIVE-HOST.md`.
