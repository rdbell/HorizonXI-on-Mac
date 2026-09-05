# Benchmark harness

The point of this directory is that a frame-rate claim in this project should be reproducible by
running one command, not by squinting at an overlay. Every number in `docs/PERFORMANCE.md` and
`docs/SETTINGS-SWEEP.md` came out of `bench.py`.

These scripts drive Daniel's install directly (paths are hard-coded at the top of `bench.py`);
they are checked in as a record of how the measurements were taken and as a starting point, not
as a general-purpose tool.

## Bounded menu run

`menu-run.py` drives one launch to the top-level menu with the rules-screen Return and nothing
else, so it can run unattended without ever reaching the character list:

```sh
scripts/harness/menu-run.py --x87-profile \
  --profile-analyzer /path/to/x87sidecar/build/bin/profile_analyze
```

It refuses to start while any launcher, Wine, sidecar, or game process is alive, or while launchd
still carries a diagnostic variable from an earlier experiment. It arms `capture-performance.py`,
launches the app exactly as the Play button does, waits for the rules screen by watching the
DXVK frame log, screenshots the game window, sends one Return through the compiled
`game-window` helper, waits for the main menu, screenshots again, holds, and stops. The helper
clicks the title bar and refuses to post the key unless the game is frontmost. A second Return
is a hard error in the driver, not a configuration.

Cleanup is two-phase. The game process this run launched gets `SIGTERM` first and the driver
waits up to eight seconds for its sidecar to see the exit and append the block-profile counter
section. Only then does the broad sweep terminate, kill, and check every related process name.
If a game process the driver did not launch is alive at cleanup time, a person is at the
keyboard and the driver skips cleanup entirely rather than end their session; it once killed a
hand-driven character creation this way. The run ends
with `menu-run.json` in the capture directory: phase times, the game PID, screenshots, every
launchd variable it set and cleared, the leftover process check, and whether the block profile
is complete.

One-launch diagnostic overrides go through `--env NAME=value`, repeatable. Only `X87_`, `DXVK_`,
`D3D9_`, `MVK_`, and `FFXI_ON_MAC_` names are accepted, they are set with `launchctl setenv`
just before the launch, and they are removed on every exit path. `--x87-profile` sets
`X87_PROFILE` to `x87-block-%p.prof` inside the capture directory and, when an analyzer path is
given, writes `x87-block-analysis.txt` from the complete game profile. `--no-return` stops at the
rules screen for a pure boot measurement. `--limit` bounds the game phase, including blocked
recorder and subprocess waits, to 180 seconds by default. A deadline exits with status 124.
Cleanup runs afterwards with its own subprocess timeouts so the sidecar can finalize its
counters; optional profile analysis has a separate 300-second limit.

## Local renderer comparisons

`renderer-run.py` reuses the bounded menu driver and requires the installed local Docker
world, loopback login, and `hxitest` account. It confirms Hxitest and a single registered
character through OCR before entering an optional scenario. All five server containers must
already be running. It does not restart them.

```sh
python3 scripts/harness/renderer-run.py --output /path/outside/git/dxvk-minimal
python3 scripts/harness/renderer-run.py --output /path/outside/git/mtld3d-minimal \
  --renderer-bundle /path/to/mtld3d-v0.8.0 --dump
python3 scripts/harness/renderer-run.py --output /path/outside/git/dxvk-city \
  --scenario city --menu-sample 0 --limit 420 --capture-seconds 390
```

The default boot script loads only Addons, fps, drawdistance, and perfscene. Add individual
plugins with `--load-plugin`, individual addons with `--load-addon`, or use `--boot-file`
for a frozen copy of the full boot configuration. The user's default script is preserved.
The launcher's existing LuaJIT crash guard still applies; the counter records `jit_enabled`
so a JIT assumption cannot silently change the comparison.

`--background 2048` temporarily changes both background dimensions in the local profile,
keeping the window, UI and other quality settings. The runner records numeric graphics keys
before and after launch, and restores the original profile afterwards. Omit it to use the
saved dimensions. Resolution probes should be labeled separately from renderer improvements.
`--menu-sample 0` skips menu measurement waits while retaining OCR, screenshots and DLL checks.

World scenarios use server-supplied position and rotation, followed by Home to reset the
camera. Client-only heading writes can be overwritten by the next update. Review the actual
coordinates, heading and screenshots when adding a scene.

`city_long` extends both city holds to 60 seconds. `town` uses the same longer holds with
the second vantage in the Mines plaza. `field` measures clear weather, thunderstorms and
a mob crowd outdoors; each settled phase holds for 20 seconds before the next change.

The runner snapshots renderer files, boot scripts, registry hives, local account storage,
and the selected account preferences. Its `private/` directory has mode 0700 and must never
be published. On normal completion it restores the saved file states and preferences and
checks Docker IDs/start times. `--restore OUTPUT` repeats that recovery after an interrupted
parent, and refuses to run while game or Wine processes remain.

Candidate launchers are separate signed copies. Loaded D3D8/D3D9 hashes must match their
resources, and mtld3d's loaded shim and Unix library must match the candidate bundle too.
`--launcher-binary /path/to/HorizonXILauncher` replaces the executable in that copy and
records its hash. The installed application stays intact. `--graphics-profile` copies only
numeric graphics settings from a saved boot profile, preserving the local connection details.
`--dump` presses F12 once at character selection for mtld3d's three-frame log.
`--dump-scene city-settled` captures the first town view instead. The runner saves the
renderer log after the game exits, before a later launch can rotate it away.
`--renderer-config` supplies mtld3d's existing configuration overrides and records them.
`--renderer-log` selects its `RUST_LOG` filter for a diagnostic run. Keep detailed logging
off for performance comparisons, since it adds work to the measured process.
Game and capture limits cannot exceed 420 seconds. The regular driver performs cleanup
afterwards, including the sidecar's eight-second finalization window.

`common-fps.csv` measures Ashita's `d3d_present` event with QueryPerformanceCounter across
backends. Each second includes the frame count, elapsed time, zone, and frame-time p50,
p95, p99 and maximum. Percentiles describe individual one-second windows, not a pooled
whole-run percentile. Screenshots and `renderer-loaded-files.json` retain the rendering
and binary evidence. A faster scene with missing geometry or shading is an invalid
performance comparison.

Generate a comparison from completed run directories:

```sh
python3 scripts/harness/renderer-report.py /path/outside/git/dxvk-city \
  /path/outside/git/mtld3d-city > comparison.json
```

The report uses complete one-second windows inside each menu sample or settled world phase.
It excludes the first two seconds after a settled marker to leave the scene screenshot out
of the measured interval. FPS is total frames divided by total measured seconds. It also
reports the minimum window FPS, time below 120 FPS, worst per-window p99, and longest frame.
Missing counter windows, short samples, unexpected zones, unsuccessful runs, and unconfirmed
renderer hashes or recovery are reported. Review the game screenshots before treating two
renderers as equivalent workloads. Settled markers include the actual player coordinates
and heading, so comparisons can check that the same vantage was used.

For a capture with `--level standard`, correlate complete ten-second guest-sampler windows
with those same scenes:

```sh
python3 scripts/harness/guest-scene-report.py /path/outside/git/mtld3d-city \
  --renderer-bundle /path/to/immutable-mtld3d-bundle > guest-scenes.json
```

The bundle is optional. Renderer symbols are used only when a binary's hash matches the
loaded-file record. If the installed DLL has since been restored and no matching bundle is
available, the report keeps module offsets instead of assigning functions from another build.

### Repeated battle effects

The local `effects` scenario prepares Hxitest as RDM99 with all spells, waits in Bastok Mines,
then runs three Chainspell rounds. Each round casts Blaze Spikes, Ice Spikes, Shock Spikes,
Stoneskin, Blink and Aquaveil on the character. It resets recasts, restores MP, and removes
the prior Blink, Stoneskin, Aquaveil and Chainspell effects before the round. It waits for
each spell's server completion and another three seconds before requesting the next spell.
A missing completion ends the scenario after 15 seconds; a no-effect response fails it.

```sh
python3 scripts/harness/renderer-run.py \
  --output /path/outside/git/effects-full \
  --renderer-bundle /Applications/FFXI-on-Mac.app/Contents/Resources/mtld3d \
  --shader-cache /path/to/frozen/mtld3d_shaders.bin \
  --boot-file /path/to/frozen/default.txt \
  --graphics-profile /path/to/saved/graphics.ini \
  --renderer-config 'color.hdr.enable=false;render.scale=1;present.maxFps=0;render.mergePasses=true;render.submitDraws=0' \
  --scenario effects --level standard-nosample --limit 420 --capture-seconds 400 \
  --menu-sample 0 --hold 2 --env 'PERFSCENE_FRAMES={session}\frame-times.csv'
python3 scripts/harness/effects-report.py /path/outside/git/effects-full
```

The report uses individual frame durations and keeps whole frames that overlap phase
boundaries. A complete round requires one successful Chainspell response and all six buffs
applied once. Check the renderer problems and screenshots as well as the phase validity.
The entire game configuration tree is backed up and restored, including addon settings
created during a test. Private backups and boot scripts must stay outside Git.

For profiling, use `--level standard` with a launcher containing the guest-range correction.
The old full-address-space default could follow AppKit's window event thread while missing
the game thread. Discovery now excludes 64-bit addresses; `X87_GUEST_RANGE` can narrow it
further. Confirm the actual sampled modules and thread, since Windows DLLs can relocate and
their preferred PE image bases do not prove where they loaded. A high sample-coverage
percentage alone does not establish that the intended thread was sampled.

## Offline fault benchmark

`fault-bench.py` runs a Windows benchmark under the installed Wine runtime, without the x87
sidecar, and counts its page faults, copy-on-write faults, Mach traps and kernel time per
quarter second. It stops every Wine process afterwards. `scripts/tools/d3d9-scene-bench.c`
reproduces the game's scene-load traffic: thousands of draws per frame under distinct world
transforms, plus a batch of freshly created and initialised index buffers per frame. Its fifth
argument runs steps before the device exists: `load-nonx` loads a DLL built without the
NX-compatible flag, `nx-on` and `nx-on-permanent` set `ProcessExecuteFlags`, `query` prints
them. This is how the loading stall was isolated to Wine's execute-everywhere response:

```sh
i686-w64-mingw32-gcc -O2 -o /tmp/bench/d3d9-scene-bench.exe scripts/tools/d3d9-scene-bench.c -ld3d9 -lgdi32
cp vendor/dxvk-1.10.3-x32-d3d9-horizonxi.dll /tmp/bench/d3d9.dll
scripts/harness/fault-bench.py /tmp/bench d3d9-scene-bench.exe 12 3000 64 65536 load-nonx
scripts/harness/fault-bench.py --env DXVK_ENFORCE_NX=0 /tmp/bench d3d9-scene-bench.exe 12 3000 64 65536 load-nonx
```

## Capture one real launch

`capture-performance.py` records a launch from the installed Mac app without pressing keys or
rebuilding the command that logs into the server:

```sh
scripts/harness/capture-performance.py \
  --game-dir "$HOME/Games/FFXI/HorizonXI"
```

Start the recorder first, press Play normally, then move through the slow screens and into the
problem scene. If the recorder has a terminal, type labels such as `terms`, `character select`,
or `city loaded` and press Return. Labels are timestamped without sending input to the game.
The recorder stops when the game exits, with a 15-minute safety limit. Use `--duration` to change
that limit.

The recorder arms a one-shot request in Application Support. The launcher consumes it on the
next matching launch and gives the DXVK probes unique output paths. Later launches return to
normal automatically. A request expires if Play is not pressed within ten minutes.

The standard capture includes:

- frame rate, draw count, render passes, queue submissions, GPU idle time, GPU sync time,
  asynchronous compiler activity, and live pipeline counts;
- time inside and outside `Present`, DXVK map/CS stalls, Windows wait calls, texture-lock shapes,
  flushes, queue-retirement timing, and once-per-second frame, submit, and in-flight
  `DrawPrimitiveUP` phase watchdogs;
- per-second process CPU, physical footprint, page-ins, instructions, cycles, wakeups, and
  per-process disk bytes from `proc_pid_rusage`, plus page faults, copy-on-write faults, Mach and
  BSD syscall counts, context switches, thread count, and the task user/kernel clock from
  `proc_pidinfo`. `timeline.csv` turns these into per-second rates and a kernel share, and the
  summary contrasts the slow seconds with the recovered seconds so a stall reads as page-fault
  bound, syscall bound, idle, or user-mode work without a second run. Consecutive slow seconds
  are grouped into named low-FPS windows with their fault rate and footprint change;
- five-second thread CPU, system memory, and system-wide GPU utilization snapshots; network byte
  totals, loaded-file snapshots, and binary hashes;
- a 1 kHz x87sidecar guest-PC profile, split into ten-second windows and
  correlated with the DXVK frame-rate log. Discovery within 32-bit addresses selects a guest thread,
  and sticky sampling keeps following it through DLLs, Rosetta code, syscalls, and long stalls. The
  summary reports coverage and separate hotspots for slow and recovered windows;
- the launcher logs with common username, password, token, and secret forms redacted;
- when `X87_PROFILE` is set for the launch, the x87sidecar block-execution profile of the game
  process. The summary reports whether the counter section is present; it is written only after
  the game exits, which is why `menu-run.py` stops the game before the sidecars.

For a short run at 1080p, `--level deep` also enables the D3D9 call histogram, long-gap
attribution, framebuffer and render-pass probes. Those per-call probes change timing more than
the standard set. The draw probe is known to be unstable with the x87 sidecar at 4K, so do not
use deep mode there. The retired DXVK instruction sampler is intentionally excluded because it
suspended the frame thread and could turn a slow launch into a black-screen run. The guest-PC
sampler used now runs in x87sidecar and never suspends the target.

The diagnostic DLL also exposes `DXVK_UP_STAGE_LOG` in standard captures. It records any
`DrawPrimitiveUP` call that stays in one phase for a second, including primitive count, generated
vertex count, stride, data size, and allocation size. The deep-only `DXVK_UP_PROBE` splits
completed calls into device lock, draw preparation, temporary-buffer allocation, user-data copy,
and command-enqueue time, with call rates and upload-size buckets. Apply
`patches/dxvk-1.10.3-drawprimitiveup-probe.patch` after the cumulative fence-wait patch when
building that DLL. Older DLLs ignore the variable, and the manifest records which probe names
each installed DLL actually contains.

With `patches/dxvk-1.10.3-pipeline-compiler-probe.patch` applied, `DXVK_FPS_LOG` also records
`compiler_busy`, `graphics_pipelines`, and `compute_pipelines`. Those columns show whether the
low-FPS window overlaps asynchronous state-cache compilation.

`scripts/tools/d3d9-up-bench.c` reproduces FFXI's 112-byte `DrawPrimitiveUP` traffic without an
account or server connection. It crosses the 1 MiB arena boundary many times and reports calls per
second. Use `DXVK_UP_PROBE` and `DXVK_UP_STAGE_LOG` with it to verify that an upload-buffer change
does not introduce a rollover stall.

Native `/usr/bin/sample` snapshots are off by default. Rosetta can produce recursive or otherwise
invalid native unwinds that look like Wine syscall loops. They remain available for a specific
host-side question with `--sample-at 30,90 --sample-seconds 5`.

Results go under `GAME/logs/performance-captures/<session>/`. The recorder writes both a compact
`summary.txt` and the raw files, then makes a `.tar.gz` beside the directory. It deliberately
never reads or stores a process argument list or Ashita boot profile because both may contain
account credentials.

To add host-side data to a game that is already running:

```sh
scripts/harness/capture-performance.py --pid <game-pid> --duration 60
```

An attached capture cannot turn on DXVK probes after process start, so use an armed launch when
the renderer data matters.

## bench.py

```sh
./bench.py --tag baseline                       # character select, default settings
./bench.py --tag div1 --env FFXI_FPS_DIVISOR=1  # one environment override
./bench.py --tag low --profile profiles/s-all-low.json
./bench.py --tag light --enters 0               # stop at the rules screen instead
```

It kills stale clients, applies the variant, launches the game, presses Return until the draw
count says the heavy scene has been reached, samples for `--sample` seconds, screenshots the game
window in the background (`screencapture -l <window>`, which works even when the window is
occluded), kills the client and writes `results/<tag>.json`.

A variant is a JSON profile with any of: `env`, `registry` (FFXI's own settings, applied through
Ashita's `[ffxi.registry]` block), `dxvk_conf`, `dlls`, `renderer`, `addons`.

Frame rate comes from `DXVK_FPS_LOG`, which our `d3d9.dll` writes. It also reports per-frame
draws, render passes, barriers and queue submits, so a change that helps the frame rate can be
told apart from one that just changes the scene.

**Scene choice.** Character select: ~1841 draws, deterministic, reachable with two keypresses,
and no character is in the world, so killing the client afterwards is safe. The rules-of-conduct
screen (`--enters 0`) is the light-scene equivalent at ~380 draws.

## fpsvideo.py

Frame rate for pathways that do not use our DXVK — counts visually distinct frames in a screen
recording with ffmpeg's `mpdecimate`. Cross-check it against `DXVK_FPS_LOG` on a DXVK run before
trusting it: it under-reports on a scene that is genuinely static.

## renderer.sh

Swaps the wrapper's wine D3D translation DLLs between wine's own builtins, DXMT (native Metal)
and DXVK's d3d11. Run `./renderer.sh save` once before the first switch and `restore` after.

## install-d3d9.sh

Copies a built `d3d9.dll` to all five paths the game can load it from. Missing one silently
tests the old build.

## addons/fpslog

An Ashita Lua addon that logs frame rate, zone and rendered-entity count to CSV — renderer
agnostic, so it measures pathways that have no DXVK in them. **It does not currently load**:
Ashita.dll in this install is interface 4.16 and every bundled plugin, including the `Addons`
Lua host, is 4.15, so the plugin manager rejects them all. Kept for when that is fixed.
