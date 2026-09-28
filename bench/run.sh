#!/usr/bin/env bash
# The nycflights benchmark (#86): fetch and verify the post's file, derive its
# CSV and NA-stripped copies, then print the scoreboard and the ratio table.
#
#   nix run .#bench          # from the repository root
#   bash bench/run.sh        # inside `nix develop`
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

url=https://www.travishinkelman.com/data/nycflights.tsv
sha256=f6854cb53bcd9472aef9165af77a883a7c2c36ad4a4463242e3f24c95589403d
data=bench/data

mkdir -p "$data"
if ! echo "$sha256  $data/nycflights.tsv" | sha256sum --check --status 2>/dev/null; then
  echo "bench: fetching $url" >&2
  curl --fail --silent --show-error --location --output "$data/nycflights.tsv.part" "$url"
  if ! echo "$sha256  $data/nycflights.tsv.part" | sha256sum --check --status; then
    echo "bench: $url does not have sha256 $sha256" >&2
    exit 1
  fi
  mv "$data/nycflights.tsv.part" "$data/nycflights.tsv"
fi

# No field holds a comma or a quote, so swapping the separator is a faithful CSV.
tr '\t' ',' < "$data/nycflights.tsv" > "$data/nycflights.csv"
awk 'BEGIN { FS = OFS = "\t" } { for (i = 1; i <= NF; i++) if ($i == "NA") $i = ""; print }' \
  "$data/nycflights.tsv" > "$data/nycflights-nona.tsv"
tr '\t' ',' < "$data/nycflights-nona.tsv" > "$data/nycflights-nona.csv"

raco make bench/blog-test.rkt bench/perf.rkt
racket bench/blog-test.rkt
echo
racket bench/perf.rkt
