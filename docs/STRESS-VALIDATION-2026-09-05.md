# Stress suite validation, September 5

Installed renderer remains build 24. This checkpoint changes benchmark tooling only.
All live runs used Local LSB/Hxitest. Docker was neither restarted nor rebuilt.

## Completed evidence

The eight-mob Firaga workload completed both Chainspell rounds and all 20 casts.
Both the client action packet and the server damage audit confirmed eight targets.
Full personal addons, 4096-square background, and the frozen shader seed produced
41.652 FPS idle, 39.072 FPS in round one, and 32.768 FPS in round two. Worst frame
was 78.610 ms. These are baselines, not improvements.

City testing found three fixture problems:

- `setStatus(DISAPPEAR)` deleted dynamic NPCs without a client despawn update.
  `hideNPC(600)` sends the update before dynamic-entity deletion. Replacement and
  final zero-entity cleanup subsequently completed.
- All 64 NPC records reached the client, but only 36-38 had active render flags.
  Defaults now use 16 and 32 identical NPCs, then 32 with seven fixed looks.
- Home key delivery did not establish a camera view toward the formation.
  A temporary fixture target and a lock/unlock pair aligned the camera successfully.

The completed city-12 diagnostic measured 35.950 FPS empty, 21.873 with 16 NPCs,
16.910 with 32, and 15.894 with 32 mixed looks. Screenshots confirmed the formation
was visible, but its back row reached the auction-house stairs. These timings are
provisional and must not be compared directly with later flat-ground runs.
The report initially rejected mixed-32 because one population check still expected
64. That check and a regression test were corrected; the recorded workload passes
the corrected report. Visual review remains separate from numeric validity.

The final script moves the player to `(0,0,-90)` in Bastok Mines and centers the
single camera anchor. That position still needs live screenshot validation. The
next run, baseline-13, timed out recognizing character selection before entering
the world. All 44 saved file states and launcher preferences were restored, and
the temporary server command was removed. No game or Wine process remained.

## Next comparisons

1. Validate the flat-ground crowd view, then run identical full/minimal addon tests.
2. Compare submitDraws=0 against 512 with mergePasses=true, holding renderer bytes,
   graphics, boot script, and shader seed fixed. Prior submission tests predated
   pass merging and showed a busy-scene gain with a light-scene regression.
3. Validate aga24/aga40 server audits and repeated arrivals. Camera-heading phases
   remain experimental because server orientation does not prove camera orientation.

Local raw captures and private rollback snapshots remain outside Git under
`ximac/benchmarks/20260905-stress-suite/`. Do not publish those private snapshots.
Focused Lua stress/fixture tests and Python report/suite tests pass.
