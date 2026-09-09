# Emit YAML

`yaml_emit()` converts one R object to a YAML document.
`yaml_emit_all()` converts a list of objects to a YAML *stream*.

## Usage

``` r
yaml_emit(
  x,
  indent = 2L,
  width = 80L,
  document_start = FALSE,
  document_end = FALSE
)

yaml_emit_all(
  x,
  indent = 2L,
  width = 80L,
  document_start = FALSE,
  document_end = FALSE
)
```

## Arguments

- x:

  An R object. `yaml_emit_all()` takes a list, one element per document.

- indent:

  Spaces per indentation level, 1 to 255.

- width:

  Line width before wrapping, 0 to 255. `0` disables wrapping.

- document_start:

  Emit a leading `---`.

- document_end:

  Emit a trailing `...`.

## Value

A length-one UTF-8 character vector.

## Details

Emission favours readable YAML over reproducing any particular source
formatting. Comments, quoting style and flow-versus-block choices are
not preserved; see `vignette("zuyaml")` for the conversions that do not
round trip.

## Examples

``` r
cat(yaml_emit(list(host = "localhost", port = 8080L)))
#> host: localhost
#> port: 8080
cat(yaml_emit_all(list(list(a = 1L), list(b = 2L))))
#> a: 1
#> ---
#> b: 2

# Strings that look like other types stay strings.
cat(yaml_emit(list(version = "42")))
#> version: "42"
```
