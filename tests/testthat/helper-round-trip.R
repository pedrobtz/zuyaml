# Helpers for test-round-trip.R, kept out of it so that the file's tests can run in
# any order: devtools::test(shuffle = TRUE) shuffles top-level expressions,
# and a test shuffled ahead of a file-scope definition cannot find it.

round_trips <- function(value, ...) {
  text <- yaml_emit(value, ...)
  identical(yaml_parse(text, ...), value)
}

# Characters chosen so that a random draw lands on the constructs that break
# plain scalars: line breaks, edge whitespace, YAML indicators, and the reserved
# words. Plain letters are included so that most strings stay ordinary.
alphabet <- c(
  letters[1:6], "0", "1", "7", " ", " ", "\t", "\n", "\r", "\n",
  "#", ":", "-", "?", ",", "[", "]", "{", "}", "&", "*", "!", "|", ">",
  "'", "\"", "%", "@", "`", ".", "\\", "é", "☃"
)
random_strings <- function(n, max_len = 12L) {
  vapply(seq_len(n), function(i) {
    len <- sample.int(max_len + 1L, 1L) - 1L
    paste0(sample(alphabet, len, replace = TRUE), collapse = "")
  }, character(1))
}
