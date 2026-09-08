#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

/*
 * Backstop for violated cyaml library invariants.
 *
 * Upstream's CYAML_ASSERT and CYAML_UNREACHABLE macros print to stderr and
 * call abort(). CRAN policy prohibits both, and abort() in an R package
 * terminates the user's whole session, unsaved work included. The vendored
 * header is patched to route both macros here instead
 * (tools/patches/0001-assertions-no-abort.patch).
 *
 * Rf_error() longjmps, so anything cyaml had allocated at the point of the
 * assertion leaks. That is accepted here and nowhere else: these macros fire
 * only when a library invariant is already broken -- a bug -- and leaking on
 * that path is far better than killing the session. Ordinary parse and emit
 * errors must NOT reach R this way; see the unwind safety section of
 * .agents/DESIGN-zuyaml.md.
 */
_Noreturn void zuyaml_panic(const char* msg, const char* cond,
    const char* file, int line)
{
    Rf_error("internal cyaml error: %s\n"
             "  failed: %s\n"
             "  at: %s:%d\n"
             "This is a bug in zuyaml or its vendored cyaml library. "
             "Please report it at https://github.com/pedrobtz/zuyaml/issues",
        msg ? msg : "(no message)",
        cond ? cond : "(no condition)",
        file ? file : "(unknown file)",
        line);
}
