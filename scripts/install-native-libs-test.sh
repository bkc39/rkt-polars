#!/usr/bin/env bash
#
# The install-native-libs gate (#265). A copy over a differing library gives
# the target a new inode, and a descriptor opened on the old file still reads
# the old bytes; an identical library keeps its inode and mtime; a failing
# cp, mv or read-only directory leaves no temporary file and the target as it
# was; a read-only source installs as 0755. Every libcompat.* the glob matches
# is handled on its own, and .gitignore covers the temporary file. The first
# check is also run against `cp -f`, which it must catch.
#
# Usage: scripts/install-native-libs-test.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
script=$here/install-native-libs.sh
work=$(mktemp -d)
trap 'chmod -R u+w "$work" 2> /dev/null; rm -rf "$work"' EXIT
base_path=$PATH

status=0
fail() {
  status=1
  echo "FAIL: $*" >&2
}

inode() { stat -c %i "$1"; }
mtime() { stat -c %Y "$1"; }
mode() { stat -c %a "$1"; }

cat > "$work/cp-f.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
cp -f "$1"/libcompat.* "$2"/
EOF

fresh() {
  rm -rf "$work/src" "$work/dest"
  mkdir -p "$work/src" "$work/dest"
}

leftovers() {
  find "$1" -name '.libcompat.*' | wc -l
}

# Prints nothing when INSTALLER replaces the target as #265 requires.
replaces() {
  local installer=$1 fd before reasons=
  fresh
  printf 'old library bytes\n' > "$work/dest/libcompat.so"
  printf 'new library bytes, longer\n' > "$work/src/libcompat.so"
  before=$(inode "$work/dest/libcompat.so")
  exec {fd}< "$work/dest/libcompat.so"
  bash "$installer" "$work/src" "$work/dest" || reasons+="status $?; "
  [ "$(inode "$work/dest/libcompat.so")" != "$before" ] || reasons+="same inode; "
  [ "$(cat <&"$fd")" = "old library bytes" ] || reasons+="the open descriptor reads new bytes; "
  exec {fd}<&-
  [ "$(cat "$work/dest/libcompat.so")" = "new library bytes, longer" ] \
    || reasons+="the target does not hold the new bytes; "
  [ "$(leftovers "$work/dest")" -eq 0 ] || reasons+="a temporary file is left; "
  printf '%s' "${reasons%; }"
}

got=$(replaces "$script")
if [ -z "$got" ]; then
  echo "ok: a differing library gets a new inode, the old one stays readable"
else
  fail "differing library: $got"
fi
got=$(replaces "$work/cp-f.sh")
if [ -n "$got" ]; then
  echo "ok: the same check catches cp -f ($got)"
else
  fail "the check does not catch cp -f"
fi

fresh
printf 'same bytes\n' > "$work/src/libcompat.so"
printf 'same bytes\n' > "$work/dest/libcompat.so"
touch -d @1000000000 "$work/dest/libcompat.so"
before="$(inode "$work/dest/libcompat.so") $(mtime "$work/dest/libcompat.so")"
if ! bash "$script" "$work/src" "$work/dest"; then
  fail "identical library: status $?"
elif [ "$(inode "$work/dest/libcompat.so") $(mtime "$work/dest/libcompat.so")" != "$before" ]; then
  fail "identical library: inode and mtime moved from [$before]"
else
  echo "ok: an identical library keeps its inode and mtime"
fi

fresh
printf 'same\n' > "$work/src/libcompat.so"
printf 'same\n' > "$work/dest/libcompat.so"
printf 'new dylib\n' > "$work/src/libcompat.dylib"
printf 'old dylib\n' > "$work/dest/libcompat.dylib"
same_inode=$(inode "$work/dest/libcompat.so")
dylib_inode=$(inode "$work/dest/libcompat.dylib")
if ! bash "$script" "$work/src" "$work/dest"; then
  fail "two libraries: status $?"
elif [ "$(inode "$work/dest/libcompat.so")" != "$same_inode" ] \
  || [ "$(inode "$work/dest/libcompat.dylib")" = "$dylib_inode" ] \
  || [ "$(cat "$work/dest/libcompat.dylib")" != "new dylib" ]; then
  fail "two libraries: each was not decided on its own"
else
  echo "ok: each library the glob matches is decided on its own"
fi

fresh
printf 'store bytes\n' > "$work/src/libcompat.so"
chmod 0555 "$work/src/libcompat.so"
if ! bash "$script" "$work/src" "$work/dest"; then
  fail "read-only source: status $?"
elif [ "$(mode "$work/dest/libcompat.so")" != 755 ]; then
  fail "read-only source: the target is $(mode "$work/dest/libcompat.so"), not 755"
else
  chmod u+w "$work/src/libcompat.so"
  printf 'next store bytes\n' > "$work/src/libcompat.so"
  chmod 0555 "$work/src/libcompat.so"
  if ! bash "$script" "$work/src" "$work/dest"; then
    fail "read-only source, second install: status $?"
  elif [ "$(cat "$work/dest/libcompat.so")" != "next store bytes" ] \
    || [ "$(mode "$work/dest/libcompat.so")" != 755 ]; then
    fail "read-only source, second install: the target is not the new 0755 copy"
  else
    echo "ok: a 0555 source installs as 0755 and is replaced again"
  fi
fi
chmod -R u+w "$work/src"

fresh
printf 'new\n' > "$work/src/libcompat.so"
if ! bash "$script" "$work/src" "$work/dest/missing"; then
  fail "missing destination: status $?"
elif [ "$(cat "$work/dest/missing/libcompat.so")" != "new" ]; then
  fail "missing destination: no copy"
else
  echo "ok: a missing destination is created"
fi

fresh
if bash "$script" "$work/src" "$work/dest" 2> "$work/err"; then
  fail "no library: status 0"
elif ! grep -qF "no libcompat.* in $work/src" "$work/err"; then
  fail "no library: stderr is [$(cat "$work/err")]"
else
  echo "ok: a source with no library is an error"
fi

stub() {
  mkdir -p "$work/$1"
  printf '#!%s\n%s\n' "$(command -v bash)" "$3" > "$work/$1/$2"
  chmod +x "$work/$1/$2"
}
# shellcheck disable=SC2016
stub failing-cp cp 'printf partial > "${@: -1}"; exit 1'
stub failing-mv mv 'exit 1'

refused() {
  local label=$1 before
  shift
  fresh
  printf 'old\n' > "$work/dest/libcompat.so"
  printf 'new\n' > "$work/src/libcompat.so"
  before=$(inode "$work/dest/libcompat.so")
  "$@"
  if env PATH="${path_prefix:-}$base_path" bash "$script" "$work/src" "$work/dest" 2> /dev/null; then
    fail "$label: status 0"
  elif [ "$(leftovers "$work/dest")" -ne 0 ]; then
    fail "$label: a temporary file is left: [$(ls -A "$work/dest")]"
  elif [ "$(inode "$work/dest/libcompat.so")" != "$before" ] \
    || [ "$(cat "$work/dest/libcompat.so")" != "old" ]; then
    fail "$label: the target changed"
  else
    echo "ok: $label leaves no temporary file and the target as it was"
  fi
  chmod -R u+w "$work/dest"
}

path_prefix="$work/failing-cp:" refused "a failing cp" true
path_prefix="$work/failing-mv:" refused "a failing mv" true
if [ "$(id -u)" -eq 0 ]; then
  echo "skip: a read-only directory (running as root, which writes through it)"
else
  refused "a read-only directory" chmod a-w "$work/dest"
fi

repo=$(cd "$here/.." && pwd -P)
sample=polars/native-libs/.libcompat.so.Ab12Cd
ignore_repo=$work/ignore-repo
if ! command -v git > /dev/null; then
  fail "git is needed to check that .gitignore covers $sample"
else
  git init -q --template= "$ignore_repo"
  cp "$repo/.gitignore" "$ignore_repo/.gitignore"
  if git -C "$ignore_repo" -c core.excludesFile=/dev/null \
    check-ignore -q "$sample"; then
    echo "ok: .gitignore covers a killed install's temporary file $sample"
  else
    fail ".gitignore does not cover $sample"
  fi
fi

exit $status
