# Upstream integration, 2026-09-11

## Source boundaries

- x87sidecar baseline development: `056b0a5398932e85d26ceefc409c59ba3adfab64`.
- Upstream master: `010f50a93c86d57ac93c395d5f9c283b74a5a6e8`.
- PR #31 follow-up: `48535de895bf7230cfe6e772b4ebe19d5b041424`.
- Candidate: `c00c5f7c2de0c04728e53ce08af225c608c47ec1`.
- wine-build main moves from `3d1f96df69c6e3742c873a7865794f5eed177912` to
  `9d348f5445d58606419b4a423b8f945d7055ee7c`, a fast-forward with no fork delta.
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

Launcher checks passed: 23 capture/report tests, 11 menu-run tests, three guest-scene tests,
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
for performance comparisons. Each run has a 180-second game deadline including launch and
loading, followed by separately bounded cleanup. Fixtures shorten the existing city route,
RDM/Chainspell self-buffs plus Warp, and Chainspell/Firaga against eight mobs.

The isolated sidecar login smoke test completed on Hxitest in zone 234. The recorder confirmed
two cooperative handshakes and active translation throughput. All 44 saved file states and
launcher preferences were restored. This run overlapped the Wine build and is not FPS evidence.

Further runtime results and the deployment decision will be recorded after validation.

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
