#!/usr/bin/env bash
#
# Compile zuyaml's own C sources with warnings well beyond CRAN's set, as
# errors (#7).
#
# Usage:  tools/ci/compile-warnings.sh [compiler ...]     (default: cc)
#
# CRAN builds with -Wall -pedantic, so nothing else reports -Wextra and the
# conversion warnings: they have to be run deliberately or not at all. The
# warnings that matter in a parser are the ones about comparing and narrowing
# indices and lengths (-Wsign-compare, -Wconversion), a struct gaining a field
# in a re-vendor that a local initialiser does not (-Wmissing-field-
# initializers), and format strings (-Wformat=2, which the printf attribute on
# zuyaml_stopf() makes cover every error message).
#
# Only zuyaml_*.c and init.c are checked. The vendored cyaml sources are
# upstream's: a warning there that we will not fix is noise, and noise is what
# makes a warnings job ignorable. Their headers, R's and zufast's are included
# with -isystem, so a warning inside them is not reported against us. That
# needs the sources copied out of src/: a quoted #include searches the
# including file's own directory first, so from src/ cyaml.h would be found
# there, as an ordinary header.
#
# One flag is off, for an R API idiom rather than a defect: registering a
# .Call entry point casts it to DL_FUNC (-Wcast-function-type).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[ $# -gt 0 ] || set -- cc

r_inc="$(Rscript -e 'cat(R.home("include"))')"
zufast_inc="$(Rscript -e 'cat(system.file("include", package = "zufast"))')"
[ -n "$zufast_inc" ] || { echo "error: zufast is not installed" >&2; exit 1; }
version="$(sed -n 's/.*-DCYAML_VERSION_STR=\\"\([^\\]*\)\\".*/\1/p' "$root/src/Makevars")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$root"/src/zuyaml*.c "$root"/src/zuyaml*.h "$root/src/init.c" "$tmp/"

flags=(
  -std=gnu11 -fsyntax-only -Werror
  -Wall -Wextra -pedantic
  -Wconversion -Wsign-conversion -Wshadow -Wcast-qual -Wformat=2
  -Wstrict-prototypes -Wmissing-prototypes -Wundef
  -Wno-cast-function-type
  -isystem "$r_inc" -isystem "$zufast_inc" -isystem "$root/src"
  "-DCYAML_VERSION_STR=\"$version\""
)

status=0
for cc in "$@"; do
  extra=()
  # clang 19 split the DL_FUNC cast warning out under its own name.
  if "$cc" -Werror -Wno-cast-function-type-mismatch -x c -fsyntax-only /dev/null 2>/dev/null; then
    extra+=(-Wno-cast-function-type-mismatch)
  fi
  echo "== $("$cc" --version | head -n 1)"
  for f in "$tmp"/*.c; do
    if ! "$cc" "${flags[@]}" "${extra[@]+"${extra[@]}"}" "$f"; then
      status=1
    fi
  done
done
[ "$status" -eq 0 ] && echo "No warnings."
exit "$status"
