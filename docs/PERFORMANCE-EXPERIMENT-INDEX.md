# Performance experiment decisions

Read this before proposing or rerunning a performance experiment. Updated September 6,
2026. This is an index of recorded decisions, not a claim that every historical private
capture has been audited. Linked reports retain methods, measurements, patches and limits.
Game runs are currently paused at the user's request.

Current user-approved baseline: [version 3.8 build 24 at 4096-square background](KNOWN-GOOD-2026-09-06.md).
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
| Fused render/readback submission | **No demonstrated benefit.** Within-run changes about -1.4% to +1.2%; wait moved into the combined submission. Default off; source patch only, not installed. | A materially different mechanism that reduces necessary work or synchronization, rather than merging the same two submissions again. | [Fused readback](FUSED-READBACK-2026-09-06.md), [measurements](benchmarks/2026-09-06-fused-readback.json) |
| `submitDraws=512` early submission | **Inconclusive / scene tradeoff.** Earlier Markets gain accompanied a tunnel regression; later full-addon crowd A/B/A drifted. Remains disabled. | Within-run controls or a concrete adaptive scheduling design, including both light and crowded scenes. Do not label 512 universally faster or slower. | [Early tests](MTLD3D-EXPERIMENTS.md#early-submission-experiment), [crowd repeat](STRESS-VALIDATION-2026-09-05.md#resumed-campaign-crowded-frame-synchronization) |
| Conservative render-pass merging | **Adopted for mtld3d play testing.** Early pair favored average FPS, with tunnel tail-latency caveats. Launcher enables it; upstream config defaults off. | New correctness failure or a matched experiment targeting a specific remaining pass cost. Historical 'keep disabled pending repeats' text predates launcher integration. | [Merging](MTLD3D-EXPERIMENTS.md#independent-render-pass-merging), [launcher integration](MTLD3D-EXPERIMENTS.md#launcher-play-testing-build-22) |
| Identical shader-source reuse | **Adopted, build 23.** Recorded compiler replay reduced live compilation work about 82-84%; game validation did not reproduce the original cold compilation burst. | A new shader workload or an attributable remaining compile/pipeline stall. Do not claim an 84% FPS gain. | [Shader investigation](MTLD3D-EXPERIMENTS.md#stutters-when-characters-appear-repeated-compilation-of-identical-shaders), [measurements](benchmarks/2026-09-05-shader-dedup.json) |
| Enforce NX at `Direct3DCreate9` | **Adopted, build 24.** Corrected data-page execution policy and removed reproduced long Chainspell freezes. | Recurrence with policy flags and fault evidence showing this protection is absent or insufficient. | [Battle-effect investigation](BATTLE-EFFECTS-2026-09-05.md), [measurements](benchmarks/2026-09-05-battle-effects.json) |
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

- The consumer of the freshly written 16x16 masks is not identified. Visibility is an
  inference; stale-pixel caching or delayed reads are not validated solutions.
- Matched Linux/Proton live testing and cross-backend graphics-trace replay are proposals,
  not results. Current source research does not establish a matching 120-FPS Linux baseline.
- The shared LuaJIT crash guard is a source-level lead. Its underlying compiler/runtime
  fault has not been fixed here; the guard was not disabled in these runs.
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
