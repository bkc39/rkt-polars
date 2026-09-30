#!/usr/bin/env bash
#
# The periodic toolchain refresh; see polars/native-libs/BUILDING.md.  On a
# branch with a clean tree it benches the tree, then moves nixpkgs
# (flake.lock), the release rustc (rust/rust-toolchain.toml) to the new
# nixpkgs', the manylinux2014 image (scripts/build-so.sh) to its current
# digest and the crates to their newest semver-compatible versions
# (rust/Cargo.lock, so polars stays on its minor), checks the result as CI
# does and benches it again.  It commits nothing: it writes the commit message
# and the PR body under DIR.
#
#   scripts/refresh-toolchain.sh [--dir DIR] [--no-bench]
set -euo pipefail

die() { echo "refresh-toolchain: $*" >&2; exit 1; }
usage() {
  echo "usage: scripts/refresh-toolchain.sh [--dir DIR] [--no-bench]" >&2
  exit 2
}

dir="$HOME/rkt-polars-toolchain"
bench=1
while (( $# )); do
  case "$1" in
    --dir) dir="${2:?}"; shift 2 ;;
    --no-bench) bench=""; shift ;;
    *) usage ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] \
  || die "commit or discard the tracked changes first"
[[ "$(git branch --show-current)" != master ]] || die "check out a branch for the refresh"
out="$dir/$(date -u +%Y-%m-%dT%H%MZ)"
mkdir -p "$out"

image_repo=quay.io/pypa/manylinux2014_x86_64

# One tool from the nixpkgs flake.lock pins, which `nix flake update` moves.
tool() { local pkg="$1"; shift; nix shell --inputs-from . "nixpkgs#$pkg" --command "$@"; }
rustc_release() { tool rustc rustc -vV | sed -n 's/^release: //p'; }
versions() {
  printf 'nixpkgs\t%s\n' "$(tool jq jq -r '.nodes.nixpkgs.locked.rev[:7]' flake.lock)"
  printf 'rustc\t%s\n' "$(rustc_release)"
  printf 'Racket\t%s\n' "$(tool racket racket -e '(display (version))')"
  printf 'polars crate\t%s\n' \
    "$(sed -n '/^name = "polars"$/{n;s/^version = "\(.*\)"$/\1/p;}' rust/Cargo.lock)"
  printf 'manylinux2014\t%s\n' \
    "$(sed -n "s|^MANYLINUX_IMAGE=$image_repo:\([^@]*\)@.*|\1|p" scripts/build-so.sh)"
}

before="$(versions)"
if [[ -n "$bench" ]]; then
  echo ">> bench before"
  nix run .#bench | tee "$out/bench-before.txt"
fi

echo ">> nix flake update"
nix flake update

release="$(rustc_release)"
[[ -n "$release" ]] || die "no rustc release from the updated nixpkgs"
echo ">> release toolchain: rustc $release"
sed -i.orig "s/^channel = \".*\"$/channel = \"$release\"/" rust/rust-toolchain.toml
rm rust/rust-toolchain.toml.orig

tags="$(curl -fsS "https://quay.io/api/v1/repository/${image_repo#quay.io/}/tag/?onlyActiveTags=true&limit=20")"
digest="$(tool jq jq -r '.tags[] | select(.name == "latest") | .manifest_digest' <<< "$tags")"
[[ "$digest" == sha256:* ]] || die "quay.io lists no latest $image_repo"
dated="$(tool jq jq -r --arg d "$digest" \
  '[.tags[] | select(.name != "latest" and .manifest_digest == $d) | .name] | max // "latest"' \
  <<< "$tags")"
echo ">> manylinux2014 image: $dated ($digest)"
sed -i.orig "s|^MANYLINUX_IMAGE=.*|MANYLINUX_IMAGE=$image_repo:$dated@$digest|" scripts/build-so.sh
rm scripts/build-so.sh.orig

echo ">> cargo update"
nix shell --inputs-from . nixpkgs#cargo nixpkgs#rustc \
  --command cargo update --manifest-path rust/Cargo.toml

# racket-deps is fixed-output: a store that already holds it never refetches,
# so only a rebuild shows that the catalog still serves the pinned hash.
echo ">> racket-deps against its pinned hash"
nix build --no-link .#racket-deps
nix build --no-link --rebuild .#racket-deps

echo ">> nix flake check"
nix flake check

if [[ -n "$bench" ]]; then
  echo ">> bench after"
  nix run .#bench | tee "$out/bench-after.txt"
fi

after="$(versions)"
moved="$(paste <(printf '%s\n' "$before") <(printf '%s\n' "$after" | cut -f2))"
title="build: refresh the toolchain (rustc $release, nixpkgs $(head -1 <<< "$after" | cut -f2))"

cat > "$out/commit-msg.txt" <<EOF
$title

scripts/refresh-toolchain.sh moved nixpkgs, the release rustc, the
manylinux2014 image and the crates within their semver ranges:

$(awk -F'\t' '{ printf "- %s: %s -> %s\n", $1, $2, $3 }' <<< "$moved")
EOF

{
  echo "The periodic toolchain refresh (polars/native-libs/BUILDING.md), by"
  echo "\`scripts/refresh-toolchain.sh\`."
  echo
  echo "| | before | after |"
  echo "|---|---|---|"
  awk -F'\t' '{ printf "| %s | %s | %s |\n", $1, $2, $3 }' <<< "$moved"
  echo
  echo "\`nix flake check\` passed, and racket-deps still matches its pinned hash."
  if [[ -n "$bench" ]]; then
    for when in before after; do
      echo
      echo "Bench $when:"
      echo
      echo '```'
      cat "$out/bench-$when.txt"
      echo '```'
    done
  fi
  echo
  echo "The committed candidates are refreshed from this PR's CI run"
  echo "(\`scripts/refresh-candidates.sh <PR>\`)."
} > "$out/pr-body.md"

git diff --stat
cat <<EOF

>> the refresh is in the working tree; to open its PR:
   git commit -a -F $out/commit-msg.txt
   git push -u origin HEAD
   gh pr create --title "$title" --body-file - < $out/pr-body.md
>> then, once the PR's CI has built both candidates:
   scripts/refresh-candidates.sh <PR>
EOF
