# Number conversion through zufast (#14).
#
# Scalars are converted by zufast's span parsers rather than strtod() and
# cyaml_str_to_i64(). These tests pin what that conversion must give, against
# oracles that do not go through R's own reader: IEEE-754 bit patterns
# (helper-doubles.R), C's printf, and the core schema's grammar.

test_that("!!float takes YAML float syntax only, not C's (#14)", {
  # strtod() accepted these under an explicit !!float, and zufast does not:
  # none of them is a YAML float, so each is an unresolvable scalar, which is
  # a string. `!!float 0o17` was already a string; hex now agrees with it.
  c_only <- c(
    "0x10",
    "0xFF",
    "-0x10",
    "+0x10",
    "0x1p3",
    "inf",
    "nan",
    "infinity",
    "-inf",
    "INF",
    "0o17"
  )
  for (tok in c_only) {
    expect_identical(yaml_parse(paste("!!float", tok)), tok, info = tok)
    expect_identical(yaml_parse(sprintf("!!float '%s'", tok)), tok, info = tok)
  }
})

test_that("!!float takes every form of the core schema float", {
  # [-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?, and the special
  # values in the spellings cyaml's resolver accepts.
  cases <- list(
    "0" = 0,
    "-0" = -0,
    "+0" = 0,
    "1" = 1,
    "+1" = 1,
    "007" = 7,
    "1.5" = 1.5,
    "+1.5" = 1.5,
    "-1.5" = -1.5,
    ".5" = 0.5,
    "-.5" = -0.5,
    "1." = 1,
    "0." = 0,
    "00.5" = 0.5,
    "1e3" = 1000,
    "1E3" = 1000,
    "1e+3" = 1000,
    "+.5e1" = 5,
    "1e-3" = dbl("3F50624DD2F1A9FC"),
    ".inf" = Inf,
    "+.inf" = Inf,
    "-.inf" = -Inf,
    ".Inf" = Inf,
    ".INF" = Inf
  )
  for (tok in names(cases)) {
    want <- cases[[tok]]
    expect_identical(yaml_parse(paste("!!float", tok)), want, info = tok)
    # Untagged, the integer-looking ones resolve as integers; the rest are
    # floats and must agree with the tagged conversion.
    if (grepl("[.eE]", tok)) {
      expect_identical(yaml_parse(tok), want, info = tok)
    }
  }
  expect_true(is.nan(yaml_parse("!!float .nan")))
  expect_true(is.nan(yaml_parse(".NaN")))
  expect_identical(1 / yaml_parse("!!float -0"), -Inf)

  # Near misses stay strings, tagged or not.
  for (tok in c(
    "1.0e",
    "1e",
    "e3",
    ".",
    ".e1",
    "--1",
    "+-1",
    "1_000",
    "1,5",
    "12abc",
    "+.nan",
    "1.5 "
  )) {
    expect_identical(yaml_parse(sprintf("!!float '%s'", tok)), tok, info = tok)
  }
})

test_that("floats are correctly rounded", {
  # Each decimal string with the double it denotes, as a bit pattern. Several
  # sit within one unit of a rounding boundary, where a parser that is not
  # correctly rounded gives the neighbour.
  cases <- c(
    "0.1" = "3FB999999999999A",
    "2.2250738585072011e-308" = "000FFFFFFFFFFFFF", # largest subnormal
    "2.2250738585072012e-308" = "0010000000000000", # smallest normal
    "1.7976931348623157e308" = "7FEFFFFFFFFFFFFF", # DBL_MAX
    "1.7976931348623158e308" = "7FEFFFFFFFFFFFFF", # below the halfway point
    "4.9406564584124654e-324" = "0000000000000001", # smallest subnormal
    "2.4703282292062328e-324" = "0000000000000001", # just above half of it
    "9007199254740993.0" = "4340000000000000", # 2^53 + 1: ties to even
    "9007199254740995.0" = "4340000000000002", # 2^53 + 3: ties to even
    "9007199254740993.000000000001" = "4340000000000001" # just above the tie
  )
  for (tok in names(cases)) {
    expect_identical(yaml_parse(tok), dbl(cases[[tok]]), info = tok)
  }
  # Just below half the smallest subnormal: zero, a double, not a string.
  expect_identical(yaml_parse("2.4703282292062327e-324"), 0)
})

test_that("seventeen significant digits read back as the same double", {
  # Seventeen digits identify a double uniquely, and C's printf writes them
  # correctly on every platform CRAN uses, so a correctly rounded parser must
  # give back exactly the double printf was handed. R's reader is not the
  # oracle (helper-doubles.R says why).
  withr::local_seed(14)
  x <- c(
    runif(300) * 10^sample(-307:307, 300, replace = TRUE),
    -runif(50) * 10^sample(-307:307, 50, replace = TRUE),
    runif(50) * 2^-1060 # subnormals
  )
  txt <- sprintf("%.17g", x)
  # Exponent-free output of an integral value would resolve as an integer.
  txt <- ifelse(grepl("[.e]", txt), txt, paste0(txt, ".0"))
  got <- vapply(txt, yaml_parse, numeric(1), USE.NAMES = FALSE)
  expect_identical(got, x)
})

test_that("long numbers are read whole, not truncated", {
  # The span is parsed in place. The old path copied it into a buffer first;
  # a length limit there, or a parser that stops after some digits, would
  # change these.
  expect_identical(yaml_parse(paste0("1.", strrep("0", 2000), "1")), 1)
  expect_identical(
    yaml_parse(paste0("0.", strrep("0", 300), "1e300")),
    dbl("3FB999999999999A") # 0.1
  )
  # 1 followed by 400 zeros, scaled back: exactly 1, past any double's digits.
  expect_identical(yaml_parse(paste0("1", strrep("0", 400), "e-400")), 1)
  expect_identical(yaml_parse(paste0("9", strrep("9", 400), ".5")), Inf)
})

test_that("integers straddle every boundary the same in every base", {
  # Decimal, hex and octal spellings of the same value convert the same way:
  # integer up to 2^31 - 1, double up to 2^53, zuyaml_bigint beyond.
  same <- list(
    c("2147483647", "0x7FFFFFFF", "0o17777777777"),
    c("2147483648", "0x80000000", "0o20000000000"),
    c("-2147483647", "-0x7FFFFFFF", "-0o17777777777"),
    c("-2147483648", "-0x80000000", "-0o20000000000"),
    c("9007199254740992", "0x20000000000000", "0o400000000000000000"),
    c("9007199254740993", "0x20000000000001", "0o400000000000000001"),
    c("9223372036854775807", "0x7FFFFFFFFFFFFFFF"),
    c("9223372036854775808", "0x8000000000000000"),
    c("-9223372036854775808", "-0x8000000000000000"),
    c("18446744073709551615", "0xFFFFFFFFFFFFFFFF", "0XffffFFFFffffFFFF")
  )
  for (spellings in same) {
    want <- yaml_parse(spellings[[1]])
    for (s in spellings[-1]) {
      expect_identical(yaml_parse(s), want, info = s)
      expect_identical(yaml_parse(paste("!!int", s)), want, info = s)
    }
  }
  expect_identical(yaml_parse("2147483647"), 2147483647L)
  expect_identical(yaml_parse("-2147483647"), -2147483647L)
  expect_identical(yaml_parse("2147483648"), 2^31)
  expect_identical(yaml_parse("-2147483648"), -2^31) # INT_MIN is NA_integer_
  expect_identical(yaml_parse("9007199254740992"), 2^53)
  expect_identical(
    unclass(yaml_parse("9007199254740993")),
    "9007199254740993"
  )
  expect_identical(
    unclass(yaml_parse("-9223372036854775808")),
    "-9223372036854775808"
  )
  expect_identical(
    unclass(yaml_parse("0xFFFFFFFFFFFFFFFF")),
    "18446744073709551615"
  )
  expect_identical(yaml_parse("+0x10"), 16L)
  expect_identical(yaml_parse("-0o17"), -15L)
  expect_identical(yaml_parse("-0"), 0L)
  expect_identical(yaml_parse("+007"), 7L)
})

test_that("integer near misses are strings", {
  # A hex literal past uint64 has no decimal form to keep, so it stays text.
  for (tok in c(
    "0x",
    "0o",
    "0o8",
    "0xG",
    "0x10000000000000000",
    "1.5",
    "1e3",
    "--1",
    "+-1",
    "0x-5",
    "0x+5",
    "1_000",
    "12abc"
  )) {
    expect_identical(yaml_parse(sprintf("!!int '%s'", tok)), tok, info = tok)
  }
})

test_that("an approximated big integer is the nearest double", {
  # The approximation of a literal past uint64 is parsed from its digits.
  big <- paste0("1", strrep("0", 30))
  got <- yaml_parse(big, big_integers = "double")
  expect_identical(got, dbl("46293E5939A08CEA")) # 1e30, correctly rounded
  expect_identical(
    yaml_parse(paste0("-", big), big_integers = "double"),
    -dbl("46293E5939A08CEA")
  )
})
