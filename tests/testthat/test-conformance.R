# Conformance against the upstream yaml-test-suite.
#
# The package ships a curated subset (tools/curate-test-suite.R) so that CRAN
# test time stays reasonable. Point ZUYAML_TEST_SUITE at a full checkout to run
# all of it instead:
#
#   tools/fetch-yaml-test-suite.sh /tmp/yaml-test-suite
#   ZUYAML_TEST_SUITE=/tmp/yaml-test-suite R -e 'testthat::test_local(".")'
#
# What these tests are for: cyaml's own conformance is upstream's business, and
# is already covered by upstream's test runner. What matters here is that
# *wrapping* it does not destroy correctness -- that every case produces either
# a value or a proper zuyaml condition, and never a crash, a hang, or a bare R
# error escaping from C.

suite_root <- function() {
  from_env <- Sys.getenv("ZUYAML_TEST_SUITE", "")
  if (nzchar(from_env) && dir.exists(from_env)) {
    return(from_env)
  }
  testthat::test_path("fixtures", "yaml-test-suite")
}

suite_cases <- function() {
  root <- suite_root()
  if (!dir.exists(root)) {
    return(NULL)
  }
  # A case identifier may hold in.yaml directly, or numbered subdirectories
  # when one identifier covers several related inputs.
  inputs <- list.files(root, pattern = "^in\\.yaml$", recursive = TRUE,
                       full.names = TRUE)
  dirs <- dirname(inputs)
  # A full checkout exposes every case a second time under name/, keyed by its
  # description. Skip those: they are duplicates, and their paths are long.
  dirs <- dirs[!grepl("(^|/)name/", dirs)]
  data.frame(
    id = basename(dirs),
    dir = dirs,
    should_fail = file.exists(file.path(dirs, "error")),
    stringsAsFactors = FALSE
  )
}

describe_case <- function(dir) {
  f <- file.path(dir, "===")
  if (file.exists(f)) readLines(f, n = 1L, warn = FALSE) else ""
}

test_that("the test-suite fixtures are present", {
  cases <- suite_cases()
  expect_false(is.null(cases))
  expect_gt(nrow(cases), 20L)
  # Invalid documents are the interesting half; a subset of only valid ones
  # would not exercise the error paths at all.
  expect_gt(sum(cases$should_fail), 5L)
})

test_that("every case yields a value or a zuyaml condition, never a crash", {
  cases <- suite_cases()
  skip_if(is.null(cases), "no test suite available")

  bad <- character()

  for (i in seq_len(nrow(cases))) {
    path <- file.path(cases$dir[i], "in.yaml")
    bytes <- readBin(path, "raw", n = file.info(path)$size)

    outcome <- tryCatch(
      {
        yaml_parse_all(bytes, max_nodes = 1e6)
        "ok"
      },
      zuyaml_error = function(e) "condition",
      error = function(e) paste0("bare R error: ", conditionMessage(e))
    )

    if (!outcome %in% c("ok", "condition")) {
      bad <- c(bad, sprintf("%s (%s): %s", cases$id[i],
                            describe_case(cases$dir[i]), outcome))
    }
  }

  expect_identical(bad, character(), info = paste(bad, collapse = "\n"))
})

test_that("valid documents parse and invalid documents are rejected", {
  cases <- suite_cases()
  skip_if(is.null(cases), "no test suite available")

  wrong <- character()

  for (i in seq_len(nrow(cases))) {
    path <- file.path(cases$dir[i], "in.yaml")
    bytes <- readBin(path, "raw", n = file.info(path)$size)

    errored <- tryCatch(
      {
        yaml_parse_all(bytes, max_nodes = 1e6)
        FALSE
      },
      error = function(e) TRUE
    )

    if (errored != cases$should_fail[i]) {
      wrong <- c(wrong, sprintf(
        "%s (%s): expected %s, got %s",
        cases$id[i], describe_case(cases$dir[i]),
        if (cases$should_fail[i]) "error" else "success",
        if (errored) "error" else "success"
      ))
    }
  }

  expect_identical(wrong, character(), info = paste(wrong, collapse = "\n"))
})

test_that("anything that parses can be emitted or refused deliberately", {
  # Emission is narrower than parsing by design: complex keys and duplicate
  # names are parse-only. Every such refusal must still be a zuyaml condition
  # rather than an internal failure.
  cases <- suite_cases()
  skip_if(is.null(cases), "no test suite available")

  bad <- character()

  for (i in seq_len(nrow(cases))) {
    if (cases$should_fail[i]) next
    path <- file.path(cases$dir[i], "in.yaml")
    bytes <- readBin(path, "raw", n = file.info(path)$size)

    docs <- tryCatch(yaml_parse_all(bytes, max_nodes = 1e6), error = function(e) NULL)
    if (is.null(docs)) next

    outcome <- tryCatch(
      {
        yaml_emit_all(docs)
        "ok"
      },
      zuyaml_error = function(e) "condition",
      error = function(e) paste0("bare R error: ", conditionMessage(e))
    )

    if (!outcome %in% c("ok", "condition")) {
      bad <- c(bad, sprintf("%s: %s", cases$id[i], outcome))
    }
  }

  expect_identical(bad, character(), info = paste(bad, collapse = "\n"))
})
