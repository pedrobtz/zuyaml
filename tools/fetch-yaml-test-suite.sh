#!/usr/bin/env bash
#
# Fetch the upstream yaml-test-suite into a directory for the conformance
# tests to read.
#
# Usage:  tools/fetch-yaml-test-suite.sh [destination]
#
# The package ships only a small curated subset under
# tests/testthat/fixtures/yaml-test-suite (see tools/curate-test-suite.R), so
# that CRAN test time stays reasonable. CI uses this script to run the full
# suite instead, by pointing ZUYAML_TEST_SUITE at the result.
#
# The suite's cases live on the repository's `data` branch, one directory per
# case, each holding:
#
#   ===        one-line description
#   in.yaml    the input
#   error      present when the input is expected to fail parsing
#   in.json    JSON equivalent, for valid cases only
#
# A case directory may instead hold numbered subdirectories (00, 01, ...) when
# one identifier covers several related inputs.
#
set -euo pipefail

dest="${1:-${TMPDIR:-/tmp}/yaml-test-suite}"
url="https://github.com/yaml/yaml-test-suite/archive/refs/heads/data.tar.gz"

command -v curl >/dev/null 2>&1 || { echo "need curl" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Fetching yaml-test-suite (data branch)"
curl -sSL --fail --max-time 180 "$url" -o "$tmp/data.tar.gz"
tar xzf "$tmp/data.tar.gz" -C "$tmp"

src="$tmp/yaml-test-suite-data"
[ -d "$src" ] || { echo "unexpected archive layout" >&2; exit 1; }

rm -rf "$dest"
mkdir -p "$(dirname "$dest")"
mv "$src" "$dest"

cases=$(find "$dest" -name in.yaml | wc -l | tr -d ' ')
echo "  $cases cases in $dest"
echo
echo "Run the full suite with:"
echo "  ZUYAML_TEST_SUITE=$dest R -e 'testthat::test_local(\".\")'"
