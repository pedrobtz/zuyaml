# zuyaml 0.9.0

First release candidate. The API is complete but not yet frozen; it may still
change before 1.0.0.

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

* Mappings whose keys are sequences or mappings become `zuyaml_map` rather than
  having their structure flattened into names. This is parse-only.

* Errors are classed conditions carrying a stable `code`, `line` and `column`,
  so callers never have to match on message text.

* `max_size`, `max_depth` and `max_nodes` bound untrusted input. The last of
  these is what stops alias-expansion bombs, which are small and shallow by
  construction and so escape the first two.

## Notes

* `simplify` defaults to `FALSE`: the shape of the result never depends on the
  contents of the document.

* The `cyaml` C library is bundled and pinned to v0.1.3. See `inst/COPYRIGHTS`
  for licensing and the two modifications made for R compatibility.
