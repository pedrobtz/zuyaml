# Helpers for test-unwind-safety.R, kept out of it so that the file's tests can run in
# any order: devtools::test(shuffle = TRUE) shuffles top-level expressions,
# and a test shuffled ahead of a file-scope definition cannot find it.

# `expr` is re-evaluated each time, so it is taken as a quoted expression
# rather than a promise: a promise is forced once and every later iteration
# would reuse the cached failure instead of driving the path again.
poison <- function(expr, times = 25L) {
  expr <- substitute(expr)
  where <- parent.frame()
  for (i in seq_len(times)) {
    caught <- tryCatch({
      eval(expr, where)
      NULL
    }, zuyaml_error = identity)
    expect_s3_class(caught, "zuyaml_error")
  }
}

healthy <- function() {
  expect_identical(yaml_parse("a: 1\nb: [x, y]\n"), list(a = 1L, b = list("x", "y")))
  expect_identical(yaml_emit(list(a = 1L)), "a: 1\n")
}

# --- gctorture ------------------------------------------------------------
#
# The runtime counterpart to rchk: a collection between every allocation, so an
# unprotected intermediate is collected immediately rather than by luck. Slow,
# so each block stays small.

# Only the package call runs under torture. An expect_*() allocates heavily of
# its own accord -- waldo alone is thousands of allocations -- so asserting
# inside the block would spend minutes collecting garbage for testthat rather
# than for zuyaml, and would say nothing extra about this package's C code.
with_gctorture <- function(code) {
  gctorture(TRUE)
  on.exit(gctorture(FALSE), add = TRUE)
  force(code)
}
