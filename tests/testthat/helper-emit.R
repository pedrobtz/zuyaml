# Helpers for test-emit.R, kept out of it so that the file's tests can run in
# any order: devtools::test(shuffle = TRUE) shuffles top-level expressions,
# and a test shuffled ahead of a file-scope definition cannot find it.

emitted <- function(x, ...) sub("\n$", "", yaml_emit(x, ...))
