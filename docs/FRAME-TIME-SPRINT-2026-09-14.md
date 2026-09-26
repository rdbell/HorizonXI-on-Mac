# Frame-time sprint, September 14

The six-hour sprint completed at 14:41 UTC, followed by final reporting and
restoration verification. The installed app is protected; no candidate described here
has been installed into `/Applications`, committed, or pushed by this sprint.

The strongest result so far is earlier render submission: repeated within-run
crowd comparisons improved FPS by 31-45%, with a 14% gain in the quiet control.
A prototype shared memory-pattern scanner also improved crowd FPS by 6-7% in
repeated within-run tests and reduced p99 by about 25%; the final production
wrapper subsequently gained 3-6% with early submission fixed at 512, with mixed
worst-frame results. The full addon workload is retained. It is not
evidence of a universal 120-FPS result or elimination of all frame-time spikes.

## Controls

The six-hour sprint started at 08:41:25 UTC and runs through at least 14:41:25 UTC.
The user suspended the non-Docker VM and closed applications before the sprint.
Only Hxitest on the local Docker LSB server is used. Docker stays running.

The preserved test baseline has native renderer SHA-256
`619faf2d6f588b98713a10edf03fc4c0e20f672a3662bd2c0fa116dd7fccb17e`.
A separate `installed-baseline/FFXI-on-Mac.app` rollback now preserves all 40
files from the installed app, with per-file hashes. The installed native library
at sprint start had SHA-256
`99fd358a792617c2c1fe6a22df9eab37b32a352e45900569fcc87aeef03fef04`.
These packages are different; neither identity is inferred from the other.

The test machine is an Apple M2 Max (Mac14,5) with 96 GiB RAM.

Tests fix the full boot script, shader seed, 4096-square background, menu layout,
camera, noon weather setup, and draw distance 20. Each game run is bounded to 360
seconds; the recorder is bounded to 340 seconds. No builds or rendering tests run
during game measurements. Configuration, graphics preferences, fixture files, and
temporarily staged shared libraries are restored and checked after every run.

These synthetic 32-character results cannot be compared directly to the user's
historical 50-120+ FPS play tests. The character, layout, population, and draw
distance differ. They support controlled relative comparisons only.

At 11:45 UTC, a screenshot exposed prior spell buffs persisting into a later crowd
run. Stress setup now explicitly sets RDM99/BLM49 and removes effects 1-1023 before
measurement, preserving the GM effect with ID 0. New separate-launch comparisons
start with `normalized-baseline-a`. Earlier within-run ABBA results still compare
modes within the same character state; earlier separate-launch results need this
additional caveat.

## Shared pattern search

Sampling identified byte-pattern search inside Addons.dll. A direct shared-API
probe measured search at roughly 7-8% of wall time in the spell fixture, including
instrumentation. The replacement parses canonical hex/`??` patterns and uses an
SSE2 anchor search on x86. It performs a fresh search on every call; no result is
cached. Overlapping matches and occurrence ordinals are preserved.

The Lua wrapper delegates unsupported calls to the original binding, including
default numeric ranges, module aliases, explicit module-size overrides, unusual
argument counts/types, and noncanonical patterns. Module base/size are resolved
afresh. Native access violations return a fallback status; Lua protected calls
alone would not catch those faults. Other native exceptions are not swallowed.

| Within-run crowd comparison | Original FPS | Scanner FPS | Change | Original p99 | Scanner p99 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `quiet-scan-ab` | 10.262 | 10.983 | +7.02% | 143.830 ms | 108.223 ms |
| `quiet-scan-ab-repeat` | 11.980 | 12.738 | +6.33% | 121.964 ms | 91.792 ms |

The first run predates the page-boundary safeguard; its source and DLL are
preserved. The repeat uses that safeguard. Longer settling exclusions retain a
positive direction, approximately +4.5% to +10%, but do not establish universality.

Validation completed so far:

- 40,576 ARM and 40,576 Rosetta x86-64 differential cases for the prototype.
- 36,000 Windows x86 differential cases and 512 early-match guard-page cases.
- Two native access-fault fallback cases for the production helper, also tested
  through the portable runner in a fresh isolated Wine prefix.
- 5,705 live prototype shadow comparisons, zero mismatches.
- 462 live binding-contract cases, including 191 delegated cases, followed by
  4,411 additional gameplay comparisons, zero mismatches.
- 4,701 reported production-wrapper shadow comparisons in 39 addon runtimes,
  zero mismatches, during a validated 20-cast Firaga run against eight mobs.
- Standalone Lua binding tests and Swift package/staging/rollback tests.

The launcher integration verifies helper hashes, retains exact original common
library bytes, and inserts one environment-gated hook in `addons/libs/common.lua`.
It preserves BOMs, line endings, permissions, and earlier rollback files. If an
updater replaces the library, a different original gets its own hash-named backup.
It skips unfamiliar layouts and symbolic-link targets. Missing/corrupt helpers
leave original search active. `FFXI_ON_MAC_ENABLE_SCAN=1` explicitly opts in to final-source activation;
`FFXI_ON_MAC_DISABLE_SCAN=1` disables it. Earlier automatic-integration packages
are labeled separately below.

The rebuilt launcher automatically activated the exact packaged helper during
`normalized-scanner-app-aga`; the DLL mapping was checked in the fresh game
process. All 20 Firaga casts hit eight mobs and all staging/restoration gates
passed. Trimmed idle/round-1/round-2 results were 32.753/27.634/25.614 FPS, with
p99 34.771/82.612/90.500 ms. The later normalized baseline spell run was slower, but was separated by roughly
an hour; this does not establish causality. The packaged arrivals run
`normalized-scanner-arrivals` was mixed: loading p99 was 98.837/101.704/101.932 ms,
while warm p99 was 93.965/124.674/137.232 ms. Its second and third warm intervals
had 69 and 15 frames above 100 ms. All guards, exact DLL mapping, and restoration
checks passed. This mixed result motivated the final-production within-run comparisons with
512-draw submission fixed, recorded below.

The first final-production scanner ABBA comparison with submission fixed at 512,
`normalized-production-scan-early-ab`, measured 18.159 versus 18.724 FPS (+3.11%),
p99 75.649 versus 70.967 ms, and maximum 78.847 versus 74.658 ms. The optimized
intervals recorded 1,939 production-wrapper invocations; this counter includes
any original-API delegation inside the wrapper. Exact helper/source receipts,
workload, and restoration checks passed.

The final-production repeat `normalized-production-scan-early-repeat` was also
positive for FPS: 14.498 to 15.362 (+5.96%), with 1,648 optimized-wrapper calls.
p99 changed only slightly, 89.574 to 88.662 ms, and the maximum worsened from
106.019 to 141.082 ms. Both workloads/restorations passed. This supports the
scanner as a modest throughput improvement alongside early submission, not a
claim that it removes long frames. The final candidate keeps this feature opt-in: use
`FFXI_ON_MAC_ENABLE_SCAN=1` in Extra environment to enable it;
`FFXI_ON_MAC_DISABLE_SCAN=1` still wins. The earlier `scanner-early-candidate`
package deliberately enabled it for the combined integration measurements.

### Paired arrivals, 2026-09-26

The retry the index asked for: separate launches in ABBA order (off, on, on, off, three minutes
apart) on development 966b1aa with cx-26.3.0-6, mtld3d, 512-draw submission and the native
window, the sprint's boot script and shader seed, 4096 background and draw distance 20. The only
difference between arms was `FFXI_ON_MAC_ENABLE_SCAN=1`; each run confirmed from the live game
that the packaged scanner DLL was, or was not, mapped. All four workloads were valid.

| phase | FPS off -> on | p99 off -> on | worst off -> on |
| --- | --- | --- | --- |
| arrival-1 | 30.38 -> 31.99 (+5.3%) | 38.9 -> 37.2 ms | 53.5 -> 42.2 ms |
| arrival-warm-1 | 26.98 -> 28.46 (+5.5%) | 40.7 -> 38.2 ms | 46.0 -> 44.4 ms |
| arrival-2 | 28.48 -> 29.40 (+3.3%) | 43.0 -> 42.1 ms | 65.3 -> 52.2 ms |
| arrival-warm-2 | 26.43 -> 27.84 (+5.3%) | 40.3 -> 39.0 ms | 58.7 -> 50.4 ms |
| arrival-3 | 28.56 -> 30.27 (+6.0%) | 41.1 -> 45.6 ms | 51.6 -> 56.1 ms |
| arrival-warm-3 | 26.34 -> 27.73 (+5.3%) | 40.6 -> 39.1 ms | 49.7 -> 45.0 ms |

Means of two runs per arm; worst is the larger of the two. Both scanner runs beat both controls
in every phase (mean +5.1%) and no phase had a frame above 100 ms. arrival-3 p99 was worse in
both scanner runs by 2.5-6 ms. The unpaired `normalized-scanner-arrivals` tail above did not
reproduce. The launcher now enables the scanner by default; `FFXI_ON_MAC_DISABLE_SCAN=1` turns it
off. Two runs per arm on local LSB only; hosted worlds were not tested.

## Renderer work

### Full-viewport reused-target clears: rejected

The candidate replaced a full-screen clear quad with a Metal load-action clear
when a reused target's viewport covered its entire attachment. Partial and
mid-pass clears retained their previous behavior. Two unit regressions failed the
baseline; 1,048 core/types tests, 207 native/shared tests, and 49 targeted i686
rendering tests passed. Pixel coverage included intervening copies and partial MRT
clears preserving surrounding pixels.

Correctness tests did not predict performance. Both eight-second ABBA crowd runs
were slower:

| Run | Original FPS | Candidate FPS | Change | Original p99 | Candidate p99 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `quiet-fast-clear-ab` | 12.476 | 11.108 | -10.96% | 109.091 ms | 119.262 ms |
| `quiet-fast-clear-ab-repeat` | 12.121 | 11.429 | -5.71% | 105.661 ms | 118.939 ms |

Startup intervals without eligible clears were excluded before parsing mode
markers. Continuous markers were required within a 16-second bracket around the
measured phase, in addition to the usual switching/phase settling exclusions.
Both workloads and restoration checks passed. The change was removed; its patch,
packages, symbols, and reports are preserved privately.

### Compact command stream: repeat is inconclusive

The i686 operation union shrinks from 120 to 48 bytes when draw payloads are
stored separately. Both vectors preserve insertion order and belong to the frame.
The repeated normalized crowd controls did not support promotion; this layout
was removed from production source:

| Run | FPS | p99 ms | max ms |
| --- | ---: | ---: | ---: |
| normalized-baseline-a | 12.553 | 112.461 | 148.607 |
| normalized-compact-a | 13.798 | 98.135 | 197.143 |
| normalized-baseline-b | 12.482 | 88.369 | 96.035 |
| normalized-compact-b | 11.873 | 116.472 | 148.747 |

The first pair improved FPS by 9.9%; the second regressed by 4.9%. Separate-launch
noise or state not captured by the controls remains possible. The layout remains unproven. The broader storage-reuse experiment now uses the
baseline layout, so a recycling gain cannot be credited to the compact format.


### Early submission: positive initial controls

The renderer already supports splitting accumulated work after a draw threshold.
The launcher baseline disables it (`render.submitDraws=0`). An eight-second ABBA
diagnostic switches between 0 and 512 at application Present boundaries, using
the existing continuation and readback synchronization rules.

| Within-run comparison | Original FPS | 512-draw FPS | Change | Original p99 ms | 512-draw p99 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| normalized-early-crowd-retry | 11.946 | 15.680 | +31.25% | 95.245 | 85.313 |
| normalized-early-light | 21.303 | 24.339 | +14.25% | 55.106 | 45.948 |
| normalized-early-crowd-repeat | 11.942 | 17.359 | +45.36% | 114.021 | 71.232 |

The crowd benefit repeated, with a larger but variable magnitude. Normal-
configuration spell and arrival results are recorded below. These controls
justify revisiting older inconclusive early-submit experiments:
character state is normalized, the other VM is suspended, and the two modes now
share one running workload. They do not establish universal improvements.

The first early crowd attempt ended before measurement because the client rejected
an anchor-spawn chat command one second after clearing the previous fixture. Its
screenshot records the command error; it is an invalid workload, not a renderer
regression. Initial server-command and anchor-spawn spacing is now at least two
seconds. The successful retry confirmed the full fixture and restored all state.

The normal configuration path also completed a valid crowd run:
`normalized-early-production`, the preserved baseline package with a verified
512-draw setting, measured 18.125 FPS, p99 65.628 ms, and maximum 77.779 ms after
the fixed settling exclusion. No measured frames exceeded 100 ms. All 46 file
states, preferences, and owned processes were restored. This separate launch
supports the within-run results but is not a new universal FPS baseline.

The first normalized spell pair shows a smaller benefit, with all 20 casts hitting
eight mobs and no freeze in either run. Settled idle improved 23.101 to 24.565 FPS;
casting rounds improved 21.441 to 21.934 and 21.891 to 22.826 FPS. Round-1 p99 was
essentially unchanged (108.504 versus 109.158 ms), while round-2 p99 fell from
106.297 to 100.575 ms. Do not extrapolate the crowd gain to every spell workload.

The normalized arrivals comparison includes the full loading intervals. Results
favor 512, but do not support a hiccup-free claim:

| Loading round | Original FPS | 512 FPS | Original p99 ms | 512 p99 ms | Original >100 ms frames | 512 >100 ms frames |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 15.320 | 18.961 | 101.017 | 79.427 | 4 | 0 |
| 2 | 12.883 | 18.077 | 163.140 | 77.050 | 76 | 0 |
| 3 | 15.362 | 18.543 | 99.562 | 88.925 | 3 | 2 |

Settled crowd FPS after these arrivals improved from 11.18-11.92 to 16.19-16.62.
The largest individual frame in the 512 run was still 198.397 ms in round 3,
versus a baseline maximum of 172.743 ms in round 2. Both complete workloads and
restoration checks passed. The launcher source now selects 512 by default;
packaged gameplay verification is recorded below. The full source renderer
suite passed with submission 512: 1,046 core/type tests, 207 native/shared tests,
and 454 rendering tests on each of i686 and x86-64. Each Wine rendering leg
reported one process with lingering output handles; all assertions passed and
the owned wineserver cleanup completed. The i686 conformance gate did not pass: its device/window subtest timed out
at 90 seconds and visual failures exceeded the stored upstream baseline. A matched
submission-0 control reproduced the timeout and the same 236 visual, zero
stateblock, and one D3D9Ex failures. The timed-out device tests reported 24
baseline versus 22 candidate failures, with no new candidate failing site. This
is not a clean conformance pass: later device coverage is missing and the aggregate
Make target did not reach x86-64 conformance. Neither baseline counts nor expected
images were changed to make this gate pass. The runner's temporary configuration
patch was restored and its source hash checked after both runs.

A first 512-versus-1024 within-run comparison (`normalized-early-tune-crowd`)
favored 512: 15.414 versus 14.840 FPS (-3.72% for 1024), with p99 77.690 versus
83.310 ms. Both modes shared the same diagnostic package and workload. This
does not justify increasing the threshold. The final 512-versus-128 comparison,
`normalized-early-small-crowd`, also favored 512 for FPS: 17.545 versus 16.913
(-3.60% for 128). The smaller batch improved p99 from 79.451 to 74.879 ms in that
single run. Both controls and restoration passed. This tradeoff does not justify
changing the more thoroughly validated default to 128.

The harness now accepts an explicit `--submit-draws` control for packaged-renderer
validation, limited to 0/128/256/512/1024. It verifies the effective value in the
fresh launcher environment and restores the previous preferences after the run.
`--expected-submit-draws` validates a package without overriding it. The harness
expects the new launcher default of 512; task runs explicitly identify older
packages as 0.

### CPU frame storage recycling: no demonstrated benefit

Two candidates have passed 213 targeted i686 pixel tests each (one leaky Wine
handle reported per run). The first recycles empty operation/draw arrays on top
of the compact layout. The second starts from the original layout and also
recycles the API scratch arena only after the existing `execute_submit` boundary
has finished reading it. GPU retention and readback correctness remain separate.

Return queues never block and retain at most two bundles, each no larger than
8 MiB. The ordinary allocation path remains the fallback. Both synchronous and
asynchronous submission paths use the same safe return boundary.

`normalized-storage-early-ab` compared reuse off/on within the crowded scene with
512-draw submission fixed. Original allocation measured 18.589 FPS/p99 66.650 ms;
recycling measured 17.946 FPS/p99 64.018 ms, a 3.46% FPS regression. Counters
confirmed thousands of actual reuses in optimized intervals and zero in disabled
intervals. Summed buffer capacity is not measured allocation traffic or copied
bytes. This first comparison does not justify the added complexity: the storage
change was removed from production source and its patch/package retained for
reference. The earlier compact-array-only recycling package remains unmeasured.

## Other measured paths

| Experiment | Result and disposition |
| --- | --- |
| Inverse-view gate/cache, quiet ABBA retry | -2.65%; removed. Earlier inconsistent results did not reproduce a benefit. |
| Pthread QoS promotion | Setters returned EPERM. Invalid treatment, no performance conclusion. |
| Win32 highest priority | -5.89% within-run comparison; rejected. |
| Unused fixed-function sampler pruning | No convincing gain or reduction in heavy pass count; removed. |
| MoonJIT re-enabled | 37 runtimes enabled, compiled traces observed, no targeted mcode fault reproduced. Separate-launch spell results were slower; production crash guard retained. |
| Shared SDK getters through Lua FFI | 439,416 matching results, but 3.1-3.3 times slower call path. Rejected. Sampled original native getter budget was about 4.4-5.3%, including measurement overhead. |

The runtime identifies itself as MoonJIT 2.2.0. Its `jit.off()` does not simply
remove existing compiled bytecodes, so toggling it is not a valid interpreted
versus compiled comparison without further controls.

GPU timeline diagnostics found that preceding render execution covered 88.5% of
the pre-copy queue delay. The copy itself was about 0.005 ms median. Captured
dependencies tied a 16x16 reduction to a 4096 target attached to the scene depth
buffer. This does not establish that the query can move ahead of scene writes.
The immediate CPU consumer reads fresh alpha bits and affects rendering; stale or
zero readback substitutions were not used.

## Reproduction and artifacts

Raw logs, account/configuration snapshots, extracted client data, and copied game
DLLs remain outside the repositories in the local sprint directory. The tracked
sources contain no private captures.

- `scripts/build-memory-scan.py`: build or verify the scanner package.
- `scripts/tests/memory-scan-test.py`: native differential oracle.
- `scripts/tests/memory-scan-windows-test.py`: bounded x86 runtime test in an owned prefix.
- `scripts/tests/memory-scan-wrapper-test.lua`: public binding/fallback contract.
- `scripts/tests/memory-scan-test.swift`: staging and rollback without XCTest.
- `scripts/harness/stable-phase-report.py`: validated whole-frame statistics with
  fixed first-three/last-one-second exclusions, retaining the original report.
  Use these exclusions for settled holds; arrival transitions must retain their
  initial frames in the original stress report so loading spikes are not hidden.

Static source validation ran each Make leg independently so the existing
formatting failure would not hide later results. PE clippy and documentation
builds passed. Native clippy and the mechanical audit remain blocked by findings
in unchanged picture/settings, shader-cache, and execution-policy files. Two
new observer warnings were corrected; the follow-up native clippy run has no
observer findings, but still fails on the pre-existing code. The full repository
`check` gate is therefore not green.

The scanner-enabled combined arrival run passed all guards and exact helper
mapping checks, but its warm tails were worse than the earlier rendering-only
run. Loading FPS was 17.908/16.745/18.873, p99 82.525/101.314/87.654 ms. Warm FPS
was 12.790/14.093/14.725, p99 147.069/149.056/128.900 ms, and maximum
183.072/214.151/236.971 ms. Separate-launch drift prevents assigning that change
to the scanner. A later read-only host snapshot found healthy memory (79% free)
but substantial CPU activity in airportd, WindowServer, and other background
apps; it does not prove what caused the earlier spikes.

Because the goal prioritizes smoothness, final source keeps the scanner opt-in.
The principal candidate enables only the better-supported 512-draw submission
setting by default. The combined experimental package and its evidence are
retained. The combined spell run also passed: all 20 Firaga casts hit eight mobs, with
full restoration and no freeze. Settled idle/round1/round2 FPS was
26.938/24.636/23.177, with p99 46.991/99.955/100.152 ms. These are useful
integration results, not an isolated scanner effect.

The final `early-candidate/FFXI-on-Mac.app` was rebuilt successfully with the
scanner opt-in and the 512-draw default. It retains the preserved baseline PE
and native renderer, plus the bundled helper for optional experiments. The
final default-package run passed its workload, verified that no scanner DLL was
mapped, verified 512 without a configuration override, and restored all state.
Its profiling instrumentation means its absolute FPS is not a performance control.

Eight complete settled profiling windows contained 80,245 samples. Selected-thread
leaf shares were Addons.dll 35.01%, FFXiMain.dll 16.58%, UCRT 11.06%, and D3D9
10.48%. The two largest wait syscalls were psynch_cvwait 8.15% and ulock_wait2
4.54%. Renderer symbols identified snapshot delta emission at 2.23% of all
samples and vertex-constant assembly at 1.58%. These are sampling categories,
not all-thread CPU utilization or proof of a particular Lua interpreter cost.

The next larger opportunity is to break down the shared Addons/runtime and UCRT
costs under this improved schedule, while preserving the full addon workload.
Earlier JIT and SDK-binding experiments did not help, so this profile does not
justify blindly repeating them. The scanner's arrival tails need a matched
within-package control before enabling it by default.


## Final disposition

The built play-test candidate is `early-candidate/FFXI-on-Mac.app` in the local
sprint directory. It defaults to 512-draw submission and leaves the shared
scanner opt-in. No candidate was installed, committed, or pushed. Its signature
and the absence of the scanner in the final default runtime were verified.

The final audit verified all 40 installed-app files against the separate rollback,
23 normalized restoration receipts, shared-hook restoration receipts, graphics
preferences, the final launcher-preference restoration, and unchanged Docker
state. No related game/Wine/sidecar process remains. Source changes and binary
diffs are checkpointed under `source-checkpoint-final`, independently of Git commits.

The results support a repeatable 31-45% crowded-scene throughput improvement from
earlier submission, smaller benefits in the spell tests, and improved arrival
p99 in the matched initial comparison. They do not establish universal 120 FPS
or hiccup-free gameplay. Long frames remain; the combined scanner measurements
and the incomplete conformance gate are documented above rather than hidden.

## Subsequent baseline promotion

On 2026-09-15 the user promoted the early-submission candidate with the desktop visibility-recovery correction. The sprint's statements about uncommitted/uninstalled work describe its original closeout. See [the current baseline](SPACE-RESUME-BASELINE.md) for installed identity, rollback, verification and committed-source provenance. The scanner remains opt-in.
