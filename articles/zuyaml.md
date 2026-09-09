# Converting between YAML and R

``` r

library(zuyaml)
```

`zuyaml` converts between YAML 1.2 and ordinary R objects. This article
documents the conversion rules, which are part of the package’s
contract: they are meant to be predictable rather than clever, and every
place where information is lost is listed at the end.

## Why another YAML package

R already has the mature
[`yaml`](https://cran.r-project.org/package=yaml) package, built on
LibYAML. `zuyaml` is not a re-spelling of it. The differences are
deliberate:

- **YAML 1.2 core schema**, not 1.1 — `yes` and `no` are strings.
- **Strict by default** — duplicate keys are rejected and partially
  named lists refuse to emit. Application tags are ignored unless you
  ask for `tags = "error"`.
- **Explicit multi-document handling** — a YAML *stream* and a YAML
  *sequence* are different things, and the API keeps them apart.
- **No silent precision loss** — integers beyond 2^53 are preserved
  rather than quietly rounded.
- **No system dependency** — the C library is bundled and pinned.

If you want compatibility with the existing `yaml` package’s behaviour,
use that package. `zuyaml` optimises for predictability instead.

## The API

Eight functions, on one rule: **`_all` means “YAML stream”**.

|  | one document | stream of documents |
|----|----|----|
| parse text | [`yaml_parse()`](https://pedrobtz.github.io/zuyaml/reference/yaml_parse.md) | [`yaml_parse_all()`](https://pedrobtz.github.io/zuyaml/reference/yaml_parse.md) |
| emit text | [`yaml_emit()`](https://pedrobtz.github.io/zuyaml/reference/yaml_emit.md) | [`yaml_emit_all()`](https://pedrobtz.github.io/zuyaml/reference/yaml_emit.md) |
| read file | [`yaml_read()`](https://pedrobtz.github.io/zuyaml/reference/yaml_read.md) | [`yaml_read_all()`](https://pedrobtz.github.io/zuyaml/reference/yaml_read.md) |
| write file | [`yaml_write()`](https://pedrobtz.github.io/zuyaml/reference/yaml_read.md) | [`yaml_write_all()`](https://pedrobtz.github.io/zuyaml/reference/yaml_read.md) |

A YAML *stream* holds several documents separated by `---`. It is a
different thing from a *sequence*, and the API keeps them apart:
[`yaml_parse()`](https://pedrobtz.github.io/zuyaml/reference/yaml_parse.md)
refuses anything but exactly one document, so trailing documents are
never silently discarded.

``` r

yaml_parse("a: 1")
#> $a
#> [1] 1

yaml_parse_all("---\na: 1\n---\nb: 2\n")
#> [[1]]
#> [[1]]$a
#> [1] 1
#> 
#> 
#> [[2]]
#> [[2]]$b
#> [1] 2

try(yaml_parse("---\na: 1\n---\nb: 2\n"))
#> Error : YAML stream contains 2 documents; use yaml_parse_all().
```

An empty stream is an error rather than `NULL`, because `NULL` is the
legitimate result of parsing a document whose content is `null`.

## Scalars

Scalars follow the YAML 1.2 **core schema**. The most visible
consequence is that `yes` and `no` are strings, not booleans — that was
a YAML 1.1 rule.

``` r

str(yaml_parse("[null, true, 42, 3.14, hello, yes, 2026-09-07]"))
#> List of 7
#>  $ : NULL
#>  $ : logi TRUE
#>  $ : int 42
#>  $ : num 3.14
#>  $ : chr "hello"
#>  $ : chr "yes"
#>  $ : chr "2026-09-07"
```

Dates stay strings: turning them into `Date` would be policy beyond a
parser’s job. Quoted scalars are always strings, so quoting is how you
protect a value that would otherwise look like a number.

``` r

str(yaml_parse('[42, "42"]'))
#> List of 2
#>  $ : int 42
#>  $ : chr "42"
```

`.inf` and `.nan` map to `Inf` and `NaN`, and an empty *quoted* string
stays a string rather than becoming `NULL`.

``` r

str(yaml_parse('["", ~, .inf]'))
#> List of 3
#>  $ : chr ""
#>  $ : NULL
#>  $ : num Inf
```

### Large integers

R has no exact integer type beyond 2^53. Rather than round silently,
values past that point become a `zuyaml_bigint`, a character vector
holding the decimal value.

``` r

x <- yaml_parse("9223372036854775807")
x
#> <zuyaml_bigint>
#> [1] 9223372036854775807
class(x)
#> [1] "zuyaml_bigint"
```

It carries the decimal normalisation, not the source text, so
hexadecimal input compares equal to its decimal spelling:

``` r

as.character(yaml_parse("0x7FFFFFFFFFFFFFFF"))
#> [1] "9223372036854775807"
```

Use `big_integers` to choose a different policy — `"double"` opts in to
losing precision, `"error"` refuses the document.

``` r

yaml_parse("9223372036854775807", big_integers = "double")
#> [1] 9.223372e+18
```

## Sequences and mappings

A sequence becomes a list, and a mapping with scalar keys becomes a
named list.

``` r

str(yaml_parse("- 1\n- two\n- true\n"))
#> List of 3
#>  $ : int 1
#>  $ : chr "two"
#>  $ : logi TRUE
str(yaml_parse("host: localhost\nport: 8080\n"))
#> List of 2
#>  $ host: chr "localhost"
#>  $ port: int 8080
```

`simplify = TRUE` collapses sequences whose elements are all scalars of
one type. It is **not** the default, because it makes the shape of the
result depend on the contents of the document: `[1, 2]` would give an
integer vector while `[1, "a"]` gives a list, so code that indexes the
result would be correct only for the inputs its author happened to test.

``` r

str(yaml_parse("[1, 2, 3]"))
#> List of 3
#>  $ : int 1
#>  $ : int 2
#>  $ : int 3
str(yaml_parse("[1, 2, 3]", simplify = TRUE))
#>  int [1:3] 1 2 3
```

### Duplicate keys

Rejected by default, because the resulting object would be ambiguous to
index.

``` r

try(yaml_parse("a: 1\na: 2\n"))
#> Error : Duplicate mapping key 'a'; set duplicate_keys = TRUE to allow duplicates.
```

Non-string scalar keys are stringified, so `1` and `"1"` would collide
as R names. That collision is caught too rather than quietly producing
duplicate names.

``` r

str(yaml_parse("1: a\n2: b\n"))
#> List of 2
#>  $ 1: chr "a"
#>  $ 2: chr "b"
try(yaml_parse('1: a\n"1": b\n'))
#> Error : Duplicate mapping key '1'; set duplicate_keys = TRUE to allow duplicates.
```

### Keys that are not scalars

YAML allows a sequence or mapping to be a key. Such a mapping cannot
become a named list without destroying structure, so it becomes a
`zuyaml_map`: two parallel lists, `keys` and `values`.

``` r

yaml_parse("? [one, two]\n: value\n")
#> <zuyaml_map> 1 pair
#>   key:   list("one", "two")
#>   value: "value"
```

## Anchors and aliases

Aliases are resolved to the value of their target. Node identity is not
preserved — R has no portable way to express it.

``` r

str(yaml_parse("defaults: &d\n  timeout: 30\nserver: *d\n"))
#> List of 2
#>  $ defaults:List of 1
#>   ..$ timeout: int 30
#>  $ server  :List of 1
#>   ..$ timeout: int 30
```

Cycles are refused, and `aliases = "error"` rejects aliases outright.

## Tags

A tag overrides schema resolution: `!!str 12` is the string, not the
integer. Core schema tags are honoured in every spelling — the shorthand
`!!str`, the verbatim `!<tag:yaml.org,2002:str>`, and a handle bound by
a `%TAG` directive — and the non-specific tag `!` forces string
resolution too.

``` r

yaml_parse("!!str 12")
#> [1] "12"
yaml_parse("! 12")
#> [1] "12"
yaml_parse('!!int "12"')
#> [1] 12
```

A core tag on text that does not conform to it resolves as a string,
which is what an unresolvable scalar is in YAML.

``` r

yaml_parse("!!float abc")
#> [1] "abc"
```

Application tags such as `!duration` are ignored by default: the value
is converted as though it carried no tag. Refusing them would reject a
great deal of ordinary YAML — the specification’s own examples carry
application tags — so `tags = "error"` is opt-in, for callers who would
rather hear about the semantics they are dropping.

``` r

yaml_parse("v: !duration 5m")
#> $v
#> [1] "5m"
try(yaml_parse("v: !duration 5m", tags = "error"))
#> Error : Unsupported YAML tag '!duration' at line 1, column 4.
```

A `%TAG` directive that rebinds a handle is honoured, so the shorthand
no longer names a core tag.

``` r

yaml_parse("%TAG !! tag:example.com,2000:app/\n---\n!!int 1 - 3\n")
#> [1] "1 - 3"
```

## Emitting

``` r

cat(yaml_emit(list(host = "localhost", port = 8080L, tls = TRUE)))
#> host: localhost
#> port: 8080
#> tls: true
```

Strings that would resolve as another type under the core schema are
quoted, so they survive a round trip:

``` r

cat(yaml_emit(list(version = "42", ratio = 0.5, name = "true")))
#> version: "42"
#> ratio: 0.5
#> name: "true"
```

Ambiguous input is refused rather than guessed at. A partially named
list has no obvious meaning as either a sequence or a mapping:

``` r

try(yaml_emit(list(a = 1, 2)))
#> Error : Cannot emit a partially named list or vector: element 2 has no name. Name every element or none.
try(yaml_emit(data.frame(a = 1)))
#> Error : Data frames are not emitted automatically; convert explicitly to a list.
```

[`list()`](https://rdrr.io/r/base/list.html) cannot express both an
empty sequence and an empty mapping, so it emits as `[]`, and an empty
*named* list is how you ask for
[`{}`](https://rdrr.io/r/base/Paren.html).

``` r

cat(yaml_emit(list()))
#> []
cat(yaml_emit(structure(list(), names = character())))
#> {}
```

## Untrusted input

Three limits apply, all enforced by `zuyaml` itself:

- `max_size` — input bytes;
- `max_depth` — nesting depth;
- `max_nodes` — total values materialised.

The third exists because the first two do not bound *alias expansion*. A
billion-laughs document is small and shallow by construction, yet
expands exponentially:

``` r

bomb <- paste0(
  "a: &a [x,x,x,x,x,x,x,x,x]\n",
  "b: &b [*a,*a,*a,*a,*a,*a,*a,*a,*a]\n",
  "c: &c [*b,*b,*b,*b,*b,*b,*b,*b,*b]\n",
  "d: &d [*c,*c,*c,*c,*c,*c,*c,*c,*c]\n",
  "e: [*d,*d,*d,*d,*d,*d,*d,*d,*d]\n"
)
nchar(bomb)
#> [1] 163
try(yaml_parse(bomb, max_nodes = 1000))
#> Error : Document exceeds the node limit (1000); see max_nodes.
```

## Errors

Failures are classed conditions carrying a stable code and a position,
so callers never have to match on message text.

``` r

err <- tryCatch(yaml_parse("a: [1, 2"), zuyaml_error = identity)
err$code
#> [1] "syntax"
err$line
#> [1] 2
err$column
#> [1] 1
```

## What does not round-trip

Every entry below is a deliberate trade-off, not an oversight.

| Construct | Behaviour | Round-trips? |
|----|----|----|
| Comments | Discarded | No |
| Quoting and block style | Re-chosen on emit | Semantically |
| Anchors and aliases | Resolved to values | Semantically |
| Tags | Applied on parse, then discarded | **No** |
| Non-string scalar keys | Stringified (`1` → `"1"`) | Semantically |
| Collection-valued keys | `zuyaml_map` on parse | **No** — cannot be emitted |
| Duplicate keys (opt-in) | Duplicate R names | **No** — cannot be emitted |
| `NA` | Emitted as `null`, parses back as `NULL` | **No** |
| `list(1L)` vs `c(1L)` | Both emit `- 1` | **No** |
| Whole-numbered doubles | Emit as `42`, parse back as integer | Numerically |
| `big_integers = "double"` | Precision lost | No (opt-in) |

`zuyaml` is a semantic parser, not a round-trip editor: it converts
values, and formatting is not part of the value. Preserving comments and
layout would need a different API built on a retained document.
