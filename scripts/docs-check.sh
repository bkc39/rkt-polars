#!/usr/bin/env bash
#
# The docs gate: builds the manual with raco setup and fails on an undefined
# tag or on information collected for a key multiple times (a duplicated
# defproc).  raco setup reports both as warnings and exits 0, and it reports
# them only on a run that runs or renders the manual.  So a run that renders
# it records the warnings in DOC-DIR.docs-check-warnings, under a copy of
# DOC-DIR/stamp.sxref, Scribble's build stamp, and a run that does not reads
# them back, unless the manual has been rendered since (by a plain raco
# setup): its stamp differs, or its index.html is newer than the record.
# Where modification times are whole seconds, a plain raco setup that renders
# the manual, while a run records, within the record's second is missed.
# The rendered HTML is also searched for Scribble's badlink, which a run with
# nothing to rebuild leaves in place.  A run that holds no current record
# deletes the stamp, so that raco setup renders the manual again.  Each run
# holds DOC-DIR.docs-check-lock while it renders and records.
#
# Usage:
#   scripts/docs-check.sh [DOC-DIR]      raco setup over the package, then check
#   scripts/docs-check.sh --record       raco setup over the package, recording
#                                        and printing its warnings, failing
#                                        only when raco setup fails (the dev
#                                        shell's setup on entry); it writes no
#                                        GitHub Actions annotations
#   scripts/docs-check.sh --scan LOG DOC-DIR
#                                        check a raco setup log and DOC-DIR
#
#   DOC-DIR is the rendered manual (default: doc/polars under the installed
#   polars collection).  The package is DOCS_CHECK_PKG (default rkt-polars;
#   scripts/test-local.sh installs it as polars).  Extra raco setup flags go
#   in DOCS_CHECK_SETUP_FLAGS, e.g. "-j 4".  A run waits up to
#   DOCS_CHECK_LOCK_TIMEOUT seconds (default 1800) for the lock of another
#   run that is still running.
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
  grep -qE '^raco setup: ([0-9]+ )?(re-)?(running|rendering): .*/polars/scribblings/polars\.scrbl( @ [0-9]+)?$' "$1"
}

# The warnings in LOG; each undefined tag follows its warning on a line of
# its own, indented.
log_warnings() {
  awk '/undefined tag|multiple times/ { keys = 1; print; next }
       keys && /^raco setup:  / { print; next }
       { keys = 0 }' "$1"
}

# stamp DOC-DIR: Scribble's build stamp in DOC-DIR on one line; it names the
# inputs of the last render.  Empty when there is none.
stamp() {
  if [ -f "$1/stamp.sxref" ]; then
    tr -d '\n' < "$1/stamp.sxref"
  fi
}

# scan LOG DOC-DIR: 0 when clean, 1 when not, 2 when LOG shows no render and
# no render's warnings are recorded, or the manual was rendered after they
# were (by a run that did not record them).  The record's first line is the
# stamp of the render it records; its warnings follow.  A render that leaves
# the stamp as it was (one after a dependency's manual changes or appears)
# still rewrites index.html.
scan() {
  local log=$1 doc_dir=${2%/}
  local record="$doc_dir.docs-check-warnings"
  local status=0 warnings recorded="" badlinks="" current

  warnings=$(log_warnings "$log")
  current=$(stamp "$doc_dir")
  if [ -f "$doc_dir/index.html" ]; then
    badlinks=$(grep -rnoE --include='*.html' '<font class="badlink">.{0,160}' "$doc_dir" || true)
  else
    report "no rendered manual at $doc_dir (no index.html)"
    status=1
  fi

  if rendered "$log"; then
    if [ -d "$doc_dir" ] && ! printf '%s\n%s' "$current" "$warnings" > "$record"; then
      report "could not record the render's warnings in $record"
      status=1
    fi
  elif [ -f "$record" ] && [ "$(head -n 1 < "$record")" != "$current" ]; then
    report "raco setup did not render the manual, and it was rendered after its warnings were recorded in $record (its stamp.sxref differs)"
    status=2
  elif [ -f "$record" ] && [ "$doc_dir/index.html" -nt "$record" ]; then
    report "raco setup did not render the manual, and it was rendered after its warnings were recorded in $record (its index.html is newer)"
    status=2
  elif [ -f "$record" ]; then
    recorded=$(tail -n +2 < "$record")
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

held_lock=""
log=""
refused=""

# release LINK: removes LINK if it names this run.
release() {
  if [ "$(readlink -- "$1" 2> /dev/null)" = "$$" ]; then
    rm -f -- "$1"
  fi
}

# shellcheck disable=SC2329 # called by the EXIT trap
cleanup() {
  if [ -n "$log" ]; then
    rm -f -- "$log"
  fi
  if [ -n "$held_lock" ]; then
    release "$held_lock"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# gone PID: PID names no running process other than this one.
gone() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]] || return 0
  [ "$1" != "$$" ] || return 0
  ! kill -0 "$1" 2> /dev/null && ! ps -p "$1" > /dev/null 2>&1
}

# reap LINK HOLDER: removes LINK if it still names HOLDER and HOLDER is not
# running, holding LINK.reap meanwhile, so that no waiter removes a lock
# another has just taken in its place.  A LINK.reap whose holder is not
# running is reaped first, the same way.  1 when it removes nothing; a
# LINK.reap that is not a symbolic link, where ln -s would make the marker
# inside it and exclude no other reaper, is refused, and named in $refused.
reap() {
  local link=$1 holder=$2 marker="$1.reap" reaper status=1
  if [ -e "$marker" ] && [ ! -L "$marker" ]; then
    refuse_marker "$marker"
    return 1
  fi
  if ! ln -sn -- "$$" "$marker" 2> /dev/null; then
    reaper=$(readlink -- "$marker" 2> /dev/null) || return 1
    gone "$reaper" && reap "$marker" "$reaper" && reap "$link" "$holder"
    return
  fi
  if [ "$(readlink -- "$marker" 2> /dev/null)" != "$$" ]; then
    release "$marker/$$"
    refuse_marker "$marker"
    return 1
  fi
  if [ "$(readlink -- "$link" 2> /dev/null)" = "$holder" ] && gone "$holder" \
       && rm -f -- "$link"; then
    status=0
  fi
  release "$marker"
  return "$status"
}

refuse_marker() {
  refused=$1
  report "$1 is not a docs-check reaper's marker (a symbolic link naming a pid); if no docs-check is running, remove it"
}

# lock DOC-DIR: takes DOC-DIR.docs-check-lock, a symbolic link naming its
# holder's pid, since ln -s creates it with its pid atomically everywhere and
# flock is not on macOS; the EXIT trap releases it.  A lock whose holder is
# not running is removed.
lock() {
  local lock="${1%/}.docs-check-lock" waited=0 absent=0
  local limit=${DOCS_CHECK_LOCK_TIMEOUT:-1800} holder="" said=""
  if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
    report "DOCS_CHECK_LOCK_TIMEOUT is $limit, not a number of seconds"
    return 1
  fi
  if ! mkdir -p -- "$(dirname -- "$lock")"; then
    report "could not create the directory of the lock $lock"
    return 1
  fi
  if [ -e "$lock" ] && [ ! -L "$lock" ]; then
    report "$lock is not a docs-check lock (a symbolic link naming a pid); if no docs-check is running, remove it"
    return 1
  fi
  while ! ln -sn -- "$$" "$lock" 2> /dev/null; do
    if ! holder=$(readlink -- "$lock" 2> /dev/null); then
      absent=$((absent + 1))
      if [ "$absent" -gt 1 ]; then
        report "could not create the lock $lock"
        return 1
      fi
      continue
    fi
    absent=0
    if gone "$holder" && reap "$lock" "$holder"; then
      echo "docs-check: removed $lock, left by pid $holder, which is not running" >&2
      continue
    fi
    if [ -n "$refused" ]; then
      return 1
    fi
    if [ "$waited" -ge "$limit" ]; then
      report "another docs-check has held $lock for over ${limit}s (pid $holder); if none is running, remove it"
      return 1
    fi
    if [ -z "$said" ]; then
      echo "docs-check: waiting for $lock (pid $holder)" >&2
      said=yes
    fi
    sleep 1
    waited=$((waited + 1))
  done
  held_lock=$lock
}

if [ "${1:-}" = "--scan" ]; then
  if [ "$#" -ne 3 ]; then
    echo "usage: $0 --scan LOG DOC-DIR" >&2
    exit 64
  fi
  lock "$3" || exit 1
  scan "$2" "$3" || exit 1
  exit 0
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ "${1:-}" = "--record" ]; then
  unset GITHUB_ACTIONS
  doc_dir=$(default_doc_dir) || exit 1
elif [ -n "${1:-}" ]; then
  doc_dir=$1
else
  doc_dir=$(default_doc_dir) || exit 1
fi
doc_dir=${doc_dir%/}
lock "$doc_dir" || exit 1

if ! log=$(mktemp "${TMPDIR:-/tmp}/docs-check.XXXXXX"); then
  report "could not create a log file in ${TMPDIR:-/tmp}"
  exit 1
fi

if [ "${1:-}" = "--record" ]; then
  setup "$log" || exit 1
  scan "$log" "$doc_dir" || true
  exit 0
fi

status=0
setup "$log" || status=1
scan "$log" "$doc_dir" || scanned=$?
case "${scanned:-0}" in
  0) ;;
  2)
    if ! rm -f -- "$doc_dir/stamp.sxref"; then
      report "could not remove $doc_dir/stamp.sxref to render the manual again"
      exit 1
    fi
    echo "docs-check: rendering the manual again to record its warnings" >&2
    setup "$log" || status=1
    scan "$log" "$doc_dir" || status=1
    ;;
  *) status=1 ;;
esac
exit "$status"
