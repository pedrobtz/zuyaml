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

# Numeric extremes: generous about numbers, strict about text.
#
# The same rule `zujson` follows, and for the same reason. A number outside
# what a double can hold still has a well-defined nearest value -- C requires
# strtod() to return it, and R's own reader agrees -- so the document is read
# and the number converted. The alternative is worse than it sounds: it is not
# an error, it is a *type change*. `timeout: 1e308` gave a double and
# `timeout: 1e309` gave the string "1e309", so the R type of a field depended
# on the magnitude of its value. That is the thing `simplify = FALSE` exists to
# prevent, arriving through the back door.
#
# The cause was upstream: cyaml_str_to_f64() treats any non-zero errno as
# failure, and strtod() sets ERANGE for overflow, for underflow to zero, and
# for any subnormal result -- so even the perfectly representable 1e-323 was
# refused.

test_that("floats outside the double range become the nearest double", {
  expect_identical(yaml_parse("1e309"), Inf)
  expect_identical(yaml_parse("-1e309"), -Inf)
  expect_identical(yaml_parse("123123e100000"), Inf)
  expect_identical(yaml_parse("1.7976931348623157e309"), Inf)

  # Underflow is zero, not a string, and keeps its sign.
  expect_identical(yaml_parse("1e-324"), 0)
  expect_identical(yaml_parse("123e-10000000"), 0)
  expect_identical(yaml_parse("-1e-324"), -0)

  # Subnormals are representable and must not be refused. Written as a bit
  # pattern rather than as an R literal: see the note below.
  expect_identical(yaml_parse("1e-323"), dbl("0000000000000002"))
  expect_identical(yaml_parse("5e-324"), dbl("0000000000000001")) # the smallest

  # The classification agrees with R's own reader for every one of them --
  # overflow to an infinity, underflow to a zero, everything else finite. Only
  # the classification: see the bit-pattern test below for why an extreme value
  # must not be compared against as.numeric() bit for bit.
  tokens <- c("1e309", "-1e309", "123123e100000", "1e-324", "123e-10000000",
              "1e-323", "5e-324", "1e308", "2.5", "-0.75")
  for (tok in tokens) {
    got <- yaml_parse(tok)
    ref <- as.numeric(tok)
    expect_type(got, "double")
    expect_identical(is.finite(got), is.finite(ref), info = tok)
    expect_identical(got == 0, ref == 0, info = tok)
    expect_identical(sign(got), sign(ref), info = tok)
  }
})

test_that("text that is not a number is still a string", {
  # The generosity is about *numbers*. An explicit !!float on text that is not
  # a number falls back to a string, as an unresolvable scalar does in YAML,
  # and that path must not be swallowed by the range handling above.
  expect_identical(yaml_parse("!!float abc"), "abc")
  expect_identical(yaml_parse("!!float 1e309 and more"), "1e309 and more")
  expect_identical(yaml_parse("!!float 1e309"), Inf)
  expect_identical(yaml_parse("1e309 and more"), "1e309 and more")
})

test_that("double expectations are written as bit patterns, not R literals", {
  # Borrowed from zujson, which hit this on CI: R's own string-to-double
  # conversion accumulates through LDOUBLE, which on aarch64 is plain double
  # rather than 80-bit extended, so on Apple silicon R's reader lands a few
  # units in the last place away from the correctly rounded value. A test that
  # compares a parsed number against the same literal written in R source then
  # passes everywhere except macOS.
  #
  # This package sees it, and worse than zujson's example. On this platform
  # R's reader disagrees with the correctly rounded value for several ordinary
  # tokens, and for one of them it is not a rounding difference at all:
  #
  #   token                      zuyaml (correctly rounded)   as.numeric()
  #   1e308                      0x7fe1ccf385ebc8a0           0x7fe1ccf385ebc8a3
  #   1e300                      0x7e37e43c8800759c           0x7e37e43c880075a0
  #   2.2250738585072014e-308    0x0010000000000000 (DBL_MIN) 0x000ffffffffffffc
  #   1.7976931348623157e308     0x7fefffffffffffff (DBL_MAX) 0x7ff0000000000000 (Inf)
  #
  # R's reader overflows on DBL_MAX written out in full -- the canonical
  # round-trip literal. So a value produced by the C layer is compared against
  # a bit pattern, never against an R source literal or as.numeric(). Where a
  # value genuinely goes through R's reader, as.numeric() remains the right
  # reference, because tracking R is the documented behaviour there.
  # An R *hex* literal is no better, and fails in a third way: 0x1p-1074 reads
  # as 0 in R source, because R's reader underflows on subnormals it can
  # perfectly well represent. The only spelling that survives all of this is
  # the bit pattern itself, read through readBin().
  expect_identical(yaml_parse("1"), 1L)
  expect_identical(yaml_parse("1.0"), dbl("3ff0000000000000"))
  expect_identical(yaml_parse("0.5"), dbl("3fe0000000000000"))
  expect_identical(yaml_parse("-0.75"), dbl("bfe8000000000000"))
  expect_identical(yaml_parse("1e308"), dbl("7fe1ccf385ebc8a0"))
  expect_identical(yaml_parse("1e300"), dbl("7e37e43c8800759c"))
  expect_identical(yaml_parse("1.7976931348623157e308"), dbl("7fefffffffffffff"))
  expect_identical(yaml_parse("2.2250738585072014e-308"), dbl("0010000000000000"))
  expect_identical(yaml_parse("1e-323"), dbl("0000000000000002"))
  expect_identical(yaml_parse("5e-324"), dbl("0000000000000001"))

  # And the same values survive an emit, still compared as bit patterns. This
  # is the check that matters most: the emitter picks the shortest text that
  # reads back as the same double, and "reads back" means through this
  # package's own C reader, which is why it holds for DBL_MAX where an R
  # source literal would not.
  patterns <- c("3ff0000000000000", "3fe0000000000000", "bfe8000000000000",
                "7fefffffffffffff", "0010000000000000", "0000000000000002",
                "0000000000000001", "7fe1ccf385ebc8a0", "7ff0000000000000",
                "fff0000000000000", "8000000000000000")
  for (p in patterns) {
    v <- dbl(p)
    expect_identical(yaml_parse(yaml_emit(list(x = v)))$x, v, info = p)
  }
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

test_that("a literal NUL byte is refused, not silently truncated", {
  # Different defect from the escape above, and invisible to the check that
  # catches it: cyaml treats a literal NUL as end of input, so the scalar span
  # is already cut and every later document is gone before conversion runs.
  # `a: 1\nb: x<NUL>y\nc: 3\n` used to parse as two keys with b = "x" and no
  # sign that c had ever existed. The input is scanned before the parser now.
  nul_at <- function(text, at) {
    bytes <- charToRaw(text)
    bytes[at] <- as.raw(0)
    bytes
  }

  cases <- list(
    value  = nul_at("a: 1\nb: xy\nc: 3\n", 11),
    key    = nul_at("ab: 1\n", 2),
    block  = nul_at("a: |\n  xy\n", 9),
    stream = nul_at("a: 1\n---\nb: 2\n", 7),
    first  = nul_at("ab\n", 1),
    quoted = nul_at('"ab"\n', 3)
  )

  for (nm in names(cases)) {
    err <- tryCatch(yaml_parse_all(cases[[nm]]), zuyaml_error = identity)
    expect_s3_class(err, "zuyaml_error")
    expect_identical(err$code, "embedded_nul")
    # Position, so the caller can find it. The exit criterion for this fix is
    # that it is never reported without one.
    expect_true(is.numeric(err$line) && err$line >= 1)
    expect_true(is.numeric(err$column) && err$column >= 1)
  }

  # The example from the review, spelled out: the tail must not be silently
  # dropped.
  err <- tryCatch(yaml_parse_all(cases$value), zuyaml_error = identity)
  expect_identical(err$line, 2L)
  expect_identical(err$column, 6L)
})

test_that("a leading UTF-8 BOM is not part of the document", {
  # A BOM is permitted at the start of a stream. cyaml leaves it in the first
  # scalar, so it used to end up inside the first key name.
  bom <- as.raw(c(0xEF, 0xBB, 0xBF))

  expect_identical(
    yaml_parse(c(bom, charToRaw("a: 1\nb: 2\n"))),
    yaml_parse("a: 1\nb: 2\n")
  )
  expect_identical(names(yaml_parse(c(bom, charToRaw("key: v\n")))), "key")
  expect_identical(yaml_parse(c(bom, charToRaw("- 1\n- 2\n"))), list(1L, 2L))

  # A BOM on its own is an empty stream, exactly as no input at all is.
  expect_identical(yaml_parse_all(bom), yaml_parse_all(""))

  # Positions are reported against the content, not the file: the BOM is not a
  # column of line 1.
  err <- tryCatch(
    yaml_parse(c(bom, charToRaw("a: 1\n\tb: 2\n"))),
    zuyaml_error = identity
  )
  expect_identical(err$line, 2L)

  # A BOM elsewhere is ordinary text, not a marker, and must not be stripped.
  expect_identical(
    yaml_parse(c(charToRaw("a: "), bom, charToRaw("x\n"))),
    list(a = "\ufeffx")
  )
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
