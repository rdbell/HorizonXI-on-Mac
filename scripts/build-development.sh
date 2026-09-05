#!/usr/bin/env bash
# build-development.sh -- (re)build the `development` mainline integration branch.
#
# `development` is our fork's mainline (Scenario B), but it is not hand-edited history: it
# is a fresh copy of master with every branch in development-branches.txt merged on top, so
# it holds all of our fork's changes at once and stays fully reproducible from the recipe.
# It is never opened as a PR and never merged into master (master stays a clean mirror of
# upstream). Rebuild it whenever the recipe changes or master advances. See
# docs/FORK-STRATEGY.md.
#
# Usage:
#   scripts/build-development.sh [worktree-path]
#
# Rebuilds `development` in a dedicated worktree (default: ../hxi-development), resetting
# it to origin/master and merging each recipe branch in order. Conflict resolutions are
# recorded with git rerere, so the first rebuild may need a hand and later ones replay
# automatically. On an unresolved conflict the script stops and tells you what to do.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
RECIPE="$HERE/development-branches.txt"
REMOTE="${HXI_REMOTE:-origin}"
WORKTREE="${1:-$REPO/../hxi-development}"

[[ -f "$RECIPE" ]] || { echo "no recipe at $RECIPE" >&2; exit 1; }

# Remember conflict resolutions across rebuilds -- the whole point of a rebuildable
# integration branch is that you resolve each collision once.
git -C "$REPO" config rerere.enabled true
git -C "$REPO" config rerere.autoUpdate true

echo "==> fetching $REMOTE"
git -C "$REPO" fetch --quiet "$REMOTE"
git -C "$REPO" rev-parse --verify --quiet "$REMOTE/master^{commit}" >/dev/null \
  || { echo "no $REMOTE/master" >&2; exit 1; }

# A dedicated worktree so this never disturbs your main checkout. `development` only ever
# lives here; force-recreate the branch pointer at master to start each rebuild clean.
if [[ -d "$WORKTREE/.git" || -f "$WORKTREE/.git" ]]; then
  git -C "$WORKTREE" reset -q --hard "$REMOTE/master"
  git -C "$WORKTREE" checkout -q -B development "$REMOTE/master"
else
  git -C "$REPO" worktree add -f -B development "$WORKTREE" "$REMOTE/master" >/dev/null
fi
echo "==> development reset to $REMOTE/master ($(git -C "$WORKTREE" rev-parse --short HEAD))"

merged=()
while IFS= read -r raw; do
  line="${raw%%#*}"
  line="$(printf '%s' "$line" | tr -d '[:space:]')"
  [[ -z "$line" ]] && continue
  ref="$REMOTE/$line"
  git -C "$REPO" rev-parse --verify --quiet "$ref^{commit}" >/dev/null \
    || { echo "!! unknown branch in recipe: $line ($ref does not exist)" >&2; exit 1; }
  echo "==> merging $line"
  if ! git -C "$WORKTREE" merge --no-edit -m "development: merge $line" "$ref"; then
    if git -C "$WORKTREE" diff --name-only --diff-filter=U | grep -q .; then
      echo "" >&2
      echo "!! conflict merging '$line'. Files:" >&2
      git -C "$WORKTREE" diff --name-only --diff-filter=U | sed 's/^/     /' >&2
      echo "   Resolve them in $WORKTREE, then record the resolution:" >&2
      echo "     git -C \"$WORKTREE\" add -A && git -C \"$WORKTREE\" commit --no-edit" >&2
      echo "   Then re-run this script -- rerere will replay the fix and continue." >&2
      exit 2
    fi
    # No unmerged files means rerere already resolved it; just finalize the commit.
    git -C "$WORKTREE" commit --no-edit
  fi
  merged+=("$line")
done < "$RECIPE"

echo ""
echo "==> development rebuilt in $WORKTREE"
echo "    tip:    $(git -C "$WORKTREE" rev-parse --short HEAD)"
echo "    merged: ${merged[*]}"
echo "    build:  (cd \"$WORKTREE/app\" && ./bundle.sh /Applications)"
echo "    push:   git -C \"$WORKTREE\" push -f $REMOTE development   # optional; it is disposable"
