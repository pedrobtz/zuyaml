# Semantic conformance: what a document parses *to*.
#
# test-conformance.R checks that the right documents are accepted and rejected.
# That says nothing about the values produced. This file compares the parsed
# object against `in.json` -- the suite's own rendering of the same document --
# which is an external reference rather than the package's own expectations.
#
# It is worth the trouble. Writing this comparison found three real conversion
# bugs that the accept/reject tests could not have caught:
#
#   * multi-line plain scalars were not line-folded, because the zero-copy path
#     returned the raw span verbatim;
#   * empty block scalars came back as NULL instead of "";
#   * an alias used as a mapping key turned the whole mapping into a
#     zuyaml_map;
#   * tags were ignored entirely, so `!!str 12` gave the integer 12;
#   * a %TAG directive redefining `!!` was not honoured, so `!!int 1 - 3`
#     became a zuyaml_bigint holding "1 - 3".
#
# Two allowances are made for JSON's own limits (number typing and key order),
# and one construct differs by design. That one is listed in
# `expected_mismatch` below, so this file records exactly where the package and
# the reference part company, and why.

skip_if_not_installed("jsonlite")

suite_root_semantic <- function() {
  from_env <- Sys.getenv("ZUYAML_TEST_SUITE", "")
  if (nzchar(from_env) && dir.exists(from_env)) {
    return(from_env)
  }
  testthat::test_path("fixtures", "yaml-test-suite")
}

# JSON has one number type, so it cannot distinguish 450 from 450.00 -- both
# arrive as an R integer even though YAML resolves the latter as a float.
# Numbers are therefore compared by value, not by storage type.
#
# JSON objects are unordered, so key order is not meaningful either. zuyaml
# preserves document order, which is right, but it cannot be checked here.
normalise <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  if (is.list(x)) {
    if (!is.null(names(x)) && length(x)) {
      x <- x[order(names(x))]
    }
    return(lapply(x, normalise))
  }
  if (is.numeric(x)) {
    return(as.double(x))
  }
  x
}

# Cases where the package deliberately differs from the suite's JSON.
expected_mismatch <- c(
  # JSON cannot express a mapping whose key is a sequence, so the reference
  # flattens it. zuyaml_map preserves the structure instead, which is strictly
  # more faithful -- see the design's mapping section.
  "WZ62"
)

semantic_cases <- function() {
  root <- suite_root_semantic()
  if (!dir.exists(root)) {
    return(NULL)
  }
  inputs <- list.files(root, pattern = "^in\\.yaml$", recursive = TRUE,
                       full.names = TRUE)
  dirs <- dirname(inputs)
  dirs <- dirs[!grepl("(^|/)name/", dirs)]
  dirs <- unique(dirs[file.exists(file.path(dirs, "in.json")) &
                        !file.exists(file.path(dirs, "error"))])
  dirs
}

test_that("parsed values match the suite's own JSON rendering", {
  dirs <- semantic_cases()
  skip_if(is.null(dirs) || length(dirs) == 0L, "no JSON references available")

  compared <- 0L
  wrong <- character()

  for (d in dirs) {
    id <- basename(d)
    yaml_file <- file.path(d, "in.yaml")

    docs <- tryCatch(
      yaml_parse_all(readBin(yaml_file, "raw", file.info(yaml_file)$size),
                     max_nodes = 1e6),
      error = function(e) NULL
    )
    if (is.null(docs)) next

    # A stream's in.json holds one JSON value per document, concatenated and
    # pretty-printed. Splitting that reliably needs an incremental parser, so
    # only single-document cases are compared.
    if (length(docs) != 1L) next

    reference <- tryCatch(
      jsonlite::fromJSON(
        paste(readLines(file.path(d, "in.json"), warn = FALSE), collapse = "\n"),
        simplifyVector = FALSE
      ),
      error = function(e) NULL
    )
    if (is.null(reference)) next

    compared <- compared + 1L
    agrees <- identical(normalise(docs[[1]]), normalise(reference))

    if (id %in% expected_mismatch) {
      # Listed as a known difference. If it starts agreeing, the note above is
      # stale and should be removed.
      if (agrees) {
        wrong <- c(wrong, sprintf(
          "%s now agrees with the reference; remove it from expected_mismatch",
          id
        ))
      }
    } else if (!agrees) {
      wrong <- c(wrong, sprintf(
        "%s: got %s, reference %s", id,
        substr(paste(deparse(docs[[1]]), collapse = " "), 1, 90),
        substr(paste(deparse(reference), collapse = " "), 1, 90)
      ))
    }
  }

  expect_gt(compared, 10L)
  expect_identical(wrong, character(), info = paste(wrong, collapse = "\n"))
})

# The bugs this comparison found, pinned directly so they cannot regress
# quietly if the fixtures are ever re-curated.

test_that("multi-line plain scalars are folded", {
  # A plain scalar may span lines, and YAML folds the breaks into spaces. The
  # zero-copy path must not return the raw span for these.
  expect_identical(
    yaml_parse("plain: This unquoted scalar\n  spans two lines\n"),
    list(plain = "This unquoted scalar spans two lines")
  )
  expect_identical(yaml_parse("a: b\n c\n"), list(a = "b c"))

  # A blank line inside a plain scalar folds to a newline, not a space.
  expect_identical(yaml_parse("a: b\n\n c\n"), list(a = "b\nc"))

  # Single-line plain scalars still take the zero-copy path unchanged.
  expect_identical(yaml_parse("a: hello world\n"), list(a = "hello world"))
})

test_that("empty block scalars are strings, not NULL", {
  # Only *plain* scalars are resolved against the schema. A block scalar is a
  # string however empty it is.
  expect_identical(
    yaml_parse("strip: >-\n\nclip: >\n\nkeep: |+\n\n"),
    list(strip = "", clip = "", keep = "\n")
  )
  expect_identical(yaml_parse("a: |\n"), list(a = ""))
})

test_that("an alias may be a mapping key", {
  # The key is an alias node, but it resolves to a scalar, so the mapping is
  # an ordinary named list rather than a zuyaml_map.
  x <- yaml_parse("top: &a key\nmap:\n  *a : value\n")
  expect_false(inherits(x$map, "zuyaml_map"))
  expect_identical(x$map, list(key = "value"))
})

test_that("tags override schema resolution", {
  # A tag decides the type, whatever the text looks like.
  expect_identical(yaml_parse("!!str 12"), "12")
  expect_identical(yaml_parse("! 12"), "12") # non-specific tag
  expect_identical(yaml_parse('!!int "12"'), 12L)
  expect_identical(yaml_parse('!!bool "true"'), TRUE)
  expect_identical(yaml_parse("!!float 1"), 1)
  expect_null(yaml_parse("!!null anything"))

  # An empty tagged node is still tagged: cyaml represents it as a null node,
  # so the tag must be consulted before defaulting to NULL.
  expect_identical(yaml_parse("- !!str\n"), list(""))

  # Untagged resolution is unaffected.
  expect_identical(yaml_parse("12"), 12L)
})

test_that("a %TAG directive redefining a handle is honoured", {
  # `%TAG !! ...` makes !!int an application tag, not the core integer tag, so
  # this interval stays a string rather than becoming a bigint.
  expect_identical(
    yaml_parse("%TAG !! tag:example.com,2000:app/\n---\n!!int 1 - 3\n"),
    "1 - 3"
  )
})

test_that("application tags are ignored by default and can be refused", {
  # Rejecting by default would refuse a great deal of ordinary YAML: more than
  # twenty documents in the upstream suite carry application tags and are
  # valid.
  expect_identical(yaml_parse("v: !duration 5m"), list(v = "5m"))

  err <- tryCatch(
    yaml_parse("v: !duration 5m", tags = "error"),
    zuyaml_error = identity
  )
  expect_identical(err$code, "unsupported_tag")
  expect_match(conditionMessage(err), "!duration")
  expect_match(conditionMessage(err), "line [0-9]+, column [0-9]+")

  # Core tags are never "unsupported", whatever the policy.
  expect_identical(yaml_parse("!!str 12", tags = "error"), "12")
})

test_that("an explicit int tag on non-integer text does not become a bigint", {
  # The bigint fallback exists for integers beyond uint64, and must not be
  # reached by text that is not an integer at all.
  expect_identical(yaml_parse("!!int 1 - 3"), "1 - 3")
  expect_false(inherits(yaml_parse("!!int nonsense"), "zuyaml_bigint"))
})
