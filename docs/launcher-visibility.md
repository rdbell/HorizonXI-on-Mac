# Launcher visibility during gameplay

Once the existing game-window watcher sees the client's first visible window,
the launcher orders its windows out and switches to macOS accessory activation
policy. Its running Dock tile and Command-Tab entry disappear. The game keeps
its own windows and Dock entry; the launcher continues logging and watching
for game exit.

On game exit, the launcher restores regular activation policy and its windows.
A failed launch that never produces a game window leaves the launcher visible.
Opening FFXI-on-Mac.app from Finder during a game restores the existing launcher
window, and subsequent window polls leave it visible for the rest of that run.
This does not remove a shortcut the user has explicitly pinned in the Dock.

The change uses the existing two-second game-window poll. It does not add a
second process watcher, change how Wine launches, or terminate the launcher.

Validation on macOS 26.5:

```sh
swift build -c release --package-path app --jobs 4
swiftc app/Sources/HorizonXILauncher/LauncherVisibility.swift \
  scripts/tests/launcher-visibility-test.swift -o /tmp/launcher-visibility-test
/tmp/launcher-visibility-test
```

The native test opens a temporary AppKit window and checks actual application
activation policy and window visibility across hide, manual reopen, repeated
polls, the next game, exit, and a failed launch. Both checks passed. It does not
log into FFXI; a complete game-session check remains part of play-testing.
