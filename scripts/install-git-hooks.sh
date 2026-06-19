#!/usr/bin/env bash
# Install tracked git hooks from scripts/githooks/ into the shared hooks dir.
# Run once per clone: bash scripts/install-git-hooks.sh
# Uses --git-common-dir so the hooks apply to the main checkout AND every worktree
# (worktrees share one hooks dir). Part of AG_DEV_POLICY.md §14.4.
set -eu
ROOT=$(git rev-parse --show-toplevel)
HOOKS=$(git rev-parse --git-common-dir)/hooks
SRC=$ROOT/scripts/githooks
mkdir -p "$HOOKS"
for h in "$SRC"/*; do
  name=$(basename "$h")
  cp "$h" "$HOOKS/$name"
  chmod +x "$HOOKS/$name"
  echo "installed: $name"
done
