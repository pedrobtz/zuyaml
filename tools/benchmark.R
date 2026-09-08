#!/usr/bin/env Rscript
#
# Benchmark zuyaml against the yaml package.
#
# Usage:  Rscript tools/benchmark.R
#
# Performance is not the reason this package exists, so these numbers exist to
# guide implementation, not to make claims. Two things in particular are worth
# watching:
#
#   * where the time actually goes -- the YAML engine or the allocation of R
#     objects. The design takes a zero-copy path for plain scalars precisely
#     because R conversion was expected to dominate; this is the measurement
#     that confirms or refutes that.
#
#   * what max_nodes should default to. The current 1e7 was chosen for order of
#     magnitude, not measured against a real large document.
#
# Requires: yaml, bench.

suppressMessages({
  library(zuyaml)
})
stopifnot(requireNamespace("yaml", quietly = TRUE),
          requireNamespace("bench", quietly = TRUE))

# --- corpus ---------------------------------------------------------------

small_config <- paste0(
  "name: zuyaml\n",
  "version: 0.0.1\n",
  "debug: false\n",
  "timeout: 30\n",
  "tags:\n  - a\n  - b\n"
)

k8s_like <- paste0(
  "apiVersion: apps/v1\nkind: Deployment\n",
  "metadata:\n  name: web\n  labels:\n    app: web\n    tier: frontend\n",
  "spec:\n  replicas: 3\n  selector:\n    matchLabels:\n      app: web\n",
  "  template:\n    metadata:\n      labels:\n        app: web\n",
  "    spec:\n      containers:\n",
  paste0(
    "        - name: c", 1:8, "\n",
    "          image: registry.example.com/web:1.0\n",
    "          ports:\n            - containerPort: 8080\n",
    "          env:\n            - name: MODE\n              value: \"prod\"\n",
    collapse = ""
  )
)

large_array <- paste0("- ", seq_len(20000L), "\n", collapse = "")
large_strings <- paste0("- \"item-", seq_len(20000L), "\"\n", collapse = "")

deep_nesting <- paste0(
  paste(rep("a:\n", 60), collapse = ""),
  paste(rep(" ", 60), collapse = ""), "1\n"
)
deep_nesting <- paste0(strrep("[", 60), "1", strrep("]", 60))

multi_doc <- paste0(rep("---\na: 1\nb: [1, 2, 3]\n", 500), collapse = "")

corpus <- list(
  "small config" = small_config,
  "kubernetes-style" = k8s_like,
  "20k integers" = large_array,
  "20k strings" = large_strings,
  "deep nesting" = deep_nesting,
  "500 documents" = multi_doc
)

# --- parsing ---------------------------------------------------------------

cat("\n== parsing ==\n\n")
for (nm in names(corpus)) {
  src <- corpus[[nm]]
  multi <- nm == "500 documents"

  res <- bench::mark(
    zuyaml = if (multi) yaml_parse_all(src) else yaml_parse(src),
    yaml = if (multi) yaml::yaml.load(src) else yaml::yaml.load(src),
    check = FALSE,
    iterations = if (nchar(src) > 100000) 10 else 100,
    time_unit = "ms"
  )
  cat(sprintf(
    "%-18s %8.2f ms   %8.2f ms   %5.2fx   (%s)\n",
    nm, res$median[1], res$median[2],
    as.numeric(res$median[2]) / as.numeric(res$median[1]),
    format(structure(nchar(src), class = "object_size"), units = "auto")
  ))
}
cat("\n(columns: zuyaml, yaml, ratio, input size; >1 means zuyaml is faster)\n")

# --- emission --------------------------------------------------------------

cat("\n== emission ==\n\n")
for (nm in names(corpus)) {
  if (nm == "500 documents") next
  obj <- yaml_parse(corpus[[nm]])

  res <- bench::mark(
    zuyaml = yaml_emit(obj),
    yaml = yaml::as.yaml(obj),
    check = FALSE,
    iterations = if (nchar(corpus[[nm]]) > 100000) 10 else 100,
    time_unit = "ms"
  )
  cat(sprintf(
    "%-18s %8.2f ms   %8.2f ms   %5.2fx\n",
    nm, res$median[1], res$median[2],
    as.numeric(res$median[2]) / as.numeric(res$median[1])
  ))
}

# --- where does the time go? ----------------------------------------------

# The design's open question: is the bottleneck the YAML engine or building R
# objects? Parsing the same document twice, once keeping the result and once
# discarding it, does not separate them -- but comparing a document of many
# small scalars against one of few large ones does, because the first makes
# many R allocations for the same number of parsed bytes.

cat("\n== engine vs R allocation ==\n\n")
many_small <- paste0("- ", seq_len(20000L), "\n", collapse = "")
few_large <- paste0("- \"", strrep("x", 5000), "\"\n", collapse = "")
few_large <- paste0(rep(few_large, 20), collapse = "")

for (nm in c("20000 tiny scalars", "20 large scalars")) {
  src <- if (nm == "20000 tiny scalars") many_small else few_large
  t <- bench::mark(yaml_parse(src), iterations = 20, time_unit = "ms")
  cat(sprintf("%-20s %8.2f ms for %8s of input\n", nm, t$median[1],
              format(structure(nchar(src), class = "object_size"),
                     units = "auto")))
}
cat("\nA large gap per byte between these two means R allocation dominates,\n")
cat("which is what the zero-copy path for plain scalars is there to reduce.\n")

# --- installed size --------------------------------------------------------

cat("\n== footprint ==\n\n")
for (p in c("zuyaml", "yaml")) {
  d <- system.file(package = p)
  if (nzchar(d)) {
    sz <- sum(file.info(list.files(d, recursive = TRUE, full.names = TRUE))$size,
              na.rm = TRUE)
    cat(sprintf("%-8s %s installed\n", p,
                format(structure(sz, class = "object_size"), units = "auto")))
  }
}
cat("\n")
