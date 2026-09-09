# Parse YAML

`yaml_parse()` parses a single YAML document. `yaml_parse_all()` parses
a YAML *stream* and returns one element per document.

## Usage

``` r
yaml_parse(
  x,
  simplify = FALSE,
  aliases = c("resolve", "error"),
  big_integers = c("bigint", "double", "error"),
  tags = c("ignore", "error"),
  duplicate_keys = FALSE,
  max_depth = 128L,
  max_size = 64 * 1024^2,
  max_nodes = 1e+06,
  path = NULL
)

yaml_parse_all(
  x,
  simplify = FALSE,
  aliases = c("resolve", "error"),
  big_integers = c("bigint", "double", "error"),
  tags = c("ignore", "error"),
  duplicate_keys = FALSE,
  max_depth = 128L,
  max_size = 64 * 1024^2,
  max_nodes = 1e+06,
  path = NULL
)
```

## Arguments

- x:

  A length-one character vector containing YAML, or a raw vector of
  UTF-8 YAML bytes.

- simplify:

  If `TRUE`, sequences whose elements are all scalars of the same type
  collapse to an atomic vector. The default is `FALSE`, so the shape of
  the result never depends on the contents of the document.

- aliases:

  How to treat YAML aliases. `"resolve"` (the default) replaces each
  alias with the value of its target; node identity is not preserved.
  `"error"` rejects any document containing an alias.

- big_integers:

  How to represent integers too large for an R numeric type to hold
  exactly (beyond 2^53). `"bigint"` (the default) returns a
  [zuyaml_bigint](https://pedrobtz.github.io/zuyaml/reference/zuyaml_bigint.md)
  character vector holding the decimal value, `"double"` is an explicit
  opt-in to lossy conversion, and `"error"` refuses the document. The
  package never loses integer precision silently.

- tags:

  How to treat an application tag such as `!duration`. Core schema tags
  (`!!str`, `!!int`, `!!float`, `!!bool`, `!!null`) always override
  resolution, so `!!str 12` is the string `"12"`. `"ignore"` (the
  default) converts a tagged value as though it were untagged; `"error"`
  rejects the document. Ignoring is the default because rejecting would
  refuse a great deal of ordinary YAML.

- duplicate_keys:

  If `FALSE` (the default), a mapping with duplicate keys is an error.
  If `TRUE`, duplicates become duplicate names in the resulting list.

- max_depth:

  Maximum nesting depth, or `0` for unlimited.

- max_size:

  Maximum input size in bytes, or `0` for unlimited.

- max_nodes:

  Maximum number of R values materialised, or `0` for unlimited. This is
  the limit that bounds alias expansion: a billion-laughs document is
  small and shallow, so neither `max_size` nor `max_depth` constrains
  it. The default leaves roughly fifty times the headroom a very large
  document needs.

- path:

  Optional file path, used only to make error messages more informative.
  [`yaml_read()`](https://pedrobtz.github.io/zuyaml/reference/yaml_read.md)
  and its companions set it for you.

## Value

`yaml_parse()` returns an R object. `yaml_parse_all()` returns a list
with one element per document.

## Details

Both functions parse the input as a stream. `yaml_parse()` then requires
it to contain exactly one document, so trailing documents are never
silently discarded:

|           |                |                                              |
|-----------|----------------|----------------------------------------------|
| documents | `yaml_parse()` | `yaml_parse_all()`                           |
| 0         | error          | [`list()`](https://rdrr.io/r/base/list.html) |
| 1         | the object     | list of length 1                             |
| more      | error          | list of that length                          |

A zero-document stream is an error rather than `NULL`, because `NULL` is
the legitimate result of parsing a document whose content is `null`.
Comment-only input is a zero-document stream.

## Examples

``` r
yaml_parse("host: localhost\nport: 8080\ntls: true\n")
#> $host
#> [1] "localhost"
#> 
#> $port
#> [1] 8080
#> 
#> $tls
#> [1] TRUE
#> 

# The core schema, not YAML 1.1: `yes` is a string, and a quoted number
# stays a string.
str(yaml_parse("answer: yes\nversion: \"42\"\n"))
#> List of 2
#>  $ answer : chr "yes"
#>  $ version: chr "42"

# A stream is not a sequence: one element per document.
yaml_parse_all("---\nfirst\n---\nsecond\n")
#> [[1]]
#> [1] "first"
#> 
#> [[2]]
#> [1] "second"
#> 
```
