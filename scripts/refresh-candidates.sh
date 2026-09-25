#!/usr/bin/env bash
#
# Refresh the committed libcompat candidates from a CI run's build artifacts.
#
#   scripts/refresh-candidates.sh [--dir DIR] PR
#   scripts/refresh-candidates.sh [--dir DIR] --run RUN_ID
#
# Takes the push-event CI run for the PR's head commit (a pull_request run
# builds the merge with master, not the head) and refuses unless that
# commit's rust/ is this checkout's.  Waits for the run's Build libcompat
# jobs, downloads both artifacts under DIR/<run> (default
# ~/rkt-polars-candidates: the snap gh cannot write under a hidden
# directory), checks them with verify-candidates.py and, with this host's
# candidate staged, check-bindings.rkt, then copies them into
# polars/native-libs/candidates/ and writes a commit message.  Re-runs
# itself inside `nix develop`, whose Racket and package links the load
# check needs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "${REFRESH_CANDIDATES_IN_DEV_SHELL:-}" ]]; then
  REFRESH_CANDIDATES_IN_DEV_SHELL=1 exec nix develop --command "$ROOT/scripts/refresh-candidates.sh" "$@"
fi

die() { echo "refresh-candidates: $*" >&2; exit 1; }
usage() { sed -n '5,6p' "$0" | sed 's/^# *//' >&2; exit 2; }

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
if [[ -n "$pr" && -n "$run" ]] || [[ -z "$pr" && -z "$run" ]]; then usage; fi

if [[ "$(command -v gh)" == /snap/* && "$dir" =~ /\. ]]; then
  die "the snap gh cannot write under a hidden directory; pass --dir outside one"
fi
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"

repo="$(git remote get-url origin | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##')"
cand=polars/native-libs/candidates

if [[ -n "$pr" ]]; then
  sha="$(gh pr view "$pr" -R "$repo" --json headRefOid -q .headRefOid)"
  run="$(gh api "repos/$repo/actions/runs?head_sha=$sha&event=push" \
           --jq '[.workflow_runs[] | select(.path == ".github/workflows/ci.yml")][0].id // empty')"
  [[ -n "$run" ]] || die "no push-event CI run for ${sha:0:7}, the head of #$pr"
else
  IFS=$'\t' read -r sha event < <(gh api "repos/$repo/actions/runs/$run" --jq '[.head_sha, .event] | @tsv')
  [[ "$event" == push ]] \
    || die "run $run is a $event run, which builds the merge with master; pass the push run for ${sha:0:7}"
  pr="$(gh api "repos/$repo/commits/$sha/pulls" --jq '.[0].number // empty')"
fi
ref="${pr:+#$pr}"
ref="${ref:-run $run}"
echo ">> run $run built ${sha:0:7} ($ref)"

git cat-file -e "$sha^{commit}" 2>/dev/null || git fetch --quiet origin "$sha"
[[ "$(git rev-parse "$sha:rust")" == "$(git rev-parse HEAD:rust)" ]] \
  || die "${sha:0:7}'s rust/ differs from HEAD's; check out the commit the run built"
[[ -z "$(git status --porcelain -- rust)" ]] || die "rust/ has uncommitted changes"

artifacts() {
  gh api "repos/$repo/actions/runs/$run/artifacts" \
    --jq '[.artifacts[] | select(.expired | not) | .name] | sort | join(",")'
}
failed_builds() {
  gh api --paginate "repos/$repo/actions/runs/$run/jobs" \
    --jq '.jobs[] | select((.name | contains("Build libcompat")) and .status == "completed"
                           and .conclusion != "success") | .name'
}
deadline=$(( SECONDS + 90 * 60 ))
until [[ "$(artifacts)" == libcompat-darwin,libcompat-linux ]]; do
  failed="$(failed_builds)"
  [[ -z "$failed" ]] || die "run $run: ${failed//$'\n'/, } did not succeed"
  [[ "$(gh api "repos/$repo/actions/runs/$run" --jq .status)" != completed ]] \
    || die "run $run finished without both libcompat artifacts (expired, or never uploaded)"
  (( SECONDS < deadline )) || die "gave up after 90 minutes waiting for run $run's artifacts"
  echo ">> waiting for run $run's Build libcompat jobs ($(date -u +%H:%MZ))"
  sleep 60
done

out="$dir/$run"
rm -rf "$out"
for platform in linux darwin; do
  gh run download "$run" -R "$repo" -n "libcompat-$platform" -D "$out/$platform"
done
linux="$out/linux/libcompat.so"
darwin="$out/darwin/libcompat.dylib"

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
restore
trap - EXIT

install -m 755 "$linux" "$cand/linux/libcompat.so"
install -m 755 "$darwin" "$cand/darwin/libcompat.dylib"

msg="$out/commit-msg.txt"
cat > "$msg" <<EOF
native: refresh both libcompat candidates ($ref)

The catalog installs these committed binaries, and define-compat
resolves every symbol at module load (polars/native-libs/BUILDING.md).
Both are CI's artifacts from run $run on ${sha:0:7}, built by
scripts/build-so.sh, and scripts/refresh-candidates.sh checked them:

$bullets
- Every module under polars/private instantiates against the $host
  candidate.
EOF
echo
cat "$msg"
echo
echo ">> staged in $cand; to commit:"
echo "   git add $cand && git commit -F $msg"
