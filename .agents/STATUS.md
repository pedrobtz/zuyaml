# zuyaml — status

Written 2026-09-08, at version 0.9.0, 18 commits on `develop`.

Companion to [DESIGN-zuyaml.md](DESIGN-zuyaml.md) (what to build) and
[ROADMAP.md](ROADMAP.md) (in what order). This says **where it actually is**,
including what is not done and what has been claimed but not demonstrated.

---

## Short answer

M0–M5 are complete. **M6 is not**, and M7 has only had its preparation done.
The package works and is well tested; two of the robustness claims the roadmap
attaches to M6 have never been demonstrated.

| | |
|---|---|
| Version | 0.9.0 (release candidate; API complete, **not frozen**) |
| Exports | 9 — eight API functions plus `zuyaml_bigint()` |
| Code | 527 lines R, 1,614 lines C, plus 14,478 lines vendored cyaml |
| Tests | 2,517 assertions across 12 files, plus 84 conformance fixtures |
| `R CMD check --as-cran` | 0 errors, 0 warnings, 1 NOTE (new submission) |
| Vendored patches | 2, both mandatory and documented |

---

## What the checks say

| Check | Result |
|---|---|
| R-CMD-check — macOS, Windows, Ubuntu ×4 (release/devel/oldrel-1/clang) | pass |
| yaml-test-suite, all 355 cases | pass — 333/333 agreement on valid vs invalid |
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

**Two of these are upstream bugs worth reporting** and have not been reported:
the emitter turning `a: true` into `a: "true"` on its own parse-then-emit round
trip, and the three options that do nothing.

---

## Not done

### Blocking a 1.0

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

### Housekeeping

- No `0.9.0` git tag.
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

---

## Honest notes on performance

`zuyaml` parses at **0.6–0.9×** the speed of the `yaml` package and emits at
**1.5–4×**. It wins on parsing only for multi-document streams. Installed size
is 399 KB against 645 KB.

Time is dominated by R object allocation, not YAML parsing: 20,000 tiny scalars
cost ~4× more per byte than 20 large ones. Further optimisation belongs on the
allocation side, not in the parser.

**No performance claim appears in the README, `DESCRIPTION`, or the vignette,
and none should.** The reason to use this package is its handling of ambiguous
YAML, not its speed.
