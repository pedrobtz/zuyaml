# Read and write YAML files

`yaml_read()` reads one YAML document from a file; `yaml_read_all()`
reads a stream. `yaml_write()` and `yaml_write_all()` are their
counterparts.

## Usage

``` r
yaml_read(path, ...)

yaml_read_all(path, ...)

yaml_write(x, path, ...)

yaml_write_all(x, path, ...)
```

## Arguments

- path:

  Path to a file.

- ...:

  Passed to
  [`yaml_parse()`](https://pedrobtz.github.io/zuyaml/reference/yaml_parse.md)
  or
  [`yaml_emit()`](https://pedrobtz.github.io/zuyaml/reference/yaml_emit.md).

- x:

  An R object. `yaml_write_all()` takes a list, one element per
  document.

## Value

`yaml_read()` returns an R object and `yaml_read_all()` a list of them.
The writers return `path` invisibly.

## Details

These work on bytes, not text: files are read and written with
[`readBin()`](https://rdrr.io/r/base/readBin.html) and
[`writeBin()`](https://rdrr.io/r/base/readBin.html), so nothing depends
on the session's locale, and the file path is carried into parse errors
to make them locatable.

## Examples

``` r
path <- tempfile(fileext = ".yml")
yaml_write(list(host = "localhost", port = 8080L), path)
yaml_read(path)
#> $host
#> [1] "localhost"
#> 
#> $port
#> [1] 8080
#> 
unlink(path)
```
