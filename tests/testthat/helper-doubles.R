# Build a double from its IEEE-754 bit pattern, most significant byte first.
#
# The only spelling of a double that means the same thing on every platform.
# An R source literal does not qualify, and the reasons are not academic --
# see "double expectations are written as bit patterns" in test-scalars.R for
# the three ways R's own reader disagrees with the correctly rounded value on
# aarch64, including reading DBL_MAX as Inf and every subnormal hex literal
# as 0.
#
# The practice is borrowed from `zujson`, which hit the same thing on CI.
dbl <- function(hex) {
  stopifnot(nchar(hex) == 16L)
  bytes <- as.raw(strtoi(substring(hex, seq(1L, 15L, 2L), seq(2L, 16L, 2L)), 16L))
  readBin(bytes, "double", n = 1L, size = 8L, endian = "big")
}
