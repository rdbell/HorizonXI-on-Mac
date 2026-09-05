# Fork strategy: how we build our changes and keep master clean

We maintain a fork (`rdbell/HorizonXI-on-Mac`, remote `origin`) of the canonical repo
(`danielalanbates/HorizonXI-on-Mac`, remote `upstream`). We want two things at once:

1. **Builds that include all of our important changes**, right now, without waiting on
   upstream review.
2. **A `master` that stays a clean mirror of upstream**, so we can keep contributing back
   with clean, reviewable PRs.

We do not yet know whether upstream will accept our PRs. This document sets up one
foundation that serves **both** possible futures, and defers the choice between them.

> **Status (2026-09-04): Scenario B is in effect.** We have stopped gating our build on
> upstream review and adopted `development` as our permanent mainline. The recipe below is
> now our integration manifest. `master` remains a clean mirror of upstream so we can keep
> upstreaming individual branches cleanly. The mechanics did not change -- only the posture.

## The three branches

| Branch | Role | Rule |
|---|---|---|
| `master` | Clean mirror of `upstream/master` | **Never** carries an original commit. Only ever fast-forwarded from upstream. |
| feature branches | One change each, based on `master` | The unit we open PRs from. Kept rebased on master so they stay both PR-able and merge-able. |
| `development` | **Our mainline** (Scenario B, in effect) | Rebuilt by a script from `master` + a recipe, so it holds every fork change at once. Never PR'd, never merged into master; master stays a clean upstream mirror. Reproducible from the recipe, so a bad rebuild costs nothing. |

Everything our fork adds beyond upstream is captured as a list of feature-branch names in
[`scripts/development-branches.txt`](../scripts/development-branches.txt) -- the recipe.
That file is the single source of truth for "what is ours."

## Producing a build with all our changes

```sh
scripts/build-development.sh            # rebuilds `development` in ../hxi-development
cd ../hxi-development/app && ./bundle.sh /Applications
```

`build-development.sh` resets `development` to `origin/master`, merges each recipe branch
in order, and records conflict resolutions with `git rerere` so later rebuilds replay them
automatically. `development` lives in its own worktree and never touches your main checkout
or `master`.

To add a change to the build, add its branch name to the recipe and rebuild. To drop one,
delete the line.

## The two futures -- and why we don't have to choose yet

The setup above is identical for both. The only difference is a one-time action taken
**if and when** a future becomes real. The discipline that keeps both doors open is the
master rule: no original commits on `master`.

### Scenario A -- upstream accepts our PRs (canonical stays the source of truth)

Each time a PR merges upstream, re-sync master and prune the recipe:

```sh
git fetch upstream
git checkout master
git merge --ff-only upstream/master      # fast-forward only; never a merge commit
git push origin master
# delete the merged branch's line from scripts/development-branches.txt, then:
scripts/build-development.sh
```

Because master only ever fast-forwards, these re-syncs never conflict, and our divergence
from upstream shrinks toward zero as PRs land. Nothing special to undo.

### Scenario B -- upstream declines; we go independent (permanent fork)

**We took this path on 2026-09-04**, keeping the name `development` (rather than minting a
separate `fork-main`). `development` already is master + everything ours, and the recipe is
its manifest, so there was nothing to branch -- we simply adopted it as the mainline and
folded in the remaining important work (the winecursor input bundle, ashita-signature-repair,
vanagear, release-cadence-check, docs-findings-cleanup). New work lands as a feature branch
+ a recipe line, exactly as before:

```sh
scripts/build-development.sh             # get a clean, current integration
git branch fork-main development         # our new mainline, committed to directly from here on
git push origin fork-main
```

From then on, new work lands on `fork-main` directly (no upstream review gate). We can
still pull upstream's fixes when we want them -- upstream becomes a source we merge or
cherry-pick from, not a gate:

```sh
git fetch upstream
git checkout fork-main
git merge upstream/master                # take their fixes on our terms
```

`master` can stay a mirror as long as we like (useful if we ever resume upstreaming), or
be retired. Nothing about scenario A has to be unwound to get here.

## Why this is safe

- `master` never diverges, so scenario A's fast-forward re-syncs stay trivial forever.
- The recipe captures our fork's identity in one file, so scenario B is a branch + merge
  away, not an archaeology project.
- `development` is disposable: a bad rebuild costs nothing, because it holds no history
  that isn't reconstructable from the recipe.
