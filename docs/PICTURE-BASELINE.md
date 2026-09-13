# Native picture controls baseline

The user accepted the picture-controls build after manual playtesting and
requested its promotion to the installed baseline on 2026-09-13 UTC.
The exact approved app was installed at `/Applications/FFXI-on-Mac.app`.
No rebuild or runtime change was made during promotion.

The baseline includes adaptive sharpening, exposure, contrast, saturation,
temperature, HDR and accurate-color toggles, FXAA, and adjustable bloom in the
native Command-comma panel. Effects remain session-only and start neutral;
startup HDR and color-space choices still come from existing configuration.
The user's preferences and game configuration were preserved.

## Identity and rollback

[The baseline record](baselines/native-picture-controls-20260913.json) records
the renderer source commit, signed renderer hash, complete installed bundle
file inventory, acceptance basis, and rollback artifact. The previous app is
preserved as `installed-before-picture-controls-20260913T023722Z.app` in the
local `ximac/benchmarks/20260912-native-host` artifact directory. Existing older
baselines are retained as well. Restoring that app restores the previous
package without changing user preferences.

The renderer vendor manifest now identifies the committed source and manual
acceptance. Its source patch includes acceptance documentation added after
building; runtime source is unchanged from the tested snapshot. The exact
installed bundle keeps its original signed metadata. This avoids rebuilding
or resealing the user's approved artifact solely to update provenance text.

## Evidence and limits

The production x86_64 renderer build succeeded with Rust 1.97.1. Package
signatures and renderer manifest hashes were verified. All 40 installed
bundle files/symlinks match the approved candidate, and the rollback copy
matches the former installed app. No process was stopped or launched.

The user described manual results as excellent and explicitly selected this
baseline. The report did not identify a full effects/display matrix or FPS
measurements. The earlier instruction against automated tests and agent-led
gameplay remained in force. No new automated test or benchmark results are
claimed, and no compiler independent of the running game validated the Metal
shaders. Prior native-host automated results cover the earlier host release.
