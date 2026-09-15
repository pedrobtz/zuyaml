# Unwind safety, and two things that currently work by accident.
#
# The C layer raises R errors with a longjmp, so every failure path runs
# through code that was in the middle of owning a cyaml stream or a built
# document. The design's unwind-safety section is the package's riskiest claim
# and, until 0.1.0, nothing asserted it: every one of these paths already
# passed, which is exactly why they needed pinning. They pass by construction,
# not by test, and construction changes.
#
# None of this needs a sanitizer, a container or a network. That is the point:
# rchk found a real PROTECT bug that 2,517 tests, 15,000 fuzz iterations and
# valgrind all missed, and rchk does not run on CRAN. gctorture and a poisoning
# loop do.

# --- poisoning loops ------------------------------------------------------
#
# Drive an error path repeatedly, then assert an ordinary parse still works.
# A leaked longjmp, a half-freed parser or a stream freed twice shows up as a
# failure *after* the loop, not during it.

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

test_that("the parser stays healthy after a repeated duplicate-key error", {
  poison(yaml_parse("a: 1\na: 2\n"))
  healthy()
})

test_that("the parser stays healthy after a repeated node-limit error", {
  # Raised part-way through conversion, with a stream owned and R objects
  # half-built -- the most interesting of these paths.
  big <- paste0("[", paste(1:200, collapse = ","), "]")
  poison(yaml_parse(big, max_nodes = 10))
  healthy()
})

test_that("the parser stays healthy after a repeated depth-limit error", {
  poison(yaml_parse(strrep("- ", 60), max_depth = 5))
  healthy()
})

test_that("the parser stays healthy after a repeated unsupported-tag error", {
  poison(yaml_parse("v: !duration 5m", tags = "error"))
  healthy()
})

test_that("the parser stays healthy after a repeated alias-cycle error", {
  poison(yaml_parse("&a [*a]\n"))
  healthy()
})

test_that("the parser stays healthy after a repeated syntax error", {
  # This one fails before conversion starts, so the stream is freed on a
  # different path from the others.
  poison(yaml_parse("a: [1, 2\n"))
  healthy()
})

test_that("the parser stays healthy after a repeated embedded-NUL error", {
  bytes <- c(charToRaw("a: "), as.raw(0), charToRaw("b\n"))
  poison(yaml_parse(bytes))
  healthy()
})

test_that("the emitter stays healthy after a repeated refusal", {
  # The emit path owns a cyaml_doc_t rather than a stream, and releases it
  # with a different finalizer. Freeing it as a stream would be type
  # confusion, so this loop is worth having on its own.
  poison(yaml_emit(list(a = complex(1))))
  poison(yaml_emit(list(a = 1, 2)))
  healthy()
})

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

test_that("conversion is clean under gctorture", {
  x <- with_gctorture(
    yaml_parse("a: 1\nb:\n  - 1\n  - two\n  - true\nc: {d: 3.5, e: null}\n")
  )
  expect_identical(names(x), c("a", "b", "c"))
  expect_identical(x$c$d, 3.5)
  expect_null(x$c$e)
  expect_identical(with_gctorture(yaml_parse("!!str 12")), "12")
  expect_s3_class(
    with_gctorture(yaml_parse("99999999999999999999")), "zuyaml_bigint"
  )
  expect_identical(
    with_gctorture(yaml_parse("a: &x [1, 2]\nb: *x\n")),
    list(a = list(1L, 2L), b = list(1L, 2L))
  )
})

test_that("error paths are clean under gctorture", {
  # An unwind out of C, with a GC at every allocation on the way.
  errs <- lapply(
    list(
      quote(yaml_parse("a: 1\na: 2\n")),
      quote(yaml_parse("v: !duration 5m", tags = "error")),
      quote(yaml_parse("a: [1, 2\n")),
      quote(yaml_parse(strrep("- ", 60), max_depth = 5))
    ),
    function(expr) {
      with_gctorture(tryCatch(eval(expr), zuyaml_error = identity))
    }
  )
  for (err in errs) {
    expect_s3_class(err, "zuyaml_error")
    expect_true(nzchar(conditionMessage(err)))
  }

  # And the session is still usable afterwards.
  expect_identical(yaml_parse("a: 1\n"), list(a = 1L))
})

test_that("emission is clean under gctorture", {
  # build_node() fetches the names attribute and passes it into an allocating
  # function -- the exact pattern rchk flagged.
  out <- with_gctorture(
    yaml_emit(list(a = 1L, b = list(x = "one", y = c("p", "q"))))
  )
  expect_match(out, "^a: 1\n")
  expect_match(out, "x: one")

  err <- with_gctorture(
    tryCatch(yaml_emit(list(a = 1, 2)), zuyaml_error = identity)
  )
  expect_s3_class(err, "zuyaml_error")
})

# --- format specifiers stay literal ---------------------------------------
#
# zuyaml_stopf() is printf-shaped and interpolates user text into the message.
# Every caller must pass that text as an *argument*; a "%s" or "%n" arriving as
# the format string is a crash, not a mangled message.

test_that("a format specifier in a tag name is not interpolated", {
  err <- tryCatch(
    yaml_parse("v: !%s%n%d 5m", tags = "error"),
    zuyaml_error = identity
  )
  expect_s3_class(err, "zuyaml_error")
  expect_identical(err$code, "unsupported_tag")
  expect_true(grepl("%s%n%d", conditionMessage(err), fixed = TRUE))
})

test_that("a format specifier in a duplicate key is not interpolated", {
  err <- tryCatch(yaml_parse("a%s%n: 1\na%s%n: 2\n"), zuyaml_error = identity)
  expect_s3_class(err, "zuyaml_error")
  expect_identical(err$code, "duplicate_key")
  expect_true(grepl("a%s%n", conditionMessage(err), fixed = TRUE))
})

test_that("a format specifier in a file path is not interpolated", {
  # The path reaches both the R and the C message builders.
  dir <- withr::local_tempdir()
  path <- file.path(dir, "%s%n%d.yaml")
  writeLines("a: [1, 2", path)

  err <- tryCatch(yaml_read(path), zuyaml_error = identity)
  expect_s3_class(err, "zuyaml_error")
  expect_true(grepl("%s%n%d", conditionMessage(err), fixed = TRUE))
  expect_identical(err$path, path)

  missing <- file.path(dir, "%n%n%n.yaml")
  err <- tryCatch(yaml_read(missing), zuyaml_error = identity)
  expect_identical(err$code, "io")
  expect_true(grepl("%n%n%n", conditionMessage(err), fixed = TRUE))
})

test_that("a format specifier in an unemittable class name is not interpolated", {
  err <- tryCatch(
    yaml_emit(structure(list(1), class = "%s%n")),
    zuyaml_error = identity
  )
  expect_s3_class(err, "zuyaml_error")
  expect_true(grepl("%s%n", conditionMessage(err), fixed = TRUE))
})

# --- registration ---------------------------------------------------------

test_that("R_forceSymbols(TRUE) still holds", {
  # Native routines must be reachable only through the registration symbols.
  # One line to assert, and it regresses silently if init.c is regenerated by
  # a tool that drops the call.
  expect_error(
    .Call("zuyaml_parse_", "a: 1\n", FALSE, "keep", "class", "ignore",
          FALSE, 100L, 0L, 1e6, NULL),
    "not in load table|character string"
  )
  # The symbol itself still works, which is what the package uses.
  expect_identical(yaml_parse("a: 1\n"), list(a = 1L))
})
