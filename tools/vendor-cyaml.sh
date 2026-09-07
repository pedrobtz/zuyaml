#!/usr/bin/env bash
#
# Vendor the cyaml C library into src/.
#
# Usage:  tools/vendor-cyaml.sh
#
# This is a maintainer tool. It is not run at install time and is excluded
# from the built tarball.
#
# Design notes (see .agents/DESIGN-zuyaml.md section 13):
#
#   * The vendored sources live FLAT in src/, not in a subdirectory, because
#     R CMD SHLIB only compiles sources directly in src/. A subdirectory would
#     need a hand-maintained OBJECTS list in Makevars and Makevars.win.
#
#   * All 8 .c files are vendored, including those implementing features
#     zuyaml defers. cyaml.c defines cyaml_path(), which calls into
#     cyaml_path.c, and references cyaml_is_json(); dropping those translation
#     units would mean patching cyaml.c itself.
#
#   * Upstream is pinned to an immutable commit, never a branch.
#
#   * GitHub's generated archives are not guaranteed byte-stable over time,
#     so the per-file checksum manifest below -- not the archive checksum --
#     is authoritative.
#
set -euo pipefail

CYAML_REPO="https://github.com/andrewmd5/cyaml"
CYAML_VERSION="v0.1.3"
CYAML_COMMIT="0672e81b809bc3dfd1d4f57ba0fcfbb20c60ae70"

# sha256 of each upstream file at CYAML_COMMIT, as published.
read -r -d '' MANIFEST <<'EOF' || true
1f081da04d71de0db3cc4fa95cf29457da39db6b06f80d358caed7d30f3c6b3c  cyaml.c
dd31666e0883dddc8c1d9c72e0307df8e84c414f123dd692aeb509bf36a85b8e  cyaml_emitter.c
61d1364ddff69d82f9005d6072406c5557418331588ab7977d7ffa0b968d3d9a  cyaml_events.c
073f7b78f940ccf4df57f765f463375e6799b221cbffaac2e67eae8b7f3b83ca  cyaml_json.c
9ac7cc4527dfda4b1d0968fbdaf16e68b57d2cfc9fc85c4e96be06723214dd3e  cyaml_modify.c
008cc00595754addab1bfaa7228009ab0f231f50e8d3414d87113db3e78cc115  cyaml_parser.c
81c8efd8f70bf03b43fe2d4eadfef9ef652ada2ff0a1201ef712c7e0168aacda  cyaml_path.c
722a6408d809e4c5548f858bb5890386396a446c75ed078ad98e90fd797a25f9  cyaml_utf8.c
a240ca5f01ba11b5321e93f279e29b9d8aa57f766cfc2ac899bedc8b5bf4f58c  cyaml.h
32b8c9d42510f5e96ae94a97a4bf4a5f72ebec34b255d7a7b3ca2d94c961033d  cyaml_internal.h
e601459232a18278471050f0e7c01d8d7eea101c16a96178bce9e8047eb93a8d  cyaml_utf8.h
EOF

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

say() { printf '  %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    die "need sha256sum or shasum"
  fi
}

command -v curl >/dev/null 2>&1 || die "need curl"
command -v git  >/dev/null 2>&1 || die "need git (patches are applied with git apply)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Vendoring cyaml ${CYAML_VERSION} (${CYAML_COMMIT})"

# --- fetch -----------------------------------------------------------------
say "downloading ${CYAML_COMMIT}"
curl -sSL --fail --max-time 120 \
  "${CYAML_REPO}/archive/${CYAML_COMMIT}.tar.gz" -o "$tmp/cyaml.tar.gz" \
  || die "download failed"

tar xzf "$tmp/cyaml.tar.gz" -C "$tmp"
upstream="$tmp/cyaml-${CYAML_COMMIT}/src"
[ -d "$upstream" ] || die "unexpected archive layout: $upstream missing"

# --- verify ----------------------------------------------------------------
say "verifying checksums"
count=0
while read -r want file; do
  [ -n "${want:-}" ] || continue
  [ -f "$upstream/$file" ] || die "missing upstream file: $file"
  got="$(sha256 "$upstream/$file")"
  [ "$got" = "$want" ] || die "checksum mismatch for $file
    expected $want
    actual   $got
  Upstream content changed for a pinned commit, or the manifest is stale."
  count=$((count + 1))
done <<< "$MANIFEST"
say "$count files verified"

# --- copy ------------------------------------------------------------------
say "copying into src/"
rm -f src/cyaml*.c src/cyaml*.h
while read -r _ file; do
  [ -n "${file:-}" ] || continue
  cp "$upstream/$file" "src/$file"
done <<< "$MANIFEST"

# --- patch -----------------------------------------------------------------
# Patches are mandatory, not cosmetic. See tools/patches/README.md.
shopt -s nullglob
patches=(tools/patches/*.patch)
shopt -u nullglob
[ ${#patches[@]} -gt 0 ] || die "no patches found in tools/patches/ -- the
  assertion patch is required for CRAN compliance and must not be skipped"

for p in "${patches[@]}"; do
  say "applying $(basename "$p")"
  git apply --whitespace=nowarn "$p" \
    || die "failed to apply $p
  Upstream context has changed. Re-derive the patch against the new source
  and re-read .agents/DESIGN-zuyaml.md section 13.2 before proceeding."
done

# The patch must have removed every abort() call. Verify, don't assume.
# Comments are stripped first: the patch's own comment explains what it
# removed and legitimately contains the word.
say "checking for prohibited calls"
for f in src/cyaml*.c src/cyaml*.h; do
  if sed 's://.*::' "$f" | grep -q '\babort[[:space:]]*(' ; then
    die "abort() still reachable in $f after patching.
  CRAN policy prohibits it, and it would terminate the user's R session.
  Extend tools/patches/ to cover this call site."
  fi
done

# --- record ----------------------------------------------------------------
archive_sha="$(sha256 "$tmp/cyaml.tar.gz")"
cat > inst/cyaml-VERSION <<EOF
upstream: ${CYAML_REPO}
version:  ${CYAML_VERSION}
commit:   ${CYAML_COMMIT}
archive:  sha256:${archive_sha}
          (advisory only -- GitHub archives are not byte-stable;
           tools/vendor-cyaml.sh verifies each file individually)
patches:  $(for p in "${patches[@]}"; do printf '%s ' "$(basename "$p")"; done)
vendored: $(date -u +%Y-%m-%d)

Generated by tools/vendor-cyaml.sh. Do not edit by hand.
See inst/COPYRIGHTS for licensing and the list of modifications.
EOF

say "wrote inst/cyaml-VERSION"
echo
echo "Done. Next:"
echo "  1. confirm Makevars still defines -DCYAML_VERSION_STR=\\\"${CYAML_VERSION#v}\\\""
echo "  2. R CMD check, and re-run the full yaml-test-suite in CI"
echo "  3. re-read the verification note in .agents/DESIGN-zuyaml.md"
