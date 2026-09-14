# zuyaml 0.1.0

First release. The API is complete and the package is well tested, but it is
**not frozen**: names, defaults and return types may still change. Pin the
version if you depend on it.

## Features

* `yaml_parse()` / `yaml_parse_all()` parse YAML 1.2 from a string or a raw
  vector, `yaml_emit()` / `yaml_emit_all()` convert R objects back to YAML, and
  `yaml_read()` / `yaml_read_all()` / `yaml_write()` / `yaml_write_all()` do the
  same for files. Throughout, `_all` means a YAML *stream*: several documents
  separated by `---`, which is a different thing from a sequence.

* Scalars follow the YAML 1.2 core schema, so `yes` and `no` are strings and
  dates are not coerced. Quoted scalars are always strings, and a quoted empty
  string never becomes `NULL`.

* Integers beyond 2^53 are preserved as `zuyaml_bigint` rather than silently
  rounded. `big_integers` selects a different policy.

* Tags override schema resolution, so `!!str 12` is the string `"12"`, in every
  spelling a core tag has: the shorthand, the verbatim form, and a handle bound
  by a `%TAG` directive. Application tags such as `!duration` are ignored by
  default; `tags = "error"` refuses them.

* Mappings whose keys are sequences or mappings become `zuyaml_map` rather than
  having their structure flattened into names. This is parse-only.

* Errors are classed conditions carrying a stable `code`, `line` and `column`,
  so callers never have to match on message text.

* `max_size`, `max_depth` and `max_nodes` bound untrusted input. The last of
  these is what stops alias-expansion bombs, which are small and shallow by
  construction and so escape the first two.

* A value emitted with `yaml_emit()` parses back to the same value. Strings
  containing a line break, and strings with leading or trailing whitespace, are
  quoted so that neither is lost; a double with an integral value emits as
  `1.0` rather than `1`, so it does not come back as an integer; and mapping
  keys get the same treatment as values. The property is asserted over the
  whole yaml-test-suite and over generated input, not over a list of cases.

* A literal NUL byte in the input is refused with an `embedded_nul` condition
  and a position. The underlying library treats one as end of input, so the
  rest of the document -- including any later documents in the stream -- would
  otherwise be discarded without a word.

* A UTF-8 byte order mark at the start of a stream is not part of the document.

* A float outside the range of a double is converted to the nearest one:
  `1e309` is `Inf`, `1e-324` is `0`, and `1e-323` is the subnormal it names.
  These previously came back as *character strings*, so the R type of a field
  depended on the magnitude of its value.

## Notes

* `simplify` defaults to `FALSE`: the shape of the result never depends on the
  contents of the document.

* The `cyaml` C library is bundled and pinned to v0.1.3. See `inst/COPYRIGHTS`
  for licensing and the modifications made for R compatibility, and
  `tools/patches/README.md` for why each one is required.
