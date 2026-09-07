# zuyaml bundles the cyaml C library (see inst/COPYRIGHTS). CRAN policy
# requires that "the ownership of copyright and intellectual property rights of
# all components of the package must be clear and unambiguous", credited via
# `ctb` / `cph` roles in Authors@R. These tests guard that setup against a
# future DESCRIPTION edit or a usethis regeneration quietly dropping it.

authors_at_r <- function() {
  field <- utils::packageDescription("zuyaml", fields = "Authors@R")
  eval(parse(text = field))
}

test_that("the bundled cyaml author is credited as contributor and copyright holder", {
  authors <- authors_at_r()
  sampson <- Filter(function(p) identical(p$family, "Sampson"), authors)

  expect_length(sampson, 1)
  expect_true("cph" %in% sampson[[1]]$role)
  expect_true("ctb" %in% sampson[[1]]$role)
  expect_match(sampson[[1]]$comment, "cyaml", fixed = TRUE)
})

test_that("the package has a maintainer", {
  authors <- authors_at_r()
  expect_true(any(vapply(authors, function(p) "cre" %in% p$role, logical(1))))
})

test_that("COPYRIGHTS is installed and pins the vendored cyaml version", {
  path <- system.file("COPYRIGHTS", package = "zuyaml")
  expect_true(nzchar(path))

  copyrights <- readLines(path, warn = FALSE)
  expect_true(any(grepl("andrewmd5/cyaml", copyrights, fixed = TRUE)))
  expect_true(any(grepl("Andrew Sampson", copyrights, fixed = TRUE)))
  # The commit must be an exact 40-character sha, never a branch name.
  expect_true(any(grepl("Commit:\\s+[0-9a-f]{40}$", copyrights)))
})

test_that("DESCRIPTION carries no usethis template text", {
  desc <- utils::packageDescription("zuyaml")
  expect_false(grepl("What the [Pp]ackage [Dd]oes", desc$Title))
  expect_false(grepl("What the package does", desc$Description, fixed = TRUE))
})
