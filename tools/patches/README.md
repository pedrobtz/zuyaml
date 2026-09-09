# Patches applied to vendored cyaml

Applied in filename order by `tools/vendor-cyaml.sh`, against a pristine copy
of the upstream `src/` tree. Every patch here is **mandatory** — the vendor
script refuses to run if this directory is empty.

Keep them minimal and keep upstream recognisable: no reformatting, no symbol
renaming, no cosmetic changes. A patch that fails to apply after an upstream
bump is a signal to re-read the design's verification note, not to force it
through.

## 0001-assertions-no-abort.patch

**Why it is required:** `cyaml_internal.h` defines `CYAML_ASSERT` and
`CYAML_UNREACHABLE` as `fprintf(stderr, ...)` followed by `abort()`, described
upstream as "release-safe [...] always active". CRAN policy prohibits compiled
code that writes to `stderr` or calls `abort()`, and in an R package `abort()`
would terminate the user's entire session — including unsaved work — rather
than raise a catchable error.

**What it does:** routes both macros through `zuyaml_panic()`
(`src/zuyaml_panic.c`), which raises an R error condition. The helper is
declared `_Noreturn` so that the compiler still treats `CYAML_UNREACHABLE` as
terminating a code path.

**Known trade-off:** `Rf_error()` is a `longjmp`, so whatever cyaml had
allocated at the point of the assertion leaks. That is acceptable here and
only here: these macros fire solely on a violated library invariant — a bug —
and leaking on that path is much better than killing the session. This is *not*
a licence to raise R errors from inside cyaml anywhere else; see the unwind
safety section of the design.

**Upstream usage:** one call site at the time of writing (`cyaml_emitter.c`).
Re-check after every upstream bump — new call sites are silently absorbed by
this patch, which is the intent, but the count is worth knowing.

## 0002-emitter-plain-scalar-style.patch

**Why it is required:** `emit_scalar()` promotes any *plain* scalar whose text
is `null`, `true`, `false` or `~` to double-quoted. cyaml scalars carry no type
of their own — a type is inferred from the text — so quoting is the safe
default for a string, but it has two consequences:

- a boolean built with `cyaml_new_bool()` emits as the **string** `"true"`;
- cyaml's own parse-then-emit turns `a: true` into `a: "true"`.

There is no way around it through the public API. The only escape hatch is a
non-zero `tag_len`, and any non-zero tag is emitted verbatim, which would put
`!!bool` in front of every logical value.

**What it does:** suppresses that one promotion. Every other quoting rule —
indicators, document markers, trailing colons, line breaks, `: `, ` #`, the
empty string — still applies.

**Why it is safe here:** zuyaml chooses scalar styles *before* building, and
double-quotes any string that would resolve as a non-string under the YAML 1.2
core schema (see `resolves_as_non_string()` in `src/zuyaml_emit.c`). So the
decision this patch removes has already been made, more precisely, by the
caller.

**The constraint it introduces:** this is safe *only* because zuyaml always
builds nodes from R values and never re-emits a parsed document. If a future
document API emits parsed nodes directly (design §20), it must restore the
promotion or set styles explicitly, or strings spelled `true` will emit
unquoted and change type.

**Worth reporting upstream:** the parse-then-emit case is a bug in cyaml
independent of zuyaml.

## 0003-doc-append-zero-length.patch

**Why it is required:** `cyaml_doc_append()` copies with

```c
memcpy(doc->src.owned.ptr + doc->src.owned.len, data, len);
```

When the first append to a fresh document has `len == 0`, `needed` is also 0,
so the buffer-growth branch above never runs and `owned.ptr` is still `NULL`.
`memcpy` is declared `nonnull`, so `memcpy(NULL, data, 0)` is undefined
behaviour even though it copies nothing.

`cyaml_new_str(doc, "", 0)` reaches it, which means `yaml_emit("")` — emitting
an empty string — is enough to trigger it.

**What it does:** skips the copy when there is nothing to copy.

**How it was found:** UndefinedBehaviorSanitizer, and both ASan builds,
reported it identically:

```
cyaml.c:550: runtime error: null pointer passed as argument 1,
             which is declared to never be null
  cyaml_doc_append ← cyaml_new_str ← new_string_node ← build_element
```

Nothing else caught it — not the test suite, not the fuzzer, not valgrind,
which does not check `nonnull` attributes. CRAN runs UBSan builds, so this
would have surfaced there.

**Worth reporting upstream:** it is a real defect independent of zuyaml, and
reachable from any caller that appends an empty string.

## 0004-str-to-i64-int64-min.patch

**Why it is required:** `cyaml_str_to_i64()` negates the parsed magnitude with

```c
*out = -(int64_t)uval;
```

For `INT64_MIN` the magnitude is `(uint64_t)INT64_MAX + 1`, which the bound
check above deliberately admits. Converting it to `int64_t` yields `INT64_MIN`,
and negating `INT64_MIN` overflows — signed overflow, which is undefined
behaviour, not merely implementation-defined.

Parsing the ordinary literal `-9223372036854775808` is enough to reach it.

**What it does:** returns `INT64_MIN` directly for that one magnitude, leaving
every other value on the original path, where the negation is in range.

**How it was found:** UndefinedBehaviorSanitizer:

```
cyaml_utf8.c:1049: runtime error: negation of -9223372036854775808 cannot be
                   represented in type 'int64_t'
```

The value produced was correct on the compilers tried, so nothing else caught
it — not the test suite, not the fuzzer. `tools/sanitizer-exercise.R` did not
reach it either, which is why the sanitizer CI job stayed green; it now parses
the 64-bit boundary values explicitly.

**Worth reporting upstream:** it is a real defect independent of zuyaml, in a
function any caller reaches through `cyaml_as_int()`.
