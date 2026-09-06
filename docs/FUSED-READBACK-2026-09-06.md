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
