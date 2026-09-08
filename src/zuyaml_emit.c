#include <ctype.h>
#include <inttypes.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zuyaml.h"

/* --- unwind-safe ownership of the document being built ----------------- */

static void doc_finalizer(SEXP owner)
{
    cyaml_doc_t* doc = (cyaml_doc_t*)R_ExternalPtrAddr(owner);
    if (doc != NULL) {
        cyaml_free(doc);
        R_ClearExternalPtr(owner);
    }
}

static void doc_release(SEXP owner)
{
    doc_finalizer(owner);
}

static SEXP doc_own(cyaml_doc_t* doc)
{
    SEXP owner = PROTECT(R_MakeExternalPtr(doc, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(owner, doc_finalizer, TRUE);
    UNPROTECT(1);
    return owner;
}

/* --- scalar style selection -------------------------------------------- */

static bool all_digits(const char* s, size_t n)
{
    size_t i;
    if (n == 0) {
        return false;
    }
    for (i = 0; i < n; i++) {
        if (s[i] < '0' || s[i] > '9') {
            return false;
        }
    }
    return true;
}

static bool matches(const char* s, size_t n, const char* lit)
{
    size_t m = strlen(lit);
    return n == m && memcmp(s, lit, m) == 0;
}

/*
 * Would this text be resolved as something other than a string by the YAML 1.2
 * core schema?
 *
 * This exists because cyaml's emitter does not check. needs_quoting_ex() in
 * cyaml_emitter.c promotes a plain scalar to double-quoted for indicators,
 * document markers, trailing colons and the reserved words null/true/false/~,
 * but performs no numeric test at all. Without this check,
 * yaml_emit(list(x = "42")) produces `x: 42`, which parses back as the integer
 * 42 -- and version strings, zip codes and IDs all land there.
 *
 * Only the numeric gap is closed here; everything upstream already handles is
 * left to upstream. The null and boolean cases are included anyway because
 * they are two lines and make this function independently correct if the
 * upstream behaviour ever changes.
 */
static bool resolves_as_non_string(const char* s, size_t n)
{
    size_t i = 0;
    bool digits_before = false, digits_after = false, dot = false;

    if (n == 0) {
        return true; /* empty must be quoted or it reads as null */
    }

    /* null */
    if (matches(s, n, "~") || matches(s, n, "null") || matches(s, n, "Null")
        || matches(s, n, "NULL")) {
        return true;
    }
    /* bool */
    if (matches(s, n, "true") || matches(s, n, "True") || matches(s, n, "TRUE")
        || matches(s, n, "false") || matches(s, n, "False")
        || matches(s, n, "FALSE")) {
        return true;
    }

    /* hex and octal integers, which cyaml also accepts */
    if (n > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        for (i = 2; i < n; i++) {
            if (!isxdigit((unsigned char)s[i])) {
                break;
            }
        }
        if (i == n) {
            return true;
        }
    }
    if (n > 2 && s[0] == '0' && (s[1] == 'o' || s[1] == 'O')) {
        for (i = 2; i < n; i++) {
            if (s[i] < '0' || s[i] > '7') {
                break;
            }
        }
        if (i == n) {
            return true;
        }
    }

    i = 0;
    if (s[i] == '+' || s[i] == '-') {
        i++;
    }

    /* .inf and .nan, with the capitalisations the core schema allows */
    {
        const char* rest = s + i;
        size_t rest_n = n - i;
        if (matches(rest, rest_n, ".inf") || matches(rest, rest_n, ".Inf")
            || matches(rest, rest_n, ".INF")) {
            return true;
        }
        if (matches(rest, rest_n, ".nan") || matches(rest, rest_n, ".NaN")
            || matches(rest, rest_n, ".NAN")) {
            return true;
        }
    }

    /* decimal integer or float: digits, optional dot, optional exponent */
    while (i < n && s[i] >= '0' && s[i] <= '9') {
        i++;
        digits_before = true;
    }
    if (i < n && s[i] == '.') {
        dot = true;
        i++;
        while (i < n && s[i] >= '0' && s[i] <= '9') {
            i++;
            digits_after = true;
        }
    }
    if (!digits_before && !digits_after) {
        return false;
    }
    if (i < n && (s[i] == 'e' || s[i] == 'E')) {
        size_t save = i;
        i++;
        if (i < n && (s[i] == '+' || s[i] == '-')) {
            i++;
        }
        if (i < n && all_digits(s + i, n - i)) {
            i = n;
        } else {
            i = save;
        }
    }
    (void)dot;
    return i == n;
}

/* Build a string scalar, quoting it when a plain scalar would change type. */
static cyaml_node_t* new_string_node(cyaml_doc_t* doc, const char* s, size_t n)
{
    cyaml_node_t* node = cyaml_new_str(doc, s, n);

    if (node != NULL && resolves_as_non_string(s, n)) {
        /* cyaml_node is fully defined in the public header, so setting the
           style is legitimate use of the API. */
        node->style = CYAML_DOUBLE;
    }
    return node;
}

/* --- numeric formatting -------------------------------------------------- */

/*
 * Format a double so that parsing the text yields the same double.
 *
 * cyaml_new_float() cannot be used: it formats with "%g", which keeps only six
 * significant digits, so 3.14159265358979 would emit as 3.14159.
 *
 * The shortest representation that round-trips is preferred, so ordinary
 * numbers stay readable and only awkward ones grow. R requires LC_NUMERIC to
 * be "C", so the decimal separator is a point; the guard below is cheap
 * insurance rather than a real expectation.
 */
static void format_double(double v, char* buf, size_t buf_n)
{
    int prec;
    size_t i;

    for (prec = 15; prec <= 17; prec++) {
        snprintf(buf, buf_n, "%.*g", prec, v);
        if (strtod(buf, NULL) == v) {
            break;
        }
    }
    for (i = 0; buf[i] != '\0'; i++) {
        if (buf[i] == ',') {
            buf[i] = '.';
        }
    }
}

/* --- building ------------------------------------------------------------ */

static cyaml_node_t* build_node(cyaml_doc_t* doc, SEXP x);

static cyaml_node_t* build_double(cyaml_doc_t* doc, double v)
{
    char buf[64];

    if (ISNA(v)) {
        return cyaml_new_null(doc);
    }
    if (ISNAN(v)) {
        return cyaml_new_str(doc, ".nan", 4);
    }
    if (!R_FINITE(v)) {
        return v > 0 ? cyaml_new_str(doc, ".inf", 4)
                     : cyaml_new_str(doc, "-.inf", 5);
    }
    format_double(v, buf, sizeof(buf));
    return cyaml_new_str(doc, buf, strlen(buf));
}

static cyaml_node_t* build_element(cyaml_doc_t* doc, SEXP x, R_xlen_t i)
{
    switch (TYPEOF(x)) {
    case LGLSXP:
        return LOGICAL(x)[i] == NA_LOGICAL
            ? cyaml_new_null(doc)
            : cyaml_new_bool(doc, LOGICAL(x)[i] != 0);
    case INTSXP:
        return INTEGER(x)[i] == NA_INTEGER
            ? cyaml_new_null(doc)
            : cyaml_new_int(doc, (int64_t)INTEGER(x)[i]);
    case REALSXP:
        return build_double(doc, REAL(x)[i]);
    case STRSXP: {
        SEXP el = STRING_ELT(x, i);
        const char* s;
        if (el == NA_STRING) {
            return cyaml_new_null(doc);
        }
        s = Rf_translateCharUTF8(el);
        return new_string_node(doc, s, strlen(s));
    }
    default:
        zuyaml_stopf("unsupported_type", NULL,
            "Cannot emit an R object of type '%s'.", Rf_type2char(TYPEOF(x)));
    }
}

/* A zuyaml_bigint is emitted as an integer scalar, after re-validation. */
static cyaml_node_t* build_bigint(cyaml_doc_t* doc, SEXP x)
{
    SEXP el;
    const char* s;
    size_t n, i;

    if (TYPEOF(x) != STRSXP || XLENGTH(x) != 1
        || STRING_ELT(x, 0) == NA_STRING) {
        zuyaml_stopf("invalid_input", NULL,
            "A zuyaml_bigint must be a single non-NA string.");
    }
    el = STRING_ELT(x, 0);
    s = CHAR(el);
    n = strlen(s);

    /* Nothing stops a user constructing one by hand, so the class attribute
       is not trusted: an invalid value is an error, never a quoted string. */
    i = (n > 0 && (s[0] == '+' || s[0] == '-')) ? 1 : 0;
    if (n == i || !all_digits(s + i, n - i)) {
        zuyaml_stopf("invalid_input", NULL,
            "A zuyaml_bigint must hold a decimal integer; got '%s'.", s);
    }
    return cyaml_new_str(doc, s, n);
}

static void check_names(SEXP names, R_xlen_t n)
{
    R_xlen_t i, j;

    for (i = 0; i < n; i++) {
        SEXP nm = STRING_ELT(names, i);
        if (nm == NA_STRING || CHAR(nm)[0] == '\0') {
            zuyaml_stopf("partial_names", NULL,
                "Cannot emit a partially named list or vector: element %d has "
                "no name. Name every element or none.",
                (int)(i + 1));
        }
    }
    /* cyaml_map_set is set-or-update, so a duplicate name would silently
       overwrite rather than produce two keys. */
    for (i = 0; i < n; i++) {
        for (j = i + 1; j < n; j++) {
            if (strcmp(CHAR(STRING_ELT(names, i)), CHAR(STRING_ELT(names, j)))
                == 0) {
                zuyaml_stopf("duplicate_key", NULL,
                    "Cannot emit a list with duplicate names ('%s').",
                    CHAR(STRING_ELT(names, i)));
            }
        }
    }
}

static cyaml_node_t* build_map(cyaml_doc_t* doc, SEXP x, SEXP names)
{
    R_xlen_t n = XLENGTH(x), i;
    cyaml_node_t* map = cyaml_new_map(doc);

    if (map == NULL) {
        zuyaml_stopf("memory", NULL, "Could not allocate a YAML mapping.");
    }
    /* An empty block collection emits as nothing at all, so empty containers
       are marked flow to get {} and []. node->style doubles as the collection
       style for CYAML_SEQ and CYAML_MAP. */
    if (n == 0) {
        map->style = (cyaml_style_t)CYAML_FLOW;
    }
    check_names(names, n);

    for (i = 0; i < n; i++) {
        SEXP el = (TYPEOF(x) == VECSXP) ? VECTOR_ELT(x, i) : x;
        cyaml_node_t* val = (TYPEOF(x) == VECSXP)
            ? build_node(doc, el)
            : build_element(doc, x, i);

        if (val == NULL
            || !cyaml_map_set(doc, map, CHAR(STRING_ELT(names, i)), val)) {
            zuyaml_stopf("memory", NULL, "Could not build a YAML mapping.");
        }
    }
    return map;
}

static cyaml_node_t* build_seq(cyaml_doc_t* doc, SEXP x)
{
    R_xlen_t n = XLENGTH(x), i;
    cyaml_node_t* seq = cyaml_new_seq(doc);

    if (seq == NULL) {
        zuyaml_stopf("memory", NULL, "Could not allocate a YAML sequence.");
    }
    if (n == 0) {
        seq->style = (cyaml_style_t)CYAML_FLOW; /* emit [] rather than nothing */
    }
    for (i = 0; i < n; i++) {
        cyaml_node_t* el = (TYPEOF(x) == VECSXP)
            ? build_node(doc, VECTOR_ELT(x, i))
            : build_element(doc, x, i);

        if (el == NULL || !cyaml_seq_push(seq, el)) {
            zuyaml_stopf("memory", NULL, "Could not build a YAML sequence.");
        }
    }
    return seq;
}

static cyaml_node_t* build_node(cyaml_doc_t* doc, SEXP x)
{
    SEXP names;

    if (x == R_NilValue) {
        return cyaml_new_null(doc);
    }

    if (Rf_inherits(x, "zuyaml_bigint")) {
        return build_bigint(doc, x);
    }
    if (Rf_inherits(x, "zuyaml_map")) {
        zuyaml_stopf("unsupported_type", NULL,
            "A zuyaml_map cannot be emitted: the YAML library's builder only "
            "accepts string keys, so mappings with collection-valued keys do "
            "not round-trip.");
    }
    if (Rf_inherits(x, "data.frame")) {
        zuyaml_stopf("unsupported_type", NULL,
            "Data frames are not emitted automatically; convert explicitly to "
            "a list.");
    }
    if (Rf_isFactor(x)) {
        /* Labels, never the internal integer codes. */
        SEXP levels = Rf_getAttrib(x, R_LevelsSymbol);
        SEXP chr = PROTECT(Rf_asCharacterFactor(x));
        cyaml_node_t* out;
        (void)levels;
        out = build_node(doc, chr);
        UNPROTECT(1);
        return out;
    }

    switch (TYPEOF(x)) {
    case LGLSXP:
    case INTSXP:
    case REALSXP:
    case STRSXP:
    case VECSXP:
        break;
    default:
        zuyaml_stopf("unsupported_type", NULL,
            "Cannot emit an R object of type '%s'.", Rf_type2char(TYPEOF(x)));
    }

    /* An S3/S4 object of an unrecognised class is refused rather than being
       serialised by blindly stripping its attributes. */
    if (Rf_isObject(x)) {
        SEXP cls = Rf_getAttrib(x, R_ClassSymbol);
        zuyaml_stopf("unsupported_type", NULL,
            "Cannot emit an object of class '%s'; convert it explicitly.",
            cls != R_NilValue ? CHAR(STRING_ELT(cls, 0)) : "?");
    }

    names = Rf_getAttrib(x, R_NamesSymbol);

    if (names != R_NilValue) {
        /* An empty but named list is the way to ask for {}; list() alone is
           ambiguous and emits as [] (see the design's empty-containers
           section). */
        return build_map(doc, x, names);
    }
    if (TYPEOF(x) != VECSXP && XLENGTH(x) == 1) {
        return build_element(doc, x, 0);
    }
    return build_seq(doc, x);
}

/* --- entry point --------------------------------------------------------- */

SEXP zuyaml_emit_(SEXP x, SEXP indent, SEXP width, SEXP document_start,
    SEXP document_end)
{
    cyaml_doc_t* doc;
    cyaml_emit_opts_t opts = CYAML_EMIT_DEFAULT;
    cyaml_node_t* root;
    SEXP owner, out;
    char* text;
    size_t len = 0;

    doc = cyaml_doc_new();
    if (doc == NULL) {
        zuyaml_stopf("memory", NULL, "Could not allocate a YAML document.");
    }
    owner = PROTECT(doc_own(doc));

    root = build_node(doc, x);
    if (root == NULL) {
        zuyaml_stopf("memory", NULL, "Could not build the YAML document.");
    }
    cyaml_set_root(doc, root);

    /* indent and width are uint8_t upstream; R validates the range. */
    opts.indent = (uint8_t)Rf_asInteger(indent);
    opts.width = (uint8_t)Rf_asInteger(width);
    opts.doc_start = (Rf_asLogical(document_start) == TRUE);
    opts.doc_end = (Rf_asLogical(document_end) == TRUE);
    opts.preserve_comments = false;
    opts.preserve_style = false;

    text = cyaml_emit(doc, &opts, &len);
    if (text == NULL) {
        zuyaml_stopf("emit", NULL, "Could not emit the YAML document.");
    }

    out = PROTECT(Rf_ScalarString(Rf_mkCharLenCE(text, (int)len, CE_UTF8)));
    free(text);

    /* Must be doc_release, not the parser's stream release: the pointer here
       is a cyaml_doc_t and freeing it as a stream would be type confusion. */
    doc_release(owner);
    UNPROTECT(2);
    return out;
}
