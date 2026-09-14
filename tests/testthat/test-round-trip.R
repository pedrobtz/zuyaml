# The emitter's round-trip property.
#
# R value -> YAML -> R value must give back the same R value. Until 0.1.0 this
# was asserted only by a hand-written list of cases enumerated from the spec's
# scalar-style section, which is why it missed what it missed: every string
# containing a line break was corrupted on emit, as was every string with
# leading or trailing whitespace, and every double with an integral value came
# back as an integer.
#
# The replacement is deliberately a *property* over generated input rather than
# another list. A list can only contain cases someone thought of, and the same
# person wrote the code.
#
# What is not asserted here: anything about the emitted text. The package
# promises readable YAML, not any particular quoting or block style, so the
# only thing worth pinning is that the value survives.

round_trips <- function(value, ...) {
  text <- yaml_emit(value, ...)
  identical(yaml_parse(text, ...), value)
}

# Characters chosen so that a random draw lands on the constructs that break
# plain scalars: line breaks, edge whitespace, YAML indicators, and the reserved
# words. Plain letters are included so that most strings stay ordinary.
alphabet <- c(
  letters[1:6], "0", "1", "7", " ", " ", "\t", "\n", "\r", "\n",
  "#", ":", "-", "?", ",", "[", "]", "{", "}", "&", "*", "!", "|", ">",
  "'", "\"", "%", "@", "`", ".", "\\", "é", "☃"
)

random_strings <- function(n, max_len = 12L) {
  vapply(seq_len(n), function(i) {
    len <- sample.int(max_len + 1L, 1L) - 1L
    paste0(sample(alphabet, len, replace = TRUE), collapse = "")
  }, character(1))
}

test_that("generated strings survive a round trip in every position", {
  withr::local_seed(20260914)

  values <- c(
    random_strings(400L),
    # The specific shapes the 0.1.0 review found, kept alongside the generated
    # ones so a failure names them directly.
    "a\nb", "line one\nline two\n", "x\n", "\n", "\r\n", "a\r\nb",
    "  spaced  ", "\tbar", "bar\t", " ", "\t", "   ", "",
    "42", "0x1F", ".inf", "true", "null", "~", "-", "---", "...",
    "a: b", "a #b", "b:", "é☃"
  )

  bad <- character()
  for (v in values) {
    ok <- round_trips(v) &&                          # bare scalar document
      round_trips(list(v)) &&                        # sequence element
      round_trips(list(key = v)) &&                  # mapping value
      round_trips(list(list(v), list(inner = v)))    # nested
    # An empty name is refused on emit: R cannot tell `list("" = 1)` from an
    # unnamed element, so it is a partial-names error rather than a key.
    if (ok && nzchar(v)) {
      ok <- round_trips(stats::setNames(list(1L), v))
    }
    if (!ok) {
      bad <- c(bad, encodeString(v, quote = '"'))
    }
  }

  expect_identical(bad, character(), info = paste(bad, collapse = ", "))
})

test_that("every short string over the indicator alphabet round-trips", {
  # Exhaustive rather than random for the shapes where an off-by-one in the
  # style rules lives: one and two characters drawn from every YAML indicator.
  # This is what found the lone "-" and "?", which are indicators rather than
  # scalars -- `k: ?` does not parse at all -- and which no hand-written list
  # contained, because nobody writes a one-character scalar on purpose.
  alphabet <- c("a", "1", " ", "\t", "\n", "#", ":", "-", "?", ",",
                "[", "]", "{", "}", "&", "*", "!", "|", ">", "'", "\"",
                "%", "@", "`", ".", "\\")
  pairs <- expand.grid(alphabet, alphabet, stringsAsFactors = FALSE)
  values <- c("", alphabet, paste0(pairs[[1]], pairs[[2]]))

  bad <- character()
  for (v in values) {
    ok <- round_trips(list(key = v)) && round_trips(list(v))
    if (ok && nzchar(v)) {
      ok <- round_trips(stats::setNames(list(1L), v))
    }
    if (!ok) {
      bad <- c(bad, encodeString(v, quote = '"'))
    }
  }
  expect_identical(bad, character(), info = paste(bad, collapse = ", "))
})

test_that("the round trip does not depend on the emitter's line width", {
  # The newline defect was width-independent, and the fix must be too: folding
  # is a property of the plain style, not of wrapping.
  withr::local_seed(1L)
  values <- c(random_strings(60L, max_len = 40L), strrep("word ", 30L),
              paste0(strrep("x", 90), "\n", strrep("y", 90)))

  bad <- character()
  for (width in c(0L, 20L, 80L, 200L)) {
    for (v in values) {
      text <- yaml_emit(list(key = v), width = width)
      if (!identical(yaml_parse(text), list(key = v))) {
        bad <- c(bad, sprintf("width %d: %s", width,
                              encodeString(v, quote = '"')))
      }
    }
  }
  expect_identical(bad, character(), info = paste(bad, collapse = "\n"))
})

test_that("doubles keep their type across a round trip", {
  # "%g" prints the double 450 as `450`, which the core schema resolves as an
  # integer, so an integral double used to come back as an integer -- the
  # yaml-test-suite's own invoice example (UGM3) has `price: 450.00`.
  withr::local_seed(2L)

  values <- c(
    0, 1, -1, 450, 2^31, 2^53, -0.0, 0.5, 1 / 3, 3.14159265358979,
    1e-300, 1e300, .Machine$double.xmax, .Machine$double.eps,
    round(stats::runif(50L, -1e6, 1e6)),   # integral doubles
    stats::runif(50L, -1e6, 1e6),
    # The extremes, as bit patterns rather than R literals: R's own reader
    # disagrees with the correctly rounded value for several of these on
    # aarch64, and reads every subnormal hex literal as 0. See
    # helper-doubles.R and test-scalars.R.
    vapply(c("7fefffffffffffff",  # DBL_MAX
             "0010000000000000",  # DBL_MIN
             "0000000000000001",  # smallest subnormal
             "0000000000000002",
             "8000000000000000",  # -0
             "7fe1ccf385ebc8a0",  # 1e308, correctly rounded
             "3cb0000000000000"), # DBL_EPSILON
           dbl, numeric(1)),
    Inf, -Inf
  )

  bad <- character()
  for (v in values) {
    if (!round_trips(list(x = v))) {
      bad <- c(bad, sprintf("%a", v))
    }
  }
  expect_identical(bad, character(), info = paste(bad, collapse = ", "))

  # Integers stay integers, and are not widened by the float spelling.
  expect_identical(yaml_emit(list(x = 1L)), "x: 1\n")
  expect_identical(yaml_emit(list(x = 1)), "x: 1.0\n")
  expect_identical(yaml_parse("x: 1\n"), list(x = 1L))
  expect_identical(yaml_parse("x: 1.0\n"), list(x = 1))
})

test_that("the documented non-finite and NA behaviour is unchanged", {
  # These are the rows of the design's lossy-conversion table that touch the
  # emitter. They must stay lossy in exactly the documented way -- the round
  # trip above must not have been bought by changing them.
  expect_identical(yaml_emit(list(x = Inf)), "x: .inf\n")
  expect_identical(yaml_emit(list(x = -Inf)), "x: -.inf\n")
  expect_identical(yaml_emit(list(x = NaN)), "x: .nan\n")
  expect_identical(yaml_parse(yaml_emit(list(x = Inf))), list(x = Inf))
  expect_identical(yaml_parse(yaml_emit(list(x = NaN))), list(x = NaN))

  # NA emits as null and comes back as NULL. Documented, and deliberately not
  # "fixed" by this work.
  expect_identical(yaml_emit(list(x = NA)), "x: null\n")
  expect_identical(yaml_parse(yaml_emit(list(x = NA))), list(x = NULL))
})

test_that("whole structures round-trip, not only scalars", {
  withr::local_seed(3L)

  value <- list(
    name = "zuyaml",
    versions = list("0.1.0", "1.0"),
    notes = "first line\nsecond line\n",
    padded = "  keep me  ",
    counts = list(1L, 2L, 3L),
    ratios = list(0.5, 2, 1 / 3),
    flags = list(yes = TRUE, no = FALSE),
    empty_map = stats::setNames(list(), character()),
    empty_seq = list(),
    nested = list(a = list(b = list(c = "\tdeep\t")))
  )

  expect_true(round_trips(value))
  expect_true(round_trips(list(value, value)))

  # And through a file, which is the path most callers actually take.
  path <- withr::local_tempfile(fileext = ".yaml")
  yaml_write(value, path)
  expect_identical(yaml_read(path), value)
})
