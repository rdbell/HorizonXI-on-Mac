# Wine cx-26.3.0-6

The game runtime moves from athei/wine-build `cx-26.3.0-1` (2026-08-19) to `cx-26.3.0-6`
(2026-09-25, athei/wine `d82e36650b0`). It brings the winemac fixes for per-click stalls in
full-screen Metal games, the arrow cursor flickering over games, races when windows are
destroyed from several threads, and Mission Control on macOS 27, plus no-execute kept on
under Rosetta ([wine-build#3](https://github.com/athei/wine-build/issues/3), which this
project reported).

## What the upgrade needed

- **No Vulkan.** From `cx-26.3.0-2` the runtime is built without Vulkan: `winevulkan` and
  `vulkan-1` are absent. The DXVK and wined3d-Vulkan pathways cannot run, so mtld3d becomes the
  default renderer and those two are retired (see `Renderer.swift`). OpenGL remains.
- **Locale fix rebuilt** from `d82e36650b0`. Stock `-6` still fails 14 of 57 UCRT locale checks
  per architecture; the rebuilt DLLs pass all 57 with the string and misc suites unchanged.
  `msvcrt/locale.c` is byte-identical to the `-1` source. See `WINE-LOCALE-FIX.md`.
- **Native-host driver rebuilt** from `d82e36650b0`. `-6`'s makedep rejects any include before
  `config.h`, so the patch moves `#import <objc/runtime.h>` below it; no other line changes.
  See `NATIVE-GAME-HOST.md`.
- **compatdb rule.** From `cx-26.3.0-3` the runtime's `compatdb.so` prepends its own bundled
  mtld3d to every process's search path. The game then pairs our `d3d9.dll` with the runtime's
  `mtld3d.so` and Metal aborts on the first draw ("vertex attribute index (65537) must be
  < 31"). The launcher sets `WINE_COMPATDB` to keep every process on Wine's own d3d9 tree, as
  `-1` behaved, so the renderer the launcher installs is the one that loads.

Existing installs need the new runtime once: Setup reports the patched game Wine missing and
downloads it (233 MB). The `-1` runtime stays on disk until removed.

## Validation, 2026-09-26

M2 Max, macOS 26.5, local Docker LSB with Hxitest. The `-6` runs used an APFS clone of the
prefix; the `-1` run used the installed app. Same boot script, renderer hashes, graphics
(1882x1058, 4096 background), draw distance 20 and noon clock; mtld3d with the native window.
One run each, so no frame-rate difference is claimed:

| scene | `-1` fps | `-6` fps | `-1` worst frame | `-6` worst frame |
| --- | --- | --- | --- | --- |
| Bastok Markets, settled | 111.97 | 112.69 | 11.0 ms | 19.9 ms |
| Gusgen Mines, settled | 119.96 | 119.86 | 15.3 ms | 27.5 ms |

The harness verified the loaded modules on `-6`: our mtld3d from the app bundle, the rebuilt
native-host `winemac.so`, the locale-fixed `ucrtbase.dll`. The native window attached and
rendering matched `-1`. The native window's title is left-aligned on `-6` instead of centred.

After merging into development, the same scenario on `-6` ran at 111.76 fps in Bastok Markets
and 120.00 in Gusgen Mines (worst frames 19.1 and 13.9 ms), again with the native window
attached and x87 acceleration active. Classic (OpenGL) logged in on `-6` with Wine's builtin
`d3d8.dll`, drew Bastok Mines correctly and held 38-41 fps there at draw distance 10.

Not measured: the click-stall, cursor-flicker and window-race fixes themselves, the Command-comma
panel, HorizonXI, and macOS 27.
