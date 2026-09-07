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
static SEXP scalar_charsxp(const cyaml_doc_t* doc, const cyaml_node_t* node)
{
    if (node->style == CYAML_PLAIN) {
        const char* p = cyaml_str(doc, node);
        uint32_t n = cyaml_len(node);

        if (p == NULL || n == 0) {
            return Rf_mkCharLenCE("", 0, CE_UTF8);
        }
        check_no_nul(p, (size_t)n);
        return Rf_mkCharLenCE(p, (int)n, CE_UTF8);
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
            return Rf_mkCharLenCE("", 0, CE_UTF8);
        }

        /* The C string must not be live across an allocating R call that
           could unwind, so it is copied into a CHARSXP and freed at once. */
        out = PROTECT(Rf_mkCharLenCE(s, (int)strlen(s), CE_UTF8));
        free(s);
        UNPROTECT(1);
        return out;
    }
}

static SEXP scalar_string(const cyaml_doc_t* doc, const cyaml_node_t* node)
{
    SEXP ch = PROTECT(scalar_charsxp(doc, node));
    SEXP out = Rf_ScalarString(ch);
    UNPROTECT(1);
    return out;
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

/* --- collections ------------------------------------------------------- */

/*
 * Collapse a list of length-one scalars of one type into an atomic vector.
 *
 * Only applied when simplify = TRUE, which is NOT the default: simplification
 * makes the shape of the result depend on the contents of the document, so
 * code that indexes the result is correct only for the inputs its author
 * happened to test. See the design's sequence section.
 */
static SEXP maybe_simplify(SEXP list)
{
    R_xlen_t n = XLENGTH(list), i;
    SEXPTYPE type = NILSXP;
    SEXP out;

    if (n == 0) {
        return list; /* an empty sequence stays list() */
    }

    for (i = 0; i < n; i++) {
        SEXP el = VECTOR_ELT(list, i);
        SEXPTYPE et = TYPEOF(el);

        if (el == R_NilValue || XLENGTH(el) != 1) {
            return list;
        }
        if (et != LGLSXP && et != INTSXP && et != REALSXP && et != STRSXP) {
            return list;
        }
        /* A classed element (zuyaml_bigint, later) is never simplified. */
        if (Rf_getAttrib(el, R_ClassSymbol) != R_NilValue) {
            return list;
        }
        if (i == 0) {
            type = et;
        } else if (et != type) {
            return list;
        }
    }

    out = PROTECT(Rf_allocVector(type, n));
    for (i = 0; i < n; i++) {
        SEXP el = VECTOR_ELT(list, i);
        switch (type) {
        case LGLSXP:
            LOGICAL(out)[i] = LOGICAL(el)[0];
            break;
        case INTSXP:
            INTEGER(out)[i] = INTEGER(el)[0];
            break;
        case REALSXP:
            REAL(out)[i] = REAL(el)[0];
            break;
        case STRSXP:
            SET_STRING_ELT(out, i, STRING_ELT(el, 0));
            break;
        default:
            break;
        }
    }
    UNPROTECT(1);
    return out;
}

/*
 * Is every element of this sequence a scalar in the *YAML* sense?
 *
 * The check has to be on node types, not on the converted R values: an inner
 * sequence that simplified to a length-one vector would otherwise make its
 * parent look like a scalar-only sequence, so [[1], [2]] would collapse to
 * c(1L, 2L) and lose a level of structure.
 */
static bool seq_is_scalar_only(const cyaml_node_t* node)
{
    uint32_t n = cyaml_seq_len(node), i;

    for (i = 0; i < n; i++) {
        const cyaml_node_t* el = cyaml_seq_get(node, i);
        if (el == NULL || el->type != CYAML_SCALAR) {
            return false;
        }
    }
    return true;
}

static SEXP convert_seq(const cyaml_doc_t* doc, const cyaml_node_t* node,
    zuyaml_ctx_t* ctx, const zuyaml_anc_t* anc)
{
    uint32_t n = cyaml_seq_len(node), i;
    zuyaml_anc_t frame = { node, anc };
    SEXP out;

    /* The length is known up front, so the container is allocated once
       rather than grown. */
    out = PROTECT(Rf_allocVector(VECSXP, (R_xlen_t)n));
    for (i = 0; i < n; i++) {
        SET_VECTOR_ELT(out, (R_xlen_t)i,
            zuyaml_convert_node(doc, cyaml_seq_get(node, i), ctx, &frame));
    }

    if (ctx->simplify && seq_is_scalar_only(node)) {
        out = maybe_simplify(out);
    }
    UNPROTECT(1);
    return out;
}

/* Text of a mapping key, as a CHARSXP. */
static SEXP key_charsxp(const cyaml_doc_t* doc, const cyaml_node_t* key)
{
    if (key == NULL || key->type != CYAML_SCALAR) {
        /* Sequence- and mapping-valued keys have no faithful named-list
           representation; they become a zuyaml_map in M3. */
        zuyaml_stopf("unsupported_key", NULL,
            "Mapping keys that are not scalars are not supported yet.");
    }
    return scalar_charsxp(doc, key);
}

static int cmp_cstr(const void* a, const void* b)
{
    return strcmp(*(const char* const*)a, *(const char* const*)b);
}

/*
 * Reject duplicate names.
 *
 * cyaml v0.1.3 advertises duplicate-key detection but never implements it --
 * opts.dup_keys is declared in the header and read nowhere -- so this is
 * zuyaml's own job. Sorting is O(n log n); the pairwise alternative would be
 * quadratic on large mappings.
 *
 * This also catches collisions introduced by stringifying non-string scalar
 * keys, where YAML saw two distinct keys (1 and "1") but R would see one name.
 */
static void check_unique_names(SEXP names)
{
    R_xlen_t n = XLENGTH(names), i;
    const char** sorted;

    if (n < 2) {
        return;
    }

    /* R_alloc is released when the .Call returns, including on an unwind. */
    sorted = (const char**)R_alloc((size_t)n, sizeof(const char*));
    for (i = 0; i < n; i++) {
        sorted[i] = CHAR(STRING_ELT(names, i));
    }
    qsort(sorted, (size_t)n, sizeof(const char*), cmp_cstr);

    for (i = 1; i < n; i++) {
        if (strcmp(sorted[i - 1], sorted[i]) == 0) {
            zuyaml_stopf("duplicate_key", NULL,
                "Duplicate mapping key '%s'; set duplicate_keys = TRUE to "
                "allow duplicates.",
                sorted[i]);
        }
    }
}

static SEXP convert_map(const cyaml_doc_t* doc, const cyaml_node_t* node,
    zuyaml_ctx_t* ctx, const zuyaml_anc_t* anc)
{
    uint32_t n = cyaml_map_len(node), i;
    zuyaml_anc_t frame = { node, anc };
    SEXP out, names;

    out = PROTECT(Rf_allocVector(VECSXP, (R_xlen_t)n));
    names = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t)n));

    for (i = 0; i < n; i++) {
        cyaml_pair_t* pair = cyaml_map_at(node, i);

        SET_STRING_ELT(names, (R_xlen_t)i, key_charsxp(doc, pair->key));
        SET_VECTOR_ELT(out, (R_xlen_t)i,
            zuyaml_convert_node(doc, pair->val, ctx, &frame));
    }

    if (!ctx->duplicate_keys) {
        check_unique_names(names);
    }
    Rf_setAttrib(out, R_NamesSymbol, names);

    UNPROTECT(2);
    return out;
}

/*
 * Convert one cyaml node to an R object.
 *
 * Dispatch covers every member of cyaml_type_t. CYAML_NONE marks an
 * invalid/uninitialised node and should be unreachable from a successful
 * parse, but it must not fall through silently -- a new upstream node type
 * would otherwise be converted as whatever the default happened to be.
 */
/*
 * Resolve an alias to the value of its target.
 *
 * cyaml populates node->alias.target during parsing (the composer sets it), so
 * this needs neither cyaml_find_anchor() nor cyaml_resolve_aliases(). Avoiding
 * the latter is the point: it replaces every alias with a *deep copy* of its
 * target, in C, with no budget -- which is precisely how a billion-laughs
 * payload turns 200 bytes of source into gigabytes of memory. Resolving here
 * means every expanded node is charged against max_nodes and the conversion
 * aborts as soon as the budget runs out.
 */
static SEXP convert_alias(const cyaml_doc_t* doc, const cyaml_node_t* node,
    zuyaml_ctx_t* ctx, const zuyaml_anc_t* anc)
{
    const cyaml_node_t* target = node->alias.target;
    const zuyaml_anc_t* a;

    if (ctx->alias_error) {
        zuyaml_stopf("alias", NULL,
            "Document contains a YAML alias and aliases = \"error\".");
    }
    if (target == NULL) {
        zuyaml_stopf("alias", NULL,
            "YAML alias does not resolve to a known anchor.");
    }

    /* A target that is also an ancestor is a cycle. Following it would
       recurse forever; R lists cannot represent it either. */
    for (a = anc; a != NULL; a = a->parent) {
        if (a->node == target) {
            /* The composer fills in node->anchor for an alias but leaves
               node->span zeroed, so the anchor span is the only position
               available. */
            const cyaml_span_t* at = node->anchor.start_line ? &node->anchor
                                                             : &node->span;
            if (at->start_line > 0) {
                zuyaml_stopf("alias_cycle", NULL,
                    "YAML alias cycle detected at line %u, column %u.",
                    (unsigned)at->start_line, (unsigned)at->start_col);
            }
            zuyaml_stopf("alias_cycle", NULL,
                "YAML alias cycle detected; aliases cannot refer to a node "
                "that contains them.");
        }
    }

    return zuyaml_convert_node(doc, target, ctx, anc);
}

SEXP zuyaml_convert_node(const cyaml_doc_t* doc, const cyaml_node_t* node,
    zuyaml_ctx_t* ctx, const zuyaml_anc_t* anc)
{
    /* An empty document has no root. */
    if (node == NULL) {
        return R_NilValue;
    }

    /* Charge every materialised node against the budget. This is what bounds
       alias expansion: max_depth and max_size do not, because a billion-laughs
       payload is small and shallow. */
    ctx->nodes += 1;
    if (ctx->max_nodes > 0 && ctx->nodes > ctx->max_nodes) {
        zuyaml_stopf("limit_nodes", NULL,
            "Document exceeds the node limit (%.0f); see max_nodes.",
            ctx->max_nodes);
    }

    switch (node->type) {
    case CYAML_NULL:
        return R_NilValue;

    case CYAML_SCALAR:
        return convert_scalar(doc, node);

    case CYAML_SEQ:
    case CYAML_MAP: {
        SEXP out;

        /* cyaml v0.1.3 never reads opts.max_depth, so the limit is enforced
           here. Besides bounding hostile input, this is what keeps deeply
           nested documents from exhausting R's protection stack during this
           very recursion. */
        if (ctx->max_depth > 0 && ctx->depth >= ctx->max_depth) {
            zuyaml_stopf("limit_depth", NULL,
                "YAML nesting exceeds max_depth (%u).",
                (unsigned)ctx->max_depth);
        }
        ctx->depth++;
        out = (node->type == CYAML_SEQ) ? convert_seq(doc, node, ctx, anc)
                                        : convert_map(doc, node, ctx, anc);
        ctx->depth--;
        return out;
    }

    case CYAML_ALIAS:
        return convert_alias(doc, node, ctx, anc);

    case CYAML_NONE:
        break;
    }

    zuyaml_stopf("internal", NULL,
        "Unexpected cyaml node type (%d). This is a bug in zuyaml.",
        (int)node->type);
}
