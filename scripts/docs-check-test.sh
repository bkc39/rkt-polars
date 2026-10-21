#!/usr/bin/env bash
#
# The docs-check-test gate: scripts/docs-check.sh against fixture raco setup
# logs and rendered manuals (scripts/docs-check-fixtures/), through --scan,
# and through its raco setup run with raco, racket and tee stubbed.
#
# Usage: scripts/docs-check-test.sh
set -euo pipefail

scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script="$scripts/docs-check.sh"
fixtures="$scripts/docs-check-fixtures"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export TMPDIR="$work"
unset GITHUB_ACTIONS DOCS_CHECK_SETUP_FLAGS DOCS_CHECK_PKG

status=0
fail() {
  status=1
  echo "FAIL: $*" >&2
}

# manual NAME [FIXTURE]: a copy of a fixture manual (default: the clean one)
# at $work/NAME, so a scan records its warnings beside it, not in the repo.
manual() {
  rm -rf "${work:?}/$1" "$work/$1.docs-check-warnings"
  cp -r "$fixtures/${2:-manual}" "$work/$1"
  printf '%s' "$work/$1"
}

# expect LABEL WANT-STATUS COMMAND...: runs COMMAND, holding its exit status
# to WANT-STATUS; its stdout and stderr are left in $out.
out=""
expect() {
  local label=$1 want=$2 got=0
  shift 2
  out=$("$@" 2>&1) || got=$?
  if [ "$got" -ne "$want" ]; then
    fail "$label: exit $got, not $want; output:"$'\n'"$out"
    return 1
  fi
  echo "ok: $label"
}

# has LABEL TEXT: $out holds TEXT.
has() {
  if ! grep -qF -- "$2" <<< "$out"; then
    fail "$1: output lacks [$2]:"$'\n'"$out"
  fi
}

lacks() {
  if grep -qF -- "$2" <<< "$out"; then
    fail "$1: output has [$2]:"$'\n'"$out"
  fi
}

scan() {
  bash "$script" --scan "$@"
}

# shellcheck disable=SC2329 # called through expect
run() {
  PATH="$fixtures/bin:$PATH" bash "$script" "$@"
}

dir=$(manual undefined)
if expect "undefined tag" 1 scan "$fixtures/undefined-tag.log" "$dir"; then
  has "undefined tag" 'WARNING: undefined tag in'
  has "undefined tag" '((lib "threading/main.rkt") ~>)'
  has "undefined tag" '((lib "polars/main.rkt") no-such-verb)'
  has "undefined tag" 'run: raco setup --pkgs threading-doc'
  lacks "undefined tag" 'rendering:'
fi

dir=$(manual multiple)
if expect "key collected multiple times" 1 scan "$fixtures/multiple-times.log" "$dir"; then
  has "key collected multiple times" 'collected information for key multiple times'
fi

dir=$(manual badlink badlink-manual)
if expect "badlink" 1 scan "$fixtures/clean-render.log" "$dir"; then
  has "badlink" 'undefined links (badlink)'
  has "badlink" '<font class="badlink">~&gt;'
  has "badlink" 'run: raco setup --pkgs threading-doc'
fi

dir=$(manual clean)
if expect "clean render" 0 scan "$fixtures/clean-render.log" "$dir"; then
  has "clean render" 'no undefined tags, duplicate keys or badlinks'
  [ -f "$dir.docs-check-warnings" ] && [ ! -s "$dir.docs-check-warnings" ] \
    || fail "clean render: no empty record at $dir.docs-check-warnings"
fi

mkdir -p "$work/empty"
if expect "no index.html" 1 scan "$fixtures/clean-render.log" "$work/empty"; then
  has "no index.html" "no rendered manual at $work/empty (no index.html)"
fi

dir=$(manual recorded)
cp "$fixtures/duplicate.warnings" "$dir.docs-check-warnings"
if expect "recorded warning, no render" 1 scan "$fixtures/no-render.log" "$dir"; then
  has "recorded warning, no render" "the manual's last render warned"
  has "recorded warning, no render" 'collected information for key multiple times'
fi

dir=$(manual other-doc)
cp "$fixtures/duplicate.warnings" "$dir.docs-check-warnings"
if expect "recorded warning, another document rendered" 1 \
     scan "$fixtures/other-doc-render.log" "$dir"; then
  has "recorded warning, another document rendered" "the manual's last render warned"
fi

dir=$(manual rerendered)
scan "$fixtures/multiple-times.log" "$dir" > /dev/null 2>&1 || true
if expect "a clean render clears the record" 0 scan "$fixtures/clean-render.log" "$dir"; then
  expect "then a run without a render is clean" 0 scan "$fixtures/no-render.log" "$dir" || true
fi

dir=$(manual unrecorded)
if expect "no render, nothing recorded" 1 scan "$fixtures/no-render.log" "$dir"; then
  has "no render, nothing recorded" "no render's warnings are recorded in $dir.docs-check-warnings"
fi

dir=$(manual record)
if STUB_LOG="$fixtures/multiple-times.log" STUB_DOC_DIR="$dir" \
     expect "--record passes on a warning" 0 run --record; then
  has "--record passes on a warning" 'collected information for key multiple times'
fi
if STUB_LOG="$fixtures/no-render.log" STUB_DOC_DIR="$dir" \
     expect "then a check without a render" 1 run; then
  has "then a check without a render" "the manual's last render warned"
fi

dir=$(manual setup-fails)
if STUB_LOG="$fixtures/clean-render.log" STUB_RACO_STATUS=1 \
     expect "raco setup fails" 1 run "$dir"; then
  has "raco setup fails" 'docs-check: raco setup failed'
fi

dir=$(manual tee-fails)
if STUB_LOG="$fixtures/clean-render.log" PATH="$fixtures/failing-tee:$PATH" \
     expect "tee fails" 1 run "$dir"; then
  has "tee fails" 'docs-check: could not write the raco setup log'
  lacks "tee fails" 'raco setup failed'
fi

if STUB_LOG="$fixtures/clean-render.log" expect "collection lookup fails" 1 run; then
  has "collection lookup fails" "docs-check: could not find the installed polars collection"
fi

dir=$(manual stale)
if STUB_LOG="$fixtures/no-render.log" STUB_RENDER_INTO="$dir" \
     expect "nothing recorded: renders again" 0 run "$dir"; then
  has "nothing recorded: renders again" 'rendering the manual again'
  [ -f "$dir.docs-check-warnings" ] \
    || fail "nothing recorded: renders again: no record at $dir.docs-check-warnings"
fi

exit $status
