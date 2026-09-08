# Anchors, aliases, cycles, and the expansion budget.

test_that("aliases resolve to the value of their target", {
  expect_identical(yaml_parse("a: &x 1\nb: *x\n"), list(a = 1L, b = 1L))
  expect_identical(
    yaml_parse("defaults: &d\n  timeout: 30\nserver:\n  config: *d\n"),
    list(defaults = list(timeout = 30L), server = list(config = list(timeout = 30L)))
  )
  expect_identical(
    yaml_parse("a: &x [1, 2]\nb: *x\n"),
    list(a = list(1L, 2L), b = list(1L, 2L))
  )
})

test_that("aliases = 'error' rejects documents containing aliases", {
  err <- tryCatch(
    yaml_parse("a: &x 1\nb: *x\n", aliases = "error"),
    zuyaml_error = identity
  )
  expect_identical(err$code, "alias")

  # A document with an anchor but no alias is not affected.
  expect_identical(yaml_parse("a: &x 1\n", aliases = "error"), list(a = 1L))
})

test_that("aliases must match a known anchor", {
  err <- tryCatch(yaml_parse("b: *nope\n"), zuyaml_error = identity)
  expect_s3_class(err, "zuyaml_error")
})

test_that("the node budget stops alias expansion bombs", {
  # A billion-laughs payload is small and shallow, so neither max_size nor
  # max_depth constrains it: this one is under 350 bytes and seven levels deep,
  # but expands to 9^8 leaves. Only a node budget bounds it.
  bomb <- function(levels) {
    s <- "a: &a [x,x,x,x,x,x,x,x,x]\n"
    prev <- "a"
    for (i in seq_len(levels)) {
      nm <- paste0("l", i)
      s <- paste0(
        s, nm, ": &", nm, " [",
        paste(rep(paste0("*", prev), 9), collapse = ","), "]\n"
      )
      prev <- nm
    }
    s
  }

  payload <- bomb(7)
  expect_lt(nchar(payload), 400)

  err <- tryCatch(yaml_parse(payload), zuyaml_error = identity)
  expect_identical(err$code, "limit_nodes")

  # A tighter budget stops a smaller one too.
  err <- tryCatch(yaml_parse(bomb(6), max_nodes = 1e5), zuyaml_error = identity)
  expect_identical(err$code, "limit_nodes")

  # And the budget does not fire on ordinary documents.
  expect_identical(yaml_parse("a: 1\nb: [1, 2]\n", max_nodes = 100), list(a = 1L, b = list(1L, 2L)))
})

test_that("max_nodes is validated", {
  expect_error(yaml_parse("a: 1", max_nodes = -1), "non-negative")
  expect_error(yaml_parse("a: 1", max_nodes = NA), "non-negative")
  expect_identical(yaml_parse("a: 1", max_nodes = 0), list(a = 1L)) # unlimited
})

test_that("aliases is validated", {
  expect_error(yaml_parse("a: 1", aliases = "nonsense"))
})

test_that("alias cycles are detected and reported with a position", {
  # An alias whose target contains it would recurse forever, and no ordinary R
  # list can represent it.
  for (src in c("&x [*x]", "&x {a: *x}", "a: &x\n  b: *x\n")) {
    err <- tryCatch(yaml_parse(src), zuyaml_error = identity)
    expect_identical(err$code, "alias_cycle")
    expect_match(conditionMessage(err), "alias cycle detected at line [0-9]+")
  }
})

test_that("repeating an anchor is not a cycle", {
  # The same anchor used twice as siblings is ordinary reuse, not recursion.
  expect_identical(
    yaml_parse("a: &x [1]\nb: [*x, *x]\n"),
    list(a = list(1L), b = list(list(1L), list(1L)))
  )
})
