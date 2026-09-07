# Sequence and mapping conversion.

test_that("sequences become lists", {
  expect_identical(yaml_parse("- one\n- 2\n- true\n"), list("one", 2L, TRUE))
  expect_identical(yaml_parse("[1, 2, 3]"), list(1L, 2L, 3L))
  expect_identical(yaml_parse("[]"), list())
})

test_that("simplify is off by default and opt-in", {
  # The default keeps the shape of the result independent of the contents of
  # the document.
  expect_identical(yaml_parse("[1, 2, 3]"), list(1L, 2L, 3L))
  expect_identical(yaml_parse("[1, 2, 3]", simplify = TRUE), 1:3)
  expect_identical(yaml_parse("[a, b]", simplify = TRUE), c("a", "b"))
  expect_identical(yaml_parse("[true, false]", simplify = TRUE), c(TRUE, FALSE))
  expect_identical(yaml_parse("[1.5, 2.5]", simplify = TRUE), c(1.5, 2.5))
})

test_that("simplify only collapses homogeneous scalar sequences", {
  expect_identical(yaml_parse("[1, a]", simplify = TRUE), list(1L, "a"))
  expect_identical(yaml_parse("[1, null, 3]", simplify = TRUE), list(1L, NULL, 3L))
  # The outer sequence holds sequences, not scalars, so it is not simplified;
  # each inner one is scalar-only and collapses on its own merit.
  expect_identical(yaml_parse("[[1], [2]]", simplify = TRUE), list(1L, 2L))
  expect_identical(yaml_parse("[[1, 2], [3]]", simplify = TRUE), list(1:2, 3L))
  expect_identical(yaml_parse("[]", simplify = TRUE), list())
})

test_that("mappings become named lists", {
  expect_identical(
    yaml_parse("host: localhost\nport: 8080\ntls: true\n"),
    list(host = "localhost", port = 8080L, tls = TRUE)
  )
  expect_identical(yaml_parse("{}"), structure(list(), names = character()))
})

test_that("nested structures convert", {
  expect_identical(
    yaml_parse("a:\n  b:\n    - 1\n    - x\n"),
    list(a = list(b = list(1L, "x")))
  )
  expect_identical(
    yaml_parse("apiVersion: v1\nmetadata:\n  labels:\n    app: web\n"),
    list(apiVersion = "v1", metadata = list(labels = list(app = "web")))
  )
})

test_that("non-string scalar keys are stringified", {
  expect_identical(yaml_parse("1: a\n2: b\n"), list(`1` = "a", `2` = "b"))
  expect_identical(yaml_parse("true: a\n"), list(`true` = "a"))
})

test_that("duplicate keys are rejected by default", {
  # cyaml does not do this (see test-parse.R); zuyaml enforces it while
  # building the name vector.
  err <- tryCatch(yaml_parse("a: 1\na: 2\n"), zuyaml_error = identity)
  expect_identical(err$code, "duplicate_key")
  expect_match(conditionMessage(err), "Duplicate mapping key 'a'")
})

test_that("duplicate keys are allowed on request", {
  expect_identical(
    yaml_parse("a: 1\na: 2\n", duplicate_keys = TRUE),
    list(a = 1L, a = 2L)
  )
})

test_that("stringification collisions are caught", {
  # YAML sees two distinct keys, 1 and "1", but R would see one name. Silently
  # returning a list with duplicate names would defeat the duplicate check.
  err <- tryCatch(yaml_parse("1: a\n\"1\": b\n"), zuyaml_error = identity)
  expect_identical(err$code, "duplicate_key")
})

test_that("collection-valued keys are refused for now", {
  # These become a zuyaml_map in M3 rather than being coerced into names.
  err <- tryCatch(yaml_parse("? [one, two]\n: value\n"), zuyaml_error = identity)
  expect_identical(err$code, "unsupported_key")
})

test_that("max_depth is enforced by zuyaml, since cyaml ignores it", {
  # cyaml v0.1.3 declares opts.max_depth and never reads it: a document 20000
  # levels deep parses happily with max_depth = 10. The limit is applied during
  # conversion instead, which also keeps deep nesting from exhausting R's
  # protection stack.
  deep <- paste0(strrep("[", 300), strrep("]", 300))

  err <- tryCatch(yaml_parse(deep, max_depth = 10), zuyaml_error = identity)
  expect_identical(err$code, "limit_depth")

  expect_type(yaml_parse(deep, max_depth = 0), "list") # 0 = unlimited
  expect_type(yaml_parse(deep, max_depth = 500), "list")
})

test_that("max_size is enforced by zuyaml, since cyaml ignores it", {
  err <- tryCatch(yaml_parse("a: 1", max_size = 2), zuyaml_error = identity)
  expect_identical(err$code, "limit_size")
  expect_identical(yaml_parse("a: 1", max_size = 0), list(a = 1L)) # unlimited
  expect_identical(yaml_parse("a: 1", max_size = 4), list(a = 1L))
})

# Alias behaviour is covered in test-aliases.R.
