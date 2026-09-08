#!/usr/bin/env Rscript
#
# Exercise the C layer under a sanitizer, using nothing but base R.
#
# The sanitizer jobs care about the compiled code: memory errors, undefined
# behaviour, and leaks on the unwind path. They do not care about testthat's
# assertions. Depending on testthat made the jobs fail for an unrelated reason
# -- the r-hub containers' binary repository does not host it, and building it
# and its twenty-odd dependencies from source under a sanitizer is slow and
# fragile. So this script has no dependencies at all.
#
# It deliberately spends most of its effort on *error* paths. An R error is a
# longjmp that skips the explicit cyaml_stream_free() and leaves the
# external-pointer finalizer to reclaim the stream, which is the single most
# delicate thing in the C layer and the thing a leak checker is best placed to
# catch.
#
# Usage:  Rscript tools/sanitizer-exercise.R [conformance-dir]

library(zuyaml)

args <- commandArgs(trailingOnly = TRUE)
suite <- if (length(args) >= 1L) args[[1]] else ""

failures <- 0L
checked <- 0L

check <- function(label, expr) {
  checked <<- checked + 1L
  ok <- tryCatch(isTRUE(expr), error = function(e) {
    message("  ERROR in ", label, ": ", conditionMessage(e))
    FALSE
  })
  if (!ok) {
    failures <<- failures + 1L
    message("  FAILED: ", label)
  }
  invisible(ok)
}

# Anything that raises a zuyaml condition is fine; a crash or a bare R error is
# not, and the sanitizer will say so independently.
quietly <- function(expr) {
  tryCatch({ force(expr); "ok" },
           zuyaml_error = function(e) "condition",
           error = function(e) paste0("bare: ", conditionMessage(e)))
}

cat("-- round trips --------------------------------------------------\n")

values <- list(
  NULL, TRUE, FALSE, 42L, -7L, 3.14159265358979, Inf, -Inf, NaN,
  "hello", "42", "true", "", "café — 日本語",
  list(1L, 2L, 3L), list(a = 1L, b = "x"),
  list(a = list(b = list(c = 1L))),
  as.list(seq_len(50)), as.list(letters),
  structure(list(), names = character()), list()
)
for (v in values) {
  check(paste("round trip", deparse(v)[1]),
        identical(yaml_parse(yaml_emit(v)), v))
}

# The list-versus-vector distinction is documented as not surviving a round
# trip: a list holding a vector emits as a nested sequence and comes back as a
# nested list. Assert the documented behaviour rather than pretending otherwise.
check("list/vector asymmetry is as documented",
      identical(yaml_parse(yaml_emit(list(1:3))), list(list(1L, 2L, 3L))))
check("simplify recovers the vector",
      identical(yaml_parse(yaml_emit(list(1:3)), simplify = TRUE), list(1:3)))

cat("-- parsing, including every error path ---------------------------\n")

sources <- c(
  "a: 1", "[1, 2, 3]", "- a\n- b", "null", "~", '""', "{}", "[]",
  "a: &x 1\nb: *x", "? [one, two]\n: value", "9223372036854775807",
  "0x1F", ".inf", ".nan", "2026-09-07", "|\n  block\n", ">\n  folded\n",
  "---\na: 1\n---\nb: 2\n", "%YAML 1.2\n---\na: 1\n",
  # error paths
  "a: [1, 2", "a: 1\na: 2", "&x [*x]", "b: *nope", "\t- x",
  "", "# comment only", "a:\n\t- b", "[", "{", "\"unterminated",
  paste0(strrep("[", 400), strrep("]", 400))
)
for (src in sources) {
  r <- quietly(yaml_parse_all(src, max_nodes = 1e5))
  check(paste("parse:", substr(encodeString(src), 1, 28)),
        r %in% c("ok", "condition"))
}

cat("-- limits and hostile input --------------------------------------\n")

bomb <- paste0(
  "a: &a [x,x,x,x,x,x,x,x,x]\n",
  "b: &b [*a,*a,*a,*a,*a,*a,*a,*a,*a]\n",
  "c: &c [*b,*b,*b,*b,*b,*b,*b,*b,*b]\n",
  "d: &d [*c,*c,*c,*c,*c,*c,*c,*c,*c]\n",
  "e: [*d,*d,*d,*d,*d,*d,*d,*d,*d]\n"
)
check("alias bomb is refused", quietly(yaml_parse(bomb, max_nodes = 1000)) == "condition")
check("max_depth is refused", quietly(yaml_parse(strrep("- ", 300), max_depth = 8)) == "condition")
check("max_size is refused", quietly(yaml_parse("a: 1", max_size = 2)) == "condition")
check("embedded NUL is refused",
      quietly(yaml_parse(rawToChar(as.raw(c(0x22, 0x5c, 0x30, 0x22))))) == "condition")

cat("-- unwind path (errors while the C stream is live) ---------------\n")

# This is the loop that matters most: each iteration raises an R error from
# inside the conversion, so the explicit free is skipped every time. A leak
# here is what LeakSanitizer exists to find.
for (i in seq_len(3000L)) {
  invisible(quietly(yaml_parse("a: 1\na: 2\n")))
  invisible(quietly(yaml_parse("a: [1, 2")))
  invisible(quietly(yaml_emit(list(a = 1, 2))))
}
check("unwind loop completed", TRUE)
gc()

cat("-- fuzz ----------------------------------------------------------\n")

set.seed(20260908L)
for (i in seq_len(3000L)) {
  n <- sample.int(100L, 1L)
  bytes <- as.raw(sample.int(256L, n, replace = TRUE) - 1L)
  r <- quietly(yaml_parse_all(bytes, max_depth = 64, max_nodes = 1e4))
  if (!r %in% c("ok", "condition")) {
    failures <- failures + 1L
    message("  FAILED fuzz: ", r)
  }
}
check("fuzz completed", TRUE)

if (nzchar(suite) && dir.exists(suite)) {
  cat("-- conformance corpus --------------------------------------------\n")
  inputs <- list.files(suite, pattern = "^in\\.yaml$", recursive = TRUE,
                       full.names = TRUE)
  inputs <- inputs[!grepl("(^|/)name/", inputs)]
  for (path in inputs) {
    bytes <- readBin(path, "raw", n = file.info(path)$size)
    r <- quietly(yaml_parse_all(bytes, max_nodes = 1e5))
    if (!r %in% c("ok", "condition")) {
      failures <- failures + 1L
      message("  FAILED ", basename(dirname(path)), ": ", r)
    }
  }
  cat("  ", length(inputs), " cases\n", sep = "")
}

cat("\n", checked, " checks, ", failures, " failures\n", sep = "")
if (failures > 0L) quit(status = 1L)
