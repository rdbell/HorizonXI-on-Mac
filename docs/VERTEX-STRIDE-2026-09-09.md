# Overlapping vertex streams

An intermittent yellow/orange triangle was reported during play. The saved renderer
log contains `stream stride 36 below the consumed declaration extent 44; layout
widened to the extent`. That warning identifies a real vertex-fetch bug, but it was
logged only once and has not been correlated with the reported frame.

## Cause and correction

mtld3d changed the GPU's vertex stride from 36 to 44 without repacking the vertex
buffer. Vertices stored at offsets 0, 36 and 72 were fetched at 0, 44 and 88 instead.
The source comment said Metal rejected overlapping attributes. A native Metal probe
on the Apple M2 Max, with API validation enabled, accepts stride 36 with extent 44
and reads all positions and overlapping attributes correctly. Widening the same
buffer to stride 44 produces incorrect positions.

The correction preserves every nonzero application stride. Bound buffers retain
their existing direct GPU path. Their tracked read range includes any attribute
tail beyond the last stride, protecting pending draws against overlapping uploads.
Inline draws copy the same caller-provided byte range as before and zero-pad the
final attribute tail. Ordinary inline draws keep the existing allocation path.

This follows the structure of [DXVK's inline vertex-buffer handling](https://github.com/doitsujin/dxvk/blob/v1.10.3/src/d3d9/d3d9_device.h#L985).
No attributes are removed, no render-state heuristic is added, and no shader source
or shader-cache schema changes. The existing zero-stride constant-stream behavior
is preserved.

The candidate starts from build 24's bundled source patch on mtld3d commit
`ea1b1ca3e584917a460c79aac8916d8084099fb4`. It excludes the later experiments in the
working renderer checkout. Only the D3D9 renderer DLL needs to be replaced; the Wine
shim, signed Unix renderer and existing performance settings can be retained.

## Verification

Five pixel regressions cover overlapping bound streams, signed base vertices,
stream offsets, inline indexed and non-indexed drawing, triangle fans, instance
step rates, fixed-function zero-filled tails and a tail upload after a queued draw.
Core tests cover read-range overflow and reused scratch storage.

All five pixel tests fail on the exact D3D9 DLL from the installed build 24 and
pass on the production candidate DLL with the installed Wine shim and Unix
renderer. Reference comparisons read pixels before Present, since a DISCARD
backbuffer has undefined contents after presentation.

`make check` passed, including formatting, clippy, the conventions audit and docs.
`make test` passed 1,045 core/type tests, 203 shared tests and all 452 rendering
checks on each PE architecture. All five new pixel tests pass on both architectures.
Metal API validation was enabled.

Wine's stock D3D9/OpenGL renderer passes four of the five new tests. Its instance
step-rate change renders all four positions where rate 2 should repeat only the
first two. That reference limitation is recorded separately from the matching
vertex-addressing and zero-padding results; it is not counted as a passing test.

The full conformance command ran on both architectures and returned nonzero against
the older checked-in baseline. The i686 visual leg has 236 failures and x86_64 has
234; stateblock has none and D3D9Ex has one on both architectures. The device legs
hit the existing bounded window-management timeout, so their counts are incomplete.

A separate visual comparison used the exact installed and production candidate
i686 DLLs with the same Wine SDK, prefix, installed shim and Unix renderer. Both
report exactly the same 236 failing assertions, including the actual versus
expected pixel values. The additional failures versus the older reference are
already present in build 24. No conformance baselines were rewritten. This is
evidence against a new visual-conformance regression, not a claim of full D3D9
conformance.

The final local LSB baseline and candidate runs completed in 272 and 276 seconds
to the last scene marker, with a 360-second game limit. Both confirmed noon,
18:07, 00:07, 06:07 and storm at 06:16 in North Gustaberg. Graphics settings,
boot script, scenario source and effective draw distance 10 matched. Corresponding
screenshots were reviewed; recorded positions match within 0.001 units vertically.

| Settled scene | Build 24 FPS | Candidate FPS |
| --- | ---: | ---: |
| Noon | 26.15 | 27.53 |
| Sunset | 25.66 | 27.13 |
| Midnight | 25.58 | 29.05 |
| Dawn | 24.77 | 26.74 |
| Storm | 24.50 | 28.98 |

These are roughly seven-second samples after each checkpoint, from one paired
local rendering check. They do not establish a sustained FPS improvement or
replace the approved gameplay baseline. Neither run logged a renderer error.
The baseline logged the widened-stride warning; the candidate did not. A visible
secondary improvement is that the minimap's map image renders in all five candidate
screenshots, where the baseline's border surrounds a transparent interior.

Both runs restored 44 saved file states and launcher preferences, verified that
Docker IDs/start times were unchanged, and left no related processes running.
See the [recorded checks and measurements](benchmarks/2026-09-09-vertex-stride.json).
The intermittent screenshot itself still requires reproduction or user retesting;
a corrected compatibility defect is not proof of that attribution.

## Installation

Installed as version 3.8 build 25, retaining the existing performance settings,
Wine shim, signed Unix renderer and targetguard fix. The only runtime component
changed is D3D9; the launcher executable matches build 24 after removing its code
signature. Source patch, manifest, bundle version and app signature were updated.
The installed bundle's signature and every renderer hash verify.
An additional local LSB character-selection run through the installed app verified
the loaded production DLL and normal mtld3d configuration. It restored all saved
settings and left the game closed.

The full pre-change app is retained outside Git at
`benchmarks/20260909-triangle/pre-stride-build24.app`. The earlier approved
`benchmarks/known-good-20260906-build24/` snapshot is also untouched. Restore an app
only with game and launcher closed.

## Repeatable local lighting check

The `lighting` scenario in [the renderer harness](../scripts/harness/README.md#local-renderer-comparisons)
uses the local test character, a fixed North Gustaberg position, noon, sunset,
midnight, dawn, thunderstorms, and a final clear-weather reset. Saved graphics,
boot scripts, shader cache, account selection and renderer files are restored.

Setup attempts revealed two invalid measurement conditions. The old outdoor
anchor reused an arrival position for the other Gustaberg zone. Also, changing the
server clock alone left the client at noon. Sending a separate reload one second
later produced a client command error; the server audit confirmed that those
reload commands never arrived. The final sequence combines clock changes and
same-position zoning in a single GM command. Client clock markers and screenshots
must agree before a phase is counted. The earlier setup captures are excluded.

## Rules check

No new runtime key, environment control, static, wire field, dependency, derive or
lint suppression. Stream and scratch logic remain in the host-testable core. The
draw layer only binds the corrected layout and existing frame-owned storage. A
small test helper reads before Present to allow comparison with reference D3D9.
The stream coverage row accompanies the tests. Source and binaries are delivered
through the launcher development fork; mtld3d's upstream remote is not a push target.
