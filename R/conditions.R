# Conditions and argument validation.
#
# Validation lives in R, not C: the C layer receives values it can trust and
# does not re-derive policy. The condition shape here must stay identical to
# the one built in src/zuyaml_error.c, so that a caller can handle errors from
# either layer the same way.

#' @keywords internal
#' @noRd
zuyaml_abort <- function(message,
                         code,
                         path = NULL,
                         line = NULL,
                         column = NULL,
                         end_line = NULL,
                         end_column = NULL,
                         class = "zuyaml_parse_error") {
  cond <- structure(
    list(
      message = message,
      call = NULL,
      code = code,
      line = line,
      column = column,
      end_line = end_line,
      end_column = end_column,
      path = path
    ),
    class = c(class, "zuyaml_error", "error", "condition")
  )
  stop(cond)
}

check_input <- function(x, path) {
  if (is.raw(x)) {
    return(invisible(x))
  }
  if (is.character(x) && length(x) == 1L && !is.na(x)) {
    return(invisible(x))
  }
  # A character vector of length != 1 is a user mistake far more often than a
  # request to parse several documents, so it is refused rather than guessed at.
  zuyaml_abort(
    "`x` must be a single string or a raw vector.",
    code = "invalid_input",
    path = path
  )
}

check_flag <- function(value, arg, path) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    zuyaml_abort(
      sprintf("`%s` must be TRUE or FALSE.", arg),
      code = "invalid_input",
      path = path
    )
  }
  invisible(value)
}

# Upstream stores these as uint32_t, so they are validated and passed as
# doubles: the upper bound exceeds R's integer range.
check_uint32 <- function(value, arg, path) {
  if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
    value < 0 || value > 4294967295) {
    zuyaml_abort(
      sprintf("`%s` must be a single number between 0 and 4294967295.", arg),
      code = "invalid_input",
      path = path
    )
  }
  as.double(value)
}

check_path <- function(path) {
  if (is.null(path)) {
    return(invisible(path))
  }
  if (is.character(path) && length(path) == 1L && !is.na(path)) {
    return(invisible(path))
  }
  zuyaml_abort(
    "`path` must be NULL or a single string.",
    code = "invalid_input"
  )
}

# max_nodes counts materialised values and can exceed R's integer range, so it
# is validated as a non-negative count rather than a uint32.
check_count <- function(value, arg, path) {
  if (!is.numeric(value) || length(value) != 1L || is.na(value) || value < 0) {
    zuyaml_abort(
      sprintf("`%s` must be a single non-negative number.", arg),
      code = "invalid_input",
      path = path
    )
  }
  as.double(value)
}

# indent and width are uint8_t in the emitter options upstream, so an
# out-of-range value would silently wrap (width = 1000 becomes 232).
check_uint8 <- function(value, arg, min = 0L) {
  if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
    value < min || value > 255) {
    zuyaml_abort(
      sprintf("`%s` must be a single number between %d and 255.", arg, min),
      code = "invalid_input"
    )
  }
  as.integer(value)
}
