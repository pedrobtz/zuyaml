# File reading and writing. Byte-oriented, locale-independent.

test_that("a document round-trips through a file", {
  path <- withr::local_tempfile(fileext = ".yml")
  x <- list(host = "localhost", port = 8080L, tls = TRUE)

  expect_identical(yaml_write(x, path), path)
  expect_identical(yaml_read(path), x)
})

test_that("yaml_write returns the path invisibly", {
  path <- withr::local_tempfile(fileext = ".yml")
  expect_invisible(yaml_write(list(a = 1L), path))
})

test_that("streams round-trip through a file", {
  path <- withr::local_tempfile(fileext = ".yml")
  docs <- list(list(a = 1L), list(b = 2L))

  yaml_write_all(docs, path)
  expect_identical(yaml_read_all(path), docs)

  # A multi-document file is exactly what yaml_read() must refuse.
  err <- tryCatch(yaml_read(path), zuyaml_error = identity)
  expect_identical(err$code, "too_many_documents")
})

test_that("parse errors from a file name the file", {
  path <- withr::local_tempfile(fileext = ".yml")
  writeLines("a: [1, 2", path)

  err <- tryCatch(yaml_read(path), zuyaml_error = identity)
  expect_identical(err$path, path)
  expect_match(conditionMessage(err), basename(path), fixed = TRUE)
  expect_type(err$line, "integer")
})

test_that("missing files give a clear condition", {
  err <- tryCatch(yaml_read(tempfile()), zuyaml_error = identity)
  expect_identical(err$code, "io")
  expect_match(conditionMessage(err), "does not exist")

  expect_error(yaml_read(42), "single string")
})

test_that("UTF-8 survives the file round trip", {
  path <- withr::local_tempfile(fileext = ".yml")
  x <- list(name = "café — 日本語", emoji = "🎉")

  yaml_write(x, path)
  back <- yaml_read(path)

  expect_identical(back, x)
  expect_identical(Encoding(back$name), "UTF-8")
})

test_that("parse options pass through to the reader", {
  path <- withr::local_tempfile(fileext = ".yml")
  writeLines("- 1\n- 2", path)

  expect_identical(yaml_read(path), list(1L, 2L))
  expect_identical(yaml_read(path, simplify = TRUE), 1:2)
})

test_that("emit options pass through to the writer", {
  path <- withr::local_tempfile(fileext = ".yml")
  yaml_write(list(a = list(b = 1L)), path, indent = 4L)
  expect_match(paste(readLines(path), collapse = "\n"), "    b")
})

test_that("raw HTTP-style bodies parse without any file involved", {
  # zuhttp hands over response bytes; zuyaml must need nothing else.
  body <- charToRaw('{"host": "example.com", "port": 443}')
  expect_identical(yaml_parse(body), list(host = "example.com", port = 443L))

  utf8_body <- charToRaw(enc2utf8('name: "café"'))
  expect_identical(yaml_parse(utf8_body), list(name = "café"))
})
