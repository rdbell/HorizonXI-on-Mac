# Stress suite validation, September 5

Installed renderer remains build 24. This checkpoint changes benchmark tooling only.
All live runs used Local LSB/Hxitest. Docker was neither restarted nor rebuilt.

## Completed evidence

The eight-mob Firaga workload completed both Chainspell rounds and all 20 casts.
Both the client action packet and the server damage audit confirmed eight targets.
Full personal addons, 4096-square background, and the frozen shader seed produced
41.652 FPS idle, 39.072 FPS in round one, and 32.768 FPS in round two. Worst frame
was 78.610 ms. These are baselines, not improvements.

City testing found three fixture problems:

- `setStatus(DISAPPEAR)` deleted dynamic NPCs without a client despawn update.
  `hideNPC(600)` sends the update before dynamic-entity deletion. Replacement and
  final zero-entity cleanup subsequently completed.
- All 64 NPC records reached the client, but only 36-38 had active render flags.
  Defaults now use 16 and 32 identical NPCs, then 32 with seven fixed looks.
- Home key delivery did not establish a camera view toward the formation.
  A temporary fixture target and a lock/unlock pair aligned the camera successfully.

The completed city-12 diagnostic measured 35.950 FPS empty, 21.873 with 16 NPCs,
16.910 with 32, and 15.894 with 32 mixed looks. Screenshots confirmed the formation
was visible, but its back row reached the auction-house stairs. These timings are
provisional and must not be compared directly with later flat-ground runs.
The report initially rejected mixed-32 because one population check still expected
64. That check and a regression test were corrected; the recorded workload passes
the corrected report. Visual review remains separate from numeric validity.

The final script moves the player to `(0,0,-90)` in Bastok Mines and centers the
single camera anchor. That position still needs live screenshot validation. The
next run, baseline-13, timed out recognizing character selection before entering
the world. All 44 saved file states and launcher preferences were restored, and
the temporary server command was removed. No game or Wine process remained.

## Next comparisons

1. Validate the flat-ground crowd view, then run identical full/minimal addon tests.
2. Compare submitDraws=0 against 512 with mergePasses=true, holding renderer bytes,
   graphics, boot script, and shader seed fixed. Prior submission tests predated
   pass merging and showed a busy-scene gain with a light-scene regression.
3. Validate aga24/aga40 server audits and repeated arrivals. Camera-heading phases
   remain experimental because server orientation does not prove camera orientation.

Local raw captures and private rollback snapshots remain outside Git under
`ximac/benchmarks/20260905-stress-suite/`. Do not publish those private snapshots.
Focused Lua stress/fixture tests and Python report/suite tests pass.

## Log review and next experiment plan

Game automation paused when the user returned. Tooling checkpoint `5d09d37` is
pushed to the user-owned development branch; the installed app remains build 24.

The completed city-12 diagnostic separates sustained cost from long freezes:

| Phase | FPS | Median frame ms | p99 ms | Frames over 100 ms |
| --- | ---: | ---: | ---: | ---: |
| Empty | 35.950 | 27.505 | 34.783 | 0 |
| 16 identical NPCs | 21.873 | 45.619 | 52.995 | 0 |
| 32 identical NPCs | 16.910 | 58.666 | 69.168 | 0 |
| 32 mixed NPCs | 15.894 | 62.619 | 72.101 | 0 |

Identical models already incur most of the slowdown. Model diversity adds a smaller
cost. This favors investigating per-character animation, state setup, and repeated
render work over assuming new-texture loading explains the steady-state slowdown.
It does not distinguish game CPU work from renderer synchronization by itself.

The renderer logged NX flags changing from 2 to 9, pass merging enabled, and submission
threshold zero. Shader prewarming reused 399 variants from 143 unique libraries in
17 ms; no live shader compilations or GPU errors were logged. System-wide GPU
utilization medians were 43.5%, 42%, 39.5%, and 39.5% across those phases. Those are
whole-system utilization counters, not this game's GPU duration. Settled phases had
zero page-ins; disk reads were zero except roughly 43 KB/s in mixed-32. Ordinary
process faults remained measurable and are not proof of a renewed execute-policy
exception storm. Detailed API/readback timings were not enabled in these runs.

Run the next experiments sequentially, after the user releases the computer:

1. Validate final flat-ground placement and camera alignment. Run full/reduced/full
   addon comparisons on crowd and aga8 using one renderer, graphics profile, and
   shader seed. Preserve XICamera, aspect/projection, and asset overrides on both
   sides. The existing bare `--minimal` changes camera configuration as well, so it
   cannot isolate UI CPU cost without that control. Compare both FPS and p99.
2. If addons explain a substantial share, time the identified addons/modules in
   separate 20-30 second diagnostic windows. LuaJIT's built-in profiler supports
   interpreted code; first verify that Ashita's embedded build exposes `jit.profile`.
   Keep the JIT crash guard enabled. Retain all intended UI behavior when optimizing.
3. Use a separate short readback/GPU/guest-stack diagnostic on the heavy phase.
   Existing trace targets are `mtld3d::readback` and `mtld3d::gpu_time`. API timing
   requires a build with `MTLD3D_PERF`; setting a runtime log target cannot restore
   timers compiled out of the production build. Confirm guest module/thread identity.
4. Test submitDraws=512 versus zero with mergePasses=true. Include a light scene to
   detect the regression seen before pass merging. Promote only a repeated gain
   with correct rendering. Consider adaptive submission only if timing supports it.
5. If the game remains dominant, isolate character shadows and animation cost in
   the same crowd. Capture a bounded representative draw/state trace before pursuing
   state deduplication, instancing, or translation changes. Finish aga24/aga40 and
   arrivals validation; camera-heading phases remain experimental.

### Research leads and limits

- [LuaJIT profiler documentation](https://luajit.org/ext_profiler.html) explicitly
  supports interpreted and compiled code. This offers addon attribution without
  reintroducing the known JIT crash. Embedded availability remains unverified.
- [Apple command-buffer guidance](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/CommandBuffers.html)
  recommends the fewest submissions that keep the GPU fed. It describes the same
  starvation-versus-submission-cost tradeoff our threshold experiment measures.
- [Mesa issue 320](https://github.com/iXit/Mesa-3D/issues/320) fixed stateblock aliasing
  that zeroed character material data. It is a correctness reference, not FPS evidence.
- [DXVK batching option](https://github.com/doitsujin/dxvk/blob/master/dxvk.conf) and
  [batcher source](https://github.com/doitsujin/dxvk/blob/master/src/d3d8/d3d8_batch.h)
  show a specialized approach for compatible tiny draws. Prior local batching
  conclusions were explicitly superseded in PERFORMANCE.md; do not revive the
  broad instancing proposal from draw-count ratios alone. Old DXVK timings also
  cannot establish the cost split in the current mtld3d renderer.
- [DXVK FFXI issue 5839](https://github.com/doitsujin/dxvk/issues/5839), August 2026,
  discusses direct D3D8 support and a HUD sampler/filtering correction. It is useful
  for compatibility reference, not evidence that replacing our renderer is faster.
- [Windows player report, September 2024](https://www.vogons.org/viewtopic.php?t=102459)
  describes mostly 60 FPS with dips into the 40s during busy FFXI combat. This is
  anecdotal and lacks a matched workload; it does not establish stable 120 FPS.

No new renderer optimization or 120-FPS result is claimed by this checkpoint.

## Scope update

The user ruled out individual addon tuning as a distraction from general FFXI-on-Mac
performance. The next campaign keeps the full addon setup fixed and prioritizes
renderer scheduling, character-processing attribution, and shared runtime overhead.
Reduced-addon runs are reserved for diagnosis if needed; no per-addon tuning campaign
is planned. A Lua execution finding would motivate a runtime-wide investigation.

## Resumed campaign: crowded-frame synchronization

All runs below used the same build-24 renderer bytes, full boot script, 4096-square
background, graphics profile, shader seed, and corrected flat-ground fixture.
The screenshots now show the full formation on the forecourt. Numeric details and
renderer identities are in `benchmarks/2026-09-05-crowd-readbacks.json`.

| Run | submitDraws | Empty FPS | 16 identical | 32 identical | 32 mixed |
| --- | ---: | ---: | ---: | ---: | ---: |
| submit-a14 | 0 | 33.596 | 22.861 | 17.628 | 16.332 |
| submit-b15 | 512 | 31.069 | 20.625 | 15.230 | 14.959 |
| submit-a16 | 0 | 26.032 | 17.768 | 13.301 | 13.457 |

The baseline repeat also slowed. The A/B/A sequence is inconclusive, so early
submission remains disabled. All three had zero logged live shader compilations.
A short host check during the following diagnostic observed substantial CPU use
in WindowServer, MacsyZones, and the recorder's own nettop process. Memory pressure
was normal, swap usage unchanged, and pmset reported no recorded thermal warning.
The other applications were left alone. The stress suite now omits nettop unless
`--network` is requested and records the selection. Its first attempt failed at
argument parsing before launch; the missing forwarding flag was corrected. The
next live run verified that no network.csv was generated and restoration passed.

### Readback and guest profile

`profile-17` enabled existing readback/GPU trace targets and the guest sampler.
It followed the thread executing FFXiMain, Addons, and the renderer. The finalized
profile covered 274.5 of 278 seconds, about 98.7%, with no dropped samples. Scene
analysis uses two complete ten-second sample windows per phase. The pinned range
selected the useful thread; it must still not be described as FFXiMain's image base.

All observed lockable readbacks were 16x16. Excluding one second at each phase
boundary, the summed synchronous flush-plus-read timings divided by measured frame
count were approximately 16.4 ms/frame empty, 27.5 with 16 characters, 38.8 with 32
identical characters, and 38.5 with 32 mixed characters. These are diagnostic sums,
not the sum of percentile values or independent CPU/GPU time. Trace overhead is
included. Corresponding guest-sample shares in psynch_cvwait plus ulock_wait2 were
40.5%, 45.8%, 48.35%, and 47.8%. The waits alone do not identify their caller, but
the independently timed synchronous readback path accounts for substantial wall time.

`dump-19` captured exactly three frames at the 32-character phase. It recorded
6,569, 6,575, and 6,566 draws, and 49 total 16x16 StretchRect/readback preparations.
One representative frame had 16 readbacks. Before each, two draws wrote TextureId(10)
using the shared scene depth, a third draw sampled that texture into TextureId(27)
at 16x16, and StretchRect copied it to a lockable standalone surface. The first two
draws select vertex diffuse color: one has depth disabled and the other enables the
depth test without writing depth. This resembles a visibility mask/readback sequence;
its exact game purpose is inferred, not yet confirmed by a caller disassembly.

The source is rewritten before each readback. Returning a cached previous result
would therefore change semantics. The scene-depth dependency also means that a
selective flush cannot simply ignore all earlier scene rendering.

The next targeted renderer experiment should append the readback blit to the producing
submission and complete the CPU request after that buffer finishes. Current code first
blocks until the encoder commits the rendering, then creates, commits, and waits for
a separate readback command buffer. Combining them may remove repeated submission and
handoff overhead while preserving current pixels. This requires explicit lifetime and
ordering tests for render targets, copies, LockRect, and later draws; no such native
change has been implemented or enabled yet.

The dump run, with nettop omitted, measured 34.385/23.236/17.898/18.562 FPS across the
four phases. Do not attribute that recovery to nettop alone: host drift and the
three-frame diagnostic dump prevent a controlled performance claim.

Every completed run restored 44 file states and launcher preferences and left Docker
unchanged. The installed application remains build 24. Stable 120 FPS is not achieved.
