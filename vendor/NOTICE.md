# vendor — third-party binaries

Redistributed so the Metal renderer and x87 acceleration work without a build on the user's Mac.
All are freely redistributable. Local modifications are listed below and in `../patches/README.md`.

| File | Upstream | Version | Licence |
| --- | --- | --- | --- |
| `d3d8to9.dll` | [crosire/d3d8to9](https://github.com/crosire/d3d8to9) | v1.15.1 | BSD 3-Clause |
| `dxvk-1.10.3-x32-d3d9-horizonxi.dll` | [doitsujin/dxvk](https://github.com/doitsujin/dxvk) `x32/d3d9.dll` plus the project patches | v1.10.3+ | zlib |
| `mtld3d/` | [athei/mtld3d](https://github.com/athei/mtld3d) `ea1b1ca3` plus the included `source.patch` | 0.8.0+, built 2026-09-05 | zlib, see `mtld3d/LICENSE` |
| `x87sidecar-coop` | [athei/x87sidecar](https://github.com/athei/x87sidecar) `010f50a` plus `x87sidecar-upstream-integration.patch` | built 2026-09-12 | MIT |
| `x87sidecar_entitled` | [athei/x87sidecar](https://github.com/athei/x87sidecar) `010f50a` plus `x87sidecar-upstream-integration.patch` | built 2026-09-12 | MIT |

## dxvk-1.10.3-x32-d3d9-horizonxi.dll

This is DXVK 1.10.3 with the cumulative HorizonXI and exact readback-fence patches, the
MoltenVK upload-buffer prefault, the NX enforcement that removes the scene-load stall under
Rosetta, and the opt-in diagnostic probes listed in `../patches/README.md`. The prefault and NX
enforcement are active in normal play. The probes do nothing unless the launcher arms a
performance capture. SHA-256 `5164ce8dae9f1defaf03c6bfad67779944884854be5df4b01da1c7519371e9b6`,
built 2026-09-03 from the patch stack in `../patches/README.md`, which was verified to reproduce
the build tree exactly.

## mtld3d

The production build includes the FFXI material fallback and unaligned buffer-lock fixes,
diagnostic probes, optional independent render-pass merging, and reuse of identical generated
shader code across rendering states. The shader reuse change preserves schema 68 and existing
warmed caches. It is a modified upstream
build. `mtld3d/build.json` records the base commit and every runtime file's SHA-256;
`mtld3d/source.patch` records the complete source diff used to build it. The renderer selector
enables pass merging and keeps early submission disabled. The Wine shim, Unix library and
both prefix markers must accompany the native D3D9 DLL. See `../docs/MTLD3D-EXPERIMENTS.md`.

## x87sidecar-coop

This is the unentitled cooperative binary used by the patched Wine runtime. It is built from
`rdbell/x87sidecar@7b4db46cc1ec3878192c82981e5948955bbd7e4b`, based on upstream `010f50a` with the PR #31
automatic profiler PID suffixes, our optional sticky sampler, and cheaper native-state boundary
conversions that preserve the upstream correctness fix. `x87sidecar-build.json` records
its binary and source-patch hashes. `../patches/x87sidecar-upstream-integration.patch` is the
complete source difference from that upstream commit.

Upstream supplies the native x87 state restoration, FPATAN signed-zero correction, tracing,
and Tahoe detach fixes. The fork includes the measured native-boundary optimization; it does not disable state
conversions. The benchmark evidence does not establish a reliable gameplay FPS percentage.
The launcher supplies base
filenames; the sidecar appends `.<target-pid>` to each profiler output. `%p` is now literal text.
Sticky sampling continues following the selected thread through DLL and runtime calls.

## x87sidecar_entitled

This is the entitled build of the same source commit and cumulative patch as the cooperative
binary above. Both vendor binaries match the preserved installed app and the final optimized
2026-09-12 x87-boundary test artifacts byte-for-byte. The unsafe conversion-disabled control is
not included. `x87sidecar-build.json` records both identities.

The retained baseline signature carries `com.apple.security.cs.debugger` and
`com.apple.security.get-task-allow`. The normal launcher uses the unentitled cooperative binary.
Ad-hoc app builds preserve those exact signatures. An explicit Developer ID build re-signs
them with the same entitlement set and records both vendor and packaged hashes. The entitled
fallback retains get-task-allow, so this packaging is not claimed ready for notarization.

**Why these exact versions.** DXVK 2.x and 3.x require Vulkan 1.3 and the `geometryShader`
feature. Metal has no geometry shaders, so MoltenVK can never expose one and those releases can
never run on Apple Silicon — 3.0.2 loads, enumerates the M1, and rejects it. 1.10.3 predates that
requirement. Gcenx's macOS repack of 1.10.3 omits `d3d9.dll` entirely, so it has to come from
doitsujin's release.

## dxvk-1.10.3-x32-d3d9-nofog.dll

DXVK 1.10.3 (doitsujin/dxvk, zlib/libpng licence), built here from the v1.10.3 tag with two
patches in `../patches/`:

* `dxvk-1.10.3-build-gcc14.patch` — build fixes only. GCC 14 / mingw-w64 14 no longer include
  `<cstdint>` transitively, and mingw now defines `_D3DDEVINFO_RESOURCEMANAGER` itself, so DXVK's
  old workaround became a redefinition.
* `dxvk-1.10.3-ffp-fog.patch` — the functional change. Fixed-function fog is bypassed, because it
  reads `render_state_t`, the uniform block MoltenVK mis-binds on Metal. See docs/PATHWAYS.md.

Build: `meson setup --cross-file build-win32.txt --buildtype release builddir32 &&
ninja -C builddir32 src/d3d9/d3d9.dll`, then `i686-w64-mingw32-strip -s`.

The unpatched `dxvk-1.10.3-x32-d3d9.dll` is kept beside it for comparison.
