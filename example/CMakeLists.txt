cmake_minimum_required(VERSION 3.16)
project(greet C)

add_library(greet src/greet.c)
target_include_directories(greet PUBLIC src)

enable_testing()
add_executable(test_greet tests/test_greet.c)
target_link_libraries(test_greet PRIVATE greet)

# One ctest case per argv[1] of test_greet. Adding a case = a function and a
# dispatch line in tests/test_greet.c plus an add_test line here; the next
# `cmake --build` re-runs the configure step by itself.
add_test(NAME greet.basic COMMAND test_greet basic)
add_test(NAME greet.truncation COMMAND test_greet truncation)
