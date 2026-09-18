# zuyaml

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/pedrobtz/zuyaml/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zuyaml/actions/workflows/R-CMD-check.yaml)
[![hardening](https://github.com/pedrobtz/zuyaml/actions/workflows/hardening.yaml/badge.svg)](https://github.com/pedrobtz/zuyaml/actions/workflows/hardening.yaml)
[![native-checks](https://github.com/pedrobtz/zuyaml/actions/workflows/native-checks.yaml/badge.svg)](https://github.com/pedrobtz/zuyaml/actions/workflows/native-checks.yaml)
[![pkgdown](https://github.com/pedrobtz/zuyaml/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/pedrobtz/zuyaml/actions/workflows/pkgdown.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/zuyaml/main/.github/badges/coverage.svg)](https://github.com/pedrobtz/zuyaml/actions/workflows/coverage.yaml)
<!-- badges: end -->

zuyaml converts between YAML 1.2 and ordinary R objects, using a bundled copy of
the [cyaml](https://github.com/andrewmd5/cyaml) C11 parser and emitter, so there
is no system dependency and no runtime dependency beyond R itself. Ambiguous YAML
is handled strictly: the 1.2 core schema (so `yes` is a string), duplicate keys
refused, large integers preserved, and a document *stream* kept apart from a sequence.

## Installation

``` r
install.packages("zuyaml")
```

Or the development version from GitHub:

``` r
# install.packages("pak")
pak::pak("pedrobtz/zuyaml")
```

## Usage

`yaml_parse()` turns YAML text into R objects:

``` r
library(zuyaml)

yaml_parse("host: localhost\nport: 8080\ntls: true\n")
#> $host
#> [1] "localhost"
#> 
#> $port
#> [1] 8080
#> 
#> $tls
#> [1] TRUE
```

`yaml_emit()` goes the other way. Note the quoting: `"42"` is a string in R, so it
stays a string in YAML and on the way back. The same holds for the cases that are
easy to get wrong — line breaks, leading and trailing whitespace, mapping keys,
whole-numbered doubles — so what you emit parses back to what you had.

``` r
cat(yaml_emit(list(version = "42", ratio = 0.5)))
#> version: "42"
#> ratio: 0.5
```

Both have an `_all` variant for a YAML *stream* — several documents separated by
`---`, which is a different thing from a sequence — and `yaml_read()` /
`yaml_write()` do the same for files:

``` r
yaml_parse_all("a: 1\n---\na: 2\n")
#> [[1]]
#> [[1]]$a
#> [1] 1
#> 
#> 
#> [[2]]
#> [[2]]$a
#> [1] 2
```

The [getting started
article](https://pedrobtz.github.io/zuyaml/articles/zuyaml.html) documents the
conversion rules in full, including the cases that do not round-trip.

## Testing

- **`tests/testthat/`** runs a curated 84-case [yaml-test-suite](https://github.com/yaml/yaml-test-suite) subset in every `R CMD check`; `ZUYAML_TEST_SUITE` points it at a full 402-case checkout instead.
- **`tools/conformance.R`** walks the same corpus but *reports* rather than asserts — counts per boundary, failures named, against a baseline pinned in the script.
- The split is deliberate: a test cannot hold a number like `278/279` that is meant to change deliberately rather than break a build.

| Workflow | Jobs, and what they do | When | Runs |
|---|---|---|---|
| [`R-CMD-check.yaml`](https://github.com/pedrobtz/zuyaml/blob/main/.github/workflows/R-CMD-check.yaml) | `R CMD check --as-cran` on macOS, Windows and Ubuntu at R release and oldrel-1, and in the CRAN-like containers `clang23`, `ubuntu-clang` and `ubuntu-gcc16` — the package vendors C11, so the compiler CRAN uses is the one that has to see it | push, PR | [view](https://github.com/pedrobtz/zuyaml/actions/workflows/R-CMD-check.yaml) |
| [`hardening.yaml`](https://github.com/pedrobtz/zuyaml/blob/main/.github/workflows/hardening.yaml) | `full-test-suite` — all 402 yaml-test-suite cases, then `tools/conformance.R` against its pinned baseline. `fuzz` — the wrapper fuzzer at 20,000 iterations | push, PR, weekly | [view](https://github.com/pedrobtz/zuyaml/actions/workflows/hardening.yaml) |
| [`native-checks.yaml`](https://github.com/pedrobtz/zuyaml/blob/main/.github/workflows/native-checks.yaml) | `sanitizers` — UBSan on a runner, ASan in the `clang-asan` and `gcc-asan` images. `valgrind`, `lto`, `rchk` (failing on findings), and `gctorture` at step 500 on every push with the sensitive step-20 run weekly | push, PR, weekly | [view](https://github.com/pedrobtz/zuyaml/actions/workflows/native-checks.yaml) |
| [`coverage.yaml`](https://github.com/pedrobtz/zuyaml/blob/main/.github/workflows/coverage.yaml) | `covr`, with a per-file breakdown in the job summary | push, PR | [view](https://github.com/pedrobtz/zuyaml/actions/workflows/coverage.yaml) |

`R-CMD-check.yaml`, `native-checks.yaml` and `coverage.yaml` call the reusable
workflows in [r-actions](https://github.com/pedrobtz/r-actions) rather than
keeping a second copy here. `hardening.yaml` does not: it holds the two checks
that are specific to this package.
