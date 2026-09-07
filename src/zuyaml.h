#ifndef ZUYAML_H
#define ZUYAML_H

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

#include "cyaml.h"

/*
 * Unwind-safe ownership of a cyaml stream.
 *
 * R's error mechanism is a longjmp, so an Rf_error() -- or an allocation
 * failure, or a user interrupt -- anywhere between cyaml_parse_stream() and
 * cyaml_stream_free() would skip the free and leak the whole document tree.
 * PROTECT does not help: it guards against the garbage collector, not against
 * unwinding.
 *
 * zuyaml_stream_own() hands the stream to a transient external pointer with a
 * finalizer. On the normal path, zuyaml_stream_release() frees it immediately.
 * On an unwind the external pointer becomes unreachable and the finalizer
 * frees it at the next garbage collection.
 *
 * This is function-scoped and never reaches R code, so it does not contradict
 * the design's "no persistent C document pointers" rule -- see the unwind
 * safety section of .agents/DESIGN-zuyaml.md.
 *
 * Usage:
 *     SEXP owner = PROTECT(zuyaml_stream_own(stream));
 *     ... conversion, which may raise R errors ...
 *     zuyaml_stream_release(owner);
 *     UNPROTECT(1);
 */
SEXP zuyaml_stream_own(cyaml_stream_t* stream);
void zuyaml_stream_release(SEXP owner);

/* Errors: build and signal classed R conditions. Both are noreturn. */
const char* zuyaml_err_code(cyaml_err_t code);

_Noreturn void zuyaml_stop_parse_error(
    const cyaml_error_t* err, SEXP path);

_Noreturn void zuyaml_stopf(
    const char* code, SEXP path, const char* fmt, ...);

/* .Call entry points (registered in init.c). */
SEXP zuyaml_parse_(SEXP x, SEXP duplicate_keys, SEXP max_depth,
    SEXP max_size, SEXP path);

/* Conversion of a cyaml node to an R object. */
SEXP zuyaml_convert_node(const cyaml_doc_t* doc, const cyaml_node_t* node);

#endif /* ZUYAML_H */
