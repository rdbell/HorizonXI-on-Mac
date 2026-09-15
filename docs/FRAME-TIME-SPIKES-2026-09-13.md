# Frame-time investigation, September 13

Investigation in progress. No candidate from this investigation has been installed
into `/Applications`, and no elimination of all frame-time spikes is claimed.

## Controls and limits

All game runs use Hxitest on the local Docker LSB server. The full addon boot
script, shader-cache seed, 4096-square background, menu resolution, draw distance,
native window and renderer options are fixed. Each run has a 360-second game
deadline and a 340-second recorder deadline. The harness verifies local identity,
fixture completion, fresh loaded-renderer hashes and restoration of configuration
and preferences. Screenshots verify the formation and minimap rendering.

The persistence package based on launcher `25cd082b` and renderer `6cc05618` was
copied intact before experiments. Its native renderer SHA-256 is
`619faf2d6f588b98713a10edf03fc4c0e20f672a3662bd2c0fa116dd7fccb17e`; its i686
`d3d9.dll` is `4a159a9b023c0c685dec4a5255c7bfb38ad84983cf66b3938270754a4e53a9e7`.
Exact baseline DLL/PDB copies are preserved independently of build outputs.

Background application/VM activity is substantial and was left running. The
fixture's addon layout also differs from the user's normal character. These FPS
values cannot establish a regression against historical play-testing reports.

Raw captures, account/configuration snapshots, and private input files remain
outside the Git repositories. Local artifacts live under
`ximac/benchmarks/20260914-frame-spikes`; that directory's date was an initial
naming mistake, not the measurement date.

## Findings

- The 32-character formation causes sustained slow frames, not just arrival
  hitches. Settled production-baseline phases were approximately 8-9 FPS.
- No live shader compilations occurred in the arrivals captures. Shader-source
  deduplication is already enabled; repeating that optimization is not justified.
- In two settled diagnostic windows, readback flushes consumed approximately
  291-293 ms per second, read calls 135 ms per second, and native completion waits
  124 ms per second. These are nested wall-time sums, not additive frame stages.
  Typical individual native waits were around 0.6 ms, with some 13-17 ms waits.
- Thirty seconds of complete guest-sampler windows contained 30,009 samples:
  Addons 23.10%, FFXiMain 11.09%, d3d9 9.36%, UCRT 7.68%, host `ulock_wait2`
  25.37%, and `psynch_cvwait` 11.58%. These are observations, not independent
  speedup budgets. Several hot Addons offsets fall in a byte-pattern search loop;
  its entire cost must not be attributed to interpreted Lua.
- Matching baseline PDBs identify draw-state snapshots and vertex constants as
  renderer CPU hotspots. The inverse-view builder is one of them.
- Settled game-process page-ins were approximately 0-0.1 per second. Background
  memory pressure is real but did not produce sustained game paging there.
- The five-second native sample perturbed its phase badly. That phase is excluded
  from performance comparisons. Rosetta unwinding generated repeated chains that
  are not evidence of recursion.

Renderer telemetry counts internal submissions as frames in some summaries.
Actual FPS and percentiles below come from application frame durations. The PERF
encoder `Finalize` timer includes native submission on synchronous readback paths;
it does not isolate CPU pass-finalization cost.

## Rejected: exact redundant SetTransform gate

The gate compared matrix bits after state-block recording and preserved first
bone-palette initialization. Unit and targeted rendering tests passed, but the
production comparisons did not establish a useful gain. The source change was
removed; its patch and exact candidate binaries remain in the local experiment
directory.

| Settled phase | Baseline A FPS / p99 ms | Transform FPS / p99 ms | Baseline B FPS / p99 ms |
| --- | ---: | ---: | ---: |
| First arrival | 9.305 / 128.684 | 8.675 / 153.647 | 8.706 / 133.949 |
| Second arrival | 8.265 / 166.596 | 8.565 / 142.345 | 8.896 / 135.459 |
| Third arrival | 7.956 / 151.299 | 8.248 / 145.104 | 8.549 / 162.212 |

Captures: `20260913-095127`, `20260913-102810`, `20260913-103347`, all
`standard-nosample`. All workloads and restoration checks passed. Separate-run
drift prevents assigning a causal benefit from small differences.

## Inconclusive: gate and cache inverse-view work

`VsDraw` previously calculated the inverse view even with no active user clip
planes. The only shader consumer of its inverse rows is the fixed-function
clip-plane path, gated on the effective plane count. The i686 build imports
software `fmaf` helpers used by that inverse calculation.

The candidate writes identity into unused inverse rows when the effective plane
count is zero. Active clipping retains exactly the existing inverse calculation
and singular-matrix fallback. Enabling clipping already invalidates `VsDraw`.
No shader source or cache key changes are needed.

Rules check: no ABI field, static, config key, dependency, derive, lint suppression,
or game-specific heuristic is introduced. Pure logic remains in core. The uniform
layout is unchanged. Tests cover disabled/unsupported plane bits, camera changes,
and enabling clipping between draws with a translated view.

The follow-up also caches the inverse by all 16 view-matrix float bit patterns,
including signed zero and NaN payloads, per device. The active clipping math is
unchanged. Cache invalidation and enabling clipping between draws have regression
coverage. No change from this experiment is installed.

Separate-run comparisons did not establish a gain. Two within-process ABBA runs
then alternated the exact original inverse builder and candidate in eight-second
blocks with the same 32-character formation held for 96 seconds:

| Run | Baseline FPS / p99 ms | Candidate FPS / p99 ms | FPS change |
| --- | ---: | ---: | ---: |
| First | 8.700 / 173.029 | 9.312 / 140.876 | +7.03% |
| Repeat | 8.690 / 133.988 | 8.672 / 155.059 | -0.20% |

Captures: `20260913-111641` and `20260913-112249`, `standard-nosample`.
Both workloads and restoration passed. The repeat failed to confirm the initial
gain and had worse tail latency. This is an inconclusive experiment, not an
accepted optimization. Patches, packages and matching symbols remain preserved.

Validation: 1,048 core/types tests, 207 shared/native tests and 38 targeted i686
rendering tests passed for the cache candidate. Full gates remain pending. The
existing `make check` formatting failures in picture/settings code predate this
patch. Diagnostic mode switching was removed from the working source after
packaging its temporary binary.

## Spell baseline

Capture `20260913-103941-standard-nosample` completed two Chainspell rounds,
20 Firaga casts total, each damaging all eight fixture mobs. No freeze occurred.

| Phase | FPS | p99 ms | Maximum ms |
| --- | ---: | ---: | ---: |
| Idle | 16.246 | 90.151 | 133.650 |
| First ten casts | 14.965 | 148.899 | 177.002 |
| Second ten casts | 14.793 | 157.307 | 177.283 |

## Tooling

`renderer-run.py --renderer-log` now permits explicit diagnostic logging with
packaged mtld3d validation. It preserves the renderer-override preflight, writes
the filter through the snapshotted launcher preference, checks the fresh spawn,
and restores the preference afterward. Multiline filters are rejected before
machine preflight. Eleven harness tests passed; a live diagnostic capture verified
both the requested filter and restoration.

## Scheduling investigation

A native-only diagnostic queries pthread QoS at device creation, command submission
and readback. It uses the baseline PE binaries and never changes scheduling policy.
Initial observations show class 21 (`QOS_CLASS_DEFAULT`) for the game/API thread
and both threads observed submitting work. The existing App Nap activity declaration
therefore does not establish that these threads use user-interactive QoS.

This observation alone does not prove starvation. A temporary within-process ABBA
experiment at default versus user-initiated QoS is being prepared; no scheduling
policy change is proposed for production without repeatable evidence.
