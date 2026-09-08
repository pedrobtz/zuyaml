## Submission

New submission of zuyaml 0.9.0.

zuyaml converts between YAML 1.2 and ordinary R objects. It bundles the cyaml
C11 parser/emitter, so it has no system dependency and no R dependencies beyond
base R.

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  Maintainer: 'Pedro Baltazar <pedrobtz@gmail.com>'
  New submission

This is the expected note for a first submission.

## Bundled third-party code

The package bundles the cyaml C11 library (MIT licensed) in `src/`, as
`cyaml*.c` and `cyaml*.h`.

* Andrew Sampson, its author and copyright holder, is credited in `Authors@R`
  with the `ctb` and `cph` roles.
* `inst/COPYRIGHTS` records the upstream repository, the exact pinned commit,
  the full MIT license text, and every modification made when bundling.
* Upstream is pinned to an immutable commit, never a branch. `tools/` holds the
  script that vendors it and verifies each file against a checksum manifest.

Two modifications were made, both documented in `inst/COPYRIGHTS` and
`tools/patches/`:

1. Upstream's assertion macros call `abort()` and write to `stderr`. Both are
   prohibited by CRAN policy, and `abort()` would terminate the user's R
   session, so they are redirected to an R error condition.
2. Upstream's emitter double-quotes any plain scalar spelled `true`, `false`,
   `null` or `~`, which makes a boolean emit as a string. The package selects
   scalar styles before emitting, so that promotion is suppressed.

## Test environments

* local macOS 26.6 (arm64), R 4.6.1
* GitHub Actions: ubuntu-latest (R release, R devel, R oldrel-1, and clang),
  macOS-latest (R release), windows-latest (R release)
* win-builder (R devel and R release)

The package is also checked under AddressSanitizer and UndefinedBehaviorSanitizer,
and fuzzed with random bytes, YAML-syntax fragments and truncated documents,
since it parses untrusted input.
