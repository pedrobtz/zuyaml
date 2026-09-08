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
