#include "zuyaml.h"

/*
 * Convert one cyaml node to an R object.
 *
 * Dispatch covers every member of cyaml_type_t. CYAML_NONE marks an
 * invalid/uninitialised node and should be unreachable from a successful
 * parse, but it must not fall through silently -- a new upstream node type
 * would otherwise be converted as whatever the default happened to be.
 *
 * Scalars, sequences and mappings arrive in the next slices of M2; aliases
 * in M3.
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
        zuyaml_stopf("not_implemented", NULL,
            "Scalar conversion is not implemented yet.");

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
