# zuyaml

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/pedrobtz/zuyaml/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zuyaml/actions/workflows/R-CMD-check.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/zuyaml/main/.github/badges/coverage.svg)](https://github.com/pedrobtz/zuyaml/actions/workflows/coverage.yaml)
<!-- badges: end -->

zuyaml converts between YAML 1.2 and ordinary R objects, using a bundled copy of
the [cyaml](https://github.com/andrewmd5/cyaml) C11 parser and emitter, so there
is no system dependency and no runtime dependency beyond R itself. Ambiguous YAML
is handled strictly: the 1.2 core schema (so `yes` is a string), duplicate keys
refused, large integers preserved, and a document *stream* kept apart from a sequence.

## Installation

Install the development version from GitHub:

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
stays a string in YAML and on the way back.

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
