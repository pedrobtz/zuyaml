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
