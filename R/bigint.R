#' Integers too large for R's numeric types
#'
#' A character vector holding the decimal representation of integers that R
#' cannot store exactly: beyond 2^53 a double silently loses precision, and R
#' has no native 64-bit integer scalar.
#'
#' [yaml_parse()] returns one of these when it meets such a value and
#' `big_integers = "bigint"` (the default). It carries the *decimal*
#' normalisation of the value, not the source text, so `0x1FFFFFFFFFFFFFFF`
#' and its decimal spelling compare equal.
#'
#' This is a marker for values whose precision must be preserved, not a
#' big-integer arithmetic type: there is no arithmetic. Use
#' `as.numeric()` to accept the precision loss deliberately, or a package such
#' as `bit64` for real 64-bit arithmetic.
#'
#' @param x A character vector of decimal integers, or an object to coerce.
#'
#' @return `zuyaml_bigint()` returns a character vector of class
#'   `"zuyaml_bigint"`.
#'
#' @examples
#' yaml_parse("9223372036854775807")
#' as.numeric(yaml_parse("9223372036854775807")) # lossy, on purpose
#' @export
zuyaml_bigint <- function(x) {
  if (inherits(x, "zuyaml_bigint")) {
    return(x)
  }
  if (is.numeric(x)) {
    x <- format(x, scientific = FALSE, trim = TRUE)
  }
  if (!is.character(x)) {
    zuyaml_abort(
      "`x` must be a character vector of decimal integers.",
      code = "invalid_input"
    )
  }
  # Validated on construction so that emission can trust the contents: a value
  # reaching the emitter has either come from the parser or through here.
  bad <- !is.na(x) & !grepl("^[+-]?[0-9]+$", x)
  if (any(bad)) {
    zuyaml_abort(
      sprintf(
        "`x` must contain only decimal integers; %s is not one.",
        encodeString(x[which(bad)[1]], quote = '"')
      ),
      code = "invalid_input"
    )
  }
  structure(as.character(x), class = "zuyaml_bigint")
}

#' @export
format.zuyaml_bigint <- function(x, ...) {
  unclass(x)
}

#' @export
print.zuyaml_bigint <- function(x, ...) {
  cat("<zuyaml_bigint>\n")
  print(unclass(x), quote = FALSE)
  invisible(x)
}

#' @export
as.character.zuyaml_bigint <- function(x, ...) {
  unclass(x)
}

#' @export
as.double.zuyaml_bigint <- function(x, ...) {
  # Deliberately lossy: that is the whole reason this class exists.
  as.numeric(unclass(x))
}

#' @export
`[.zuyaml_bigint` <- function(x, ...) {
  structure(unclass(x)[...], class = "zuyaml_bigint")
}

#' Mappings whose keys are not scalars
#'
#' YAML mapping keys can be sequences or mappings, which cannot become R names
#' without destroying structure. [yaml_parse()] represents such a mapping as a
#' `zuyaml_map`: two parallel lists, `keys` and `values`.
#'
#' This is parse-only. The vendored cyaml builder can only attach string keys,
#' so a `zuyaml_map` cannot be emitted; see `vignette("zuyaml")` for the full
#' list of conversions that do not round-trip.
#'
#' @param x A `zuyaml_map`.
#' @param ... Ignored.
#' @return `print()` returns `x` invisibly.
#'
#' @examples
#' yaml_parse("? [one, two]\n: value\n")
#' @name zuyaml_map
#' @export
print.zuyaml_map <- function(x, ...) {
  n <- length(x$keys)
  cat(sprintf("<zuyaml_map> %d pair%s\n", n, if (n == 1L) "" else "s"))
  for (i in seq_len(n)) {
    cat("  key:   ", paste(deparse(x$keys[[i]]), collapse = " "), "\n", sep = "")
    cat("  value: ", paste(deparse(x$values[[i]]), collapse = " "), "\n", sep = "")
  }
  invisible(x)
}

#' @export
length.zuyaml_map <- function(x) {
  length(unclass(x)$keys)
}
