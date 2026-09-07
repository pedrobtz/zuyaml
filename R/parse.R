#' Parse YAML
#'
#' `yaml_parse()` parses a single YAML document. `yaml_parse_all()` parses a
#' YAML *stream* and returns one element per document.
#'
#' Both functions parse the input as a stream. `yaml_parse()` then requires it
#' to contain exactly one document, so trailing documents are never silently
#' discarded:
#'
#' | documents | `yaml_parse()` | `yaml_parse_all()` |
#' | --------- | -------------- | ------------------ |
#' | 0         | error          | `list()`           |
#' | 1         | the object     | list of length 1   |
#' | more      | error          | list of that length |
#'
#' A zero-document stream is an error rather than `NULL`, because `NULL` is
#' the legitimate result of parsing a document whose content is `null`.
#' Comment-only input is a zero-document stream.
#'
#' @param x A length-one character vector containing YAML, or a raw vector of
#'   UTF-8 YAML bytes.
#' @param simplify If `TRUE`, sequences whose elements are all scalars of the
#'   same type collapse to an atomic vector. The default is `FALSE`, so the
#'   shape of the result never depends on the contents of the document.
#' @param duplicate_keys If `FALSE` (the default), a mapping with duplicate
#'   keys is an error. If `TRUE`, duplicates become duplicate names in the
#'   resulting list.
#' @param max_depth Maximum nesting depth, or `0` for unlimited.
#' @param max_size Maximum input size in bytes, or `0` for unlimited.
#' @param path Optional file path, used only to make error messages more
#'   informative. Set by the file-reading functions in a later milestone.
#'
#' @return `yaml_parse()` returns an R object. `yaml_parse_all()` returns a
#'   list with one element per document.
#'
#' @examples
#' yaml_parse("null")
#' yaml_parse_all("---\nnull\n---\nnull\n")
#' @name yaml_parse
NULL

#' @rdname yaml_parse
#' @export
yaml_parse <- function(x,
                       simplify = FALSE,
                       duplicate_keys = FALSE,
                       max_depth = 128L,
                       max_size = 64 * 1024^2,
                       path = NULL) {
  docs <- yaml_parse_all(
    x,
    simplify = simplify,
    duplicate_keys = duplicate_keys,
    max_depth = max_depth,
    max_size = max_size,
    path = path
  )

  if (length(docs) != 1L) {
    zuyaml_abort(
      if (length(docs) == 0L) {
        "YAML stream contains no documents."
      } else {
        sprintf(
          "YAML stream contains %d documents; use yaml_parse_all().",
          length(docs)
        )
      },
      code = if (length(docs) == 0L) "no_documents" else "too_many_documents",
      path = path
    )
  }

  docs[[1L]]
}

#' @rdname yaml_parse
#' @export
yaml_parse_all <- function(x,
                           simplify = FALSE,
                           duplicate_keys = FALSE,
                           max_depth = 128L,
                           max_size = 64 * 1024^2,
                           path = NULL) {
  check_input(x, path)
  check_flag(simplify, "simplify", path)
  check_flag(duplicate_keys, "duplicate_keys", path)
  max_depth <- check_uint32(max_depth, "max_depth", path)
  max_size <- check_uint32(max_size, "max_size", path)
  check_path(path)

  .Call(zuyaml_parse_, x, simplify, duplicate_keys, max_depth, max_size, path)
}
