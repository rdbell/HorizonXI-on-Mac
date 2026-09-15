# Space resume verification

The renderer could keep a stale hidden flag indefinitely: its periodic display refresh was scheduled only after acquiring a drawable, while the hidden flag prevented that acquisition. The fix schedules reconciliation before the gate and also refreshes on native-host occlusion and workspace Space changes. Visibility still uses the compositor occlusion bit; Space membership and parent visibility are diagnostic only.

## Deliverable

`final-candidate/FFXI-on-Mac.app` contains the corrected production native renderer. SHA-256: `dde236e7b994147325f80d81e8aaa891e31e75dc66c09016fe11d7b6fb6def33`.

The launcher and PE renderer are preserved from the user's early candidate. Packaging asserts the freshly built dylib matches the Makefile-staged `.so`, records source hashes and symbols, and verifies the app signature. The exact candidate was promoted to `/Applications` at the user's request. `source-final/` preserves all dirty source, including unrelated pre-existing sprint changes; Source is committed separately from the preserved build-time metadata.

## Completed evidence

- Controlled stale-visibility regression: baseline remained hidden for the four-second observation (four already-queued frames); candidate cleared the flag automatically and presented 240 frames. Manual clear restored the baseline. The test helper refused an unrelated PID. See `final-stale-baseline/` and `final-stale-candidate/`.
- Four windowed Space round trips, four native-fullscreen Space round trips, and four Finder focus round trips passed. All 12 captures passed quadrant-image validation. Every probe restored the starting desktop.
- The first visible presentation after a desktop-return request occurred within 0.44-0.58 seconds in the standalone tests, including desktop-animation time. This is not an exact recovery latency measurement. The focus test kept presenting while unfocused.
- `make test`: all 2,161 per-test results passed: 1,046 core/type, 207 native/shared, 454 i686 and 454 x86_64 rendering tests. Five leaky-output-handle reports were benign; no failed or timed-out assertion. Counts independently checked in `test-counts.json`.
- Both PE clippy legs and rustdoc passed with the existing user-local xwin SDK. Targeted mechanical audits for all three changed Rust files and `git diff --check` passed.
- `make check` is not green: existing formatting drift in picture/present modules, native clippy warnings in existing settings/preferences code, and existing mechanical-audit findings remain. Initial PE checks also hit the repository's absent `/opt/xwin` SDK; the existing task build wrapper provided the installed SDK and those legs then passed.

## Final FFXI run

`final-game/`: local Docker LSB, Hxitest, existing full addon boot, 4096 background setting, native host and submitDraws=512. Loaded module mapping and SHA-256 match the final candidate. All six desktop round trips completed; first presentation after the return request occurred in 0.425-0.664 seconds. Largest subsequent presented interval in each observation ranged from 0.27 to 0.45 seconds. No 5-10 second freeze was observed. These are recovery checks, not a clean FPS benchmark.

The final screenshot shows Hxitest in Bastok Mines with game and addon rendering present. `restoration.json` confirms 46 file states and preferences restored, Docker unchanged, and no related processes left. The generic capture tool warned about missing DXVK CSVs; timing analysis uses the mtld3d `presented` trace instead. See `timing-summary.json` and `renderer.log`.

## Scope and limits

Ordinary baseline desktop switching did not naturally reproduce the reported 5-10 second freeze. The lost-notification recovery failure is confirmed and corrected, but cannot establish the cause of every reported pause. Final manual confirmation of the original trigger is still valuable. Tests exercise macOS Spaces and app focus; physical monitor dragging is not newly validated here.

Some `nextDrawable` calls waited about 1.2 seconds while leaving a fullscreen Space, ending with the window marked hidden. Return presentation recovered; these are not observed multi-second post-return freezes. New production warnings distinguish long drawable acquisition from GPU-retirement waits without changing synchronization.

The early `candidate/` and `runloop-candidate/` packages used stale staged binaries and are invalid. Their measurements do not test this fix. The speculative run-loop change was reverted. `visibility-candidate/` is an intermediate tested version, superseded by `final-candidate/`.

## Baseline promotion

The user selected this candidate as the new baseline on 2026-09-15. The installed app exactly matches all 44 candidate files, with no rebuild or resealing. The previous installed app is preserved at the rollback path in [the baseline record](baselines/space-resume-early-submit-20260915.json). No game was launched during promotion. Saved graphics and game settings were preserved.

The launcher vendor renderer and source patch now point at the committed correction, so future bundles include recovery alongside the 512-draw default. The source-backed scanner remains opt-in. The installed app retains its original build-time metadata; the baseline record supplies the final committed provenance.
