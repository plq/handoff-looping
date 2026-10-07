#include "greet.h"

#include <stdio.h>

size_t greet(const char *name, char *out, size_t n)
{
    int len = snprintf(out, n, "Hello, %s!", name);
    return len < 0 ? 0 : (size_t)len;
}
