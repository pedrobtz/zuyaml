# The `code` of the zuyaml condition `expr` raises, or NA when it raises none.
# Callers rely on `code`, so tests assert it rather than message text (#36).
# Any other error is not caught, so it fails the test loudly.
error_code <- function(expr) {
  tryCatch({
    expr
    NA_character_
  }, zuyaml_error = function(e) e$code)
}
