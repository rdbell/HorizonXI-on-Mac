# Upstream integration, 2026-09-11

## Source boundaries

- x87sidecar baseline development: `056b0a5398932e85d26ceefc409c59ba3adfab64`.
- Upstream master: `010f50a93c86d57ac93c395d5f9c283b74a5a6e8`.
- PR #31 follow-up: `48535de895bf7230cfe6e772b4ebe19d5b041424`.
- Candidate: `c00c5f7c2de0c04728e53ce08af225c608c47ec1`.
- wine-build main incorporates upstream `9d348f5445d58606419b4a423b8f945d7055ee7c`
  from `3d1f96df69c6e3742c873a7865794f5eed177912`, then adds `842fbdb` to put the
  configured LLVM toolchain first in PATH. The upstream portion is a fast-forward.
- Isolated Wine source: `athei/wine@28fe1321fd7ddb7f7e1338fa1815f84b2404d31f`, plus
  `patches/wine-ucrt-country-locale.patch`. This is distinct from updating packaging scripts.

Upstream provides the Tahoe detach fix, native x87 state restoration, register tracing, and
FPATAN signed-zero correction. Our additions are the PR #31 automatic profiler PID suffixes,
sticky sampling, and the bounded signal-test coverage adjustment below. The shipped sidecar's
complete source patch and binary hash are in `vendor/x87sidecar-build.json`.

## Correctness checks

The original integrated test suite completed 1,023 entries: 1,020 passes, two known stock
Rosetta divergences, and one failure. The failure was the signal-context test under
`X87_DISABLE_HOOK=1`: no signal reached its exact observation PC during the 200 ms window.
It reported `checked=0`, `invalid=0`, `bad=0`; repeated runs also intermittently missed coverage.

The fixture now extends only observation-starved cases to a maximum two seconds. It never
clears an error or retries a failed numerical result. All 12 entries in the focused suite
passed, covering all translation modes and tracing. Three additional stock-emitter runs
passed all 60 cases. The unaffected full suite was not rerun after this test-only adjustment.

The concurrent-path regression passed three filename cases with two simultaneous targets,
both profilers, window files and preserved sentinel files. Literal `%p` remains literal.
A sticky-sampler runtime check recorded 2,903 samples, including 1,949 outside the main image,
with zero unavailable samples, a complete block-counter section and window records.

Launcher checks passed: 24 capture/report tests, 11 menu-run tests, three guest-scene tests,
and the Swift performance-diagnostics checks. The production app built successfully.
The complete source patch was applied to a temporary Git index and reproduced the candidate
tree exactly. Wine packaging scripts passed shell syntax checks.

## Isolation and measurement plan

Evidence remains in `ximac/benchmarks/20260911-upstream-integration/`. Private snapshots,
profiles and client assets must not be published. The installed app, patched Wine runtime,
prefix and shader seed were copied before testing. The test launcher uses an isolated prefix
and runtime; those overrides are not part of the shipped application.

Game fixtures use Hxitest on local Docker LSB only, with 4096-square background resolution,
the same mtld3d files, frozen initial shader cache and fixed graphics configuration. The
renderer uses `render.mergePasses=true;render.submitDraws=0`, with no x87 tracing or sampling
for performance comparisons. Initial runs had a 180-second game deadline including launch
and loading; valid city repeats use 240 seconds and effects runs allow 300 seconds, followed
by separately bounded cleanup. Fixtures shorten the existing city route,
RDM/Chainspell self-buffs plus Warp, and Chainspell/Firaga against eight mobs.

The isolated sidecar login smoke test completed on Hxitest in zone 234. The recorder confirmed
two cooperative handshakes and active translation throughput. All 44 saved file states and
launcher preferences were restored. This run overlapped the Wine build and is not FPS evidence.

## City comparison and installation decision

The initial 10-second holds produced only seven seconds of complete measurement windows.
The report correctly rejected those samples as too short. They suggested a 6–7% slowdown,
but are pilot evidence only. Repeats hold each settled viewpoint for 20 seconds and reverse
the test order: candidate first, baseline second. Both repeats completed and both viewpoints
passed zone, position, draw-distance, clock and frame-coverage validation. Compilers and
other Wine runs were stopped throughout the measurements.

| Scene | Installed sidecar | Integrated sidecar | Difference |
| --- | ---: | ---: | ---: |
| Bastok Markets | 39.783 FPS | 35.396 FPS | -11.0% |
| Bastok Mines | 97.271 FPS | 85.973 FPS | -11.6% |

These are frame-weighted averages from roughly 17 seconds of complete windows per viewpoint,
using the same old patched Wine runtime. They are not crowded multiplayer benchmarks or
estimates of all gameplay. The worst per-window p99 was 44.602 → 60.873 ms in Markets and
28.877 → 24.972 ms in Mines; the recording cannot supply a pooled p99 from these window rows.
No live shader compilations occurred in either repeat. Candidate screenshots show the
expected scene geometry and player at both viewpoints.

The slowdown repeats the pilot's direction and is sufficient to hold installation.
Upstream's native x87 state conversion is a plausible contributor: its commit documents
microbenchmark overhead. We have not isolated that commit in FFXI, so this is not a confirmed
attribution. PR #31's path changes do not run in the frame loop with profiling disabled.
Keep `/Applications/FFXI-on-Mac.app` and its existing runtime at the known-good baseline.
The integrated sources and candidate bundle remain available for further work.

## Wine runtime validation and a local build failure

A full local Wine build was bounded, resumed incrementally, and ultimately stopped before
completion. This is not a successful full packaging test. The runtime candidate instead uses
the official cx-26.3.0-5 archive (SHA-256
`584dae6b109621cb364dcac6242ba457f86f6218d530bc4fdf63ec38178e6208`). Release workflow
34378832855, job 102558330004, confirms source commit
`28fe1321fd7ddb7f7e1338fa1815f84b2404d31f`. Only the source-matched locale-patched UCRT DLLs
were rebuilt locally. This also avoids interpreting a packaging-script update as a runtime
update. The production launcher still selects its existing cx-26.3.0-1 runtime.

The first rebuilt DLL pair passed locale/string/misc tests but broke GUI initialization.
Pristine UCRT on the same runtime/prefix passed. A 32-bit-only replacement also passed;
the 64-bit replacement failed. A bounded loader/exception trace mapped the null dereference
to `msvcrt_get_thread_data`, `dlls/msvcrt/thread.c:58`, while `MSVCRT_locale` was uninitialized.

The build mixed LLVM-compiled objects with import libraries generated through Homebrew
MinGW tools. Its UCRT had eager imports of user32/advapi32 instead of delay imports, introducing
a GUI startup dependency cycle. Setting the per-architecture compiler variables alone was
insufficient: winegcc/winebuild find additional cross-tools through PATH. Prepending the
selected LLVM toolchain, rebuilding both import libraries and relinking UCRT restored both
delay-import tables and fixed the graphical probe. Relinking without regenerating the
import libraries did not fix it. The wine-build fork records the PATH correction in `842fbdb`.

After that correction, all six i386/x86_64 locale/string/misc checks passed again. The dedicated
locale round-trip retained `en-US / 0x409`. The three DEP memory cases passed, and the graphical
scene completed the NX EXE, legacy DLL and override rows with flags `0x1`; median frame times
were 13.30, 11.75 and 11.55 ms respectively. These are short synthetic probes, not FFXI FPS
measurements. The candidate's UCRT SHA-256 values are:

- i386: `22121a7c9360a031b6dcc106511296b893c85cb5a77e75e7501f7585f953a682`
- x86_64: `62ff1f4f16d5b75e2dec1fcfbf1999741bb196339ea8f1e9d354d56d42c7e032`

## Gameplay smoke tests

The corrected cx5 runtime with the integrated sidecar completed the local Hxitest effects
scenario and exited normally. The action-packet validator confirmed one Chainspell and
one successful application of each of Blaze Spikes, Ice Spikes, Shock Spikes, Stoneskin,
Blink and Aquaveil. Warp completed with spell/animation ID 261 and message 93. All 44 saved
file states and launcher preferences were restored afterward.

The 32.191-second buff phase had 1,021 frames, p99 44.466 ms and maximum 186.457 ms; two frames
exceeded 100 ms and none exceeded 500 ms. This is a correctness smoke test with some frame
timing evidence, not a matched Wine performance comparison. The local fixture intentionally
runs one buff round; the normal three-round report correctly flags the other two rounds as
missing. Only the completed first round and idle phase are counted here.

The eight-mob smoke test also completed under corrected cx5 and the integrated sidecar.
Server responses confirmed one Chainspell and four sequential Firagas, each damaging all
eight targets within the Chainspell window. The final fixture response confirmed zero
remaining mobs. The 18.169-second casting phase covered 537 frames, p99 61.448 ms and maximum
63.369 ms, with no frames over 100 ms. This shortened fixture is not the normal two-round,
ten-casts-per-round stress suite, and is not claimed as a pass of that full suite.

The full repeated effects/AoE comparison and a matched cx1/cx5 gameplay performance comparison
remain unperformed. The confirmed sidecar slowdown already blocks installation; passing
smoke tests does not close that performance-validation gap.

## Delivery and follow-up

The x87sidecar `development` and wine-build `main` branches are fast-forwarded and pushed;
the launcher `development` update includes the PID-path migration, reporting improvements,
vendored integrated sidecar and this report. No published history is rewritten. The existing
launcher archive checkout is preserved.

The next performance experiment should isolate the native-state boundary conversion while
retaining its signal-context/FXSAVE correctness tests. An experimental revert could establish
causality in the fixed city scenes, but would not be a shippable fix. Optimize the conversion
only once that comparison identifies it as the cost. Then repeat the paired city and full
effects/AoE comparisons, followed by a matched cx1/cx5 run before changing the runtime pin.

## Profiler integration checks

The real game generated `x87-sample.prof.<pid>` and `x87-block.prof.<pid>` for both
injector and client. The client block profile finalized and the native analyzer read it.
The diagnostic run reached the world at its 180-second deadline, so it is not a completed
gameplay scenario. Its cleanup restored all saved state.

Reporting initially exceeded the cleanup budget. A bounded offline profile identified
repeated module lookups as the dominant cost. Per-summary PC caching and searching the
existing export table directly let the complete report finish in 46.6 seconds under build
load, recognizing both processes and 15 client window records. A regression check verifies
repeated PCs resolve once per summary without retaining stale module maps. The capture suite
now has 24 passing tests.

The pinned guest range was honored by the sampler but its header read uninitialized zero
counters. Startup now initializes those header counters from the configured bounds. The
concurrent-path test also checks the pinned range and sticky flag in each resulting profile.
