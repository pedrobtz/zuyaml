#!/usr/bin/env Rscript
#
# Run the *full* yaml-test-suite and report, rather than assert.
#
# What this is for, and why it is not in tests/: the package ships a curated
# subset so CRAN test time stays reasonable, and `tests/` asserts a pass/fail
# outcome. This runs every case in an upstream checkout, prints counts per
# boundary, names each failure, and compares the result against a pinned
# baseline so that drift is visible in CI without a test having to encode a
# number that will change.
#
# Four boundaries, and a different suite artifact pins each:
#
#   accept/reject   the `error` marker     — text to a verdict
#   semantics       `in.json`              — text to an R *value*
#   round trip      (needs no artifact)    — R value to text and back
#   emit/refuse     (needs no artifact)    — every refusal is a condition
#
# `out.yaml` is deliberately not used. It is the suite's own re-serialisation
# and encodes block-versus-flow and quoting choices the package explicitly does
# not commit to, so diffing text against it would fail on style constantly and
# on meaning never. `test.event` is unused until tags are preserved (M8), when
# its `<tag:...>` tokens become a ready-made external reference for them.
#
# Usage:
#   tools/fetch-yaml-test-suite.sh /tmp/yaml-test-suite
#   Rscript tools/conformance.R /tmp/yaml-test-suite
#
# Exits 1 when anything fails or when the counts have moved away from the
# baseline below.

args <- commandArgs(trailingOnly = TRUE)
suite <- if (length(args) >= 1L && nzchar(args[[1]])) {
  args[[1]]
} else {
  Sys.getenv("ZUYAML_TEST_SUITE", "")
}
if (!nzchar(suite) || !dir.exists(suite)) {
  stop("usage: conformance.R <suite-dir>   (or set ZUYAML_TEST_SUITE)")
}

if (requireNamespace("devtools", quietly = TRUE)) {
  devtools::load_all(".", quiet = TRUE)
} else {
  library(zuyaml)
}
has_json <- requireNamespace("jsonlite", quietly = TRUE)

# --- baseline --------------------------------------------------------------
#
# Update deliberately, in the same commit as whatever changed the numbers, and
# say why in the commit message. A silent edit here defeats the purpose.
#
# Recorded 2026-09-14 against the yaml-test-suite `data` branch, with
# zuyaml 0.1.0: 402 cases (308 valid, 94 invalid), 279 with a JSON reference,
# 280 emittable and 28 refused on emit by design.
baseline <- list(
  cases = 402L,
  verdict_wrong = 0L,
  semantic_disagree = 1L, # WZ62: JSON cannot express a sequence-valued key
  round_trip_wrong = 0L,
  bare_errors = 0L
)

# --- cases -----------------------------------------------------------------

leaves <- dirname(list.files(suite, pattern = "^in\\.yaml$", recursive = TRUE,
                             full.names = TRUE))
# A checkout re-exposes every case under name/ (by description) and tags/ (by
# category) as symlink trees, which list.files() follows. Without this the
# counts are roughly four times the real number of cases.
leaves <- unique(leaves[!grepl("(^|/)(name|tags)/", leaves)])
if (length(leaves) == 0L) {
  stop("no cases found under ", suite)
}

describe <- function(d) {
  f <- file.path(d, "===")
  if (file.exists(f)) readLines(f, n = 1L, warn = FALSE) else ""
}

read_raw <- function(path) readBin(path, "raw", n = file.info(path)$size)

# JSON has one number type and unordered objects, so numbers are compared by
# value and keys by sorted order. Same rule as test-conformance-semantic.R.
normalise <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  if (is.list(x)) {
    if (!is.null(names(x)) && length(x)) x <- x[order(names(x))]
    return(lapply(x, normalise))
  }
  if (is.numeric(x)) {
    return(as.double(x))
  }
  x
}

# A stream's in.json is one JSON value per document, concatenated; jsonlite has
# no incremental reader, so accumulate lines and retry.
read_json_stream <- function(txt) {
  one <- function(s) {
    tryCatch(list(jsonlite::fromJSON(s, simplifyVector = FALSE)),
             error = function(e) NULL)
  }
  whole <- one(txt)
  if (!is.null(whole)) {
    return(whole)
  }
  out <- list()
  buffer <- character()
  for (line in strsplit(txt, "\n", fixed = TRUE)[[1]]) {
    buffer <- c(buffer, line)
    value <- one(paste(buffer, collapse = "\n"))
    if (!is.null(value)) {
      out <- c(out, value)
      buffer <- character()
    }
  }
  if (any(nzchar(trimws(buffer)))) NULL else out
}

# --- run -------------------------------------------------------------------

counts <- list(
  cases = length(leaves), valid = 0L, invalid = 0L,
  verdict_ok = 0L, semantic_ok = 0L, semantic_compared = 0L,
  round_trip_ok = 0L, round_trip_checked = 0L, emit_refused = 0L
)
verdict_wrong <- character()
semantic_disagree <- character()
round_trip_wrong <- character()
bare_errors <- character()

for (d in leaves) {
  id <- basename(d)
  label <- sprintf("%s (%s)", id, describe(d))
  should_fail <- file.exists(file.path(d, "error"))
  counts[[if (should_fail) "invalid" else "valid"]] <-
    counts[[if (should_fail) "invalid" else "valid"]] + 1L

  bytes <- read_raw(file.path(d, "in.yaml"))

  docs <- tryCatch(
    yaml_parse_all(bytes, max_nodes = 1e6),
    zuyaml_error = function(e) e,
    error = function(e) {
      bare_errors <<- c(bare_errors,
                        sprintf("%s: %s", label, conditionMessage(e)))
      e
    }
  )
  errored <- inherits(docs, "condition")

  if (errored == should_fail) {
    counts$verdict_ok <- counts$verdict_ok + 1L
  } else {
    verdict_wrong <- c(verdict_wrong, sprintf(
      "%s: expected %s", label, if (should_fail) "error" else "success"
    ))
  }
  if (errored) next

  # --- semantics, against in.json
  json_file <- file.path(d, "in.json")
  if (has_json && file.exists(json_file)) {
    txt <- rawToChar(read_raw(json_file))
    Encoding(txt) <- "UTF-8"
    reference <- read_json_stream(txt)
    if (!is.null(reference) && length(reference) == length(docs)) {
      counts$semantic_compared <- counts$semantic_compared + 1L
      if (identical(normalise(docs), normalise(reference))) {
        counts$semantic_ok <- counts$semantic_ok + 1L
      } else {
        semantic_disagree <- c(semantic_disagree, label)
      }
    }
  }

  # --- round trip: R value -> text -> R value
  text <- tryCatch(
    yaml_emit_all(docs),
    zuyaml_error = function(e) NULL,
    error = function(e) {
      bare_errors <<- c(bare_errors,
                        sprintf("%s: emit: %s", label, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(text)) {
    counts$emit_refused <- counts$emit_refused + 1L
    next
  }

  counts$round_trip_checked <- counts$round_trip_checked + 1L
  back <- tryCatch(yaml_parse_all(text, max_nodes = 1e6),
                   error = function(e) e)
  if (inherits(back, "condition")) {
    round_trip_wrong <- c(round_trip_wrong, sprintf(
      "%s: emitted YAML does not parse: %s", label, conditionMessage(back)
    ))
  } else if (!identical(docs, back)) {
    round_trip_wrong <- c(round_trip_wrong,
                          sprintf("%s: value changed on round trip", label))
  } else {
    counts$round_trip_ok <- counts$round_trip_ok + 1L
  }
}

# --- report ----------------------------------------------------------------

rule <- function() cat(strrep("-", 68), "\n")

cat("\nyaml-test-suite conformance\n")
cat("  suite:  ", normalizePath(suite), "\n", sep = "")
cat("  cyaml:  ", zuyaml:::cyaml_version(), "\n", sep = "")
rule()
cat(sprintf("  cases                  %6d  (%d valid, %d invalid)\n",
            counts$cases, counts$valid, counts$invalid))
cat(sprintf("  accept/reject          %6d / %d\n",
            counts$verdict_ok, counts$cases))
cat(sprintf("  semantics vs in.json   %6d / %d\n",
            counts$semantic_ok, counts$semantic_compared))
cat(sprintf("  round trip             %6d / %d   (%d refused on emit)\n",
            counts$round_trip_ok, counts$round_trip_checked,
            counts$emit_refused))
rule()

report <- function(title, items) {
  if (length(items) == 0L) {
    return(invisible())
  }
  cat(sprintf("\n%s (%d):\n", title, length(items)))
  cat(paste0("  - ", items, collapse = "\n"), "\n")
}

report("Wrong verdict", verdict_wrong)
report("Semantic disagreement", semantic_disagree)
report("Round-trip failure", round_trip_wrong)
report("Bare R error escaping from C", bare_errors)

if (!has_json) {
  cat("\nNote: jsonlite is not installed; semantics were not compared.\n")
}

# --- baseline comparison ---------------------------------------------------

observed <- list(
  cases = counts$cases,
  verdict_wrong = length(verdict_wrong),
  semantic_disagree = length(semantic_disagree),
  round_trip_wrong = length(round_trip_wrong),
  bare_errors = length(bare_errors)
)

drift <- character()
for (nm in names(baseline)) {
  if (!identical(as.integer(observed[[nm]]), as.integer(baseline[[nm]]))) {
    drift <- c(drift, sprintf("  %-20s baseline %d, now %d", nm,
                              baseline[[nm]], observed[[nm]]))
  }
}

if (length(drift)) {
  cat("\nDrift from the pinned baseline:\n")
  cat(paste(drift, collapse = "\n"), "\n")
  cat("\nIf the change is intended, update `baseline` in this file in the\n")
  cat("same commit, and say why in the commit message.\n")
} else {
  cat("\nMatches the pinned baseline.\n")
}

failed <- length(verdict_wrong) > 0L || length(round_trip_wrong) > 0L ||
  length(bare_errors) > 0L || length(drift) > 0L
quit(status = if (failed) 1L else 0L)
