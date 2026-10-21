# shellcheck shell=bash
#
# Sourced by the dev shell's hook (flake.nix's devSetup) and by
# scripts/devshell-home-test.sh, so the gate runs the hook's own code. From
# the working directory it sets project_root and exports PLTUSERHOME, or
# prints one line to stderr, changes neither and returns 1.
#
# The home is keyed on the root as git resolves it (symlinks and a trailing
# slash gone, a subdirectory lifted to the top), so every way into one
# worktree shares one home (#158). GIT_DIR and GIT_WORK_TREE, which a git hook
# exports, are ignored: with GIT_DIR alone git takes the working directory for
# the top. Outside git, or inside a repository that
# is not an rkt-polars checkout, the root is the physical path of the
# directory. A checkout whose path has no symlinks keeps the home it had.
#
# Usage: . scripts/devshell-home.sh [path-prefix]
#   path-prefix is put before PATH while git, sha256sum and cut run.

rkt_polars_devshell_home() (
  set -uo pipefail
  fail() {
    printf 'rkt-polars dev shell: %s; skipping the setup\n' "$1" >&2
    exit 1
  }
  if [ -n "${1:-}" ]; then
    PATH="$1:$PATH"
  fi
  dir=$(pwd -P) || fail "cannot resolve the working directory"
  root=$(env -u GIT_DIR -u GIT_WORK_TREE \
    git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root=
  if [ -z "$root" ] || [ ! -f "$root/polars/info.rkt" ]; then
    root=$dir
  fi
  if [ -n "${XDG_CACHE_HOME:-}" ]; then
    cache=$XDG_CACHE_HOME
  elif [ -n "${HOME:-}" ]; then
    cache=$HOME/.cache
  else
    fail "neither XDG_CACHE_HOME nor HOME is set, so PLTUSERHOME has no place"
  fi
  id=$(printf '%s' "$root" | sha256sum 2>/dev/null | cut -c1-12) \
    || fail "sha256sum failed, so PLTUSERHOME has no key"
  [[ $id =~ ^[0-9a-f]{12}$ ]] \
    || fail "sha256sum gave no hash, so PLTUSERHOME has no key"
  printf '%s\n%s/rkt-polars-devshell/%s\n' "$root" "$cache" "$id"
)

if rkt_polars_devshell_lines=$(rkt_polars_devshell_home "${1:-}"); then
  # shellcheck disable=SC2034
  project_root=${rkt_polars_devshell_lines%%$'\n'*}
  export PLTUSERHOME=${rkt_polars_devshell_lines#*$'\n'}
  unset -v rkt_polars_devshell_lines
  unset -f rkt_polars_devshell_home
else
  unset -v rkt_polars_devshell_lines
  unset -f rkt_polars_devshell_home
  return 1
fi
