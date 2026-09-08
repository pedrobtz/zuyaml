#' Emit YAML
#'
#' `yaml_emit()` converts one R object to a YAML document. `yaml_emit_all()`
#' converts a list of objects to a YAML *stream*.
#'
#' Emission favours readable YAML over reproducing any particular source
#' formatting. Comments, quoting style and flow-versus-block choices are not
#' preserved; see `vignette("zuyaml")` for the conversions that do not round
#' trip.
#'
#' @param x An R object. `yaml_emit_all()` takes a list, one element per
#'   document.
#' @param indent Spaces per indentation level, 1 to 255.
#' @param width Line width before wrapping, 0 to 255. `0` disables wrapping.
#' @param document_start Emit a leading `---`.
#' @param document_end Emit a trailing `...`.
#'
#' @return A length-one UTF-8 character vector.
#'
#' @examples
#' cat(yaml_emit(list(host = "localhost", port = 8080L)))
#' cat(yaml_emit_all(list(list(a = 1L), list(b = 2L))))
#'
#' # Strings that look like other types stay strings.
#' cat(yaml_emit(list(version = "42")))
#' @name yaml_emit
NULL

#' @rdname yaml_emit
#' @export
yaml_emit <- function(x,
                      indent = 2L,
                      width = 80L,
                      document_start = FALSE,
                      document_end = FALSE) {
  indent <- check_uint8(indent, "indent", min = 1L)
  width <- check_uint8(width, "width", min = 0L)
  check_flag(document_start, "document_start", NULL)
  check_flag(document_end, "document_end", NULL)

  .Call(zuyaml_emit_, x, indent, width, document_start, document_end)
}

#' @rdname yaml_emit
#' @export
yaml_emit_all <- function(x,
                          indent = 2L,
                          width = 80L,
                          document_start = FALSE,
                          document_end = FALSE) {
  if (!is.list(x) || inherits(x, "zuyaml_map")) {
    zuyaml_abort(
      "`x` must be a list, with one element per document.",
      code = "invalid_input"
    )
  }
  if (length(x) == 0L) {
    return("")
  }

  # cyaml_stream_emit() is not used: it takes no options and is built to
  # preserve the formatting of a stream that was parsed, not one being
  # constructed. Each document is emitted with the same options instead.
  #
  # A stream is not parseable without markers, so `---` is forced from the
  # second document onward regardless of the argument.
  parts <- vapply(
    seq_along(x),
    function(i) {
      yaml_emit(
        x[[i]],
        indent = indent,
        width = width,
        document_start = document_start || i > 1L,
        document_end = document_end
      )
    },
    character(1)
  )

  paste(parts, collapse = "")
}
