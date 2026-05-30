/* libcompatshim.so — companion library bundled with libcompat.so on Linux.
 *
 * Provides definitions for glibc symbols that polyfill-glibc cannot rewrite
 * down to an older glibc baseline.  By redirecting libcompat.so to resolve
 * these symbols here (via --rename-dynamic-symbols), the package loads
 * cleanly on hosts whose system libc/libm are older than the build
 * toolchain's (e.g. pkg-build.racket-lang.org, whose glibc is < 2.27).
 *
 *   __libc_single_threaded  (glibc 2.32+, libc): a uint8_t hint the Rust std
 *       library reads.  We export a zero byte ("not known single-threaded"),
 *       which forces any caller to take the thread-safe path — always
 *       behaviorally correct.
 *
 *   getentropy              (glibc 2.25+, libc): a fallback entropy source.
 *       Rust's getrandom prefers the getrandom(2) syscall, so this symbol is
 *       not exercised at runtime; stub aborts if ever called.
 *
 *   strfromf128 / strtof128 (glibc 2.26+, libc): _Float128 <-> string.  Not
 *       referenced by a Rust cdylib, but stubbed defensively in case a
 *       dependency pulls them in.  Stubs abort if ever called.
 */

#include <stddef.h>
#include <stdlib.h>

__attribute__((visibility("default"))) const char __libc_single_threaded = 0;

__attribute__((visibility("default")))
int getentropy(void *buffer, size_t length) {
    (void)buffer; (void)length;
    abort();
}

__attribute__((visibility("default")))
int strfromf128(char *dest, size_t size, const char *format, long double f) {
    (void)dest; (void)size; (void)format; (void)f;
    abort();
}

__attribute__((visibility("default")))
long double strtof128(const char *nptr, char **endptr) {
    (void)nptr; (void)endptr;
    abort();
}
