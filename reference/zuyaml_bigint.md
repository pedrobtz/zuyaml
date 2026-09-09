# Integers too large for R's numeric types

A character vector holding the decimal representation of integers that R
cannot store exactly: beyond 2^53 a double silently loses precision, and
R has no native 64-bit integer scalar.

## Usage

``` r
zuyaml_bigint(x)
```

## Arguments

- x:

  A character vector of decimal integers, or an object to coerce.

## Value

`zuyaml_bigint()` returns a character vector of class `"zuyaml_bigint"`.

## Details

[`yaml_parse()`](https://pedrobtz.github.io/zuyaml/reference/yaml_parse.md)
returns one of these when it meets such a value and
`big_integers = "bigint"` (the default). It carries the *decimal*
normalisation of the value, not the source text, so `0x1FFFFFFFFFFFFFFF`
and its decimal spelling compare equal.

This is a marker for values whose precision must be preserved, not a
big-integer arithmetic type: there is no arithmetic. Use
[`as.numeric()`](https://rdrr.io/r/base/numeric.html) to accept the
precision loss deliberately, or a package such as `bit64` for real
64-bit arithmetic.

## Examples

``` r
yaml_parse("9223372036854775807")
#> <zuyaml_bigint>
#> [1] 9223372036854775807
as.numeric(yaml_parse("9223372036854775807")) # lossy, on purpose
#> [1] 9.223372e+18
```
