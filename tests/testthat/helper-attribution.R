# Helpers for test-attribution.R, kept out of it so that the file's tests can run in
# any order: devtools::test(shuffle = TRUE) shuffles top-level expressions,
# and a test shuffled ahead of a file-scope definition cannot find it.

authors_at_r <- function() {
  field <- utils::packageDescription("zuyaml", fields = "Authors@R")
  eval(parse(text = field))
}
