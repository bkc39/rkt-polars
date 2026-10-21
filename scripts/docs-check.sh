#!/usr/bin/env bash
#
# The docs gate: builds the manual with raco setup and fails on an undefined
# tag or on information collected for a key multiple times (a duplicated
# defproc).  raco setup reports both as warnings and exits 0, and it reports
# them only on a run that runs or renders the manual.  So a run that renders
# it records the warnings in DOC-DIR.docs-check-warnings, and a run that does
# not reads them back; the rendered HTML is also searched for Scribble's
# badlink, which a run with nothing to rebuild leaves in place.
#
# Usage:
#   scripts/docs-check.sh [DOC-DIR]      raco setup over the package, then check
#   scripts/docs-check.sh --record       raco setup over the package, recording
#                                        and printing its warnings, failing
#                                        only when raco setup fails (the dev
#                                        shell's setup on entry)
#   scripts/docs-check.sh --scan LOG DOC-DIR
#                                        check a raco setup log and DOC-DIR
#
#   DOC-DIR is the rendered manual (default: doc/polars under the installed
#   polars collection).  The package is DOCS_CHECK_PKG (default rkt-polars;
#   scripts/test-local.sh installs it as polars).  Extra raco setup flags go
#   in DOCS_CHECK_SETUP_FLAGS, e.g. "-j 4".
set -euo pipefail

report() {
  local message=$1
  echo "docs-check: $message" >&2
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error::docs-check: $message"
  fi
}

# Whether LOG shows raco setup running or rendering the manual.
rendered() {
  grep -qE '^raco setup: ([0-9]+ )?(re-)?(running|rendering): .*/polars/scribblings/polars\.scrbl$' "$1"
}

# The warnings in LOG; each undefined tag follows its warning on a line of
# its own, indented.
log_warnings() {
  awk '/undefined tag|multiple times/ { keys = 1; print; next }
       keys && /^raco setup:  / { print; next }
       { keys = 0 }' "$1"
}

# scan LOG DOC-DIR: 0 when clean, 1 when not, 2 when LOG shows no render and
# no render's warnings are recorded.
scan() {
  local log=$1 doc_dir=${2%/}
  local record="$doc_dir.docs-check-warnings"
  local status=0 warnings recorded="" badlinks=""

  warnings=$(log_warnings "$log")
  if [ -f "$doc_dir/index.html" ]; then
    badlinks=$(grep -rnoE --include='*.html' '<font class="badlink">.{0,160}' "$doc_dir" || true)
  else
    report "no rendered manual at $doc_dir (no index.html)"
    status=1
  fi

  if rendered "$log"; then
    if [ -d "$doc_dir" ] && ! printf '%s' "$warnings" > "$record"; then
      report "could not record the render's warnings in $record"
      status=1
    fi
  elif [ -f "$record" ]; then
    recorded=$(cat "$record")
  elif [ "$status" -eq 0 ]; then
    report "raco setup did not render the manual, and no render's warnings are recorded in $record"
    status=2
  fi

  if [ -n "$warnings" ]; then
    status=1
    report "raco setup warned (it exits 0 on these):"
    printf '%s\n' "$warnings" >&2
  fi
  if [ -n "$recorded" ]; then
    status=1
    report "the manual's last render warned (recorded in $record):"
    printf '%s\n' "$recorded" >&2
  fi
  if [ -n "$badlinks" ]; then
    status=1
    report "the rendered manual has undefined links (badlink):"
    printf '%s\n' "$badlinks" >&2
  fi
  if printf '%s\n%s\n%s\n' "$warnings" "$recorded" "$badlinks" | grep -qE 'threading|~>|~&gt;'; then
    report "the threading docs are not rendered; run: raco setup --pkgs threading-doc"
  fi

  if [ "$status" -eq 0 ]; then
    echo "docs-check: no undefined tags, duplicate keys or badlinks in $doc_dir"
  fi
  return "$status"
}

# setup LOG: raco setup over the package, its output copied to LOG.
setup() {
  local log=$1 statuses
  set +e
  # --pkgs of one package renders its manual and no other document that
  # defines bindings, so a key collected multiple times, whose warning names
  # no document, is this manual's.
  # shellcheck disable=SC2086
  raco setup ${DOCS_CHECK_SETUP_FLAGS:-} --check-pkg-deps --unused-pkg-deps \
    --pkgs "${DOCS_CHECK_PKG:-rkt-polars}" 2>&1 | tee "$log"
  statuses=("${PIPESTATUS[@]}")
  set -e
  if [ "${statuses[1]}" -ne 0 ]; then
    report "could not write the raco setup log to $log"
    return 1
  fi
  if [ "${statuses[0]}" -ne 0 ]; then
    report "raco setup failed"
    return 1
  fi
}

default_doc_dir() {
  if ! racket -e '(display (build-path (collection-path "polars") "doc" "polars"))'; then
    report "could not find the installed polars collection's doc directory"
    return 1
  fi
}

if [ "${1:-}" = "--scan" ]; then
  if [ "$#" -ne 3 ]; then
    echo "usage: $0 --scan LOG DOC-DIR" >&2
    exit 64
  fi
  scan "$2" "$3" || exit 1
  exit 0
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! log=$(mktemp "${TMPDIR:-/tmp}/docs-check.XXXXXX"); then
  report "could not create a log file in ${TMPDIR:-/tmp}"
  exit 1
fi
trap 'rm -f "$log"' EXIT

if [ "${1:-}" = "--record" ]; then
  setup "$log" || exit 1
  doc_dir=$(default_doc_dir) || exit 1
  scan "$log" "$doc_dir" || true
  exit 0
fi

status=0
setup "$log" || status=1
if [ -n "${1:-}" ]; then
  doc_dir=$1
else
  doc_dir=$(default_doc_dir) || exit 1
fi

scan "$log" "$doc_dir" || scanned=$?
case "${scanned:-0}" in
  0) ;;
  2)
    # Nothing recorded the warnings of the render that left DOC-DIR, so drop
    # it and render again.
    rm -rf -- "$doc_dir"
    echo "docs-check: rendering the manual again to record its warnings" >&2
    setup "$log" || status=1
    scan "$log" "$doc_dir" || status=1
    ;;
  *) status=1 ;;
esac
exit "$status"
