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

**M0–M6 complete.** Parsing, emission, files, conformance, fuzzing and
benchmarks are done and on `develop`. `R CMD check --as-cran` is clean at one
NOTE (new submission); 2517 tests pass; R-CMD-check is green on macOS, Windows
and Ubuntu (release, devel, oldrel-1, clang).

What the milestones actually turned up, none of it predictable from the header:

| Found | Consequence |
|---|---|
| Three of five `cyaml_opts_t` fields are never read (`dup_keys`, `max_depth`, `max_size`) | zuyaml enforces all three itself (design §3.1, §11) |
| `cyaml_scalar_str()` truncates at an embedded NUL, silently | Raw span scanned before decoding |
| `cyaml_new_float()` formats with `%g` — six significant digits | zuyaml formats doubles itself |
| The emitter quotes plain `true`/`false`/`null`/`~`, so booleans emit as strings | Second vendored patch (`0002`) |
| The emitter never quotes numeric-looking strings | `resolves_as_non_string()` in the emit path |

Conformance: **333/333** agreement with the yaml-test-suite on valid-versus-
invalid, no crashes, no bare R errors escaping from C.

Benchmarks: parsing runs at **0.6–0.9×** the `yaml` package, emission at
**1.5–4×**, installed size 399 KB against 645 KB. R allocation dominates, not
parsing. No performance claim belongs in user-facing text.

Remaining: **M6.5** and **M7**. M6.5 is new and blocking — see the
comparative review below, which found two silent-data-loss defects that the
conformance and fuzz work did not.

---

## Comparative review — `yaml12` 0.2.0 (reviewed 2026-09-11)

Posit's [yaml12](https://posit-dev.github.io/r-yaml12/) 0.2.0 (CRAN
2026-08-25) is the only other YAML 1.2 parser for R: a Rust binding to
[saphyr](https://github.com/saphyr-rs/saphyr). Both packages were installed
into a scratch library and run side by side. What that produced is the source
for M6.5, M8 and M9 below.

**Syntax conformance is a tie.** Full upstream yaml-test-suite, 402 cases:
both are 402/402 (308/308 valid accepted, 94/94 invalid rejected). Core-schema
scalar resolution agrees on every probe — `yes`/`on` as strings, `0o14`,
`0x1A`, `.inf`/`.nan`, sexagesimal, `685_230.15`, timestamps uncoerced,
quoted `"42"` preserved. Neither implements `<<` merge keys (correct for 1.2);
neither preserves comments. On the 308 valid cases the two produce
semantically identical objects in 304; all four differences are `yaml12`
dropping map entries with non-string keys.

**So "YAML 1.2 support" does not separate them.** The differences are entirely
in R-level semantics, in the API, and in what each refuses.

Where zuyaml is ahead — each of these is a design claim, now evidenced against
a real alternative rather than against `yaml`:

| | zuyaml | yaml12 0.2.0 |
|---|---|---|
| 289-byte alias bomb | refused in 0.18 s (`max_nodes`) | expands to 48,427,560 leaves in 178 s |
| `max_size` / `max_depth` / `max_nodes` | all three | none; a hard-coded 256-level saphyr recursion cap only |
| `a: 1` / `a: 2` | error by default; `duplicate_keys = TRUE` keeps both | silently keeps the last |
| two null keys (`2JQS`), aliased duplicate key (`X38W`) | both entries kept | one entry silently dropped |
| `9007199254740993` | `zuyaml_bigint`, exact | `9.01e+15` |
| `[1, null, 3]` | `null` stays `NULL` | `c(1L, NA, 3L)` under the default `simplify = TRUE` |
| two-document stream, single-doc entry point | error naming `yaml_parse_all()` | returns document 1, no warning |
| errors | `zuyaml_parse_error` with `code`/`line`/`column`/`path` | `simpleError`; position only inside the message text |
| dependencies | bundled C11, 336 KB installed | Rust ≥ 1.71 to build, 1.2 MB installed |
| parse speed | 4.4 / 6.5 / 6.4 ms | 15.8 / 14.3 / 10.9 ms (nested map ×2000, int seq ×20000, string seq ×10000) |

The parse-speed result is worth recording because it contradicts the
expectation set by a Rust implementation: zuyaml is **2–3.5× faster** on these
three shapes. Emission is mixed — 6.7× *slower* on nested maps (33 ms vs 5 ms),
1.7× slower on integer sequences, 1.6× faster on string sequences. This does
not change the standing rule that no performance claim belongs in user-facing
text; it changes what is true if one ever does.

Where `yaml12` is ahead, and what M8/M9 answer:

| | yaml12 0.2.0 | zuyaml today |
|---|---|---|
| application tags | `yaml_tag` attribute; `%TAG` handles resolved to full URIs | discarded — `!duration 30` resolves as untagged `30L` |
| tag hooks | `handlers = list("!expr" = f)`, run per tagged node | none; `tags` is `"ignore"` or `"error"` |
| tag round-trip | `structure(x, yaml_tag = "!expr")` emits `!expr x` | tags dropped on emit |
| non-string keys | `yaml_keys` attribute, honoured by the writer | `zuyaml_map`, parse-only |
| multi-line strings | literal block `|`, round-trips | **folded to spaces — data loss (M6.5)** |
| `"  spaced  "` | quoted, round-trips | **emitted bare, reparses as `"spaced"` (M6.5)** |
| input | character vector, elements joined with newlines | single string or raw vector (raw is rejected by yaml12) |
| writer | `append = TRUE`, stdout by default | file path only |

One shared defect: neither strips a UTF-8 BOM, so it becomes part of the first
key name. Both are wrong per spec.

---

## Sequence

| # | Milestone | Version | Effort | Gate |
|---|---|---|---|---|
| M0 ✅ | Metadata and hygiene | — | S | Skeleton is a real package, not a template |
| M1 ✅ | Vendored build | 0.0.1 | M | Compiles clean on 3 platforms |
| M2 ✅ | Parser core | 0.1.0 | L | Representative YAML 1.2 → R, safely |
| M3 ✅ | Hard cases | 0.2.0 | L | No silent semantic loss |
| M4 ✅ | Emitter | 0.3.0 | L | Round trips hold, including numeric strings |
| M5 ✅ | Files and integration | 0.4.0 | S | Usable as a dependency |
| M6 ◐ | Conformance and hardening | 0.5.0 | L | Demonstrably robust |
| M6.5 | Byte and round-trip correctness | 0.2.0 | M | No silent loss on emit or on NUL |
| M6.6 | Conformance harness | 0.2.0 | S | The corpus asserts round-trip identity |
| M7 | Freeze and release | → 1.0.0 | M | CRAN-accepted, API committed |
| M8 | Tag interoperation | 1.1.0 | M | Tags survive a round trip; hooks exist |
| M9 | Key and style fidelity | 1.2.0 | L | `zuyaml_map` emits; block styles chosen |

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

**Reopened at M6.5.** The embedded-NUL criterion above is only half met. The
*escape* path is correct — `a: "x\0y"` raises `embedded_nul` as designed. A
**literal** NUL byte in the input is not caught at all, because cyaml ends the
document there before `check_no_nul()` in `zuyaml_convert.c` is handed a span
to check. `a: 1\nb: x<NUL>y\nc: 3\n` returns `a` and `b = "x"`; `c`
disappears without a condition.

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

**Reopened at M6.5.** The round-trip criterion above is false as shipped. The
regression suite covers the cases §7.2 named — numeric-looking strings,
`".inf"`, `"true"`, `"---"` — and those pass. It contains no string with a
newline or with leading or trailing whitespace, and every such string is
corrupted on emit. See M6.5.

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
- ✅ Full suite green, with any deviations documented as known and intentional.
  333/333 agreement on valid-versus-invalid, no crashes, no bare R errors.
- ❌ **Clean ASan/UBSan across the test suite and fuzz corpus.** Not yet
  demonstrated. The sanitizer jobs failed on their first line for two runs
  (`set -o pipefail` is not available in the containers' `sh`), so they had
  never executed a single test. Fixed; awaiting a green run.
- ✅ No leaks on repeated failure paths — as far as a plain R heap check can
  show. The real evidence is the ASan run above, so this is provisional.
- ✅ Benchmark numbers recorded; no performance claim is made anywhere.
- ✅ **Semantic conformance.** Implemented. Parsed objects are compared against
  the suite's `in.json` rendering: **970 of 990** single-document cases agree,
  and every remaining difference is listed with a reason. It found three real
  conversion bugs the accept/reject tests could not: unfolded multi-line plain
  scalars, empty block scalars returning `NULL`, and an alias used as a mapping
  key collapsing the whole mapping into a `zuyaml_map`.

  Agreement is now **977 of 990**. Not compared: multi-document cases, whose
  `in.json` concatenates one value per document and needs an incremental parser
  to split, and number typing and key order, which JSON cannot represent. One
  known difference remains: collection-valued keys, where JSON flattens what
  `zuyaml_map` preserves.

---

## M6.5 — Byte and round-trip correctness

**Version 0.2.0. Blocking 1.0.** Two silent-data-loss defects, found by
differential testing against `yaml12` rather than by the conformance suite or
the fuzzer. Both contradict the package's central claim, so neither can be
carried into a stability promise.

### 1. The emitter destroys strings containing newlines or edge whitespace

`yaml_emit()` round-trips are not what M4 asserts:

| input | emitted | reparses as |
|---|---|---|
| `"line one\nline two\n"` | `txt: line one line two` | `"line one line two"` |
| `"a\nb"` | `a b` | `"a b"` |
| `"  spaced  "` | `a:   spaced  ` | `"spaced"` |
| `"x\n"` | `a: x ` | `"x"` |
| `"a\rb"` | `a b` | `"a b"` |
| `"\tbar"` | `a: \tbar` | `"bar"` |
| `"bar\t"` | `a: bar\t` | `"bar"` |

Width-independent: `width = 0`, `20` and `200` all fold. `yaml12` gets every
one of these right, using a literal block.

**Cause.** `resolves_as_non_string()` in `zuyaml_emit.c` deliberately closes
"only the numeric gap" and leaves the rest to cyaml's `needs_quoting_ex()`,
which promotes on indicators, document markers, trailing colons and the
reserved words — and performs no whitespace test whatsoever. This is the same
class of defect as the numeric gap the function was written to close, with one
case left open. The comment in that function should be corrected too: it
currently reads as though upstream handles everything else, which is what made
the gap invisible.

**Fix.** Force a non-plain style when the text contains `\n` or `\r`, or
begins or ends with **whitespace — space or tab**. A tab is easy to overlook
here: `"a\tb"` survives, but `"\tbar"` and `"bar\t"` are both stripped back to
`"bar"`. Use `CYAML_DOUBLE`: a double-quoted scalar
escapes newlines and preserves edge spaces, so it round-trips unconditionally
and needs no chomping or indentation-indicator logic — precisely the machinery
cyaml's emitter is least reliable at. A literal block (`|`, `|-`, `|+`) reads
better for genuinely multi-line text and is a **readability** follow-up for M9,
not part of the correctness fix.

**Scale.** Not a corner case. Running parse → emit → parse over the upstream
suite: of the 308 valid cases, 280 emit (28 are deliberate refusals) and
**70 of those 280 — 25% — come back as different values.** 66 are strings
containing a newline; the rest are edge whitespace. The suite is full of block
scalars and multi-line plain scalars, so it was always going to find this.

**Exit:** an emit → parse identity assertion added to the existing conformance
loop (see M6.6), plus a property-based test over generated strings covering
embedded newlines, CR, CRLF, leading and trailing spaces *and tabs*, a trailing
newline, and a string that is only whitespace. The gap existed because the M4
suite enumerated cases from §7.2 by hand; the replacement must be a property,
not another hand-written list.

### 2. A literal NUL byte truncates the document silently

`check_no_nul()` catches a NUL produced by a `\0` **escape**, which is what it
was written for. It never sees a literal NUL byte in the input: cyaml treats it
as end-of-input, so the scalar span is already cut and everything after it is
gone.

```
a: 1\nb: x<NUL>y\nc: 3\n   ->   $a 1, $b "x"     # c vanishes, no condition
```

**Fix.** Pre-scan the input buffer in `zuyaml_parse.c` before handing it to
cyaml and raise `embedded_nul`, alongside the `max_size` length check that
already walks the input. Refusing is right: the alternative is a document
whose tail was discarded without a word.

**Exit:** a literal NUL anywhere in the input — in a key, in a value, inside a
block scalar, or between documents in a stream — raises `embedded_nul` with a
line and column, and never returns a truncated object.

### 3. Strip the UTF-8 BOM

`\xEF\xBB\xBF` currently becomes part of the first key name. `yaml12` has the
identical bug, so this is not competitive pressure, just a spec conformance
point that is cheap alongside the NUL pre-scan. The BOM is permitted at the
start of a stream and must not reach the document.

**Exit:** a BOM-prefixed document parses identically to the same document
without one.

---

## M6.6 — Conformance harness

**Version 0.2.0, with M6.5.** M6.5 is the defect; this is the reason it
survived. The corpus was already in the repository and already being iterated
over — what was missing was the assertion.

**Which suite artifact pins which boundary.** The wrapper sits between two
conversions, and the suite ships a different reference for each:

| artifact | present | pins | whose defect | status |
|---|---|---|---|---|
| `error` marker | 94 | text → accept/reject | cyaml's, but the wrapper must not alter the verdict | covered, `test-conformance.R` |
| `test.event` | 402 | text → event stream, **and the tag set** | cyaml's for events; **zuyaml's for tags** | unused — justified today, **wrong from M8** |
| `in.json` | 282 | text → R *value* | **zuyaml's** (`zuyaml_convert.c`) | covered, `test-conformance-semantic.R` |
| `out.yaml` | 249 | text → normalised text | cyaml's emitter | **correctly unused** — see below |
| *(none needed)* | — | R value → text → R value | **zuyaml's** (`zuyaml_emit.c`) | **the gap** |

`test.event` was dismissed too quickly. As an event stream it is cyaml's
business and zuyaml has no event API to compare against — that part holds. But
`yaml12` extracts the `<tag:...>` tokens from it, subtracts the seven core
tags, and asserts that the tags it preserved match exactly. That turns
`test.event` into a ready-made, external reference for tag handling, needing no
event API at all. zuyaml cannot use it today because it discards application
tags — but it is precisely the oracle M8 needs, already in the repository. See
M8's exit criteria.

`out.yaml` is deliberately not adopted. It is the suite's own re-serialisation,
and it encodes block-versus-flow and quoting choices the package explicitly
does not commit to ("emission favours readable YAML over reproducing any
particular source formatting", `vignette("zuyaml")`). Diffing text against it
would fail on style constantly and on meaning never. The emitter needs a
*property*, not a reference file.

- **Add the round-trip assertion to `tests/`.** The existing "anything that
  parses can be emitted or refused deliberately" test in `test-conformance.R`
  already parses, already emits, and already tolerates deliberate refusal. It
  stops one call short: it never reparses. Adding
  `identical(docs, yaml_parse_all(yaml_emit_all(docs)))` fails 70 cases today.
  This stays in `testthat` — it is fast, deterministic, offline, and needs no
  extra dependency.
- **Compare multi-document cases too.** `test-conformance-semantic.R` skips any
  case where `length(docs) != 1`, because a stream's `in.json` concatenates one
  value per document. That is **23 of the 279** cases with a reference, and
  streams are a construct the package makes a point of handling. Splitting
  concatenated JSON needs an incremental reader, which is why it was deferred —
  but `yaml12` has a working dependency-free one: try `read_json` on the whole
  file, and on failure accumulate lines one at a time, retrying `parse_json`
  after each and resetting the buffer whenever it succeeds. Crude, but it needs
  nothing `Suggests` does not already have.
- **Add `tools/conformance.R`** for what cannot live in `tests/`: the full
  upstream checkout rather than the curated subset, the differential run against
  another implementation, and a report with a drift baseline. Model it on
  `zujson`'s `tools/jsontestsuite.R` in *shape* — counts, named failures, a
  pinned baseline, `exit(1)` — not in content, since the accept/reject half is
  already covered here and JSONTestSuite has no value references to compare.
- **Assert unwind safety from R.** `yaml12`'s `test-unwind-safety.R` is the
  most transferable thing in their suite, and none of it needs their handler
  feature. Two patterns:
  - **Poisoning loops.** Drive an error path 25 times, then assert an ordinary
    parse still works. This catches leaked `longjmp` state and half-freed
    parsers with no sanitizer, no CI container, and no network — it runs
    everywhere, including on CRAN. zuyaml has at least eight such paths
    (duplicate key, `max_nodes`, `max_depth`, `unsupported_tag`, alias cycle,
    syntax, `embedded_nul`, emit refusal). All eight pass today; **nothing
    asserts that they keep passing**, and §9.3 is the design's riskiest claim.
  - **`gctorture(TRUE)`** around conversion, error and emit paths. This is the
    runtime counterpart to rchk, and rchk is the only thing that ever found the
    `build_node()` PROTECT bug — 2,517 tests, 15,000 fuzz iterations and
    valgrind all missed it. `gctorture` needs no special toolchain.

  Both matter more after M6.5 and M8 than before: M6.5 rewrites the emit style
  path, and M8 introduces R code called *from* C, which is exactly the hazard
  §9.3 exists for. Adopt `yaml12`'s whole nested-handler battery at M8 — by
  then it tests the same construct in both packages.
- **Pin two things that currently work by accident.**
  - **Format specifiers stay literal.** `zuyaml_stopf()` is printf-shaped and
    interpolates user text — a path, a tag name, a duplicate key. A `%s` or
    `%n` arriving as the *format* rather than an argument is a crash. All three
    paths are correct today; none is tested.
  - **`R_forceSymbols(TRUE)` holds.** `.Call("zuyaml_parse_", ...)` is rejected
    by name, as M1 intended. One line to assert, and it silently regresses if
    `init.c` is ever regenerated.

**Also not adopted: one `test_that()` per case.** `yaml12` generates a test
per suite case in a top-level `for` loop, which names failures nicely; zuyaml
accumulates into a character vector and reports once with `info`. Either works.
Do not copy their version literally, though — the test name uses `title_text`,
which is only assigned inside `if (file.exists(title_path))`, so a case without
a `===` file silently inherits the previous iteration's title. `describe_case()`
already handles that correctly.

**Not adopted: snapshot tests.** `yaml12` keeps `_snaps/*.md` of error message
text. zuyaml deliberately went the other way — stable `code`, `line` and
`column` fields so callers never match on prose (design §10) — and that is the
better contract. Snapshots would re-couple the tests to wording the package
promises nothing about. Recording the rejection so it is not revisited by
default.

**Exit:** round-trip identity holds over the whole suite, or each exception is
listed with a reason in the same style as `expected_mismatch`; multi-document
cases are compared; error paths assert health after repetition and under
`gctorture`; `tools/conformance.R` runs against a full checkout and reports.

**Note for the risk register.** Differential testing against `yaml12` found in
minutes what 2,517 tests, 15,000 fuzz iterations and a 402-case corpus did not.
The corpus was never the weak part — the assertions over it were.

---

## M7 — Freeze and release

**0.1.0 → 1.0.0.**

0. **M6.5 must be closed first.** Both of its defects are silent data loss in
   the emit and parse paths; commitment 2 of this document ("the documented
   conversion rules are stable") cannot be made while the documented rules and
   the behaviour disagree.
1. **Resolve every open question** in design §22 and record the decision.
   `simplify` (kept `FALSE`) and `max_nodes` (lowered to `1e6`) are settled.
   Still open: key stringification, the eight-versus-five function count, and
   whether `zuyaml_bigint` and `zuyaml_map` belong in 1.0 — all breaking
   changes afterwards.

   The `yaml12` review supplies evidence for §22.4 that did not exist when the
   question was written. It represents non-string keys as a `yaml_keys`
   *attribute* on an ordinary list rather than as a class, which keeps the
   common path a plain list and lets the writer honour it — see M9. That is a
   real alternative to `zuyaml_map`, and it is the direction that makes
   emitting possible at all. Decide §22.4 against it rather than in the
   abstract.

   **The freeze is deliberately deferred.** The package ships as 0.1.0 with the
   API explicitly unfrozen. The per-milestone version numbers elsewhere in this
   document were planning fiction: the first release is 0.1.0, and 1.0.0 comes
   only after the questions above are answered and the package has been used on
   something real.
2. **Populate `conditionCall()`.** Every zuyaml condition carries a `call`
   slot and every one of them is `NULL` — hardcoded in both layers, at
   `R/conditions.R:21` and `src/zuyaml_error.c:55`. The effect is that a
   failure prints as `Error: YAML parse error at line 2, column 1: ...` rather
   than `Error in yaml_parse(config) : ...`, so in a script with a dozen parse
   calls nothing says which one failed. `path` covers that for `yaml_read()`;
   an inline `yaml_parse()` has nothing. `yaml12` returns the public wrapper
   call and reads better for it.

   This belongs at the freeze rather than after it. Populating the slot is
   backward compatible — handlers that ignore `call` are unaffected — but the
   condition object is part of the stability promise, and "the field exists and
   is always empty" is not a shape to commit to for a major version.

   Two constraints. The call must be the **public wrapper** (`yaml_parse(x)`),
   not the internal `.Call`, which means threading `sys.call()` down rather
   than deriving it in C. And the R and C layers must stay shape-identical —
   `R/conditions.R` says so explicitly, and it is the reason a caller can
   handle errors from either layer the same way. Test both origins: a
   validation error raised in R and a parse error raised in C.

3. Use 0.1.0 in a real project (`zuhttp` is the obvious candidate) before
   freezing anything.
4. Full documentation pass: every exported function, the conversion vignette, a
   README that describes the package rather than the `usethis` template.
5. `R CMD check --as-cran` clean on all platforms; win-builder and R-hub.
6. Run the `review-cran-submission` / `cran-extrachecks` passes: license and
   vendored-code notice, `inst/COPYRIGHTS`, URL validity, runnable examples,
   `\value` on every exported function.
7. Submit. Expect the vendored C to attract reviewer attention — have the
   provenance record and the assertion patch rationale ready to explain.
8. Tag `1.0.0` on acceptance.

**Exit:** on CRAN, with the six commitments at the top of this document held.

---

## M8 — Tag interoperation

**Version 1.1.0. Post-1.0, additive.** The one capability gap the `yaml12`
review found where zuyaml has no answer at all, rather than a stricter answer.

Today `tags` is a two-position switch: `"ignore"` discards the tag and resolves
the node as though it were untagged, so `!duration 30` is indistinguishable
from `30`; `"error"` refuses the document. Neither lets a caller *use* a tag.
Application tags are how YAML is extended, and refusing to carry them makes
zuyaml unusable for any format that has its own vocabulary.

- **Preserve tags.** A third `tags` value — `"keep"` — attaching the resolved
  tag to the value. Resolve `%TAG` handles to the full URI, as `yaml12` does
  (`!e!gizmo` → `tag:example.com,2024:gizmo`): the shorthand is
  document-local and meaningless once the document is gone.
- **Hooks.** A `handlers` argument: a named list of functions keyed by tag,
  called with the node's converted value. Follow `yaml12`'s shape here, not a
  novel one — two packages with gratuitously different handler protocols helps
  nobody, and theirs is the one already on CRAN.
- **Decide the representation deliberately.** An attribute (`yaml_tag`, as
  `yaml12` does) keeps the common path a plain vector and is what M9 needs in
  order to emit. A class is more R-idiomatic but multiplies method surface and
  fights `simplify`. This is the same trade-off as §22.4 and should be settled
  the same way, at the same time.
- **Keep the security posture.** Handlers run arbitrary R code during parsing,
  which is exactly what `max_nodes` and the rest exist to prevent from being
  automatic. So: no handler runs unless the caller passed one, `"ignore"` stays
  the default, and a handler's error propagates as a zuyaml condition carrying
  the node's line and column rather than escaping raw. Note plainly in the docs
  that `handlers` is an execution surface — an `!expr` handler on untrusted
  input is arbitrary code execution, and that is the caller's decision to make
  knowingly.

**Exit:** `!duration 30` survives parse → emit unchanged with `tags = "keep"`;
a handler receives the value and its result replaces the node; core schema tags
continue to override resolution exactly as they do now; the default behaviour
of every existing call is unchanged. **Verified against `test.event`**, not
against hand-written expectations: extract the `<tag:...>` tokens from each
case, subtract the seven core tags, and assert the preserved tag set matches —
the suite already ships this oracle for all 402 cases (see M6.6). Bring over
`yaml12`'s nested-handler unwind battery at the same time; once handlers exist,
it tests the same construct in both packages.

---

## M9 — Key and style fidelity

**Version 1.2.0. Post-1.0.** Two asymmetries the design accepted knowingly
(§8) and one readability item deferred from M6.5. Grouped because they share a
blocker.

- **Emit non-string keys.** `zuyaml_map` is parse-only, so a document with a
  sequence key cannot be written back. The obstruction is real and structural:
  `cyaml_map_set()` takes a string key and has set-or-update semantics, so
  neither a collection key nor a duplicate key can be expressed through it.
  Needs either a patch adding a node-keyed setter, an upstream change, or
  building the mapping node directly. Cost this before committing — it may be
  the largest single item left, and it is why §22.4 should be decided first.
- **Emit duplicate keys.** Same blocker. `duplicate_keys = TRUE` parses to
  duplicate names that cannot be written back out.
- **Literal block scalars.** The readability half of M6.5's fix: multi-line
  strings emitted as `|` rather than as a double-quoted escape. Requires
  correct chomping (`|`, `|-`, `|+`) and an indentation indicator when a line
  begins with whitespace — the cases cyaml's emitter is least trustworthy on,
  which is why correctness lands first and separately. Every change here must
  keep the M6.5 property test green.

**Exit:** every construct zuyaml parses, it can also emit, or the refusal is
documented and raises a condition naming the reason rather than silently
altering the data.

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
| `zuyaml_map` / duplicate keys don't round-trip | Certain | Low | Documented asymmetry (design §8); reconsider at M7 whether they belong in 1.0; scheduled at M9 |
| **Hand-enumerated test corpora hide whole categories** | Certain | High | The emitter gap survived 2517 tests, 15,000 fuzz iterations and a 402-case suite because every corpus was written from the same list of cases the code was written from. M6.5's exit requires property-based round-trip tests; prefer differential testing against another implementation over extending a list |
| Handlers (M8) become an arbitrary-code-execution surface | Medium | High | Opt-in only, never default; documented as such; handler errors surface as zuyaml conditions with position |
| `yaml12` closes the strictness gap | Medium | Medium | Its defaults (silent duplicate-key loss, unbounded alias expansion, `simplify = TRUE`) are design choices, not oversights; zuyaml's differentiation is the opposite choice, not a lead to protect |

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
  `cyaml_map_set()`'s string-key, set-or-update signature. **Now scheduled:
  M9.**
- Custom-tag handlers and tag preservation. **Now scheduled: M8** — the
  `yaml12` review supplied the missing use case, which is that this is the
  only gap where a competing package can do something zuyaml cannot do at all.
- Schema validation, data-frame conversion, `!!binary`, Date/POSIXct coercion.
- YAML 1.1 compatibility mode, via a future `version` argument if ever needed.

Each of these is a candidate for 1.x or 2.0. None is a reason to delay 1.0.
