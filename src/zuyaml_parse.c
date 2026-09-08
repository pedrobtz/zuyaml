#include <string.h>

#include "zuyaml.h"

/* --- unwind-safe stream ownership ------------------------------------- */

static void stream_finalizer(SEXP owner)
{
    cyaml_stream_t* stream = (cyaml_stream_t*)R_ExternalPtrAddr(owner);
    if (stream != NULL) {
        cyaml_stream_free(stream);
        R_ClearExternalPtr(owner);
    }
}

SEXP zuyaml_stream_own(cyaml_stream_t* stream)
{
    SEXP owner = PROTECT(R_MakeExternalPtr(stream, R_NilValue, R_NilValue));
    /* onexit = TRUE: also run at R shutdown, so a session ending mid-parse
       does not report a leak under sanitizers. */
    R_RegisterCFinalizerEx(owner, stream_finalizer, TRUE);
    UNPROTECT(1);
    return owner;
}

void zuyaml_stream_release(SEXP owner)
{
    stream_finalizer(owner);
}

/* --- input ------------------------------------------------------------- */

/*
 * Obtain UTF-8 bytes from the R input.
 *
 * The returned pointer is borrowed and must stay valid for as long as the
 * cyaml stream lives: cyaml parses zero-copy, and every scalar is an offset
 * into this buffer. Both cases below satisfy that as long as `x` stays
 * protected for the duration of the .Call:
 *
 *   - RAWSXP: points directly at the vector's data.
 *   - STRSXP: Rf_translateCharUTF8 either returns the CHARSXP's own bytes
 *     (already UTF-8 or ASCII) or an R_alloc'd copy valid until the .Call
 *     returns.
 */
static const char* input_bytes(SEXP x, size_t* len, SEXP path)
{
    if (TYPEOF(x) == RAWSXP) {
        *len = (size_t)XLENGTH(x);
        return (const char*)RAW(x);
    }

    if (TYPEOF(x) == STRSXP && XLENGTH(x) == 1
        && STRING_ELT(x, 0) != NA_STRING) {
        const char* s = Rf_translateCharUTF8(STRING_ELT(x, 0));
        *len = strlen(s);
        return s;
    }

    zuyaml_stopf("invalid_input", path,
        "`x` must be a single string or a raw vector.");
}

/* --- options ----------------------------------------------------------- */

static uint32_t as_uint32(SEXP x, const char* arg, SEXP path)
{
    double v;

    if (Rf_length(x) != 1) {
        zuyaml_stopf("invalid_input", path, "`%s` must be a single number.",
            arg);
    }
    v = Rf_asReal(x);
    if (!R_FINITE(v) || v < 0 || v > 4294967295.0) {
        zuyaml_stopf("invalid_input", path,
            "`%s` must be between 0 and 4294967295.", arg);
    }
    return (uint32_t)v;
}

/* --- entry point -------------------------------------------------------- */

/*
 * Parse `x` as a YAML *stream* and return a list with one element per
 * document. yaml_parse() is an R-level wrapper that requires the list to have
 * length 1; see the design's "one document versus many" section. Parsing as a
 * stream unconditionally is what makes it impossible to silently accept only
 * the first document.
 */
SEXP zuyaml_parse_(SEXP x, SEXP simplify, SEXP aliases, SEXP big_integers,
    SEXP tags, SEXP duplicate_keys, SEXP max_depth, SEXP max_size,
    SEXP max_nodes, SEXP path)
{
    const char* src;
    size_t len;
    cyaml_opts_t opts = { 0 };
    cyaml_error_t err = { 0 };
    cyaml_stream_t* stream;
    uint32_t n_docs, i;
    SEXP owner, out;
    zuyaml_ctx_t ctx;

    src = input_bytes(x, &len, path);

    /* cyaml_parse_stream takes a size_t, but cyaml_span_t offsets and
       cyaml_stream_t.src_len are uint32_t, so the real ceiling is 4 GiB.
       R raw vectors can exceed that on 64-bit builds. Refuse explicitly
       rather than silently truncating. */
    if (len > 4294967295u) {
        zuyaml_stopf("limit_size", path,
            "Input is larger than 4 GiB, which cyaml cannot address.");
    }

    /* Upstream's defaults are max_depth = 1000, max_size = 0 (unlimited) and
       spec = CYAML_SPEC_AUTO. All three are overridden deliberately; the
       explicit spec is what pins the package to YAML 1.2 semantics. */
    /* NOTE: cyaml v0.1.3 never reads opts.dup_keys and never raises
       CYAML_ERR_DUP_KEY -- the option is declared in the public header and
       nowhere else. Duplicate-key rejection is enforced by zuyaml during
       mapping conversion. This is set anyway so that a future upstream
       version which honours it agrees with our own behaviour. */
    opts.dup_keys = (Rf_asLogical(duplicate_keys) == TRUE);
    opts.preserve_comments = false;
    opts.max_depth = as_uint32(max_depth, "max_depth", path);
    opts.max_size = as_uint32(max_size, "max_size", path);
    opts.spec = CYAML_SPEC_1_2;

    ctx.simplify = (Rf_asLogical(simplify) == TRUE);
    ctx.duplicate_keys = opts.dup_keys;
    ctx.max_depth = opts.max_depth;
    ctx.depth = 0;
    ctx.alias_error = (strcmp(CHAR(STRING_ELT(aliases, 0)), "error") == 0);
    ctx.tag_error = (strcmp(CHAR(STRING_ELT(tags, 0)), "error") == 0);
    ctx.max_nodes = Rf_asReal(max_nodes);
    ctx.nodes = 0;
    {
        const char* bi = CHAR(STRING_ELT(big_integers, 0));
        ctx.big_integers = (strcmp(bi, "double") == 0) ? ZUYAML_BIGINT_DOUBLE
            : (strcmp(bi, "error") == 0)               ? ZUYAML_BIGINT_ERROR
                                                       : ZUYAML_BIGINT_CLASS;
    }

    /* cyaml v0.1.3 never reads opts.max_size either, so enforce it here,
       before handing the buffer to the parser. */
    if (opts.max_size > 0 && len > (size_t)opts.max_size) {
        zuyaml_stopf("limit_size", path,
            "Input is %.0f bytes, which exceeds max_size (%u).",
            (double)len, (unsigned)opts.max_size);
    }

    stream = cyaml_parse_stream(src, len, &opts, &err);
    if (stream == NULL) {
        zuyaml_stop_parse_error(&err, path);
    }

    /* From here on, every path must be unwind-safe: the conversion below
       raises R errors and allocates R objects, either of which can longjmp
       past the free. */
    owner = PROTECT(zuyaml_stream_own(stream));

    n_docs = cyaml_stream_count(stream);
    out = PROTECT(Rf_allocVector(VECSXP, (R_xlen_t)n_docs));

    for (i = 0; i < n_docs; i++) {
        cyaml_doc_t* doc = cyaml_stream_doc(stream, i);
        SET_VECTOR_ELT(out, (R_xlen_t)i,
            zuyaml_convert_node(doc, cyaml_root(doc), &ctx, NULL));
    }

    zuyaml_stream_release(owner);
    UNPROTECT(2);
    return out;
}
