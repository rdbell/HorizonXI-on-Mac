# Archived cx5 validation launcher

This branch preserves the local launcher edits used for Wine cx5 validation.
It is a diagnostic snapshot, not a distributable launcher or a change to the
production development branch.

- `Install.prefix` points to the original machine-local validation prefix.
- `WineRuntime.root` accepts `FFXI_ON_MAC_TEST_RUNTIME` and otherwise uses the
  original machine-local cx5 runtime directory.
- `Runner` skips `WineLocaleFix.apply` to leave the selected upstream runtime
  unmodified during the comparison.

The prefix override is hard-coded. There is no `FFXI_ON_MAC_TEST_PREFIX`
override in this snapshot. The referenced directories are not included in Git.
Use only an isolated local LSB test prefix with Hxitest. Do not use this branch
to launch a Horizon account or package a release.

This commit archives the existing source without changing its behavior.
Publication validation consists of reviewing the diff, checking whitespace,
and parsing the three changed Swift files. No game run or performance test
was performed for this archival commit. It does not establish a new benchmark
result or prove that every previously built test binary matches this snapshot.

The installed application, runtime, and local rollback files are unchanged.
