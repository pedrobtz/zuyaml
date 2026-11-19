# M2 slice 1: stream parsing, document counting, error conditions, and the
# unwind-safe scope. Scalar, sequence and mapping conversion arrive in the
# next slices, so the tests here deliberately stop at null documents.

test_that("a null document parses to NULL", {
  expect_null(yaml_parse("null"))
  expect_null(yaml_parse("~"))
  expect_null(yaml_parse("---\nnull\n"))
})

test_that("raw input is accepted", {
  expect_null(yaml_parse(charToRaw("null")))
})

test_that("yaml_parse_all always returns a list, one element per document", {
  expect_identical(yaml_parse_all("null"), list(NULL))
  expect_identical(yaml_parse_all("---\nnull\n---\nnull\n"), list(NULL, NULL))
  expect_identical(yaml_parse_all(""), list())
})

test_that("yaml_parse rejects a stream that is not exactly one document", {
  # Trailing documents must never be silently discarded.
  expect_error(
    yaml_parse("---\nnull\n---\nnull\n"),
    "contains 2 documents"
  )
  err <- tryCatch(yaml_parse("---\nnull\n---\nnull\n"), zuyaml_error = identity)
  expect_identical(err$code, "too_many_documents")
})

test_that("an empty stream is an error, not NULL", {
  # NULL is the legitimate result of parsing `null`, so the two cases must be
  # distinguishable.
  err <- tryCatch(yaml_parse(""), zuyaml_error = identity)
  expect_s3_class(err, "zuyaml_parse_error")
  expect_identical(err$code, "no_documents")

  # A comment-only input is also a zero-document stream.
  err <- tryCatch(yaml_parse("# nothing here"), zuyaml_error = identity)
  expect_identical(err$code, "no_documents")
})

test_that("parse errors carry a structured condition", {
  err <- tryCatch(yaml_parse("a: [1, 2"), zuyaml_error = identity)

  expect_s3_class(err, "zuyaml_parse_error")
  expect_s3_class(err, "zuyaml_error")
  expect_s3_class(err, "error")

  # Callers must never have to parse the message to learn the category.
  expect_type(err$code, "character")
  expect_false(err$code %in% c("ok", "unknown"))
  expect_type(err$line, "integer")
  expect_type(err$column, "integer")
  expect_gte(err$line, 1L)
  expect_gte(err$column, 1L)
  expect_match(conditionMessage(err), "^YAML parse error at line")
})

test_that("the file path appears in errors when supplied", {
  err <- tryCatch(
    yaml_parse("a: [1, 2", path = "config.yml"),
    zuyaml_error = identity
  )
  expect_identical(err$path, "config.yml")
  expect_match(conditionMessage(err), "in 'config.yml'")
})

test_that("duplicate-key rejection comes from zuyaml, not cyaml", {
  # cyaml v0.1.3 declares cyaml_opts_t.dup_keys and defines CYAML_ERR_DUP_KEY
  # with a strerror string, but the option is never read and the error is never
  # raised -- `grep -r dup_keys src/` matches only the header. Rejection is
  # therefore zuyaml's own work, done while building the name vector.
  #
  # Conversion errors carry the position of the second key (#35), as a cyaml
  # parse error carries its own, so position no longer tells the layers apart;
  # the message does, and the grep above is the check on upstream.
  err <- tryCatch(yaml_parse("a: 1\na: 2\n"), zuyaml_error = identity)
  expect_identical(err$code, "duplicate_key")
  expect_identical(err$line, 2L)
  expect_identical(err$column, 1L)

  # By contrast, a genuine cyaml parse error does carry a position.
  syntax <- tryCatch(yaml_parse("a: [1, 2"), zuyaml_error = identity)
  expect_type(syntax$line, "integer")
})

test_that("invalid arguments are refused before reaching C", {
  expect_error(yaml_parse(1L), "single string or a raw vector")
  expect_error(yaml_parse(c("a", "b")), "single string or a raw vector")
  expect_error(yaml_parse(NA_character_), "single string or a raw vector")
  expect_error(yaml_parse("null", max_depth = -1), "between 0 and 4294967295")
  expect_error(yaml_parse("null", max_depth = 2^33), "between 0 and 4294967295")
  expect_error(yaml_parse("null", duplicate_keys = NA), "must be TRUE or FALSE")
})

test_that("max_depth is enforced", {
  deep <- paste0(strrep("- ", 50), "null")
  err <- tryCatch(yaml_parse(deep, max_depth = 4), zuyaml_error = identity)
  expect_identical(err$code, "limit_depth")
})

test_that("errors raised mid-conversion do not leak the stream", {
  # The error below is raised while the cyaml stream is still alive, so it
  # exercises the unwind path: R's longjmp skips the explicit free and the
  # external-pointer finalizer has to reclaim it.
  #
  # Repeat enough times that a leak per failure is obvious under ASan or
  # valgrind.
  for (i in 1:200) {
    expect_error(yaml_parse("a: 1\na: 2\n"), class = "zuyaml_error")
  }
  gc()
  expect_true(TRUE)
})

test_that("conversion errors carry a line, column and path (#35)", {
  # Each code is raised during conversion, after cyaml has parsed, and used to
  # arrive with line, column and path all NULL, even from yaml_read().
  cases <- list(
    list(doc = "a: 1\nb: 2\na: 3\n", args = list(), code = "duplicate_key",
         line = 3L),
    list(doc = "x: 1\ny:\n  - - - 1\n", args = list(max_depth = 3),
         code = "limit_depth", line = 3L),
    list(doc = "x: 1\ny: 99999999999999999999\n",
         args = list(big_integers = "error"), code = "precision", line = 2L),
    list(doc = "x: &a 1\ny: *a\n", args = list(aliases = "error"),
         code = "alias", line = 2L),
    list(doc = "x: 1\ny: [1, 2, 3]\n", args = list(max_nodes = 3),
         code = "limit_nodes", line = 2L),
    list(doc = "x: 1\ny: !app 1\n", args = list(tags = "error"),
         code = "unsupported_tag", line = 2L)
  )
  path <- withr::local_tempfile(fileext = ".yml")
  for (case in cases) {
    writeLines(case$doc, path, sep = "")
    for (via in c("text", "file")) {
      err <- tryCatch(
        if (via == "text") {
          do.call(yaml_parse, c(list(case$doc), case$args))
        } else {
          do.call(yaml_read, c(list(path), case$args))
        },
        zuyaml_error = identity
      )
      info <- paste(case$code, via)
      expect_s3_class(err, "zuyaml_parse_error")
      expect_identical(err$code, case$code, info = info)
      expect_identical(err$line, case$line, info = info)
      expect_type(err$column, "integer")
      if (via == "file") {
        expect_identical(err$path, path, info = info)
      } else {
        expect_null(err$path)
      }
    }
  }
})

test_that("an unknown span end is NULL, not 0 (#35)", {
  err <- tryCatch(yaml_parse("[[[[1]]]]", max_depth = 2),
                  zuyaml_error = identity)
  expect_identical(err$line, 1L)
  expect_null(err$end_line)
  expect_null(err$end_column)
})
