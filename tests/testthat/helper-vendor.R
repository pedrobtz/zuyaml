# Helpers for test-vendor.R, kept out of it so that the file's tests can run in
# any order: devtools::test(shuffle = TRUE) shuffles top-level expressions,
# and a test shuffled ahead of a file-scope definition cannot find it.

version_record <- function() {
  path <- system.file("cyaml-VERSION", package = "zuyaml")
  expect_true(nzchar(path))
  readLines(path, warn = FALSE)
}

field <- function(record, name) {
  line <- grep(paste0("^", name, ":"), record, value = TRUE)
  expect_length(line, 1)
  trimws(sub(paste0("^", name, ":"), "", line[[1]]))
}
