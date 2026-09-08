# Mappings whose keys are not scalars.

test_that("collection-valued keys produce a zuyaml_map", {
  m <- yaml_parse("? [one, two]\n: value\n")

  expect_s3_class(m, "zuyaml_map")
  expect_length(m, 1L)
  expect_identical(m$keys[[1]], list("one", "two"))
  expect_identical(m$values[[1]], "value")
})

test_that("a single complex key makes the whole mapping a zuyaml_map", {
  # Splitting a mapping across two representations would be worse than
  # converting all of it consistently.
  m <- yaml_parse("a: 1\n? [x]\n: 2\n")

  expect_s3_class(m, "zuyaml_map")
  expect_length(m, 2L)
  expect_identical(m$keys[[1]], "a")
  expect_identical(m$values[[1]], 1L)
  expect_identical(m$keys[[2]], list("x"))
})

test_that("mapping-valued keys are preserved structurally", {
  m <- yaml_parse("? {a: 1}\n: v\n")

  expect_s3_class(m, "zuyaml_map")
  expect_identical(m$keys[[1]], list(a = 1L))
  expect_identical(m$values[[1]], "v")
})

test_that("keys and values are parallel lists", {
  m <- yaml_parse("? [a]\n: 1\n? [b]\n: 2\n")

  expect_named(unclass(m), c("keys", "values"))
  expect_length(m$keys, 2L)
  expect_length(m$values, 2L)
  expect_identical(m$values, list(1L, 2L))
})

test_that("zuyaml_map prints readably", {
  expect_output(print(yaml_parse("? [one, two]\n: value\n")), "zuyaml_map")
  expect_output(print(yaml_parse("? [one, two]\n: value\n")), "key:")
})

test_that("scalar-key mappings are unaffected", {
  expect_false(inherits(yaml_parse("a: 1\n"), "zuyaml_map"))
  expect_false(inherits(yaml_parse("1: a\n"), "zuyaml_map"))
})
