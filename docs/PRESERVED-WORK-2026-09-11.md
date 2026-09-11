# Preserved local work, September 11, 2026

This branch saves the older local launcher worktree based on a5578ec. Much of its
runtime installation, performance tooling, patches, and documentation was incorporated
into development and subsequently improved there. It also preserves local server-path
adjustments and older diagnostic implementations for reference.

The current launcher is development at c793fd1, build 26. This historical snapshot is
not an update to the installed app and must not replace development wholesale. In
particular, its Wine startup, profiler defaults, renderer, and x87 resources predate
the current fixes. Use development for new work and cherry-pick only a verified missing
change from this snapshot.

Generated Python bytecode is ignored. Private game profiles, logs, benchmark capture
backups, and the full Wine prefix remain outside this commit. Publication does not
rebuild or restart the game, Wine wrapper, or local Docker server.
