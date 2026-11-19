# Helpers for test-conformance-semantic.R, kept out of it so that the file's tests can run in
# any order: devtools::test(shuffle = TRUE) shuffles top-level expressions,
# and a test shuffled ahead of a file-scope definition cannot find it.

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
# Fixture directories are named either by the bare suite id ("WZ62") or with a
# descriptive prefix ("tags-unknown-tag-P76L"), depending on how the fixture
# was curated. Matching on the trailing id makes the allow-list work on the
# bundled fixtures as well as on an upstream checkout.
is_expected_mismatch <- function(id) {
  id %in% expected_mismatch ||
    any(endsWith(id, paste0("-", expected_mismatch)))
}

# Read `in.json` as a *stream* of values.
#
# A YAML stream's in.json holds one JSON value per document, concatenated and
# pretty-printed, so `{"a": 1}\n{"b": 2}` is not valid JSON as a whole and
# jsonlite has no incremental reader. Splitting it needs no parser of our own:
# accumulate lines, retry after each, and reset the buffer whenever the
# accumulated text parses. Crude, but it needs nothing beyond what Suggests
# already has, and the alternative was skipping streams entirely -- a construct
# the package makes a point of handling.
#
# Returns NULL when the text cannot be split this way, so the caller skips the
# case rather than reporting a disagreement that is really a reader failure.
read_json_stream <- function(json_text) {
  one <- function(txt) {
    tryCatch(list(jsonlite::fromJSON(txt, simplifyVector = FALSE)),
             error = function(e) NULL)
  }

  whole <- one(json_text)
  if (!is.null(whole)) {
    return(whole)
  }

  out <- list()
  buffer <- character()
  for (line in strsplit(json_text, "\n", fixed = TRUE)[[1]]) {
    buffer <- c(buffer, line)
    value <- one(paste(buffer, collapse = "\n"))
    if (!is.null(value)) {
      out <- c(out, value)
      buffer <- character()
    }
  }
  if (any(nzchar(trimws(buffer)))) {
    return(NULL) # trailing text that never completed a value
  }
  out
}

semantic_cases <- function() {
  root <- suite_root_semantic()
  if (!dir.exists(root)) {
    return(NULL)
  }
  inputs <- list.files(root, pattern = "^in\\.yaml$", recursive = TRUE,
                       full.names = TRUE)
  dirs <- dirname(inputs)
  # name/ and tags/ are symlink trees re-exposing every case; see
  # test-conformance.R.
  dirs <- dirs[!grepl("(^|/)(name|tags)/", dirs)]
  dirs <- unique(dirs[file.exists(file.path(dirs, "in.json")) &
                        !file.exists(file.path(dirs, "error"))])
  dirs
}
