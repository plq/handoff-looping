#include "greet.h"

#include <stdio.h>
#include <string.h>

/* Each case is a function; main dispatches on argv[1]. CMakeLists.txt
 * registers one ctest case per name. */

static int fail(const char *what, const char *got)
{
    fprintf(stderr, "FAIL %s: got \"%s\"\n", what, got);
    return 1;
}

static int test_basic(void)
{
    char out[64];
    size_t len = greet("Ada", out, sizeof out);
    if (strcmp(out, "Hello, Ada!") != 0)
        return fail("basic text", out);
    if (len != strlen("Hello, Ada!"))
        return fail("basic length", out);
    return 0;
}

static int test_truncation(void)
{
    char out[8];
    size_t len = greet("Grace Hopper", out, sizeof out);
    if (strcmp(out, "Hello, ") != 0)
        return fail("truncated text", out);
    if (len != strlen("Hello, Grace Hopper!"))
        return fail("truncated length", out);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: test_greet <case>\n");
        return 2;
    }
    if (strcmp(argv[1], "basic") == 0)
        return test_basic();
    if (strcmp(argv[1], "truncation") == 0)
        return test_truncation();
    fprintf(stderr, "unknown case: %s\n", argv[1]);
    return 2;
}
