# Performance push, 2026-09-28

Six-hour push on the development stack (cx-26.3.0-6, mtld3d, native window, shared scanner on).
Local Docker LSB with Hxitest only. M2 Max, macOS 26.5. Inputs: the September 14 frozen full boot
script (the user's own set: about 40 add-ons and 11 plugins), frozen shader seed, 4096 background,
draw distance 20, noon. Scenes: `crowdsteady` (32 mixed characters, 96 s hold) and `lightsteady`
(the same Mines spot with no crowd). The host was noisy (airportd near 100% CPU, a VM running), so
renderer decisions use within-run ABBA switching (8-second blocks at Present, harness window
selector) rather than separate launches. Raw runs are in `ximac/benchmarks/20260928-perf-push`.

## Result

| Change | Light scene | Crowd | Evidence |
| --- | --- | --- | --- |
| Submit every 64 draws at render-target changes (`render.submitDraws=64`, `render.submitAtPassBoundary=true`), replacing 512 mid-pass | **+12.2% FPS, p99 -9.5%** (38.5 -> 43.2) | +2.5% and +0.9% FPS in two runs; p99 -1.0% and +0.1% | ABBA `pb64-ab-light`, `pb64-ab-1`, `crowd-ab-512v64-r2`; normal-launcher candidate runs: light 42.9, crowd 30.1, arrivals +5-12% per phase against 2026-09-26 |
| View inverse without the `fmaf` libcall (array sums, as `view_transform_point` already does) | CPU only | ucrtbase 11.0% -> 8.4% and d3d9 10.1% -> 9.3% of the game thread | profiles `base-profile`, `fma-profile` |

In the Firaga battle scenario (20 casts on 8 mobs, ABBA from frame times) the new schedule measured
-1.55% FPS with better tails (p99 37.0 -> 35.4 ms, worst frame 74.8 -> 68.6 ms).

Both ship in the vendored mtld3d PE build and the launcher default. mtld3d checks: 1040 core and 4
types unit tests, PE clippy clean, no new audit findings, full e2e suites on i686 and x86_64 (454
passed each; one test that fails identically on unmodified 930087e excluded). Submission only changes when
work reaches the GPU, never draw order or content (new e2e regression
`pass_boundary_submission_keeps_ping_pong_targets`). The view inverse is consumed only by user clip
planes; all 18,378 draws in a three-frame crowd dump have `clip_plane_count: 0`, so FFXI's output
cannot change. (The first candidate used a bit-exact inline fused multiply-add, verified on 2
million cases against hardware FMA; it needed new lint suppressions the mtld3d conventions reject,
so the unfused form, already the codebase's idiom for this, replaced it with the same CPU saving.)

## What limits the frame

Crowd frame (about 34 ms, F12 dump of one frame): 6127 draws and 1360 render-target switches. FFXI
draws each character piece into the 4096 scene target (A, with depth) and into a 4096 colour-only
silhouette target (B), then composites B onto A (blend ZERO / INVSRCCOLOR: character shadows).
B is cleared 34 times a frame. mtld3d's pass merging reduces 1351 passes to about 96, but the
per-character B -> composite dependency cannot be merged away. GPU time is about 20 ms a frame at
roughly 0.25 ms per 4096 pass. Seven 16x16 readbacks follow the world and all characters; each
first renders into a 4096 target that carries the scene depth, and the game reads the result at
once. So the first readback waits for almost all scene GPU work, and everything the CPU does after
it runs while the GPU idles.

- **CPU and GPU are balanced in the crowd.** Removing ~37 add-ons cut the game thread's own work
  by about a third but raised FPS only 1.9% (the thread then waited 61% of the time); a 2048
  background (quality change, diagnostic) raised it 12.6%. Neither side alone is the limit.
- **Ashita's add-on dispatch is the largest CPU cost.** Addons.dll raises `d3d_dp`/`d3d_dip` for
  every draw call and, for every loaded add-on, builds the event name as a `std::string`, FNV-hashes
  it and probes that add-on's event map (Addons.dll+0x9b4250 hash, +0xbbe80 compare, `memmove` via
  ucrtbase). With ~40 add-ons that is 20-35% of the game thread whether or not an add-on handles
  the event. In the light scene, the full set measured 37.6 FPS and three add-ons (aspect,
  drawdistance, fps) 50.3 FPS: about 0.18 ms a frame per loaded add-on. There is no Ashita setting
  for it; fewer add-ons is the only lever and is the user's choice.
- FFXiMain is 17-18% of the thread; its hottest loop is x87 triangle/plane intersection code.

## Tried and not adopted

| Experiment | Result |
| --- | --- |
| Defer the 512-draw split to the next render-target change (no threshold change) | -0.45% crowd; no effect |
| 16 draws at boundaries instead of 64 | light +2.7%, crowd **-16.8%** (213 submissions/frame) |
| Additional split when the GPU has retired everything sent | rule never fired (always one submission in flight) |
| Fold reused full-viewport clears into `loadAction=Clear` (September 14's rejected patch) | +0.2% crowd, GPU per large command buffer -5.7%; neutral, the old -6..-11% did not reproduce |
| Small-copy fast path in Wine's ucrtbase `memmove` | correct (453,440 overlap checks) but no faster (5 ns per call either way) |
| Background GPU keepalive (clock-scaling hypothesis) | -0.9% |

## Other observations

- The one slow frame a minute (+15-20 ms) seen in every run lands at hh:mm:45 wall-clock (a smaller
  one near :09.8). A native 1 ms sleep loop with no game running saw host-wide wake-up delays at the
  same seconds, so it is this host (a periodic system task), not the game, Wine or mtld3d.
- After the change, the light-scene game thread is ~84% CPU work (Addons.dll 31%, FFXiMain 21%,
  ucrtbase 9%, d3d9 8%) and waits 16% (was 25%); FFXiMain's hot loop is x87 geometry code. The
  x87sidecar options that would speed it (`X87_FAST_ROUND`, `X87_ENABLE_FMA_CONTRACT`) change
  rounding and were not used.
- Plain `menu-run.py` (no scenario) cannot detect the rules screen under mtld3d: it reads the
  DXVK-era frame log, which mtld3d does not write. Use `renderer-run.py` scenarios.

- Startup hang: 2 of about 20 launches stopped after the first Present with a black window
  (last line `reject StretchRect: src/dst not D3DPOOL_DEFAULT`). Seen with and without the
  submission change. The harness now keeps a native `sample` of the hung process
  (`hang-<scene>.sample.txt`) before cleanup.
- One run showed the game drawn at half size in the window corner after two drawable
  acquisition stalls (343 and 968 ms). Known behaviour, not a regression: it happens when the
  monitor disconnects and reconnects, and dragging or resizing the window corrects it. That run
  (`addoncost-1`) is excluded.
- `render_target::successive_submits_preserve_up_data_across_readback_continuations` fails on the
  unmodified 930087e source too.

## Tooling

- `scripts/harness/guest-hotspots.py`: per-module, per-offset, caller and PDB-function shares for
  one stress phase of a `--level standard` run.
- `scripts/harness/mtld3d-ab-report.py`: report for diagnostic builds that log `mtld3d::ab`
  block markers (8-second ABBA at Present).
- `addoncost` stress scenario: cumulative add-on and plugin unloads under the steady crowd.
- `renderer-run.py`: `--submit-draws` accepts 16-1024 and `--pass-boundary`; the spawn check
  verifies `render.submitAtPassBoundary` (absent means false for older packages).
- `menu-run.py`: native sample of a live game on any scene timeout.
