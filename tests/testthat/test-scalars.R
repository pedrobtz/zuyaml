# Scalar conversion, YAML 1.2 core schema.

test_that("nulls convert to NULL", {
  expect_null(yaml_parse("null"))
  expect_null(yaml_parse("Null"))
  expect_null(yaml_parse("NULL"))
  expect_null(yaml_parse("~"))
})

test_that("the quoted empty string stays a string and never becomes NULL", {
  expect_identical(yaml_parse('""'), "")
  expect_identical(yaml_parse("''"), "")
  expect_false(is.null(yaml_parse('""')))
})

test_that("booleans use YAML 1.2 rules, not 1.1", {
  expect_identical(yaml_parse("true"), TRUE)
  expect_identical(yaml_parse("True"), TRUE)
  expect_identical(yaml_parse("TRUE"), TRUE)
  expect_identical(yaml_parse("false"), FALSE)
  expect_identical(yaml_parse("False"), FALSE)

  # 1.1 booleans are plain strings under the 1.2 core schema.
  expect_identical(yaml_parse("yes"), "yes")
  expect_identical(yaml_parse("no"), "no")
  expect_identical(yaml_parse("on"), "on")
  expect_identical(yaml_parse("off"), "off")
})

test_that("integers become integer or double by magnitude", {
  expect_identical(yaml_parse("42"), 42L)
  expect_identical(yaml_parse("-7"), -7L)
  expect_identical(yaml_parse("0"), 0L)

  # Above 32-bit, but exactly representable as a double.
  expect_identical(yaml_parse("2147483648"), 2147483648)
  expect_identical(yaml_parse("5000000000"), 5e9)

  # NA_INTEGER is INT_MIN, so that value must not come back as an integer.
  expect_type(yaml_parse("-2147483648"), "double")
})

test_that("hex and octal integers are supported", {
  expect_identical(yaml_parse("0x1F"), 31L)
  expect_identical(yaml_parse("0o17"), 15L)
})

test_that("integers beyond 2^53 are never silently rounded", {
  # Full coverage of the policy lives in test-bigint.R; this pins the
  # invariant at the point where scalars are classified.
  expect_s3_class(yaml_parse("9223372036854775807"), "zuyaml_bigint")
})

test_that("floats convert, including the special values", {
  expect_identical(yaml_parse("3.14"), 3.14)
  expect_identical(yaml_parse("-0.5"), -0.5)
  expect_identical(yaml_parse("1e3"), 1000)
  expect_identical(yaml_parse(".inf"), Inf)
  expect_identical(yaml_parse("-.inf"), -Inf)
  expect_true(is.nan(yaml_parse(".nan")))
})

test_that("quoted scalars are always strings", {
  expect_identical(yaml_parse('"42"'), "42")
  expect_identical(yaml_parse('"true"'), "true")
  expect_identical(yaml_parse('"null"'), "null")
  expect_identical(yaml_parse("'3.14'"), "3.14")
})

test_that("timestamps are not coerced to Date or POSIXct", {
  expect_identical(yaml_parse("2026-09-07"), "2026-09-07")
  expect_identical(yaml_parse("2026-09-07T12:00:00Z"), "2026-09-07T12:00:00Z")
})

test_that("text is returned as UTF-8", {
  x <- yaml_parse('"café — 日本語"')
  expect_identical(Encoding(x), "UTF-8")
  expect_identical(x, "café — 日本語")
})

test_that("escapes and block scalars are processed", {
  expect_identical(yaml_parse('"a\\tb"'), "a\tb")
  expect_identical(yaml_parse('"\\u00e9"'), "é")
  expect_identical(yaml_parse("|\n  a\n  b\n"), "a\nb\n")
  expect_identical(yaml_parse(">\n  a\n  b\n"), "a b\n")
})

test_that("embedded NUL is refused instead of silently truncating", {
  # `key: "\0"` is legal YAML, and R strings cannot hold a NUL.
  # cyaml_scalar_str() returns a NUL-terminated string with no length, so the
  # value would otherwise come back silently truncated to "".
  raw_yaml <- function(bytes) rawToChar(as.raw(bytes))

  for (src in list(
    c(0x22, 0x5c, 0x30, 0x22), # "\0"
    c(0x22, 0x5c, 0x78, 0x30, 0x30, 0x22), # "\x00"
    c(0x22, 0x5c, 0x75, 0x30, 0x30, 0x30, 0x30, 0x22), # backslash-u-0000
    c(0x22, 0x61, 0x5c, 0x30, 0x62, 0x22) # "a\0b"
  )) {
    err <- tryCatch(yaml_parse(raw_yaml(src)), zuyaml_error = identity)
    expect_s3_class(err, "zuyaml_error")
    expect_identical(err$code, "embedded_nul")
  }
})

test_that("NUL detection does not false-positive on similar escapes", {
  raw_yaml <- function(bytes) rawToChar(as.raw(bytes))

  # An escaped backslash followed by a literal 0 is not a NUL escape.
  expect_identical(yaml_parse(raw_yaml(c(0x22, 0x5c, 0x5c, 0x30, 0x22))), "\\0")
  expect_identical(yaml_parse('"\\x41"'), "A")
  expect_identical(yaml_parse('"\\u00e9"'), "é")
  expect_identical(yaml_parse('"0"'), "0")
  expect_identical(yaml_parse("0"), 0L)
})
