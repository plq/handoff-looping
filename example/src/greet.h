#ifndef GREET_H
#define GREET_H

#include <stddef.h>

/* Writes "Hello, <name>!" into out, which holds n bytes. The output is
 * always NUL-terminated when n > 0 and truncated when the greeting does
 * not fit. Returns the length of the full greeting, as snprintf does, so
 * a caller can detect truncation. */
size_t greet(const char *name, char *out, size_t n);

#endif
