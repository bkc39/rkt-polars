#!/usr/bin/env bash
#
# Prints, one per line, the configured package catalogs polars' dependencies
# resolve from: a release catalog
# (https://download.racket-lang.org/releases/<version>/catalog/) and
# https://pkgs.racket-lang.org. The release tests (release_catalogs in
# scripts/release/pins.sh) put only these, less the release catalog (#124),
# behind their file:// catalog, so an outage of the others (Rhombus's,
# planet-compats), which hold nothing polars needs, cannot fail them. CI's
# install-racket action drops the release catalog, and a full installation
# has every package it lists. Fails, naming the catalogs it read, when
# neither is configured.
#
# Usage: scripts/dependency-catalogs.sh
set -euo pipefail

configured=$(raco pkg config catalogs)
kept=$(grep -E '^https://(download\.racket-lang\.org/releases/[^/]+/catalog/?|pkgs\.racket-lang\.org/?)$' \
  <<< "$configured") || status=$?
case "${status:-0}" in
  0) printf '%s\n' "$kept" ;;
  1)
    echo "dependency-catalogs: no release catalog or pkgs.racket-lang.org among [$configured]" >&2
    exit 1
    ;;
  *) exit 2 ;;
esac
