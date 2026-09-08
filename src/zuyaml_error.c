#include <stdarg.h>
#include <stdio.h>

#include "zuyaml.h"

/*
 * Map upstream error codes to stable zuyaml codes.
 *
 * Users must never have to parse a message string to discover the category of
 * a failure, and upstream's enum values are an implementation detail. A code
 * that appears here and not upstream (or vice versa) is a signal to re-read
 * the design's verification note after a re-vendor.
 */
const char* zuyaml_err_code(cyaml_err_t code)
{
    switch (code) {
    case CYAML_OK:
        return "ok";
    case CYAML_ERR_NOMEM:
        return "memory";
    case CYAML_ERR_SYNTAX:
        return "syntax";
    case CYAML_ERR_EOF:
        return "eof";
    case CYAML_ERR_INDENT:
        return "indent";
    case CYAML_ERR_ESCAPE:
        return "escape";
    case CYAML_ERR_ANCHOR:
        return "anchor";
    case CYAML_ERR_ALIAS:
        return "alias";
    case CYAML_ERR_TAG:
        return "tag";
    case CYAML_ERR_DUP_KEY:
        return "duplicate_key";
    case CYAML_ERR_IO:
        return "io";
    }
    /* Reached only if upstream adds a code. Fail loudly rather than
       silently bucketing it as something else. */
    return "unknown";
}

/* Build the condition object signalled for every zuyaml error. */
static SEXP build_condition(const char* message, const char* code,
    const cyaml_span_t* span, SEXP path)
{
    const char* names[] = { "message", "call", "code", "line", "column",
        "end_line", "end_column", "path", "" };

    SEXP cond = PROTECT(Rf_mkNamed(VECSXP, names));

    SET_VECTOR_ELT(cond, 0, Rf_mkString(message));
    SET_VECTOR_ELT(cond, 1, R_NilValue); /* call */
    SET_VECTOR_ELT(cond, 2, Rf_mkString(code));

    if (span != NULL) {
        SET_VECTOR_ELT(cond, 3, Rf_ScalarInteger((int)span->start_line));
        SET_VECTOR_ELT(cond, 4, Rf_ScalarInteger((int)span->start_col));
        SET_VECTOR_ELT(cond, 5, Rf_ScalarInteger((int)span->end_line));
        SET_VECTOR_ELT(cond, 6, Rf_ScalarInteger((int)span->end_col));
    } else {
        SET_VECTOR_ELT(cond, 3, R_NilValue);
        SET_VECTOR_ELT(cond, 4, R_NilValue);
        SET_VECTOR_ELT(cond, 5, R_NilValue);
        SET_VECTOR_ELT(cond, 6, R_NilValue);
    }

    SET_VECTOR_ELT(cond, 7, path == NULL ? R_NilValue : path);

    SEXP cls = PROTECT(Rf_allocVector(STRSXP, 4));
    SET_STRING_ELT(cls, 0, Rf_mkChar("zuyaml_parse_error"));
    SET_STRING_ELT(cls, 1, Rf_mkChar("zuyaml_error"));
    SET_STRING_ELT(cls, 2, Rf_mkChar("error"));
    SET_STRING_ELT(cls, 3, Rf_mkChar("condition"));
    Rf_setAttrib(cond, R_ClassSymbol, cls);

    UNPROTECT(2);
    return cond;
}

/* Signal a condition via base::stop(). Does not return. */
static _Noreturn void signal_condition(SEXP cond)
{
    SEXP call = PROTECT(Rf_lang2(Rf_install("stop"), cond));
    Rf_eval(call, R_BaseEnv);
    UNPROTECT(1); /* not reached */
    Rf_error("zuyaml internal error: stop() returned");
}

/* Describe where the input came from, for the message prefix. */
static const char* path_str(SEXP path)
{
    if (path == NULL || path == R_NilValue || TYPEOF(path) != STRSXP
        || Rf_length(path) != 1) {
        return NULL;
    }
    return CHAR(STRING_ELT(path, 0));
}

_Noreturn void zuyaml_stop_parse_error(const cyaml_error_t* err, SEXP path)
{
    const char* detail;
    const char* where = path_str(path);
    char message[512];

    /* Upstream's msg is a fixed 128-byte buffer and its wording is an
       implementation detail, so it is an input to our message, never passed
       through as the whole of it. Fall back to the code's static string. */
    if (err->msg[0] != '\0') {
        detail = err->msg;
    } else {
        detail = cyaml_strerror(err->code);
    }

    if (where != NULL) {
        snprintf(message, sizeof(message),
            "YAML parse error in '%s' at line %u, column %u: %s",
            where, (unsigned)err->span.start_line,
            (unsigned)err->span.start_col, detail);
    } else {
        snprintf(message, sizeof(message),
            "YAML parse error at line %u, column %u: %s",
            (unsigned)err->span.start_line, (unsigned)err->span.start_col,
            detail);
    }

    SEXP cond = PROTECT(build_condition(
        message, zuyaml_err_code(err->code), &err->span, path));
    signal_condition(cond); /* noreturn */
}

_Noreturn void zuyaml_stopf(const char* code, SEXP path, const char* fmt, ...)
{
    char message[512];
    va_list ap;

    va_start(ap, fmt);
    vsnprintf(message, sizeof(message), fmt, ap);
    va_end(ap);

    SEXP cond = PROTECT(build_condition(message, code, NULL, path));
    signal_condition(cond); /* noreturn */
}
