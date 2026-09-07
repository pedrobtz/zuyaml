#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "zuyaml.h"

/* Largest integer exactly representable as an IEEE-754 double. */
#define ZUYAML_MAX_EXACT_DOUBLE 9007199254740992.0

_Noreturn static void stop_embedded_nul(void)
{
    zuyaml_stopf("embedded_nul", NULL,
        "YAML scalar contains an embedded NUL byte, which cannot be "
        "represented as an R string.");
}

/*
 * R character strings cannot contain an embedded NUL, and Rf_mkCharLenCE()
 * raises an error if handed one -- which is an unwind. Detect it first so we
 * can free any C allocation and raise a proper condition instead.
 */
static void check_no_nul(const char* s, size_t len)
{
    if (memchr(s, '\0', len) != NULL) {
        stop_embedded_nul();
    }
}

/*
 * Does this double-quoted scalar contain an escape that produces a NUL?
 *
 * `key: "\0"` is legal YAML -- \0 is a valid double-quoted escape -- and R
 * cannot represent the result. cyaml_scalar_str() returns a NUL-terminated
 * string with no length, so by the time we hold its result the value has
 * already been truncated at the NUL and the loss is undetectable. The raw
 * source span has to be scanned instead, before the value is used.
 *
 * Only CYAML_DOUBLE needs this: plain, single-quoted, literal and folded
 * scalars have no escape that can produce a NUL.
 */
static bool has_nul_escape(const char* p, size_t n)
{
    size_t i = 0;

    while (i < n) {
        if (p[i] != '\\') {
            i++;
            continue;
        }
        i++; /* consume the backslash */
        if (i >= n) {
            break;
        }
        switch (p[i]) {
        case '0':
            return true;
        case 'x':
            if (i + 2 < n && memcmp(p + i + 1, "00", 2) == 0) {
                return true;
            }
            i += 3;
            break;
        case 'u':
            if (i + 4 < n && memcmp(p + i + 1, "0000", 4) == 0) {
                return true;
            }
            i += 5;
            break;
        case 'U':
            if (i + 8 < n && memcmp(p + i + 1, "00000000", 8) == 0) {
                return true;
            }
            i += 9;
            break;
        default:
            /* \\ , \" , \n and friends: consume the escaped character so a
               literal backslash is never mistaken for an escape opener. */
            i++;
            break;
        }
    }
    return false;
}

/*
 * Convert a scalar node's text to an R character vector.
 *
 * Plain scalars take the zero-copy path: cyaml_str()/cyaml_len() point
 * straight into the source buffer, so the text goes to Rf_mkCharLenCE() with
 * no intermediate allocation. Only styles that need processing -- escapes,
 * line folding, block indent stripping -- pay for cyaml_scalar_str(), which
 * mallocs and must be freed.
 *
 * Since plain scalars dominate real documents, this removes most of the
 * per-scalar malloc/free traffic.
 */
static SEXP scalar_string(const cyaml_doc_t* doc, const cyaml_node_t* node)
{
    if (node->style == CYAML_PLAIN) {
        const char* p = cyaml_str(doc, node);
        uint32_t n = cyaml_len(node);

        if (p == NULL || n == 0) {
            return Rf_ScalarString(Rf_mkCharLenCE("", 0, CE_UTF8));
        }
        check_no_nul(p, (size_t)n);
        return Rf_ScalarString(Rf_mkCharLenCE(p, (int)n, CE_UTF8));
    }

    /* Check the raw span before decoding: cyaml_scalar_str() would truncate
       a NUL-producing escape without telling us. */
    {
        const char* raw = cyaml_str(doc, node);
        uint32_t raw_n = cyaml_len(node);

        if (raw != NULL && raw_n > 0) {
            check_no_nul(raw, (size_t)raw_n);
            if (node->style == CYAML_DOUBLE
                && has_nul_escape(raw, (size_t)raw_n)) {
                stop_embedded_nul();
            }
        }
    }

    {
        char* s = cyaml_scalar_str(doc, node);
        SEXP out;

        if (s == NULL) {
            return Rf_ScalarString(Rf_mkCharLenCE("", 0, CE_UTF8));
        }

        /* The C string must not be live across an allocating R call that
           could unwind, so it is copied into a CHARSXP and freed at once. */
        out = PROTECT(
            Rf_ScalarString(Rf_mkCharLenCE(s, (int)strlen(s), CE_UTF8)));
        free(s);
        UNPROTECT(1);
        return out;
    }
}

static SEXP scalar_int(const cyaml_doc_t* doc, const cyaml_node_t* node)
{
    int64_t v;

    if (cyaml_as_int(doc, node, &v)) {
        /* NA_INTEGER is INT_MIN, so it is not available as a value. */
        if (v > (int64_t)INT_MIN && v <= (int64_t)INT_MAX) {
            return Rf_ScalarInteger((int)v);
        }
        if (v >= -(int64_t)ZUYAML_MAX_EXACT_DOUBLE
            && v <= (int64_t)ZUYAML_MAX_EXACT_DOUBLE) {
            return Rf_ScalarReal((double)v);
        }
    }

    /* Beyond 2^53, or beyond int64 entirely. Converting here would silently
       lose precision, which the package promises never to do. The
       zuyaml_bigint representation arrives in M3. */
    zuyaml_stopf("not_implemented", NULL,
        "Integers beyond 2^53 are not supported yet (big_integers is M3).");
}

static SEXP scalar_double(const cyaml_doc_t* doc, const cyaml_node_t* node)
{
    double v;

    /* Handles .inf, -.inf and .nan. */
    if (!cyaml_as_float(doc, node, &v)) {
        zuyaml_stopf("syntax", NULL, "Could not parse YAML float scalar.");
    }
    return Rf_ScalarReal(v);
}

static SEXP scalar_bool(const cyaml_doc_t* doc, const cyaml_node_t* node)
{
    bool v;

    if (!cyaml_as_bool(doc, node, &v)) {
        zuyaml_stopf("syntax", NULL, "Could not parse YAML boolean scalar.");
    }
    return Rf_ScalarLogical(v ? TRUE : FALSE);
}

/*
 * Classify a scalar with YAML 1.2 core schema rules.
 *
 * cyaml_scalar_kind() returns CYAML_KIND_STRING for every quoted scalar, which
 * is exactly the distinction R needs: `""` stays "" and never becomes NULL.
 * Note that cyaml_is_null_val() would be the wrong function here -- it treats
 * an empty value as null, collapsing the quoted empty string.
 */
static SEXP convert_scalar(const cyaml_doc_t* doc, const cyaml_node_t* node)
{
    switch (cyaml_scalar_kind(doc, node)) {
    case CYAML_KIND_NULL:
        return R_NilValue;
    case CYAML_KIND_BOOL:
        return scalar_bool(doc, node);
    case CYAML_KIND_INT:
        return scalar_int(doc, node);
    case CYAML_KIND_FLOAT:
        return scalar_double(doc, node);
    case CYAML_KIND_STRING:
        return scalar_string(doc, node);
    }

    zuyaml_stopf("internal", NULL,
        "Unexpected cyaml scalar kind. This is a bug in zuyaml.");
}

/*
 * Convert one cyaml node to an R object.
 *
 * Dispatch covers every member of cyaml_type_t. CYAML_NONE marks an
 * invalid/uninitialised node and should be unreachable from a successful
 * parse, but it must not fall through silently -- a new upstream node type
 * would otherwise be converted as whatever the default happened to be.
 */
SEXP zuyaml_convert_node(const cyaml_doc_t* doc, const cyaml_node_t* node)
{
    /* An empty document has no root. */
    if (node == NULL) {
        return R_NilValue;
    }

    switch (node->type) {
    case CYAML_NULL:
        return R_NilValue;

    case CYAML_SCALAR:
        return convert_scalar(doc, node);

    case CYAML_SEQ:
        zuyaml_stopf("not_implemented", NULL,
            "Sequence conversion is not implemented yet.");

    case CYAML_MAP:
        zuyaml_stopf("not_implemented", NULL,
            "Mapping conversion is not implemented yet.");

    case CYAML_ALIAS:
        zuyaml_stopf("not_implemented", NULL,
            "Alias resolution is not implemented yet.");

    case CYAML_NONE:
        break;
    }

    zuyaml_stopf("internal", NULL,
        "Unexpected cyaml node type (%d). This is a bug in zuyaml.",
        (int)node->type);
}
