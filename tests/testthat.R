# This file is part of the standard setup for testthat.
#
# Where should you do additional test configuration?
# Learn more about the roles of various files in:
# * https://r-pkgs.org/testing-design.html#sec-tests-files-overview
# * https://testthat.r-lib.org/articles/special-files.html
#
# Departs from the generated file in one way: the suite is conditional on the
# suggested packages it needs. CRAN's NOSUGGESTS flavor runs R CMD check with
# no suggested packages installed, and `library(testthat)` at top level is an
# ERROR there rather than a skipped check. Writing R Extensions asks for the
# use of a suggested package to be conditional for exactly this reason.
#
# Both packages, not only testthat: withr is used unguarded in test-files.R,
# test-round-trip.R and test-unwind-safety.R, so a machine with testthat but
# no withr would fail in the same way one step later. jsonlite is not here --
# only the semantic conformance tests need it, and they already carry their
# own skip_if_not_installed().

if (requireNamespace("testthat", quietly = TRUE) &&
    requireNamespace("withr", quietly = TRUE)) {
  library(testthat)
  library(zuyaml)

  test_check("zuyaml")
}
