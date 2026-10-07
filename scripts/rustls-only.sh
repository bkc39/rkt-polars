#!/usr/bin/env bash
#
# The rustls-only gate: fails when rust/Cargo.lock holds a TLS stack other than
# rustls on ring.  OpenSSL or native-tls would link the system's libssl, which
# the catalog's binaries cannot assume (a Linux host without that libssl
# version fails to load libcompat), and aws-lc (rustls' default provider) is C
# and assembly built with cmake.  object_store asks reqwest for
# rustls-tls-native-roots, which is ring; a dependency bump that pulls any of
# these in fails here.
#
# Usage: scripts/rustls-only.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

lock=rust/Cargo.lock
forbidden='openssl|openssl-sys|native-tls|hyper-tls|tokio-native-tls|aws-lc-rs|aws-lc-sys|aws-lc-fips-sys'
hits=$(grep -nE "^name = \"($forbidden)\"$" "$lock" || true)

if [ -n "$hits" ]; then
  while IFS=: read -r line text; do
    message="$text: TLS must be rustls on ring (AGENTS.md); find what pulls it in with cargo tree -i"
    echo "$lock:$line: $message"
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      echo "::error file=$lock,line=$line::$message"
    fi
  done <<< "$hits"
  exit 1
fi
echo "rustls-only: no OpenSSL, native-tls or aws-lc in $lock"
