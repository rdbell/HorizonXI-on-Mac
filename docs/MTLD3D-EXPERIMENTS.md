# mtld3d performance experiments

The September 5 investigation uses mtld3d v0.8.0, commit
`ea1b1ca3e584917a460c79aac8916d8084099fb4`, with crosire's D3D8-to-D3D9 converter.
Tests run on an Apple M2 Max with macOS 26.5. Game experiments use only the local
LandSandBoat server and its test character. Each game run is limited to 420 seconds;
Wine conformance subtests are limited to 180 seconds.

## Characters rendered black because omitted vertex colors became zero

An F12 dump showed that the character's vertex declaration contains positions, normals,
and texture coordinates, but omits COLOR0 and COLOR1. Lighting and COLORVERTEX are enabled.
The selected diffuse and ambient sources are COLOR1, and the specular source is COLOR2.
The material itself is valid, with diffuse components of 0.5 and ambient components of 1.0.

mtld3d's fixed-function shader emitter selected zero for a requested color omitted from an
explicit declaration. D3D9 uses the corresponding material constant in this case. A color
that is declared on an unbound stream is a separate case and still reads zero.

This distinction agrees with [DXVK's material-source masking](https://github.com/doitsujin/dxvk/blob/v1.10.3/src/d3d9/d3d9_device.cpp#L6590).
Wine's `test_color_vertex` declares COLOR elements on unbound streams. Its expected zero
values do not describe declarations that omit those elements. The material-zero state-block
issue in [Mesa issue 320](https://github.com/iXit/Mesa-3D/issues/320) was a useful lead, but
the captured mtld3d materials are nonzero and identify a different mechanism.

`patches/mtld3d-0.8.0-material-fallback.patch` removes the incorrect declaration-origin
distinction from the layout, shader key, and material resolver. Shader-cache schema 68
invalidates previously emitted shaders. Two pixel regressions exercise both color selectors
and all four material components, covering omitted and declared-but-unbound colors.

Before the fix, the omitted-color test rendered transparent black where it expected opaque
red. The unbound-stream control passed. Both tests pass after the fix.

`patches/mtld3d-0.8.0-ff-diagnostics.patch` independently extends the existing three-frame F12
dump with fixed-function keys, material colors, FVF, and stream-0 stride. It adds no work
unless a frame dump is active.

## Building and checking

Apply either patch to the pinned source checkout. Follow mtld3d's build instructions with
Rust 1.97.1 and an isolated Wine SDK. `make install` must target the isolated SDK, since it
replaces the renderer inside that Wine tree. Also apply the unaligned-lock patch below when
using a build with debug assertions enabled.

```sh
git checkout ea1b1ca3e584917a460c79aac8916d8084099fb4
git apply /path/to/mtld3d-0.8.0-material-fallback.patch
git apply /path/to/mtld3d-0.8.0-ff-diagnostics.patch
make RUST_STABLE=1.97.1 WINE_SDK=/path/to/isolated/wine check test
make RUST_STABLE=1.97.1 WINE_SDK=/path/to/isolated/wine conformance
make RUST_STABLE=1.97.1 WINE_SDK=/path/to/isolated/wine PROD=1 bundle
```

Use a private `WINEPREFIX` as well. If a prefix predates installation of either PE
architecture, update it with `wineboot -u` or install the bundle's matching prefix markers.
Otherwise the 64-bit test leg can fail before running with `Library mtld3d.dll not found`.

Validation so far:

- `make check` passed, including formatting, clippy, audit, and documentation.
- `make test` passed 1,035 core tests, 202 shared tests, and 442 rendering tests on each
  architecture. Per-test output was checked, including both new tests on both architectures.
- Full conformance ran on both architectures with the installed runtime's isolated SDK.
  It hit a 180-second device-test timeout and 13 visual sites beyond the repository baseline.
  Stateblock and D3D9Ex results matched the baseline.
- The CI-pinned `cx-26.3.0-2` SDK on a fresh prefix gave the same i686 result. Its release
  archive SHA-256 is `5348938761dfe7912289ef55950e2795bcda2f37dfb557e723211cb27d7099d6`.
- An unmodified v0.8.0 release, installed into that private SDK and verified by DLL hashes,
  produced the identical 234 visual failures at identical sites. The patched build adds no
  visual-conformance failures on this machine. The device-test timeout remains unresolved;
  the upstream baseline has not been rewritten to hide it.

The corrected production build also renders Hxitest's skin, clothing, textures, and lighting
at character selection and in-world on the local LSB server. The first town capture measured
123.75 FPS in Markets and 110.49 FPS in Mines at the existing 4096 x 4096 background setting.
Those are preliminary results: the client-only heading setter did not persist, so the
camera must be fixed before comparing renderers. Neither scene established stable 120 FPS.

The patch remains experimental. The identical visual-conformance failures establish that
this fix did not introduce those failures; they do not establish complete D3D9 conformance.

## First comparison with fixed camera positions

Server-authoritative `setPos` rotation followed by the Home camera reset now preserves the
same headings in both renderers. Screenshots match the Markets bridge view and the Mines
entrance tunnel. The tunnel is a light scene, not a substitute for the open part of town.

These short samples use the same minimal addon boot script, crosire converter, 1024 x 742
window and UI, and `/fps 0`. Each contains 17 complete one-second frame-counter windows
after loading settles. Other saved quality settings are unchanged; this is not a max-quality
profile. All runs verified the loaded renderer hashes and restored the saved installation.

| Renderer | Background | Markets FPS | Mines tunnel FPS | Mines minimum one-second FPS |
| --- | --- | ---: | ---: | ---: |
| DXVK 1.10.3, existing patched build | 4096 x 4096 | 32.330 | 66.025 | 58.652 |
| mtld3d, material fix | 4096 x 4096 | 40.003 | 126.236 | 103.727 |
| mtld3d, material fix | 2048 x 2048 | 43.484 | 141.479 | 105.750 |

The matched 4096 runs favor mtld3d by 23.7 percent in Markets and 91.2 percent in the tunnel.
These are single runs and need repeats. The 2048 result is a resolution-sensitivity probe;
its modest Markets gain suggests CPU work remains a better lead than reducing pixel count.
No sample establishes stable 120 FPS. Even the faster 2048 tunnel run spent 5.87 percent of
measured time below 120 FPS.
These early comparisons also predate the client-clock validation described below.

## Packed buffer-lock outputs aborted the debug renderer

FFXI supplies a pointer output slot aligned to two bytes when calling vertex-buffer `Lock`.
mtld3d assigned through that pointer directly, which requires four-byte alignment on i686.
Its debug build aborted at `vertex_buffer.rs:812`. Index-buffer `Lock` had the same defect,
including the error paths that write a null output.

`patches/mtld3d-0.8.0-unaligned-lock.patch` makes the existing `OutPtr` wrapper write unaligned
storage and uses it in both buffer Lock methods. The wrapper creates no reference to the
output, so its constructor can accept unaligned storage without weakening any downstream
reference invariant. Existing aligned callers retain their behavior. No shader or wire layout
changes are involved.

Both new i686 rendering-suite probes aborted before the fix with the observed alignment
panic. After the fix they pass on both architectures, including successful locks,
invalid-range null outputs, and untouched neighboring bytes. A shared-unit regression checks
the same byte-storage boundary. `make check` and all 2,126 tests pass. Full conformance ran
on both architectures; completed subtests have identical failure sites and counts to the
material-only build, and each device subtest retains the existing 180-second timeout.

Apply this patch after the material patch so its coverage-document context matches. The
source changes themselves address output alignment independently of the material correction.

## Markets readback stalls

A bounded in-world capture found one readback per application frame. FFXI draws a 16 x 16
texture from its 4096 x 4096 scene texture, copies it to a lockable surface with StretchRect,
then locks it. The captured frame contains 3,317 draws. The tiny readback waits for all the
rendering ahead of it.

`patches/mtld3d-0.8.0-readback-timing.patch` adds an opt-in `mtld3d::readback=trace` target.
It separates the API's command flush from the readback call, and the native blit's encoding
from its commit/completion wait. It changes no synchronization. In one Markets diagnostic
run, the medians were 8.27 ms for the command flush and 8.48 ms for the readback. Encoding
the blit took 0.14 ms; its commit/completion wait took 8.21 ms. These are diagnostic call
timings, not an FPS improvement.

mtld3d's existing performance grid counts internal submissions as frames. In this workload,
374 reported frames contained 187 Surface LockRect calls and about 187 application Presents.
Do not interpret that grid's milliseconds as application frame times without normalizing it.
The renderer-independent `common-fps.csv` remains the FPS measurement.

The corresponding guest sampler captured 99.7 percent of the game's lifetime. In complete
Markets windows, 52.7 percent of samples were in `ulock_wait2` or `psynch_cvwait`. This supports
investigating scheduling around readback. It does not make x87 operation counts a CPU-time
profile. When analyzing captures after renderer restoration, resolve module offsets against
the captured binary, since the same installed DLL path now names the restored renderer.

The longer `town` scenario now places Hxitest near Valeri in Mines at 39, 0, -49 with rotation
128. The earlier 0, 0, -18 placement put the camera inside geometry and is excluded. The
replacement's screenshot shows a clear player and ground, with a large town structure ahead;
it is a fixed vantage, not a representative average of the zone.

## Draw distance and renderer restoration

`renderer-run.py --draw-distance N` sets world and entity distance, then records the effective
client values in each scene marker. Reports reject a scene when either value is absent or
differs from the request. The default remains 20 for continuity with the stress comparisons
above. The minimal boot starts with client defaults of 1.0; the user's normal script uses 10.
Compare renderer changes at the same verified distance. Reducing it is a workload and visual
quality change, not evidence of a faster renderer.

The launcher also replaces `syswow64/d3d8.dll` and `syswow64/d3d9.dll`. Earlier benchmark
snapshots omitted these paths; their 26-file restoration reports did not cover the two system
DLLs. Both were recovered from verified pre-session backups. The runner now snapshots them,
with a regression that overwrites and restores the system D3D9 DLL. It also covers the files
used by the optional D3D11 experiment. The first run with this coverage restored all 43 file
states and preferences, and verified unchanged Docker identities and start times.

## dgVoodoo2 and DXMT loading experiment

The runner accepts `--dxmt-bundle`, `--converter`, and `--dgvoodoo-config` for a bounded
dgVoodoo2-to-D3D11-to-Metal trial. This path is experimental and has no game FPS result yet.
The first attempt with official dgVoodoo2 2.87.4 and DXMT 0.80 stopped at a white game window
and the 100-second rules-screen timeout. It never verified loaded renderer identities or
captured frame counters. Reports now describe absent counters without crashing.

Separate 32-bit and 64-bit D3D11 smoke tests successfully created a feature-level 11.0
hardware device after installing DXMT into a task-owned Wine SDK and prefix. This establishes
device creation on the machine, not compatibility with the game's launcher or bridge.
The game trial uses the documented `dxgi.forceSDR=True` and
`d3d11.preferredMaxFrameRate=0` configuration keys for subsequent attempts.

With valid D3D8 presentation parameters, the isolated dgVoodoo probe reaches the Apple M2 Max
adapter, then crashes in its D3D8 DLL at module offset `0x5e622` during device creation.
DXMT's standalone D3D11 creation still succeeds. This is a reproducible bridge-compatibility
lead; it is not evidence of a game performance ceiling.

## Early submission experiment

`patches/mtld3d-0.8.0-early-submission.patch` adds `render.submitDraws`, disabled at zero.
A nonzero threshold sends a continuation through the existing bounded encoder channel while
the game collects subsequent draws. It preserves color, depth, snapshot lifetimes, and
readback ordering. Small chunks also add render-pass store/load work.

At the existing distance-20, 4096-square settings, short clean captures gave 40.849 FPS
Markets and 106.964 tunnel with a 512-draw threshold, versus 35.602 and 119.667 at zero.
These single captures suggest a scene tradeoff and do not justify enabling the option.
The threshold-1 rendering regression checks depth and changing draw snapshots across forced
continuations. `make check` and all 2,128 tests passed with that threshold; full Wine
conformance has not been repeated for this scheduling experiment.

## Paired Metal submission timings

`patches/mtld3d-0.8.0-gpu-timing.patch` samples adjacent submission sequences every 128
submissions under `mtld3d::gpu_time=trace`. A single even sequence would repeatedly miss one
half of a two-submission application frame. Timing uses the existing Metal completion handler
and is disabled without the trace target.

The verified `mtld3d-gpu-paired-city-01` run reached both expected zones and restored all 43
file states. In the complete Markets interval, 33 samples per half gave these medians:

| Submission | Metal passes | CPU encode and commit | Metal GPU elapsed |
| --- | ---: | ---: | ---: |
| Before readback | 184 | 4.898 ms | 11.005 ms |
| With Present | 104 | 2.936 ms | 5.888 ms |

The tunnel's 98 sampled submissions had 52 passes and a median 3.538 ms GPU elapsed.
The run measured 35.873 FPS Markets and 107.701 tunnel with timing enabled. These diagnostic
results identify pass overhead; they are not an improvement claim. The earlier GPU-stage
run never left Mines, so its interval labelled Markets is invalid.

Apply both experimental patches after the published material, alignment, fixed-function
diagnostic, and readback-timing patches. They each apply to that common base independently.

## Reliable benchmark clock setup

LSB uses `earth_time::now()` for both the Vana'diel clock and session expiry. The earlier
`!addtime 0` / forward `!perftime 12` sequence could expire Hxitest immediately, leaving a
rendering client in the old zone with no server traffic. Those captures are invalid. The
command also remained cached after editing its bind-mounted Lua file.

`perftime` now preserves the existing offset and moves backward to noon. The scenario
refreshes that one command before calling it and records the client's game hour and minute.
It aborts at a settled scene if the zone, draw distance, or noon schedule is wrong. Reports
apply the same checks. Completed scenarios restore the normal server clock after the final
measurement marker; the forward reset can end the test session, so it belongs after timing.

The command passed 216 hour/minute/offset cases and two invalid-hour cases. A bounded live
run confirmed Markets at 12:15 and Mines at 12:50 with continuing server traffic. No Docker
container was restarted. On this machine the single-file Docker bind retained the original
file length after an in-place edit, so the live Lua file was padded to that length and its
complete bytes verified inside the container. Its source in this repository needs no padding.

## Independent render-pass merging

The Markets dump contains 3,317 draws and 231 consecutive draw-target groups. Most alternate
between the scene and an intermediate target. The intermediate never samples the scene,
and only six groups sample the intermediate. This suggested that some passes could share a
Metal encoder without changing the order of dependent draws.

`patches/mtld3d-0.8.0-pass-merge.patch` adds `render.mergePasses`, disabled by default.
Apply it after the material, alignment, fixed-function diagnostic, readback-timing,
early-submission, and GPU-timing patches. The patch was checked by reconstructing the exact
candidate source tree. It includes the new `windows/core/src/passes/merge.rs` module.

The scheduler tracks fragment and vertex texture reads, sRGB aliases, color and depth
attachments, and intervening writes. It preserves draw order within a target and refuses
queries, leading copies, resolves, multiple color targets, attachment feedback, and unknown
commands. Compatible later passes can move across independent passes within a 16-pass
lookback. Implicit blend, depth-bias, and stencil defaults are restored at each former pass
boundary. Load/store rules run after merging.

`make check` passed. All 1,039 core/types tests, 203 shared/native tests, and 446 rendering
tests per architecture passed. The first x86_64 rendering run hit a Rosetta EmulateForward
exception in a resource-refcount test, reached its 60-second timeout, and skipped four
tests. A focused retry passed that case and every skipped case. One initial fixture error
was corrected before the completed run. Full Wine conformance has not been repeated for
this scheduling change.

The immutable production bundle is `mtld3d-pass-merge-production`, with D3D9 SHA-256
`5c50f730f02ef38aee0b6bec847ae559e91d1dfc179de5f9895615f1ae3abdcf`.
Its source archive uses a temporary Git index so newly added source files are included
without modifying the working checkout's index.

The first enabled run, `mtld3d-merge-on-city-01`, measured 43.171 FPS in Markets and
99.720 FPS in the entrance tunnel across complete 56.7- and 57.3-second intervals.
Both screenshots rendered correctly. Effective distance 20, the noon schedule, zones,
loaded renderer hashes, all 43 restored file states/preferences, and unchanged Docker
identities were verified. The final screenshot also confirms that `!addtime 0` restored
normal server time after measurement. No stable 120 FPS result was reached.

The first same-binary disabled control stopped at the main-menu OCR timeout. Its pointer
obscured the highlighted Select Character text, while frame counters kept advancing. The
runner now accepts the corresponding footer together with Create Character and Delete
Character. The character-list and live-counter checks remain required. A regression covers
the exact observed OCR error and rejects incomplete or unrelated menus.

The corrected control, `mtld3d-merge-off-city-02`, completed with the same binary, boot,
graphics, positions, clock schedule, and draw distance. It measured 34.528 FPS Markets and
94.922 FPS tunnel. Both scenes passed screenshot review; restoration and final clock reset
were verified again. The enabled run was 25.0 percent faster in Markets and 5.1 percent in
the tunnel. This is one sequential pair, not a repeated performance guarantee. In the tunnel,
merging's minimum one-second FPS was worse, 79.716 versus 84.055, as was the worst per-window
p99, 49.901 versus 42.412 ms. The option remains disabled pending repeats and wider scenes.

## Launcher play testing, build 22

The app now bundles that production build under `Contents/Resources/mtld3d`. Select
**Metal / mtld3d (experimental)** in Settings to use it. The existing DXVK choice remains
the default for new installations and the fallback for comparison. Changing the renderer
preserves other performance preferences, server selection, account settings and boot scripts.

The mtld3d choice enables `render.mergePasses=true` for play testing. It also sets
`color.hdr.enable=false;render.scale=1;present.maxFps=0;render.submitDraws=0` and locates
the bundled Wine shim through `WINEDLLPATH`. Early submission stays disabled. Normal Play
installs both prefix markers and the D3D8 converter/native D3D9 pair. Missing resources or
copy errors stop the launch with an error. Switch back to Metal / DXVK and relaunch to compare.
Use `/fps 0` in-game to remove the client's separate limiter.

`vendor/mtld3d/build.json` records the tested file hashes and `source.patch` contains the
complete modified source diff. Packaging checks those hashes, signs the Unix library, then
records its signed hash in the app's manifest while preserving `unsigned_unix_sha256`.
Signing changes that library's bytes without rebuilding the renderer.

To verify the installed launch path on Local LSB with Hxitest, close the game and launcher,
select mtld3d first, and run:

```sh
python3 scripts/harness/renderer-run.py --installed-mtld3d \
  --output /tmp/mtld3d-installed-validation \
  --limit 200 --capture-seconds 180 --menu-sample 2 --hold 3
```

This mode rejects renderer-resource replacements and renderer environment overrides. It
checks the launcher's own configuration, advancing frame counters, the local character
screen, and hashes of the loaded D3D9, shim and Unix library. It restores temporary files
and account preferences, including the saved renderer, and checks that Docker was unchanged.
The output directory contains private rollback files and must stay outside Git.

Installed build 22 passed this check in capture `20260905-105726-standard-nosample`.
The local Hxitest character rendered correctly, frame counters advanced, and the loaded
D3D8 converter, native D3D9, Wine shim and signed Unix library matched the packaged hashes.
The launcher supplied the configuration above without a renderer override. Cleanup restored
all 43 saved file states and the original preferences except the requested mtld3d selection;
Docker was unchanged and no game or Wine processes remained. This was an installation check
through character selection, not another in-world performance measurement. The recorder's
generic DXVK-probe warning is expected for mtld3d; this mode checks the shared FPS counter
and loaded renderer identities instead.

Focused installation tests run with Command Line Tools:

```sh
swiftc app/Sources/HorizonXILauncher/{Renderer,Settings,Install,Servers}.swift \
  scripts/tests/renderer-test.swift -o /tmp/renderer-test
/tmp/renderer-test
python3 scripts/tests/renderer-run-test.py
```
The numerical reports are preserved in
[benchmarks/2026-09-05-pass-merge.json](benchmarks/2026-09-05-pass-merge.json).

The downloaded dgVoodoo 2.79.3 and 2.81.3 archives are retained locally for a future isolated
smoke test. They came from the
[masterotaku preservation mirror](https://github.com/masterotaku/dgVoodoo-binaries), with
URLs and archive hashes recorded. They have not been executed or adopted as a game renderer.

## Stutters when characters appear: repeated compilation of identical shaders

The build 22 play-session log contained 214 prewarmed shaders followed by 290 live
compilations, reporting 6,125 ms of aggregate live compilation. The largest logged burst
was 38 shaders and 736 ms. These are compiler totals across a burst, not measured frame
durations. The encoder performs those live compiles synchronously.

An exact audit of the 504 recorded shaders found only 105 distinct generated sources after
normalizing their generated entry-point names. The 214 warm records represent 59 sources;
only 46 of the 290 subsequent records add a source. The other 244 live records could reuse
compiled code. A preliminary regex audit overcounted unique sources because some generated
hash names were shorter; the Rust replay uses the actual cache implementation.

`patches/mtld3d-0.8.0-shader-dedup.patch` adds a per-device source index alongside the existing
state-key index. Only a new state miss performs the source comparison. It normalizes exactly
one generated entry declaration and otherwise preserves the complete source and entry name.
Full string equality prevents a source-hash collision from sharing different instructions.
Failed compiles remain retryable. One owner holds each library/function pair, including when
the prewarm cache moves to the encoder. Equivalent functions also share pipeline-cache keys.

The change keeps shader-cache schema 68 and existing warmed caches. It writes a disk record
only when compiling new source. A state alias encountered after relaunch can resolve against
the prewarmed source without another Metal compilation. New source still compiles
synchronously; this fix does not eliminate every possible loading or asset-upload stall.

### Recorded Metal compilation replay

Two sequential pairs replayed the same captured sources, first baseline then deduplication,
then in reverse order. Each run used fresh entry-point names to avoid reusing an earlier
driver source-cache result, the renderer's Metal language and math options, and a 150-second
parent timeout. No build, rendering suite, or game ran concurrently. The internal replay
limit is 120 seconds, checked between compilations.

| Work | Build 22 behavior | Source reuse |
| --- | ---: | ---: |
| Warm compilation calls | 214 | 59 |
| Live compilation calls | 290 | 46 |
| Live compilation time, first pair | 5,587.895 ms | 900.283 ms |
| Live compilation time, reversed pair | 4,939.885 ms | 892.563 ms |

Live compiler work fell 83.9% and 81.9%. This measures library compilation and entry lookup,
not game FPS, frame-time percentiles, or render-pipeline creation. The longest individual
live compile remained 33.8 to 40.3 ms with reuse, because new shader code still needs compiling.

The replay lives in the renderer's `windows/core/examples/shader_cache_audit.rs`, included
in both the cumulative and incremental patches. After applying one appropriate patch:

```sh
cd windows
cargo +1.97.1 build -p mtld3d-core --target aarch64-apple-darwin --example shader_cache_audit
target/aarch64-apple-darwin/debug/examples/shader_cache_audit CACHE_FILE 214
target/aarch64-apple-darwin/debug/examples/shader_cache_audit CACHE_FILE 214 baseline UNIQUE_SALT
target/aarch64-apple-darwin/debug/examples/shader_cache_audit CACHE_FILE 214 dedup ANOTHER_SALT
```

Use alphanumeric salts and bound each timed command externally to 150 seconds. Keep recorded
game caches and logs private; the published evidence contains aggregate measurements only.

### Validation

Formatting, clippy, source audit and documentation checks passed. All 1,043 core/types and
203 native/shared tests passed, as did all 447 rendering tests on each Wine architecture.
The new pixel regression changes ignored texture arguments, then makes them active, checking
colors across two devices. The initial 32-bit fixture posted WM_QUIT by destroying one window
before creating the next. Keeping both windows alive corrected that fixture; the affected
tests and the tests skipped by fail-fast then passed. Each architecture reported one passing
test with Wine stdio still open, which nextest calls a leak. No assertions remain failing.

The renderer harness now snapshots and restores the user's shader cache among its
44 saved file states. `--shader-cache FILE` seeds paired tests with identical cache contents and
records the seed hash. It captures the result before restoring the original cache. The
snapshot regression verifies that restoration, and all six harness tests pass. The report
also records compiler bursts separately from frame times, carries the cache-seed hash, and
labels the batched reuse counter as a lower bound. All eight report tests pass.

### Local game comparison

The production baseline and candidate completed the bounded local Hxitest town scenario.
The settled scene positions, camera, noon clock schedule, 4096 x 4096 background, other
graphics, minimal boot script, draw distance, renderer configuration and 214-record cache
seed matched. Screenshots preserve the character, textures, terrain and lighting. The Mines
vantage faces the plaza wall; it is not a crowd of player characters.

| Settled scene | Baseline FPS | Candidate FPS | Baseline maximum frame | Candidate maximum frame |
| --- | ---: | ---: | ---: | ---: |
| Markets bridge | 41.951 | 45.004 | 71.802 ms | 51.507 ms |
| Mines plaza wall | 36.253 | 37.697 | 83.087 ms | 77.201 ms |

These are one sequential pair, not a repeatability claim or evidence of stable 120 FPS.
The minimum one-second FPS improved in Markets but fell from 31.463 to 29.939 in Mines.
Frame-time percentiles in the JSON are per-window values, not pooled percentiles.

The driver source cache was already warm. Baseline prewarming compiled 214 libraries in
62 ms; the candidate compiled 59 in 46 ms and reused 155 states. Baseline logged one live
compile taking 2 ms; the candidate logged none. This local workload therefore did not
reproduce the original live compilation burst. It confirms integration and rendering, while
the recorded-source replay supplies the evidence for first-time compilation savings.
Baseline initially entered at the Mines tunnel and the candidate at the plaza, so comparisons
use the later fixed scene positions. Each run restored all 44 file states and saved
preferences, kept Docker unchanged, and left no game or Wine processes running.

Aggregate evidence and full scene summaries are in
[benchmarks/2026-09-05-shader-dedup.json](benchmarks/2026-09-05-shader-dedup.json).

### Installed build 23

`/Applications/FFXI-on-Mac.app` now contains the production shader-reuse build. Its native
D3D9 SHA-256 is `10bb9153f2edc2ff5f6628e6ce7062581dfd2de5db2c7f948e53b80682c2deb6`.
The Wine shim and Unix implementation are unchanged. Bundle signing and all renderer hashes
passed verification.

The first normal-launch validation refused to run because the saved renderer was DXVK.
Selecting mtld3d changed only that preference. The next bounded validation,
`20260905-131712-standard-nosample`, passed through the local Hxitest character screen using
the installed launcher's own renderer configuration and resources. Loaded hashes matched;
x87 acceleration and frame counters were active. The original 504-record game cache produced
105 prewarm compilations in 44 ms and 399 reused variants. Character-screen rendering was
reviewed and remains correct.

After validation, all 44 file states matched the originals from before the paired tests,
including the shader cache. Every preference except the intended mtld3d selection matched
the pre-install backup. Docker was unchanged and no launcher, game or Wine process remained.
The local rollback copy is
`ximac/benchmarks/20260905-shader-stutter/rollback-build22/FFXI-on-Mac.app`, with private
settings backups beside it. Restoring that app while the game is closed reverts the renderer
code; DXVK also remains selectable in build 23.
