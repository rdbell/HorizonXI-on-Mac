# Launch speed, September 11, 2026

Build 26 keeps one Wine runtime for launch preparation and the game, and skips renderer
setup that already matches. Build 25 took 45.5 and 46.3 seconds to the first visible XI
window. The final launcher candidate took 15.4 and 15.1 seconds. The installed app took 16.9 and 13.2 seconds, averaging 15.0 seconds versus the
45.9-second baseline mean, about 31 seconds or 67% less time. All run records are in [the sanitized measurements](benchmarks/2026-09-11-launch.json).
This is a launch-time improvement, with no in-game FPS or rendering change claimed.

| Implementation | Request to XI window | Launcher preparation |
| --- | --- | --- |
| Build 25, clean baseline repeats | 45.5, 46.3 s | No internal phase logs |
| Use game Wine for launch preparation | 22.4 s | 6.43 s |
| Also skip unchanged registry and renderer writes | 16.7 s | 1.29 s |
| Also skip shutdown subprocesses when no wineserver exists | 15.4, 15.1 s | 0.48, 0.48 s |
| Installed build 26 | 16.9, 13.2 s | 0.49, 0.24 s |

The baseline used the wrapper's Sikarugir Wine for renderer registry commands and the
patched CrossOver Wine for the game. Their `wine.inf` timestamps are 1775860812 and
1787146421. Wine compares that value with the prefix's `.update-timestamp` and reconfigures
when they differ. Switching runtimes caused repeated prefix updates. A prior read-only
inspection found 1,475 Windows system files rewritten during the pre-game gap. Baseline 3
confirmed the prefix timestamp changed during launch; the optimized repeats did not.
Wine's [update logic](https://github.com/athei/wine/blob/cx-26-patched/programs/wineboot/wineboot.c)
is in `update_timestamp` and `update_wineprefix`.

`Install.usingWine` changes the runtime for renderer and PlayOnline registry helpers while
retaining the prefix and game directory. Wrapper repair and isolated third-party installers
keep their original runtime. After Wine exits and flushes its registry, `RendererSetup`
checks every value in the desired registry transaction. If anything differs, it applies the
whole transaction. Unchanged mtld3d DLL files retain their bytes and timestamps; damaged
files are replaced, and symlinks are replaced without writing through into the Wine runtime.
The final helper shutdown remains necessary when helpers have run, because they do not
inherit the game's synchronization settings. The new no-server shortcut applies only when
`pgrep` returns status 1. Errors retain the existing cleanup path.

Measurements used Local LSB in the existing Docker containers, account hxitest and character
Hxitest. No Horizon login was attempted. Each run used the full saved default boot script,
4096 x 4096 background, 1920 x 1080 window/menu, draw distance 10, msync, x87 acceleration,
and the same four build-25 renderer components. No addon was individually tuned. Native
sampling and network sampling were off in accepted timing runs. Each game was bounded to
180 seconds, or 210 seconds for world entry, with captures bounded to 160 or 190 seconds.
Cleanup had its existing separate deadline. Docker was never rebuilt or restarted.

The primary clock starts immediately before requesting `open -a ... --world local --play`.
It includes roughly 1.5 seconds of app initialization and local preflight. It is not the
exact time of a mouse click in an already open launcher. Window detection polls every
0.2 seconds, plus the time taken by the window-query subprocess. Tests began with no Wine
processes; macOS caches were warm. These results do not describe first installation or a
cold reboot. Baseline 1's 52.9 seconds is excluded because compilation overlapped startup.

Two diagnostic runs are also excluded. A Wine process/module trace took 17.0 seconds, and
an immediate six-second native sample took 17.1 seconds. The trace shows about 4.4 seconds
from the first wineboot module to Ashita-cli, followed by DLL loading, injection, and
macOS window-driver initialization. There is a 2.8-second gap between the loader's C++
runtime and the next module. That gap is not yet attributed to a specific function. The
sample shows the original guest thread suspended during injection, while Rosetta's
recursive syscall stacks prevent useful attribution of the injection thread. It does not
prove a deliberate sleep. Upstream xiloader's visible two-second sleep is in its exit path,
not its launch path, and that source is not proof about the installed Horizon loader.

Shader prewarming in ordinary runs was only tens of milliseconds. Ashita's logged core
initialization was about 0.23 seconds in the inspected run. Full-script addon startup delays
our OCR checks after the first window has appeared, so the later rules-screen OCR timestamp
is not an earliest-visibility measurement. The common frame counter, screenshots, module
hashes, and world-entry markers validated live operation. The recorder's missing-DXVK-probe
warning is expected for mtld3d; it is not used to assess launch success. Its Rosetta-blind
rusage CPU figure is known to have a timebase scaling problem and was not used here.

Launch preparation is now under half a second. Another large reduction would require a
specific Wine/injection improvement or keeping a prestarted Wine session in the background.
Background warming could move some cost before Play but would add process lifecycle,
settings, and resource-use concerns. Disabling services, dropping client components, or
bypassing x87 acceleration would trade compatibility or in-game performance for startup.
There is no measured case for those changes here. This is a reasonable stopping point for
the current launcher work, not proof that the measured 13-17 seconds is a universal lower bound. Reopen the
remaining gap when profiling can identify its actual work or a newer runtime changes it.

Standalone renderer tests passed for registry matching/mismatches, missing sections,
escaped values, runtime selection, unchanged-file preservation, corruption repair, and
builtin symlink protection. The release build passed. Python runner/report checks and the
Lua Hxitest-only, command-free login check passed. Full `swift test` is unavailable with
this machine's Command Line Tools SDK because it lacks the XCTest module; the runtime-scope
case is also covered by the standalone Swift test.

Build 26 was assembled from the saved installed build 25 with only the launcher executable,
bundle version, and signature changed. All 26 resource entries, including the renderer,
x87 sidecar, and audio helper, remained identical. Strict deep signature verification
passed. The installed app entered the world as Hxitest and completed its second run at
character selection; both runs verified all four renderer hashes and restoration. The
complete original Wine prefix was restored before the installed-app test,
including its matching update timestamp. Per-run checks restore 44 saved file states and
launcher preferences, verify unchanged Docker identities/start times, and verify no test
game or Wine processes remain.

Local rollback copies are `benchmarks/20260911-launch/pre-launch-build25.app` and
`benchmarks/20260911-launch/private/prefix10` under the ximac workspace. Restore only with
the game and Wine closed. The latter is a complete APFS-cloned prefix, contains private
state, and must not be published. Ordinary app rollback needs only the saved app; keep Wine's
builtin files and `.update-timestamp` together if restoring the full prefix.
