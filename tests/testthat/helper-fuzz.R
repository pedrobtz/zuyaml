# Helpers for test-fuzz.R, kept out of it so that the file's tests can run in
# any order: devtools::test(shuffle = TRUE) shuffles top-level expressions,
# and a test shuffled ahead of a file-scope definition cannot find it.

fuzz_iterations <- function(default = 200L) {
  n <- suppressWarnings(as.integer(Sys.getenv("ZUYAML_FUZZ", "")))
  if (is.na(n) || n <= 0L) default else n
}

parse_quietly <- function(bytes) {
  tryCatch(
    {
      yaml_parse_all(bytes, max_depth = 64, max_nodes = 1e5)
      "ok"
    },
    zuyaml_error = function(e) "condition",
    error = function(e) paste0("bare R error: ", conditionMessage(e))
  )
}
