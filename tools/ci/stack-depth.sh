#!/usr/bin/env bash
#
# Run tools/ci/stack-depth.R under several C stack sizes (#8).
#
# Usage:  tools/ci/stack-depth.sh [--large-output]
#
# 8 MB is the usual default for a main thread, 1 MB is common for secondary
# threads and embedded interpreters, and 256 KB is small enough that a
# recursion this package did not bound would show up. Each size runs in its
# own process, because `ulimit -s` applies at exec.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

lib="$(mktemp -d)"
trap 'rm -rf "$lib"' EXIT
find src -name '*.o' -delete # load_all() leaves -O0 objects (CLAUDE.md)
R CMD INSTALL --no-test-load -l "$lib" . >/dev/null
export R_LIBS="$lib${R_LIBS:+:$R_LIBS}"

status=0
for kb in 8192 1024 256; do
  echo "== ulimit -s $kb"
  extra=()
  if [ "$kb" = 8192 ] && [ "${1:-}" = --large-output ]; then
    extra=(--large-output)
  fi
  if ! (ulimit -s "$kb" && Rscript tools/ci/stack-depth.R "${extra[@]+"${extra[@]}"}"); then
    echo "FAILED under ulimit -s $kb (exit status above; a crash ends the process)"
    status=1
  fi
done
exit "$status"
