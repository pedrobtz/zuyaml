#' Version of the vendored cyaml library
#'
#' Reports the version string compiled into the bundled cyaml sources. Used to
#' verify that the vendored code and the provenance recorded in
#' `inst/cyaml-VERSION` agree.
#'
#' @return A length-one character vector, e.g. `"0.1.3"`.
#' @keywords internal
#' @noRd
cyaml_version <- function() {
  .Call(zuyaml_cyaml_version_)
}
