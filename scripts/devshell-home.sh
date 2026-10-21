#!/usr/bin/env bash
#
# Prints the checkout's root and the dev shell's PLTUSERHOME, one a line.
# The home is keyed on the root as git resolves it (symlinks and a trailing
# slash gone, a subdirectory lifted to the top), so every way into one
# worktree shares one home (#158). Outside git, or inside a repository that
# is not an rkt-polars checkout, the root is the physical path of the
# directory. A checkout whose path has no symlinks keeps the home it had.
#
# Usage: scripts/devshell-home.sh [dir]     (default: $PWD)
set -euo pipefail

dir=$(cd "${1:-$PWD}" && pwd -P)
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$root" ] || [ ! -f "$root/polars/info.rkt" ]; then
  root=$dir
fi

cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/rkt-polars-devshell"
printf '%s\n' "$root"
printf '%s/%s\n' "$cache_root" "$(printf '%s' "$root" | sha256sum | cut -c1-12)"
