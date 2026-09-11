# zuyaml — status

Written 2026-09-08, at version 0.1.0, 25 commits on `develop`.
Revised 2026-09-11 after a differential review against `yaml12` 0.2.0, which
found two silent-data-loss defects in this package and the testing gap that let
them through. Both are staged as M6.5 in the roadmap.

Companion to [DESIGN-zuyaml.md](DESIGN-zuyaml.md) (what to build) and
[ROADMAP.md](ROADMAP.md) (in what order). This says **where it actually is**,
including what is not done and what has been claimed but not demonstrated.

---

## Short answer

M0–M5 were recorded as complete. **Two of them are not.** M4's round-trip
criterion is false as shipped, and M3's embedded-NUL criterion is half met —
both found on 2026-09-11, both now staged as M6.5 and blocking 1.0. **M6 is
still not complete**, and M7 has only had its preparation done.

The package is well tested by volume. It is not well tested at the boundary
that broke: 2,517 assertions, 15,000 fuzz iterations and a 402-case corpus, and
not one of them reparses what the emitter produced.

| | |
|---|---|
| Version | 0.1.0 — API complete, deliberately **not frozen** |
| Exports | 9 — eight API functions plus `zuyaml_bigint()` |
| Code | 527 lines R, 1,614 lines C, plus 14,478 lines vendored cyaml |
| Tests | 2,517 assertions across 12 files, plus 84 conformance fixtures |
| `R CMD check --as-cran` | 0 errors, 0 warnings, 1 NOTE (new submission) |
| Vendored patches | 2, both mandatory and documented |
| Known defects | **2, both silent data loss** — staged at M6.5, see below |

---

## What the checks say

| Check | Result |
|---|---|
| R-CMD-check — macOS, Windows, Ubuntu ×4 (release/devel/oldrel-1/clang) | pass |
| yaml-test-suite, all 355 cases | pass — 333/333 agreement on valid vs invalid |
| yaml-test-suite, full re-run 2026-09-11 (402 leaf cases) | pass — 402/402 on valid vs invalid; 304/308 semantic agreement with `yaml12` |
| yaml-test-suite — **emit → parse round trip** | **fail — 70 of 280 emitted documents come back as different values** |
| Differential review vs `yaml12` 0.2.0 | **found both defects below**; neither was reachable by the existing checks |
| Fuzzing — random bytes, syntax fragments, truncation | pass at 15,000 iterations each |
| R-hub — valgrind, c23, nold, noremap, intel | pass |
| R-hub — **rchk** | pass, **after fixing a real defect it found** |
| **ASan / UBSan** | **never executed** — see below |
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

### ASan and UBSan have never run

Three consecutive attempts failed before executing a single test:

1. Backslash line continuations inside a YAML `run:` block are literal text,
   not shell continuations, so R received invalid input.
2. `set -o pipefail` is not available in the containers' `sh`.
3. Under `sh -e`, a failing `Rscript` aborts the step before `cat
   sanitizer.log`, so the output was swallowed.

All three are fixed; a green run has not yet been observed. Until it is,
**"clean under ASan/UBSan" is an unsupported claim** — and it is the claim that
backs the unwind-safety design, the riskiest part of the C layer.

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
`gctorture(TRUE)`. None of these is *asserted* anywhere, which is the point —
they pass by construction, not by test. M6.6 pins them.

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
| `cyaml_new_float()` | Formats with `%g` — six significant digits |
| Emitter | Never quotes numeric-looking strings, so `"42"` emits as `42` |
| Emitter | *Always* quotes plain `true`/`false`/`null`/`~`, so `cyaml_new_bool()` emits the string `"true"` |

The package implements the three missing limits itself, scans the raw span for
NUL, formats doubles itself, chooses scalar styles itself, and carries a
vendored patch for the last item.

Two of those workarounds are narrower than this reads. The NUL scan covers a
`\0` *escape* but not a literal NUL byte, and the scalar-style choice covers
numeric-looking text but not whitespace — see the review section above. Both
are this package's defects, not upstream's, and both are staged at M6.5.

**Two of these are upstream bugs worth reporting** and have not been reported:
the emitter turning `a: true` into `a: "true"` on its own parse-then-emit round
trip, and the three options that do nothing.

---

## Not done

### Blocking a 1.0

- **The emitter round-trip defect** (M6.5). Strings with newlines or edge
  whitespace are corrupted on emit; 70 of 280 suite documents change value.
  This is the one that most directly contradicts what the package is for.
- **Literal NUL truncation** (M6.5). Everything after the first NUL byte is
  discarded without a condition.
- **The round-trip assertion itself** (M6.6). `test-conformance.R` already
  parses, emits and tolerates refusal; it never reparses. One line closes the
  gap that hid the defect above.
- **ASan/UBSan green run** — fixed but unobserved (M6 exit criterion).
- ~~Tag handling~~ — **done.** Core tags override resolution, `%TAG` handle
  redefinition is honoured, and application tags are ignored by default with
  `tags = "error"` to refuse them. The design's original "always error" default
  was changed on evidence: it rejected more than twenty valid documents in the
  upstream suite, including a spec example.
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
- win-builder results unread.
- Upstream bug reports unfiled.
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
a Rust implementation sets. The nested-map emit result is the one to act on, and
M6.5 will change that code anyway.

Time is dominated by R object allocation, not YAML parsing: 20,000 tiny scalars
cost ~4× more per byte than 20 large ones. Further optimisation belongs on the
allocation side, not in the parser.

**No performance claim appears in the README, `DESCRIPTION`, or the vignette,
and none should.** The reason to use this package is its handling of ambiguous
YAML, not its speed — and as of 2026-09-11 one of those handling claims is
false on the emit path. Fix M6.5 before making any claim about anything.
