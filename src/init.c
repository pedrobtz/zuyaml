#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

#include "cyaml.h"

/*
 * Report the version string compiled into the vendored cyaml sources.
 *
 * Internal, and deliberately the only native routine in M1. cyaml_internal.h
 * falls back to "0.0.0-dev" unless the build defines CYAML_VERSION_STR, which
 * upstream's CMake does and we do not use -- so src/Makevars must supply it.
 * The test in tests/testthat/test-vendor.R compares this against
 * inst/cyaml-VERSION, catching both a botched re-vendor and a dropped -D flag.
 */
static SEXP zuyaml_cyaml_version_(void)
{
    return Rf_mkString(cyaml_version());
}

static const R_CallMethodDef call_methods[] = {
    { "zuyaml_cyaml_version_", (DL_FUNC)&zuyaml_cyaml_version_, 0 },
    { NULL, NULL, 0 }
};

void attribute_visible R_init_zuyaml(DllInfo* dll)
{
    R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
