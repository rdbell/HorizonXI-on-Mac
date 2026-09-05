# mtld3d performance experiments

The September 5 investigation uses mtld3d v0.8.0, commit
`ea1b1ca3e584917a460c79aac8916d8084099fb4`, with crosire's D3D8-to-D3D9 converter.
Tests run on an Apple M2 Max with macOS 26.5. Game experiments use only the local
LandSandBoat server and its test character. Each game run is limited to 420 seconds;
Wine conformance subtests are limited to 180 seconds.

## Characters rendered black because omitted vertex colors became zero

An F12 dump showed that the character's vertex declaration contains positions, normals,
and texture coordinates, but omits COLOR0 and COLOR1. Lighting and COLORVERTEX are enabled.
The selected diffuse and ambient sources are COLOR1, and the specular source is COLOR2.
The material itself is valid, with diffuse components of 0.5 and ambient components of 1.0.

mtld3d's fixed-function shader emitter selected zero for a requested color omitted from an
explicit declaration. D3D9 uses the corresponding material constant in this case. A color
that is declared on an unbound stream is a separate case and still reads zero.

This distinction agrees with [DXVK's material-source masking](https://github.com/doitsujin/dxvk/blob/v1.10.3/src/d3d9/d3d9_device.cpp#L6590).
Wine's `test_color_vertex` declares COLOR elements on unbound streams. Its expected zero
values do not describe declarations that omit those elements. The material-zero state-block
issue in [Mesa issue 320](https://github.com/iXit/Mesa-3D/issues/320) was a useful lead, but
the captured mtld3d materials are nonzero and identify a different mechanism.

`patches/mtld3d-0.8.0-material-fallback.patch` removes the incorrect declaration-origin
distinction from the layout, shader key, and material resolver. Shader-cache schema 68
invalidates previously emitted shaders. Two pixel regressions exercise both color selectors
and all four material components, covering omitted and declared-but-unbound colors.

Before the fix, the omitted-color test rendered transparent black where it expected opaque
red. The unbound-stream control passed. Both tests pass after the fix.

`patches/mtld3d-0.8.0-ff-diagnostics.patch` independently extends the existing three-frame F12
dump with fixed-function keys, material colors, FVF, and stream-0 stride. It adds no work
unless a frame dump is active.

## Building and checking

Apply either patch to the pinned source checkout. Follow mtld3d's build instructions with
Rust 1.97.1 and an isolated Wine SDK. `make install` must target the isolated SDK, since it
replaces the renderer inside that Wine tree. Also apply the unaligned-lock patch below when
using a build with debug assertions enabled.

```sh
git checkout ea1b1ca3e584917a460c79aac8916d8084099fb4
git apply /path/to/mtld3d-0.8.0-material-fallback.patch
git apply /path/to/mtld3d-0.8.0-ff-diagnostics.patch
make RUST_STABLE=1.97.1 WINE_SDK=/path/to/isolated/wine check test
make RUST_STABLE=1.97.1 WINE_SDK=/path/to/isolated/wine conformance
make RUST_STABLE=1.97.1 WINE_SDK=/path/to/isolated/wine PROD=1 bundle
```

Use a private `WINEPREFIX` as well. If a prefix predates installation of either PE
architecture, update it with `wineboot -u` or install the bundle's matching prefix markers.
Otherwise the 64-bit test leg can fail before running with `Library mtld3d.dll not found`.

Validation so far:

- `make check` passed, including formatting, clippy, audit, and documentation.
- `make test` passed 1,035 core tests, 202 shared tests, and 442 rendering tests on each
  architecture. Per-test output was checked, including both new tests on both architectures.
- Full conformance ran on both architectures with the installed runtime's isolated SDK.
  It hit a 180-second device-test timeout and 13 visual sites beyond the repository baseline.
  Stateblock and D3D9Ex results matched the baseline.
- The CI-pinned `cx-26.3.0-2` SDK on a fresh prefix gave the same i686 result. Its release
  archive SHA-256 is `5348938761dfe7912289ef55950e2795bcda2f37dfb557e723211cb27d7099d6`.
- An unmodified v0.8.0 release, installed into that private SDK and verified by DLL hashes,
  produced the identical 234 visual failures at identical sites. The patched build adds no
  visual-conformance failures on this machine. The device-test timeout remains unresolved;
  the upstream baseline has not been rewritten to hide it.

The corrected production build also renders Hxitest's skin, clothing, textures, and lighting
at character selection and in-world on the local LSB server. The first town capture measured
123.75 FPS in Markets and 110.49 FPS in Mines at the existing 4096 x 4096 background setting.
Those are preliminary results: the client-only heading setter did not persist, so the
camera must be fixed before comparing renderers. Neither scene established stable 120 FPS.

The patch remains experimental. The identical visual-conformance failures establish that
this fix did not introduce those failures; they do not establish complete D3D9 conformance.

## First comparison with fixed camera positions

Server-authoritative `setPos` rotation followed by the Home camera reset now preserves the
same headings in both renderers. Screenshots match the Markets bridge view and the Mines
entrance tunnel. The tunnel is a light scene, not a substitute for the open part of town.

These short samples use the same minimal addon boot script, crosire converter, 1024 x 742
window and UI, and `/fps 0`. Each contains 17 complete one-second frame-counter windows
after loading settles. Other saved quality settings are unchanged; this is not a max-quality
profile. All runs verified the loaded renderer hashes and restored the saved installation.

| Renderer | Background | Markets FPS | Mines tunnel FPS | Mines minimum one-second FPS |
| --- | --- | ---: | ---: | ---: |
| DXVK 1.10.3, existing patched build | 4096 x 4096 | 32.330 | 66.025 | 58.652 |
| mtld3d, material fix | 4096 x 4096 | 40.003 | 126.236 | 103.727 |
| mtld3d, material fix | 2048 x 2048 | 43.484 | 141.479 | 105.750 |

The matched 4096 runs favor mtld3d by 23.7 percent in Markets and 91.2 percent in the tunnel.
These are single runs and need repeats. The 2048 result is a resolution-sensitivity probe;
its modest Markets gain suggests CPU work remains a better lead than reducing pixel count.
No sample establishes stable 120 FPS. Even the faster 2048 tunnel run spent 5.87 percent of
measured time below 120 FPS.

## Packed buffer-lock outputs aborted the debug renderer

FFXI supplies a pointer output slot aligned to two bytes when calling vertex-buffer `Lock`.
mtld3d assigned through that pointer directly, which requires four-byte alignment on i686.
Its debug build aborted at `vertex_buffer.rs:812`. Index-buffer `Lock` had the same defect,
including the error paths that write a null output.

`patches/mtld3d-0.8.0-unaligned-lock.patch` makes the existing `OutPtr` wrapper write unaligned
storage and uses it in both buffer Lock methods. The wrapper creates no reference to the
output, so its constructor can accept unaligned storage without weakening any downstream
reference invariant. Existing aligned callers retain their behavior. No shader or wire layout
changes are involved.

Both new i686 rendering-suite probes aborted before the fix with the observed alignment
panic. After the fix they pass on both architectures, including successful locks,
invalid-range null outputs, and untouched neighboring bytes. A shared-unit regression checks
the same byte-storage boundary. `make check` and all 2,126 tests pass. Full conformance ran
on both architectures; completed subtests have identical failure sites and counts to the
material-only build, and each device subtest retains the existing 180-second timeout.

Apply this patch after the material patch so its coverage-document context matches. The
source changes themselves address output alignment independently of the material correction.
