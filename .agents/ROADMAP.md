# zuyaml — Roadmap to v1.0

Companion to [DESIGN-zuyaml.md](DESIGN-zuyaml.md). The design says *what* to
build; this says *in what order*, and *how you know a stage is done*.

Milestones are sequenced, not scheduled — there are no dates, because the
ordering constraints are real and the calendar is not. Effort sizes are relative:
**S** ≈ a sitting, **M** ≈ a few, **L** ≈ a sustained push.

---

## What v1.0 means

v1.0 is a **stability promise**, not a feature count. Shipping it asserts:

1. The eight exported functions and their arguments are stable; changing them
   afterwards requires a deprecation cycle.
2. The documented R ↔ YAML conversion rules are stable, including every row of
   the lossy-conversion table (design §8).
3. `zuyaml_bigint` and `zuyaml_map` are stable, as far as they exist at 1.0.
4. `R CMD check --as-cran` is clean on Linux, macOS, and Windows.
5. The wrapper does not crash, leak, or hang on hostile input, demonstrated by
   sanitizers and fuzzing rather than asserted.
6. Every open question in design §22 has been decided on purpose.

Anything that cannot be committed to at that level is deferred past 1.0 — see
[Explicitly not in v1](#explicitly-not-in-v1).

---

## Current state

A bare `usethis` skeleton on `main`, nothing committed yet:

| Present | State |
|---|---|
| `DESCRIPTION` | **Template placeholders** — "What the Package Does", `First Last` |
| `NAMESPACE` | Empty roxygen stub |
| `R/zuyaml-package.R` | `useDynLib` stub only |
| `src/zuyaml-package.c` | Includes only, no entry points |
| `.github/workflows/R-CMD-check.yaml` | Present, untested against compiled code |
| `LICENSE` / `LICENSE.md` | MIT, needs the vendored-code notice |
| `.Rbuildignore` | Missing `^\.agents$` |

No cyaml source is vendored yet. Everything below is greenfield.

---

## Sequence

| # | Milestone | Version | Effort | Gate |
|---|---|---|---|---|
| M0 | Metadata and hygiene | — | S | Skeleton is a real package, not a template |
| M1 | Vendored build | 0.0.1 | M | Compiles clean on 3 platforms |
| M2 | Parser core | 0.1.0 | L | Representative YAML 1.2 → R, safely |
| M3 | Hard cases | 0.2.0 | L | No silent semantic loss |
| M4 | Emitter | 0.3.0 | L | Round trips hold, including numeric strings |
| M5 | Files and integration | 0.4.0 | S | Usable as a dependency |
| M6 | Conformance and hardening | 0.5.0 | L | Demonstrably robust |
| M7 | Freeze and release | 0.9.0 → 1.0.0 | M | CRAN-accepted, API committed |

M2 blocks everything after it. M3 and M4 are genuinely parallelisable if you want
to work on two fronts; M5 is trivial once M4 lands.

---

## M0 — Metadata and hygiene

**Goal:** stop looking like `usethis::create_package()` output.

- Fill `DESCRIPTION`: real `Title`, `Description`, `Authors@R`, `URL`,
  `BugReports`, `Encoding`. Add `SystemRequirements: C11` only if M1 proves it
  necessary (design §14.2).
- Add `^\.agents$` to `.Rbuildignore` — otherwise the design and this roadmap ship
  inside the tarball and draw a check NOTE.
- Set up `testthat` (edition 3) and `devtools::check()` as the working loop.
- Add the vendored-code notice scaffolding: `inst/COPYRIGHTS`.

**Exit:** `R CMD check --as-cran` passes with no ERRORs or WARNINGs, and only the
two NOTEs an empty package necessarily produces:

- *CRAN incoming feasibility* — "New submission" plus "Version contains large
  components (0.0.0.9000)"; the second goes away at the first real version;
- *compiled code* — "no symbols" and "Found no calls to `R_registerRoutines`,
  `R_useDynamicSymbols`", because `src/` has no entry points yet. **M1 clears
  this**, and it must not still be present at M1's exit.

---

## M1 — Vendored build

**Version 0.0.1 (internal).** No user-facing API yet.

- Write `tools/vendor-cyaml.sh`: fetch tag `v0.1.3`
  (`0672e81b809bc3dfd1d4f57ba0fcfbb20c60ae70`), verify the archive checksum, copy
  `src/*` **flat into `src/`** (design §9.1), apply the patch set, write
  `inst/cyaml-VERSION`.
- Apply the mandatory assertion patch to `cyaml_internal.h` (design §13.2):
  `CYAML_ASSERT` / `CYAML_UNREACHABLE` must not `abort()` or write to `stderr`.
  **This is a CRAN blocker, not a nicety.**
- Write `Makevars` and `Makevars.win` with
  `-DCYAML_VERSION_STR=\"0.1.3\"` (design §14.1). Without it `cyaml_version()`
  reports `"0.0.0-dev"`.
- Add `src/init.c` with `R_useDynamicSymbols(dll, FALSE)` and
  `R_forceSymbols(dll, TRUE)`.
- Expose one internal native routine returning `cyaml_version()`, purely to prove
  the build and to back the provenance test.
- Extend the CI matrix to Linux/GCC, Linux/Clang, macOS, Windows.

**Exit:**
- Package builds and loads on all four toolchains.
- `zuyaml:::cyaml_version()` returns `"0.1.3"`, matching `inst/cyaml-VERSION` —
  the test that catches both a botched vendor update and a missing `-D` flag.
- No compiler warnings under `-Wall -Wextra` that originate in `zuyaml_*` files.
- Re-running the vendor script produces a byte-identical tree (reproducibility).

**Risks:** anonymous unions or other C11 constructs tripping an older Windows
toolchain; the visibility question in design §14.4 (note it, don't fix it yet).

---

## M2 — Parser core

**Version 0.1.0.** The first release with a usable API.

- `zuyaml_parse_()`: single native entry point, always parsing as a stream via
  `cyaml_parse_stream()`, always returning a list of documents (design §9.2).
- `yaml_parse()` / `yaml_parse_all()` in R, including the zero / one / many
  document table (design §5.2).
- Scalar conversion via `cyaml_scalar_kind()`: null, bool, int (32-bit and
  double-representable only — big integers are M3), float, string.
- Sequences and scalar-key mappings.
- Structured conditions with code, line, and column (design §10), and the full
  `cyaml_err_t` mapping table.
- Argument validation in R, including the `uint8_t`/`uint32_t` ceilings.
- **Unwind safety (design §9.3) — build it now.**

> **Do not defer §9.3 to the hardening milestone.** Every `Rf_error()` this
> milestone introduces is a `longjmp` past `cyaml_stream_free()`. Retrofitting the
> transient-external-pointer scope after the conversion code is written means
> touching every allocation site a second time, and M6's fuzzer will find the
> leaks either way. It is cheap now and expensive later.

Same reasoning, smaller scale: take the zero-copy path for `CYAML_PLAIN` scalars
(design §9.5) from the start rather than writing `cyaml_scalar_str()` everywhere
and optimising later.

**Exit:**
- Representative YAML 1.2 documents convert correctly.
- `yaml_parse("a: 1")`, `yaml_parse("[1, 2, 3]")`, nested structures, Unicode, and
  `""`-is-not-`NULL` all pass.
- Zero-, one-, and many-document streams behave per the table.
- Every `cyaml_err_t` member maps to a stable `err$code`.
- A deliberate error raised mid-conversion leaks nothing under ASan.

---

## M3 — Hard cases

**Version 0.2.0.** Where the design's strictness claims get cashed.

- Big integers: the 32-bit / 2^53 / beyond ladder, `zuyaml_bigint` with decimal
  normalisation (hex and octal sources included), `format`/`print`/`as.character`/
  `as.numeric` methods, validating constructor, and all three `big_integers`
  policies.
- Duplicate keys: rejection by default, opt-in duplicate names, and the
  **stringification collision check** (`{1: a, "1": b}`). Note this is
  **zuyaml's own work, not a flag flip** — cyaml v0.1.3 advertises duplicate-key
  detection but never implements it (design §3.1), discovered in M2 when the
  option provably had no effect. Detection happens while building the name
  vector during mapping conversion.
- Collection-valued keys → `zuyaml_map`, two parallel lists.
- Aliases: traversal-time resolution with a cycle guard, plus `aliases = "error"`.
- Limits: `max_depth`, `max_size`, and `max_nodes` — including an actual
  billion-laughs fixture proving `max_nodes` stops it (design §11.1).
- The 4 GiB `uint32_t` ceiling check, and the embedded-NUL path
  (`key: "\0"` → `"embedded_nul"` condition, not an R internal error).

**Exit:** no silent semantic loss for any supported construct. Every row of the
lossy-conversion table (design §8) that concerns *parsing* has a test asserting
the documented behaviour.

**Risk:** `zuyaml_bigint` is public API the moment it ships. If open question §22.4
is going to be resolved as "no class in v1", decide it *here*, not at M7.

---

## M4 — Emitter

**Version 0.3.0.**

- Build `cyaml_doc_t` via `cyaml_doc_new()` and the `cyaml_new_*` constructors,
  preferring `cyaml_new_str(doc, s, len)` over `cyaml_new_cstr()`.
- The R → YAML type rules: scalars, atomic vectors, lists, empty containers,
  factors, and the error cases (partial names, duplicate names, `zuyaml_map`,
  data frames, unsupported S3/S4).
- **Scalar style selection (design §7.2).** The core-schema check that forces
  `CYAML_DOUBLE` for numeric-looking strings. This is not an optimisation or a
  polish item — without it `yaml_emit(list(x = "42"))` produces `x: 42` and the
  round-trip guarantee is false.
- `yaml_emit_all()`, joining documents with forced `---` markers rather than using
  `cyaml_stream_emit()`.
- Locale-independent double formatting with round-trip precision.
- Unwind safety on the emit path too: the `cyaml_doc_t` and the buffer from
  `cyaml_emit()`.

**Exit:**
- Documented supported R values pass semantic round-trip tests.
- The numeric-string regression suite passes: `"42"`, `".inf"`, `"0x1F"`,
  `"true"`, `"null"`, `""`, `"---"`, `"a: b"` all survive emit → parse unchanged.
- `indent`/`width` validated at 0, 255, 256.

---

## M5 — Files and integration

**Version 0.4.0.**

- `yaml_read()` / `yaml_read_all()` / `yaml_write()` / `yaml_write_all()`, all
  byte-oriented, with the file path threaded into parse errors.
- Raw-vector body tests standing in for `zuhttp` usage (design §19), confirming
  `zuyaml` needs no knowledge of HTTP objects.
- First pass at user documentation: roxygen for all eight functions, and a
  vignette covering the conversion rules and the lossy table.

**Exit:** `zuyaml` can be listed as a dependency by another package and used for
files and raw bodies without reaching into internals.

---

## M6 — Conformance and hardening

**Version 0.5.0.** The milestone that justifies the 1.0 promise.

- Curated yaml-test-suite subset in `tests/`, kept within reasonable CRAN time.
- Full upstream suite in CI, asserting valid-parses / invalid-errors and, for
  cases with `in.json`, matching the R object against the JSON-derived
  expectation (design §16.3).
- ASan and UBSan jobs.
- Wrapper-level fuzzing: arbitrary bytes into `yaml_parse()`, and deliberate
  fuzzing of the **error** paths and interrupt delivery, which is what actually
  exercises §9.3.
- Benchmarks against the `yaml` package, with the three-stage split
  (cyaml parse / R conversion / total) — this is what sets `max_nodes` and
  confirms the zero-copy scalar path was worth it.

**Exit:**
- Full suite green, with any deviations documented as known and intentional.
- Clean ASan/UBSan across the test suite and fuzz corpus.
- No leaks on repeated failure paths.
- Benchmark numbers recorded, and any performance claim in the README traceable
  to them.

---

## M7 — Freeze and release

**0.9.0 → 1.0.0.**

1. **Resolve every open question** in design §22 and record the decision. In
   particular `simplify`'s default and the fate of `zuyaml_bigint` — both are
   breaking changes after 1.0.
2. Tag `0.9.0` as a release candidate. Use it in a real project (`zuhttp` is the
   obvious candidate) before freezing.
3. Full documentation pass: every exported function, the conversion vignette, a
   README that describes the package rather than the `usethis` template.
4. `R CMD check --as-cran` clean on all platforms; win-builder and R-hub.
5. Run the `review-cran-submission` / `cran-extrachecks` passes: license and
   vendored-code notice, `inst/COPYRIGHTS`, URL validity, runnable examples,
   `\value` on every exported function.
6. Submit. Expect the vendored C to attract reviewer attention — have the
   provenance record and the assertion patch rationale ready to explain.
7. Tag `1.0.0` on acceptance.

**Exit:** on CRAN, with the six commitments at the top of this document held.

---

## Do these early even though they feel late

Three items are architectural, not polish. Deferring them to M6 means rewriting
code from M2 and M4:

| Item | Milestone | Why not later |
|---|---|---|
| Unwind safety (§9.3) | **M2** | Every `Rf_error()` added later is another leak site to retrofit |
| Emit style selection (§7.2) | **M4** | Round-trip tests written without it encode wrong expectations |
| `cyaml_version()` provenance test | **M1** | Cheap insurance against a silently botched re-vendor |

---

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **Upstream is pre-1.0** — 4 tags, ~57 commits | High | High | Vendoring pins us; but bug fixes mean re-vendor + re-verify + re-patch. Budget for it, and re-run the design's verification note each time. |
| CRAN objects to vendored `abort()`/`stderr` | Medium | High | The §13.2 patch is mandatory and permanent; test that it survives re-vendoring |
| Upstream API churn breaks the wrapper | Medium | Medium | The design's verification note lists exactly what to re-check |
| Deferred-feature files can't be dropped | Certain | Low | Accepted (design §13.1); be honest about size in the README |
| Windows toolchain and C11 | Low | Medium | Caught at M1, before anything is built on top |
| R conversion dominates parse time | Medium | Low | Zero-copy plain-scalar path from M2; measured at M6 |
| `zuyaml_map` / duplicate keys don't round-trip | Certain | Low | Documented asymmetry (design §8); reconsider at M7 whether they belong in 1.0 |

The first row is the strategic one. A 1.0 stability promise sits on top of a
library that has not made one. Vendoring is what makes that acceptable — the
version you shipped keeps working regardless of upstream — but it converts
"upstream fixed a bug" into a deliberate re-vendor, re-patch, and re-verify cycle
rather than a free upgrade. Plan for that to happen more than once before 1.0.

---

## Explicitly not in v1

Deferred with intent, each awaiting a real use case:

- The document API: `yaml_document()`, mutation, comment and style preservation,
  formatting-preserving round trips (design §20).
- YPATH querying — belongs with the document API, not the value parser.
- Streaming/SAX parsing — upstream does not expose a streaming parser, and
  `cyaml_events()` is not one (design §3.1).
- Emitting collection-valued or duplicate keys — blocked by
  `cyaml_map_set()`'s string-key, set-or-update signature.
- Schema validation, custom-tag handlers, data-frame conversion, `!!binary`,
  Date/POSIXct coercion.
- YAML 1.1 compatibility mode, via a future `version` argument if ever needed.

Each of these is a candidate for 1.x or 2.0. None is a reason to delay 1.0.
