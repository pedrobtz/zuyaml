# Documents nested exactly `d` collections deep, one per shape that recurses.
# Each holds a scalar at the bottom, so depth d is d collections around it.
nest <- function(shape, d) {
  switch(shape,
    flow_seq = paste0(strrep("[", d), "1", strrep("]", d)),
    flow_map = paste0(strrep("{a: ", d), "1", strrep("}", d)),
    block_seq = paste0(strrep("- ", d), "1"),
    block_map = paste0(
      paste0(strrep("  ", seq_len(d) - 1L), "a:", collapse = "\n"), " 1"
    ),
    # Alternating flow sequence and flow mapping: [{a: [{a: 1}]}]
    flow_mixed = {
      open <- rep_len(c("[", "{a: "), d)
      close <- rev(rep_len(c("]", "}"), d))
      paste0(paste(open, collapse = ""), "1", paste(close, collapse = ""))
    },
    # Block mappings around flow sequences: every level counts, but only the
    # flow half is visible to the scanner's check, so conversion must still
    # catch what the scanner lets through.
    block_then_flow = {
      b <- d %/% 2L
      f <- d - b
      if (b == 0L) {
        return(paste0(strrep("[", f), "1", strrep("]", f)))
      }
      paste0(
        paste0(strrep("  ", seq_len(b) - 1L), "a:", collapse = "\n"), " ",
        strrep("[", f), "1", strrep("]", f)
      )
    }
  )
}

nest_shapes <- c("flow_seq", "flow_map", "block_seq", "block_map",
                 "flow_mixed", "block_then_flow")

depth_result <- function(doc, ...) {
  tryCatch({
    yaml_parse(doc, ...)
    "ok"
  }, zuyaml_error = function(e) e$code)
}

# A list nested `d` levels deep around 1, built without recursion.
deep_list <- function(d) {
  x <- 1
  for (i in seq_len(d)) x <- list(x)
  x
}

# Whether gctorture is on. gctorture2() reports the previous step as it sets a
# new one, so this turns it off and straight back on, with the same step.
gctorture_on <- function() {
  step <- gctorture2(0)
  if (step > 0) gctorture2(step)
  step > 0
}
