# Nesting depth: the limit, the scanner's share of it, and the C stack (#8,
# #28). tools/ci/stack-depth.R runs the same cases under reduced stacks in
# hardening.yaml, which R cannot set for itself.

test_that("max_depth trips at limit + 1 in every nesting shape (#8)", {
  for (shape in nest_shapes) {
    for (limit in c(1L, 2L, 5L, 128L)) {
      info <- paste(shape, limit)
      expect_identical(depth_result(nest(shape, limit - 1L), max_depth = limit), "ok", info = info)
      expect_identical(depth_result(nest(shape, limit), max_depth = limit), "ok", info = info)
      expect_identical(depth_result(nest(shape, limit + 1L), max_depth = limit), "limit_depth", info = info)
    }
  }
  # The default is 128.
  for (shape in nest_shapes) {
    expect_identical(depth_result(nest(shape, 128L)), "ok", info = shape)
    expect_identical(depth_result(nest(shape, 129L)), "limit_depth", info = shape)
  }
})

test_that("the scanner refuses deep flow nesting where it starts (#28)", {
  # Scanning flow collections costs O(tokens x flow depth). Before patch 0006
  # the whole document was scanned before the depth was checked, so these
  # took minutes; now the scanner stops at the bracket that crosses the limit
  # and says where it is. Conversion errors carry no position, so the line
  # and column are the evidence that the scanner refused it.
  for (shape in c("flow_seq", "flow_map")) {
    err <- tryCatch(yaml_parse(nest(shape, 1e5L)), zuyaml_error = identity)
    expect_s3_class(err, "zuyaml_parse_error")
    expect_identical(err$code, "limit_depth", info = shape)
    expect_identical(err$line, 1L, info = shape)
    step <- if (shape == "flow_seq") 1L else 4L # "[" or "{a: "
    expect_identical(err$column, 128L * step + 1L, info = shape)
  }

  # Every document of a stream gets the same scanner.
  stream <- paste0("--- [1]\n--- ", nest("flow_seq", 1e5L), "\n")
  err <- tryCatch(yaml_parse_all(stream), zuyaml_error = identity)
  expect_identical(err$code, "limit_depth")
  expect_identical(err$line, 2L)

  # Without a limit, the scanner does not refuse either.
  expect_type(yaml_parse(nest("flow_seq", 1000L), max_depth = 0), "list")
})

test_that("nesting deeper than the C stack is an R error, not a crash (#8)", {
  # Conversion and emitting recurse in C, once per level, and neither cyaml's
  # parser nor its emitter does. R_CheckStack() at each level turns running
  # out into R's stackOverflowError. Without it, R's segfault handler reports
  # "segfault from C stack overflow" and the session ends.
  #
  # The check needs R to know its stack size; when it does not (an unlimited
  # stack), R_CheckStack() checks nothing.
  stack <- Cstack_info()[["size"]]
  skip_if(is.na(stack), "R does not know its C stack size")
  skip_if(stack > 256 * 1024^2, "C stack larger than 256 MB")
  # A limit check, not a memory-safety one, and under gctorture every
  # collection re-marks the deep list (r-actions gctorture.yml says the same).
  skip_if(gctorture_on(), "gctorture is on")
  # Every level costs more than 64 bytes of stack (tools/ci/stack-depth.sh
  # measures 100 to 200), so this depth is beyond the stack with room to spare.
  d <- as.integer(stack / 32)

  # Caught with tryCatch(), not expect_error(): an exiting handler unwinds
  # before it runs, where a calling handler would run R code on a stack that
  # is already full, and overflow again.
  overflow <- function(expr) {
    tryCatch({
      expr
      "no error"
    }, stackOverflowError = function(e) "stackOverflowError")
  }

  # Block sequences, because their scan is linear in depth.
  deep <- nest("block_seq", d)
  expect_identical(
    overflow(yaml_parse(deep, max_depth = 0, max_nodes = 0)),
    "stackOverflowError"
  )
  nested <- deep_list(d)
  expect_identical(overflow(yaml_emit(nested)), "stackOverflowError")

  # Both unwound cleanly: the stream and the document were owned.
  expect_identical(yaml_parse("a: [1, 2]"), list(a = list(1L, 2L)))
  expect_identical(yaml_emit(list(a = 1L)), "a: 1\n")
})

test_that("a document both too deep and invalid reports limit_depth (#34)", {
  # The scanner stops at the first bracket past max_depth, before the later
  # syntax error is reached. 0.1.0 reported "syntax" here.
  doc <- "- [[[[1]]]]\n- {a: 1, b: 2"
  err <- tryCatch(yaml_parse(doc, max_depth = 3), zuyaml_error = identity)
  expect_s3_class(err, "zuyaml_parse_error")
  expect_identical(err$code, "limit_depth")
  expect_identical(err$line, 1L)
  # Within the limit, the syntax error is what is reported.
  err <- tryCatch(yaml_parse(doc, max_depth = 10), zuyaml_error = identity)
  expect_identical(err$code, "syntax")
})
