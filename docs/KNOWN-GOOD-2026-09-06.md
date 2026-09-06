# Known-good play-test baseline, September 6, 2026

Preserve this baseline before deploying further performance experiments. The user
explicitly selected the currently installed app and configuration as known good.
This records successful real-world play testing, not a controlled benchmark or a
claim of stable 120 FPS everywhere.

## User observations

- 100+ FPS is common.
- 120+ FPS occurs in low-demand scenes.
- FPS rarely falls below 50, including crowded cities.
- These observations are at 4K background resolution, verified as 4096 x 4096.
- The user described the current experience as excellent.

No benchmark, profiling capture, setting change, or game restart was performed to
record this baseline. Session PID 28868 remained untouched.

## Verified identity and saved settings

- Installed app: `/Applications/FFXI-on-Mac.app`, version **3.8, build 24**.
- Renderer: mtld3d, production build from base `ea1b1ca3e584917a460c79aac8916d8084099fb4`
  plus the recorded source patch. The five renderer artifacts and source patch match
  the app manifest. The game bootloader's D3D8 and D3D9 hashes match the app copies.
- The running session's log confirms `render.mergePasses=true`, `render.submitDraws=0`,
  `render.scale=1`, `present.maxFps=0`, and `color.hdr.enable=false`.
- The same log confirms NX flags `0x2 -> 0x9` and reuse of 399 shader variants with
  150 unique prewarmed libraries.
- Background: **4096 x 4096**. Window and menu: **1920 x 1080** in the saved profile.
- Saved preferences: mtld3d, msync on, esync off, Wine debug silenced, Metal HUD off,
  App Nap disabled, large-address-aware enabled, unsafe no-wait readback off.
- Experimental fused readback and alternating-mode builds are not installed. No
  frame-generation implementation is installed.

The [sanitized baseline manifest](benchmarks/2026-09-06-known-good-build24.json)
contains hashes for all 29 app files, the renderer build manifest, all numeric game
registry settings, safe performance preferences, boot-script/cache hashes, addon
load names and plugin DLL hashes. Extra environment values and full launch files
are retained only in the private local snapshot.

## Comparison limits

The user reports above are not independently measured percentiles. Do not rewrite
our 15-20 FPS synthetic crowd results as the user's typical play experience, or
claim this baseline guarantees 120 FPS in every scene.

The saved boot script requests world/entity draw distance **10**; the synthetic
crowd suite requests **20**. It also contains `/fps 1` and `/fastcs fps uncapped`.
Those saved commands do not establish the current session's effective values,
which can be changed in-game. We did not inject commands to inspect or alter them.
The differing workload and settings need reconciliation before using the stress
suite alone to accept or reject a future release.

Future comparisons should identify the actual user-facing regression or improvement,
preserve full addons, verify matching effective settings, and retain screenshots
and frame-time evidence. Keep the installed baseline until a candidate is proven.

## Local rollback copy

Private snapshot outside Git:

`ximac/benchmarks/known-good-20260906-build24/`

It contains `FFXI-on-Mac.app`, `baseline.json`, private performance preferences,
the saved Horizon boot profile, default boot script and on-disk shader cache.
All 29 copied app files were verified byte-for-byte. Launch files and cache were
hashed before and after copying to detect concurrent changes. The snapshot directory
is private. No live process state, full game assets, or complete addon configuration
tree was copied; this is an app/launch-settings rollback copy, not a whole-machine image.

Only restore while the game and launcher are closed, and only when authorized.
Validate hashes against the manifest, then restore through the established app and
configuration rollback workflow. Do not restore private settings over later user
changes without reviewing the differences.
