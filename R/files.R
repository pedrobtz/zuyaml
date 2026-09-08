#' Read and write YAML files
#'
#' `yaml_read()` reads one YAML document from a file; `yaml_read_all()` reads a
#' stream. `yaml_write()` and `yaml_write_all()` are their counterparts.
#'
#' These work on bytes, not text: files are read and written with [readBin()]
#' and [writeBin()], so nothing depends on the session's locale, and the file
#' path is carried into parse errors to make them locatable.
#'
#' @param path Path to a file.
#' @param x An R object. `yaml_write_all()` takes a list, one element per
#'   document.
#' @param ... Passed to [yaml_parse()] or [yaml_emit()].
#'
#' @return `yaml_read()` returns an R object and `yaml_read_all()` a list of
#'   them. The writers return `path` invisibly.
#'
#' @examples
#' path <- tempfile(fileext = ".yml")
#' yaml_write(list(host = "localhost", port = 8080L), path)
#' yaml_read(path)
#' unlink(path)
#' @name yaml_read
NULL

read_bytes <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    zuyaml_abort("`path` must be a single string.", code = "invalid_input")
  }
  if (!file.exists(path)) {
    zuyaml_abort(
      sprintf("File '%s' does not exist.", path),
      code = "io",
      path = path
    )
  }
  size <- file.info(path)$size
  if (is.na(size)) {
    zuyaml_abort(
      sprintf("Could not determine the size of '%s'.", path),
      code = "io",
      path = path
    )
  }
  readBin(path, what = "raw", n = size)
}

write_bytes <- function(text, path) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    zuyaml_abort("`path` must be a single string.", code = "invalid_input")
  }
  # charToRaw on a UTF-8 string yields its UTF-8 bytes; writeBin never adds a
  # trailing newline or rewrites line endings.
  writeBin(charToRaw(enc2utf8(text)), path)
  invisible(path)
}

#' @rdname yaml_read
#' @export
yaml_read <- function(path, ...) {
  yaml_parse(read_bytes(path), ..., path = path)
}

#' @rdname yaml_read
#' @export
yaml_read_all <- function(path, ...) {
  yaml_parse_all(read_bytes(path), ..., path = path)
}

#' @rdname yaml_read
#' @export
yaml_write <- function(x, path, ...) {
  write_bytes(yaml_emit(x, ...), path)
}

#' @rdname yaml_read
#' @export
yaml_write_all <- function(x, path, ...) {
  write_bytes(yaml_emit_all(x, ...), path)
}
