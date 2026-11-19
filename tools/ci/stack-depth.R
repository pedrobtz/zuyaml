# Nesting depth against the C stack (#8), for tools/ci/stack-depth.sh.
#
# Usage:  Rscript tools/ci/stack-depth.R [--large-output]
#
# Run under a reduced stack (`ulimit -s`), which R cannot set for itself. A
# crash is a non-zero exit, so this script failing to finish is the failure
# it exists to catch. It checks three things and measures one:
#
#   1. With default arguments every nesting shape is refused at depth 129 with
#      limit_depth, never with a stack error, at every stack size.
#   2. With max_depth = 0, a document deeper than the stack is R's
#      stackOverflowError, and so is emitting a list that deep.
#   3. After either, an ordinary parse and emit still work.
#
# And it reports the depth at which the stack runs out, by bisection, for
# conversion and for emitting. Its ratio to the default max_depth is the
# actual safety margin; it must be at least 4.
#
# --large-output also emits a document longer than an R string can hold,
# which must be limit_size. It needs about 4 GB of memory.

# The installed package, not pkgload::load_all(): pkgload does not fit in a
# 256 KB stack. tools/ci/stack-depth.sh installs it.
library(zuyaml)
source("tests/testthat/helper-depth.R")

args <- commandArgs(TRUE)
fail <- function(...) {
  cat("FAIL:", ..., "\n")
  quit(status = 1)
}
classify <- function(expr) {
  tryCatch({
    expr
    "ok"
  },
  stackOverflowError = function(e) "stackOverflowError",
  zuyaml_error = function(e) e$code)
}

stack <- Cstack_info()[["size"]]
cat(sprintf("C stack: %s bytes\n", format(stack, big.mark = ",")))
if (is.na(stack)) fail("R does not know its C stack size; nothing to test")

default_depth <- formals(yaml_parse)$max_depth
for (shape in nest_shapes) {
  # Deep, but within max_size: a block mapping indents every level, so 10,000
  # levels of one would be 100 MB, which is limit_size.
  deep <- if (shape == "block_map") 1000L else 10000L
  for (d in c(default_depth - 1L, default_depth, default_depth + 1L, deep)) {
    want <- if (d <= default_depth) "ok" else "limit_depth"
    got <- classify(yaml_parse(nest(shape, d)))
    if (!identical(got, want)) fail(shape, d, "gave", got, "not", want)
  }
}
cat("default limits: every shape refused at", default_depth + 1L, "\n")

# The smallest depth in [lo, hi] at which `f(depth)` overflows, to within 1%.
trip_depth <- function(f, lo, hi) {
  if (!identical(f(hi), "stackOverflowError")) fail("no overflow at depth", hi)
  while (hi - lo > max(1L, lo %/% 100L)) {
    mid <- (lo + hi) %/% 2L
    if (identical(f(mid), "stackOverflowError")) hi <- mid else lo <- mid
  }
  hi
}
parse_at <- function(shape) {
  function(d) {
    classify(yaml_parse(nest(shape, d), max_depth = 0, max_nodes = 0,
                        max_size = 0))
  }
}
emit_at <- function(d) {
  x <- deep_list(d)
  classify(yaml_emit(x))
}

# Every shape where that is quick. Flow nesting scans in quadratic time once
# max_depth is lifted (#28), and the block mapping's input is quadratic in
# depth, so on a large stack only the block sequence is measured.
hi <- as.integer(stack %/% 32) # no level costs fewer than 32 bytes
shapes <- if (stack <= 1.1 * 1024^2) nest_shapes else "block_seq"
trips <- vapply(shapes, function(s) trip_depth(parse_at(s), 1L, hi), integer(1))
emit_trip <- trip_depth(emit_at, 1L, hi)

if (!identical(classify(yaml_parse("a: [1, 2]")), "ok")) fail("parse after overflow")
if (!identical(yaml_emit(list(a = 1L)), "a: 1\n")) fail("emit after overflow")

cat("stack runs out at (levels, bytes per level):\n")
for (s in names(trips)) {
  cat(sprintf("  parse %-16s %7d  %4.0f\n", s, trips[[s]], stack / trips[[s]]))
}
cat(sprintf("  emit  %-16s %7d  %4.0f\n", "list", emit_trip, stack / emit_trip))
margin <- min(trips) / default_depth
cat(sprintf("margin over the default max_depth (%d): %.1fx\n", default_depth, margin))
if (margin < 4) fail("margin below 4x")

if ("--large-output" %in% args) {
  # 50,000 levels of block sequence: about 2.5 GB of indentation.
  x <- deep_list(50000L)
  got <- classify(yaml_emit(x))
  if (!identical(got, "limit_size")) fail("2.5 GB emit gave", got)
  cat("emit beyond INT_MAX bytes: limit_size\n")
}
cat("OK\n")
