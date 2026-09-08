# Wrapper-level fuzzing.
#
#     arbitrary bytes -> yaml_parse() -> a value OR a controlled R condition
#
# It must never crash R, read invalid memory, leak on repeated failure paths,
# or hang. Upstream fuzzes the parser itself; what is fuzzed here is the
# wrapping -- and in particular the *error* paths, since an R error is a
# longjmp that skips the explicit free and leaves the finalizer to reclaim the
# stream.
#
# Iterations are deliberately small by default so this stays reasonable on
# CRAN. CI raises it via ZUYAML_FUZZ, and runs the same tests again under
# AddressSanitizer, where a leak on the error path becomes visible.

fuzz_iterations <- function(default = 200L) {
  n <- suppressWarnings(as.integer(Sys.getenv("ZUYAML_FUZZ", "")))
  if (is.na(n) || n <= 0L) default else n
}

parse_quietly <- function(bytes) {
  tryCatch(
    {
      yaml_parse_all(bytes, max_depth = 64, max_nodes = 1e5)
      "ok"
    },
    zuyaml_error = function(e) "condition",
    error = function(e) paste0("bare R error: ", conditionMessage(e))
  )
}

test_that("random bytes never escape as anything but a condition", {
  set.seed(20260908L)
  n <- fuzz_iterations()
  bad <- character()

  for (i in seq_len(n)) {
    len <- sample.int(120L, 1L)
    bytes <- as.raw(sample.int(256L, len, replace = TRUE) - 1L)
    outcome <- parse_quietly(bytes)
    if (!outcome %in% c("ok", "condition")) {
      bad <- c(bad, sprintf("%s on %s", outcome,
                            paste(bytes, collapse = " ")))
    }
  }

  expect_identical(bad, character(), info = paste(head(bad, 5), collapse = "\n"))
})

test_that("structured but hostile input stays controlled", {
  # Random bytes rarely reach the interesting code paths, so these are built
  # out of YAML's own syntax: the fragments most likely to confuse a parser or
  # the conversion layer behind it.
  set.seed(20260908L)
  pieces <- c(
    "- ", "? ", ": ", "[", "]", "{", "}", "&a ", "*a ", "!!str ", "!tag ",
    "---\n", "...\n", "%YAML 1.2\n", "#c\n", "\"", "'", "|", ">", "\\",
    "\n", "  ", "\t", ",", "a", "1", "true", "null", "~", ": :", "0x", ".inf",
    "é", "\U0001F600", "@", "`"
  )
  n <- fuzz_iterations()
  bad <- character()

  for (i in seq_len(n)) {
    src <- paste(sample(pieces, sample.int(40L, 1L), replace = TRUE),
                 collapse = "")
    outcome <- parse_quietly(charToRaw(src))
    if (!outcome %in% c("ok", "condition")) {
      bad <- c(bad, sprintf("%s on %s", outcome, encodeString(src, quote = '"')))
    }
  }

  expect_identical(bad, character(), info = paste(head(bad, 5), collapse = "\n"))
})

test_that("truncation of valid documents stays controlled", {
  # Truncated input is what an interrupted HTTP body looks like, and it drives
  # the parser into states a well-formed document never reaches.
  valid <- paste0(
    "apiVersion: v1\n",
    "metadata:\n  name: x\n  labels:\n    app: \"web\"\n",
    "items:\n  - &a {a: 1, b: [1, 2]}\n  - *a\n",
    "block: |\n  line one\n  line two\n"
  )
  bytes <- charToRaw(valid)
  bad <- character()

  for (i in seq_along(bytes)) {
    outcome <- parse_quietly(bytes[seq_len(i)])
    if (!outcome %in% c("ok", "condition")) {
      bad <- c(bad, sprintf("truncated at %d: %s", i, outcome))
    }
  }

  expect_identical(bad, character(), info = paste(head(bad, 5), collapse = "\n"))
})

test_that("repeated failures do not accumulate memory", {
  # Every iteration raises an error while the cyaml stream is still alive, so
  # the explicit free is skipped and the finalizer has to reclaim it. Under
  # ASan a leak here is reported directly; without it, a growing heap is the
  # only signal available.
  gc()
  before <- sum(gc()[, 1])

  for (i in seq_len(2000L)) {
    expect_error(yaml_parse("a: 1\na: 2\n"), class = "zuyaml_error")
  }

  gc()
  after <- sum(gc()[, 1])

  # Generous: this is looking for unbounded growth, not ordinary churn.
  expect_lt(after, before * 3 + 1e5)
})
