# September 5 performance session

The autonomous session began at 05:00 CST. At about 09:50 the user asked to finish the
current pass-merging comparison and pause. All game runs used local LandSandBoat and Hxitest.
The Docker server was neither rebuilt nor restarted. Stable 120 FPS across representative
game scenes has not been achieved.

Times below are approximate CST, UTC minus six hours. Detailed methods, patches, and
limitations are in [MTLD3D-EXPERIMENTS.md](MTLD3D-EXPERIMENTS.md).

| Time | Work | Result |
| --- | --- | --- |
| 05:00–06:10 | Build a repeatable renderer comparison and harden capture cleanup. | Added real wall-clock deadlines, local-account checks, renderer identity checks, screenshots, complete FPS windows, frozen-counter rejection, and file/preference restoration. |
| 05:30–06:45 | Investigate the black character under mtld3d, using Mesa issue 320 as a lead. | The captured material was valid. The actual defect was treating omitted vertex colors as zero instead of using material constants. Pixel regressions failed before the fix and passed after it; the character now renders correctly. |
| 06:10–06:45 | Check renderer correctness against the test suite and Wine conformance. | Unit/rendering tests passed. Stock and material-patched mtld3d showed the same 234 visual-conformance failures on this machine. A bounded device-test timeout remains unresolved. |
| 06:45–07:05 | Fix the camera, compare mtld3d with DXVK, and probe background resolution. | At a 4096-square background, the early same-view runs measured 40.0 vs 32.3 FPS in Markets and 126.2 vs 66.0 in the tunnel. A 2048-square mtld3d run reached 43.5 and 141.5 FPS. These short runs predate client-clock validation and dipped below 120. |
| 07:05–07:30 | Fix packed output pointers in vertex/index buffer locking. | Debug builds could abort on valid unaligned application pointers. Before/after regressions and both rendering architectures passed after correction. This is a correctness fix, not a measured speedup. |
| 07:30–08:00 | Profile the expensive Markets view and split readback timing. | Found 3,317 draws per frame and a small GPU-to-CPU readback that waits on preceding scene work. Readback was about 15 ms per application frame and encoding about 8.6 ms in the instrumented capture. These timings overlap and must not be added as independent frame costs. |
| 08:00–09:20 | Test submitting work before the full frame is collected. | A 512-draw threshold measured 40.8 FPS Markets / 107.0 tunnel, versus 35.6 / 119.7 at zero. The scene tradeoff kept the option disabled. Tests passed with an aggressive threshold of one draw. |
| 08:30–09:20 | Try dgVoodoo 2.87.4 with DXMT 0.80 and measure paired GPU submissions. | Standalone D3D11 device creation worked in 32 and 64 bits, but dgVoodoo's D3D8 device creation crashed. No game FPS result. Markets GPU work spanned 184 passes before readback and 104 with Present, about 11.0 and 5.9 ms median GPU elapsed. |
| 09:00–09:30 | Repair benchmark clock changes and verify actual scene state. | Forward clock changes could expire the test session and leave the client rendering an old zone. The command now moves backward to noon, and reports verify client time, zone, and effective draw distance. A clean baseline measured 34.2 FPS Markets / 108.8 tunnel. |
| 09:20–pause | Implement and test conservative merging of independent render passes. | The option is disabled by default. All 2,134 unique tests passed, with one Rosetta timeout resolved by a focused retry. The first enabled game run measured 43.2 FPS Markets / 99.7 tunnel with correct screenshots. See the final comparison below. |

The bridge in Markets is the demanding town view. The Mines tunnel is a light scene and
does not represent all of Mines. Most comparisons used distance 20 and a 4096-square
background, with a 1024 by 742 window and minimal addons. Lowering resolution or distance
changes the workload and must be reported separately from renderer improvements.

## Final comparison and pause state

The final pair uses the same production binary and verified camera, clock, distance, and
graphics settings. Each result covers approximately 57 complete seconds after settling.

| Scene | Merging off | Merging on | Average change |
| --- | ---: | ---: | ---: |
| Markets bridge | 34.528 FPS | 43.171 FPS | +25.0% |
| Mines entrance tunnel | 94.922 FPS | 99.720 FPS | +5.1% |

This is one sequential pair. It needs repetition before adoption, and the tunnel's minimum
one-second FPS and worst per-window p99 were worse with merging. The option remains off by
default. Both views passed screenshot review. See the
[numerical reports](benchmarks/2026-09-05-pass-merge.json).

The first control attempt was excluded after a menu OCR timeout caused by the pointer
covering the selected button. The runner's footer fallback now covers that observed case
without relaxing character identity or live-frame checks. Its regression and the affected
tooling suites passed all 24 tests.

At the pause point, the game, Wine, launcher, and profiling processes are closed. The final
run restored all 43 tracked file states and launcher preferences, confirmed the Docker
identities and start times were unchanged, and reset normal server time after measurement.

No newer dgVoodoo experiment was started after the pause request. Versions 2.79.3 and 2.81.3
were downloaded from a community preservation mirror and retained for a future isolated
smoke test, with source URLs and hashes. They have not been executed.

The next useful step is to measure how many Metal passes merging actually removes, then
repeat the comparison and check the open town and outdoor scenes. A clock-verified comparison
at ordinary draw distance is also still needed. The scheduling options remain experimental.

Verified changes and renderer source patches are published on HorizonXI-on-Mac's
`development` branch. mtld3d's configured remote belongs to upstream, so its modifications
are preserved as patches in Horizon rather than pushed to that remote. Benchmark binaries,
logs, screenshots, and private rollback snapshots remain outside Git under
`benchmarks/20260905-050000-autonomous`. Private snapshots must not be published.
