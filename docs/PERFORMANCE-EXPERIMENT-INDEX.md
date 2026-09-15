# Performance experiment decisions

Current installed baseline: [early submission and Space recovery](SPACE-RESUME-BASELINE.md), promoted 2026-09-15.

Read this before proposing or rerunning a performance experiment. Updated September 14,
2026. This is an index of recorded decisions, not a claim that every historical private
capture has been audited. Linked reports retain methods, measurements, patches and limits.
The September 13 campaign is recorded in [Frame-time investigation](FRAME-TIME-SPIKES-2026-09-13.md).
The quieter September 14 sprint is recorded in [Frame-time sprint](FRAME-TIME-SPRINT-2026-09-14.md).

Historical user-approved baseline report: [version 3.8 build 24 at 4096-square background](KNOWN-GOOD-2026-09-06.md).
User reports common 100+ FPS, 120+ in light scenes, and rarely below 50 in crowded
play. Preserve this app/configuration; these are play-test observations, not stress-suite
percentiles. Reconcile workload differences before using synthetic results to change it.

## How to use this record

- Distinguish **adopted**, **no demonstrated benefit**, **inconclusive**, **blocked**,
  **invalid measurement**, and **not tested**. A failed launch is not a slow renderer.
- Before a retry, name the previous experiment and the new evidence, implementation,
  environment, or measurement control that makes the retry useful. Do not repeat an
  unchanged rejected experiment merely because its hypothesis sounds promising.
- Keep renderer/runtime versions, hardware, boot/addons, scene/camera, clock, resolution,
  cache seed and capture overhead with the evidence. Historical menu/minimal-addon FPS
  cannot be compared directly with the current full-addon crowd suite.
- Future experiments should add a row here and a detailed report with hypothesis,
  configuration/identity, run IDs, correctness checks, FPS/frame times, outcome, deployment
  status and retry condition. Keep raw captures and private restoration snapshots outside Git.
- Keep full addons fixed for the general-performance campaign. Individual addon tuning
  is outside the requested scope. Research leads are not completed experiments.

## Renderer and runtime decisions

| Experiment | Recorded outcome and disposition | What would justify revisiting it? | Evidence |
| --- | --- | --- | --- |
| Earlier render submission, controlled retry | **Default in the play-test candidate; not installed.** Two within-run crowd tests improved FPS 31-45%; quiet control improved 14%. Normal launcher, 20-cast battle, and full arrivals validations passed; one 198 ms arrival outlier remains. Full 2161 renderer tests passed; conformance remains incomplete because the same window-test timeout occurs with submission 0 and 512. Not installed. | The new ABBA method, normalized character state, and quieter host justify revisiting earlier inconclusive results. | [Scheduling](FRAME-TIME-SPRINT-2026-09-14.md#early-submission-positive-initial-controls) |
| Submission threshold 128 or 1024 versus 512 | **Not promoted.** Single ABBA comparisons lost 3.60% FPS at 128 and 3.72% at 1024. The 128 run had a slightly better p99; retain 512 pending stronger tradeoff evidence. | New repeated controls or an adaptive mechanism; do not sweep blindly. | [Threshold comparisons](FRAME-TIME-SPRINT-2026-09-14.md#early-submission-positive-initial-controls) |
| Bounded CPU frame-storage recycling | **No demonstrated benefit; removed.** Working reuse counters, 213 targeted i686 tests passed, but first controlled early-submit crowd comparison lost 3.46% FPS. | Measure reuse counters and matched FPS, then complete lifetime/readback and broader checks. | [Storage reuse](FRAME-TIME-SPRINT-2026-09-14.md#cpu-frame-storage-recycling-no-demonstrated-benefit) |
| Shared byte-pattern scanner | **Experimental, opt-in.** Prototype gains were 6-7%; final-production comparisons on submission512 gained 3.1% and 6.0%. Combined arrivals had worse warm tails than an earlier rendering-only run; causality unresolved. Fresh searches and original-API fallback; full addons fixed. Not installed. | Resolve the tail-latency tradeoff with paired arrival controls. FFXI_ON_MAC_ENABLE_SCAN=1 enables it; DISABLE_SCAN=1 wins. | [Scanner](FRAME-TIME-SPRINT-2026-09-14.md#shared-pattern-search) |
| Full-target reused-attachment fast clear | **Rejected and removed.** Pixel tests passed, but two ABBA runs lost 6-11% FPS and worsened p99. | A new measured mechanism or a different workload, not the assumption that load-action Clear is always faster. | [Clear results](FRAME-TIME-SPRINT-2026-09-14.md#full-viewport-reused-target-clears-rejected) |
| Compact API-to-encoder command storage | **Inconclusive.** Operation size 120 to 48 bytes; normalized pairs were +9.9% and -4.9%. Targeted pixel tests passed; no accepted FPS gain. | New within-run controls or a demonstrated allocation cost; the normalized repeat did not confirm a gain. | [Compact stream](FRAME-TIME-SPRINT-2026-09-14.md#compact-command-stream-repeat-is-inconclusive) |
| Shared SDK getters through Lua FFI | **Rejected.** 439,416 matching results, but measured call path 3.1-3.3 times slower. | A materially cheaper binding design; do not repeat the same guarded FFI wrapper. | [Other paths](FRAME-TIME-SPRINT-2026-09-14.md#other-measured-paths) |
| Pthread/Win32 priority promotion | **Pthread treatment invalid:** EPERM. **Win32 highest rejected:** -5.89% within-run. | Evidence of scheduler starvation plus a working, controlled treatment. | [Other paths](FRAME-TIME-SPRINT-2026-09-14.md#other-measured-paths) |
| Exact redundant SetTransform gate | **No demonstrated benefit; removed.** Correctness checks passed, but matched arrivals runs did not establish a useful FPS or p99 gain. Patch and binaries preserved locally. | A new trace showing a materially larger repeated-transform cost, or more stable controls supporting a gain. | [September 13 results](FRAME-TIME-SPIKES-2026-09-13.md#rejected-exact-redundant-settransform-gate) |
| Fused render/readback submission | **No demonstrated benefit.** Within-run changes about -1.4% to +1.2%; wait moved into the combined submission. Default off; source patch only, not installed. | A materially different mechanism that reduces necessary work or synchronization, rather than merging the same two submissions again. | [Fused readback](FUSED-READBACK-2026-09-06.md), [measurements](benchmarks/2026-09-06-fused-readback.json) |
| `submitDraws=512` early submission | **Historical inconclusive result, superseded by September 14 controls above.** Earlier Markets gain accompanied a tunnel regression; later full-addon crowd A/B/A drifted. | Within-run controls or a concrete adaptive scheduling design, including both light and crowded scenes. Do not label 512 universally faster or slower. | [Early tests](MTLD3D-EXPERIMENTS.md#early-submission-experiment), [crowd repeat](STRESS-VALIDATION-2026-09-05.md#resumed-campaign-crowded-frame-synchronization) |
| Conservative render-pass merging | **Adopted for mtld3d play testing.** Early pair favored average FPS, with tunnel tail-latency caveats. Launcher enables it; upstream config defaults off. | New correctness failure or a matched experiment targeting a specific remaining pass cost. Historical 'keep disabled pending repeats' text predates launcher integration. | [Merging](MTLD3D-EXPERIMENTS.md#independent-render-pass-merging), [launcher integration](MTLD3D-EXPERIMENTS.md#launcher-play-testing-build-22) |
| Identical shader-source reuse | **Adopted, build 23.** Recorded compiler replay reduced live compilation work about 82-84%; game validation did not reproduce the original cold compilation burst. | A new shader workload or an attributable remaining compile/pipeline stall. Do not claim an 84% FPS gain. | [Shader investigation](MTLD3D-EXPERIMENTS.md#stutters-when-characters-appear-repeated-compilation-of-identical-shaders), [measurements](benchmarks/2026-09-05-shader-dedup.json) |
| Enforce NX at `Direct3DCreate9` | **Adopted, build 24.** Corrected data-page execution policy and removed reproduced long Chainspell freezes. | Recurrence with policy flags and fault evidence showing this protection is absent or insufficient. | [Battle-effect investigation](BATTLE-EFFECTS-2026-09-05.md), [measurements](benchmarks/2026-09-05-battle-effects.json) |
| Single Wine runtime and unchanged-setup checks at launch | **Adopted, build 26.** About 46 seconds to the XI window became 13-17 seconds with the same renderer and full boot script. No FPS gain claimed. | A newly measured preparation regression or an attributable Wine/injection startup cost. Diagnostic trace/sample runs and the compile-overlapped first baseline are excluded. | [Launch report](LAUNCH-SPEED-2026-09-11.md), [measurements](benchmarks/2026-09-11-launch.json) |
| Preserve overlapping vertex strides | **Adopted, build 25.** Widening stride 36 to extent 44 fetched the wrong vertices. Five production pixel regressions fail on build 24 and pass with the fix; local lighting checks completed and minimap fill rendered. No sustained FPS gain claimed; the reported intermittent triangle remains unconfirmed. | Recurrence with frame-correlated geometry evidence, or a different stream layout. | [Stride correction and test limitations](VERTEX-STRIDE-2026-09-09.md), [measurements](benchmarks/2026-09-09-vertex-stride.json) |
| Omitted vertex-color material fallback | **Correctness fix adopted.** Black characters came from missing colors becoming zero. Mesa issue 320 suggested a different, unobserved material-zero mechanism. | A distinct material/stateblock failure shown by capture. Do not repeat the same Mesa diagnosis without matching evidence. | [Material diagnosis](MTLD3D-EXPERIMENTS.md#characters-rendered-black-because-omitted-vertex-colors-became-zero) |
| Unaligned VB/IB Lock output pointers | **Correctness fix adopted.** Debug renderer aborted on valid packed pointer outputs; regressions passed after correction. No FPS gain claimed. | A new alignment failure with a different affected boundary. | [Lock correction](MTLD3D-EXPERIMENTS.md#packed-buffer-lock-outputs-aborted-the-debug-renderer) |
| dgVoodoo 2.87.4 + DXMT 0.80 | **Blocked at compatibility.** D3D11 smoke tests worked; game/bridge startup did not. No game FPS result. Older downloaded versions were not executed in that campaign. | A bridge/device-creation fix or materially different version, starting with the isolated reproducer. | [Bridge experiment](MTLD3D-EXPERIMENTS.md#dgvoodoo2-and-dxmt-loading-experiment), [version status](PERFORMANCE-2026-09-05.md) |
| DXVK versus mtld3d | **Earlier matched scenes favored mtld3d**, with camera/clock and single-pair limitations. Current full-addon crowd results do not form a new matched DXVK comparison. | A specific newer backend change or a controlled comparison that answers a new question. | [Early renderer comparison](MTLD3D-EXPERIMENTS.md#first-comparison-with-fixed-camera-positions) |
| DXVK upload-arena prefaulting | **Recorded cold-loading improvement**, on the older DXVK stack. Not a current mtld3d steady-state result. | The same first-touch mechanism on a new runtime/backend. | [Historical update](PERFORMANCE.md#the-loading-stall-2026-09-03), [x87/loading history](X87-WALL.md) |
| Broad instancing/batching based on mesh ratios | **Historical conclusion superseded.** Ratios alone did not establish a draw-submission bottleneck. Experimental groundwork stayed off. | Current-backend profiling showing relevant CPU cost and compatible draw sequences with preserved order. | [Corrections](PERFORMANCE.md#corrections-to-earlier-conclusions), [archived batching analysis](BATCHING.md) |
| DXVK `KEEP_DEPTH` | **Historical regression.** Reduced framebuffer changes but measured 11.6 versus 12.9 FPS in that old setup; default off. | A different backend/workload with measured depth-transition cost. This does not invalidate the later mtld3d pass-merging result. | [Corrections](PERFORMANCE.md#corrections-to-earlier-conclusions) |

## Diagnostics and invalid comparisons

| Test or method | Decision / limitation | Evidence |
| --- | --- | --- |
| 4096 to 1024 background, menu unchanged | **Quality-changing diagnostic only.** Crowded FPS remained around 20; part of readback time fell. Separate-launch drift prevents precise causal gain attribution. Settings restored. Do not propose it as a code optimization. | [Resolution result](FUSED-READBACK-2026-09-06.md#resolution-diagnostic-and-paused-handoff) |
| 1024 x 576 menu with 4096 background | **Failed startup, no FPS result.** One black-screen failure does not establish that menu resolution caused it. | [Earlier battle attempts](BATTLE-EFFECTS-2026-09-05.md#implementation-and-earlier-attempts) |
| First fusion off/on/off runs | **Inconclusive due to baseline drift.** Later within-run switching supersedes their apparent regression. | [Separate runs](FUSED-READBACK-2026-09-06.md#separate-run-comparison) |
| Eight-second fusion switching | **Useful control with sampling limits.** Each of two runs had one scene with too few usable windows; every scene had a qualifying comparison across the two runs. Do not count both complete AB reports as passing. | [Within-run results](FUSED-READBACK-2026-09-06.md#within-run-result-no-demonstrated-benefit) |
| 64-NPC crowd | **Unsuitable rendered-population control.** All records arrived but only about 36-38 had active render flags. Current test uses 16 and 32 NPCs. | [Fixture validation](STRESS-VALIDATION-2026-09-05.md) |
| Early crowd placement / camera / despawn | **Superseded fixture.** Stair placement, nonpersistent heading, and missing client despawns invalidated assumptions. Flat-ground screenshots and active render flags are required. | [Fixture validation](STRESS-VALIDATION-2026-09-05.md) |
| Chainspell/Firaga stress | **aga8 validated with 20 casts.** aga24/aga40 remained unvalidated in this campaign. Earlier missed casts/no-effect responses are excluded. | [Stress validation](STRESS-VALIDATION-2026-09-05.md), [battle attempts](BATTLE-EFFECTS-2026-09-05.md) |
| Recorder network sampling | **Removed from default stress captures** after observing high nettop CPU cost. No isolated FPS gain attributed to its removal. | [Capture overhead](STRESS-VALIDATION-2026-09-05.md#resumed-campaign-crowded-frame-synchronization) |
| Renderer frame counters / forward clock changes | **Invalid measurement hazards corrected.** Internal submissions are not application frames; clock changes could expire sessions and leave stale scene state. Use verified live client markers and actual frame counters. | [Readback counters](MTLD3D-EXPERIMENTS.md#markets-readback-stalls), [clock validation](MTLD3D-EXPERIMENTS.md#reliable-benchmark-clock-setup) |

## Open questions, not completed optimizations

- A September 14 capture identified an immediate consumer of 16x16 readback alpha
  bits that affects rendering. GPU dependencies still prevent assuming the work can
  move earlier; stale-pixel caching and delayed reads remain unvalidated.
- Matched Linux/Proton live testing and cross-backend graphics-trace replay are proposals,
  not results. Current source research does not establish a matching 120-FPS Linux baseline.
- The shared LuaJIT crash guard remains in production. A September 14 MoonJIT-enabled
  diagnostic run compiled traces without reproducing the old mcode fault, but did
  not show a performance benefit. The underlying old fault is not confirmed fixed.
- Camera-heading stress phases remain experimental. Server orientation alone is not proof
  of camera orientation.

## Research lead: dxvk-low-latency

Source review only, September 6. **Not built, installed, or benchmarked.** Reviewed
[netborg-afps/dxvk-low-latency at ccc8cc8](https://github.com/netborg-afps/dxvk-low-latency/tree/ccc8cc8219b97088a7450ae9872d202acac294cc).
The main objective is input latency and pacing through predictive frame-start timing.
The README says its minimum-latency mode sacrifices CPU/GPU overlap and FPS; do not
mistake the project's high-refresh examples for measured FFXI performance.

Potentially useful implementation ideas:

- [Submission tracking](https://github.com/netborg-afps/dxvk-low-latency/blob/ccc8cc8219b97088a7450ae9872d202acac294cc/src/dxvk/framepacer/dxvk_gpu_progress.h)
  and calibrated GPU timestamps distinguish submission gaps from GPU progress. This
  is the best immediate reference for our missing queue/execution/wakeup attribution.
- [Low-latency setup](https://github.com/netborg-afps/dxvk-low-latency/blob/ccc8cc8219b97088a7450ae9872d202acac294cc/src/dxvk/framepacer/dxvk_framepacer.cpp)
  lowers pending-submission/chunk thresholds from 2/3 to 1/1. This is a concrete
  scheduling variation, not evidence that our prior 512-draw threshold works.
- [Threaded sleep](https://github.com/netborg-afps/dxvk-low-latency/blob/ccc8cc8219b97088a7450ae9872d202acac294cc/src/dxvk/framepacer/dxvk_threaded_sleep.h)
  wakes early and spins for the remaining interval, aiming for a 150-microsecond
  margin. Consider only if wakeup overshoot is measured; it uses CPU time and does
  not remove the dependency on fresh GPU pixels.

The inspected fork diff does not introduce a D3D9 LockImage/GetRenderTargetData
readback shortcut. Its D3D9 device change adjusts a latency-marker emission; most
changes concern pacing, timestamps, queue notifications, synchronization and HUDs.
There are also allocator synchronization changes, not assessed for correctness or
performance in this review. The README acknowledges incomplete integration of CS
processing timings into pacing. The fork is not a drop-in replacement for mtld3d;
any mtld3d adoption needs a Metal implementation and a new controlled experiment.

## Historical evidence

[PERFORMANCE.md](PERFORMANCE.md), [X87-WALL.md](X87-WALL.md),
[INWORLD-STALL.md](INWORLD-STALL.md), and [BATCHING.md](BATCHING.md) preserve older
hardware/runtime investigations. Their statements about addon loading, renderer CPU shares,
or the most promising next experiment are scoped to those captures, not the current setup.
The [September 5 timeline](PERFORMANCE-2026-09-05.md) and detailed reports above preserve
later changes. Consult the latest dated decision for the same configuration before acting.
