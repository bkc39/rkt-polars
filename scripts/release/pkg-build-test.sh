#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/release/pins.sh
. "$here/pins.sh"

release_platform x86_64-linux
package=$RELEASE_PACKAGE
say() { echo "pkg-build test${phase:+ ($phase)}: $*"; }

in_container() {
  phase=$1
  export PLTUSERHOME=/work/user PATH="/work/racket/bin:$PATH"
  trap 'cp /work/*.log /logs/ 2>/dev/null || true; chown -R "$HOST_UID:$HOST_GID" /work /cache /logs' EXIT
  case $phase in
    install)
      local status=0
      sh "/cache/${RELEASE_NATIPKG_RACKET##*/}" --in-place --dest /work/racket >/dev/null
      say "Racket $(racket -e '(display (version))') on $(racket -e '(display (system-library-subpath #f))'), uid $(id -u)"
      mkdir -p /work/catalog/pkg /work/files
      cp -R /src/polars /work/files/polars
      raco pkg create --format zip --dest /work/files /work/files/polars
      racket "$here/catalog.rkt" entry polars /work/files/polars /work/files/polars.zip \
        file:///work/files/polars.zip >/work/catalog/pkg/polars
      racket "$here/catalog.rkt" local-entry "/dist/$package.rktd" "file:///dist/$package.zip" \
        >"/work/catalog/pkg/$package"
      listed=$(release_catalogs)
      catalogs=()
      while IFS= read -r catalog; do catalogs+=("$catalog"); done <<<"$listed"
      raco pkg config --set --scope installation catalogs file:///work/catalog "${catalogs[@]}"
      say "raco pkg install --jobs 2 -u --auto polars, with docs"
      raco pkg install --batch --jobs 2 -u --auto polars >/work/install.log 2>&1 || status=$?
      say "raco pkg install exited $status"
      if [ "$status" -ne 0 ] || release_grep -E "raco setup: (error|  error)|setup reported errors" /work/install.log; then
        tail -n 60 /work/install.log
        exit 1
      fi
      release_check_install_log /work/install.log
      racket "$RELEASE_SCRIPTS/check-native-install.rkt" "$package"
      [ -n "$(find "$PLTUSERHOME" -path '*/doc/polars/index.html' -print -quit)" ] || {
        say "no rendered manual under $PLTUSERHOME"
        exit 1
      }
      say "polars and $package installed, manual rendered"
      ;;
    test)
      local status=0
      if timeout 5 bash -c '</dev/tcp/pkgs.racket-lang.org/443' 2>/dev/null; then
        say "the network is reachable; this phase runs with --network none"
        exit 1
      fi
      say "raco test --jobs 2 --drdr --package polars, offline, as root"
      raco test --jobs 2 --drdr --package polars >/work/test.log 2>&1 || status=$?
      release_matches -cE '^raco test: ' /work/test.log | sed 's/^/pkg-build test (test): modules run: /'
      say "raco test exited $status"
      [ "$status" -eq 0 ] || {
        release_matches -oE '[0-9]+/[0-9]+ test failures' /work/test.log | tail -n 1
        say "the modules that failed, with their failure counts:"
        release_matches -E '^[1-9][0-9]* +[0-9]+ /' /work/test.log
        release_matches -B3 -A15 -E '^(FAILURE|ERROR)$|^non-empty stderr$' /work/test.log >/work/failures.log
        sed '/^UserWarning/d' /work/failures.log | sed -n 1,120p
        exit 1
      }
      ;;
  esac
  say "passed"
}

if [ "${1:-}" = --in-container ]; then
  in_container "$2"
  exit 0
fi
if [ $# -ne 1 ]; then
  echo "usage: pkg-build-test.sh DIST" >&2
  exit 2
fi
root=$(cd "$here/../.." && pwd)
dist=$(cd "$1" && pwd)
cache=${RELEASE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/rkt-polars-release}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
logs=${RELEASE_LOGS:-$work/logs}
mkdir -p "$cache" "$work/work" "$work/src" "$logs"
release_tracked_copy "$root" polars "$work/src"
release_fetch "$RELEASE_NATIPKG_RACKET" "$RELEASE_NATIPKG_RACKET_SHA256" "$cache" >/dev/null

run() {
  docker run --rm --init --cpus "${RELEASE_CPUS:-4}" --memory "${RELEASE_MEMORY:-16g}" \
    -v "$RELEASE_SCRIPTS:/scripts:ro" -v "$dist:/dist:ro" -v "$work/src:/src:ro" \
    -v "$work/work:/work" -v "$cache:/cache" -v "$logs:/logs" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -e PLT_PKG_BUILD_SERVICE=1 -e CI=true -e "PLT_INFO_ALLOW_VARS=;PLT_PKG_BUILD_SERVICE" \
    --entrypoint /bin/bash "$@"
}
run "$RELEASE_PKG_BUILD_IMAGE" /scripts/release/pkg-build-test.sh --in-container install
run --network none -e HOME=/work "$RELEASE_PKG_BUILD_IMAGE" /scripts/release/pkg-build-test.sh --in-container test
