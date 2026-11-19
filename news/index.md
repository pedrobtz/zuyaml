# Changelog

## zuyaml 0.1.1

A bug-fix release. Several of these fixes correct values that 0.1.0
returned silently wrong, so upgrading is recommended.

### Bug fixes

- Integers above 2^64 keep their digits. 0.1.0 wrapped some of them
  modulo 2^64 without a warning: `43526186596692760666` came back as the
  `zuyaml_bigint` `"6632698449273657434"`
  ([\#37](https://github.com/pedrobtz/zuyaml/issues/37)).

- Hex and octal integers beyond 64 bits, and negative ones below -2^63,
  are `zuyaml_bigint` like their decimal spellings and follow
  `big_integers`. 0.1.0 returned them as strings. A hex or octal literal
  longer than 4096 digits is refused with code `limit_size`
  ([\#31](https://github.com/pedrobtz/zuyaml/issues/31)).

- [`yaml_emit()`](https://pedrobtz.github.io/zuyaml/reference/yaml_emit.md)
  quotes every string the parser would read back as another type.
  `"-0x10"`, `"+0o7"`, `"nULL"`, `"tRUE"` and `".iNf"` used to be
  emitted plain and came back as `-16L`, `7L`, `NULL`, `TRUE` and `Inf`
  ([\#30](https://github.com/pedrobtz/zuyaml/issues/30)).

- [`yaml_emit()`](https://pedrobtz.github.io/zuyaml/reference/yaml_emit.md)
  translates names to UTF-8 as it does values. A latin1 name produced
  output that was not valid UTF-8, and two names with the same text in
  different encodings were not caught as duplicates
  ([\#32](https://github.com/pedrobtz/zuyaml/issues/32)).

- Deeply nested flow collections (`[[[...]]]`, `{a: {a: ...}}`) are
  refused as soon as they pass `max_depth`. Before, the whole document
  was scanned first, in time growing with the square of the depth: 80 KB
  of `[` took ten seconds, so a small hostile document could hold the
  parser for hours. The error is still `limit_depth`. A document that is
  both too deep and invalid in another way now reports `limit_depth`
  rather than the other error
  ([\#28](https://github.com/pedrobtz/zuyaml/issues/28),
  [\#34](https://github.com/pedrobtz/zuyaml/issues/34)).

- Nesting deeper than the C stack allows, possible with `max_depth = 0`
  or with a deeply nested list given to
  [`yaml_emit()`](https://pedrobtz.github.io/zuyaml/reference/yaml_emit.md),
  raises R’s `stackOverflowError` instead of crashing the session. The
  default `max_depth` trips first with a wide margin, measured at about
  10x on a 256 KB stack
  ([\#8](https://github.com/pedrobtz/zuyaml/issues/8)).

- [`yaml_emit()`](https://pedrobtz.github.io/zuyaml/reference/yaml_emit.md)
  of more than an R string can hold (2^31 - 1 bytes) is an error with
  code `limit_size`. It used to hang, uninterruptibly, once the strings
  being emitted passed 2 GB, or fail with “negative length vectors are
  not allowed” ([\#8](https://github.com/pedrobtz/zuyaml/issues/8),
  [\#33](https://github.com/pedrobtz/zuyaml/issues/33)).

- Errors found while converting a parsed document (`duplicate_key`,
  `limit_depth`, `limit_nodes`, `precision`, `alias`, `unsupported_tag`)
  carry `line` and `column`, and `path` when reading a file; they were
  `NULL`. An end position that is not known is `NULL` rather than `0`
  ([\#35](https://github.com/pedrobtz/zuyaml/issues/35)).

### Other changes

- Numbers are converted by the header-only zufast package (`LinkingTo:`)
  instead of the C library’s `strtod()`, so floats are correctly rounded
  on every platform. Under an explicit `!!float` tag, text that is C
  number syntax but not YAML float syntax is now a string, as under
  every other core tag: `!!float 0x10`, `!!float 0x1p3` and
  `!!float inf` used to give 16, 8 and `Inf`
  ([\#14](https://github.com/pedrobtz/zuyaml/issues/14)).

## zuyaml 0.1.0

CRAN release: 2026-10-07

First release. The API is complete and the package is well tested, but
it is **not frozen**: names, defaults and return types may still change.
Pin the version if you depend on it.

### Features

- [`yaml_parse()`](https://pedrobtz.github.io/zuyaml/reference/yaml_parse.md)
  /
  [`yaml_parse_all()`](https://pedrobtz.github.io/zuyaml/reference/yaml_parse.md)
  parse YAML 1.2 from a string or a raw vector,
  [`yaml_emit()`](https://pedrobtz.github.io/zuyaml/reference/yaml_emit.md)
  /
  [`yaml_emit_all()`](https://pedrobtz.github.io/zuyaml/reference/yaml_emit.md)
  convert R objects back to YAML, and
  [`yaml_read()`](https://pedrobtz.github.io/zuyaml/reference/yaml_read.md)
  /
  [`yaml_read_all()`](https://pedrobtz.github.io/zuyaml/reference/yaml_read.md)
  /
  [`yaml_write()`](https://pedrobtz.github.io/zuyaml/reference/yaml_read.md)
  /
  [`yaml_write_all()`](https://pedrobtz.github.io/zuyaml/reference/yaml_read.md)
  do the same for files. Throughout, `_all` means a YAML *stream*:
  several documents separated by `---`, which is a different thing from
  a sequence.

- Scalars follow the YAML 1.2 core schema, so `yes` and `no` are strings
  and dates are not coerced. Quoted scalars are always strings, and a
  quoted empty string never becomes `NULL`.

- Integers beyond 2^53 are preserved as `zuyaml_bigint` rather than
  silently rounded. `big_integers` selects a different policy.

- Tags override schema resolution, so `!!str 12` is the string `"12"`,
  in every spelling a core tag has: the shorthand, the verbatim form,
  and a handle bound by a `%TAG` directive. Application tags such as
  `!duration` are ignored by default; `tags = "error"` refuses them.

- Mappings whose keys are sequences or mappings become `zuyaml_map`
  rather than having their structure flattened into names. This is
  parse-only.

- Errors are classed conditions carrying a stable `code`, `line` and
  `column`, so callers never have to match on message text.

- `max_size`, `max_depth` and `max_nodes` bound untrusted input. The
  last of these is what stops alias-expansion bombs, which are small and
  shallow by construction and so escape the first two.

- A value emitted with
  [`yaml_emit()`](https://pedrobtz.github.io/zuyaml/reference/yaml_emit.md)
  parses back to the same value. Strings containing a line break, and
  strings with leading or trailing whitespace, are quoted so that
  neither is lost; a double with an integral value emits as `1.0`, so it
  does not come back as an integer; and mapping keys are treated exactly
  like values. Asserted over the whole yaml-test-suite and over
  generated input. The exceptions are listed in `vignette("zuyaml")`.

- A literal NUL byte in the input is refused with an `embedded_nul`
  condition and a position. The underlying library treats one as end of
  input, so the rest of the document – including any later documents in
  the stream – would otherwise be discarded without a word.

- A UTF-8 byte order mark at the start of a stream is not part of the
  document.

- A float outside the range of a double converts to the nearest one:
  `1e309` is `Inf`, `1e-324` is `0`, and `1e-323` is the subnormal it
  names. One extreme value never changes the R type of a field.

### Notes

- `simplify` defaults to `FALSE`: the shape of the result never depends
  on the contents of the document.

- The `cyaml` C library is bundled and pinned to v0.1.3. See
  `inst/COPYRIGHTS` for licensing and the modifications made for R
  compatibility, and `tools/patches/README.md` for why each one is
  required.
