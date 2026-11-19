# Helpers for test-conformance.R, kept out of it so that the file's tests can run in
# any order: devtools::test(shuffle = TRUE) shuffles top-level expressions,
# and a test shuffled ahead of a file-scope definition cannot find it.

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
  # A full checkout exposes every case again under name/ (keyed by its
  # description) and again under tags/ (keyed by category), both as symlink
  # trees that list.files() follows. Skipping them turns 1,552 leaf paths back
  # into the 402 real cases; the paths are also long enough to be awkward.
  dirs <- dirs[!grepl("(^|/)(name|tags)/", dirs)]
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
