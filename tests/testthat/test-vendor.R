# zuyaml bundles a pinned copy of the cyaml C library. These tests guard the
# provenance chain: the compiled code, the recorded version, and the patches
# must stay in agreement. They are cheap and they fail loudly after a botched
# re-vendor, which is exactly when it matters.

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

test_that("the compiled cyaml version matches inst/cyaml-VERSION", {
  recorded <- sub("^v", "", field(version_record(), "version"))
  expect_identical(cyaml_version(), recorded)
})

test_that("CYAML_VERSION_STR was defined at build time", {
  # cyaml_internal.h falls back to "0.0.0-dev" when src/Makevars does not
  # define CYAML_VERSION_STR. Upstream's CMake supplies it; we do not use
  # CMake, so a dropped -D flag would silently misreport the version.
  expect_false(grepl("dev", cyaml_version(), fixed = TRUE))
  expect_match(cyaml_version(), "^[0-9]+\\.[0-9]+\\.[0-9]+$")
})

test_that("the vendored source is pinned to an immutable commit", {
  # A branch name here would mean the package silently tracks upstream.
  expect_match(field(version_record(), "commit"), "^[0-9a-f]{40}$")
})

test_that("the mandatory assertion patch is recorded as applied", {
  # CRAN prohibits abort() and stderr writes from compiled code. If this
  # record is ever empty, the vendored assertions can kill the R session.
  expect_match(field(version_record(), "patches"), "assertions-no-abort")
})
