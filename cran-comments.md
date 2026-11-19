## Submission

Update of zuyaml, 0.1.0 to 0.1.1. A bug-fix release. Several of the fixes
correct values that 0.1.0 returned wrong without an error, such as integers
above 2^64 and strings that did not survive being emitted and parsed again.
It also bounds parse time and stack use on deeply nested input.

One new build-time dependency: `LinkingTo: zufast`, a header-only package on
CRAN, which replaces the C library's `strtod()` for number conversion. There
is no new runtime dependency.

## R CMD check results

0 errors | 0 warnings | 0 notes

## Bundled third-party code

The package bundles the cyaml C11 library (MIT licensed) in `src/`, as
`cyaml*.c` and `cyaml*.h`, pinned to an immutable commit.
`inst/COPYRIGHTS` records the upstream repository, the commit, the license
and every modification.

This release adds one modification to the five in 0.1.0. The scanner now
honours the library's own `max_depth` option for flow collections, because
scanning them takes time that grows with the square of their nesting depth.
All six modifications are documented in `inst/COPYRIGHTS` and as patches in
`tools/patches/`. `tools/` also holds a verifier that rebuilds the bundled
sources from upstream plus those patches and requires them to match byte for
byte.

## Test environments

GitHub Actions, through the pedrobtz/r-actions reusable workflows:

* runners: ubuntu-latest (R release and R oldrel-1), macOS-latest (R
  release), windows-latest (R release and R devel)
* R-hub containers on R devel: `clang23`, `ubuntu-clang` and `ubuntu-gcc16`,
  compiled as the corresponding CRAN flavors are (C as `-std=gnu23` with
  `-pedantic`), plus the `nosuggests` and `nold` configurations
* CRAN's additional checks: rcnst, rlibro and vnu

The package is also checked under AddressSanitizer and
UndefinedBehaviorSanitizer, under valgrind, with gctorture, with rchk and with
LTO. It is run against the full yaml-test-suite and fuzzed, since it parses
untrusted input.

## Reverse dependencies

There are no reverse dependencies on CRAN.

## Method references

There are no published references describing the methods in this package. It
implements the YAML 1.2 specification (<https://yaml.org/spec/1.2.2/>), which
is cited in the DESCRIPTION.
