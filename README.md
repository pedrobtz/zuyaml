# zuyaml

<!-- badges: start -->
[![R-CMD-check](https://github.com/pedrobtz/zuyaml/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zuyaml/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

> **Status: in development.** Parsing and emitting work; the API is not frozen
> and the package is not on CRAN. See
> [`.agents/DESIGN-zuyaml.md`](.agents/DESIGN-zuyaml.md) and
> [`.agents/ROADMAP.md`](.agents/ROADMAP.md).

`zuyaml` converts between YAML 1.2 and ordinary R objects using a bundled copy of
the [`cyaml`](https://github.com/andrewmd5/cyaml) C11 parser and emitter, with
strict handling of ambiguous YAML features and no runtime dependencies beyond R.

It is designed to compose with a family of lightweight infrastructure packages
(`zuhttp`, `zujson`, `zuxml`, `zukomp`) and to be safe to point at untrusted
input.

## Why another YAML package

R already has the mature [`yaml`](https://cran.r-project.org/package=yaml)
package, built on LibYAML. `zuyaml` is not a re-spelling of it. The differences
are deliberate:

- **YAML 1.2 core schema**, not 1.1 — `yes` and `no` are strings.
- **Strict by default** — duplicate keys are rejected, unknown tags are an error,
  partially named lists refuse to emit.
- **Explicit multi-document handling** — a YAML *stream* and a YAML *sequence*
  are different things, and the API keeps them apart.
- **No silent precision loss** — integers beyond 2^53 are preserved rather than
  quietly rounded.
- **No system dependency** — the C library is bundled and pinned.

If you want compatibility with the existing `yaml` package's behaviour, use that
package. `zuyaml` optimises for predictability instead.

## API

Eight functions, on one rule: **`_all` means "YAML stream"**.

|  | one document | stream of documents |
|---|---|---|
| parse text | `yaml_parse()` | `yaml_parse_all()` |
| emit text | `yaml_emit()` | `yaml_emit_all()` |
| read file | `yaml_read()` | `yaml_read_all()` |
| write file | `yaml_write()` | `yaml_write_all()` |

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

cat(yaml_emit(list(version = "42", ratio = 0.5)))
#> version: "42"
#> ratio: 0.5
```

Note the quoting: `"42"` is a string in R, so it stays a string in YAML and on
the way back. See `vignette("zuyaml")` for the full conversion rules, including
the cases that do not round-trip.

## Installation

``` r
# install.packages("pak")
pak::pak("pedrobtz/zuyaml")
```

## License

MIT. The package bundles the `cyaml` library, which is also MIT licensed and
copyright (c) 2025 Andrew Sampson — see
[`inst/COPYRIGHTS`](inst/COPYRIGHTS) for details.
