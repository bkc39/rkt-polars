#!/usr/bin/env bash
#
# Print, on one line, the toolchain record scripts/build-so.sh writes beside a
# candidate: its rustc, LLVM, and the image (Linux) or the linker and the
# minimum macOS (darwin).  scripts/refresh-candidates.sh puts the line in its
# commit message.
#
# Usage: scripts/toolchain-summary.sh RECORD
set -euo pipefail

awk '
  NR == 1 { head = $0 }
  sub(/^LLVM version: /, "") { llvm = $0 }
  sub(/^image: /, "") { extra = extra ", in " $0 }
  sub(/^ld: /, "") { extra = extra ", ld " $0 }
  sub(/^minos: /, "") { extra = extra ", minos " $0 }
  END { print head ", LLVM " llvm extra }' "${1:?usage: scripts/toolchain-summary.sh RECORD}"
