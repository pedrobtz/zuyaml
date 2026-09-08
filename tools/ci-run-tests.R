#!/usr/bin/env Rscript
#
# Run the test suite and exit non-zero if anything failed.
#
# This lives in a file rather than inline in the workflow because a `run:`
# block is a YAML scalar: a trailing backslash is literal text, not a shell
# line continuation, so multi-line `Rscript -e` commands silently become
# invalid R. Keeping the R here means the workflow never quotes R code.
#
# Usage:  Rscript tools/ci-run-tests.R [filter]

args <- commandArgs(trailingOnly = TRUE)
filter <- if (length(args) >= 1L && nzchar(args[[1]])) args[[1]] else NULL

if (requireNamespace("devtools", quietly = TRUE)) {
  devtools::load_all(".", quiet = TRUE)
} else {
  library(zuyaml)
}

res <- testthat::test_local(".", filter = filter, reporter = "summary",
                            stop_on_failure = FALSE)
df <- as.data.frame(res)

cat(sprintf(
  "\n%d passed, %d failed, %d skipped, %d errored\n",
  sum(df$passed), sum(df$failed), sum(df$skipped), sum(df$error)
))

if (sum(df$failed) > 0 || any(df$error)) {
  quit(status = 1L)
}
