# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Shared conventions

The portfolio's shared rules are synced into `.claude/shared/` from
`pedrobtz/packages:claude/shared/`. Never edit them here. Where this file and
a shared file disagree, this file wins for this package.

@.claude/shared/workflow.md
@.claude/shared/r-package.md
@.claude/shared/ci.md
@.claude/shared/native-code.md
@.claude/shared/correctness.md
@.claude/shared/assurance.md

## What this is

zuyaml parses and emits YAML 1.2 to and from ordinary R objects through a
vendored copy of the cyaml C11 library, with no system library and no runtime
dependency beyond R. It is strict where YAML is ambiguous: duplicate keys are
refused by default, the 1.2 core schema means `yes` and `no` are strings,
integers beyond 2^53 are kept as `zuyaml_bigint`, and a stream (`_all`) is
kept apart from a sequence. `max_size`, `max_depth` and `max_nodes` bound
untrusted input, `max_nodes` being what stops alias bombs. The C layer uses
the R C API directly: no Rcpp, cpp11 or C++. A persistent document API is
future work (design §20), and no performance claim belongs in user-facing
text.

Three documents in `.agents/` are the specification and outrank this file:
[`DESIGN-zuyaml.md`](.agents/DESIGN-zuyaml.md) (what to build; key decisions
§21, open questions §22), [`ROADMAP.md`](.agents/ROADMAP.md) (milestones
M0–M9) and [`STATUS.md`](.agents/STATUS.md) (what was demonstrated, and what
upstream actually does). The design's verification note applies to every
cyaml claim: grep the implementation and write a test, because the header and
README are not reliable.

## Current state

Verified 2026-11-11. 0.1.0 is on CRAN (published 2026-10-07) with the API
complete but explicitly **not frozen**. `main` is `0.1.0.9000` with no
changes yet in `NEWS.md`. Milestones M0–M6.6 are done. M7 (freeze to 1.0.0)
waits on the three open questions in design §22 (key stringification, eight
versus five functions, whether `zuyaml_bigint` and `zuyaml_map` belong in
1.0) and on `conditionCall()`, which is still `NULL` in both layers
(`R/conditions.R`, `src/zuyaml_error.c`). `STATUS.md` was last revised
2026-09-14, before the release, so its release and housekeeping notes are out
of date.

## Versions and dependents

The current version's parent issue is
[#15](https://github.com/pedrobtz/zuyaml/issues/15) for `v0.1.1`; its one
sub-issue is #14, adopting zufast for scalar number resolution. #17 is the
reminder that the next submission opens from 2026-11-18. Sibling packages
that depend on this one: none yet. Design §19 plans zuhttp's use of it for
YAML response bodies.

## Commands

Occasional, from the package root:

```sh
tools/vendor-cyaml.sh                          # re-vendor cyaml at the pinned commit
tools/fetch-yaml-test-suite.sh <dir>           # check out the full upstream suite
Rscript tools/conformance.R <dir>              # full suite vs the pinned baseline
Rscript tools/curate-test-suite.R <dir>        # rebuild the shipped subset
Rscript tools/sanitizer-exercise.R <fixtures>  # base-R driver for ASan
Rscript tools/benchmark.R                      # against the yaml package
```

Before a sanitizer or benchmark build, `find src -name '*.o' -delete`:
`load_all()` leaves `-O0` objects in `src/`, and `R CMD INSTALL .` reuses any
`.o` newer than its `.c`, so the build is silently uninstrumented or
unoptimised. `nm -u .../zuyaml.so | grep -c asan` tells an instrumented build
from one that is not.

## Architecture

- **Vendored cyaml lives flat in `src/`** (`cyaml*.c`, `cyaml*.h`), not in
  `src/vendor/`, because `R CMD SHLIB` compiles only top-level sources and a
  subdirectory would need a hand-kept `OBJECTS` list in both Makevars files.
  `zuyaml_`-prefixed files are ours. All eight `.c` files are vendored,
  including the unused YPATH, JSON, modify and events units, because
  `cyaml.c` references them (design §13.1).
- **Two entry points** (design §9.2): `zuyaml_parse_()` always returns a list
  of documents, and `yaml_parse()` is an R wrapper that requires exactly one;
  `zuyaml_emit_()` emits. Argument validation (types, ranges, `match.arg()`)
  happens in R; C trusts what it receives.
- `src/zuyaml_convert.c` turns the cyaml tree into R values (design §6,
  §9.5), `src/zuyaml_emit.c` builds a cyaml document from R values and picks
  scalar styles (§7), `src/zuyaml_error.c` maps `cyaml_err_t` to the stable
  `code` strings of §10.1, and `src/zuyaml_panic.c` is where patch 0001 sends
  cyaml's assertions.
- `src/init.c` registers both entry points with
  `R_useDynamicSymbols(dll, FALSE)` and `R_forceSymbols(dll, TRUE)`.
- Errors are `zuyaml_parse_error` (and siblings) inheriting `zuyaml_error`,
  carrying `code`, `line`, `column`, `end_line`, `end_column` and, for files,
  `path`. The message is composed by zuyaml, never passed through from cyaml.

## Invariants that are easy to break

- **A parsed cyaml stream is owned by a transient external pointer** with a
  finalizer, from the moment `cyaml_parse_stream()` succeeds. Any
  `Rf_error()`, allocation failure or interrupt would otherwise unwind past
  `cyaml_stream_free()` and leak the tree. The same holds for the emit
  path's `cyaml_doc_t` and output buffer (design §9.3).
- **The `char *` from `cyaml_scalar_str()` must not be live across an
  allocating R call.** Plain scalars take the zero-copy path through
  `cyaml_str()`/`cyaml_len()` instead (design §9.5).
- **The parsed tree borrows its source buffer:** keep the input `SEXP`
  protected for the whole call (design §9.4).
- **`Rf_getAttrib()` can allocate:** protect its result before passing it on.
  rchk found exactly this in `build_node()`, which nothing else caught.
- **cyaml ignores `dup_keys`, `max_depth` and `max_size`** and never raises
  `CYAML_ERR_DUP_KEY`. zuyaml enforces all three itself; do not hand them to
  cyaml and assume they work.
- **Scan for NUL before parsing and during conversion, and skip a leading
  BOM:** the parser treats a literal NUL as end of input and drops the rest
  silently, and leaves a BOM inside the first scalar.
- **Emitter round trip:** the same "needs a non-plain style" predicate applies
  to values *and* keys, integral doubles emit as floats (`1.0`), and `NULL`
  and `NA` emit as an explicit `null`. Each rule closed a silent data loss
  found in M6.5.
- **Doubles are formatted by zuyaml,** not by `cyaml_new_float()` (`%g`, six
  digits). An out-of-range float becomes the nearest double, never a string
  (`out_of_range_double()` in `zuyaml_convert.c`), so a field's R type never
  depends on its magnitude.
- **A new upstream error code must fail loudly** in the §10.1 mapping, not
  fall through to a default.
- **Never define `CYAML_DEBUG` or `CYAML_TRACE`:** they enable `printf()` and
  `stderr` paths that CRAN rejects. `CYAML_VERSION_STR` must be set in both
  Makevars files, or `cyaml_version()` misreports and `test-vendor.R` fails.
- **No snapshot tests of message text:** callers rely on `code`, `line` and
  `column`, and tests assert those.

## Testing

- **Conformance:** `tests/testthat/fixtures/yaml-test-suite/` is a curated
  84-case subset of the upstream yaml-test-suite, kept small for CRAN time;
  `test-conformance.R` checks valid versus invalid and
  `test-conformance-semantic.R` compares against the suite's `in.json`. The
  full suite runs outside `tests/` through `tools/conformance.R`, against a
  pinned baseline. The one deliberate semantic difference is case `WZ62`.
- **Round trip:** every suite case that emits must reparse to the same value,
  plus generated strings and every one- and two-character string over the
  indicator alphabet (`test-round-trip.R`).
- **Unwind safety:** `test-unwind-safety.R` runs poisoning loops over error
  paths and then asserts an ordinary parse still works, plus format-specifier
  and `R_forceSymbols` checks.
- **Helpers:** `helper-doubles.R` builds doubles from IEEE-754 bit patterns
  (`dbl()`), because R's reader is not correctly rounded on aarch64 and reads
  `DBL_MAX` written out in full as `Inf`. Write numeric expectations that way,
  never as R literals.
- `test-fuzz.R` holds the fuzz cases; `hardening.yaml` runs them at larger
  iteration counts through `tools/ci-run-tests.R fuzz`.

## Continuous integration

Shared r-actions workflows at `@v1`: `R-CMD-check.yaml` (with NOSUGGESTS,
since the suite needs only two of five Suggests, and NOLD, since number
parsing and emitting can be right only by accident of 80-bit intermediates),
`coverage.yaml`, and `native-checks.yaml`: sanitizers (ASan driven by
`tools/sanitizer-exercise.R` over the fixtures), valgrind, LTO, rchk, CRAN's
special flavours, and gctorture twice: step 500 on every push, step 20 weekly
and on demand. rchk stays permanently, because it alone found the
`build_node()` PROTECT bug.

Package-owned: `hardening.yaml` fetches the full yaml-test-suite and runs the
suite, `tools/conformance.R` and the fuzz cases, weekly and on push.
`pkgdown.yaml` builds the site.

Open CI gaps: #9 (no `vendor.yml`, so nothing guards hand edits to
`src/cyaml*.c`) and #7 (`-Wextra` no longer runs anywhere).

## Vendored native code

cyaml (`andrewmd5/cyaml`), MIT, tag `v0.1.3`, commit `0672e81b`, vendored
2026-09-08. `inst/cyaml-VERSION` is the generated record;
`tools/vendor-cyaml.sh` verifies each upstream file against its own SHA-256
manifest, because GitHub archives are not byte-stable. Five mandatory patches
in `tools/patches/`, each explained in its `README.md`:

- 0001 routes `CYAML_ASSERT` and `CYAML_UNREACHABLE` to `zuyaml_panic()`
  instead of `fprintf(stderr)` and `abort()`. It leaks on that path, which is
  acceptable only because it fires on a cyaml bug.
- 0002 stops the emitter promoting plain `null`/`true`/`false`/`~` to
  double-quoted, so logicals emit as booleans.
- 0003 fixes appending a zero-length document.
- 0004 fixes `cyaml_str_to_i64()` at `INT64_MIN`.
- 0005 makes `cyaml_scalar_str()` return a built node's span verbatim, so
  emitted strings keep their line breaks.

Keep upstream recognisable: no reformatting or renaming, and every change as
a patch. Four upstream bugs are recorded in `STATUS.md` but not yet reported.
