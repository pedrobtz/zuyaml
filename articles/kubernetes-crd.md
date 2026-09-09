# A Kubernetes CRD in YAML

The YAML most people actually deal with is machine-written
configuration, and the largest example in common circulation is a
Kubernetes CustomResourceDefinition: an OpenAPI schema for a resource
type, expanded into YAML. The Prometheus Operator’s `Prometheus` CRD is
773 KB and 13,000 lines, nested 27 levels deep.

The URL is pinned to a release tag rather than a branch, so the file —
and therefore everything printed below — does not change under you.

``` r

library(zuyaml)

url <- paste0("https://raw.githubusercontent.com/prometheus-operator/",
              "prometheus-operator/v0.76.0/example/prometheus-operator-crd/",
              "monitoring.coreos.com_prometheuses.yaml")
path <- file.path(tempdir(), "prometheuses.yaml")
download.file(url, path, quiet = TRUE)

c(bytes = file.size(path), lines = length(readLines(path)))
#>  bytes  lines
#> 773063  13063
```

## Reading it

``` r

crd <- yaml_read(path)

names(crd)
#> [1] "apiVersion" "kind"       "metadata"   "spec"

crd$kind
#> [1] "CustomResourceDefinition"

crd$metadata$name
#> [1] "prometheuses.monitoring.coreos.com"
```

Parsing takes about 9 milliseconds.
[`yaml_read()`](https://pedrobtz.github.io/zuyaml/reference/yaml_read.md)
rather than
[`yaml_parse()`](https://pedrobtz.github.io/zuyaml/reference/yaml_parse.md)
because the path then travels with the document: if the file were
malformed, the error would name it rather than reporting a line number
in the abstract.

## How deep this actually goes

``` r

depth <- function(x) if (!is.list(x) || !length(x)) 0L else 1L + max(vapply(x, depth, 1L))
nodes <- function(x) if (!is.list(x)) 1L else 1L + sum(vapply(x, nodes, 1L))

c(depth = depth(crd), nodes = nodes(crd))
#> depth nodes
#>    27  7810
```

27 levels. The default `max_depth` is 128, so this passes comfortably —
but that default exists because a hand-written recursive walk over an
untrusted document is exactly how a stack overflow happens, and this
file shows that real configuration reaches double-digit depths without
anyone intending it.

The deepest path in the file is worth seeing, because it explains where
the depth comes from — a schema describing a schema describing a pod
spec:

``` r

#> spec > versions > [[1]] > schema > openAPIV3Schema > properties > spec >
#> properties > volumes > items > properties > projected > properties >
#> sources > items > properties > downwardAPI > properties > items > items >
#> properties > resourceFieldRef > properties > divisor > anyOf > [[1]] > type
```

## The schema itself

``` r

spec <- crd$spec
c(group = spec$group, scope = spec$scope)
#>                   group                   scope
#> "monitoring.coreos.com"            "Namespaced"

props <- spec$versions[[1]]$schema$openAPIV3Schema$properties$spec$properties
length(props)
#> [1] 104

sort(table(vapply(props, function(p) p$type, "")), decreasing = TRUE)
#>  object  string   array integer boolean
#>      31      26      19      16      12
```

104 configurable fields on one resource, which is a fair summary of why
this file is 13,000 lines long.

## Where the core schema earns its keep

This is the part that separates YAML 1.2 from YAML 1.1, and a Kubernetes
manifest is where it bites. Version identifiers are strings:

``` r

str(spec$versions[[1]]$name)
#>  chr "v1"
```

and `served` and `storage` are genuine booleans:

``` r

str(spec$versions[[1]][c("served", "storage")])
#> List of 2
#>  $ served : logi TRUE
#>  $ storage: logi TRUE
```

Under YAML 1.1 the tokens `yes`, `no`, `on` and `off` also resolve as
booleans, which is the origin of the well-known Kubernetes and Ansible
footgun: a country code `NO` becomes `FALSE`, and a port key `on`
becomes `TRUE`. `zuyaml` follows the 1.2 core schema, so only `true` and
`false` are boolean and everything else spelled like a word is a string.
Nothing in this file is silently retyped.

``` r

str(yaml_parse("country: NO\nenabled: true\nversion: 1.10\n"))
#> List of 3
#>  $ country: chr "NO"
#>  $ enabled: logi TRUE
#>  $ version: num 1.1
```

Note `1.10` arriving as the number `1.1`: that one *is* lossy, and it is
why image tags and version strings belong in quotes in the document
itself. YAML cannot tell you what was meant, so the package does not
guess.

## Pointing it at something you did not write

A CRD from a registry is not a file you audited. The limits are
arguments rather than global options, so they travel with the call:

``` r

yaml_read(path, max_depth = 8)
#> Error : YAML nesting exceeds max_depth (8).

crd <- yaml_read(path, max_size = 2 * 1024^2, max_depth = 64, max_nodes = 1e5)
```

`max_size` bounds the input, `max_depth` the nesting, and `max_nodes`
the number of values materialised — the last is what stops an alias
bomb, which is small and shallow by construction and so slips past the
first two. Every one of them raises a classed condition you can catch.
