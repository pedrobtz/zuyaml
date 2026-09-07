# zuyaml

<!-- badges: start -->
[![R-CMD-check](https://github.com/pedrobtz/zuyaml/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zuyaml/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

> **Status: pre-alpha.** The design is settled; the implementation has not
> started. Nothing below works yet. See
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

## Planned API

Eight functions, on one rule: **`_all` means "YAML stream"**.

|  | one document | stream of documents |
|---|---|---|
| parse text | `yaml_parse()` | `yaml_parse_all()` |
| emit text | `yaml_emit()` | `yaml_emit_all()` |
| read file | `yaml_read()` | `yaml_read_all()` |
| write file | `yaml_write()` | `yaml_write_all()` |

## Installation

Not yet installable. When it is:

``` r
# install.packages("pak")
pak::pak("pedrobtz/zuyaml")
```

## License

MIT. The package bundles the `cyaml` library, which is also MIT licensed and
copyright (c) 2025 Andrew Sampson — see
[`inst/COPYRIGHTS`](inst/COPYRIGHTS) for details.
