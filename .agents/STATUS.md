# zuyaml — status

Written 2026-09-08, at version 0.1.0, 25 commits on `develop`.
Revised 2026-09-11 after a differential review against `yaml12` 0.2.0, which
found two silent-data-loss defects in this package and the testing gap that let
them through. Both were staged as M6.5.
Revised again 2026-09-14: **M6.5 and M6.6 are done.** Both defects are fixed,
the assertion that would have caught them exists, and closing them turned up
three more of the same family that the review had not seen.

Companion to [DESIGN-zuyaml.md](DESIGN-zuyaml.md) (what to build) and
[ROADMAP.md](ROADMAP.md) (in what order). This says **where it actually is**,
including what is not done and what has been claimed but not demonstrated.

---

## Short answer

M0–M6.6 are complete. M4's round-trip criterion and M3's embedded-NUL criterion,
both found false on 2026-09-11, now hold and are asserted. **M7 is what is
left**, and it is mostly decisions rather than code: three API questions, a
`conditionCall()`, and a release.

The testing gap is closed at the boundary that broke. The corpus was never the
weak part — the assertions over it were — so the round trip is now checked by
reparsing what the emitter produced for every case in the suite, by generated
strings, and by every one- and two-character string over the indicator
alphabet.

| | |
|---|---|
| Version | 0.1.0 — API complete, deliberately **not frozen** |
| Exports | 9 — eight API functions plus `zuyaml_bigint()` |
| Code | 543 lines R, 2,202 lines C, plus 14,512 lines vendored cyaml |
| Tests | 2,972 assertions across 16 files, plus 84 conformance fixtures |
| `R CMD check --as-cran` | 0 errors, 0 warnings, 1 NOTE (new submission) |
| ASan + UBSan | **clean** — first observed green run, 2026-09-14; see below |
| Vendored patches | 5, all mandatory and documented |
| Known defects | **none** |
| Numeric policy | aligned with `zujson` — generous about numbers, strict about text |

---

## What the checks say

| Check | Result |
|---|---|
| R-CMD-check — macOS, Windows, Ubuntu (release/oldrel-1) | pass |
| R-CMD-check — CRAN-like containers `clang23`, `ubuntu-clang`, `ubuntu-gcc16` | new on 2026-09-16, first run pending — these replace the old Ubuntu-Clang row, which ran a compiler several majors behind CRAN's |
| yaml-test-suite, all 355 cases | pass — 333/333 agreement on valid vs invalid |
| yaml-test-suite, full re-run 2026-09-14 (402 cases) | pass — 402/402 on valid vs invalid |
| yaml-test-suite — semantics against `in.json` | 278/279, the one difference being `WZ62` and deliberate |
| yaml-test-suite — **emit → parse round trip** | **280/280** — was 210/280 |
| Differential review vs `yaml12` 0.2.0 | found two defects; both fixed, both now asserted |
| Property tests — generated strings, all 1- and 2-character indicator strings | pass; **found three further defects the review missed** |
| Numeric extremes vs `zujson`'s stated rule | pass, **after fixing a fifth defect it found** |
| Fuzzing — random bytes, syntax fragments, truncation | pass at 15,000 iterations each |
| valgrind, LTO, `gctorture`, **rchk** | pass — now automatic on every push via `native-checks.yaml`, not a manual R-hub dispatch |
| R-hub — nold, and the on-demand flavours | pass; `c23`, `intel` and `noremap` were run on 2026-09-08 and are since **deprecated upstream** |
| **ASan + UBSan** | **clean**, 2026-09-14 — the whole test suite and the full corpus |
| Unwind safety — 8 poisoning loops, `gctorture` | pass, and now asserted |
| CI arrangement | the generic native checks moved to `pedrobtz/r-actions@v1`; `hardening.yaml` keeps only what is specific to this package |
| win-builder devel + release | submitted; results go to the maintainer by email |

### rchk found a PROTECT error

```
Function build_node
  [UP] calling allocating function build_map with a fresh pointer (names <arg 3>)
       src/zuyaml_emit.c:426
```

`build_node()` fetched the names attribute with `Rf_getAttrib()` and passed it
unprotected into `build_map()`, which allocates. `Rf_getAttrib()` can allocate,
so its result must not be assumed reachable. Almost certainly benign in
practice — `x` is protected by the caller and the attribute hangs off it — but
the pattern is unsafe and is now fixed.

**Nothing else caught it.** Not 2,517 tests, not 15,000 fuzz iterations, not
valgrind. Static analysis aimed at exactly this hazard did. That is the
argument for keeping rchk in the platform set permanently.

### ASan and UBSan: a green run, at last

Three consecutive CI attempts had failed before executing a single test:

1. Backslash line continuations inside a YAML `run:` block are literal text,
   not shell continuations, so R received invalid input.
2. `set -o pipefail` is not available in the containers' `sh`.
3. Under `sh -e`, a failing `Rscript` aborts the step before `cat
   sanitizer.log`, so the output was swallowed.

All three were fixed but never observed working. On 2026-09-14 the package was
built with `-fsanitize=address,undefined` and run clean, with no diagnostic of
any kind:

| Run | Result |
|---|---|
| `tools/sanitizer-exercise.R`, full 402-case corpus | 66 checks, 0 failures |
| the whole `testthat` suite, full corpus | 2,972 assertions, 0 failures |

**Two things had to be got right before that meant anything**, and the first
attempt got neither:

1. **The build was not instrumented.** `R CMD INSTALL .` reuses any `src/*.o`
   newer than its `.c`, and `pkgload::load_all()` had left a full set there, so
   the sanitizer flags reached only the link step. The check that settles it is
   `nm -u .../zuyaml.so | grep -c asan` — 0 for the first build, 36 for the
   real one, and the file doubles in size. **`find src -name '*.o' -delete`
   first.** This is the same stale-object trap as the benchmark one below; it
   bit twice in one session, in two different disguises.
2. **ASan interceptors were not installed.** R `dlopen`s the shared object, so
   the runtime loads too late, and ASan says so. macOS strips `DYLD_*` from
   anything launched through `/bin/sh`, which includes the `R` and `Rscript`
   wrappers. Running `$(R RHOME)/bin/exec/R` directly with
   `DYLD_INSERT_LIBRARIES` set is what makes it work. Without this the run is
   silently weaker than it looks — instrumentation still fires on globals and
   stack, but nothing watches the heap.

A green sanitizer run that has not had both of these checked is not evidence.

**The CI job was green all along.** This section previously said a green run
had never been observed. That was written from the failures of 2026-09-08 and
never rechecked: `hardening.yaml` has run `clang-asan`, `clang-ubsan` and
`gcc-asan` to success on **every** run since 2026-09-08, including the
scheduled run of 2026-09-14, and its log shows the package compiled with
`-fsanitize=address,undefined` across all 15 C files. Those containers are the
stronger check — `clang-asan` ships an R that is itself instrumented, so ASan
watches the interpreter's allocations too. **Check the run list before writing
that something has never worked.**

The local run adds one thing the CI job does not have: the `nm` verification.
Its limits are macOS with Apple clang and an uninstrumented R, so ASan sees the
package's allocations and not R's. Between the two, the unwind paths — the
design's riskiest claim — hold under a sanitizer that is genuinely watching
them, on two toolchains.

---

## What the yaml12 review found

`yaml12` 0.2.0 is the only other YAML 1.2 parser for R. Running the two side by
side over the full upstream suite took minutes and found what the whole existing
check set could not. Recorded here because the *method* is the lesson, not the
comparison: every corpus in this package was enumerated from the same list of
cases the code was written from, so all of them share its blind spots.

Syntax conformance is a tie — both 402/402 — and on the 308 valid cases the two
produce semantically identical objects in 304, the four differences all being
`yaml12` dropping map entries. Nothing separates the packages on YAML 1.2
coverage. What the comparison surfaced was two defects here.

**1. The emitter destroys strings with newlines or edge whitespace.**

| input | emitted | reparses as |
|---|---|---|
| `"a\nb"` | `a b` | `"a b"` |
| `"  spaced  "` | `a:   spaced  ` | `"spaced"` |
| `"\tbar"` | `a: \tbar` | `"bar"` |

Width-independent. `resolves_as_non_string()` in `zuyaml_emit.c` closes "only
the numeric gap" and leaves the rest to cyaml's `needs_quoting_ex()`, which
performs no whitespace test at all — the same class of defect the function was
written to close, with one case left open. Of the 280 suite documents that
emit, **70 change value**. A tab is easy to miss: `"a\tb"` survives, `"\tbar"`
does not.

**2. A literal NUL byte truncates the document silently.** `check_no_nul()`
catches a NUL produced by a `\0` escape, which is what it was written for, but
never sees a literal one — cyaml treats it as end-of-input, so the span is
already cut before the guard is handed anything.

```
a: 1\nb: x<NUL>y\nc: 3\n   ->   $a 1, $b "x"     # c vanishes, no condition
```

**What did not break.** Probed with `yaml12`'s own techniques and all clean:
format specifiers stay literal when a `%s` or `%n` arrives inside a path, a tag
name or a duplicate key; eight error paths driven 25 times each leave the
parser healthy; conversion, error and emit paths are clean under
`gctorture(TRUE)`. None of these was *asserted* anywhere, which was the point —
they passed by construction, not by test. `test-unwind-safety.R` now pins all
of them.

---

## What fixing it found (2026-09-14)

Worth its own section, because the lesson repeats: **the review's diagnosis was
right about the symptom and wrong about the cause, and the property tests found
three more defects of the same family that the differential comparison had not
reached.**

### The cause was one level deeper than the review said

The review blamed `resolves_as_non_string()` for leaving the whitespace gap
open, and it does. But marking those strings `CYAML_DOUBLE` fixes edge
whitespace and **does nothing at all for line breaks**, which was 66 of the 70
failing documents. `cyaml_scalar_str()` re-reads a node's span as YAML *source*
— folding breaks into spaces, dropping whitespace before a break — which is
right for a parsed document and wrong for a built one, where the span is the
literal string the caller supplied. The emitter calls it **before** deciding a
style, so the break was gone before any rule could see it. No caller-side
choice could have fixed it; vendored patch `0005-scalar-str-built-verbatim`
does, by returning the span verbatim when `doc->mode == CYAML_BUILDING`.

The roadmap's fix was written from the same reading of the code that produced
the bug. Testing the fix, rather than reasoning about it, is what separated them.

### Three more defects, none of them in the review

| Defect | Found by | Effect |
|---|---|---|
| A whole-numbered double emits as `450`, which the core schema resolves as an **integer** | the round-trip assertion over the suite — case `UGM3`, the spec's own invoice example, `price: 450.00` | type changes on every round trip of an integral double |
| Mapping **keys** are never style-checked: `cyaml_map_set()` builds the key node itself and leaves it plain | generated strings, used as keys | `list("  x  " = 1)` came back as `list(x = 1)`; a key spelled `null` turned the whole mapping into an unemittable `zuyaml_map` |
| A scalar that is exactly `-` or `?` emits unquoted | exhaustive one- and two-character strings | `k: ?` **does not parse at all** — the emitter produced an invalid document |

All three are the same shape as the original: a rule that asks "would this
resolve as another type?" but not "would this survive at all?", applied in one
place and not the other. The fix applies the *same* predicate to keys and
values rather than a narrower one for keys — two rules where one will do is how
the first gap stayed open.

### And one documented behaviour that was not being honoured

`NULL` and `NA` emitted as `x:` — an empty value — rather than `x: null`, which
is what the design says. It reparses correctly, so it is not a loss, but it is
exactly the shape a truncated document has. Now an explicit `null`.

---

## Aligning numeric handling with `zujson`

Prompted by `zujson`'s testing article, which states the numeric rule as
**"generous about numbers, strict about text"**. Checking zuyaml against it
found a fifth defect of the same family as the emitter ones, and one testing
practice worth copying outright.

### A float out of range became a *character string*

`cyaml_str_to_f64()` treats a non-zero `errno` as failure, and `strtod()` sets
`ERANGE` for overflow, for underflow to zero, **and** for any subnormal result.
All three fell through to zuyaml's string fallback:

| text | was | now |
|---|---|---|
| `1e309` | `"1e309"` (character) | `Inf` |
| `-1e309` | `"-1e309"` | `-Inf` |
| `1e-324` | `"1e-324"` | `0` |
| `1e-323` | `"1e-323"` — **and this one is representable** | `9.88e-324` |

The severity is not "one absurd number fails a document", which is what the
rule is usually defended against. It is worse and quieter: `timeout: 1e308`
gave a double and `timeout: 1e309` gave a string, so **the R type of a field
depended on the magnitude of its value** — the thing `simplify = FALSE` exists
to prevent, arriving by another route. Fixed caller-side in `scalar_double()`,
because `ERANGE` is exactly the case where C guarantees the nearest value;
upstream's rule is a fifth bug worth reporting.

Text that is not a number is untouched: `!!float abc` is still `"abc"`.

### Where the two packages stay different, deliberately

An integer beyond 2^53 is a `zuyaml_bigint` here and the nearest double in
`zujson`. Not an oversight — the medium differs. `zujson` reads HTTP bodies,
where a wide integer is usually an identifier and a double carries it fine;
YAML is hand-written configuration, where a silently rounded integer is a wrong
number in a file someone will diff. `big_integers = "double"` is `zujson`'s
answer in one argument. Whether the default should change is design §22's open
question, not a defect.

### The testing practice: bit patterns, never R literals

`zujson` records that R's string-to-double conversion accumulates through
`LDOUBLE`, which on `aarch64` is plain `double`, so R's reader is not correctly
rounded. This machine reproduces it, and worse than their example:

| token | zuyaml (correctly rounded) | `as.numeric()` |
|---|---|---|
| `1e308` | `0x7fe1ccf385ebc8a0` | `0x7fe1ccf385ebc8a3` |
| `1e300` | `0x7e37e43c8800759c` | `0x7e37e43c880075a0` |
| `2.2250738585072014e-308` | `0x0010000000000000` (`DBL_MIN`) | `0x000ffffffffffffc` |
| `1.7976931348623157e308` | `0x7fefffffffffffff` (`DBL_MAX`) | `0x7ff0000000000000` — **`Inf`** |

R's reader overflows on `DBL_MAX` written out in full, which is the canonical
round-trip literal. An R *hex* literal is no escape either: `0x1p-1074` reads
as `0` in R source. Numeric expectations are now written as IEEE-754 bit
patterns through `readBin()` (`tests/testthat/helper-doubles.R`). The first
attempt at these tests was written the obvious way and failed — against a
reference that was itself wrong, which is precisely the trap the article
describes.

---

## What upstream actually does

Every one of these was found by testing behaviour, not by reading the header or
the README. This is why the design's verification note now insists on grepping
the implementation and writing a test.

| Claimed | Reality at v0.1.3 |
|---|---|
| `dup_keys` option | Declared in the header, read nowhere |
| `max_depth` option | Declared, read nowhere — 20,000 levels parse with `max_depth = 10` |
| `max_size` option | Declared, read nowhere |
| `CYAML_ERR_DUP_KEY` | Defined, with a `strerror` string, never raised |
| `cyaml_scalar_str()` | Returns a NUL-terminated string with no length, so a scalar containing a NUL is silently truncated |
| `cyaml_scalar_str()` | Re-reads a **built** node's span as YAML source, folding line breaks into spaces, so no built document can emit a multi-line string |
| Parser | Treats a literal NUL byte as end of input — the rest of the stream is dropped without an error |
| Parser | Leaves a leading UTF-8 BOM inside the first scalar |
| `cyaml_new_float()` | Formats with `%g` — six significant digits |
| Emitter | Never quotes numeric-looking strings, so `"42"` emits as `42` |
| Emitter | *Always* quotes plain `true`/`false`/`null`/`~`, so `cyaml_new_bool()` emits the string `"true"` |

The package implements the three missing limits itself, scans the input for NUL
both before parsing and during conversion, skips the BOM, formats doubles
itself, chooses scalar styles itself for values **and keys**, and carries
vendored patches for the emitter's reserved-word promotion and for the built-
document scalar text.

**Four of these are upstream bugs worth reporting** and have not been reported:
the emitter turning `a: true` into `a: "true"` on its own parse-then-emit round
trip; the three options that do nothing; `cyaml_scalar_str()` mangling built
spans; and the NUL and BOM handling in the parser.

---

## Not done

### Done since the review

- ~~**The emitter round-trip defect**~~ (M6.5) — **done.** 280/280 suite
  documents round-trip, and the property holds over generated and exhaustive
  short strings. Needed a vendored patch as well as the caller-side rule.
- ~~**Literal NUL truncation**~~ (M6.5) — **done.** Refused before parsing,
  with a line and column.
- ~~**UTF-8 BOM**~~ (M6.5) — **done.** Skipped before parsing; positions still
  count from the first real character.
- ~~**The round-trip assertion itself**~~ (M6.6) — **done**, plus multi-document
  semantic comparison (279/279 cases now compared, where 23 were skipped),
  `tools/conformance.R` with a pinned baseline, eight poisoning loops,
  `gctorture` coverage, format-specifier and `R_forceSymbols` assertions.
- ~~**ASan/UBSan green run**~~ — **observed**, locally. The r-hub containers
  are still unverified; see the sanitizer section for exactly what was and was
  not demonstrated.
- ~~Tag handling~~ — **done.** Core tags override resolution, `%TAG` handle
  redefinition is honoured, and application tags are ignored by default with
  `tags = "error"` to refuse them. The design's original "always error" default
  was changed on evidence: it rejected more than twenty valid documents in the
  upstream suite, including a spec example.

### Blocking a 1.0

- **Three open questions** (design §22): key stringification, eight-versus-five
  functions, and whether `zuyaml_bigint` and `zuyaml_map` belong in 1.0. All are
  breaking changes afterwards.
- **Use the RC on something real** before freezing. The roadmap asks for this
  explicitly; `zuhttp` is the obvious candidate.
- **`conditionCall()` is always `NULL`** (M7). Hardcoded in both layers, at
  `R/conditions.R:21` and `src/zuyaml_error.c:55`, so a failure prints as
  `Error:` rather than `Error in yaml_parse(config):`. Backward compatible to
  populate, but a field that exists and is always empty is not a shape to
  freeze.

### Housekeeping

- No git tag.
- win-builder results unread; the emitter changed since that submission, so it
  is worth resubmitting rather than reading the old result.
- Upstream bug reports unfiled — now four of them, and one (`cyaml_scalar_str()`
  on built spans) is serious for any caller of the builder API.
- Not submitted to CRAN — deliberately.

---

## Decisions taken

| Decision | Resolution |
|---|---|
| `simplify` default | **`FALSE`** — the shape of the result never depends on document contents |
| `max_nodes` default | **`1e6`** — set by measurement: a 20k-element document is 20k nodes, so ~50× headroom, while a sub-300-byte alias bomb costs ~10× less |
| Boolean emission | **Second vendored patch**, rather than `!!bool` tags on every logical |
| Vendored layout | Flat in `src/`, no `OBJECTS` list, no GNU-make dependency |
| Emitter style fix (M6.5) | **Double-quote**, not a literal block — it round-trips unconditionally and needs no chomping or indentation-indicator logic, which is where cyaml's emitter is least reliable. Literal blocks are a readability follow-up at M9 |
| Mapping keys | **The same style rule as values**, not a narrower one. Most non-string-resolving keys do survive, because the parser stringifies every key — but `null` and `~` do not, and two rules where one will do is how the first gap stayed open |
| Integral doubles | **Always emit as a float** (`1.0`), matching the `yaml` package. The alternative was to document the type change, which contradicts the round-trip claim on ordinary data |
| `NULL` / `NA` emission | **Explicit `null`**, not cyaml's empty value. `x:` reparses correctly but is the shape a truncated document has |
| Fixing `cyaml_scalar_str()` | **A fifth vendored patch**, because no caller-side style choice can prevent the folding — it happens before the emitter consults the style |
| Snapshot tests | **Rejected.** `yaml12` snapshots error message text; this package promises stable `code`/`line`/`column` instead (design §10) so callers never match on prose. Snapshots would re-couple tests to wording nothing guarantees |
| `out.yaml` as an emitter reference | **Rejected.** It encodes block-versus-flow and quoting choices the package explicitly does not commit to. The emitter needs a round-trip *property*, not a reference file |

---

## Honest notes on performance

`zuyaml` parses at **0.6–0.9×** the speed of the `yaml` package and emits at
**1.5–4×**. It wins on parsing only for multi-document streams. Installed size
is 399 KB against 645 KB.

Against `yaml12` 0.2.0 (measured 2026-09-11, three shapes: nested map ×2000,
int seq ×20000, string seq ×10000) it parses at **2–3.5× faster** — 4.4/6.5/6.4 ms
against 15.8/14.3/10.9 ms. Emission is mixed: **6.7× slower** on nested maps
(33 ms against 5 ms), 1.7× slower on integer sequences, 1.6× faster on string
sequences. Installed size 336 KB against 1.2 MB, and `yaml12` needs a Rust
toolchain to build from source. (That 336 KB is `du` on the installed tree in
this session and does not match the 399 KB recorded above, which came from a
different platform and method — the comparison against `yaml12` is like for
like, the two zuyaml figures are not.)

The parse result is worth recording only because it contradicts the expectation
a Rust implementation sets. The nested-map emit result is the one to act on.

**What M6.5 and M6.6 cost (measured 2026-09-14, same machine, before and after,
both `-O2`).** Parsing is unchanged to three significant figures, despite the
new whole-buffer NUL scan: 2.43 → 2.46 ms, 4.10 → 4.11 ms, 2.16 → 2.18 ms.
Emission is unchanged on maps and integers (30.4 → 31.2 ms, 4.13 → 3.99 ms) and
**19% slower on string sequences** (1.77 → 2.10 ms), which is the style check
and the extra quoting doing exactly what they were added to do. Nothing here
changes the standing rule that no performance claim goes in user-facing text.

*A trap worth recording, because it cost a wrong conclusion.* The first run of
this comparison showed parsing 3× slower. `pkgload::load_all()` leaves `-O0`
objects in `src/`, and `R CMD INSTALL .` reuses any `.o` newer than its `.c`,
so the "after" build was unoptimised and the "before" build — a fresh worktree
— was not. **Delete `src/*.o` before benchmarking an in-place build.**

Time is dominated by R object allocation, not YAML parsing: 20,000 tiny scalars
cost ~4× more per byte than 20 large ones. Further optimisation belongs on the
allocation side, not in the parser.

**No performance claim appears in the README, `DESCRIPTION`, or the vignette,
and none should.** The reason to use this package is its handling of ambiguous
YAML, not its speed. As of 2026-09-14 the handling claims are true on the emit
path as well as the parse path, and asserted — which is the thing worth saying,
and it is not a performance claim.
