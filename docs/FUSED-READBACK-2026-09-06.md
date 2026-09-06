# Fused synchronous readback experiment

Experimental source patch only. Installed build 24 and vendored binaries remain
unchanged. Use `render.fuseReadback=true` only with both halves rebuilt from the
patch. It changes SubmitFrameParams from 104 to 112 bytes; mixing libraries from
before and after this change is unsupported.

The crowded-city draw trace shows repeated freshly rendered 16x16 masks followed
by StretchRect and a CPU read. The experiment appends the readback blit to the
producing render command buffer, then waits for completion in SubmitFrame. This
removes a separate command-buffer submission and API-thread/native transition.
It preserves current pixels, depth ordering, managed-buffer synchronization,
resource retention, and completion bookkeeping. It cannot eliminate the game's
dependency on the returned pixels.

The patch applies after the current local renderer changes, including the readback
and GPU timing patches. It defaults off. FrameData owns the readback parameters;
the synchronous caller holds destination pages until the encoder returns. Submission
status is returned through the synchronous channel. Native readbacks check GPU
completion status. Presentation with an attached readback is rejected.

Validation before game testing:

- Production i686, x86_64 PE and x86_64 Mac library builds passed.
- 78 i686 render-target tests passed with fusion and pass merging enabled.
- An additional repeated lockable-readback depth test passed on i686.
- All 79 x86_64 render-target tests passed with fusion and pass merging enabled.
- 1,043 core/types and 203 shared/native unit tests passed. The existing ABI-size
  test first caught a stale 104-byte expectation; updated size and offset checks pass.
- Nextest reported one process with lingering output handles in each Wine test run;
  all assertions passed and bounded SDK wineserver cleanup completed.

New tests alternate eight freshly drawn colors through draw, StretchRect, repeated
readonly locks and writable locks. They also check subsequent drawing and scene
depth preservation across three intervening small readbacks.

Live comparison pending: full fixed addons, frozen shader seed, same graphics,
same candidate binaries, fusion off/on/off, Local LSB/Hxitest only. Network sampling
is omitted on both sides. Each game run has a 420-second limit and a 540-second
outer process bound. No performance gain claimed yet.

Local artifacts: `ximac/benchmarks/20260905-fused-readback/`. Candidate bundle:
`ximac/benchmarks/20260905-050000-autonomous/fused-readback-02/`. Raw captures and
rollback snapshots are private and must not be committed.

## Separate-run comparison

All three crowd reports passed, screenshots showed matching formations, and every
run restored 44 files/preferences with Docker unchanged and no game process left.
The identical candidate binaries were used throughout.

| Phase | Off A FPS | On B FPS | Off C FPS |
| --- | ---: | ---: | ---: |
| Empty | 34.321 | 29.588 | 29.183 |
| 16 identical | 23.512 | 18.138 | 20.297 |
| 32 identical | 18.284 | 14.989 | 15.142 |
| 32 mixed | 19.026 | 15.451 | 16.877 |

The second baseline dropped too. These runs do not demonstrate an improvement,
and they cannot establish the size of a regression. Fusion remains disabled.

The next diagnostic uses `render.fuseReadbackAB=true`, alternating off/on every
eight seconds within one process. This option is also disabled by default. Mode
switches are logged; the report excludes transition frames and requires at least
two windows per mode per scene. Because log timestamps have one-second precision,
it uses a two-second margin after each logged switch and one second before the
next. Whole frame intervals must fit inside the usable window. Reports are made
with `python3 scripts/harness/readback-ab-report.py SUITE_ROOT`.

The two report tests cover transition frames, separate mode attribution, and
missing/incomplete mode windows. The diagnostic candidate is `fused-readback-ab-01`.

## Within-run result: no demonstrated benefit

Two alternating runs preserved the crowd and rendering checks. Each had one scene
with only one usable window for one mode, correctly rejected by the AB report.
All four scenes have a qualifying comparison across the two runs. Do not treat
both complete AB reports as passing. D used ordinary info logging; E added readback
and GPU timing traces, so compare modes within each run, not absolute FPS across D/E.

| Phase | D off / on FPS | D change | E off / on FPS | E change |
| --- | ---: | ---: | ---: | ---: |
| Empty | 34.670 / 34.443 | -0.65% | 33.968 / 33.868 | -0.29% |
| 16 identical | 23.173 / 23.280 | +0.46% | 22.477 / 22.748 | +1.20% |
| 32 identical | 18.396 / 18.147 | -1.35% | 17.786 / 17.768 | -0.10%, insufficient windows |
| 32 mixed | 18.844 / 18.935 | +0.49%, insufficient windows | 18.368 / 18.370 | +0.01% |

Fusion has no repeatable useful gain here. Keep it disabled. This is a tested
experiment, not a performance improvement to deploy.

E's diagnostic wall-time sums in the 32-identical scene explain the result:
approximately 14.6 readbacks per frame, 12.45 ms/frame in the standalone path's
render flush, 18.61 ms/frame in its readback call, and 30.75 ms/frame in the fused
flush. Standalone native encoding was only 0.74 ms/frame; native completion waits
were 17.45 ms/frame. Fusion largely moved the wait into SubmitFrame rather than
removing it. These are time sums divided by captured frames, with boundary seconds
excluded; they include instrumentation overhead and are not summed percentiles.

Detailed sanitized measurements, input hashes, restoration results, and individual
AB windows are in `docs/benchmarks/2026-09-06-fused-readback.json`. The installed app
and vendored binaries remain build 24. No performance gain is claimed.

Next diagnostic: reduce only background resolution to 1024 while preserving menu
resolution and full addons, to distinguish high-resolution rendering/store cost
from fixed synchronization latency. This is a quality-changing diagnostic, not a
proposed user-setting change. After that, identify the game's consumer of the
16x16 masks before considering changes to their rendering or update frequency.

## Resolution diagnostic and paused handoff

The 1024-square background diagnostic completed with full addons and unchanged
menu resolution. FPS was 37.438 empty, 25.627 with 16 identical characters, 20.031
with 32 identical, and 20.751 with 32 mixed. The 32-identical scene spent about
12.01 ms/frame flushing and 13.01 ms/frame reading back, versus approximately
12.45 and 18.61 in E's 4096-square off-mode windows. Sixteen times fewer background
pixels reduced part of the readback wait but did not remove the bottleneck.
Separate-launch drift prevents assigning an exact causal FPS gain. This setting
was restored and is not a shipped optimization.

User requested a pause after this run. No further benchmark launches are scheduled.
The run restored 44 file states and preferences, removed the server fixture, and
reported Docker unchanged. Its game PID was 9401. A separate game PID 28868 started
after benchmark cleanup and was left untouched.

Next steps, analysis first:

1. Identify the FFXI caller and consumer of the freshly rewritten 16x16 surfaces.
   The visibility-mask interpretation is inferred from draw/depth state, not proven
   by caller disassembly. Do not cache or delay their pixels without this evidence.
2. Split CPU encoder replay, native encoding, GPU execution, and wakeup latency
   around representative readbacks. Use within-run controls where possible; a
   shorter command-buffer count is not a reliable proxy for lower frame time.
3. Reconcile the rest of the frame budget. At roughly 56 ms/frame, the measured
   31 ms readback path does not explain all of the 8.33 ms target for 120 FPS.
   Even an unrealistic removal of that entire path leaves about 25 ms. This is
   rough budgeting, not a predicted speedup: queued rendering and overlap change
   when synchronization changes. Keep addons fixed while profiling shared renderer
   and runtime costs.

A separate source-level lead is the launcher's LuaJITGuard and the documented
`lj_mcode_patch` crash in Addons.dll. It disables JIT across addon entry points.
Investigating the shared compiler/runtime fault fits the general-performance goal;
this session did not change the guard or attempt to enable JIT.
