#!/usr/bin/env Rscript
#
# Select a small, representative subset of the yaml-test-suite to ship with
# the package, so that CRAN test time stays reasonable while the constructs
# most likely to break a wrapper stay covered. CI runs the full suite.
#
# Usage:  Rscript tools/curate-test-suite.R /path/to/yaml-test-suite
#
# Only `===`, `in.yaml` and the `error` marker are copied; the event and JSON
# files are not used by these tests.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("usage: curate-test-suite.R <suite-dir>")
src <- args[[1]]
dest <- "tests/testthat/fixtures/yaml-test-suite"

# Every leaf case, whether or not its identifier uses numbered subdirectories.
leaves <- dirname(list.files(src, pattern = "^in\\.yaml$", recursive = TRUE,
                             full.names = TRUE))
# The suite also exposes every case a second time under name/, keyed by its
# description. Those paths are long enough to exceed the 100-byte limit a
# tarball guarantees for a path component, and they are duplicates anyway.
leaves <- leaves[!grepl("(^|/)name/", leaves)]
desc <- vapply(leaves, function(d) {
  f <- file.path(d, "===")
  if (file.exists(f)) readLines(f, n = 1L, warn = FALSE) else ""
}, character(1))
failing <- file.exists(file.path(leaves, "error"))

# Constructs where a wrapper is most likely to go wrong: the R conversion
# layer, not cyaml, is what these are guarding.
topics <- c(
  anchor = "[Aa]nchor|[Aa]lias",
  tag = "[Tt]ag",
  block = "[Bb]lock|[Ll]iteral|[Ff]olded",
  flow = "[Ff]low",
  escape = "[Ee]scape|[Qq]uote",
  key = "[Kk]ey|[Mm]apping",
  directive = "[Dd]irective|%YAML",
  scalar = "[Ss]calar|[Pp]lain",
  empty = "[Ee]mpty|[Nn]ull",
  unicode = "[Uu]nicode|UTF|BOM",
  spec = "^Spec Example"
)

set.seed(1L) # a fixed subset, so the fixtures do not churn between runs
picked <- character()
for (nm in names(topics)) {
  hit <- which(grepl(topics[[nm]], desc))
  # Take a few of each topic, always including invalid documents.
  bad <- intersect(hit, which(failing))
  good <- setdiff(hit, bad)
  picked <- c(
    picked,
    leaves[head(sample(bad), 3L)],
    leaves[head(sample(good), 4L)]
  )
}
# Guarantee a decent share of invalid documents overall.
picked <- unique(c(picked, leaves[head(sample(which(failing)), 20L)]))
picked <- unique(picked[!is.na(picked)])

unlink(dest, recursive = TRUE)
dir.create(dest, recursive = TRUE, showWarnings = FALSE)

for (d in picked) {
  id <- sub(paste0("^", src, "/?"), "", d)
  id <- gsub("/", "-", id)
  # Keep well inside the 100-byte tarball limit for a path component.
  if (nchar(id) > 32L) id <- substr(id, 1L, 32L)
  out <- file.path(dest, id)
  dir.create(out, showWarnings = FALSE)
  file.copy(file.path(d, "in.yaml"), file.path(out, "in.yaml"))
  if (file.exists(file.path(d, "==="))) {
    file.copy(file.path(d, "==="), file.path(out, "==="))
  }
  if (file.exists(file.path(d, "error"))) {
    file.create(file.path(out, "error"))
  }
}

cat(sprintf(
  "curated %d cases (%d expected to fail) into %s\n",
  length(picked), sum(file.exists(file.path(picked, "error"))), dest
))
