# Integers beyond what R can hold exactly, and the big_integers policy.

test_that("the 2^53 boundary is respected exactly", {
  # 2^53 is the largest integer a double holds exactly.
  expect_type(yaml_parse("9007199254740992"), "double")
  expect_s3_class(yaml_parse("9007199254740993"), "zuyaml_bigint")
})

test_that("large integers become zuyaml_bigint by default", {
  for (v in c(
    "9223372036854775807", # INT64_MAX
    "-9223372036854775808", # INT64_MIN
    "18446744073709551615", # UINT64_MAX
    "99999999999999999999999999" # beyond uint64
  )) {
    x <- yaml_parse(v)
    expect_s3_class(x, "zuyaml_bigint")
    expect_identical(as.character(x), v)
  }
})

test_that("zuyaml_bigint carries the decimal value, not the source text", {
  # cyaml accepts 0x and 0o integers. Storing the source would give
  # "0x7FFFFFFFFFFFFFFF", useless for comparison and not an integer on emit.
  expect_identical(
    as.character(yaml_parse("0x7FFFFFFFFFFFFFFF")),
    "9223372036854775807"
  )
})

test_that("big_integers policies behave as documented", {
  big <- "9223372036854775807"

  expect_s3_class(yaml_parse(big, big_integers = "bigint"), "zuyaml_bigint")

  # "double" is an explicit opt-in to losing precision.
  d <- yaml_parse(big, big_integers = "double")
  expect_type(d, "double")

  err <- tryCatch(
    yaml_parse(big, big_integers = "error"),
    zuyaml_error = identity
  )
  expect_identical(err$code, "precision")

  # Values that fit are unaffected by the policy.
  expect_identical(yaml_parse("42", big_integers = "error"), 42L)
})

test_that("precision is never lost silently", {
  # The invariant: no default path turns a >2^53 integer into a rounded double.
  x <- yaml_parse("9223372036854775807")
  expect_false(is.numeric(x))
  expect_identical(as.character(x), "9223372036854775807")
})

test_that("the constructor validates", {
  expect_s3_class(zuyaml_bigint("123"), "zuyaml_bigint")
  expect_s3_class(zuyaml_bigint(zuyaml_bigint("123")), "zuyaml_bigint")
  expect_identical(as.character(zuyaml_bigint("-7")), "-7")

  expect_error(zuyaml_bigint("12x"), "decimal integers")
  expect_error(zuyaml_bigint("1.5"), "decimal integers")
  expect_error(zuyaml_bigint(TRUE), "character vector")
})

test_that("zuyaml_bigint has usable methods", {
  x <- yaml_parse("9223372036854775807")

  expect_identical(format(x), "9223372036854775807")
  expect_identical(as.character(x), "9223372036854775807")
  expect_type(as.numeric(x), "double") # lossy, deliberately
  expect_output(print(x), "zuyaml_bigint")
  expect_s3_class(x[1], "zuyaml_bigint")
})

test_that("sequences of big integers are never simplified", {
  x <- yaml_parse("[9223372036854775807, 9223372036854775806]", simplify = TRUE)
  expect_type(x, "list")
  expect_s3_class(x[[1]], "zuyaml_bigint")
})

test_that("integers beyond uint64 are normalised and approximated", {
  # Past uint64 only the source text is available, so the normalisation and
  # the lossy double both have to be derived from it.
  huge <- strrep("9", 40)

  expect_identical(as.character(yaml_parse(huge)), huge)

  # A leading '+' and leading zeros are not part of the value: +007 and 7 must
  # give the same bigint, or comparison of parsed values is unreliable.
  expect_identical(
    unclass(yaml_parse(paste0("+", huge))),
    unclass(yaml_parse(huge))
  )
  expect_identical(
    unclass(yaml_parse(paste0(strrep("0", 10), huge))),
    unclass(yaml_parse(huge))
  )
  expect_identical(as.character(yaml_parse(paste0("-", huge))),
                   paste0("-", huge))

  # big_integers = "double" is lossy by design, but it must still yield the
  # value: anything of 32 digits or more used to come back as Inf.
  expect_equal(yaml_parse(strrep("9", 31), big_integers = "double"), 1e31,
               tolerance = 1e-12)
  expect_equal(yaml_parse(strrep("9", 32), big_integers = "double"), 1e32,
               tolerance = 1e-12)
  expect_equal(yaml_parse(paste0("-", huge), big_integers = "double"), -1e40,
               tolerance = 1e-12)
})

test_that("the 64-bit boundary values parse exactly", {
  # -9223372036854775808 is INT64_MIN. Negating it in int64_t overflows, which
  # is undefined behaviour rather than merely implementation-defined; UBSan
  # reports it and CRAN runs UBSan builds. See tools/patches/README.md, patch
  # 0004. The value was right on the compilers tried, so only a sanitizer
  # distinguishes the fixed code from the broken code -- which is exactly why
  # this needs pinning by value here *and* exercising under the sanitizer in
  # tools/sanitizer-exercise.R.
  boundaries <- c(
    "9223372036854775807",   # INT64_MAX
    "-9223372036854775808",  # INT64_MIN
    "-9223372036854775807",  # INT64_MIN + 1
    "9223372036854775808",   # INT64_MAX + 1, past int64 but inside uint64
    "-9223372036854775809",  # INT64_MIN - 1, past int64 on the low side
    "18446744073709551615"   # UINT64_MAX
  )

  for (v in boundaries) {
    expect_identical(as.character(yaml_parse(v)), v, info = v)
  }

  # And the sign is not lost on the way to a double.
  expect_equal(yaml_parse("-9223372036854775808", big_integers = "double"),
               -9223372036854775808, tolerance = 1e-12)
})
