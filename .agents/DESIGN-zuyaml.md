# zuyaml — Design

## Status

**Proposed.**

This document defines the design for `zuyaml`, a small R package for parsing and
emitting YAML using the vendored [`andrewmd5/cyaml`](https://github.com/andrewmd5/cyaml)
C11 library.

The design baseline is **cyaml v0.1.3**, tag commit
`0672e81b809bc3dfd1d4f57ba0fcfbb20c60ae70`. The vendored upstream version must be
pinned explicitly; `zuyaml` must not silently track upstream `main`.

> **Verification note.** Every claim in this document about cyaml's API,
> defaults, and behaviour was checked against the vendored source at the tag
> above, and the behavioural ones were confirmed by running the library.
>
> That distinction matters: three documented `cyaml_opts_t` options are
> declared in the public header, described in the README, and never read by any
> code path (§3.1). Reading headers is not enough — **grep for each option in
> the implementation, and write a test that proves the behaviour**. Re-run this
> whenever the vendored version changes (§13).

---

## 1. Summary

`zuyaml` provides a small, dependency-light YAML implementation for R with four
goals:

1. parse YAML text into ordinary R objects;
2. emit ordinary R objects as YAML;
3. support YAML 1.2 semantics predictably;
4. remain small enough to serve as an internal building block for packages such
   as `zuhttp`.

The package vendors `cyaml` and calls its C API directly through `.Call`. It does
not depend on `Rcpp`, `cpp11`, an external YAML installation, or another R YAML
package.

```text
R character/raw input            R object
        │                            │
        ▼                            ▼
   zuyaml R API                 R → cyaml tree
        │                            │
        ▼                            ▼
 small .Call layer              cyaml emitter
        │                            │
        ▼                            ▼
 vendored cyaml                  YAML string
        │
        ▼
 cyaml document tree
        │
        ▼
 deterministic conversion
        │
        ▼
     R object
```

`zuyaml` is **not** a schema framework, configuration framework, YAML editor, or
a full wrapper around every `cyaml` feature.

---

## 2. Motivation

R already has the mature `yaml` package, built on LibYAML. `zuyaml` does not exist
to provide another spelling of the same API. Its position is:

> A small, modern YAML 1.2 parser/emitter for R, built on a vendored C11
> implementation and designed to compose cleanly with lightweight infrastructure
> packages.

It fits a package family such as:

```text
zuhttp
├── zujson
├── zuxml
├── zuyaml
└── zukomp
```

The value proposition is architectural:

- no system YAML dependency;
- no C++ wrapper layer;
- modern YAML 1.2 scalar semantics;
- small public API;
- deterministic, documented R conversion rules;
- suitable for parsing HTTP response bodies;
- strict defaults for ambiguous or lossy YAML constructs;
- upstream conformance tests incorporated into package validation.

**Honest sizing.** "Small" refers to the R-facing API and the absence of
dependencies, not to the compiled footprint. The vendored library is
~13,000 lines / ~464 KB of C across 8 translation units, and §13 explains why
the files implementing deferred features cannot simply be dropped.

---

## 3. Why cyaml

The `cyaml` referred to here is **andrewmd5/cyaml**, not the older schema-oriented
`libcyaml` project.

Verified properties at v0.1.3:

- C11, no dependencies beyond the C standard library;
- YAML 1.2 parser and emitter;
- document-tree API with a public, fully-defined `cyaml_node` struct;
- multi-document stream parsing (`cyaml_parse_stream`);
- zero-copy source spans — every scalar is an offset/length into the caller's
  buffer, with 1-based line/column start and end;
- core-schema scalar classification (`cyaml_scalar_kind`);
- anchors and aliases with cycle detection;
- style and comment preservation facilities;
- YPATH querying;
- MIT license;
- upstream `yaml-test-suite` validation.

Upstream also advertises duplicate-key detection and configurable depth/size
limits. **Those are not implemented at v0.1.3** — see §3.1. They are listed
here as a warning, not as properties to rely on.

Its test/reference submodules (`third-party/Unity`, `refs/yaml-test-suite`,
`refs/yaml-spec`) are **not** required to build the library — vendoring needs only
`src/`.

### 3.1 What cyaml does not give us

Four limits shape this design. Each was found by testing behaviour rather than
by reading the header or the README, which is why the verification note above
insists on re-checking after every re-vendor:

**Event output is not SAX parsing.** `cyaml_events()` and `cyaml_stream_events()`
produce a *textual* event representation from an already-parsed document. They are
not an Expat-like streaming callback parser. Therefore `zuyaml` is designed around
the document tree, and must not advertise streaming YAML parsing unless upstream
later exposes a real streaming parser API. (`zuxml` can reasonably expose
Expat-style streaming; `zuyaml` cannot.)

**The builder only accepts string keys.** `cyaml_map_set()` takes a
`const char* key` and has *set-or-update* semantics. There is no public way to
attach an arbitrary key **node** to a map being built, and no way to build a map
with duplicate keys. This bounds what `zuyaml` can emit (§7.5).

**Most of `cyaml_opts_t` is declared but not implemented.** This is the single
most consequential gap, and it is invisible from the header. Of the five option
fields, only two are ever read by the library:

| field | read by cyaml at v0.1.3? |
|---|---|
| `spec` | **yes** — `cyaml_parser.c` |
| `preserve_comments` | **yes** — `cyaml_parser.c` |
| `dup_keys` | **no** — declared in the header, read nowhere |
| `max_depth` | **no** — declared in the header, read nowhere |
| `max_size` | **no** — declared in the header, read nowhere |

`CYAML_ERR_DUP_KEY` likewise exists, has a `cyaml_strerror()` string, and is
never raised. Verified empirically: a document with duplicate keys parses
cleanly, and one nested 20,000 levels deep parses cleanly with
`max_depth = 10`.

**`zuyaml` must therefore implement all three itself** — duplicate-key
rejection during mapping conversion (§6.4), and `max_depth` / `max_size` as
described in §11. Set the upstream fields anyway, so a future version that
honours them agrees with our behaviour rather than fighting it.

Empirically, cyaml's own parser survives 100,000 levels of flow nesting without
crashing, so the absence of `max_depth` is not a stack-overflow risk *inside
cyaml*. The risk is on our side: a recursive R conversion of such a document
exhausts R's protection stack. Enforcing depth during conversion addresses
both.

**The emitter does not quote ambiguous numerics.** `needs_quoting_ex()` in
`cyaml_emitter.c` promotes a plain scalar to double-quoted for flow indicators,
leading indicators, `---`/`...`, trailing `:`, line breaks, ` #`, `: `, and the
reserved words `null` / `true` / `false` / `~` (case-insensitive). It performs
**no numeric check**. A node built from the string `"42"` emits as bare `42`.
`zuyaml` must therefore choose scalar styles itself (§7.2).

---

## 4. Scope

### 4.1 In scope for v0.1

- YAML string parsing and raw-vector parsing;
- file reading and writing;
- single documents and multi-document streams, distinguished explicitly;
- maps, sequences, YAML 1.2 core-schema scalars;
- explicit nulls, booleans, integers, floats, strings;
- integers beyond double precision, without silent loss;
- anchors and aliases, resolved during conversion, with an expansion budget;
- duplicate-key rejection;
- collection-valued mapping keys preserved structurally (parse only);
- YAML emission with style selection that survives a round trip;
- parse errors carrying a code, line, and column.

### 4.2 Deferred, and why

| Deferred | Reason |
|---|---|
| YPATH querying | Needs a retained document (§20) |
| Document mutation, editable round trips | Needs a retained document (§20) |
| Comment and style preservation | No lossless R representation (§8) |
| `scanf`/`printf`-style cyaml APIs | Redundant with R-side access |
| Direct JSON output from cyaml | `zujson` owns JSON |
| Textual event-stream output | Not a streaming parser (§3.1) |
| Canonical yaml-test-suite dumps | CI-only concern (§16.3) |
| Arbitrary user callbacks from C | Re-entrancy and unwind hazards (§9.3) |
| Persistent C document pointers | Source-lifetime complexity (§9.4) |
| Emitting collection-valued or duplicate keys | Upstream builder cannot (§3.1) |
| Schema validation, custom-tag handlers | Policy beyond a parser |
| Data-frame conversion, `!!binary`, Date/POSIXct | Policy beyond a parser |

### 4.3 Non-goals

`zuyaml` is not intended to become a Kubernetes SDK, a YAML linter, a schema
language, a templating system, a configuration-merging framework, a general
serializer for arbitrary R classes, a comment-preserving YAML editor, or a
replacement for JSON where JSON is sufficient.

---

## 5. Public R API

Eight exported functions, on a uniform rule: **`_all` means "YAML stream"**.

|  | one document | stream of documents |
|---|---|---|
| parse text | `yaml_parse()` | `yaml_parse_all()` |
| emit text | `yaml_emit()` | `yaml_emit_all()` |
| read file | `yaml_read()` | `yaml_read_all()` |
| write file | `yaml_write()` | `yaml_write_all()` |

```r
yaml_parse(
  x,
  simplify      = FALSE,
  aliases       = c("resolve", "error"),
  big_integers  = c("bigint", "double", "error"),
  tags          = c("ignore", "error"),
  duplicate_keys = FALSE,
  max_depth     = 128L,
  max_size      = 64 * 1024^2,
  max_nodes     = 1e6,
  path          = NULL
)

yaml_parse_all(x, ...)          # same arguments; returns a list of documents

yaml_emit(
  x,
  indent         = 2L,
  width          = 80L,
  document_start = FALSE,
  document_end   = FALSE
)

yaml_emit_all(x, ...)           # x is a list of documents

yaml_read(path, ...)            # ... passed to yaml_parse()
yaml_read_all(path, ...)        # ... passed to yaml_parse_all()

yaml_write(x, path, ...)        # ... passed to yaml_emit()
yaml_write_all(x, path, ...)    # ... passed to yaml_emit_all()
```

The `yaml_*()` prefix is chosen over `parse_yaml()` / `emit_yaml()` so that every
exported function shares one discoverable prefix. Use it consistently.

### 5.1 Input types

`yaml_parse()` and `yaml_parse_all()` accept:

- a length-one, non-`NA` character vector containing YAML; or
- a raw vector containing UTF-8 YAML bytes.

Anything else is an error, including a character vector of length ≠ 1 and
`NA_character_`. There is no vectorised parsing: a character vector of length 3 is
a user mistake far more often than a request to parse three documents.

### 5.2 One document versus many

Both functions parse the input as a **stream** via `cyaml_parse_stream()`
(§9.5). `yaml_parse()` then requires exactly one document:

| documents in stream | `yaml_parse()` | `yaml_parse_all()` |
|---|---|---|
| 0 | error | `list()` |
| 1 | the object | list of length 1 |
| n > 1 | error | list of length n |

```text
YAML stream contains 2 documents; use yaml_parse_all().
YAML stream contains no documents.
```

Silently ignoring trailing documents is not acceptable, and neither is returning
`NULL` for an empty stream — `NULL` is a legitimate value for a document whose
content is `null`, so the empty-stream case must be distinguishable. Note that a
comment-only input (`"# nothing here"`) is a zero-document stream.

`yaml_parse_all()` always returns a list, including for a single-document stream.
This makes the distinction between a YAML *sequence* and a YAML *stream* explicit
in the R type.

### 5.3 Emission

`yaml_emit()` returns a length-one UTF-8 character string. Emission favours
readable YAML over exact reproduction of source formatting (§8).

Only stable formatting controls are exposed:

| argument | maps to | valid range |
|---|---|---|
| `indent` | `cyaml_emit_opts_t.indent` (`uint8_t`) | 1–255 |
| `width` | `cyaml_emit_opts_t.width` (`uint8_t`) | 0–255, **0 = no wrapping** |
| `document_start` | `.doc_start` | `TRUE`/`FALSE` |
| `document_end` | `.doc_end` | `TRUE`/`FALSE` |

Both numeric options are `uint8_t` upstream and **must be range-checked in R**
before narrowing; `width = 1000L` would otherwise silently become 232. Do not
expose the remaining upstream knobs (`preserve_comments`, `preserve_style`,
default `style`/`coll`) in v0.1.

`yaml_emit_all()` takes a list of documents and joins them with explicit `---`
markers. It does **not** use `cyaml_stream_emit()`, which accepts no options and
is designed to preserve the formatting of a *parsed* stream; instead it emits each
document with the same options and concatenates. `document_start` is forced `TRUE`
for the second and subsequent documents regardless of the argument, because a
stream is not otherwise parseable.

### 5.4 Files

```r
yaml_read <- function(path, ...) yaml_parse(read_file_as_raw(path), ...)
```

Read and write **bytes**, never locale-dependent text. `yaml_write()` emits first,
then writes, and returns `path` invisibly. Parse errors from a file include the
path (§10).

---

## 6. YAML → R conversion

The most important package-level responsibility is a stable conversion between the
YAML data model and R. The C library parses YAML; **`zuyaml` owns the R semantics.**

### 6.1 Dispatch

`cyaml_type_t` has six members and conversion must handle all of them:

```text
CYAML_NONE    -> internal error (invalid/uninitialised node); never reachable
                 from a successful parse, but must not fall through silently
CYAML_NULL    -> NULL
CYAML_SCALAR  -> classify with cyaml_scalar_kind(), then §6.2
CYAML_SEQ     -> §6.3
CYAML_MAP     -> §6.4
CYAML_ALIAS   -> §6.5
```

### 6.2 Scalars

YAML 1.2 Core Schema semantics throughout. `cyaml_scalar_kind()` classifies plain
scalars as null / bool / int / float / string and returns `CYAML_KIND_STRING` for
every quoted scalar, which is exactly the distinction R needs.

#### Null

`null`, `Null`, `NULL`, `~`, and an empty value become `NULL`.

Two traps:

- Inside lists, construct with `SET_VECTOR_ELT()` in C. The R-level idiom
  `x[[i]] <- NULL` *deletes* the element.
- Do **not** use `cyaml_is_null_val()` to make this decision: it treats an empty
  value as null, so it would collapse `""` to `NULL`. Dispatch on
  `cyaml_scalar_kind()`, which returns `CYAML_KIND_STRING` for the quoted empty
  string. Upstream also flags this case explicitly with
  `CYAML_SCALAR_EXPLICIT_EMPTY` ("empty value that should NOT become null").

```yaml
key: ""     # must be "" in R, never NULL
key:        # NULL
```

#### Boolean

`true` / `false` and their case variants become length-one logicals.

Do **not** apply YAML 1.1 rules — `yes`, `no`, `on`, `off` are strings under the
1.2 core schema. Note that upstream's `cyaml_as_bool()` documents itself as
case-*insensitive*, which is marginally broader than the core schema's
`true|True|TRUE|false|False|FALSE`. Pin the exact accepted set with tests rather
than assuming; `cyaml_scalar_kind()` is the authority in either case.

#### Integer

R has no native 64-bit integer scalar, so conversion is explicit. `cyaml_as_int()`
yields `int64_t` and `cyaml_as_uint()` yields `uint64_t`; beyond both, the raw
source span is still available via `cyaml_str()` / `cyaml_len()`.

| value range | result |
|---|---|
| fits in 32-bit R `integer` | `integer` |
| exactly representable as a double (\|v\| ≤ 2^53) | `double` |
| beyond 2^53 | per `big_integers` (below) |

```r
big_integers = "bigint"   # default: character vector of class "zuyaml_bigint"
big_integers = "double"   # explicit opt-in to lossy conversion
big_integers = "error"    # refuse the document
```

The invariant is:

> Never silently lose integer precision.

`"double"` is the escape hatch for users who have decided precision does not
matter; it is opt-in, so the invariant holds by default.

`zuyaml_bigint` is a character vector carrying the **decimal normalisation** of the
value, not its source text — cyaml accepts `0x` hex and `0o` octal integers, and
storing `0xFFFFFFFFFFFFFFFF` would make the class useless for comparison. Because
it is returned to users it is public API, and it ships with `format()`, `print()`,
`as.character()`, and `as.numeric()` methods plus a validating constructor
`zuyaml_bigint()`. A class with no methods that prints its `attr(,"class")` is not
acceptable UX for a value users will hit unpredictably.

A future version may integrate with an external 64-bit integer class. The core
package must not require one.

#### Float

YAML floats become R doubles, including `.inf` → `Inf`, `-.inf` → `-Inf`,
`.nan` → `NaN`.

#### String

All quoted scalars are strings; plain scalars classified `CYAML_KIND_STRING` are
strings. UTF-8 is the canonical text encoding (§12).

#### Timestamp-like text

`2026-09-07` and `2026-09-07T12:00:00Z` stay **strings**. The YAML 1.2 core schema
does not require timestamp coercion, and automatic date parsing is policy beyond a
parser's job.

### 6.3 Sequences

A YAML sequence becomes an R list:

```yaml
- one
- 2
- true
```

```r
list("one", 2L, TRUE)
```

An empty sequence is `list()`.

`simplify = TRUE` collapses scalar-only sequences to atomic vectors, subject to
all of:

- every element is a scalar (no nested sequence or mapping);
- every element has the same R base type;
- no element is `NULL`;
- no element is a `zuyaml_bigint`.

**The default is `FALSE`.** This reverses the conventional choice deliberately.
Simplification makes the *shape* of the return value depend on the *contents* of
the document: `[1, 2]` yields an integer vector and `[1, "a"]` yields a list, so
downstream code that indexes the result is correct only for the inputs the author
happened to test. That is the same class of ambiguity this design rejects
elsewhere by erroring (duplicate keys, partially named lists), and rejecting it
here costs users one explicit argument. `simplify = TRUE` remains available and
fully supported. See §22 — this is the most reasonable decision in the document to
reverse.

### 6.4 Mappings

YAML mapping keys are arbitrary nodes; R names are character. Iterate pairs with
`cyaml_map_len()` and `cyaml_map_at()`, which expose the key **node**.

#### Scalar keys → named list

If every key is a scalar, the result is a named R list whose names are the keys'
string values:

```yaml
host: localhost
port: 8080
tls: true
```

```r
list(host = "localhost", port = 8080L, tls = TRUE)
```

Non-string scalar keys (`1: a`, `true: b`) are stringified to `"1"`, `"true"`.
This is a documented lossy conversion (§8): `1` and `"1"` both become the name
`"1"`. It is accepted because integer keys are common in real YAML and an exotic
return type for `{1: a}` would be more surprising than the coercion. Because
stringification can collide where YAML saw distinct keys, **names are re-checked
for uniqueness after conversion** and a collision is an error unless
`duplicate_keys = TRUE`.

#### Collection keys → `zuyaml_map`

A key that is itself a sequence or mapping has no faithful named-list
representation:

```yaml
? [one, two]
: value
```

Such mappings become a `zuyaml_map`: two parallel lists, chosen over a list of
key/value pairs because iteration and emission both want the keys and values
separately.

```r
structure(
  list(keys = list(c("one", "two")), values = list("value")),
  class = "zuyaml_map"
)
```

The invariant is:

> Unsupported YAML mapping keys are preserved structurally, never silently
> coerced into names.

`zuyaml_map` is **parse-only in v0.1**, and `yaml_emit()` errors on one, because
`cyaml_map_set()` cannot attach a key node (§3.1). This is an honest limitation,
not an oversight: it means a document with complex keys does not round-trip. Say
so in the documentation rather than implying otherwise.

#### Duplicate keys

Rejected by default — **enforced by `zuyaml`, not by cyaml**. Upstream declares
the option and the error code but implements neither (§3.1), so a document with
duplicate keys parses cleanly and detection has to happen during mapping
conversion: build the name vector, then check for duplicates before returning.
This is cheap, since the names are being materialised anyway.

With `duplicate_keys = TRUE`, duplicates become duplicate names in an R list:

```r
list(a = 1L, a = 2L)
```

This must be tested explicitly, because `$` and `[[` access is ambiguous on such
objects — and, like `zuyaml_map`, it does not round-trip: `cyaml_map_set()` is
set-*or-update*, so emission would silently drop the duplicate. `yaml_emit()`
therefore errors on a list with duplicate names.

### 6.5 Anchors and aliases

R has no portable user-facing concept of YAML node identity, so `aliases`
governs behaviour rather than representation:

```r
aliases = "resolve"   # default: alias converts to the value of its target
aliases = "error"     # reject any document containing an alias
```

Node identity is not a public guarantee. Do not expose a half-specified
`"preserve"` mode until an R representation for anchors is designed.

**Resolve during traversal, not via `cyaml_resolve_aliases()`.** Upstream's
function replaces every alias with a *deep copy* of its target, in C, before
`zuyaml` sees the tree. That materialises the full expansion with no budget, which
is precisely the billion-laughs failure mode (§11). Resolving during R conversion
lets every expanded node be counted against `max_nodes` and aborted early.

Traversal keeps its own cycle guard — an alias whose target is an ancestor of the
current node is an error:

```text
YAML alias cycle detected at line 4, column 3.
```

Never attempt to manufacture recursively self-referential R lists.

### 6.6 Tags

- Standard core tags participate in normal scalar conversion. `!!str 12` is the
  string `"12"`, and the non-specific tag `!` forces string resolution too.
- Every spelling of a core tag is recognised: the shorthand `!!str`, the
  verbatim form `!<tag:yaml.org,2002:str>`, and a named handle bound to the
  core prefix by `%TAG !e! tag:yaml.org,2002:`. A tag is expanded against the
  document's `%TAG` directives before it is compared.
- A `%TAG` directive that redefines a handle is honoured: after
  `%TAG !! tag:example.com,2000:app/`, `!!int` is an *application* tag and
  `!!int 1 - 3` stays the string `"1 - 3"`. It is the *prefix* that decides
  this, not the handle: `%TAG !! tag:yaml.org,2002:` is legal and restates the
  default, so it changes nothing. The non-specific tag `!` is a separate
  production from the primary handle and is not substituted, so a `%TAG !`
  directive leaves `! 12` as the string `"12"`.
- A core tag on text that does not conform to it resolves as a string, which is
  what an unresolvable scalar is in YAML: `!!int nonsense`, `!!float abc` and
  `!!bool notabool` are all their own text. Erroring instead would reject
  documents that parsed before tags were honoured at all.
- Unknown application tags are **ignored by default**, with `tags = "error"`
  available to refuse them. The policy applies on the key side of a mapping as
  well as the value side, even though a key is stringified rather than
  converted.

> **Changed from the original design, on evidence.** This section previously
> specified that unknown tags must always error. Implementing that showed it
> rejects a great deal of perfectly ordinary YAML — more than twenty documents
> in the upstream test suite carry application tags and are valid, including
> Spec Example 2.27, whose root is tagged
> `!<tag:clarkevans.com,2002:invoice>`. A parser that refuses the spec's own
> examples is not usable. Erroring remains available for callers who want to
> know that they are dropping semantics.

```r
yaml_parse("value: !duration 5m")
#> $value
#> [1] "5m"

yaml_parse("value: !duration 5m", tags = "error")
#> Error: Unsupported YAML tag '!duration' at line 1, column 8.
```

The tag text and location come from the node's `tag` span. A future API may add
`tags = "preserve"` or named handlers; neither is required for v0.1, and C
callbacks into R are explicitly out of scope (§9.3).

---

## 7. R → YAML conversion

### 7.1 Scalars

| R value | YAML |
|---|---|
| `NULL` | `null` |
| `TRUE` / `FALSE` | `true` / `false` |
| integer scalar | integer |
| finite double | numeric text that round-trips the double |
| `Inf` / `-Inf` / `NaN` | `.inf` / `-.inf` / `.nan` |
| `NA` (any type) | `null` — lossy, see §8 |
| character scalar | string, style per §7.2 |
| `zuyaml_bigint` | integer, after re-validation |
| factor | its character labels, never its integer codes |

Doubles must be formatted with enough precision to round-trip the value, using
locale-independent formatting.

`zuyaml_bigint` is re-validated at emit time. Trusting the class attribute —
"emit as an integer, the representation was validated on the way in" — is not
sufficient, because nothing prevents a user from constructing one by hand. An
invalid value is an error, not a silently quoted string.

### 7.2 Scalar style selection

This section exists because of a concrete upstream behaviour (§3.1): the emitter
does not quote numeric-looking strings. Without intervention:

```r
yaml_emit(list(x = "42", y = ".inf", z = "0x1F"))
#> x: 42
#> y: .inf
#> z: 0x1F
```

which parses back as `42L`, `Inf`, `31L`. Version strings, zip codes, and IDs all
land here, so the round-trip guarantee in §16.2 fails on ordinary data.

**Rule.** When building a node from an R character scalar, `zuyaml` sets
`node->style = CYAML_DOUBLE` whenever the text would classify as anything other
than a string under the YAML 1.2 core schema. `cyaml_node` is fully defined in the
public header, so assigning `style` is legitimate use of the API.

The check is a small C helper mirroring the core-schema resolution patterns —
null (`null|Null|NULL|~|`), bool (`true|True|TRUE|false|False|FALSE`), int
(decimal, `0x`, `0o`), float (including `.inf`, `-.inf`, `.nan`) — and nothing
else. Everything the upstream `needs_quoting_ex()` already handles (indicators,
`---`, trailing `:`, `: `, ` #`, line breaks, the reserved words, the empty
string) is left to upstream: this helper only closes the numeric gap.

Do not "fix" this by double-quoting every string. `name: "zuyaml"` for every
scalar produces YAML nobody wants to read.

### 7.3 Vectors and lists

| R value | YAML |
|---|---|
| length-one atomic vector | scalar |
| unnamed atomic vector, length > 1 | sequence |
| fully and uniquely named atomic vector | mapping |
| unnamed list | sequence |
| fully and uniquely named list | mapping |
| partially named vector or list | **error** |
| list with duplicate names | **error** (§6.4) |

Partial naming is ambiguous, and guessing intent or discarding names is worse than
refusing.

```r
list(host = "localhost", port = 8080L)   # host: localhost / port: 8080
list("a", "b")                           # - a / - b
```

### 7.4 Empty containers

`list()` does not distinguish an empty mapping from an empty sequence. It emits as
`[]`. To emit `{}`, pass an explicitly empty named list — `structure(list(),
names = character())` — or a zero-length `zuyaml_map()` once that constructor
exists. Guessing from historical attributes is not acceptable.

### 7.5 What cannot be emitted

`yaml_emit()` errors, with guidance, on:

- a `zuyaml_map` (collection keys — upstream builder limitation, §3.1);
- a list with duplicate names (same);
- a data frame;
- any S3/S4 object that is not an explicitly supported class.

```text
Data frames are not emitted automatically; convert explicitly to a list.
```

A data frame could reasonably mean a sequence of row mappings, a mapping of column
sequences, or table-like custom YAML. None is uniquely correct, so the package
does not choose. Likewise, S3/S4 objects are not serialised by blindly stripping
attributes; recognise supported base classes, error otherwise, and add
class-specific methods later if real use cases appear.

---

## 8. Known lossy conversions

Every conversion below is a deliberate, documented trade-off. This table is part
of the package's contract and belongs in the user-facing documentation, not only
here.

| Construct | Behaviour | Round-trips? |
|---|---|---|
| Comments | Discarded | No |
| Quoting / block / flow style | Not preserved; re-chosen on emit (§7.2) | Semantically |
| Anchors and aliases | Resolved to values; identity lost | Semantically |
| Non-string scalar keys | Stringified (`1` → `"1"`) | Semantically |
| Collection-valued keys | Preserved as `zuyaml_map` on parse | **No** — cannot emit |
| Duplicate keys (opt-in) | Duplicate R names | **No** — cannot emit |
| `NA` | Emitted as `null`, parses back as `NULL` | **No** |
| `list(1L)` vs `c(1L)` | Both emit `- 1` / `1` | **No** — list/vector distinction lost |
| Big integers with `big_integers = "double"` | Precision lost | No (opt-in) |

The `NA` case deserves its own note. Erroring would be more consistent with §7.3's
treatment of partial names, but `NA` appears in ordinary R data far too often for
that to be tolerable, and no YAML 1.2 core-schema value means "missing". Mapping
it to `null` is the least-bad option, and it is listed here rather than buried.

This input:

```yaml
# comment
name: 'zuyaml'
```

may legitimately emit as `name: zuyaml`. That is acceptable. Exact formatting
preservation belongs to a future document API (§20), not the ordinary R-object
API.

---

## 9. C architecture

Use the R C API directly. Do **not** introduce `Rcpp`, `cpp11`, C++, or a
dependency on an installed system `cyaml`.

```c
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
```

### 9.1 Package layout

```text
zuyaml/
├── DESCRIPTION
├── NAMESPACE
├── LICENSE
├── R/
│   ├── parse.R
│   ├── emit.R
│   ├── files.R
│   ├── bigint.R
│   ├── map.R
│   └── conditions.R
├── src/
│   ├── init.c
│   ├── zuyaml_parse.c
│   ├── zuyaml_emit.c
│   ├── zuyaml_convert.c / .h
│   ├── zuyaml_error.c / .h
│   ├── Makevars
│   ├── Makevars.win
│   ├── cyaml.c            ← vendored, unmodified
│   ├── cyaml.h            ← vendored, unmodified
│   ├── cyaml_emitter.c    ← vendored, unmodified
│   ├── cyaml_events.c     ← vendored, unmodified
│   ├── cyaml_internal.h   ← vendored + documented patch (§13.2)
│   ├── cyaml_json.c       ← vendored, unmodified
│   ├── cyaml_modify.c     ← vendored, unmodified
│   ├── cyaml_parser.c     ← vendored, unmodified
│   ├── cyaml_path.c       ← vendored, unmodified
│   ├── cyaml_utf8.c       ← vendored, unmodified
│   └── cyaml_utf8.h       ← vendored, unmodified
├── inst/
│   ├── COPYRIGHTS
│   └── cyaml-VERSION
├── tests/{testthat,fixtures}/
├── tools/vendor-cyaml.sh
└── .agents/{DESIGN-zuyaml.md,ROADMAP.md}
```

**The vendored sources live flat in `src/`, not in `src/vendor/cyaml/`.** This is
a change from the obvious layout, and it is deliberate: `R CMD SHLIB` compiles
only the sources directly in `src/`. A subdirectory requires an explicit `OBJECTS`
list in both `Makevars` and `Makevars.win`, hand-maintained in step with the
vendor script, and CRAN discourages the GNU-make constructs (`$(wildcard)`) that
would otherwise generate it without declaring `SystemRequirements: GNU make`.
Flat files cost nothing, need no object list, and upstream's consistent `cyaml_`
prefix keeps the separation obvious. `zuyaml_`-prefixed files are ours.

`.Rbuildignore` must exclude `^\.agents$` alongside the existing entries.

### 9.2 Native entry points

Two, not three:

```c
SEXP zuyaml_parse_(SEXP x, SEXP simplify, SEXP aliases, SEXP big_integers,
                   SEXP tags, SEXP duplicate_keys, SEXP max_depth,
                   SEXP max_size, SEXP max_nodes, SEXP path);

SEXP zuyaml_emit_(SEXP x, SEXP indent, SEXP width,
                  SEXP document_start, SEXP document_end);
```

`zuyaml_parse_()` always returns a list of documents. `yaml_parse()` is a thin R
wrapper that calls it and errors unless the list has length 1 (§5.2). Since both
R functions already share one C path (`cyaml_parse_stream`), a second entry point
would duplicate the argument marshalling for a check better expressed in R.

Argument validation — types, ranges, `match.arg()`, the `uint8_t` and `uint32_t`
ceilings — happens in R. C receives values it can trust and does not re-derive
policy.

Register everything in `init.c`:

```c
R_useDynamicSymbols(dll, FALSE);
R_forceSymbols(dll, TRUE);
```

Do not expose vendored `cyaml` functions as an R-facing C API in v0.1.

### 9.3 Unwind safety

**This is the most important C-level requirement in the document, and the easiest
to omit.**

R's error mechanism is a `longjmp`. Any of the following will unwind straight past
a `cyaml_stream_free()` placed at the end of a `.Call`, leaking the entire
document tree:

- `Rf_error()` — which §10 requires for structured parse errors;
- allocation failure inside `Rf_allocVector()` / `Rf_mkCharLenCE()`;
- `Rf_mkCharLenCE()` on a string containing an embedded NUL (§11);
- `R_CheckUserInterrupt()` during a long conversion;
- a user interrupt during any allocating call.

`PROTECT` discipline does not help here: `PROTECT` guards against the garbage
collector, not against unwinding.

**Mechanism.** Immediately after `cyaml_parse_stream()` succeeds, attach the
stream to a transient external pointer with a finalizer that calls
`cyaml_stream_free()`, and keep it protected for the duration of the call. On
normal return, free explicitly and clear the pointer; on an unwind, the finalizer
runs at GC and the memory is reclaimed. `R_UnwindProtect()` is an acceptable
alternative; the external pointer is simpler because it needs no continuation
function.

This does **not** contradict §4.2's "no persistent C document pointers". That rule
is about pointers *surviving a `.Call` and being handed to users*. This one is
function-scoped, never reaches R code, and exists solely so that errors are safe.
The distinction is worth stating explicitly because the two look alike in a
diff.

The same discipline applies to the emit path (`cyaml_doc_t` and the buffer
returned by `cyaml_emit()`) and to the `char*` from `cyaml_scalar_str()`, which
must not be live across any allocating R call.

### 9.4 Input ownership

Parsed cyaml documents **borrow** their source buffer:
`cyaml_stream_t.src` is documented as "borrowed, must outlive stream", and every
scalar is an offset into it. `cyaml_free()` and `cyaml_stream_free()` do not free
the source.

Within a single `.Call` this is straightforward:

1. obtain the UTF-8 bytes from the R input;
2. keep the input `SEXP` protected for the entire C call;
3. parse with `cyaml_parse_stream()`;
4. convert the tree to R objects;
5. free the stream (§9.3);
6. return.

A raw vector already provides contiguous bytes and needs no copy. A character
input needs `Rf_translateCharUTF8()`, whose result must be treated as valid only
until the next such call — copy it or use it immediately.

If a future `yaml_document()` returns a persistent external pointer (§20), the
source must outlive it: either copy the bytes into a C-owned allocation stored
with the document, or preserve the source `SEXP` inside the external pointer's
ownership structure. That complexity stays out of v0.1.

### 9.5 Conversion algorithm

```text
convert(node, depth, budget):
    depth  > max_depth  -> error
    budget exhausted    -> error

    CYAML_NONE   -> internal error
    CYAML_NULL   -> R_NilValue
    CYAML_SCALAR -> cyaml_scalar_kind() -> §6.2
    CYAML_SEQ    -> allocate VECSXP of cyaml_seq_len(); convert each; simplify?
    CYAML_MAP    -> iterate cyaml_map_at(); named VECSXP or zuyaml_map (§6.4)
    CYAML_ALIAS  -> resolve (cycle-guarded, budget-charged) or error
```

Allocate result containers once, when sizes are known — `cyaml_seq_len()` and
`cyaml_map_len()` are available up front. Never build results by repeated R-level
concatenation.

Use `PROTECT` around every allocation that may trigger the GC, and §9.3's
mechanism around everything that may unwind.

**Take the zero-copy path for plain scalars.** `cyaml_scalar_str()` mallocs and
copies for every scalar, and its result must be freed. It is only *necessary* for
styles that require processing — `CYAML_SINGLE`, `CYAML_DOUBLE`, `CYAML_LITERAL`,
`CYAML_FOLDED` — where escapes, line folding, and block-indent stripping apply.
For `CYAML_PLAIN` scalars, `cyaml_str()` and `cyaml_len()` give a pointer and
length directly into the source buffer, which feed `Rf_mkCharLenCE(..., CE_UTF8)`
with no intermediate allocation at all. Since plain scalars dominate real
documents, this removes most of the per-scalar malloc/free traffic and is the
first thing to measure in §18.

### 9.6 Memory behaviour

Peak parsing memory is approximately:

```text
input bytes + cyaml tree + resulting R object
```

Free the whole cyaml stream immediately after conversion. Never retain a C
document tree behind an ordinary R object.

---

## 10. Errors and conditions

Convert `cyaml_error_t` into an R condition with structured metadata.
`cyaml_error_t` carries `code`, a `span`, and a 128-byte `msg`; `cyaml_span_t`
carries `off`, `len`, and 1-based `start_line`, `start_col`, `end_line`,
`end_col`.

```r
conditionMessage(err)
err$code        # stable zuyaml string, not the raw enum value
err$line        # span.start_line
err$column      # span.start_col
err$end_line
err$end_column
err$path        # present only for file input
```

```r
c("zuyaml_parse_error", "zuyaml_error", "error", "condition")
```

```text
YAML parse error at line 7, column 5: duplicate mapping key
YAML parse error in 'config.yml' at line 7, column 5: duplicate mapping key
```

The message is composed by `zuyaml`, using upstream's `msg` and
`cyaml_strerror()` as inputs rather than passing either through verbatim — a
128-byte fixed buffer is an upstream implementation detail and may change wording
between versions. Do not expose raw `cyaml` structs to R.

### 10.1 Error-code mapping

Map every member of `cyaml_err_t` to a stable `zuyaml` code, so users never parse
message strings to discover a category:

| upstream | `err$code` |
|---|---|
| `CYAML_ERR_SYNTAX` | `"syntax"` |
| `CYAML_ERR_EOF` | `"eof"` |
| `CYAML_ERR_INDENT` | `"indent"` |
| `CYAML_ERR_ESCAPE` | `"escape"` |
| `CYAML_ERR_ANCHOR` | `"anchor"` |
| `CYAML_ERR_ALIAS` | `"alias"` |
| `CYAML_ERR_TAG` | `"tag"` |
| `CYAML_ERR_DUP_KEY` | `"duplicate_key"` — mapped, but never raised upstream at v0.1.3; `zuyaml` raises this code itself (§3.1, §6.4) |
| `CYAML_ERR_NOMEM` | `"memory"` |
| `CYAML_ERR_IO` | `"io"` |

`zuyaml` adds its own codes for conditions upstream does not raise:
`"too_many_documents"`, `"no_documents"`, `"alias_cycle"`, `"limit_depth"`,
`"limit_size"`, `"limit_nodes"`, `"embedded_nul"`, `"unsupported_tag"`,
`"unsupported_key"`, `"precision"`.

A new upstream error code appearing in a future version must fail loudly in the
mapping rather than fall through to a generic default.

---

## 11. Resource limits and hostile input

YAML parsers receive untrusted input, especially via `zuhttp`. Three limits, all
user-visible:

| argument | default | enforced by |
|---|---|---|
| `max_depth` | `128L` | **`zuyaml`**, during conversion |
| `max_size` | `64 * 1024^2` | **`zuyaml`**, before parsing |
| `max_nodes` | `1e6` | **`zuyaml`**, conversion budget |

**All three limits are ours.** cyaml declares `max_depth` and `max_size` and
reads neither (§3.1), so setting the upstream fields protects nothing. Passing
them through and assuming they work is the failure mode this table exists to
prevent:

- `max_size` is checked against the input length before the buffer is handed
  to the parser.
- `max_depth` is checked as the conversion recurses, which also bounds our own
  use of R's protection stack.
- `max_nodes` is charged as R nodes are materialised, including nodes produced
  by alias expansion (§11.1).

`CYAML_OPTS_DEFAULT` is `{ false, false, 1000, 0, CYAML_SPEC_AUTO }`. The
`spec` field is the one option that genuinely matters upstream, and pinning it
to `CYAML_SPEC_1_2` is load-bearing. Benchmark the numeric defaults against
legitimately large documents before release, but never ship unlimited by
accident.

### 11.1 Alias expansion

`max_depth` and `max_size` do **not** bound alias expansion. The classic
billion-laughs payload is ~200 bytes of source, roughly ten levels deep, and
expands to gigabytes:

```yaml
a: &a ["x","x","x","x","x","x","x","x","x"]
b: &b [*a,*a,*a,*a,*a,*a,*a,*a,*a]
c: &c [*b,*b,*b,*b,*b,*b,*b,*b,*b]
# ...
```

It passes both existing limits. This is why §6.5 resolves aliases during traversal
instead of calling `cyaml_resolve_aliases()`, which deep-copies the entire
expansion in C before `zuyaml` gets a say. `max_nodes` counts every materialised R
node, including nodes produced by alias expansion, and aborts as soon as the
budget is exhausted:

```text
YAML document exceeds the node limit (10000000); see max_nodes.
```

### 11.2 Other hard limits

**4 GiB ceiling.** `cyaml_span_t.off`/`len`, `cyaml_stream_t.src_len`, and
`cyaml_opts_t.max_size` are all `uint32_t`, even though `cyaml_parse_stream()`
takes a `size_t len`. R raw vectors can exceed 2^31 elements on 64-bit builds.
Reject input ≥ 4 GiB in R, up front, with a clear message — independently of
`max_size`, which the user may have raised.

**Embedded NUL.** `\0` is a valid escape in a YAML double-quoted scalar, so
`key: "\0"` is a legal document that produces a scalar containing a NUL byte. R
character strings cannot hold one: `Rf_mkCharLenCE()` errors, which is also an
unwind (§9.3). Detect this during conversion and raise a proper `"embedded_nul"`
condition rather than letting an R internal error escape.

**Also required:** validate every length conversion before narrowing to upstream's
integer widths; check every allocation result; keep R-side recursion bounded by
`max_depth` independently of upstream's check.

For `zuhttp`, body-size enforcement should happen before `zuyaml` is invoked
wherever possible.

---

## 12. Encoding

Treat YAML input and output as UTF-8.

For character input: translate to UTF-8 explicitly, and pass the byte length
rather than calling `strlen()` when R already knows it.

For output: create UTF-8-marked R strings with `Rf_mkCharLenCE(..., CE_UTF8)`;
never rely on the process locale. Use locale-independent numeric formatting
(§7.1).

File APIs read and write bytes.

---

## 13. Vendoring cyaml

Vendoring must be reproducible, and **must not be a plain copy** — two upstream
behaviours are incompatible with CRAN.

`inst/cyaml-VERSION` records at least:

```text
upstream: https://github.com/andrewmd5/cyaml
version:  v0.1.3
commit:   0672e81b809bc3dfd1d4f57ba0fcfbb20c60ae70
sha256:   <source archive checksum>
patches:  cyaml_internal.h (assertion macros)
```

### 13.1 What to copy

Only `src/` — the three submodules (`third-party/Unity`,
`refs/yaml-test-suite`, `refs/yaml-spec`) are test and reference material.

**All 8 `.c` files must be vendored**, including those implementing deferred
features. `cyaml.c` defines `cyaml_path()`, which calls `cyaml_path_first()` in
`cyaml_path.c`, and references `cyaml_is_json()`. Dropping the YPATH, JSON,
modify, or events translation units to save space would require patching
`cyaml.c`, which contradicts §13.3. Accept the dead code, and note it honestly in
§2 rather than claiming a smaller footprint than the package has.

### 13.2 Required patch: assertion macros

`cyaml_internal.h` defines, with the comment "Release-safe assertion macro —
always active":

```c
#define CYAML_ASSERT(cond, msg)   /* fprintf(stderr, ...); abort(); */
#define CYAML_UNREACHABLE(msg)    /* fprintf(stderr, ...); abort(); */
```

CRAN policy prohibits compiled code that calls `abort()` or writes to `stderr`;
either would take down the user's whole R session. There is one live use today, in
`cyaml_emitter.c`, but any upstream bump may add more.

The vendor script applies a single, narrowly-scoped patch redirecting both macros
to a `zuyaml_panic()` helper that calls `Rf_error()`. Accept that this leaks
whatever cyaml had allocated: the macros fire only on a library invariant
violation — a bug — and leaking on that path is vastly preferable to killing the
session. This patch is permanent and must be re-applied on every update; it is the
reason `patches:` exists in the version record.

### 13.3 Keep upstream recognisable

No cosmetic rewrites, no symbol renaming, no reformatting. Every change lives as
an explicit patch file listed in the version record, so that updating upstream
stays a mechanical operation.

### 13.4 Never vendor from `main`

Every release pins a tag or immutable commit. `tools/vendor-cyaml.sh` automates:
download and verify a specific tag, copy `src/*` into `src/`, apply the patch set,
retain the upstream license text, and update `inst/cyaml-VERSION`.

---

## 14. Portability and CRAN

The vendored source compiles as ordinary package C sources under R's build system.
Do not invoke upstream's CMake at install time, and do not rely on POSIX-only
APIs, platform-specific filesystem APIs, or generated code absent from the source
tarball.

### 14.1 Makevars

A `Makevars` **is** required, for one non-obvious reason:

```make
PKG_CPPFLAGS = -DCYAML_VERSION_STR=\"0.1.3\"
```

`cyaml_internal.h` falls back to `#define CYAML_VERSION_STR "0.0.0-dev"` when the
build does not supply it — upstream's CMake does. Without this flag,
`cyaml_version()` misreports the vendored version, which would undermine the
version-provenance testing in §16.

`Makevars.win` mirrors it. Keep both free of GNU-make-only constructs.

Never define `CYAML_DEBUG` or `CYAML_TRACE`: the 26 `printf()` calls in
`cyaml_path.c` are guarded by `#ifdef CYAML_DEBUG`, and `TRACE()` writes to
`stderr` when `CYAML_TRACE` is defined. Both are silent in a default build; a
stray `-D` would turn a passing package into a CRAN rejection.

### 14.2 C standard

Upstream is C11 and uses anonymous unions. No `Makevars` directive is expected to
be necessary: GCC ≥ 8 and Clang ≥ 16 default to `gnu17`, which subsumes C11.
Verify against the oldest R version the package supports before adding
`C_STD = C11`, since support for that variable is itself version-dependent.

### 14.3 Test matrix

Linux/GCC, Linux/Clang, macOS/Apple Clang, and the Windows toolchains used by
current R releases, under `R CMD check --as-cran`.

### 14.4 Symbol visibility (minor)

`CYAML_API` expands to `__attribute__((visibility("default")))` on non-Windows,
so the vendored symbols are exported from the shared object.
`R_useDynamicSymbols(dll, FALSE)` prevents R-level lookup but does not change ELF
exports. If this ever collides with another loaded DSO, defining `CYAML_API` to
nothing is the fix. Low priority; note it rather than pre-emptively patching.

---

## 15. Licensing

`cyaml` v0.1.3 is MIT licensed. The package must retain the upstream
copyright/license notice, include a vendored-code notice, record the exact
upstream source and version, and ensure `DESCRIPTION`'s `License` field
accurately reflects `zuyaml`'s own license. `inst/COPYRIGHTS` makes the vendored
component explicit.

---

## 16. Testing

Three layers.

### 16.1 R API tests

Ordinary behaviour, plus every case this design calls out:

- null, booleans, integers, floats, `NaN`/`Inf`, Unicode, quoted strings;
- the empty string (`""` must never become `NULL`) and the empty document;
- empty sequence, empty mapping, nested structures;
- **zero-, one-, and many-document streams** for all four `_all` pairs;
- duplicate keys, both rejected and opt-in;
- non-string scalar keys, stringification collisions, collection keys;
- big integers at 2^31, 2^53, `INT64_MAX`, beyond `INT64_MAX`, and hex/octal
  forms, under all three `big_integers` policies;
- anchors, aliases, alias cycles, and an **alias expansion bomb**;
- **numeric-looking strings** (`"42"`, `".inf"`, `"0x1F"`, `"true"`, `"null"`)
  surviving an emit/parse round trip — the §7.2 regression test;
- **`key: "\0"`** producing a clean `"embedded_nul"` error, not an R internal
  error;
- malformed YAML, deep nesting, and each of `max_depth`, `max_size`, `max_nodes`;
- `indent`/`width` at 0, 255, and 256 (the `uint8_t` boundary);
- `cyaml_version()` matching `inst/cyaml-VERSION` — catches a botched vendor
  update and a missing `-DCYAML_VERSION_STR`.

### 16.2 Round-trip tests

```text
R → YAML → R                 preserves the documented semantic value
YAML → R → YAML → R          preserves the R semantic representation
```

Byte-identical YAML output is **not** required. "Documented semantic value"
explicitly excludes everything in §8's table; those rows get their own tests
asserting the *documented* lossy behaviour, so that a future change to any of them
is a deliberate test update rather than a silent regression.

### 16.3 Upstream conformance

**In the package:** a curated yaml-test-suite subset covering scalars, flow and
block collections, escapes, directives, anchors, aliases, complex keys, invalid
documents, and any case previously associated with a wrapper bug. Keep CRAN test
time reasonable.

**In CI only:** the full upstream suite, validating both the vendored build and
the R conversion layer. Many suite cases assert an *event* stream, which `zuyaml`
deliberately does not expose (§3.1), so the R-level assertions are:

- every case marked valid parses without error, and every case marked invalid
  errors;
- for cases shipping an `in.json` equivalent, the parsed R object matches the
  JSON-derived expectation under the documented conversion rules.

Run the full suite whenever the vendored version changes.

---

## 17. Fuzzing and sanitizers

Upstream provides fuzzing harnesses; `zuyaml` adds wrapper-level fuzzing.

```text
arbitrary bytes → yaml_parse() → success OR controlled R error
```

It must never crash R, access invalid memory, leak on repeated failure paths, or
hang. The failure-path leak requirement is what §9.3 exists to satisfy, and the
fuzzer is what will find it if §9.3 is implemented carelessly — so fuzz the
*error* paths deliberately, including interrupt delivery mid-conversion.

CI outside CRAN runs AddressSanitizer, UndefinedBehaviorSanitizer, the upstream
fuzz targets, and wrapper property tests. The C boundary is where this package
should be unusually strict.

---

## 18. Benchmarks

Performance is not the reason to build `zuyaml`, but measurements guide
implementation. `tools/benchmark.R` compares against the R `yaml` package.

### First measurements (macOS, arm64, R 4.6.1)

| workload | parse vs `yaml` | emit vs `yaml` |
|---|---|---|
| small config | 0.64× | 1.66× |
| Kubernetes-style | 0.86× | 1.45× |
| 20k integers | 0.68× | 4.11× |
| 20k strings | 0.64× | 1.83× |
| deep nesting | 0.61× | 1.48× |
| 500 documents | 1.13× | — |

Installed size: **399 KB** against `yaml`'s 645 KB.

**`zuyaml` parses more slowly than `yaml` — roughly 0.6–0.9×** — and emits
1.5–4× faster. Multi-document streams are the one parsing case where it wins,
which makes sense: the stream API is the path the design optimises for.

This is stated plainly because §2's value proposition is architectural, not
performance-based. **No performance claim belongs in the README or
`DESCRIPTION`**, and certainly not a speed claim for parsing.

### Where the time goes

Comparing documents of equal size but very different scalar counts separates
the engine from R allocation:

| workload | input | time |
|---|---|---|
| 20,000 tiny scalars | 145 KB | 7.95 ms |
| 20 large scalars | 98 KB | 1.27 ms |

Per byte, the many-small-scalars case costs about **4× more**. The bottleneck is
allocating R objects, not parsing YAML — which is what §9.5's zero-copy plain
scalar path exists to reduce, and confirms that further optimisation belongs on
the R-allocation side rather than in the parser. Closing the gap with `yaml`
would mean reducing per-scalar `SEXP` allocation, not faster parsing.

---

## 19. zuhttp integration

`zuyaml` remains fully usable without `zuhttp`. `zuhttp` may use it for response
bodies with media types such as `application/yaml`, `application/x-yaml`,
`text/yaml`, and vendor-specific structured suffixes.

```r
response_body_yaml <- function(response) {
  zuyaml::yaml_parse(response_body_raw(response))
}
```

| `zuhttp` owns | `zuyaml` owns |
|---|---|
| HTTP transfer, decompression | YAML syntax and semantics |
| Content-length and body limits | Conversion to R |
| Charset and media-type interpretation | YAML parse errors |
| Deciding a body is YAML | Resource limits during parsing |

`zuyaml` never knows about HTTP response objects.

---

## 20. Future: a document API

If demand appears for YPATH, comment preservation, mutation, or
formatting-preserving round trips, introduce a *separate* document abstraction
rather than complicating `yaml_parse()`:

```r
doc <- yaml_document(x)
yaml_query(doc, "/server/host")
yaml_query(doc, "/users[?@.active]/name")
yaml_set(doc, "/server/port", 8081L)
yaml_emit_document(doc, preserve_style = TRUE)
```

Internally this retains a `cyaml_doc_t`, and must solve source-buffer ownership,
external-pointer finalization, mutation safety, alias identity, preserved
comments, tags, fork behaviour, and invalidation after finalization.

YPATH belongs here specifically. Running YPATH against a document that has already
been fully converted to R would add a second object model for no benefit — its
value depends entirely on a retained document. Do not wrap it merely because it
exists.

---

## 21. Key decisions

| Question | Decision |
|---|---|
| YAML engine | vendored `andrewmd5/cyaml` |
| Baseline | pinned v0.1.3 (`0672e81`) |
| Native language / interface | C11, direct `.Call` |
| `Rcpp` / `cpp11` | no |
| YAML version | explicit 1.2 (upstream default is auto) |
| Parser representation | cyaml document tree |
| Streaming/SAX API | no — upstream has no streaming parser |
| Multi-document streams | explicit `_all` variants |
| Vendored file layout | flat in `src/`, no `OBJECTS` list |
| Native entry points | 2 (`parse`, `emit`) |
| Argument validation | in R, not C |
| Unwind safety | transient external pointer + finalizer |
| Sequences | list; `simplify = FALSE` by default |
| Scalar-key maps | named list, keys stringified |
| Collection-key maps | `zuyaml_map`, parse only |
| Duplicate keys | reject by default (zuyaml-enforced); parse only when enabled |
| Aliases | resolve during traversal, budgeted |
| Alias cycles / bombs | error / `max_nodes` |
| Resource limits | all three enforced by zuyaml, not cyaml |
| Large integers | never silently lose precision; `zuyaml_bigint` |
| Emit scalar style | chosen by `zuyaml`, not left to upstream |
| `NA` | `null`, documented as lossy |
| Comments/style | not preserved by the object API |
| Unknown custom tags | error |
| Persistent C pointers | no |
| YPATH | deferred to a document API |
| HTTP knowledge | none |
| Runtime dependencies | none beyond R |
| Conformance suite | curated subset on CRAN, full suite in CI |

---

## 22. Open questions

Two of these have now been settled; the rest remain open until the API freezes.

1. **`simplify = FALSE` as the default** (§6.3). **Settled: keep `FALSE`.**
   Consistency with the rest of the design won over matching the `yaml`
   package. The shape of the result never depends on the contents of the
   document, and `simplify = TRUE` remains one argument away.
2. **Stringifying non-string scalar keys** (§6.4). The strict alternative — any
   non-string key produces a `zuyaml_map` — is more faithful but makes `{1: a}`
   return an exotic class. Current choice favours ergonomics.
3. **Eight exported functions versus five** (§5). The `_all` variants of `emit`
   and `write` are cheap and make the rule uniform, but they exist to complete a
   pattern rather than to satisfy a demonstrated need.
4. **`zuyaml_bigint` as public API** (§6.2). Once users receive it, its
   representation is a compatibility surface. An alternative is defaulting
   `big_integers = "error"` and shipping no class at all in v0.1.
5. **`max_nodes`** (§11.1). **Settled: `1e6`.** Measurement decided it. A
   20,000-element sequence is 20,000 nodes, so even a very large manifest sits
   ~50× below the limit, while the worst case for a sub-300-byte hostile input
   drops roughly tenfold — from ~0.9s and a few hundred MB to about a tenth of
   that. The old `1e7` bought headroom no real document needed.
6. **Whether `zuyaml_map` should exist in v0.1 at all** (§6.4). It cannot be
   emitted, so it is a parse-only asymmetry; erroring on collection keys would be
   simpler, at the cost of failing on documents `cyaml` handles fine.

---

## 23. References

Design assumptions must be re-validated whenever the vendored version changes:

- cyaml project: <https://cyaml.org/>
- cyaml API (v0.1.3): <https://cyaml.org/v0.1.3/api/>
- upstream repository: <https://github.com/andrewmd5/cyaml>
- yaml-test-suite: <https://github.com/yaml/yaml-test-suite>
- YAML 1.2.2 specification: <https://yaml.org/spec/1.2.2/>
- Writing R Extensions: <https://cran.r-project.org/doc/manuals/R-exts.html>

The **vendored source** — not the live documentation — is authoritative for each
release. The verification note at the top of this document lists what was checked
and where; repeat it on every upstream bump.

---

## Appendix: initial contract

> `zuyaml` converts between YAML 1.2 and ordinary R objects using a small vendored
> C11 parser/emitter, with strict handling of ambiguous YAML features and no
> runtime dependencies beyond R.

The implementation should stay close to that sentence.
