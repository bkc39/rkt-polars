#!/usr/bin/env bash
#
# Refresh the committed libcompat candidates from a CI run's build artifacts;
# see polars/native-libs/BUILDING.md.
#
#   scripts/refresh-candidates.sh [--dir DIR] PR
#   scripts/refresh-candidates.sh [--dir DIR] --run RUN_ID
set -euo pipefail

die() { echo "refresh-candidates: $*" >&2; exit 1; }
usage() {
  echo "usage: scripts/refresh-candidates.sh [--dir DIR] (PR | --run RUN_ID)" >&2
  exit 2
}

dir="$HOME/rkt-polars-candidates"
pr=""
run=""
while (( $# )); do
  case "$1" in
    --dir) dir="${2:?}"; shift 2 ;;
    --run) run="${2:?}"; shift 2 ;;
    [0-9]*) pr="$1"; shift ;;
    *) usage ;;
  esac
done
[[ -n "$pr$run" && ( -z "$pr" || -z "$run" ) ]] || usage
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
if [[ "$(command -v gh)" == /snap/* && "$dir" =~ /\. ]]; then
  die "the snap gh cannot write under a hidden directory; pass --dir outside one"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# The load check needs this checkout's dev shell: one entered from another
# worktree links that worktree's polars collection.
if [[ -z "${REFRESH_CANDIDATES_IN_DEV_SHELL:-}" ]]; then
  REFRESH_CANDIDATES_IN_DEV_SHELL=1 exec nix develop --command \
    "$ROOT/scripts/refresh-candidates.sh" --dir "$dir" ${pr:+"$pr"} ${run:+--run "$run"}
fi

cand=polars/native-libs/candidates

if [[ -n "$pr" ]]; then
  sha="$(gh pr view "$pr" --json headRefOid -q .headRefOid)"
  run="$(gh api "repos/{owner}/{repo}/actions/runs?head_sha=$sha" \
           --jq '[.workflow_runs[] | select(.path == ".github/workflows/ci.yml")]
                 | sort_by(.event != "pull_request") | .[0].id // empty')"
  [[ -n "$run" ]] \
    || die "no CI run for ${sha:0:7}, the head of #$pr: a PR that conflicts with its" \
           "base gets none; merge the base and push, or run" \
           "\`gh workflow run ci.yml --ref <branch>\` and pass --run"
fi
IFS=$'\t' read -r sha event < <(gh api "repos/{owner}/{repo}/actions/runs/$run" --jq '[.head_sha, .event] | @tsv')
[[ -n "$pr" ]] || pr="$(gh api "repos/{owner}/{repo}/commits/$sha/pulls" --jq '.[0].number // empty')"
if [[ -n "$pr" ]]; then ref="#$pr"; else ref="run $run"; fi
echo ">> run $run is the $event run for ${sha:0:7} ($ref)"

git cat-file -e "$sha^{commit}" 2>/dev/null || git fetch --quiet origin "$sha"
tree="$(git rev-parse HEAD:rust)"
[[ "$(git rev-parse "$sha:rust")" == "$tree" ]] \
  || die "${sha:0:7}'s rust/ differs from HEAD's; check out ${sha:0:7}"
[[ -z "$(git status --porcelain -- rust)" ]] || die "rust/ has uncommitted changes"

artifacts() {
  gh api "repos/{owner}/{repo}/actions/runs/$run/artifacts" \
    --jq '[.artifacts[] | select((.name | startswith("libcompat-")) and (.expired | not))
           | .name] | sort | join(",")'
}
failed_builds() {
  gh api --paginate "repos/{owner}/{repo}/actions/runs/$run/jobs" \
    --jq '.jobs[] | select((.name | contains("Build libcompat")) and .status == "completed"
                           and .conclusion != "success") | .name'
}
until [[ "$(artifacts)" == libcompat-darwin,libcompat-linux ]]; do
  [[ -z "$(failed_builds)" ]] || die "a Build libcompat job of run $run did not succeed"
  [[ "$(gh api "repos/{owner}/{repo}/actions/runs/$run" --jq .status)" != completed ]] \
    || die "run $run finished without both libcompat artifacts"
  (( SECONDS < 90 * 60 )) || die "gave up after 90 minutes waiting for run $run's artifacts"
  echo ">> waiting for run $run's Build libcompat jobs ($(date -u +%H:%MZ))"
  sleep 60
done

out="$dir/$run"
rm -rf "$out"
for platform in linux darwin; do
  gh run download "$run" -n "libcompat-$platform" -D "$out/$platform"
done
linux="$out/linux/libcompat.so"
darwin="$out/darwin/libcompat.dylib"

# A pull_request run builds the head's merge with its base branch, so the
# rust/ tree its build recorded must be HEAD's.  A push run older than the
# record built the head itself, which the check above covers.
for platform in linux darwin; do
  if [[ -f "$out/$platform/rust-tree" ]]; then
    [[ "$(< "$out/$platform/rust-tree")" == "$tree" ]] \
      || die "run $run built libcompat-$platform from a rust/ other than HEAD's" \
             "(a $event run of ${sha:0:7}); merge the base branch into this one," \
             "push, and refresh from the new commit's run"
  else
    [[ "$event" == push ]] \
      || die "run $run does not record which rust/ it built libcompat-$platform from;" \
             "pass --run with the push run for ${sha:0:7}, if it has one"
  fi
done

# build-so.sh records the toolchain that built each candidate (a run older
# than the record has none); rust/rust-toolchain.toml pins the flake's rustc,
# which is this dev shell's.
flake_rustc="$(rustc -vV | sed -n 's/^release: //p')"
toolchains=()
for platform in linux darwin; do
  record="$out/$platform/toolchain"
  if [[ -f "$record" ]]; then
    release="$(sed -n 's/^release: //p' "$record")"
    [[ "$release" == "$flake_rustc" ]] \
      || die "run $run built libcompat-$platform with rustc ${release:-unknown}, the flake's" \
             "is $flake_rustc; rust/rust-toolchain.toml must pin it (nix flake check)"
    built="$(head -1 "$record"), LLVM $(sed -n 's/^LLVM version: //p' "$record")"
    built+="$(sed -n 's/^image: /, in /p; s/^ld: /, ld /p' "$record")"
  else
    built="not recorded"
  fi
  echo ">> libcompat-$platform built by: $built"
  toolchains+=("- $platform: $built")
done

if cmp -s "$linux" "$cand/linux/libcompat.so" && cmp -s "$darwin" "$cand/darwin/libcompat.dylib"; then
  echo ">> the committed candidates are already run $run's; nothing to do"
  exit 0
fi

echo ">> checking the binaries"
bullets="$(python3 scripts/verify-candidates.py "$linux" "$darwin" --against "$cand/linux/libcompat.so")"
echo "$bullets"

case "$(uname -s)" in
  Linux)  host=linux  staged=polars/native-libs/libcompat.so    candidate="$linux" ;;
  Darwin) host=darwin staged=polars/native-libs/libcompat.dylib candidate="$darwin" ;;
  *) die "no candidate loads on $(uname -s)" ;;
esac
echo ">> instantiating every module against the $host candidate"
find polars/private -name '*.rkt' -print0 | xargs -0 raco make
restore() { rm -f "$staged"; [[ ! -e "$staged.orig" ]] || mv "$staged.orig" "$staged"; }
[[ ! -e "$staged" ]] || mv "$staged" "$staged.orig"
trap restore EXIT
cp "$candidate" "$staged"
racket scripts/check-bindings.rkt || die "the $host candidate does not load against this checkout"

install -m 755 "$linux" "$cand/linux/libcompat.so"
install -m 755 "$darwin" "$cand/darwin/libcompat.dylib"

msg="$out/commit-msg.txt"
cat > "$msg" <<EOF
native: refresh both libcompat candidates ($ref)

Both are CI's artifacts from run $run (the $event run for ${sha:0:7}),
built by scripts/build-so.sh from this commit's rust/ with

$(printf '%s\n' "${toolchains[@]}")

scripts/refresh-candidates.sh checked them:

$bullets
- Every module under polars/private instantiates against the $host
  candidate.
EOF
echo
cat "$msg"
echo
echo ">> staged in $cand; to commit:"
echo "   git add $cand && git commit -F $msg"
