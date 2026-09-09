# Mappings whose keys are not scalars

YAML mapping keys can be sequences or mappings, which cannot become R
names without destroying structure.
[`yaml_parse()`](https://pedrobtz.github.io/zuyaml/reference/yaml_parse.md)
represents such a mapping as a `zuyaml_map`: two parallel lists, `keys`
and `values`.

## Usage

``` r
# S3 method for class 'zuyaml_map'
print(x, ...)
```

## Arguments

- x:

  A `zuyaml_map`.

- ...:

  Ignored.

## Value

[`print()`](https://rdrr.io/r/base/print.html) returns `x` invisibly.

## Details

This is parse-only. The vendored cyaml builder can only attach string
keys, so a `zuyaml_map` cannot be emitted; see `vignette("zuyaml")` for
the full list of conversions that do not round-trip.

## Examples

``` r
yaml_parse("? [one, two]\n: value\n")
#> <zuyaml_map> 1 pair
#>   key:   list("one", "two")
#>   value: "value"
```
