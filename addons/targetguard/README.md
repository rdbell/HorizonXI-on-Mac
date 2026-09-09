# Target guard

A native client compatibility fix for the FFXI target-selection freeze observed on
2026-09-09. The game repeatedly selected two objects at identical coordinates,
alternating A → B → A without finishing the frame. Metal workers were idle because
the game thread never returned from target selection.

This addon installs four guarded CALLs in FFXiMain's two fallback traversal loops.
It leaves the original selector in charge of eligibility and ordering. A repeated
starting candidate, a self-repeat, or 2,304 steps ends the fallback traversal by
returning no further candidate. The caller retains its last valid candidate.
Ordinary selections and the initial non-fallback calls are unchanged. State is
per thread; the first fallback call resets it for each traversal. The first
prevented cycle is recorded in `addons/targetguard/targetguard.log`.

Supported image: i386 FFXiMain.dll, PE timestamp `1762938809`, SizeOfImage
`12447744`, matching function-entry signature and all four original relative CALLs.
Other builds or modified call sites are rejected without patching. No client
files, renderer settings, packets, or server state are changed by the guard.
The Lua adapter disables JIT like the other project compatibility addons.

## Build and install

Requires `i686-w64-mingw32-gcc`:

```sh
./scripts/build-targetguard.sh
python3 scripts/install-targetguard.py /path/to/game --backup /path/to/new-backup
```

Close the game before installing. The installer copies the DLL and Lua adapter,
preserves existing startup text and adds `/addon load targetguard` to `default.txt`
and the local `perfscene.txt` if present. Run it again after replacing the game
installation. The installed application executable and renderer do not need rebuilding.

At startup, expect `[targetguard] Target-cycle guard installed.` A negative status
means no fix was applied. Do not bypass that check on an unsupported build.

## Rollback

Close the game and remove the single `/addon load targetguard` line from the startup
scripts, or restore the saved scripts if no later edits need preserving. Remove
`addons/targetguard`, or restore its saved prior directory. No on-disk game-code
patch needs reversing. `/addon unload targetguard` restores the original CALL bytes
in memory when those bytes still match our hooks; restart if it reports failure.

## Validation

`guard-test.c` runs the actual x86 patch and wrappers in a synthetic module under
Wine. It tests both directions, normal and empty lists, A/B and self cycles, cycles
after a noncyclic prefix, thread isolation, unsupported-build and altered-code
rejection, repeated install/remove, and byte-exact restoration. The mock selectors
also check argument forwarding across the patched CALLs.

```sh
i686-w64-mingw32-gcc -O2 -Wall -Wextra -Werror -static-libgcc \
  -o /tmp/targetguard-test.exe scripts/tests/targetguard/guard-test.c
# Run the executable with the existing configured Wine runtime.
luajit scripts/tests/targetguard/addon-test.lua addons/targetguard/targetguard.lua
```

The live captured image matched the PE identity, entry signature and all four
CALL sites. Full in-game validation is still pending: the local-server startup
attempt exited in the loader before FFXI initialized, and direct LoadLibrary of
the packed client returned DLL initialization error 1114. Neither failure shows
that the patch loaded or failed in a game session. The synthetic x86 tests passed.
The earlier Warp/Flee freezes have not been proven to share this targeting cycle.
