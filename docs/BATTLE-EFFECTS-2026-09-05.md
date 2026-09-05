# Repeated battle-effect freezes

The local RDM99 test reproduced repeated freezes after Chainspell. Enforcing normal
data-execution protection in the game process removed the long frames in both the
temporary experiment and the rebuilt renderer. This is the same Wine compatibility problem previously corrected
in the fork's DXVK build, which was absent from mtld3d.

The tests use Local LSB in Docker and Hxitest only. Each run has a 420-second game deadline,
followed by bounded cleanup. The server was not rebuilt or restarted. Captures, screenshots,
and private rollback files are under `ximac/benchmarks/20260905-battle-effects`, outside Git.
The [sanitized numerical reports](benchmarks/2026-09-05-battle-effects.json) are committed.

## Workload and results

The character changes to RDM99, learns all spells, and stands at a fixed position in Bastok
Mines with a reset camera. After an idle interval, each of three rounds resets recasts,
restores MP, clears the prior self buffs, activates Chainspell, then casts Blaze Spikes,
Ice Spikes, Shock Spikes, Stoneskin, Blink and Aquaveil. The next spell waits for the prior
server completion plus three seconds. Every reported round requires one successful
Chainspell and all six buffs applied once. A no-effect response or missed completion fails
the workload. No mobs are spawned in town.

Graphics match the user's profile: 1882 by 1058 window and menu, 4096-square background,
and draw distance 20. All personal addons remain loaded, including XIUI and Minimap.
The renderer uses pass merging, no early submission, `/fps 0`, and a frozen warm shader
cache. Detailed readback/GPU logging is enabled equally in these diagnostic comparisons;
the numbers are not a general gameplay FPS estimate.

| Phase | Clean baseline FPS | Temporary correction FPS | Baseline worst frame | Corrected worst frame | Frames over 500 ms, before / after |
| --- | ---: | ---: | ---: | ---: | ---: |
| Idle | 24.77 | 24.42 | 77 ms | 98 ms | 0 / 0 |
| Round 1 | 19.32 | 22.13 | 1,268 ms | 99 ms | 5 / 0 |
| Round 2 | 18.97 | 22.48 | 1,260 ms | 86 ms | 5 / 0 |
| Round 3 | 18.58 | 22.70 | 1,259 ms | 87 ms | 5 / 0 |

The clean baseline is `full-04`; the temporary correction is `nx-06`. Idle performance
barely changes. The useful gain is removal of the repeated one-second freezes, with all
18 spells and three Chainspells still confirmed by the server.

The final `baked-07` run used the rebuilt renderer without the temporary diagnostic
switch. Its rounds measured 21.42, 23.05 and 23.58 FPS; worst frames were 97, 80 and 93 ms.
All 18 spells and three Chainspells applied, and no measured round contained a frame over
100 ms. There were no GPU errors. The normal renderer entry point logged the automatic
policy change from 2 to 9. Screenshots retained the character, scene, and full addon UI.

## Diagnosis

The first sampler followed AppKit's window event thread. Its 99.8% sample coverage did
not measure the game loop and cannot establish what the game was doing. The launcher now
limits default discovery to 32-bit addresses and preserves an explicit `X87_GUEST_RANGE`.
The corrected capture followed a thread executing FFXI, addons, and the renderer.

The explicit range in `full-05` and `nx-06` was `0x10000000-0x10bdf000`. The actual
FFXiMain image was relocated to `0x1f30000`; polcore occupied the requested range. Thus
this range found the useful thread through polcore, not through FFXiMain's preferred
image base. Check actual module maps and samples before reusing a pinned range.

During the freezes, `FFXiMain.dll+0x4294f` dominated the guest samples. An existing runtime
dump with matching PE timestamp and image size places this in a vertex-buffer fill after
a buffer lock. The installed DLL is packed and cannot supply that code directly.

The first several seconds after Chainspell had roughly 28,351 faults and 142,868 Mach
system calls per second. The temporary correction reduced those medians to 9,795 and
13,071. These are process counters across the three round-start intervals, not independent
frame costs. Disk reads did not show a corresponding reduction.

The diagnostic queried `ProcessExecuteFlags=2`, Wine's execute-everywhere mode, then
successfully changed it to 9, disabling execution on ordinary data pages permanently for
that process. Explicitly executable code pages remain executable. This avoids Rosetta's
expensive handling of writes to pages Wine unnecessarily made executable. The existing
[DXVK diagnosis](PERFORMANCE.md) documents the same mechanism and its offline reproducer.

`full-05` had two GPU errors before the measurement phases. It is retained for profiling,
but the FPS table uses the clean `full-04` run. `nx-06` had no GPU errors. Neither live
shader compilation nor the logged GPU readback waits explain the repeated 1.26-second
frames in the clean baseline.

## Implementation and earlier attempts

`patches/mtld3d-0.8.0-enforce-nx.patch` applies the correction at `Direct3DCreate9`, before
renderer buffers are created. A thread-safe one-time guard prevents repeated calls; the
64-bit build keeps its existing execution policy. `MTLD3D_ENFORCE_NX=0` permits an isolated
control run. The policy query and result are logged. No game executable is modified.

The independent `scripts/tools/d3d9-nx-test.c` regression first puts a fresh 32-bit Wine
process into mode 2. The corrected renderer changes it to 9 and rejects a later attempt
to restore mode 2. With the opt-out, it remains in mode 2. Both cases passed. Thirty-three
existing buffer and fixed-function lighting tests passed, as did both PE clippy checks.

Build 24 was packaged through `app/bundle.sh` and installed into
`/Applications/FFXI-on-Mac.app`. Its signed renderer files exactly match the measured
candidate, and the installed launcher matches the packaged executable. The application
passed deep signature verification. The build 23 rollback copy is
`ximac/benchmarks/20260905-battle-effects/rollback-build23/FFXI-on-Mac.app`.
The last run restored the full game configuration, shader cache, tracked resources and
launcher preferences, confirmed Docker was unchanged, and left no related processes.

Earlier attempts are retained rather than mixed into the comparison:

- `full-01` reached character selection but OCR could not reliably read the small text.
  A native-resolution crop now reads the character identity and account count reliably.
- `full-02` lowered menu resolution to 1024 by 576 while keeping the background at 4096.
  It failed during GPU startup with a black screen and supplies no FPS result. This single
  run does not prove the changed menu resolution caused the failure.
- `full-03` reproduced long frames, but missed casts and no-effect Stoneskin responses
  invalidated its matched workload. Shorter GM commands, three-second command spacing,
  completion-driven casting, and response checks fixed the benchmark.

The minimap's border and markers render while its map image remains transparent. That
problem and remaining crowded-city stutters are separate unresolved observations. This
spell test does not establish stable 120 FPS or cover every battle effect.
