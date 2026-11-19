# R -> YAML conversion.

test_that("scalars emit with core-schema spellings", {
  expect_identical(emitted(NULL), "null")
  expect_identical(emitted(TRUE), "true")
  expect_identical(emitted(FALSE), "false")
  expect_identical(emitted(42L), "42")
  expect_identical(emitted(3.14), "3.14")
  expect_identical(emitted(Inf), ".inf")
  expect_identical(emitted(-Inf), "-.inf")
  expect_identical(emitted(NaN), ".nan")
  expect_identical(emitted("hello"), "hello")
})

test_that("booleans emit unquoted and round-trip", {
  # cyaml's emitter quotes any plain scalar spelled true/false/null/~, which
  # would turn a logical into a string. See
  # tools/patches/0002-emitter-plain-scalar-style.patch.
  expect_identical(yaml_parse(yaml_emit(TRUE)), TRUE)
  expect_identical(yaml_parse(yaml_emit(FALSE)), FALSE)
  expect_null(yaml_parse(yaml_emit(NULL)))
})

test_that("strings that would resolve as another type are quoted", {
  # Without this, yaml_emit(list(x = "42")) gives `x: 42`, which parses back as
  # an integer. Version strings, zip codes and IDs all land here.
  for (s in c(
    "42", "-7", "+5", "3.14", "1e3", "0x1F", "0o17",
    ".inf", "-.inf", ".nan", "true", "TRUE", "false", "null", "NULL", "~", ""
  )) {
    expect_identical(
      yaml_parse(yaml_emit(s)), s,
      info = sprintf("string %s did not round-trip", encodeString(s, quote = '"'))
    )
  }
})

test_that("strings that are unambiguous stay unquoted", {
  expect_identical(emitted("hello"), "hello")
  expect_identical(emitted("1.2.3"), "1.2.3")
  expect_identical(emitted("v1.0"), "v1.0")
  expect_identical(emitted("a b"), "a b")
})

test_that("doubles keep enough precision to round-trip", {
  # cyaml_new_float() formats with %g, which keeps six significant digits, so
  # zuyaml formats doubles itself.
  for (v in c(3.14159265358979, 1 / 3, 1e-300, 1.7976931348623157e308, 0.1)) {
    expect_identical(yaml_parse(yaml_emit(v)), v)
  }
})

test_that("NA emits as null", {
  # Documented as lossy: null parses back as NULL, not NA.
  expect_identical(emitted(NA), "null")
  expect_identical(emitted(NA_integer_), "null")
  expect_identical(emitted(NA_real_), "null")
  expect_identical(emitted(NA_character_), "null")
})

test_that("lists and vectors map to sequences and mappings", {
  expect_identical(emitted(list(host = "localhost", port = 8080L)), "host: localhost\nport: 8080")
  expect_identical(emitted(list("a", "b")), "- a\n- b")
  expect_identical(emitted(c(1L, 2L, 3L)), "- 1\n- 2\n- 3")
  expect_identical(emitted(c(a = 1L, b = 2L)), "a: 1\nb: 2")
})

test_that("empty containers are distinguishable", {
  # list() alone cannot express both, so it emits [] and an empty *named*
  # list is the way to ask for {}.
  expect_identical(emitted(list()), "[]")
  expect_identical(emitted(structure(list(), names = character())), "{}")
  expect_identical(emitted(list(a = list())), "a: []")
})

test_that("factors emit as labels, not codes", {
  expect_identical(emitted(factor(c("x", "y"))), "- x\n- y")
  expect_identical(emitted(factor("b", levels = c("a", "b"))), "b")
})

test_that("zuyaml_bigint emits as an integer", {
  big <- yaml_parse("9223372036854775807")
  expect_identical(emitted(big), "9223372036854775807")
  expect_identical(yaml_parse(yaml_emit(big)), big)

  # The class attribute is not trusted: a hand-made invalid value is refused
  # rather than quietly emitted as a string.
  expect_identical(
    error_code(yaml_emit(structure("not-a-number", class = "zuyaml_bigint"))),
    "invalid_input"
  )
})

test_that("ambiguous and unsupported objects are refused", {
  expect_identical(error_code(yaml_emit(list(a = 1, 2))), "partial_names")
  expect_identical(
    error_code(yaml_emit(stats::setNames(list(1, 2), c("a", "a")))),
    "duplicate_key"
  )
  expect_identical(error_code(yaml_emit(data.frame(a = 1))), "unsupported_type")
  expect_identical(error_code(yaml_emit(yaml_parse("? [a]\n: 1\n"))),
                   "unsupported_type")
  expect_identical(error_code(yaml_emit(sum)), "unsupported_type")
  expect_identical(error_code(yaml_emit(Sys.Date())), "unsupported_type")
})

test_that("formatting options are validated and applied", {
  expect_match(yaml_emit(list(a = list(b = 1L)), indent = 4L), "    b")
  expect_match(yaml_emit(list(a = 1L), document_start = TRUE), "^---")
  expect_match(yaml_emit(list(a = 1L), document_end = TRUE), "\\.\\.\\.")

  # indent and width are uint8_t upstream; width = 1000 would silently wrap.
  # Both ends of each range, and one past them (#36).
  emit_code <- function(...) error_code(yaml_emit(list(a = 1L), ...))
  expect_identical(emit_code(indent = 1), NA_character_)
  expect_identical(emit_code(indent = 255), NA_character_)
  expect_identical(emit_code(indent = 0), "invalid_input")
  expect_identical(emit_code(indent = 256), "invalid_input")
  expect_identical(emit_code(indent = NA), "invalid_input")
  expect_identical(emit_code(width = 0), NA_character_)
  expect_identical(emit_code(width = 255), NA_character_)
  expect_identical(emit_code(width = -1), "invalid_input")
  expect_identical(emit_code(width = 256), "invalid_input")
  expect_identical(emit_code(width = 1000), "invalid_input")
  expect_identical(emit_code(document_start = NA), "invalid_input")
})

test_that("yaml_emit_all produces a parseable stream", {
  out <- yaml_emit_all(list(list(a = 1L), list(b = 2L)))

  expect_match(out, "---")
  expect_identical(yaml_parse_all(out), list(list(a = 1L), list(b = 2L)))
  expect_identical(yaml_emit_all(list()), "")
  expect_identical(error_code(yaml_emit_all(42L)), "invalid_input")
})

test_that("nested structures round-trip", {
  x <- list(
    apiVersion = "v1",
    kind = "Pod",
    metadata = list(name = "x", labels = list(app = "web")),
    ports = list(80L, 443L),
    enabled = TRUE,
    ratio = 0.5,
    note = NULL
  )
  expect_identical(yaml_parse(yaml_emit(x)), x)
})

test_that("every string the parser resolves as non-string is quoted (#30)", {
  # The oracle is the parser itself: a string emitted plain must not come
  # back as anything else. cyaml's resolver is wider than the core schema
  # (signs before 0x/0o, keywords in any case), and the emitter used to
  # quote only the core schema's spellings.
  case_variants <- function(word) {
    chars <- strsplit(word, "")[[1]]
    alts <- lapply(chars, function(ch) unique(c(tolower(ch), toupper(ch))))
    apply(expand.grid(alts, stringsAsFactors = FALSE), 1, paste, collapse = "")
  }
  keywords <- unlist(lapply(
    c("null", "true", "false", ".inf", "+.inf", "-.inf", ".nan"),
    case_variants
  ))
  numbers <- c(
    outer(c("", "+", "-"), c("0x1F", "0X1f", "0o17", "0O7", "42", "007",
                             "1.5", ".5", "1.", "1e3", "1.5E-3"), paste0)
  )
  withr::local_seed(30)
  alphabet <- strsplit("+-0123456789.xXoOeEaAfFiInNlLtTrRuUsS~", "")[[1]]
  random <- vapply(seq_len(3000), function(i) {
    paste(sample(alphabet, sample(1:6, 1), replace = TRUE), collapse = "")
  }, "")
  for (s in unique(c(keywords, numbers, random))) {
    expect_identical(yaml_parse(yaml_emit(list(v = s)))$v, s, info = s)
  }
  # The same through a character vector, which builds elements one by one.
  v <- c("-0x10", "nULL", ".iNf", "tRUE", "+0o7")
  expect_identical(unlist(yaml_parse(yaml_emit(v))), v)
})

test_that("map keys are translated to UTF-8 like values (#32)", {
  latin1 <- iconv("café", "UTF-8", "latin1")
  k <- list(1L)
  names(k) <- latin1
  out <- yaml_emit(k)
  expect_true(validUTF8(out))
  expect_identical(Encoding(out), "UTF-8")
  expect_identical(names(yaml_parse(out)), "café")

  # The same text in two encodings is one name, so it is a duplicate.
  dup <- list(1L, 2L)
  names(dup) <- c(latin1, "café")
  err <- tryCatch(yaml_emit(dup), zuyaml_error = identity)
  expect_identical(err$code, "duplicate_key")
})
